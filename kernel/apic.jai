
Interrupt_Controller_Structure :: struct {
    subtype: Subtype;
    length: u8;

    Subtype :: enum u8 {
        LOCAL_APIC                :: 0;
        IO_APIC                   :: 1;
        INTERRUPT_SOURCE_OVERRIDE :: 2;
        NON_MASKABLE_INTERRUPT    :: 4;
        LAPIC_ADDRESS_OVERRIDE    :: 5;
        LOCAL_X2APIC              :: 9;
    }
}

Ics_Local_Apic :: struct {
    using ics: Interrupt_Controller_Structure;

    acpi_processor_uid: u8;
    apic_id: u8;

    flags: enum_flags u32 {
        ENABLED           :: 0x1;
        ONLINE_CAPABLE    :: 0x2;
    }
}

Ics_Io_Apic :: struct {
    using ics: Interrupt_Controller_Structure;

    io_apic_id: u8;
    reserved: u8;
    address: u32;
    global_system_interrupt_base: u32;
}

Ics_Source_Override :: struct {
    using ics: Interrupt_Controller_Structure;

    bus: u8;
    source: u8;
    global_system_interrupt: u32;
    flags: u16;
}

Ics_Non_Maskable_Interrupt :: struct {
    using ics: Interrupt_Controller_Structure;

    processor_uid: u8;
    flags: u16 #align 1;
    lapic_lint: u8;
}



Apic_Register :: enum {
    APIC_ID                   :: 0x20;
    APIC_VERSION              :: 0x30;
    TPR__TASK_PRIORITY        :: 0x80;
    APR__ARBITRATION_PRIORITY :: 0x90;
    PPR__PROCESSOR_PRIORITY   :: 0xa0;
    EOI__END_OF_INTERRUPT     :: 0xb0;
    SPURIOUS_INTERRUPT        :: 0xf0;
    ICR__INTERRUPT_COMMAND    :: 0x300;
    DES__INTERRUPT_DEST       :: 0x310;
    LVT__TIMER                :: 0x320;
    TIC__TIMER_INITIAL        :: 0x380;
    TCC__TIMER_CURRENT        :: 0x390;
    DV__TIMER_DIVIDE          :: 0x3e0;
    EXTENDED_FEATURE          :: 0x400;
}

read_apic_register :: (register: Apic_Register) -> u32 #no_context {
    if global.apic == null {
        bluescreen();
    }

    return cast(*u32, global.apic + cast(u64) register).*;
}

write_apic_register :: (register: Apic_Register, value: u32) #no_context {
    if global.apic == null {
        bluescreen();
    }

    cast(*u32, global.apic + cast(u64) register).* = value;
}

initialize_apic :: () {

    // Disable the older interrupt controller. I sort of assume UEFI does this anyway.
    #asm {
        mov.8 ax: gpr === a, 0xff;
        out.8 0x21, ax;
        out.8 0xa1, ax;
    }
    
    Apic_Base_Flags :: enum_flags {
        BSC__boot_strap_core :: 1 << 8;
        EXTD__2xapic_mode    :: 1 << 10;
        AE__apic_enable      :: 1 << 11;
    }

    apic_base := cast(Apic_Base_Flags)read_msr(.APIC_BASE);
    assert(apic_base & .BSC__boot_strap_core > 0);

    apic_base |= .AE__apic_enable;
    write_msr(.APIC_BASE, cast(u64) apic_base);

    {
        physical := cast(u64) apic_base & ~0xfff;
        assert(0xfee0_0000 == physical);

        virtual := cast(*void) alloc_block(*global.virtual_block_allocator, 4096);
        map_pages(virtual, physical, 1, .READ_WRITE | .PRESENT | .CACHE_DISABLE);

        global.apic = virtual;
    }


    global.processor_cores.data = space_for_processor_cores.data;
    global.processor_cores.count = 1;

    bootstrap_core := *global.processor_cores[0];
    bootstrap_core.local_apic_id = read_apic_register(.APIC_ID) >> 24;

    init_processor_core();

    global.multiprocessing_initialized = true;

    #insert #run,host -> string {
        builder: String_Builder;
        for 0..31 {
            print(*builder, "register_interrupt_gate(isr__default_isa_fault_handler_%1, %1, true);\n", it);
        }
        return builder_to_string(*builder);
    };

    register_interrupt_gate(isr__debug_exception,          1,  true);
    register_interrupt_gate(isr__breakpoint_handler,       3,  true);
    register_interrupt_gate(isr__general_protection_fault, 13, true);
    register_interrupt_gate(isr__page_fault,               14, true, ist = 1);
    register_interrupt_gate(isr__floating_point_exception, 19, true);

    //
    // Iterate interrupt controller structures
    //

    table: uacpi_table;
    status := uacpi_table_find_by_signature(ACPI_MADT_SIGNATURE, *table);
    assert(status == .OK, "Could not find Multiple Apic Description Table.");

    madt_table := cast(*acpi_madt) table.hdr;

    cursor := cast(u64) (madt_table + 1);

    while cursor < cast(u64) madt_table + madt_table.hdr.length {

        ics := cast(*Interrupt_Controller_Structure) cursor;
        defer cursor += ics.length;

        if ics.subtype == {
          case .LOCAL_APIC;
            lapic_ics := cast(*Ics_Local_Apic) ics;

            if lapic_ics.apic_id == bootstrap_core.local_apic_id {
                continue;
            }

            // Apparently we should be able to use the ONLINE_CAPABLE bit in the ics flags to determine if
            // this processor core is usable, but for some reason it's always 0 in Qemu and Vbox.

            id := global.processor_cores.count;
            global.processor_cores.count += 1;

            new_core := *global.processor_cores[id];

            new_core.local_apic_id = lapic_ics.apic_id;
            new_core.id = id;

          case .IO_APIC;
            assert(global.io_apic == null);

            ioapic_ics := cast(*Ics_Io_Apic) ics;

            virtual := cast(*void) alloc_block(*global.virtual_block_allocator, 4096);
            map_pages(virtual, ioapic_ics.address, 1, .READ_WRITE | .PRESENT | .CACHE_DISABLE);

            global.io_apic = virtual;

            assert(ioapic_ics.address == 0xfec0_0000);

          case .INTERRUPT_SOURCE_OVERRIDE;

            iso := cast(*Ics_Source_Override) ics;
            // Todo
        }
    }

    uacpi_table_unref(*table);

    timer_gate := allocate_interrupt_gate();
    register_interrupt_gate(isr__scheduling_timer_interrupt, timer_gate);

    // Store this, to be able to configure the APIC timer (or TSC deadline) of all cores to use the same interrupt handler, which is done in core_begin_multitasking.
    global.scheduling_interrupt_gate = timer_gate;

    global.tasks.allocator = context.allocator;
    global.next_task_id = 1;
}

startup_application_processors :: () {

    // Load the 16 bit AP initialization routine from static memory
    memcpy(cast(*void) 0x8000 + DIRECT_MAPPING_BASE, ap_startup_bin.data, 4096);

    Ap_Startup_Data :: struct {
        // Layout matches the ap_startup assembly code.
        stack: *void;
        entry_point: *void;
        pml4: *u64;
    }

    ap_startup_data := cast(*Ap_Startup_Data) (0x8200 + DIRECT_MAPPING_BASE);
    ap_startup_data.entry_point = cast(*void) ap_entry_point;
    ap_startup_data.pml4 = global.boot_data.page_tables.pml4.data;

    for* global.processor_cores {
        if it_index == 0 {
            // This is the bootstrap processor.
            continue;
        }

        // This lock is to ensure that APs have time to copy their stack's base address into their stack register before the next AP is started up.
        // Maybe if processors could use their APIC ID to find their stack memory it would be faster.
        // Todo: Maybe this needs a timeout in case a core fails to start.
        acquire(*ap_startup_spinlock);

        ap_startup_data.stack = alloc(0x8_0000) + 0x8_0000;

        write_apic_register(.DES__INTERRUPT_DEST, it.local_apic_id << 24);

        // Todo: People online are saying these sometimes need to be executed multiple times per core.
        // Todo: Magic numbers
        command: u32;
        command = (0b101 << 8) | (1 << 14); // INIT IPI
        write_apic_register(.ICR__INTERRUPT_COMMAND, command);

        command = (0b110 << 8) | 8; // STARTUP IPI
        write_apic_register(.ICR__INTERRUPT_COMMAND, command);
    }
}

ap_startup_bin :: #run,host -> [] u8 {
    #import "Compiler";
    #import "File";

    code := read_entire_file(".build/ap_startup.bin");
    return add_global_data(cast([] u8) code, .WRITABLE);
}

ap_startup_spinlock: Spinlock(lock_type = .RAW);

ap_entry_point :: () #c_call {
    set_stack_trace_sentinel();

    release(*ap_startup_spinlock);

    push_context {
        // This thread doesn't have temporary storage, but it barely needs it so we let it go to the default allocator (physical_block_allocator).

        init_processor_core();

        core_begin_multitasking();

        assert(cpu_local_read("irq_disable_count") == 0);
        #asm { sti; }

        cpu_idle_loop();
    }
}

get_current_core :: inline () -> *X64_Core #no_context {
    core: *X64_Core;

    #asm FSGSBASE {
        rdgsbase core;
    }

    return core;
}

get_core_id :: () -> int #no_context {
    return cpu_local_read("id");
}

get_task_id :: () -> int #no_context {
    if !global.multiprocessing_initialized {
        return 0;
    }

    core := get_current_core();

    if !core.online {
        return 0;
    }

    task := get_current_task();
    return task.id;
}



cpu_local_read :: inline ($field_name: string) -> s64 #no_context {
    offset := inline offset_of(X64_Core, field_name);

    gs_relative_read :: (offset: int) -> s64 #foreign Assembly;
    return gs_relative_read(offset);
}

cpu_local_write :: inline ($field_name: string, value: s64) #no_context {
    offset := inline offset_of(X64_Core, field_name);

    gs_relative_write :: (offset: int, value: s64) #foreign Assembly;
    gs_relative_write(offset, s64);
}

cpu_local_increment :: inline ($field_name: string) #no_context {
    offset := inline offset_of(X64_Core, field_name);

    gs_relative_inc :: (offset: int) #foreign Assembly;
    gs_relative_inc(offset);
}

cpu_local_decrement :: inline ($field_name: string) #no_context {
    offset := inline offset_of(X64_Core, field_name);

    gs_relative_dec :: (offset: int) #foreign Assembly;
    gs_relative_dec(offset);
}



ioapic_add_interrupt_redirection_table_entry :: (redirection_index: u32, entry: u64) {
    REDIRECTION_TABLE_BASE       : u32 : 0x10;
    REDIRECTION_TABLE_ENTRY_SIZE : u32 : 0x2;

    register_index := REDIRECTION_TABLE_BASE + redirection_index * REDIRECTION_TABLE_ENTRY_SIZE;

    global.io_apic[0] = register_index;
    global.io_apic[4] = cast(u32) entry;

    global.io_apic[0] = register_index+1;
    global.io_apic[4] = 0;
}



#insert #run,host -> string {
    Isa_Exception_Definition :: struct {
        name: string;
        error_code: bool;
    }

    // Todo: Many of these don't happen in 64-bit mode anyway.
    exceptions :: Isa_Exception_Definition.[
        { "Division Error",                    false },
        { "Debug",                             false },
        { "Non-maskable Interrupt",            false },
        { "Breakpoint",                        false },
        { "Overflow",                          false },
        { "Bound Range Exceeded",              false },
        { "Invalid Opcode",                    false },
        { "Device Not Available",              false },
        { "Double Fault",                      true  },
        { "Coprocessor Segment Overrun",       false },
        { "Invalid TSS",                       true  },
        { "Segment Not Present",               true  },
        { "Stack-Segment Fault",               true  },
        { "General Protection Fault",          true  },
        { "Page Fault",                        true  },
        { "Reserved",                          false },
        { "x87 Floating-Point Exception",      false },
        { "Alignment Check",                   true  },
        { "Machine Check",                     false },
        { "SIMD Floating-Point Exception",     false },
        { "Virtualization Exception",          false },
        { "Control Protection Exception",      true  },
        { "", false }, { "", false }, { "", false }, { "", false }, { "", false }, { "", false },
        { "Reserved",                          false },
        { "Hypervisor Injection Exception",    false },
        { "VMM Communication Exception",       true  },
        { "Security Exception",                true  },
    ];

    builder: String_Builder;

    for exceptions {
        print(*builder, DEFAULT_ISA_FAULT_HANDLER, it_index, it.error_code, ifx it.error_code "WithErrorCode", it.name);
        append(*builder, "\n");
    }

    return builder_to_string(*builder);
};

DEFAULT_ISA_FAULT_HANDLER :: #string,\% END
#program_export
default_isa_fault_handler_%1 :: (stack: *Interrupt_Stack_Frame(%2)) #c_call {
    push_context,defer_pop;
    push_print_style().base = 16;

    b: String_Builder;

    core := get_current_core();

    print(*b, "\nAn ISA exception (%4) occurred.\n");
    print(*b, "Core ID \%, running thread '\%'.\n", core.id, core.scheduler.current_task.name);
    print(*b, "\n");

    print(*b, "CPU Context:\n");
    print(*b, "    RIP: 0x\%\n", stack.ip);
    print(*b, "    RSP: 0x\%\n", stack.sp);
    print(*b, "    CS: \%\n", stack.cs);
    print(*b, "\n");

    buffer: [32] u32;
    do_stack_trace(buffer);

    print(*b, "Stack Trace:\n");
    append_formatted_stack_trace(*b, buffer);

    write_builder(*b);

    bluescreen();
} @InterruptRoutine%3
END;

#program_export
debug_exception :: (stack: *Interrupt_Stack_Frame()) #c_call {
    push_context {

        core := get_current_core();
        task := core.scheduler.current_task;

        print("Debug exception on core %, running thread \"%\"\n", core.id, task.name);

        print("RIP: 0x%\n", stack.ip);
        print("RSP: 0x%\n", stack.sp);
        print("SS: %\n", stack.ss);
        print("CS: %\n", stack.cs);

        DR6 :: enum_flags u64 {
            BREAKPOINT_0_HIT     :: 0x1;
            BREAKPOINT_1_HIT     :: 0x2;
            BREAKPOINT_2_HIT     :: 0x4;
            BREAKPOINT_3_HIT     :: 0x8;

            DR_ACCESS            :: 1 << 13;
            SINGLE_STEP          :: 1 << 14;
            HARDWARE_TASK_SWITCH :: 1 << 15;
            OUTSIDE_RTM_REGION   :: 1 << 16;
        }

        dr6: DR6;
        #asm { get_dr6 dr6; }
        stack_dr6 := dr6;
        print("DR6 flags: %\n", stack_dr6);

        bluescreen();
    }
} @InterruptRoutine

#program_export
breakpoint_handler :: (stack: *Interrupt_Stack_Frame(false)) #c_call {
    push_context,defer_pop;

    b: String_Builder;

    {
        ps := push_print_style();
        ps.use_long_form_if_more_than_this_many_members = 0;
        ps.use_newlines_if_long_form = true;
        ps.base = 16;

        print(*b, "\nBreakpoint hit. Context:\n%\n\n", stack.*);
    }

    buffer: [32] u32;
    do_stack_trace(buffer);

    append_formatted_stack_trace(*b, buffer);

    write_builder(*b);

    bluescreen();
} @InterruptRoutine

#program_export
page_fault :: (stack: *Interrupt_Stack_Frame(true)) #c_call {
    push_context,defer_pop;

    core := get_current_core();
    task := core.scheduler.current_task;

    b: String_Builder;

    print(*b, "\nPage Fault (On core %, running thread \"%\")\n", core.id, task.name);

    _cr2: u64;
    #asm { get_cr2 _cr2; }
    cr2 := _cr2;

    {
        push_print_style().base = 16;

        print(*b, "Virtual Address: 0x%\n", cr2);

        Flags :: enum_flags u32 {
            PRESENT;
            WRITE;
            USER;
            RESERVED_WRITE;
            INSTRUCTION_FETCH;
            PROTECTION_KEY;
            SHADOW_STACK;
        }
        flags := cast(Flags)stack.error_code;
        print(*b, "Error flags: %\n\n", flags);

        print(*b, "RIP: 0x%\n", stack.ip);
        print(*b, "RSP: 0x%\n", stack.sp);
        print(*b, "SS: %\n", stack.ss);
        print(*b, "CS: %\n", stack.cs);

        print(*b, "\n");
    }


    buffer: [32] u32;
    do_stack_trace(buffer, cast(*void) stack.rbp);

    append_formatted_stack_trace(*b, buffer);

    write_builder(*b);


    acquire(*global.guarded_memory.spinlock);

    g := find_guarded_memory(cast(*void) cr2);
    if g {
        print(*b, "\nThis was a guarded allocation requested at %:%.\n",
              g.created_at.fully_pathed_filename,
              g.created_at.line_number);
    }

    release(*global.guarded_memory.spinlock);

    write_builder(*b);

    bluescreen();
} @InterruptRoutineWithErrorCode

#program_export
general_protection_fault :: (stack: *Interrupt_Stack_Frame(with_error_code = true)) #c_call {
    push_context {

        core := get_current_core();
        task := core.scheduler.current_task;

        b: String_Builder;

        print(*b, "\nGeneral Protection Fault    (On core %, running thread \"%\")\n", core.id, task.name);

        ps := push_print_style();
        ps.base = 16;

        print(*b, "RIP: 0x%\n", stack.ip);
        print(*b, "RSP: 0x%\n", stack.sp);
        print(*b, "SS: %\n", stack.ss);
        print(*b, "CS: %\n", stack.cs);

        Selector_Error_Code :: enum u32 {
            external              :: 1;
            descriptor_table_kind :: 2;
            selector_index        :: 13;
            reserved              :: 16;
        } @Bitfield

        table_names :: string.["GDT", "IDT", "LDT", "IDT"];

        selector_error := cast(Selector_Error_Code) stack.error_code;

        is_external := cast(bool) bitfield_get(selector_error, .external);
        table       :=            bitfield_get(selector_error, .descriptor_table_kind);
        index       :=            bitfield_get(selector_error, .selector_index);

        print(*b, "Error code: external=%, table=%, index=% (0x%)\n", is_external, table_names[table], formatInt(index, base=10), index);

        buffer: [32] u32;
        do_stack_trace(buffer);

        ps.base = 10;
        append_formatted_stack_trace(*b, buffer);

        write_builder(*b);

        bluescreen();
    }
} @InterruptRoutineWithErrorCode

#program_export
floating_point_exception :: (stack: *Interrupt_Stack_Frame()) #c_call {
    mxcsr: Mxcsr;
    pmxcsr := *mxcsr;

    #asm {
        stmxcsr [pmxcsr];
    }

    push_context {
        core := get_current_core();
        log("Floating point exception: % (thread %)", mxcsr, core.scheduler.current_task.id);
    }
} @InterruptRoutine



initialize_uacpi :: () {

    init_uacpi_interrupt_handlers();

    if uacpi_initialize(0) != .OK bluescreen();
    if uacpi_namespace_load() != .OK bluescreen();
    if uacpi_namespace_initialize() != .OK bluescreen();

    uacpi_set_interrupt_model(.IOAPIC);

    uacpi_install_fixed_event_handler(.POWER_BUTTON, (ctx: uacpi_handle) -> uacpi_interrupt_ret #c_call {
        write_string("Turning off the PC...\n");

        uacpi_prepare_for_sleep_state(.S5);
        uacpi_enter_sleep_state(.S5);

        write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);

        return UACPI_INTERRUPT_HANDLED;
    }, null);

    if uacpi_finalize_gpe_initialization() != .OK bluescreen();

    uacpi := *global.uacpi_state;
    uacpi.work_thread = create_task(uacpi.work_thread_proc, name="uACPI Worker");

    // According to uACPI kernel_api.h, work items should be done on CPU0 due to firmware bugs.
    cpu0 := *global.processor_cores[0];
    put_task_on_core(uacpi.work_thread, cpu0);

    find_routing_table_under_bridge :: (user: *void, node: *uacpi_namespace_node, depth: u32) -> uacpi_iteration_decision #c_call {
        node_info: *uacpi_namespace_node_info;
        uacpi_get_namespace_node_info(node, *node_info);

        routing: *uacpi_pci_routing_table;
        uacpi_get_pci_routing_table(node, *routing);

        entries := cast(*uacpi_pci_routing_table_entry) (routing + 1);

        global.pci_routing_table.count = cast(s64) routing.num_entries;
        global.pci_routing_table.data = entries;

        return .BREAK;
    }

    uacpi_find_devices("PNP0A03", find_routing_table_under_bridge, null);

    if global.pci_routing_table.data == null {
        uacpi_find_devices("PNP0A08", find_routing_table_under_bridge, null);
    }

    assert(global.pci_routing_table.data != null);
}

//
// Implement the uACPI kernel API callbacks
//

uACPI_State :: struct {
    first_irq_handler_gate_index: int;

    irq_contexts: [8] struct {
        handler: uacpi_interrupt_handler;
        ctx: uacpi_handle;
    };
    irq_contexts_used: int;
    irq_handlers_in_flight: int;

    Work_Item :: struct {
        type:    uacpi_work_type;
        handler: uacpi_work_handler;
        ctx:     uacpi_handle;

        queue_node: List_Node(#this);
    }

    // Todo: Should way simplify how this synchronization is done.

    work_queue: List_Node(Work_Item);
    work_queue_lock: Spinlock(.IRQ);
    work_thread: *Task_Info;
    work_in_progress: bool;

    work_added:     Semaphore;
    work_completed: Condition_Variable;

    work_thread_proc :: () {
        using global.uacpi_state;

        log_category("uACPI");

        list_init(*work_queue);

        while true {
            wait_for(*work_added);

            acquire(*work_queue_lock);

            item := list_pop(*work_queue);
            work_in_progress = true;

            release(*work_queue_lock);

            log("Beginning work item.");
            item.handler(item.ctx);
            log("Work item completed.");

            acquire(*work_queue_lock);

            free_small_object(item);

            work_in_progress = false;
            if is_empty(*work_queue) {
                notify_all(*work_completed);
            }

            release(*work_queue_lock);
        }
    }

    memory_pool: Pool;
}

#import "Pool";
#import "uACPI";

#program_export
uacpi_kernel_get_rsdp :: (rsdp_address: *uacpi_phys_addr) -> uacpi_status #c_call {
    rsdp_address.* = cast(uacpi_phys_addr) global.acpi_rsdp - DIRECT_MAPPING_BASE;
    return .OK;
}

#program_export
uacpi_kernel_io_map :: (base: uacpi_io_addr, len: uacpi_size, out_handle: *uacpi_handle) -> uacpi_status #c_call {
    using global.uacpi_state;

    out_handle.* = xx base;

    return .OK;
}

#program_export
uacpi_kernel_io_unmap :: () #c_call {
    // Nothing to do.
}

#program_export
uacpi_kernel_map :: (addr: uacpi_phys_addr, len: uacpi_size) -> *void #c_call {
    push_context {
        memory := cast(*void) alloc_block(*global.virtual_block_allocator, cast(u64) len);
 
        pages_needed := cast(s64) (len / 4096);
        if len % 4096 pages_needed += 1;

        page_flags := Page_Flags.READ_WRITE | .PRESENT | .CACHE_DISABLE;

        map_pages(memory, addr, pages_needed, page_flags);

        return memory;
    }
}

#program_export
uacpi_kernel_unmap :: (addr: *void, len: uacpi_size) #c_call {
    return;
}

#program_export
uacpi_kernel_alloc :: (size: uacpi_size) -> *void #c_call {
    // Todo: uACPI wants to allocate a large number of tiny, equally sized blocks separately using a general purpose allocator, which is always going to be wasteful. For now it just gets a pool/arena to avoid spamming the block allocator.

    push_context {
        return get(*global.uacpi_state.memory_pool, cast(s64)size);
    }
}

#program_export
uacpi_kernel_free :: (mem: *void) #c_call {
    // Do nothing, uACPI memory is pooled for now.
}

#program_export
uacpi_kernel_log :: (log_level: uacpi_log_level, c_string: *uacpi_char) #c_call {
    push_context {
        log_category("uACPI");

        data := c_string;
        count := c_style_strlen(c_string);

        if data[0] >= #char "a" && data[0] <= #char "z" {
            data[0] -= #char "a" - #char "A";
        }

        if (data[count-1] == #char "\n") && (data[count-2] != #char ".") {
            data[count-1] = #char ".";
        }

        log(.{count, data});
    }
}

#program_export uacpi_kernel_get_nanoseconds_since_boot :: () -> u64 #c_call {
    push_context {
        return cast(u64) to_nanoseconds(get_kernel_timestamp());
    }
}

#program_export uacpi_kernel_stall :: (usec: uacpi_u8) #c_call {
    push_context { busy_wait(usec); }    
}

#program_export uacpi_kernel_sleep :: (msec: uacpi_u64) #c_call {
    push_context { sleep(cast(s64)msec, .milliseconds); }
}



#program_export uacpi_kernel_create_mutex :: () -> uacpi_handle #c_call {
    push_context {
        return New(Mutex,, global.small_objects);
    }
}

#program_export uacpi_kernel_free_mutex :: (handle: uacpi_handle) #c_call {
    push_context {
        free(handle,, global.small_objects);
    }
}

#program_export uacpi_kernel_create_event :: () -> uacpi_handle #c_call {
    push_context {
        return New(Semaphore,, global.small_objects);
    }
}

#program_export uacpi_kernel_free_event :: (handle: uacpi_handle) #c_call {
    push_context {
        free(handle,, global.small_objects);
    }
}

#program_export uacpi_kernel_get_thread_id :: () -> uacpi_thread_id #c_call {
    task := get_current_task();
    return xx task.id;
}

#program_export uacpi_kernel_acquire_mutex :: (handle: uacpi_handle, timeout: uacpi_u16) -> uacpi_status #c_call {
    push_context {
        mut := cast(*Mutex)handle;

        if timeout == 0 {
            success := trylock(mut);
            return ifx success then .OK else .TIMEOUT;
        }

        acquire(mut); // Todo: Timeout.
        return .OK;
    }
}

#program_export uacpi_kernel_release_mutex :: (handle: uacpi_handle) #c_call {
    push_context {    
        release(cast(*Mutex)handle);
    }
}

#program_export uacpi_kernel_wait_for_event :: (handle: uacpi_handle, timeout: uacpi_u16) -> uacpi_status #c_call {
    push_context {
        sem := cast(*Semaphore)handle;

        // Convert from uACPI timeout format to Apollo_Time.

        if timeout == 0 {
            success := try_wait(sem);
            return ifx success then .OK else .TIMEOUT;
        }

        timeout_apollo: Apollo_Time;
        if timeout == 0xFFFF {
            timeout_apollo = INFINITE_TIMEOUT;
        } else {
            timeout_apollo = milliseconds_to_apollo(timeout);
        }

        success := wait_for(sem, timeout_apollo);
        return ifx success then .OK else .TIMEOUT;
    }
}

#program_export uacpi_kernel_signal_event :: (handle: uacpi_handle) #c_call {
    push_context {
        sem := cast(*Semaphore)handle;
        signal(sem);
    }    
}

#program_export uacpi_kernel_reset_event :: (handle: uacpi_handle) #c_call {
    push_context {
        sem := cast(*Semaphore)handle;
        sem.counter = 0;
    }    
}

#program_export uacpi_kernel_handle_firmware_request :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_handle_firmware_request\"\n");
    bluescreen();
}

UACPI_IRQ_HANDLER :: #string END
#program_export
handle_uacpi_irq_%1 :: (stack: *void) #c_call {
    using global.uacpi_state;
    irq := *irq_contexts[%1];

    irq_handlers_in_flight += 1;
    irq.handler(irq.ctx);
    irq_handlers_in_flight -= 1;

    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);
} @InterruptRoutine
END;

#insert #run,host -> string {
    builder: String_Builder;
    for 0..7 {
        print(*builder, UACPI_IRQ_HANDLER, it);
        print(*builder, "\n");
    }
    return builder_to_string(*builder);
};

init_uacpi_interrupt_handlers :: () {
    using global.uacpi_state;

    first_irq_handler_gate_index = global.next_free_interrupt_gate;
    global.next_free_interrupt_gate += irq_contexts.count;

    #insert #run,host -> string {
        builder: String_Builder;
        for 0..7 {
            print(*builder, "register_interrupt_gate(isr__handle_uacpi_irq_%1, first_irq_handler_gate_index + %1);\n", it);
        }
        return builder_to_string(*builder);
    };
}

#program_export
uacpi_kernel_install_interrupt_handler :: (irq: u32, handler: uacpi_interrupt_handler, ctx: uacpi_handle, out_irq_handle: *uacpi_handle) -> uacpi_status #c_call {
    using global.uacpi_state;

    push_context {
        if irq_contexts_used >= irq_contexts.count {
            log_error("Must allocate more IRQ handlers for uACPI.");
            bluescreen();
        }

        new_irq := *irq_contexts[irq_contexts_used];

        new_irq.handler = handler;
        new_irq.ctx     = ctx;

        gate := first_irq_handler_gate_index + irq_contexts_used;
        ioapic_add_interrupt_redirection_table_entry(irq, cast(u64)gate);

        irq_contexts_used += 1;

        return .OK;
    }
}

#program_export uacpi_kernel_uninstall_interrupt_handler :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_uninstall_interrupt_handler\"\n");
    bluescreen();
}

#program_export
uacpi_kernel_create_spinlock :: () -> uacpi_handle #c_call {
    push_context {
        return New(Spinlock(.IRQ),, global.small_objects);
    }
}

#program_export
uacpi_kernel_free_spinlock :: (handle: uacpi_handle) #c_call {
    push_context {
        free(handle,, global.small_objects);
    }
}

#program_export
uacpi_kernel_lock_spinlock :: (handle: uacpi_handle) -> uacpi_cpu_flags #c_call {
    lock := cast(*Spinlock(.IRQ))handle;
    acquire(lock);

    return 0;
}

#program_export
uacpi_kernel_unlock_spinlock :: (handle: uacpi_handle, flags: uacpi_cpu_flags) #c_call {
    lock := cast(*Spinlock(.IRQ))handle;
    release(lock);
}

#program_export
uacpi_kernel_schedule_work :: (type: uacpi_work_type, handler: uacpi_work_handler, ctx: uacpi_handle) -> uacpi_status #c_call {
    using global.uacpi_state;

    push_context {
        item := New(Work_Item,, global.small_objects); // Todo: Allocation in interrupt handler.
        item.type = type;
        item.handler = handler;
        item.ctx = ctx;

        acquire(*work_queue_lock);
        list_append(*work_queue, *item.queue_node);
        release(*work_queue_lock);

        signal(*work_added);
    }

    return .OK;
}

#program_export
uacpi_kernel_wait_for_work_completion :: () #c_call {
    using global.uacpi_state;

    push_context {
        while irq_handlers_in_flight > 0 {
            sleep(1, .milliseconds);
        }

        acquire(*work_queue_lock);

        predicate :: #code is_empty(*work_queue) && !work_in_progress;
        wait_for(*work_completed, *work_queue_lock, predicate);

        release(*work_queue_lock);
    }
}


do_uacpi_kernel_io_read :: inline (device: uacpi_handle, offset: uacpi_size, value: *$T) -> uacpi_status #c_call {
    #asm {
        mov address: gpr === d, device;
        add address, offset;

        in?T result: gpr === a, address;
        mov [value], result;
    }
    return .OK;
}

#program_export
uacpi_kernel_io_read8 :: (device: uacpi_handle, offset: uacpi_size, value: *u8) -> uacpi_status #c_call {
    return do_uacpi_kernel_io_read(device, offset, value);
}

#program_export
uacpi_kernel_io_read16 :: (device: uacpi_handle, offset: uacpi_size, value: *u16) -> uacpi_status #c_call {
    return do_uacpi_kernel_io_read(device, offset, value);
}

#program_export
uacpi_kernel_io_read32 :: (device: uacpi_handle, offset: uacpi_size, value: *u32) -> uacpi_status #c_call {
    return do_uacpi_kernel_io_read(device, offset, value);
}



do_uacpi_kernel_io_write :: inline (device: uacpi_handle, offset: uacpi_size, value: $T) -> uacpi_status #c_call {
    #asm {
        mov address: gpr === d, device;
        add address, offset;

        value === a;
        out?T address, value;
    }
    return .OK;
}

#program_export
uacpi_kernel_io_write8 :: (device: uacpi_handle, offset: uacpi_size, value: u8) -> uacpi_status #c_call {
    return do_uacpi_kernel_io_write(device, offset, value);
}

#program_export
uacpi_kernel_io_write16 :: (device: uacpi_handle, offset: uacpi_size, value: u16) -> uacpi_status #c_call {
    return do_uacpi_kernel_io_write(device, offset, value);
}

#program_export
uacpi_kernel_io_write32 :: (device: uacpi_handle, offset: uacpi_size, value: u32) -> uacpi_status #c_call {
    return do_uacpi_kernel_io_write(device, offset, value);
}



do_uacpi_kernel_pci_read :: (handle: uacpi_handle, offset: uacpi_size, value: *$T) -> uacpi_status #c_call {
    using cast(*uacpi_pci_address) *handle;

    for global.pci_ecam {
        if it.segment_group != segment continue;

        device_offset := cast(u64) (bus * 256 + device * 8 + function);
        address := it.base_address + device_offset * PCI_CONFIGURATION_SPACE_SIZE;

        // Todo: We need to handle unaligned accesses here.
        if address & 0b11 bluescreen();

        // Todo: This address is not necessarily covered by the direct mapping. The same issue exists in the rest of the PCI configuration space access code.
        address += DIRECT_MAPPING_BASE + offset;

        value.* = (.*) cast(*T) address;
        return .OK;
    }

    bluescreen();
    return .INVALID_ARGUMENT;
}

#program_export
uacpi_kernel_pci_read8 :: (handle: uacpi_handle, offset: uacpi_size, value: *u8) -> uacpi_status #c_call {
    return do_uacpi_kernel_pci_read(handle, offset, value);
}

#program_export
uacpi_kernel_pci_read16 :: (handle: uacpi_handle, offset: uacpi_size, value: *u16) -> uacpi_status #c_call {
    return do_uacpi_kernel_pci_read(handle, offset, value);
}

#program_export
uacpi_kernel_pci_read32 :: (handle: uacpi_handle, offset: uacpi_size, value: *u32) -> uacpi_status #c_call {
    return do_uacpi_kernel_pci_read(handle, offset, value);
}



do_uacpi_kernel_pci_write :: (handle: uacpi_handle, offset: uacpi_size, value: $T) -> uacpi_status #c_call {
    using cast(*uacpi_pci_address) *handle;

    for global.pci_ecam {
        if it.segment_group != segment continue;

        device_offset := cast(u64) (bus * 256 + device * 8 + function);
        address := it.base_address + device_offset * PCI_CONFIGURATION_SPACE_SIZE;

        // Todo: We need to handle unaligned accesses here.
        if address & 0b11 bluescreen();

        // Todo: This address is not necessarily covered by the direct mapping. The same issue exists in the rest of the PCI configuration space access code.
        address += DIRECT_MAPPING_BASE + offset;

        (.*) cast(*T) address = value;
        return .OK;
    }

    bluescreen();
    return .INVALID_ARGUMENT;
}

#program_export
uacpi_kernel_pci_write8 :: (handle: uacpi_handle, offset: uacpi_size, value: u8) -> uacpi_status #c_call {
    return do_uacpi_kernel_pci_write(handle, offset, value);
}

#program_export
uacpi_kernel_pci_write16 :: (handle: uacpi_handle, offset: uacpi_size, value: u16) -> uacpi_status #c_call {
    return do_uacpi_kernel_pci_write(handle, offset, value);
}

#program_export
uacpi_kernel_pci_write32 :: (handle: uacpi_handle, offset: uacpi_size, value: u32) -> uacpi_status #c_call {
    return do_uacpi_kernel_pci_write(handle, offset, value);
}

#program_export
uacpi_kernel_pci_device_open :: (address: uacpi_pci_address, out_handle: *uacpi_handle) -> uacpi_status #c_call {
    #assert size_of(uacpi_pci_address) <= size_of(uacpi_handle);
    (.*) cast(*uacpi_pci_address) out_handle = address;
    return .OK;
}

#program_export
uacpi_kernel_pci_device_close :: (handle: uacpi_handle) #c_call {
    // Nothing to do.
}

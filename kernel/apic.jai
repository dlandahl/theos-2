
Acpi_Madt :: struct {
    using #as header: Acpi_Table_Header;

    local_apic_address: u32;
    flags: u32;
}

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
    };
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

    acpi_header := cast(*Acpi_Madt) find_acpi_table("APIC");

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

        virtual := alloc_block(*global.virtual_block_allocator, 4096);
        map_page(virtual, physical, .READ_WRITE | .PRESENT | .CACHE_DISABLE);

        global.apic = cast(*void) virtual;
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
    register_interrupt_gate(isr__page_fault,               14, true);
    register_interrupt_gate(isr__floating_point_exception, 19, true);

    //
    // Iterate interrupt controller structures
    //

    cursor := cast(u64) acpi_header + size_of(Acpi_Madt);

    while cursor < cast(u64) acpi_header + acpi_header.length {

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

            virtual := alloc_block(*global.virtual_block_allocator, 4096);
            map_page(virtual, ioapic_ics.address, .READ_WRITE | .PRESENT | .CACHE_DISABLE);

            global.io_apic = cast(*u32) virtual;

            assert(ioapic_ics.address == 0xfec0_0000);

          case .INTERRUPT_SOURCE_OVERRIDE;

            iso := cast(*Ics_Source_Override) ics;
            // Todo
        }
    }

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

    bsp := get_current_core();

    for* global.processor_cores {
        if it == bsp {
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

    release(*ap_startup_spinlock);

    push_context {
        init_processor_core();

        core_begin_multitasking();

        #asm { sti; }

        while true {
            schedule_tasks();
            #asm { sti; hlt; }
        }
    }
}

get_current_core :: inline () -> *X64_Core #no_context {
    core: *X64_Core;

    #asm FSGSBASE {
        rdgsbase core;
    }

    return core;
}

gs_relative_read  :: (offset: int) -> u64 #foreign Assembly;
gs_relative_write :: (offset: int) -> u64 #foreign Assembly;
gs_relative_inc   :: (offset: int) -> u64 #foreign Assembly;
gs_relative_dec   :: (offset: int) -> u64 #foreign Assembly;



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
    builder: String_Builder;
    for 0..31 {
        print(*builder, DEFAULT_ISA_FAULT_HANDLER, it);
        print(*builder, "\n");
    }
    return builder_to_string(*builder);
};

DEFAULT_ISA_FAULT_HANDLER :: #string END
#program_export
default_isa_fault_handler_%1 :: (stack: *void) #c_call {
    core := get_current_core();
    Scoped_Acquire(*global.text_output_spinlock);

    write_string("Something bad happened (%1) on core ");
    write_number(core.id);
    write_string(" running thread ");
    write_string(core.scheduler.current_task.name);
    write_string("\n");

    bluescreen();
} @InterruptRoutine
END;

#program_export
debug_exception :: (stack: *Interrupt_Stack_Frame()) #c_call {
    push_context {

        Scoped_Acquire(*global.text_output_spinlock);

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
    push_context {
        context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 0;
        context.print_style.default_format_struct.use_newlines_if_long_form = true;
        context.print_style.default_format_int.base = 16;

        Scoped_Acquire(*global.text_output_spinlock);

        print("\nBreakpoint hit. Context:\n%", stack.*);
    }

    bluescreen();
} @InterruptRoutine

#program_export
page_fault :: (stack: *Interrupt_Stack_Frame(true)) #c_call {
    push_context,defer_pop;

    Scoped_Acquire(*global.text_output_spinlock);

    core := get_current_core();
    task := core.scheduler.current_task;

    print("\nPage Fault (On core %, running thread \"%\")\n", core.id, task.name);

    _cr2: u64;
    #asm { get_cr2 _cr2; }
    cr2 := _cr2;

    push_print_style().default_format_int.base = 16;
    print("Virtual Address: 0x%\n", cr2);

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
    print("Error flags: %\n\n", flags);

    print("RIP: 0x%\n", stack.ip);
    print("RSP: 0x%\n", stack.sp);
    print("SS: %\n", stack.ss);
    print("CS: %\n", stack.cs);

    bluescreen();

} @InterruptRoutineWithErrorCode

#program_export
general_protection_fault :: (stack: *Interrupt_Stack_Frame(with_error_code = true)) #c_call {
    push_context {
        Scoped_Acquire(*global.text_output_spinlock);

        core := get_current_core();
        task := core.scheduler.current_task;

        print("\nGeneral Protection Fault    (On core %, running thread \"%\")\n", core.id, task.name);

        push_print_style().default_format_int.base = 16;
        print("RIP: 0x%\n", stack.ip);
        print("RSP: 0x%\n", stack.sp);
        print("SS: %\n", stack.ss);
        print("CS: %\n", stack.cs);

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

        print("Error code: external=%, table=%, index=% (0x%)\n", is_external, table_names[table], formatInt(index, base=10), index);
        bluescreen();
    }
} @InterruptRoutineWithErrorCode



initialize_uacpi :: () {

    // Initializing PCI requires uACPI to get the PCI routing table, so this code needs to run first. But uACPI wants to access PCI devices while initializing, so they already need to be discoverable. Therefore this code is here for now, even though it doesn't really fit, I don't really want to make a separate function for it or have it in the entry point.

    mcfg := cast(*Acpi_Mcfg) find_acpi_table("MCFG");
    if !mcfg {
        log_error("ACPI MCFG table not found.");
        bluescreen();
    }

    ecam_length_bytes := mcfg.length - size_of(Acpi_Mcfg);

    ecam: [] Ecam_Entry;
    ecam.data = cast(*Ecam_Entry, mcfg + 1);
    ecam.count = ecam_length_bytes / size_of(Ecam_Entry);

    global.pci_ecam = ecam;


    // uACPI uses thread local storage.
    tls := get_4k_page() + DIRECT_MAPPING_BASE;
    #asm FSGSBASE { wrfsbase tls; }


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

    // Note: according to uACPI kernel_api.h, work items should be done on CPU0 due to firmware bugs.
    cpu0 := *global.processor_cores[0];
    put_task_on_core(uacpi.work_thread, cpu0);
}

//
// Implement the uACPI kernel API callbacks
//

Uacpi_State :: struct {
    first_irq_handler_gate_index: int;

    irq_contexts: [8] struct {
        handler: uacpi_interrupt_handler;
        ctx: uacpi_handle;
    };
    irq_contexts_used: int;

    Work_Item :: struct {
        type: uacpi_work_type;
        handler: uacpi_work_handler;
        ctx: uacpi_handle;
    }

    work_queue: Queue(Work_Item);
    work_queue_lock: Spinlock(.IRQ);
    work_thread: *Task_Info;
    work_in_progress: bool;

    work_added:     Semaphore;
    work_completed: Condition_Variable;

    work_thread_proc :: () {
        using global.uacpi_state;

        log_category("uACPI");

        // uACPI uses thread local storage.
        tls := get_4k_page() + DIRECT_MAPPING_BASE;
        #asm FSGSBASE { wrfsbase tls; }

        while true {
            wait_for(*work_added);

            acquire(*work_queue_lock);

            item := queue_pop(*work_queue);
            work_in_progress = true;

            release(*work_queue_lock);

            log("Beginning work item.");
            item.handler(item.ctx);
            log("Work item completed.");

            acquire(*work_queue_lock);

            work_in_progress = false;
            if queue_is_empty(work_queue) {
                notify_all(*work_completed);
            }

            release(*work_queue_lock);
        }
    }
}

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
    write_string("uACPI kernel call: \"uacpi_kernel_io_unmap\"\n");
    bluescreen();
}

#program_export
uacpi_kernel_map :: (addr: uacpi_phys_addr, len: uacpi_size) -> *void #c_call {
    push_context {
        memory := alloc_block(*global.virtual_block_allocator, cast(u64) len);
        pages_needed := len / 4096;
        if len % 4096 pages_needed += 1;

        page_flags := Page_Flags.READ_WRITE | .PRESENT | .CACHE_DISABLE;

        for 0..pages_needed-1 {
            offset := cast(u64) it * 4096;
            map_page(memory + offset, addr + offset, page_flags);
        }

        return xx memory;
    }
}

#program_export
uacpi_kernel_unmap :: (addr: *void, len: uacpi_size) #c_call {
    return;
}

#program_export
uacpi_kernel_alloc :: (size: uacpi_size) -> *void #c_call {
    push_context {
        return alloc(cast(s64)size);
    }
}

#program_export
uacpi_kernel_free :: (mem: *void) #c_call {
    if mem == null return;

    push_context {
        free(mem);
    }
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
    irq.handler(irq.ctx);
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
    lock := cast(*Spinlock)handle;
    acquire(lock);

    return 0;
}

#program_export
uacpi_kernel_unlock_spinlock :: (handle: uacpi_handle, flags: uacpi_cpu_flags) #c_call {
    lock := cast(*Spinlock)handle;
    release(lock);
}

#program_export
uacpi_kernel_schedule_work :: (type: uacpi_work_type, handler: uacpi_work_handler, ctx: uacpi_handle) -> uacpi_status #c_call {
    using global.uacpi_state;

    item: Work_Item;
    item.type = type;
    item.handler = handler;
    item.ctx = ctx;

    push_context {
        acquire(*work_queue_lock);
        queue_push(*work_queue, item);
        release(*work_queue_lock);

        signal(*work_added);
    }

    return .OK;
}

#program_export
uacpi_kernel_wait_for_work_completion :: () #c_call {
    using global.uacpi_state;

    push_context {
        acquire(*work_queue_lock);

        predicate :: #code queue_is_empty(work_queue) && !work_in_progress;
        wait_for(*work_completed, *work_queue_lock, predicate);

        release(*work_queue_lock);
    }
}


do_uacpi_kernel_io_read :: (device: uacpi_handle, offset: uacpi_size, value: *$T) -> uacpi_status #c_call {
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



do_uacpi_kernel_io_write :: (device: uacpi_handle, offset: uacpi_size, value: $T) -> uacpi_status #c_call {
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

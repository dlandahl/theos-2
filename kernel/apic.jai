
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
    if kernel_globals.apic == null {
        bluescreen();
    }

    return cast(*u32, kernel_globals.apic + cast(u64) register).*;
}

write_apic_register :: (register: Apic_Register, value: u32) #no_context {
    if kernel_globals.apic == null {
        bluescreen();
    }

    cast(*u32, kernel_globals.apic + cast(u64) register).* = value;
}

Apic_Lvt_Timer :: enum u32 {
    gate_index      :: 8;
    reserved_0      :: 4;
    delivery_status :: 1;
    reserved_1      :: 3;
    mask            :: 1;
    timer_mode      :: 2;
    reserved_2      :: 13;
} @Bitfield

APIC_TIMER_MODE_ONE_SHOT     :: 0b00;
APIC_TIMER_MODE_PERIODIC     :: 0b01;
APIC_TIMER_MODE_TSC_DEADLINE :: 0b10;

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

        virtual := alloc_block(*kernel_globals.virtual_block_allocator, 4096);
        map_page(virtual, physical, Page_Flags.READ_WRITE | .PRESENT | .CACHE_DISABLE);

        kernel_globals.apic = cast(*void) virtual;
    }


    kernel_globals.processor_cores.data = space_for_processor_cores.data;
    kernel_globals.processor_cores.count = 1;

    bootstrap_core := *kernel_globals.processor_cores[0];
    bootstrap_core.local_apic_id = read_apic_register(.APIC_ID) >> 24;

    init_processor_core();

    #insert #run,host -> string {
        builder: String_Builder;
        for 0..31 {
            print(*builder, "register_interrupt_gate(int__default_isa_fault_handler_%1, %1, true);\n", it);
        }
        return builder_to_string(*builder);
    };

    register_interrupt_gate(int__breakpoint_handler,            3,  true);
    register_interrupt_gate(int__general_protection_fault,      13, true);
    register_interrupt_gate(int__page_fault,                    14, true);
    register_interrupt_gate(int__simd_floating_point_exception, 19, true);

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

            id := kernel_globals.processor_cores.count;
            kernel_globals.processor_cores.count += 1;

            new_core := *kernel_globals.processor_cores[id];

            new_core.local_apic_id = lapic_ics.apic_id;
            new_core.id = id;

          case .IO_APIC;
            assert(kernel_globals.io_apic == null);

            ioapic_ics := cast(*Ics_Io_Apic) ics;

            virtual := alloc_block(*kernel_globals.virtual_block_allocator, 4096);
            map_page(virtual, ioapic_ics.address, Page_Flags.READ_WRITE | .PRESENT | .CACHE_DISABLE);

            kernel_globals.io_apic = cast(*u32) virtual;

            assert(ioapic_ics.address == 0xfec0_0000);

          case .INTERRUPT_SOURCE_OVERRIDE;
            Push_Print_Style().default_format_struct.use_long_form_if_more_than_this_many_members = 1;
            iso := cast(*Ics_Source_Override) ics;
            log("Interrupt source override: %", iso.*);
        }
    }

    timer_gate := allocate_interrupt_gate();
    register_interrupt_gate(int__local_apic_timer_interrupt, timer_gate);

    // Store this, to be able to configure the APIC timer of all cores to use the same interrupt handler.
    // In the future we might not need the APIC timer if we only support CPUs with the TSC deadline feature.
    kernel_globals.local_apic_timer_interrupt_gate = timer_gate;

    kernel_globals.tasks.allocator = context.allocator;
    kernel_globals.next_task_id = 1;
}

startup_application_processors :: () {

    // Load the 16 bit AP initialization routine from static memory
    memcpy(cast(*void) 0x8000 + DIRECT_MAPPING_BASE, ap_startup_bin.data, 4096);

    Ap_Startup_Data :: struct {
        // Layout matches the ap_startup assembly code in first.jai
        stack: u64;
        entry_point: *void;
        pml4: *u64;
    }

    ap_startup_data := cast(*Ap_Startup_Data) (0x8200 + DIRECT_MAPPING_BASE);
    ap_startup_data.entry_point = cast(*void) ap_entry_point;
    ap_startup_data.pml4 = kernel_globals.boot_data.page_tables.pml4.data;

    bsp := get_current_core();

    for* kernel_globals.processor_cores {
        if it == bsp {
            continue;
        }

        // This lock is to ensure that APs have time to copy their stack's base address into their stack register before the next AP is started up.
        // Maybe if processors could use their APIC ID to find their stack memory it would be faster.
        acquire(*ap_startup_spinlock);

        stack := alloc_block(*kernel_globals.physical_block_allocator, 0x1_0000) + 0x1_0000;
        ap_startup_data.stack = stack + DIRECT_MAPPING_BASE;

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

ap_startup_spinlock: Spinlock;

ap_entry_point :: () #c_call {

    release(*ap_startup_spinlock);

    push_context {
        init_processor_core();

        core_begin_multitasking();

        #asm { sti; }

        while true {
            yield();
            #asm { hlt; }
        }
    }
}

get_current_core :: inline (loc := #caller_location) -> *X64_Core #no_context {
    core: *X64_Core;

    #asm FSGSBASE {
        rdgsbase core;
    }

    return core;
}


ioapic_add_interrupt_redirection_table_entry :: (redirection_index: u32, gate_number: int) {
    REDIRECTION_TABLE_BASE       : u32 : 0x10;
    REDIRECTION_TABLE_ENTRY_SIZE : u32 : 0x2;

    register_index := REDIRECTION_TABLE_BASE + redirection_index * REDIRECTION_TABLE_ENTRY_SIZE;

    kernel_globals.io_apic[0] = register_index;
    kernel_globals.io_apic[4] = cast(u32) gate_number;

    kernel_globals.io_apic[0] = register_index+1;
    kernel_globals.io_apic[4] = 0;
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
    Scoped_Acquire(*kernel_globals.serial_port_spinlock);

    write_string("Something bad happened (%1) on core ");
    write_number(core.id);
    write_string("\n");

    bluescreen();
} @InterruptRoutine
END;

#program_export
breakpoint_handler :: (stack: *Interrupt_Stack(false)) #c_call {
    push_context {
        context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 0;
        context.print_style.default_format_struct.use_newlines_if_long_form = true;
        context.print_style.default_format_int.base = 16;

        Scoped_Acquire(*kernel_globals.serial_port_spinlock);

        print("Breakpoint hit. Context:\n%", stack.*);
    }

    bluescreen();
} @InterruptRoutine

#program_export
page_fault :: (stack: *Interrupt_Stack(true)) #c_call {
    push_context,defer_pop;

    Scoped_Acquire(*kernel_globals.serial_port_spinlock);

    core := get_current_core();
    task := core.scheduler.current_task;

    print("Page Fault (On core %, running thread %)\n", core.id, task.id);

    _cr2: u64;
    #asm { get_cr2 _cr2; }
    cr2 := _cr2;

    Push_Print_Style().default_format_int.base = 16;
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
general_protection_fault :: (stack: *Interrupt_Stack(with_error_code = true)) #c_call {
    push_context {
        Scoped_Acquire(*kernel_globals.serial_port_spinlock);

        core := get_current_core();
        task := core.scheduler.current_task;

        print("General Protection Fault    (On core %, running thread %)\n", core.id, task.id);

        Push_Print_Style().default_format_int.base = 16;
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

    kernel_globals.pci_ecam = ecam;


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

    spinlock_storage: Bucket_Array(Spinlock, 16, always_iterate_by_pointer=true);
}

#import "Uacpi";

#program_export uacpi_do_atomic_cmpxchg64 :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_do_atomic_cmpxchg64\"\n");
    bluescreen();
}

#program_export uacpi_do_atomic_cmpxchg32 :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_do_atomic_cmpxchg32\"\n");
    bluescreen();
}

#program_export uacpi_do_atomic_cmpxchg16 :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_do_atomic_cmpxchg16\"\n");
    bluescreen();
}

#program_export uacpi_kernel_get_rsdp :: (rsdp_address: *uacpi_phys_addr) -> uacpi_status #c_call {
    rsdp_address.* = cast(uacpi_phys_addr) kernel_globals.acpi_rsdp;
    return .OK;
}

#program_export uacpi_kernel_raw_memory_read :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_raw_memory_read\"\n");
    bluescreen();
}

#program_export uacpi_kernel_raw_memory_write :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_raw_memory_write\"\n");
    bluescreen();
}

#program_export uacpi_kernel_raw_io_read :: (address: uacpi_io_addr, byte_width: uacpi_u8, out_value: *uacpi_u64) -> uacpi_status #c_call {
    value: u64;

    #asm {
        address === d;
        value   === a;
    }

    if byte_width == {
        case 1; #asm { in.8  value, address; }
        case 2; #asm { in.16 value, address; }
        case 4; #asm { in.32 value, address; }
        case; bluescreen();
    }

    out_value.* = value;
    return .OK;
}

#program_export uacpi_kernel_raw_io_write :: (address: uacpi_io_addr, byte_width: uacpi_u8, value: uacpi_u64) -> uacpi_status #c_call {
    #asm {
        address === d;
        value   === a;
    }

    if byte_width == {
        case 1; #asm { out.8  address, value; }
        case 2; #asm { out.16 address, value; }
        case 4; #asm { out.32 address, value; }
        case; bluescreen();
    }

    return .OK;
}

#program_export
uacpi_kernel_pci_read :: (bus_address: *uacpi_pci_address, offset: uacpi_size, byte_width: u8, value: *u64) -> uacpi_status #c_call {
    using bus_address;

    for kernel_globals.pci_ecam {
        if it.segment_group != segment continue;

        device_offset := cast(u64, bus * 256 + device * 8 + function);
        address := it.base_address + device_offset * PCI_CONFIGURATION_SPACE_SIZE;

        // Todo: we need to handle unaligned accesses here.
        if address & 0b11 bluescreen();

        // Todo: This address is not necessarily covered by the direct mapping. The same issue exists in the rest of the PCI configuration space access code.
        address += DIRECT_MAPPING_BASE;

        value.* = address.(*u32).*.(u64);
        value.* &= cast(u64, 1 << (byte_width*8)) - 1;

        return .OK;
    }

    bluescreen();
    return .INVALID_ARGUMENT;
}

#program_export
uacpi_kernel_pci_write :: (bus_address: *uacpi_pci_address, offset: uacpi_size, byte_width: u8, value: u64) -> uacpi_status #c_call {
    using bus_address;

    for kernel_globals.pci_ecam {
        if it.segment_group != segment continue;

        device_offset := cast(u64, bus * 256 + device * 8 + function);
        address := it.base_address + device_offset * PCI_CONFIGURATION_SPACE_SIZE;

        // Todo: we need to handle unaligned accesses here.
        if address & 0b11 bluescreen();

        // Todo: This address is not necessarily covered by the direct mapping. The same issue exists in the rest of the PCI configuration space access code.
        address += DIRECT_MAPPING_BASE;

        address.(*u32).* = value.(u32);

        return .OK;
    }

    bluescreen();
    return .INVALID_ARGUMENT;
}

#program_export
uacpi_kernel_io_map :: (base: uacpi_io_addr, len: uacpi_size, out_handle: *uacpi_handle) -> uacpi_status #c_call {
    using kernel_globals.uacpi_state;

    out_handle.* = xx base;

    return .OK;
}

#program_export uacpi_kernel_io_unmap :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_io_unmap\"\n");
    bluescreen();
}

#program_export
uacpi_kernel_io_read :: (handle: uacpi_handle, offset: uacpi_size, byte_width: uacpi_u8, value: *u64) -> uacpi_status #c_call {
    using kernel_globals.uacpi_state;

    io_base := cast(u16) handle;
    address := io_base + xx offset;

    result: u64;
    #asm {
        address === d;
        result  === a;
    }

    if byte_width == {
        case 1; #asm { in.8  result, address; }
        case 2; #asm { in.16 result, address; }
        case 4; #asm { in.32 result, address; }
        case; bluescreen();
    }

    value.* = result;

    return .OK;
}

#program_export
uacpi_kernel_io_write :: (handle: uacpi_handle, offset: uacpi_size, byte_width: uacpi_u8, value: u64) -> uacpi_status #c_call {
    using kernel_globals.uacpi_state;

    io_base := cast(u16) handle;
    address := io_base + xx offset;

    #asm {
        address === d;
        value   === a;
    }

    if byte_width == {
        case 1; #asm { out.8  address, value; }
        case 2; #asm { out.16 address, value; }
        case 4; #asm { out.32 address, value; }
        case; bluescreen();
    }

    return .OK;
}

#program_export
uacpi_kernel_map :: (addr: uacpi_phys_addr, len: uacpi_size) -> *void #c_call {
    push_context {
        memory := alloc_block(*kernel_globals.virtual_block_allocator, cast(u64) len);
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
        phys := alloc_block(*kernel_globals.physical_block_allocator, size);
        virt := cast(*void) phys + DIRECT_MAPPING_BASE;

        return virt;
    }
}

#program_export
uacpi_kernel_calloc :: (count: uacpi_size, size: uacpi_size) -> *void #c_call {
    size_bytes := size*count;

    push_context {
        phys := alloc_block(*kernel_globals.physical_block_allocator, size_bytes);
        virt := cast(*void) phys + DIRECT_MAPPING_BASE;

        memset(virt, 0, cast(s64) size_bytes);
        return virt;
    }
}

#program_export
uacpi_kernel_free :: (mem: *void) #c_call {
    if mem == null return;

    push_context {
        phys := cast(u64) mem - DIRECT_MAPPING_BASE;
        free_block(*kernel_globals.physical_block_allocator, phys);
    }
}

#program_export
uacpi_kernel_log :: (log_level: uacpi_log_level, c_string: *uacpi_char) #c_call {
    // if log_level < .INFO return;

    push_context {
        Log_Category("uACPI");

        message: string;
        message.data = c_string;
        message.count = c_style_strlen(c_string);

        log(message);
    }
}

#program_export uacpi_kernel_get_nanoseconds_since_boot :: () -> u64 #c_call {
    push_context {
        return cast(u64) to_nanoseconds(get_kernel_timestamp());
    }
}

#program_export uacpi_kernel_stall :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_stall\"\n");
    bluescreen();
}

#program_export uacpi_kernel_sleep :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_sleep\"\n");
    bluescreen();
}



// Just use spinlocks until we have actual mutexes.

#program_export uacpi_kernel_create_mutex :: () -> uacpi_handle #c_call {
    return uacpi_kernel_create_spinlock();
}

#program_export uacpi_kernel_free_mutex :: (handle: uacpi_handle) #c_call {
    uacpi_kernel_free_spinlock(handle);
}

next_event_handle: uacpi_handle = xx 1;

#program_export uacpi_kernel_create_event :: () -> uacpi_handle #c_call {
    result := next_event_handle;
    next_event_handle += 1;
    return result;
}

#program_export uacpi_kernel_free_event :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_free_event\"\n");
    bluescreen();
}

#program_export uacpi_kernel_get_thread_id :: () -> uacpi_thread_id #c_call {
    core := get_current_core();
    return xx core.scheduler.current_task.id;
}

#program_export uacpi_kernel_acquire_mutex :: (handle: uacpi_handle, timeout: uacpi_u16) -> uacpi_status #c_call {
    uacpi_kernel_lock_spinlock(handle);
    return .OK;
}

#program_export uacpi_kernel_release_mutex :: (handle: uacpi_handle) #c_call {
    uacpi_kernel_unlock_spinlock(handle, 0);
}

#program_export uacpi_kernel_wait_for_event :: (handle: uacpi_handle, timeout: uacpi_u16) #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_wait_for_event\"\n");
    bluescreen();
}

#program_export uacpi_kernel_signal_event :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_signal_event\"\n");
    bluescreen();
}

#program_export uacpi_kernel_reset_event :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_reset_event\"\n");
    bluescreen();
}

#program_export uacpi_kernel_handle_firmware_request :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_handle_firmware_request\"\n");
    bluescreen();
}

UACPI_IRQ_HANDLER :: #string END
#program_export
handle_uacpi_irq_%1 :: (stack: *void) #c_call {
    using kernel_globals.uacpi_state;
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
    using kernel_globals.uacpi_state;

    first_irq_handler_gate_index = kernel_globals.next_free_interrupt_gate;
    kernel_globals.next_free_interrupt_gate += irq_contexts.count;

    #insert #run,host -> string {
        builder: String_Builder;
        for 0..7 {
            print(*builder, "register_interrupt_gate(int__handle_uacpi_irq_%1, first_irq_handler_gate_index + %1);\n", it);
        }
        return builder_to_string(*builder);
    };
}

#program_export
uacpi_kernel_install_interrupt_handler :: (irq: u32, handler: uacpi_interrupt_handler, ctx: uacpi_handle, out_irq_handle: *uacpi_handle) -> uacpi_status #c_call {
    using kernel_globals.uacpi_state;

    push_context {
        if irq_contexts_used >= irq_contexts.count {
            log_error("Must allocate more IRQ handlers for uACPI.");
            bluescreen();
        }

        new_irq := *irq_contexts[irq_contexts_used];

        new_irq.handler = handler;
        new_irq.ctx     = ctx;

        gate := first_irq_handler_gate_index + irq_contexts_used;
        ioapic_add_interrupt_redirection_table_entry(irq, gate);

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
    using kernel_globals.uacpi_state;
    push_context {

        locator, _ := bucket_array_add(*spinlock_storage, 0);
        locator.slot_index += 1; // Because we return this in a pointer, if this value is zero, uACPI assumes we ran out of memory.

        // ucapi_handle is *void, Bucket_Locator is two 32-bit integers. We can store the locator using the pointer value.
        #assert size_of(uacpi_handle) >= size_of(Bucket_Locator);

        handle: uacpi_handle;
        memcpy(*handle, *locator, 8);

        return handle;
    }
}

#program_export
uacpi_kernel_free_spinlock :: (handle: uacpi_handle) #c_call {
    using kernel_globals.uacpi_state;

    push_context {
        locator: Bucket_Locator;
        memcpy(*locator, *handle, 8);
        locator.slot_index -= 1;

        bucket_array_remove(*spinlock_storage, locator);
    }
}

#program_export
uacpi_kernel_lock_spinlock :: (handle: uacpi_handle) -> uacpi_cpu_flags #c_call {
    using kernel_globals.uacpi_state;

    push_context {
        locator: Bucket_Locator;
        memcpy(*locator, *handle, 8);
        locator.slot_index -= 1;

        lock := bucket_array_find_pointer(*spinlock_storage, locator);
        acquire(lock);

        return 0; // Todo, think about interrupts. This may currently cause deadlocks.
    }
}

#program_export
uacpi_kernel_unlock_spinlock :: (handle: uacpi_handle, flags: uacpi_cpu_flags) #c_call {
    using kernel_globals.uacpi_state;

    push_context {
        locator: Bucket_Locator;
        memcpy(*locator, *handle, 8);
        locator.slot_index -= 1;

        lock := bucket_array_find_pointer(*spinlock_storage, locator);
        release(lock);
    }
}

#program_export uacpi_kernel_schedule_work :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_schedule_work\"\n");
    bluescreen();
}

#program_export uacpi_kernel_wait_for_work_completion :: () #c_call {
    write_string("uACPI kernel call: \"uacpi_kernel_wait_for_work_completion\"\n");
    bluescreen();
}
 
#program_export __popcountdi2 :: () {
    write_string("uACPI kernel call: \"__popcountdi2\"\n");
    bluescreen();
}

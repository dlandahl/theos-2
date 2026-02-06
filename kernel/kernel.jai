
#import "Basic";

#import "Machine_X64";
using,except(byte_swap_in_place) _ :: #import "Bit_Operations";
#import "Hash_Table";
#import "String";
#import "Random";
#import "Hash";

#import "debug_info";
#import "executable_formats";

#import "Bucket_Array";

array_add :: bucket_array_add;
array_add :: (array: *Bucket_Array) -> *array.type {
    loc, item := bucket_array_add(array, .{});
    return item;
}

#import "Bitfield"(true);

set          :: bitfield_set;
get          :: bitfield_get;
set_bit      :: bitfield_set_bit;
get_bit      :: bitfield_get_bit;
clear_bit    :: bitfield_clear_bit;
set_in_place :: bitfield_set_in_place;
get_in_place :: bitfield_get_in_place;

#import "Ring_Buffer";
#import "ASN1";
#import "Aes";
#import "Jai_Crypto";

get_calendar_time :: () -> Calendar_Time {
    apollo := get_monotonic_time();
    calendar := native_apollo_to_calendar(apollo);
    return calendar;
}

#import,file "../modules/FAT16.jai"(get_calendar_time);

Curve25519 :: #import "Curve25519";

#load "../boot_data.jai";

#load "apic.jai";
#load "x64.jai";
#load "network.jai";
#load "pci_express.jai";
#load "multitasking.jai";
#load "time.jai";
#load "file_system.jai";

TRACE_INCLUDE_RUNTIME_CODE :: true;
#load "trace.jai";

X64_Core :: struct {
    task_state_segment: Tss_With_Iopb #align 0x80;

    // Align to cache block so no extra memory accesses are required on privilege change.
    global_descriptor_table: Global_Descriptor_Table #align 64;

    local_apic_id: u32;
    id: int; // ID 0 is the bootstrap core.

    scheduler: Scheduler;

    preempt_disable_count: s64;

    interrupt_context_active: s64;

    online: bool; // The core has called core_begin_multitasking, so we can put threads on it.

    mcs_node: MCS_Node;
}

// This can't be in global, or else, due to the size of the IOPB, the compiler will
// reserve 8Mb in the executable, all of which is zero. Todo: is there really a reason not to dynamically allocate this?
space_for_processor_cores: [1024] X64_Core;

// For the same reason this struct shouldn't have default values. Todo: move the IOPB.
#assert initializer_of(X64_Core) == null;

Kernel_Globals :: struct {
    using boot_data: *Boot_Data;

    trace_state: Trace_State;

    debug_info: Debug_Info;
    debug_info_memory_pool: Pool;

    large_page_allocator: Large_Page_Allocator;

    physical_block_allocator: Block_Allocator;
    virtual_block_allocator: Block_Allocator;

    small_objects: Small_Objects_Allocator;

    guarded_memory: struct {    // Temporary to help debugging.
        allocations: List_Queue(Guarded_Allocation);

        spinlock: Spinlock;

        #as using allocator: Allocator;
        allocator.proc = guarded_memory_allocator_proc;
    }

    fadt: *acpi_fadt;
    uacpi_state: uACPI_State;

    // Hardware requires 16 byte alignment on IDT
    interrupt_descriptor_table: [256] Interrupt_Gate_Descriptor #align 16;
    next_free_interrupt_gate: int;

    tasks: Bucket_Array(Task_Info, 128, always_iterate_by_pointer=true);
    next_task_id: int;
    task_info_storage_spinlock: Spinlock;

    processor_cores: [] X64_Core;

    // This flag means that we can call "get_current_core" and that we can access the processor_cores array.
    // It does not mean that any cores besides the bootstrap processor are ready yet. For that, check the "online" bit in the corresponding X64_Core struct.
    multiprocessing_initialized: bool;

    apic: *void;
    io_apic: *u32;
    scheduling_interrupt_gate: int;

    high_precision_timer: HPET;

    boot_time: Apollo_Time;
    rtc_format_is_bcd: bool;

    tsc_frequency: u64;

    // If future x64 CPUs all support this, plus some other TSC specific features, then we'll likely remove
    // support for HPET and the Local APIC timer, and use TSC for everything. Namely the features you would
    // need are Invariant TSC, and for the frequency to be provided by CPUID. However, Boostibot on Discord
    // said that TSC frequency is imprecise even if provided by CPUID, so will need to investigate that.
    tsc_deadline_support: bool;

    text_drawing_state: struct {
        cursor_x: int;
        cursor_y: int;

        font: Netpbm_Image;

        spinlock: Spinlock(.IRQ);

        font_loaded: bool;
    }

    COM1: Serial_Port(0x3f8); // Used for writing to log files and the host console on VirtualBox and QEMU.
    COM2: Serial_Port(0x2f8); // Used for writing trace data.

    network_connection: Network_Connection;

    pci_ecam: [] Ecam_Entry;
    pci_routing_table: [] uacpi_pci_routing_table_entry;

    nvme: Nvme_Controller;

    pci_devices: [..] Pci_Device;
}

global: Kernel_Globals;

Assembly :: #library,no_dll "../.build/assembly";

#program_export
kernel_entry :: () #no_context {

    set_stack_trace_sentinel();

    {
        // Initialize cpu-local data really early, because it's useful to have e.g. core ID and interrupt_context_active available.
        core := space_for_processor_cores.data;
        core.* = .{};
        CR4_FSGSBASE := 1 << 16;

        #asm FSGSBASE {
            // Todo: FSGSBASE also gets initialized in initialize_processor_core as part of enable_cpu_features.
            get_cr4 cr4:;
            or  cr4, CR4_FSGSBASE;
            set_cr4 cr4;
            wrgsbase core;
        }
    }

    write_string_callback = kernel_write_string;
    set_default_context_callbacks();

    // We should avoid using the UEFI identity map because we'll need to get rid of it once we run user processes in low memory.
    global.boot_data = cast(*Boot_Data) (Boot_Data.BASE_ADDRESS + DIRECT_MAPPING_BASE);

    // Used for AP bootstrap.
    global.large_pages[0].state = .RESERVED;

    memory_map_index: int;
    for* page, page_index: global.large_pages {

        page_base  := page_index * 0x20_0000;
        page_limit := page_base  + 0x20_0000;

        for memory_map_index..global.memory_map_entries_used-1 {

            region := global.memory_map[it];
            region_limit := region.pages * 4096 + region.address;

            if region_limit <= cast(u64) page_base {
                continue;
            }

            if region.address >= cast(u64) page_limit {
                memory_map_index -= 1;
                continue page;
            }

            if region.type != .FREE {
                page.state = .RESERVED;
                continue page;
            }

            memory_map_index += 1;
        }
    }


    global.large_page_allocator.freelist  = FREELIST_TAIL;
    global.large_page_allocator.clearlist = FREELIST_TAIL;
    global.large_page_allocator.lru_least = LRU_TAIL;
    global.large_page_allocator.lru_most  = LRU_TAIL;

    // Todo: hardcoded.
    for region: global.memory_map {
        if !it_index continue;
        region_size := region.pages * 4096;

        if region_size >= 0x2000_0000 && region.type == .FREE {
            first_page := region.address / 0x20_0000 + 1;

            for first_page..first_page+256 {
                // Todo: Make sure all these pages were actually marked free.
                if (global.large_pages[it].state != .FREE) bluescreen();
                global.large_pages[it].state = .RESERVED;
            }

            init_block_allocator(*global.physical_block_allocator, region.address, 0x2000_0000, 0x10);
            break;
        }
    }

    // Let's init tracing as early as possible (as soon as physical memory allocation is available) so we can trace whatever we eventually want.
    init_tracing();
    // global.trace_state.tracing_enabled = false;

    if global.physical_block_allocator.base_address == 0 {
        write_string("Could not find enough memory for the kernel...\n");
        while true #asm { cli; hlt; }
    }


    push_context {
        using global.framebuffer;

        for y: 0..y_resolution-1 {
            for x: 0..x_resolution-1 {
                red   := cast(int) (0xa0 * (1.0 / y_resolution) * y);
                green := cast(int) (0xa0 * (1.0 / x_resolution) * x);

                // buffer[x + y * stride] = cast(u32, (red << 16) | (green << 8));
                buffer[x + y * stride] = 0;
            }
        }

        {
            // Put a virtual memory heap after the direct mapping.
            GB :: 0x4000_0000;
            direct_mapping_size := cast(u64) global.page_tables.direct_pd.count * GB;

            heap_base: u64 = DIRECT_MAPPING_BASE + direct_mapping_size;
            heap_size: u64 = 64 * GB;

            // Keep virtual allocations page aligned, since virtual memory always needs to be mapped anyway.
            init_block_allocator(*global.virtual_block_allocator, heap_base, heap_size, alignment=4096);
        }

        {
            // Sequentially allocating interrupt gates, starting after the ISA exceptions
            memset(global.interrupt_descriptor_table.data, 0, size_of(type_of(global.interrupt_descriptor_table)));
            global.next_free_interrupt_gate = 32;
        }

        global.text_drawing_state.font = parse_netpbm(font_file);
        global.text_drawing_state.font_loaded = true;

        {
            ts: Temporary_Storage;
            set_initial_data(*ts, TEMPORARY_STORAGE_SIZE, alloc(TEMPORARY_STORAGE_SIZE));
            context.temporary_storage = *ts;
        }

        read_debug_info();

        {
            temporary_buffer := talloc(0x8000);
            uacpi_setup_early_table_access(temporary_buffer, 0x8000);
        }

        initialize_apic();

        initialize_hpet();
        hpet_configure_timer(timer_index=0, frequency=10, periodic=true);

        initialize_rtc();

        // Get the time at the most recent second. Maybe we can use an interrupt to detect boot time more accurately.
        boot_calendar_time := rtc_get_calendar_time();

        // Don't use Basic.calendar_to_apollo, because it's OS specific
        global.boot_time = native_calendar_to_apollo(boot_calendar_time);

        initialize_tsc();

        assert(get_rflags() & .IF__interrupt == 0); // We don't want interrupts to be enabled while we're initializing multitasking.

        core_begin_multitasking();

        // Todo: System time alone is too low entropy for OS random number generation.
        time := get_monotonic_system_time();
        random_seed(cast(S128)time);

        find_all_pci_devices();

        initialize_uacpi();

        startup_application_processors();

        for *core: global.processor_cores {
            while !core.online pause();
        }

        irq_restore(true);

        for *global.pci_devices {
            if it.combined_class_code == {
              case .SATA_CONTROLLER;
                init_ahci_controller(it);

              case .NVME_CONTROLLER;
                global.nvme = init_nvme_controller(it);

              case .I8254X_ETHERNET;
                global.network_connection.adapter = init_i8254x(it);

              case .HIGH_DEFINITION_AUDIO;
                init_high_definition_audio_controller(it);
            }
        }

        {
            assert(global.nvme.mmio != null);
            buffer := cast(string) NewArray(0xa0_0000, u8);

            blocks_per_transfer := global.nvme.maximum_transfer_size_in_blocks;
            transfers := 0xa0_0000 / (blocks_per_transfer * global.nvme.block_size);

            log("Blocks per transfer: %, transfers: %, total bytes: %",
                hex(blocks_per_transfer), transfers, hex(transfers * blocks_per_transfer * global.nvme.block_size)
               );

            for 0..transfers-1 {
                start_block   := it * blocks_per_transfer;
                memory_buffer := buffer.data + start_block * global.nvme.block_size;
                nvme_read(*global.nvme, cast(u64) start_block, memory_buffer, blocks_per_transfer);
            }

            disk_image := fat16_parse_disk_image(buffer);
            root       := fat16_get_root_directory(*disk_image);

            fat16_create_directory(root, "THEOS");
            fat16_write_file(root, "THEOS/TEST", "The old gentleman's undoubting, unquestioning simplicity has a rare freshness about it in these matter-of-fact railroading and telegraphing days.");

            // success, data := fat16_read_file(root, "THEOS/TEST");
            // assert(success);
            // log(data);

            fat16_print_directory_tree(root);
            fat16_copy_fat_table(*disk_image);

            for 0..transfers-1 {
                start_block   := it * blocks_per_transfer;
                memory_buffer := buffer.data + start_block * global.nvme.block_size;
                nvme_write(*global.nvme, cast(u64) start_block, memory_buffer, blocks_per_transfer);
            }
        }

        log("=== Writing trace buffers. ===");
        trace_event_count := write_trace_buffers();
        log("=== Wrote % trace events. ===", trace_event_count);

        while true {
            schedule_tasks();
            assert(get_rflags() & .IF__interrupt > 0);
            #asm { hlt; }
        }
    }
}

network_test :: () -> string {
    USE_DNS :: false;

    log_category("TLS Test");
    log("Starting.");

    net := *global.network_connection;

    network_adapter_initialized := net.adapter.mmio != null;
    assert(network_adapter_initialized);

    task := create_task(network_thread, name = "Network Thread", kernel_stack_size = 0x10_0000);
    put_task_on_core(task, *global.processor_cores[1]);

    log("Waiting for DHCP handshake.");
    Timeout(net.dhcp_handshake_state == .COMPLETED, 60_000);

    ip_address := bit_cast(u8.[127, 0, 0, 1], u32);
    port: u16 = 4443;

    #if USE_DNS {
        log("Sending DNS Query.");

        for 1..100 {
            // Usually works the first time unless network is bad.

            dns_query := transmit_dns_query(net, "thinkpad");

            if Timeout(dns_query.complete, 1000) {
                continue;
            }

            if dns_query.response != .NOERROR {
                log("DNS Query failed with code %", dns_query.response);
                return;
            }

            ip_address = dns_query.answer;
            // port = 443;
            break;
        }
    }

    transmit_ping(net, ip_address);

    connection := initiate_tcp_connection(net, ip_address, port);

    Timeout(connection.handshake_state == .ESTABLISHED, 60_000);

    tls := establish_tls_connection(connection);

    request := tprint(HTTP_MESSAGE, HTTP_CONTENT.count, HTTP_CONTENT, "");
    request = "GET /server.py HTTP/1.1\r\nHost: thinkpad\r\nAccept: text/x-python\r\n\r\n";

    tls_transmit_application_data(*tls, request);

    builder: String_Builder;

    for 1..2 {
        response := tls_receive_application_data(*tls, seconds_to_apollo(5));
        append(*builder, response);

        log("Got HTTPS response: %", response);
    }

    // Todo: TLS Close Notify.

    tcp_close(connection);

    log("Completed.");
    return builder_to_string(*builder);
}

HTTP_CONTENT :: "{\"content\": \"This discord message was sent from the Jai operating system (running in VirtualBox) using custom ethernet driver and network protocol implementations, including transport layer security written in Jai. Will post a video in a moment.\"}";

HTTP_MESSAGE :: #string,cr END
POST /api/v8/channels/1366374734702313514/messages HTTP/1.1
Host: discord.com
Authorization: %3
Accept: application/json
Content-Type: application/json
Content-Length: %1

%2
END;



get_rbp :: () -> u64 #foreign Assembly;

Call_Stack_Frame :: struct {
    rbp: *Call_Stack_Frame;
    return_address: u64;
}

set_stack_trace_sentinel :: inline () #no_context {
    // We rely on this being inlined so it sees the correct rbp.
    stack_frame := cast(*Call_Stack_Frame) get_rbp();
    stack_frame.rbp = null;
}

do_stack_trace :: (output: [] u32) #no_context {
    stack_frame := cast(*Call_Stack_Frame) get_rbp();

    for 0..output.count-1 {
        if cast(u64) stack_frame < DIRECT_MAPPING_BASE {
            // The stack frame is not in the kernel address space. We can't read it.
            break;
        }

        if !stack_frame.rbp {
            // Found the stack trace sentinel.
            break;
        }

        if stack_frame.return_address >> 24 != 0xffff_ffff_80 {
            // The return address doesn't point into kernel code, unless the kernel executable got really big.
            break;
        }

        output[it] = cast,trunc(u32) stack_frame.return_address;
        stack_frame = stack_frame.rbp;
    }
}

append_formatted_stack_trace :: (builder: *String_Builder, trace: []u32) {
    for trace {
        if it == 0 break;

        address := cast(u64)it + 0xffff_ffff_0000_0000;

        proc_name, file, line := get_debug_info_for_address(address);

        print(builder, "%. [%] %\n", it_index, formatInt(address, base=16), proc_name);

        if file {
            print(builder, "   at %:%\n", file, line);
        }
    }
}

read_debug_info :: () {
    log_category("DWARF");

    success, elf := parse_elf(cast(string)global.kernel_elf, "kernel");

    if !success {
        log_error("Failed to parse elf.");
        return;
    }

    if !elf.debug_info_section || !elf.debug_abbrev_section || !elf.debug_line_section {
        log_error("Failed to find debug sections in elf.");
        return;
    }

    info   := get_section_data(elf, elf.debug_info_section);
    abbrev := get_section_data(elf, elf.debug_abbrev_section);
    line   := get_section_data(elf, elf.debug_line_section);
    str    := get_section_data(elf, elf.debug_str_section);

    success &= apply_relocations(elf, elf.debug_line_section_index, line);
    success &= apply_relocations(elf, elf.debug_info_section_index, info);

    if !success {
        log_error("Failed to apply relocations.");
        return;
    }

    {
        // For some reason, parsing dwarf debug info uses a huge amount of memory.
        pool := *global.debug_info_memory_pool;
        pool.memblock_size  = 0x10_0000;
        pool.oversized_size =  0x1_0000;

        set_allocators(pool);
        push_allocator(.{pool_allocator_proc, pool});

        global.debug_info, success = parse_dwarf_debug_info(info, abbrev, line, str);
    }

    if !success {
        log_error("Failed to parse debug info.");
        return;
    }
}

get_debug_info_for_address :: (address: u64) -> proc_name: string, file: string, line: int {
    // Copypasted from tools/tracer.jai

    for cu: global.debug_info.compilation_units {
        if address < cu.low_pc || address >= cu.high_pc continue;

        proc_name: string;

        for sp: cu.subprograms {
            if address < sp.low_pc || address >= sp.high_pc continue;

            proc_name = sp.name;
            break;
        }

        for seq: cu.line_info.sequences {
            first := seq.addresses[0];
            last  := seq.addresses[seq.addresses.count-1];

            if address < first || address >= last continue;

            for< seq_addr: seq.addresses {
                if seq_addr > address continue;

                mapping   := seq.mappings[it_index];
                file_name := get_filename_for_file_id(cu.line_info, mapping.file_id);

                return proc_name, file_name, mapping.line;
            }
        }
    }

    return "(no debug info)", "", 0;
}



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

set_default_context_callbacks :: () #no_context {
    // These are default context values in our custom Runtime_Support module, such that they get used by default initalized context structs.

    kernel_assertion_failed = (location: Source_Code_Location, message: string) -> bool {
        builder: String_Builder;

        append(*builder, "\n=== Assertion failure. ===\n");
        if message.count {
            append(*builder, "Message: ");
            append(*builder, message);
        }
        append(*builder, "\n");

        buffer: [32] u32;
        do_stack_trace(buffer);

        append_formatted_stack_trace(*builder, buffer);

        write_builder(*builder);

        bluescreen();
        return true;
    };

    kernel_default_logger = (message: string, data: *void, info: Log_Info) {
        builder: String_Builder;

        if context.log_category {
            append(*builder, "[");
            append(*builder, context.log_category);
            append(*builder, "] ");
        }

        if info.common_flags & .ERROR {
            append(*builder, "Error: ");
        }

        append(*builder, message);

        if message[message.count-1] != #char "\n" {
            append(*builder, "\n");
        }

        write_builder(*builder);
    }

    kernel_default_allocator_proc = (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
        if mode == .ALLOCATE || mode == .RESIZE {
            if size == 0 {
                return null;
            }

            is_resize := mode == .RESIZE && old_memory != null;

            if is_resize {
                physical := cast(u64) old_memory - DIRECT_MAPPING_BASE;
                success := resize_block(*global.physical_block_allocator, physical, cast(u64) size);

                if success {
                    return old_memory;
                }
            }

            physical := alloc_block(*global.physical_block_allocator, cast(u64) size);
            virtual := cast(*void) physical + DIRECT_MAPPING_BASE;

            if is_resize {
                memcpy(virtual, old_memory, old_size);

                physical := cast(u64) old_memory - DIRECT_MAPPING_BASE;
                free_block(*global.physical_block_allocator, physical);
            }

            return virtual;
        }

        if mode == .FREE {
            if old_memory == null {
                return null;
            }

            physical := cast(u64) old_memory - DIRECT_MAPPING_BASE;
            free_block(*global.physical_block_allocator, physical);
        }

        if mode == .CAPS {
            return cast(*void) Allocator_Caps.FREE | .HINT_I_AM_A_GENERAL_HEAP_ALLOCATOR | .ACTUALLY_RESIZE;
        }

        return null;
    };
}

init_processor_core :: () {
    core: *X64_Core;

    enable_cpu_features();

    {
        my_local_apic_id := read_apic_register(.APIC_ID) >> 24;

        for* global.processor_cores {
            if it.local_apic_id == my_local_apic_id {
                core = it;
                break;
            }
        }

        assert(core != null, "APIC id not found: %", my_local_apic_id);

        #asm FSGSBASE { wrgsbase core; }
    }

    {
        // Global descriptor table.

        // Use the IO Permission Bitmap to give user mode access to all IO ports for now.
        memset(core.task_state_segment.bitmap.data, 0, 8192);
        core.task_state_segment.iopb = size_of(Task_State_Segment);

        tss_desc: System_Segment_Descriptor;
        tss_address := cast(u64) *core.task_state_segment;

        tss_desc.segment_limit = size_of(Tss_With_Iopb);
        tss_desc.base_address_0 = cast,trunc(u16, tss_address);
        tss_desc.base_address_1 = cast,trunc(u8,  tss_address >> 16);
        tss_desc.base_address_2 = cast,trunc(u8,  tss_address >> 24);
        tss_desc.base_address_3 = cast,trunc(u32, tss_address >> 32);
        tss_desc.flags_0        = 0b1_00_0_1001; // type=TSS non-busy | PRESENT

        using Gdt_Entry;

        core.global_descriptor_table = Global_Descriptor_Table.{
            0x0,
            READ_WRITE | PRESENT | DESCRIPTOR_TYPE | LONG_MODE_CODE | EXECUTABLE,
            READ_WRITE | PRESENT | DESCRIPTOR_TYPE,
            READ_WRITE | PRESENT | DESCRIPTOR_TYPE | PRIVILEGE0 | PRIVILEGE1,
            READ_WRITE | PRESENT | DESCRIPTOR_TYPE | PRIVILEGE0 | PRIVILEGE1 | LONG_MODE_CODE | EXECUTABLE,
            tss_desc,
            0xffff_ffff,
        };

        gdt_desc: struct {
            limit: u16;
            base: *Global_Descriptor_Table #align 2;
        }

        gdt_desc.limit = size_of(Global_Descriptor_Table);
        gdt_desc.base = *core.global_descriptor_table;
        pointer := *gdt_desc;
        #asm { lgdt [pointer]; }

        #bytes .[
            0x66, 0xb8, 0x28, 0x00, // mov ax, 0x28
            0x0f, 0x00, 0xd8        // ltr ax
        ];

        init_segment_registers :: () #foreign Assembly;
        init_segment_registers();
    }

    {
        // Interrupt descriptor table.
        idt_desc: struct {
            limit: u16;
            base: *Interrupt_Gate_Descriptor #align 2;
        }

        idt_desc.limit = size_of(type_of(global.interrupt_descriptor_table));
        idt_desc.base = global.interrupt_descriptor_table.data;

        pointer := *idt_desc;
        #asm { lidt [pointer]; }
    }

    {
        // Enable syscalls.

        // According to https://www.felixcloutier.com/x86/sysret, sysret sets the privilege bits in the stack segment selector automatically, but this does not seem to happen in VirtualBox.
        star := (cast(u64) Segment_Selector.RING0_DATA | 3) << 48;
        star |= (cast(u64) Segment_Selector.RING0_CODE)     << 32;

        write_msr(.STAR__syscall_segment, star);
        write_msr(.SFMASK__syscall_flags, 0);

        syscall_entry :: () #foreign Assembly;
        write_msr(.LSTAR__syscall_address, bit_cast(syscall_entry, u64));

        EFER_SCE__syscall_enable :: 1;

        efer := read_msr(.EFER__extended_features);
        efer |= EFER_SCE__syscall_enable;
        write_msr(.EFER__extended_features, efer);
    }

    {
        // Spurious interrupts.

        register_interrupt_gate(isr__spurious_interrupt, 0xff);
        spurious := read_apic_register(.SPURIOUS_INTERRUPT);
        write_apic_register(.SPURIOUS_INTERRUPT, spurious | 0x1ff); // Todo magic number
    }
}

#program_export
spurious_interrupt :: (stack: Interrupt_Stack_Frame()) #c_call {
    write_string("Spurious...\n");
} @InterruptRoutine

bluescreen :: () #no_context {
    write_string("\nBluescreen!\n");

    using global.framebuffer;

    for y: 0..y_resolution-1 {
        for x: 0..x_resolution-1 {
            buffer[x + y * stride] |= 0xff;
        }
    }

    while true #asm {
        cli;
        hlt;
    }
}



Large_Page_Allocator :: struct {
    max_large_page_used: int;

    freelist:  int;
    clearlist: int;

    lru_least: s32;
    lru_most:  s32;

    spinlock: Spinlock;
}

allocate_large_page :: () -> u64 #no_context {

    using global.large_page_allocator;
    Scoped_Acquire(*spinlock);

    if freelist != FREELIST_TAIL {
        // Todo: This memory needs to be zeroed, as there may be firmware/bootloader stuff there.
        address := freelist * 0x20_0000;

        desc := *global.large_pages[freelist];
        desc.state = .ALLOCATED;
        freelist = desc.list_next;

        return cast(u64) address;
    }

    while max_large_page_used < global.large_pages.count {
        desc := *global.large_pages[max_large_page_used];

        address := max_large_page_used * 0x20_0000;
        max_large_page_used += 1;

        if desc.state == .RESERVED {
            continue;
        }

        desc.state = .ALLOCATED;
        return cast(u64) address;
    }

    // There are no free large pages, evict one from the disk cache.
    if lru_least != LRU_TAIL {
        desc := *global.large_pages[lru_least];
        desc.state = .ALLOCATED;

        address := cast(u64) lru_least * 0x20_0000;
        evict_disk_cache_entry(address);

        return address;
    }

    // There's no free memory. Todo: Swap to disk.
    bluescreen();
    return 0;
}

release_large_page :: (address: u64) {
    using global;

    acquire(*large_page_allocator.spinlock);

    index := cast(s32)(address / 0x20_0000);
    large_pages[index].list_next = cast(s32)large_page_allocator.clearlist;
    large_page_allocator.clearlist = index;

    release(*large_page_allocator.spinlock);
}

clear_large_page :: () -> queue_empty: bool {
    using global;

    // De-queue large page from the clear list.
    acquire(*large_page_allocator.spinlock);

    page := large_page_allocator.clearlist;

    if page == FREELIST_TAIL {
        release(*large_page_allocator.spinlock);
        return true;
    }

    large_page_allocator.clearlist = large_pages[page].list_next;

    release(*large_page_allocator.spinlock);

    // Clear the page.
    address := cast(u64)page * 0x20_0000;
    address += DIRECT_MAPPING_BASE;

    memset(cast(*void)address, 0, 0x20_0000);

    // En-queue to the free list.
    acquire(*large_page_allocator.spinlock);

    large_pages[page].list_next = cast(s32)large_page_allocator.freelist;
    large_page_allocator.freelist = page;

    release(*large_page_allocator.spinlock);
    return false;
}

// These procs do a lot of hardcoded linked-list manipulation. It would be good to
// move that into dedicated structs and procedures.

find_or_add_disk_cache_entry :: (disk_address: u64) -> u64 {
    using global;

    block_index := disk_address / 0x20_0000;
    block_hash  := block_index % cast(u64) large_pages.count;

    hash_table_entry := *large_pages[block_hash];
    lru_entry        := *large_pages[hash_table_entry.lru_entry];

    Cache_Page :: (page: u64) #expand {
        page_index := cast(s32, page / 0x20_0000);

        lru_entry := *large_pages[page_index];
        lru_entry.state = .DISK_CACHE;

        `hash_table_entry.lru_current_block = `block_index;
        `hash_table_entry.lru_entry = page_index;

        if large_page_allocator.lru_most != LRU_TAIL {
            large_pages[large_page_allocator.lru_most].more_recently_used = page_index;
        }

        lru_entry.less_recently_used = large_page_allocator.lru_most;
        lru_entry.more_recently_used = LRU_TAIL;
        large_page_allocator.lru_most = page_index;

        if large_page_allocator.lru_least == LRU_TAIL {
            large_page_allocator.lru_least = page_index;
        }
    }

    if lru_entry.state != .DISK_CACHE {
        // The disk block is not in the cache.
        page := allocate_large_page();
        Cache_Page(page);

        return page;
    }

    if hash_table_entry.lru_current_block != block_index {
        // The cache entry is aliased to a different disk block. Evict it because we're more recent.
        page := cast(u64) hash_table_entry.lru_entry * 0x20_0000;
        evict_disk_cache_entry(page);
        Cache_Page(page);

        return page;
    }

    // The disk block is already in the cache.
    page_index := hash_table_entry.lru_entry;
    page := cast(u64) page_index * 0x20_0000;

    // Move the page to the front of the list.
    if lru_entry.more_recently_used != LRU_TAIL {

        more := *large_pages[lru_entry.more_recently_used];
        more.less_recently_used = lru_entry.less_recently_used;

        if lru_entry.less_recently_used != LRU_TAIL {
            less := *large_pages[lru_entry.less_recently_used];
            less.more_recently_used = lru_entry.more_recently_used;
        }

        lru_entry.less_recently_used = large_page_allocator.lru_most;
        lru_entry.more_recently_used = LRU_TAIL;

        large_pages[large_page_allocator.lru_most].more_recently_used = page_index;
        large_page_allocator.lru_most = page_index;
    }

    return page;
}

evict_disk_cache_entry :: (page: u64) #no_context {
    using global;

    page_index := page / 0x20_0000;
    lru_entry  := *large_pages[page_index];

    if lru_entry.more_recently_used != LRU_TAIL {
        more := *large_pages[lru_entry.more_recently_used];
        more.less_recently_used = lru_entry.less_recently_used;
    }

    if lru_entry.less_recently_used != LRU_TAIL {
        less := *large_pages[lru_entry.less_recently_used];
        less.more_recently_used = lru_entry.more_recently_used;
    }

    if page_index == cast,no_check(u64) large_page_allocator.lru_least {
        large_page_allocator.lru_least = lru_entry.more_recently_used;
    }

    // Todo: actually flush the data
}



get_4k_page :: () -> u64 {
    result := cast(u64)allocate_small_object(4096) - DIRECT_MAPPING_BASE;
    return result;
}

free_4k_page :: (address: u64) {
    free_small_object(cast(*void)address + DIRECT_MAPPING_BASE);
}



Page_Flags :: enum_flags u64 {
    PRESENT         :: 1 << 0 | Page_Flags.USER_SUPERVISOR;
    READ_WRITE      :: 1 << 1;
    USER_SUPERVISOR :: 1 << 2;
    WRITE_THROUGH   :: 1 << 3;
    CACHE_DISABLE   :: 1 << 4;
    ACCESSED        :: 1 << 5;
    DIRTY           :: 1 << 6;
    PAGE_SIZE       :: 1 << 7;
    EXECUTE_DISABLE :: 1 << 63;
}

decode_virtual_address :: (address: u64) -> [4]u64 {
    mask : u64 : 0x1ff;

    pt_index: [4]u64;
    pt_index[0] = (address >> 12) & mask;
    pt_index[1] = (address >> 21) & mask;
    pt_index[2] = (address >> 30) & mask;
    pt_index[3] = (address >> 39) & mask;

    return pt_index;
}

VM_Iterator :: struct {
    start_address: *void;
    page_count: int;
}

for_expansion :: (vm_it: *VM_Iterator, body: Code, flags: For_Flags) #expand {
    // Depth-first page table walker. "page_count" is how much memory you want to cover, measured in 4k pages. So if vm_it.page_count == 512 and it finds a 2MB page, it will be done after that.

    pt_index := decode_virtual_address(cast(u64) vm_it.start_address);

    `it: struct {
        level:  int; // 3=PML4, 0=PT

        // Pointer to the current entry (*table[index])
        using entry: *union {
            value: u64;
            flags: Page_Flags;
        };
    };

    `it_index: int;

    // Cache the addresses of tables above us, so we don't have to walk from the root when going up the tree. Maybe not worth it? It would make the code much simpler if we didn't do this.
    tables: [4] *u64;
    tables[3] = global.page_tables.pml4.data;

    it.level = 3;

    depth_first_go_to_next_pt_entry :: () #expand {
        if it.level != 0 && (it.flags & .PAGE_SIZE == 0) && (it.flags & .PRESENT > 0) {
            // If we're not in the lowest level, go deeper.
            it.level -= 1;

            next_table_physical_address := it.value & ~0xfff;
            tables[it.level] = cast(*u64) (next_table_physical_address + DIRECT_MAPPING_BASE);
            return;
        }

        // We just visited a page.
        small_pages_per_page_at_this_level := int.[1, 512, 262144][it.level];
        it_index += small_pages_per_page_at_this_level;

        if it_index >= vm_it.page_count {
            break;
        }

        while true {
            // Go to the next entry at the current level.
            pt_index[it.level] += 1;
            pt_index[it.level] &= 0x1ff;

            if pt_index[it.level] != 0 {
                // We are not at the end of the current table.
                break;
            } else {
                // We are at the end of the table, go up a level.
                it.level += 1;
                assert(it.level < 4); // User tried to go past the end of virtual memory.
            }
        }

        for 0..it.level-1 {
            pt_index[it] = 0;
        }
    }

    first_time := true;

    while true {
        if !first_time {
            depth_first_go_to_next_pt_entry();
        }
        first_time = false;

        // Update the iterator based on level in the PT hierarchy.
        table := tables  [it.level];
        index := pt_index[it.level];

        it.entry = xx *table[index];

        #insert body;
    }
}

map_pages :: (virtual_start: *void, physical_start: u64, page_count: int, page_flags := Page_Flags.PRESENT | .READ_WRITE) {
    for VM_Iterator.{virtual_start, page_count} {
        assert(it.flags & .PAGE_SIZE == 0);

        if it.level == 0 {
            assert(it.flags & .PRESENT == 0);

            virtual  := virtual_start  + cast(u64)it_index * 4096;
            physical := physical_start + cast(u64)it_index * 4096;

            it.value = physical;
            it.flags |= page_flags;

            pg := *virtual;
            #asm { invlpg [pg]; }

            continue;
        }

        // It's a page table, create it if it doesn't exist.
        if it.flags & .PRESENT > 0 continue;

        new_table := get_4k_page();

        it.value = new_table;
        it.flags |= .PRESENT | .READ_WRITE;
    }
}

unmap_pages :: (virtual_address: *void, count: int) {
    for VM_Iterator.{virtual_address, count} {
        assert(it.flags & .PRESENT > 0);
        assert(it.flags & .PAGE_SIZE == 0);

        if it.level != 0 continue;

        it.flags &= ~.PRESENT;
    }
}

get_physical_address :: (virtual_address: *void) -> u64, present: bool {

    {
        // Fast path if the address is in the direct mapping.
        u64_address := cast(u64)virtual_address;

        if u64_address >= DIRECT_MAPPING_BASE && u64_address < DIRECT_MAPPING_END {
            return u64_address - DIRECT_MAPPING_BASE, true;
        }
    }

    for VM_Iterator.{virtual_address, 1} {
        is_present := it.flags & .PRESENT > 0;

        if !is_present return 0, false;
        if it.level != 0 && (it.flags & .PAGE_SIZE == 0) continue;

        mask := u64.[0xfff, 0x1f_ffff, 0x3fff_ffff][it.level];

        address        := it.value & ~0xfff;
        offset_in_page := cast(u64)virtual_address & mask;

        return address + offset_in_page, is_present;
    }

    return 0, false;
}



// A block allocator that just linearly scans to find a large enough free block. Does not do the job of finding a best fit region to prevent fragmentation.
// Is being used for both virtual and physical memory, but we probably want to switch to in-band block descriptors and then make a different allocator for virtual memory.

Block_Desc :: struct {
    base: u64; // Relative to the start of the allocator's region
    size: u64;
    used: bool;
}

Block_Allocator :: struct {
    blocks: [] Block_Desc;
    max_block_descriptors: int;

    base_address: u64;
    max_size: u64;
    alignment: int;

    spinlock: Spinlock;
}

init_block_allocator :: (allocator: *Block_Allocator, base_address: u64, max_size: u64, alignment := 0) #no_context {
    // For bootstrapping, use a large page to hold block descriptors
    page := allocate_large_page();

    allocator.blocks.data = cast(*void) page + DIRECT_MAPPING_BASE;
    allocator.max_block_descriptors = 0x20_0000 / size_of(Block_Desc);

    allocator.base_address = base_address;
    allocator.max_size = max_size;
    allocator.alignment = alignment;

    allocator.blocks.count = 1;
    allocator.blocks[0] = .{
        base = 0,
        size = max_size,
        used = false,
    };
}

find_block :: (using allocator: *Block_Allocator, address: u64) -> *Block_Desc, index: int {
    assert(is_held(spinlock)); // Caller should take the lock.

    // Find the block corresponding to that address using binary search
    looking_for := address - allocator.base_address;

    l := 0;
    r := blocks.count - 1;
    m: int;

    while l <= r {
        m = (l + r) / 2;
        block_base := blocks[m].base;

        if block_base < looking_for {
            l = m + 1;
        } else if block_base > looking_for {
            r = m - 1;
        } else return *blocks[m], m;
    }

    return null, m;
}

alloc_block :: (using allocator: *Block_Allocator, unaligned_bytes_wanted: u64) -> address: u64 {

    bytes_wanted: u64;

    if alignment {
        bytes_wanted = align(alignment, unaligned_bytes_wanted);
    } else {
        bytes_wanted = unaligned_bytes_wanted;
    }

    Scoped_Acquire(*spinlock);

    for* blocks {
        if it.used continue;
        if it.size < bytes_wanted continue;

        it.used = true;

        remaining_bytes := it.size - bytes_wanted;
        it.size = bytes_wanted;

        if remaining_bytes != 0 {
            // We didn't use the whole block, make a new one and move the others over.

            if blocks.count >= max_block_descriptors-1 {
                write_string("Block allocator out of block descriptors.");
                bluescreen();
            }

            blocks.count += 1;
            for< it_index+2 .. blocks.count-1 {
                blocks[it] = blocks[it-1];
            }

            remaining_block := *blocks[it_index+1];
            remaining_block.base = it.base + bytes_wanted;
            remaining_block.size = remaining_bytes;
            remaining_block.used = false;
        }

        allocated_address := cast(u64) (base_address + it.base);

        trace(.block_alloc, allocated_address, bytes_wanted);

        return allocated_address;
    }

    // If we get here there isn't a large enough free block.

    write_string("Block allocator out of memory.");
    bluescreen();
    return 0;
}

resize_block :: (using allocator: *Block_Allocator, address: u64, new_size: u64) -> success: bool {
    Scoped_Acquire(*spinlock);

    block, m := find_block(allocator, address);

    assert(block && block.used);

    if m == blocks.count-1 {
        return false;
    }

    following_block := *blocks[m+1];

    if following_block.used {
        return false;
    }

    additional_bytes_needed := new_size - block.size;

    // We only need to check one following block, because free blocks always get coalesced.
    if following_block.size < additional_bytes_needed {
        return false;
    }

    trace(.block_resize, address, new_size);

    // There's a free block trailing the block we're trying to grow, and it's big enough to allow the resize operation.

    block.size += additional_bytes_needed;
    following_block.size -= additional_bytes_needed;
    following_block.base += additional_bytes_needed;

    if following_block.size == 0 {
        // Remove the descriptor if the whole following block was used up by the realloc.
        array_ordered_remove_by_index(*blocks, m+1);
    }

    return true;
}

free_block :: (using allocator: *Block_Allocator, address: u64) {
    Scoped_Acquire(*spinlock);

    block, m := find_block(allocator, address);

    assert(block && block.used);
    assert(block.base == address - allocator.base_address);

    trace(.block_free, address, block.size);

    block.used = false;

    // Coalesce adjacent blocks.
    following_block_is_free := blocks.count > m+1 && !blocks[m+1].used;
    preceding_block_is_free := m            > 0   && !blocks[m-1].used;

    // Todo: The two 'ordered_remove' calls each copy the rest of the blocks one position to erase a block. So we could erase them in one pass when we need to coalesce both ways.

    if following_block_is_free {
        block.size += blocks[m+1].size;
        array_ordered_remove_by_index(*blocks, m+1);
    }

    if preceding_block_is_free {
        blocks[m-1].size += block.size;
        array_ordered_remove_by_index(*blocks, m);
    }
}



Small_Objects_Allocator :: struct {
    #as using allocator: Allocator; // So we can use it with ,,
    allocator.proc = small_objects_allocator_proc;

    PAGE_SIZE :: 0x20_0000; // Using 2 meg pages because they're very quick and easy to allocate in this OS, because it's the lowest level physical allocation granularity. I would prefer 64K, but 2MB physical granularity was chosen because it's an architectural page size so can be mapped to virtual memory in one go. That fact isn't relevant to this allocator and isn't made use of anywhere else yet either, so maybe I will change it. Also, 2MB pages can be addressed using s32, since that can reach 4000 terabytes (not enough for disk but enough for RAM.)

    Page_Metadata :: struct {
        page_freelist: *Page_Metadata;
        objects_size: s16;
        freelist: s16;
        total_objects: s16;
    }

    // Make sure it fits into slot 0 of any bucket size.
    #assert size_of(Page_Metadata) <= 32;

    // Bucket sizes: 32, 64, 128, 256, 512, 1024, 2048, 4096
    bucket_freelists: [8] *Page_Metadata;

    lock: Spinlock(.IRQ); // Todo: IRQ lock because this currently gets used for the uACPI work queue.
}

small_objects_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    if mode == {
      case .RESIZE;
        assert(false, "Trying to resize a small object.");

      case .ALLOCATE;
        return allocate_small_object(size);

      case .FREE;
        free_small_object(old_memory);
    }

    return null;
}

allocate_small_object :: (size: int) -> *void {
    using global.small_objects;

    Scoped_Acquire(*lock);

    assert(size <= 4096);

    bucket_index := bit_scan_reverse(size-1);
    bucket_index = max(bucket_index - 5, 0); // This makes 32 bytes the smallest bucket.

    objects_size := cast(s16)(32 << bucket_index);

    assert(bucket_index < bucket_freelists.count, "Trying to allocate an object of size % with the small objects allocator.", size);

    // Find or allocate a page to use.
    page_freelist := *bucket_freelists[bucket_index];

    if page_freelist.* == null {
        new_page := allocate_large_page() + DIRECT_MAPPING_BASE;

        header := cast(*Page_Metadata)new_page;
        header.page_freelist = null;
        header.objects_size  = objects_size;
        header.freelist      = FREELIST_TAIL;
        header.total_objects = 0;

        page_freelist.* = header;
    }

    address := cast(*void)page_freelist.*;
    header  := cast(*Page_Metadata)address;

    metadata_size := objects_size; // Gap after Page_Metadata to keep objects aligned to their own size. This meets the worst case alignment requirement and doesn't waste any more memory.
    objects_base  := address + metadata_size;
    max_objects   := (PAGE_SIZE - metadata_size) / objects_size;

    // Find a slot within the page. First, check if there's a freelist slot.
    slot: *void;

    if header.freelist != FREELIST_TAIL {
        slot = objects_base + cast(int)header.freelist * objects_size;
        header.freelist = (.*) cast(*s16) slot;
    }

    else {
        assert(header.total_objects < max_objects);
        slot = objects_base + cast(int)header.total_objects * objects_size;
    }

    header.total_objects += 1;

    // Remove the page from the page freelist when it's full.
    if header.total_objects == max_objects {
        page_freelist.* = header.page_freelist;
        header.page_freelist = null;
    }

    trace(.small_object_alloc, slot, size);

    memset(slot, 0, size);
    return slot;
}

free_small_object :: (address: *void) {
    if address == null return;

    using global.small_objects;
    Scoped_Acquire(*lock);

    header := cast(*Page_Metadata)address & ~(PAGE_SIZE-1);
    trace(.small_object_free, address, header.objects_size);

    bucket_index := bit_scan_reverse(header.objects_size-1);
    bucket_index  = max(bucket_index - 5, 0);

    max_objects  := (PAGE_SIZE - header.objects_size) / header.objects_size;

    if header.total_objects == max_objects {
        // Add the page to the page freelist if it is full before removing this object.
        header.page_freelist = bucket_freelists[bucket_index];
        bucket_freelists[bucket_index] = header;
    }

    header.total_objects -= 1;

    if header.total_objects == 0 {
        // Get rid of the page if this was the last object stored there.
        //
        // Just walk the page freelist in order to remove this one. We could use a doubly-linked list, but
        // there are really never going to be many entries in the list, since each page can hold thousands
        // of objects, and we're not going to allocate large numbers of objects individually.
        freelist := *bucket_freelists[bucket_index];

        while true {
            if freelist.* == header {
                freelist.* = header.page_freelist;
                break;
            }

            freelist = *freelist.*.page_freelist;
            assert(freelist.* != null, "Attempting to release now-empty small objects page, but the page was not in the freelist.");
        }

        release_large_page(cast(u64)address - DIRECT_MAPPING_BASE);
    } else {
        // Insert the free slot into the page-local freelist.
        (.*) cast(*s16) address = header.freelist;

        object_offset := cast(s16)(address & (PAGE_SIZE-1));
        object_index  := (object_offset - header.objects_size) / header.objects_size;
        header.freelist = object_index;
    }
}



Maple_Tree_Node :: struct {
    // Maybe having so many nested types makes it harder to read.
    Entry_Content :: enum {
        FREE       :: 0;
        CHILD_NODE :: 1;
        VALUE      :: 2;
    }

    Entry :: enum s64 {
        content :: 2;
        unused  :: 5; // Could put search marks here.

        // We could save a lot of bits by storing nodes in an array that can be accessed by index, and then only storing the index in nonleaf nodes. But just making it work for now.
        // It would have to be a specially implemented array that just uses large pages, because I don't want this tree to have to go to the physical block allocator to get more memory,
        // because that would prevent us from:
        //   A) Using this as part of a memory debug mode where all block-allocator allocations are guarded with virtual memory guard pages by default.
        //   B) Using this when block allocator physical memory runs out / is too fragmented to support a large allocation. Don't really care about this case that much.
        address :: 57;
    }

    Meta :: enum s64 {
        entry_count    :: 3;
        unused         :: 4;
        parent_address :: 57;
    }

    meta: Meta;

    pivots:  [7] s64;
    entries: [8] Entry;
}

#assert size_of(Maple_Tree_Node) == 128; // Two cache lines for now.

Maple_Tree_Node_Expanded :: struct {
    #as using node: *Maple_Tree_Node;

    // This struct keeps track of this information which comes from the parent node, as you walk the tree.
    implicit_min: s64;
    implicit_max: s64;
}

each_range :: (node: *Maple_Tree_Node_Expanded, body: Code, flags: For_Flags) #expand {
    #assert !(flags & .REVERSE);
    #assert !(flags & .POINTER);

    `it_index := -1;

    `it_min: s64;
    `it_max: s64;

    `it: *Maple_Tree_Node.Entry;

    entry_count := get(node.meta, .entry_count);

    while true {
        if it_index == entry_count-1 {
            break;
        }

        it_index += 1;
        it = *node.entries[it_index];

        if it_index == 0 {
            it_min = node.implicit_min;
        } else {
            it_min = node.pivots[it_index-1];
        }

        if it_index == entry_count-1 {
            it_max = node.implicit_max;
        } else {
            it_max = node.pivots[it_index] - 1;
        }

        #insert body;
    }
}

maple_add :: (node: *Maple_Tree_Node_Expanded, range_min: s64, range_max: s64, value: *void) {
    assert(range_min <= range_max);

    for :each_range node {
        // Find the child node or entry that currently contains this range.

        if it_max < range_min {
            // The wanted range is entirely to the right of this entry.
            continue;
        }

        // If we get here we know that at least the left half of the range we want overlaps with this entry.
        // But it might overlap multiple entries, which in my version of the tree is not allowed. e.g.
        //
        // Wanted:  |        |xxx|           |
        // Entries: |  |  | it |   |     |   |
        // it_max:             ^
        //
        assert(it_max >= range_max);

        // This entry should be free or a child node.
        content := cast(Maple_Tree_Node.Entry_Content) get(it.*, .content);
        assert(content != .VALUE);

        if content == .CHILD_NODE {
            // If it's a child node, recurse into it.
            child_address := get_in_place(it.*, .address);

            child: Maple_Tree_Node_Expanded;
            child.node = cast(*Maple_Tree_Node) child_address;
            child.implicit_min = it_min;
            child.implicit_max = it_max;

            maple_add(*child, range_min, range_max, value);
            return;
        }

        if it_min == range_min && it_max == range_max {
            // If it matches exactly, we can just use this range without splitting it.

            set_in_place(it, .address, cast(s64)value);
            set(it, .content, cast(s64)Maple_Tree_Node.Entry_Content.VALUE);

            return;
        }

        // If we get here we need to move the entries and pivots, to make room for either one or two new entries, depending.
        new_entries_needed: int;

        if it_min != range_min new_entries_needed += 1;
        if it_max != range_max new_entries_needed += 1;

        entry_count := get(node.meta, .entry_count);
        new_entry_count := entry_count + new_entries_needed;

        // This would split the node. Todo.
        assert(new_entry_count <= 8);

        // Move the entries after this one over.
        start := it_index + new_entries_needed + 1; // The lowest entry that we move other entries to.

        for< start..new_entry_count-1 {
            node.entries[it] = node.entries[it - new_entries_needed];
        }

        entry_to_fill := it_index;

        if it_min != range_min {
            // We need a free entry before the one we want to add.
        }
    }

    // If we get here, the range is not represented in the tree at all. This is a bug in the tree code.
    assert(false);
}



// A temporary system to help detect memory bugs.

Guarded_Allocation :: struct {
    client_address: *void; // The part of the allocation the caller can use normally.

    physical_base: u64;    // So the allocator knows how to free the physical memory.
    virtual_base: *void;   // So the allocator knows how to free the virtual memory.
    physical_pages: int;

    created_at: Source_Code_Location; // So the page fault handler can report who created the guard region when it's accessed.
}

allocate_guarded_memory :: (size: int, guard_region_size: int, caller_location := #caller_location) -> *void {
    using global.guarded_memory;

    assert(size              % 4096 == 0, "Guarded allocation size must be a multiple of 4KB.");
    assert(guard_region_size % 4096 == 0, "Guarded allocation size must be a multiple of 4KB.");

    // Physical block allocator doesn't return page aligned memory, so worst case we have to offset by 4095 bytes to align the returned memory.
    padded_size  := size + 4095;
    virtual_size := padded_size + 2 * guard_region_size; // Put guard regions on both sides because why not?

    physical := alloc_block(*global.physical_block_allocator, cast(u64) padded_size);
    virtual  := alloc_block(*global.virtual_block_allocator,  cast(u64) virtual_size);

    physical_pages    := padded_size / 4096;
    physical_aligned  := align(4096, physical);
    client_address    := cast(*void) virtual + guard_region_size;

    map_pages(client_address, physical_aligned, physical_pages);

    {
        node := New(allocations.Node,, global.small_objects);

        node.created_at      = caller_location;
        node.physical_base   = physical;
        node.virtual_base    = cast(*void) virtual;
        node.physical_pages  = physical_pages;
        node.client_address  = client_address;

        acquire(*spinlock);
        queue_push(*allocations, node);
        release(*spinlock);
    }

    return client_address;
}

free_guarded_memory :: (client_address: *void) {
    using global.guarded_memory;

    guarded: Guarded_Allocation;

    acquire(*spinlock);

    for* allocations if it.client_address == client_address {
        guarded = it.item;
        remove it;
        break;
    }

    release(*spinlock);

    assert(guarded.client_address != null);

    unmap_pages(guarded.client_address, guarded.physical_pages);

    free_block(*global.physical_block_allocator,           guarded.physical_base);
    free_block(*global.virtual\_block_allocator, cast(u64) guarded.virtual_base);
}

find_guarded_memory :: (address: *void) -> *Guarded_Allocation {
    using global.guarded_memory;

    assert(is_held(spinlock), "Caller should take the lock.");

    for* allocations {
        // Calculate the total number of pages by comparing the base address of the whole virtual memory region to the client address. We could also just store this number with the other alloction info.

        guard_region_size  := cast(u64) (it.client_address - it.virtual_base);
        guard_region_pages := cast(int) (guard_region_size * 2 / 4096);

        total_pages := it.physical_pages + guard_region_pages;

        base  := it.virtual_base;
        limit := it.virtual_base + total_pages * 4096;

        if base <= address && address < limit {
            return *it.item;
        }
    }

    return null;
}

guarded_memory_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    DEFAULT_GUARD_REGION :: 0x1_0000;

    if mode == {
      case .RESIZE;
        new_memory := allocate_guarded_memory(size, DEFAULT_GUARD_REGION);

        if old_memory {
            memcpy(new_memory, old_memory, old_size);
            free_guarded_memory(old_memory);
        }

        return new_memory;

      case .ALLOCATE;
        return allocate_guarded_memory(size, DEFAULT_GUARD_REGION);

      case .FREE;
        free_guarded_memory(old_memory);
    }

    return null;
}



Serial_Port :: struct (base_address: u16) {
    spinlock: Spinlock(.IRQ);
}

serial_out :: (data: string, using serial_port: *Serial_Port) #no_context {
    acquire(*spinlock);

    for data {
        for 1..10_0000 {
            status: u8;
            port := base_address + 5;

            #asm {
                status === a;
                port   === d;
                in.b status, port;
            }

            if status & 0x20 break;

            #asm { pause; }
        }

        byte := it;
        port := base_address;

        #asm {
            byte === a;
            port === d;
            out.b port, byte;
        }
    }

    release(*spinlock);
}



kernel_write_string :: (text: string) #no_context {
    serial_out(text, *global.COM1);
    draw_text(text);
}


barrier :: () #expand {
    #asm { mfence; }
}



fetch_add :: (value: *$T, add: T) -> T #no_context {
    #asm {
        lock_xadd?T [value], add;
    }
    return add;
}

fetch_store :: (target: *$T, value: T) -> old_value: T #no_context {
    #asm {
        lock_xchg?T value, [target];
    }
    return value;
}



preempt_disable :: () -> int #no_context {
    offset := offset_of(X64_Core, "preempt_disable_count");
    gs_relative_inc(offset);

    return 0;
}

preempt_restore :: (expected: int, loc := #caller_location) #no_context {
    offset := offset_of(X64_Core, "preempt_disable_count");
    gs_relative_dec(offset);
}

get_rflags :: () -> X64_Flags #foreign Assembly;

irq_disable :: () -> bool #no_context {
    flags := get_rflags();
    was_enabled := flags & .IF__interrupt > 0;

    #asm { cli; }

    trace(.irq_disable, was_enabled);
    return was_enabled;
}

irq_restore :: (was_enabled: bool) #no_context {
    trace(.irq_restore, was_enabled);
    if was_enabled {
        #asm { sti; }
    }
}



// Things that have 'acquire' and 'release' procedures defined. For use with polymorphic type restrictions.
Any_Lock :: Type.[MCS_Spinlock, Spinlock(.RAW), Spinlock(.PREEMPT), Spinlock(.IRQ), Mutex];



// Lock type (like "irqsave") is a static property of the spinlock type and IRQ/preempt state is stored with the lock. Other operating systems don't do this, they make the caller do everything. Not sure which is better. Todo: We could store IRQ state in CPU local data, same as preempt state.
Lock_Type :: enum {
    RAW     :: 1;
    PREEMPT :: 2;
    IRQ     :: 3;
}

Spinlock :: struct (lock_type := Lock_Type.PREEMPT) {
    now_serving: u16;
    next_ticket: u16;

    #if lock_type == .IRQ {
        irq_state: bool; // Todo: this could go in the high bit of one of the fields above to save cache space. Or as a counter in CPU local data.
    }
}

is_held :: (lock: Spinlock) -> bool #no_context {
    // Todo: Maybe should verify who the holder is in debug builds.
    return lock.now_serving != lock.next_ticket;
}

acquire :: (lock: *Spinlock) #no_context {
    #if lock.lock_type == {
        case .PREEMPT; preempt_disable();
        case .IRQ;     lock.irq_state = irq_disable();
    }

    my_ticket := fetch_add(*lock.next_ticket, 1);

    {
        // Detect issues with how spinlocks are used. This code is only for development.

        contention_level := my_ticket - lock.now_serving;
        if contention_level > 0 {
            trace(.contended_spinlock, contention_level);
        }

        offset := offset_of(X64_Core, "interrupt_context_active");
        interrupt_context_active := cast(int)gs_relative_read(offset);

        if interrupt_context_active > 0 && lock.lock_type != .IRQ {
            push_context { assert(false, "Non-IRQ lock used in interrupt context."); }
        }
    }

    while lock.now_serving != my_ticket {
        #asm { pause; }
    }
}

release :: (lock: *Spinlock) #no_context {
    lock.now_serving += 1;

    #if lock.lock_type == {
        case .PREEMPT; preempt_restore(0 /* Todo */);
        case .IRQ;     irq_restore(lock.irq_state);
    }
}

Scoped_Acquire :: (lock: *Spinlock) #expand {
    acquire(lock);
    `defer release(lock);
}



// MCS lock based on https://web.archive.org/web/20140411142823/http://www.cise.ufl.edu/tr/DOC/REP-1992-71.pdf

MCS_Node :: struct {
    next: *MCS_Node;
    blocked: bool;
    irq_state: bool;
}

MCS_Spinlock :: *MCS_Node;

acquire :: (lock: *MCS_Spinlock) #no_context {
    irq_state := irq_disable();

    core := get_current_core();
    my_node := *core.mcs_node;

    my_node.irq_state = irq_state;
    my_node.next = null;

    prev := fetch_store(lock, my_node);

    if prev {
        trace(.contended_spinlock);

        my_node.blocked = true;
        prev.next = my_node;

        while my_node.blocked {
            #asm { pause; }
        }
    }
}

release :: (lock: *MCS_Spinlock) #no_context {

    core := get_current_core();
    my_node := *core.mcs_node;

    if !my_node.next {
        if compare_and_swap(lock, my_node, null) {
            irq_restore(my_node.irq_state);
            return;
        }

        while !my_node.next {
            #asm { pause; }
        }
    }

    my_node.next.blocked = false;
    irq_restore(my_node.irq_state);
}



Sequence_Lock :: #type,distinct u32;

sequence_read :: (lock: *Sequence_Lock, body: Code) #expand {
    while true {
        sequence: Sequence_Lock;

        while true {
            sequence = lock.*;

            if !(sequence & 1) break;

            #asm { pause; }
        }
        barrier(); // These fences are full hardware barriers, but in fact on modern x64, only compiler barriers are needed. Not sure if they are needed in Jai, or how to insert them.

        #insert body;

        barrier();
        if lock.* == sequence break;
    }
}

sequence_write :: (lock: *Sequence_Lock, body: Code) #expand {
    lock.* += 1;
    barrier();

    #insert body;

    barrier();
    lock.* += 1;
}



FREELIST_TAIL :: -1;
LRU_TAIL      :: -1;



allocate_interrupt_gate :: () -> int {
    using global;

    assert(next_free_interrupt_gate < 0xff);

    result := next_free_interrupt_gate;
    next_free_interrupt_gate += 1;
    return result;
}



// These are mainly used by drivers when waiting for a response from the device. Maybe they should yield when the timeout is long.

Timeout_Block :: (code: Code, time_ms := 1000) -> bool #expand {
    start := get_monotonic_system_time();

    while true {
        #insert code;
        elapsed := get_monotonic_system_time() - start;

        if to_milliseconds(elapsed) > time_ms {
            return true;
        }

        #asm { pause; }
    }

    return false;
}

Timeout :: (code: Code, time_ms := 1000) -> bool #expand {
    start := get_monotonic_system_time();

    while true {
        condition_met := #insert code;
        if condition_met break;

        elapsed := get_monotonic_system_time() - start;

        if to_milliseconds(elapsed) > time_ms {
            return true;
        }

        #asm { pause; }
    }

    return false;
}



Terse_Print_Style :: struct {
    #as using ps: Print_Style;

    SHARED_FIELDS :: string.["value", "formatter"];

    using,except SHARED_FIELDS ps.default_format_int;
    using,except SHARED_FIELDS ps.default_format_float;
    using,except SHARED_FIELDS ps.default_format_struct;
}

push_print_style :: (style := context.print_style) -> *Terse_Print_Style #expand {
    // User may choose whether to use the input argument, return value, or neither

    old := context.print_style;
    `defer context.print_style = old;

    context.print_style = style;
    return cast(*Terse_Print_Style) *context.print_style;
}

hex :: #bake_arguments formatInt(base=16);
dec :: #bake_arguments formatInt(base=10);

#add_context log_category: string;

log_category :: (category: string) #expand {
    old := context.log_category;
    context.log_category = category;
    `defer context.log_category = old;
}



font_file :: #run,host -> [] u8 {
    image := read_entire_file("font.pgm");
    return add_global_data(cast([] u8) image, .READ_ONLY);
}

draw_text :: (text: string) #no_context {
    using global.text_drawing_state;

    if !font_loaded return;

    acquire(*spinlock);

    line_spacing :: 5;   // Number of pixels between the bottom of one character cell, and the top of the next one down.
    char_width   :: 9;
    char_height  :: 16;
    margin       :: 10;

    line_height  :: char_height + line_spacing;

    // The lowest and highest ASCII codes that are included in the font bitmap.
    first_code   :: #char " ";
    last_code    :: #char "~";

    framebuffer := global.framebuffer;

    for text {
        if it == #char "\n" {
            cursor_y += 1;
            cursor_x = 0;
            continue;
        }

        if it == #char "\r" continue;

        if it < first_code || it > last_code {
            it = #char "?";
        }

        max_x := (cursor_x + 1) * char_width + margin * 2;

        if max_x >= framebuffer.x_resolution {
            cursor_y += 1;
            cursor_x = 0;
        }

        screen_x := cursor_x * char_width + margin;
        screen_y := cursor_y * line_height + margin;

        while screen_y + line_height + margin > framebuffer.y_resolution {
            source := (line_height + margin) * framebuffer.stride;
            target := margin * framebuffer.stride;

            count := cursor_y * line_height * framebuffer.stride;

            // Inefficient when printing strings with many newlines.
            memcpy(framebuffer.buffer + target, framebuffer.buffer + source, count * size_of(u32));

            cursor_y -= 1;
            screen_y -= line_height;
        }

        source_top_left := char_width * (cast(int) it - first_code);
        target_top_left := screen_x + screen_y * framebuffer.stride;

        for char_y: 0..char_height-1 {
            for char_x: 0..char_width-1 {

                pixel_in_font   := source_top_left + char_x + char_y * font.width;
                pixel_on_screen := target_top_left + char_x + char_y * framebuffer.stride;

                c := cast(u32) font.data[pixel_in_font];

                red   := cast(int) (0xa0 * (1.0 / framebuffer.y_resolution) * (screen_y + char_y));
                green := cast(int) (0xa0 * (1.0 / framebuffer.x_resolution) * (screen_x + char_x));

                framebuffer.buffer[pixel_on_screen]  = (c) | (c << 8) | (c << 16) | (c << 24);
            }
        }

        cursor_x += 1;
    }

    release(*spinlock);
}

Netpbm_Image :: struct {
    width: int;
    height: int;

    type: enum {
        UNINITIALIZED :: 0;
        ASCII_BITMAP;
        ASCII_GRAYMAP;
        ASCII_PIXMAP;
        BITMAP;
        GRAYMAP;
        PIXMAP;
    }

    data: *u8;
}

parse_netpbm :: (file: [] u8) -> Netpbm_Image {
    buffer := file.data;
    assert(buffer[0] == #char "P");

    image: Netpbm_Image;
    image.type = xx (buffer[1] - #char "0");
    assert(image.type == .GRAYMAP || image.type == .PIXMAP);

    is_whitespace :: (char: u8) -> bool {
        return char == 0x20
            || char == 0x09
            || char == 0x0a
            || char == 0x0b
            || char == 0x0c
            || char == 0x0d
            || char == #char "#";
    }

    skip_whitespace_and_comments :: () #expand {
        while is_whitespace(buffer[`cursor]) {
            if buffer[`cursor] == #char "#" {
                while buffer[`cursor] != 0xa `cursor += 1;
            }
            cursor += 1;
        }
    }

    parse_int :: () -> int #expand {
        digit := buffer[`cursor];
        result: int;

        while !is_whitespace(digit) {
            assert(digit >= #char "0" && digit <= #char "9");
            result *= 10;
            result += digit - #char "0";
            `cursor += 1;
            digit = buffer[`cursor];
        }
        return result;
    }

    cursor := 2;
    skip_whitespace_and_comments();

    image.width = parse_int();

    skip_whitespace_and_comments();

    image.height = parse_int();

    skip_whitespace_and_comments();

    max_value := parse_int();
    assert(max_value == 255);

    skip_whitespace_and_comments();

    image.data = buffer + cursor;

    return image;
}





align :: (alignment: $T, value: $V) -> V {
    #assert size_of(T) == 8;
    #assert size_of(V) == 8;

    return cast(V) align(cast(int) alignment, cast(int) value);
}

align :: (alignment: int, value: int) -> int {
    if alignment == 0 return value;

    // This only works for powers of two.
    assert(alignment & (alignment-1) == 0);

    return (value + (alignment - 1)) & -alignment;
}

bit_cast :: (object: $T, $target_type: Type) -> target_type {
    return (.*) cast(*target_type) *object;
}

offset_of :: ($T: Type, $member: string) -> s64 #no_context {
    BODY :: #string DONE
    dummy: T = ---;
    return cast(*void) (*dummy.%) - cast(*void) *dummy;
    DONE

    #insert #run sprint(BODY, member);
}

fill_random :: (buffer: []u8) {
    u64_buffer: []u64;
    u64_buffer.count = buffer.count / 8;
    u64_buffer.data  = cast(*u64)buffer.data;

    for* u64_buffer it.* = random_get();

    remainder := buffer.count % 8;
    for 0..remainder-1 {
        buffer[buffer.count-remainder + it] = xx random_get();
    }
}

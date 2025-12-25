
#import "Basic";

#import "Machine_X64";
using,except(byte_swap_in_place) _ :: #import "Bit_Operations";
#import "Hash_Table";
#import "String";
#import "Random";
#import "Hash";

#import "Bitfield"(true);

set :: bitfield_set;
get :: bitfield_get;
set_bit :: bitfield_set_bit;
get_bit :: bitfield_get_bit;

#import "Ring_Buffer";
#import "ASN1";
#import "Aes";
#import "Jai_Crypto";

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

    // Align to cache block so no extra memory accesses are required on context switch.
    global_descriptor_table: Global_Descriptor_Table #align 64;

    local_apic_id: u32;
    id: int; // ID 0 is the bootstrap core.

    scheduler: Scheduler;

    preempt_disable_count: int;

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

    large_page_allocator: Large_Page_Allocator;

    physical_page_pool: Physical_4k_Page_Pool(1024);
    physical_block_allocator: Block_Allocator;
    virtual_block_allocator: Block_Allocator;

    root_acpi_table: *Acpi_Table_Header;
    acpi_version: int;
    fadt: *acpi_fadt;

    uacpi_state: Uacpi_State;

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

        spinlock: Spinlock;

        font_loaded: bool;
    }

    COM1: Serial_Port(0x3f8); // Used for writing to log files and the host console on VirtualBox and QEMU.
    COM2: Serial_Port(0x2f8); // Used for writing trace data.

    text_output_spinlock: Recursive_Spinlock; // Used to prevent multiple calls to write_string from different cores becoming interleaved.

    network_connection: Network_Connection;

    pci_ecam: [] Ecam_Entry;
    pci_routing_table: [] uacpi_pci_routing_table_entry;

    first_context: *#Context; // To have access to calls stacks early in boot.
}

global: Kernel_Globals;

Assembly :: #library,no_dll "../.build/assembly";

#program_export
kernel_entry :: () #no_context {
    using global;

    write_string_callback = kernel_write_string;

    set_global_context_callbacks();

    // We should avoid using the UEFI identity map because we'll need to get rid of it once we run user processes in low memory.
    boot_data = cast(*Boot_Data, Boot_Data.BASE_ADDRESS + DIRECT_MAPPING_BASE);

    // Used for AP bootstrap.
    large_pages[0].state = .RESERVED;

    memory_map_index: int;
    for* page, page_index: large_pages {

        page_base  := page_index * 0x20_0000;
        page_limit := page_base  + 0x20_0000;

        for memory_map_index..memory_map_entries_used-1 {

            region := memory_map[it];
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


    large_page_allocator.freelist = FREELIST_TAIL;
    large_page_allocator.lru_least = LRU_TAIL;
    large_page_allocator.lru_most  = LRU_TAIL;

    // Let's init tracing as early as possible (as soon as physical memory allocation is available) so we can trace whatever we eventually want.
    init_tracing();

    // Todo: hardcoded.

    for region: memory_map {
        if !it_index continue;
        region_size := region.pages * 4096;

        if region_size >= 0x200_0000 && region.type == .FREE {
            first_page := region.address / 0x20_0000;

            for first_page..first_page+32 {
                large_pages[it].state = .RESERVED;
            }

            init_block_allocator(*physical_block_allocator, region.address, 0x200_0000, 0x10);
            break;
        }
    }

    if physical_block_allocator.base_address == 0 {
        write_string("Could not find enough memory for the kernel...\n");
        while true #asm { cli; hlt; }
    }


    push_context {
        global.first_context = *context;

        using framebuffer;

        for y: 0..y_resolution-1 {
            for x: 0..x_resolution-1 {
                red   := cast(int, 0xff * (1.0 / y_resolution) * y);
                green := cast(int, 0xff * (1.0 / x_resolution) * x);

                // buffer[x + y * stride] = cast(u32, (red << 16) | (green << 8));
                buffer[x + y * stride] = 0;
            }
        }

        {
            // Init virtual memory heap.
            GB :: 0x4000_0000;
            direct_mapping_size := cast(u64) boot_data.page_tables.direct_pd.count * GB;

            heap_base: u64 = DIRECT_MAPPING_BASE + direct_mapping_size;
            heap_size: u64 = 64 * GB;

            // Keep virtual allocations page aligned, since virtual memory always needs to be mapped anyway.
            init_block_allocator(*virtual_block_allocator, heap_base, heap_size, alignment=4096);
        }

        {
            // Sequentially allocating interrupt gates, starting after the ISA exceptions
            memset(interrupt_descriptor_table.data, 0, size_of(type_of(interrupt_descriptor_table)));
            next_free_interrupt_gate = 32;
        }

        rsdp := cast(*Acpi_Rsdp) boot_data.acpi_rsdp;
        acpi_version = rsdp.revision;

        assert(acpi_version == 0 || acpi_version == 2);

        if acpi_version >= 2 {
            root_acpi_table = xx (rsdp.xsdt_address + DIRECT_MAPPING_BASE);
        } else {
            root_acpi_table = xx (rsdp.rsdt_address + DIRECT_MAPPING_BASE);
        }

        text_drawing_state.font = parse_netpbm(font_file);
        text_drawing_state.font_loaded = true;

        initialize_apic();

        initialize_hpet();
        hpet_configure_timer(timer_index = 0, frequency = 10, true);


        rtc_init();

        // Get the time at the most recent second. Maybe we can use an interrupt to detect boot time more accurately.
        boot_calendar_time := rtc_get_calendar_time();

        // Don't use Basic.calendar_to_apollo, because it's OS specific
        boot_time = native_calendar_to_apollo(boot_calendar_time);

        initialize_tsc();

        assert(get_rflags() & .IF__interrupt == 0); // We don't want interrupts to be enabled while we're initializing multitasking.

        core_begin_multitasking();

        // Todo: system time alone is too low entropy for OS random number generation.
        time := get_monotonic_system_time();
        random_seed(cast(S128)time);

        initialize_uacpi();
        find_all_pci_devices();

        startup_application_processors();

        for *core: processor_cores {
            while !core.online pause();
        }

        #asm { sti; }

        for* pci_devices {

            if false if it.class_code == .MASS_STORAGE {
                if it.subclass == {
                    case 0x8; init_nvme_controller(it);
                    case 0x6; init_ahci_controller(it);
                }
            }

            if it.class_code == .NETWORK && it.subclass == 0x0 {
                global.network_connection.adapter = init_i8254x(it);
            }

            if false if it.class_code == .MULTIMEDIA {
                if it.subclass == 0x3 {
                    init_high_definition_audio_controller(it);
                }
            }
        }

        // user_mode_stress_test();
        // semaphore_test();
        network_test();

        while true {
            schedule_tasks();
            #asm { sti; hlt; }
        }
    }
}

semaphore_test :: () {

    User_Data :: struct {
        sem: Semaphore;
        holders: int;
    }

    user_data := New(User_Data);
    user_data.sem.counter = 2;

    proc :: () {
        task := get_current_task();
        data := cast(*User_Data) task.user_data;

        while true {
            us := cast(s64)rdtsc() % 1_000_000;
            busy_wait(us);

            log("[%] Trying to take the semaphore.", task.name);

            us = cast(s64)rdtsc() % 200_000;
            if wait_for(*data.sem, microseconds_to_apollo(us)) {
                data.holders += 1;
                log("[%] Got the semaphore. Holders: %", task.name, data.holders);

                us := cast(s64)rdtsc() % 500_000;
                busy_wait(us);

                data.holders -= 1;
                signal(*data.sem);
            } else {
                log("[%] Timed out after %ms", task.name, us / 1000);
            }
        }
    }

    thread_index := 1;

    #asm { sti; }

    for *core: global.processor_cores {
        for 1..2 {
            name := tprint("Sem test %:%", core.id, thread_index);
            task := create_task(proc, kernel_stack_size = 0x4_0000, name = name, user_data = user_data);
            put_task_on_core(task, core);

            thread_index += 1;
        }
    }
}

user_mode_stress_test :: () {
    thread_index := 1;

    for *core: global.processor_cores {
        // if core.id != 0 continue;

        for 1..4 {
            name := tprint("Do Work %:%", core.id, thread_index);
            task := create_task(task_do_work, kernel_stack_size = 0x4_0000, user_stack_size = 0x4_0000, name = name);
            put_task_on_core(task, core);

            thread_index += 1;
        }
    }
}

network_test :: () {
    USE_DNS :: false;

    log_category("Test");

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
        log("Sending DNS Query");
        dns_query := transmit_dns_query(net, "discord.com");

        if Timeout(dns_query.complete, 60_000) {
            bluescreen();
        }

        ip_address = dns_query.answer;
        port = 443;
    }

    transmit_ping(net, ip_address);

    connection := initiate_tcp_connection(net, ip_address, port);

    Timeout(connection.handshake_state == .ESTABLISHED, 60_000);

    tls := establish_tls_connection(connection);

    request := tprint(HTTP_MESSAGE, HTTP_CONTENT.count, HTTP_CONTENT, "");
    request = "GET /server.py HTTP/1.1\r\nHost: thinkpad\r\nAccept: text/x-python\r\n\r\n";

    tls_transmit_application_data(*tls, request);

    for 1..2 {
        response := tls_receive_application_data(*tls);
        log("Got HTTPS response: %", response);
    }

    // Todo: TLS Close Notify.

    tcp_close(connection);
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



#program_export
floating_point_exception :: (stack: *Interrupt_Stack_Frame()) #c_call {
    mxcsr: Mxcsr;
    pmxcsr := *mxcsr;

    #asm {
        stmxcsr [pmxcsr];
    }

    push_context {
        core := get_current_core();
        log("Floating point exception: % (thread %)\n", mxcsr, core.scheduler.current_task.id);
    }
} @InterruptRoutine

set_global_context_callbacks :: () #no_context {
    // These are default context values in our custom Runtime_Support module, such that they get used by default initalized context structs.

    kernel_assertion_failed = (location: Source_Code_Location, message: string) -> bool {
        acquire(*global.text_output_spinlock);

        write_string("Assertion failure");
        if message.count {
            write_strings(": ", message);
        }
        write_string("\n");

        bluescreen(location);

        release(*global.text_output_spinlock);
        return true;
    };

    kernel_default_logger = (message: string, data: *void, info: Log_Info) {
        Scoped_Acquire(*global.text_output_spinlock);

        if context.log_category {
            write_string("[");
            write_string(context.log_category);
            write_string("] ");
        }

        if info.common_flags & .ERROR {
            write_string("ERROR: ");
        }

        write_string(message);

        if message[message.count-1] != #char "\n" {
            write_string("\n");
        }
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
        if !core bluescreen();

        #asm FSGSBASE { wrgsbase core; }
    }

    {
        // Global descriptor table

        // Use the IO Permission Bitmap to give user mode access to all IO ports for now
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
        // Interrupt descriptor table
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
        // Enable syscalls

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
        // Spurious interrupts

        register_interrupt_gate(isr__spurious_interrupt, 0xff);
        spurious := read_apic_register(.SPURIOUS_INTERRUPT);
        write_apic_register(.SPURIOUS_INTERRUPT, spurious | 0x1ff); // Todo magic number
    }
}

#program_export
spurious_interrupt :: (stack: Interrupt_Stack_Frame()) #c_call {
    write_string("Spurious...\n");
} @InterruptRoutine

bluescreen :: (loc := #caller_location) #no_context {
    disable_interrupts();

    write_string("\nBluescreen!\n");

    stack_trace: *Stack_Trace_Node;

    if global.multiprocessing_initialized {
        task := get_current_task();
        stack_trace_is_available := task && task._context && task._context.stack_trace;

        if stack_trace_is_available {
            stack_trace = task._context.stack_trace;
        }
    }

    else if global.first_context {
        stack_trace = global.first_context.stack_trace;
    }

    if stack_trace && false {
        push_context {
            print_stack_trace(global.first_context.stack_trace);
        }
    } else {
        write_string("Source code location:\n");
        write_loc(loc);
        write_string("\n");
    }

    if false {
        // Temporary hack to make debugging easier. If one core dies and leaks
        // the serial port spinlock, other CPU cores should still be able to
        // keep running.

        lock := *global.text_output_spinlock;
        core := get_current_core();

        if is_held(lock.lock) && lock.held_by_core == core.id {
            lock.recursion_count = 0;
            release(lock);
        }
    }

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
    freelist: int;

    lru_least: s32;
    lru_most:  s32;

    spinlock: Recursive_Spinlock;
}

allocate_large_page :: (loc := #caller_location) -> u64 #no_context {

    using global.large_page_allocator;
    Scoped_Acquire(*spinlock);

    if freelist != FREELIST_TAIL {
        address := freelist * 0x20_0000;

        desc := *global.large_pages[freelist];
        desc.state = .ALLOCATED;
        freelist = desc.freelist;

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

    // There's no free memory
    bluescreen(loc);
    return 0;
}

// These procs do a lot of hardcoded linked-list manipulation. It would be good to
// move that into dedicated structs and procedures.

find_or_add_disk_cache_entry :: (disk_address: u64) -> u64 {
    using global;

    Scoped_Acquire(*large_page_allocator.spinlock);

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
        // The disk block is not in the cache
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

    // The disk block is already in the cache
    page_index := hash_table_entry.lru_entry;
    page := cast(u64) page_index * 0x20_0000;

    // Move the page to the front of the list
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



Physical_4k_Page_Pool :: struct(page_count: int) {
    freelist: [page_count] s32;
    freelist_length: s32;
    highest_used: s32;

    large_pages: [(page_count+511) / 512] struct {
        index: s32;
        used: s32;
    };

    large_pages_used: s32;

    spinlock: Spinlock;
}

page_pool_index_to_address :: (pool: *Physical_4k_Page_Pool, index: s32) -> u64 #no_context {
    large_page_index := index / 512;
    page_index       := index % 512;

    large_page := *pool.large_pages[large_page_index];

    if pool.large_pages_used <= large_page_index {
        large_page.index = cast(s32, allocate_large_page() / 0x20_0000);
        pool.large_pages_used += 1;
    }

    large_page.used += 1;

    address := cast(u64) large_page.index * 0x20_0000;
    address += cast(u64) page_index * 4096;

    return address;
}

get_4k_page :: () -> u64 #no_context {
    return get_4k_page(*global.physical_page_pool);
}

get_4k_page :: (pool: *Physical_4k_Page_Pool) -> u64 #no_context {
    using pool;
    Scoped_Acquire(*spinlock);

    if freelist_length != 0 {
        freelist_length -= 1;

        page_index := freelist[freelist_length];
        address    := page_pool_index_to_address(pool, page_index);

        return address;
    }

    if highest_used >= page_count {
        bluescreen();
    }

    address := page_pool_index_to_address(pool, highest_used);
    highest_used += 1;

    return address;
}

free_4k_page :: (pool: *Physical_4k_Page_Pool, address: u64) #no_context {
    // Todo
}

free_4k_page :: (address: u64) #no_context {
    free_4k_page(*global.physical_page_pool, address);
}



get_or_create_page_table :: (table: *u64, entry: u64) -> *u64 {
    using Page_Flags;

    is_page := cast(u64, table) & xx PAGE_SIZE;
    if is_page {
        // The page table to which we're trying to add a lower level child table is actually a large or huge page.
        assert(false);
    }

    if table[entry] & xx PRESENT {
        physical := table[entry] & (~0xfff);
        return cast(*u64, physical + DIRECT_MAPPING_BASE);
    }

    address := get_4k_page();

    table[entry] = address | xx PRESENT | READ_WRITE;

    virtual_address := cast(*u64, address + DIRECT_MAPPING_BASE);
    memset(virtual_address, 0, 4096);

    return virtual_address;
}

map_page :: (virtual_address: *void, physical_address: u64, flags := Page_Flags.PRESENT | .READ_WRITE, loc := #caller_location) {
    map_page(cast(u64) virtual_address, physical_address, flags, loc);
}

map_page :: (virtual_address: u64, physical_address: u64, flags := Page_Flags.PRESENT | .READ_WRITE, loc := #caller_location) {
    mask: u64 = 0b111111111;

    pml4_offset := (virtual_address >> 39) & mask;
    pdpt_offset := (virtual_address >> 30) & mask;
    pd\ _offset := (virtual_address >> 21) & mask;
    pt\ _offset := (virtual_address >> 12) & mask;

    pml4 := global.page_tables.pml4.data;

    pdpt := get_or_create_page_table(pml4, pml4_offset);
    pd   := get_or_create_page_table(pdpt, pdpt_offset);
    pt   := get_or_create_page_table(pd,   pd_offset);

    if pt[pt_offset].(Page_Flags) & .PRESENT {
        log("%", hex(pt.(u64) - DIRECT_MAPPING_BASE));
        bluescreen(loc);
    }

    pt[pt_offset] = physical_address | cast(u64) flags;

    pg := *virtual_address;
    #asm {
        invlpg [pg];
    }
}

Page_Flags :: enum_flags u64 {
    PRESENT         :: 1 << 0 | Page_Flags.USER_SUPERVISOR;
    READ_WRITE      :: 1 << 1;
    USER_SUPERVISOR :: 1 << 2;
    WRITE_THROUGH   :: 1 << 3;
    CACHE_DISABLE   :: 1 << 4;
    ACCESSED        :: 1 << 5;
    AVAILABLE       :: 1 << 6;
    PAGE_SIZE       :: 1 << 7;
    EXECUTE_DISABLE :: 1 << 63;
}

get_physical_address :: (virtual: *void) -> u64, present: bool {
    x := cast(u64) virtual;

    mask: u64 = 0x1ff;

    pml4_offset := (x >> 39) & mask;
    pdpt_offset := (x >> 30) & mask;
    pd\ _offset := (x >> 21) & mask;
    pt\ _offset := (x >> 12) & mask;
    page_offset := x & 0xfff;

    ReadTableEntry :: (index: u64, table_address: u64) -> entry: u64 #expand {
        present := table_address.(Page_Flags) & .PRESENT;

        if !present `return 0, false;

        table := cast(*u64, table_address & ~0xfff + DIRECT_MAPPING_BASE);
        return table[index];
    }

    cr3: u64;
    #asm { get_cr3 cr3; }
    pml4 := cast(*u64, cr3 + DIRECT_MAPPING_BASE);

    pml4e := pml4[pml4_offset];

    pdpte := ReadTableEntry(pdpt_offset, pml4e);
    if pdpte.(Page_Flags) & .PAGE_SIZE {
        page_offset := x & 0x3fff_ffff;
        return (pdpte & ~0xfff) + page_offset, true;
    }

    pde := ReadTableEntry(pd_offset, pdpte);
    if pde.(Page_Flags) & .PAGE_SIZE {
        page_offset := x & 0x1f_ffff;
        return (pde & ~0xfff) + page_offset, true;
    }

    pte := ReadTableEntry(pt_offset, pde);
    return (pte & ~0xfff) + page_offset, true;
}


// A block allocator that just linearly scans to find a large enough free block. Does not do the job of finding a best fit region to prevent fragmentation.
// Is being used for both virtual and physical memory.

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

    // Find the block corresponding to that address using linear search
    looking_for := address - allocator.base_address;

    m := -1;

    for blocks {
        if it.base == looking_for {
            m = it_index;
            break;
        }
    }

    if m == -1 return null, m;

    return *blocks[m], m;
}

alloc_block :: (using allocator: *Block_Allocator, unaligned_bytes_wanted: u64, loc := #caller_location) -> address: u64 #no_context {
    Scoped_Acquire(*spinlock);

    bytes_wanted: u64;

    if alignment {
        bytes_wanted = align(alignment, unaligned_bytes_wanted);
    } else {
        bytes_wanted = unaligned_bytes_wanted;
    }

    for* blocks {
        if !it.used && it.size >= bytes_wanted {
            it.used = true;

            remaining_bytes := it.size - bytes_wanted;
            it.size = bytes_wanted;

            if remaining_bytes != 0 {
                // We didn't use the whole block, make a new one and move the others over.

                if blocks.count >= max_block_descriptors-1 {
                    bluescreen(loc);
                }

                blocks.count += 1;
                for< it_index+2 .. blocks.count-1 {
                    blocks[it] = blocks[it-1];
                }

                blocks[it_index+1].base = it.base + bytes_wanted;
                blocks[it_index+1].size = remaining_bytes;
                blocks[it_index+1].used = false;
            }

            return cast(u64, base_address + it.base);
        }
    }

    // If we get here there isn't a large enough free block.

    write_string("Block allocator out of memory.");
    bluescreen(loc);
    return 0;
}

resize_block :: (using allocator: *Block_Allocator, address: u64, new_size: u64) -> success: bool {
    Scoped_Acquire(*spinlock);

    block, m := find_block(allocator, address);

    if !block || !block.used {
        print_stack_trace(context.stack_trace);
        bluescreen();
        return false;
    }

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

    // There's a free block trailing the block we're trying to grow, and it's big enough to allow the resize operation.

    block.size += additional_bytes_needed;
    following_block.size -= additional_bytes_needed;
    following_block.base += additional_bytes_needed;

    if following_block.size == 0 {
        // Remove the descriptor if the whole following block was used up by the realloc.

        for m+2 .. blocks.count-1 {
            blocks[it-1] = blocks[it];
        }

        blocks.count -= 1;
    }

    return true;
}

free_block :: (using allocator: *Block_Allocator, address: u64) {
    Scoped_Acquire(*spinlock);

    block, m := find_block(allocator, address);

    if !block || !block.used {
        print_stack_trace(context.stack_trace);
        bluescreen();
        return;
    }

    block.used = false;

    // Coalesce following block
    if blocks.count > m+1 && !blocks[m+1].used {
        block.size += blocks[m+1].size;

        for m+2 .. blocks.count-1 {
            blocks[it-1] = blocks[it];
        }
        blocks.count -= 1;
    }

    // Coalesce preceding block
    if m > 0 && !blocks[m-1].used {
        blocks[m-1].size += block.size;

        for m+1 .. blocks.count-1 {
            blocks[it-1] = blocks[it];
        }
        blocks.count -= 1;
    }
}



Acpi_Rsdp :: struct {
    signature: [8] u8;
    checksum:      u8;
    oem_id:    [6] u8;
    revision:      u8;
    rsdt_address:  u32;

    length:        u32;
    xsdt_address:  u64 #align 4;
    checksum_2:    u8;
    reserved:  [3] u8;
}

Acpi_Table_Header :: struct {
    signature:    [4] u8;
    length:           u32;
    revision:         u8;
    checksum:         u8;

    oem_id:       [6] u8;
    oem_table_id: [8] u8;
    oem_revision:     u32;

    creator_id:       u32;
    creator_revision: u32;

    // Note that this is only aligned to 4 bytes, so if you put this in a struct followed by a u64, it will be wrong.
} #no_padding

find_acpi_table :: (signature: string) -> *Acpi_Table_Header {
    table_size := global.root_acpi_table.length - size_of(Acpi_Table_Header);

    pointer_size := cast(u64) ifx global.acpi_version then 8 else 4;
    pointer_count := table_size / pointer_size;

    table_base := cast(u64) (global.root_acpi_table + 1);

    for table_index: 0..pointer_count - 1 {
        offset := table_index * pointer_size + table_base;

        physical_address: u64 = (.*) cast(*u32)offset;

        if global.acpi_version {
            physical_address = (.*) cast(*u64)offset;
        }

        header := cast(*Acpi_Table_Header) (physical_address + DIRECT_MAPPING_BASE);

        for 0..3 if header.signature[it] != signature[it] {
            continue table_index;
        }

        return header;
    }

    return null;
}



Serial_Port :: struct (base_address: u16) {
    spinlock: Spinlock;
}

serial_out :: (data: string, using serial_port: *Serial_Port) #no_context {

    Scoped_Acquire(*spinlock);

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
}

kernel_write_string :: (text: string) #no_context {
    Scoped_Acquire(*global.text_output_spinlock);

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

    /*
    if global.multiprocessing_initialized {
        return get_current_core().preempt_disable_count;
    }
    */

    return 0;
}

preempt_restore :: (expected: int, loc := #caller_location) #no_context {
    /*
    if global.multiprocessing_initialized {
        core := get_current_core();

        if core.preempt_disable_count != expected {
            bluescreen(loc);
        }
    }
    */

    offset := offset_of(X64_Core, "preempt_disable_count");
    gs_relative_dec(offset);
}



get_rflags :: () -> X64_Flags #foreign Assembly;

disable_interrupts :: () -> X64_Flags #no_context {
    flags := get_rflags();
    #asm { cli; }
    return flags;
}

restore_interrupts :: (flags: X64_Flags) #no_context {
    if flags & .IF__interrupt {
        #asm { sti; }
    }
}



// Things that have 'acquire' and 'release' procedures defined. For use with polymorphic type restrictions.
Any_Lock :: Type.[MCS_Spinlock, Spinlock, Mutex];



Lock_Type :: enum {
    RAW     :: 1;
    PREEMPT :: 2;
    IRQ     :: 3;
}

// MCS lock based on https://web.archive.org/web/20140411142823/http://www.cise.ufl.edu/tr/DOC/REP-1992-71.pdf

MCS_Node :: struct {
    next: *MCS_Node;
    blocked: bool;
}

MCS_Spinlock :: *MCS_Node;

acquire :: (lock: *MCS_Spinlock) -> X64_Flags #no_context {
    flags := disable_interrupts();

    core := get_current_core();
    my_node := *core.mcs_node;

    my_node.next = null;
    prev := fetch_store(lock, my_node);

    if prev {
        my_node.blocked = true;
        prev.next = my_node;

        while my_node.blocked {
            #asm { pause; }
        }
    }

    return flags;
}

release :: (lock: *MCS_Spinlock, flags: X64_Flags) #no_context {
    defer restore_interrupts(flags);

    core := get_current_core();
    my_node := *core.mcs_node;

    if !my_node.next {
        if compare_and_swap(lock, my_node, null) {
            return;
        }

        while !my_node.next {
            #asm { pause; }
        }
    }

    my_node.next.blocked = false;
}



Spinlock :: struct {
    now_serving: u16;
    next_ticket: u16;
    irq_state: bool; // Todo: this could go in the high bit of one of the fields above to save cache space.
}

is_held :: (lock: Spinlock) -> bool #no_context {
    return lock.now_serving != lock.next_ticket;
}

acquire :: (lock: *Spinlock, $lock_type := Lock_Type.PREEMPT) #no_context {

    #if lock_type == {
      case .PREEMPT;
        preempt_disable();
      case .IRQ;
        flags := disable_interrupts();
        lock.irq_state = flags & .IF__interrupt > 0;
    }

    my_ticket := fetch_add(*lock.next_ticket, 1);

    while lock.now_serving != my_ticket {
        #asm { pause; }
    }
}

release :: (lock: *Spinlock, $lock_type := Lock_Type.PREEMPT) #no_context {

    lock.now_serving += 1;

    #if lock_type == {
      case .PREEMPT;
        preempt_restore(0 /* Todo */);
      case .IRQ;
        flags := ifx lock.irq_state then X64_Flags.IF__interrupt else 0;
        restore_interrupts(flags);
    }
}

Scoped_Acquire :: (lock: *Spinlock) #expand {
    acquire(lock);
    `defer release(lock);
}



// Todo: Maybe it would be better to get rid of this, and rewrite the code to not require recursive spinlocks.

Recursive_Spinlock :: struct {
    lock: Spinlock;

    held_by_core: int = -1;
    recursion_count: int;
}

acquire :: (lock: *Recursive_Spinlock) #no_context {

    flags := disable_interrupts();
    core_id := 0;

    if global.multiprocessing_initialized {
        core := get_current_core();
        core_id = core.id;
    } else {
        // If it's too early in boot for multiprocessing to be enabled, core_id can remain zero to indicate the bootstrap core.
    }

    if is_held(lock.lock) && lock.held_by_core == core_id {
        lock.recursion_count += 1;
        return;
    }

    acquire(*lock.lock, .RAW);
    lock.held_by_core = core_id;
    lock.lock.irq_state = flags & .IF__interrupt > 0;
}

release :: (lock: *Recursive_Spinlock) #no_context {

    core_id := 0;

    if global.multiprocessing_initialized {
        core := get_current_core();
        core_id = core.id;
    } else {
        // If it's too early in boot for multiprocessing to be enabled, core_id can remain zero to indicate the bootstrap core.
    }

    if lock.held_by_core != core_id bluescreen();

    if lock.recursion_count > 0 {
        lock.recursion_count -= 1;
        return;
    }

    lock.held_by_core = -1; // Prevent a race due to acquiring the lock, then setting held_by_core immediately afterwards.
    release(*lock.lock, .RAW);

    flags := ifx lock.lock.irq_state then X64_Flags.IF__interrupt else 0;
    restore_interrupts(flags);
}

Scoped_Acquire :: (lock: *Recursive_Spinlock) #expand {
    acquire(lock);
    `defer release(lock);
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




debug_print_physical_memory_map :: () {
    using global;
    push_print_style().default_format_float.trailing_width = 2;

    #if false {
        total_by_type: [5] float;

        for 0..boot_data.memory_map_entries_used-1 {
            region := boot_data.memory_map[it];
            mb := (cast(float) region.pages * 4096) / 0x20_0000;
            print("Region (%) at % (% blocks)\n", region.type, formatInt(region.address, base=16), mb);

            total_by_type[region.type] += cast(int) region.pages;

            if false for 0..cast(int) mb-1 {
                if region.type == {
                    case .FREE; print("-");
                    case .RESERVED_BY_THE_BOOTLOADER; print("+");
                    case .RESERVED_BY_FIRMWARE; print("=");
                    case .DONT_KNOW; print("?");
                }
            }
        }

        print("\n\n\n");

        push_print_style().default_format_float.trailing_width = 2;
        for total_by_type {
            print("Total (%) % MB\n=======\n", cast(type_of(Memory_Region.type)) it_index, it / 256);
        }
    }

    // Visualize the disk cache LRU
    print("Most recently used: %\nLeast recently used: %\n", large_page_allocator.lru_most, large_page_allocator.lru_least);

    for boot_data.large_pages {
        print("[% ->%] % (%<->%)\n", it_index, it.lru_entry, it.state, it.less_recently_used, it.more_recently_used);
    }
}



align :: (alignment: $T, value: $V) -> V #no_context {
    #assert size_of(T) == 8;
    #assert size_of(V) == 8;

    return cast(V) align(cast(int) alignment, cast(int) value);
}

align :: (alignment: int, value: int) -> int #no_context {
    if alignment == 0 return value;

    // This only works for powers of two.
    if popcount(alignment) != 1 {
        bluescreen();
    }

    return (value + (alignment - 1)) & -alignment;
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

push_print_style :: (style := context.print_style) -> *Print_Style #expand {
    // User may choose whether to use the input argument, return value, or neither

    old := context.print_style;
    `defer context.print_style = old;

    context.print_style = style;
    return *context.print_style;
}

hex :: #bake_arguments formatInt(base=16);
dec :: #bake_arguments formatInt(base=10);

#add_context log_category: string;

log_category :: (category: string) #expand {
    old := context.log_category;
    context.log_category = category;
    `defer context.log_category = old;
}



// Temporary debug text draw logic

font_file :: #run,host -> [] u8 {
    image := read_entire_file("font.pgm");
    return add_global_data(cast([] u8) image, .READ_ONLY);
}

draw_text :: (text: string) #no_context {
    using global.text_drawing_state;

    if !font_loaded return;

    Scoped_Acquire(*spinlock);

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

                framebuffer.buffer[pixel_on_screen] = (c) | (c << 8) | (c << 16) | (c << 24);
            }
        }

        cursor_x += 1;
    }
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

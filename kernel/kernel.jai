
#import "Basic";
#import "Machine_X64";

#import "Bitfield";
set :: bitfield_set;

#load "../boot_data.jai";

#load "apic.jai";
#load "x64.jai";
#load "journal.jai";
#load "pci_express.jai";
#load "multitasking.jai";
#load "time.jai";

X64_Core :: struct {
    // It might make sense to #add_context this because there's one per core, but many procedures are called from interrupt routines so you would have to always manually set it.

    task_state_segment: Tss_With_Iopb #align 0x80;

    // Align to cache block so no extra memory accesses are required on context switch
    global_descriptor_table: Global_Descriptor_Table #align 64;

    local_apic_id: u32;
    id: int;

    scheduler: Scheduler;
}

Kernel_Globals :: struct {
    using boot_data: *Boot_Data;

    physical_page_pool: Physical_4k_Page_Pool(1024);
    physical_block_allocator: Block_Allocator;
    virtual_block_allocator: Block_Allocator;

    root_acpi_table: *Acpi_Table_Header;
    acpi_version: int;
    fadt: *acpi_fadt;

    // Hardware requires 16 byte alignment on IDT
    interrupt_descriptor_table: [256] Interrupt_Gate_Descriptor #align 16;
    next_free_interrupt_gate: int;

    // It's not good how we're using resizable arrays in various places that get reallocated and make behavior less consistent and predictable. Better to use something like the Bucket_Array
    processor_cores: [..] X64_Core;

    apic: *void;
    io_apic: *u32;
    local_apic_timer_interrupt_gate: int;

    high_precision_timer: HPET;

    main_thread_context: #Context;

    memory_spinlock: Spinlock;

    tasks: Bucket_Array(Task_Info, 256, always_iterate_by_pointer=true);
    next_task_id: int;
    add_task_info_struct_spinlock: Spinlock;

    boot_time: Apollo_Time;
    rtc_format_is_bcd: bool;

    large_page_allocator: Large_Page_Allocator;

    timestamp_counter_frequency: u64;
}

kernel_globals: Kernel_Globals;

Interrupts :: #library,no_dll "../.build/interrupts";

#program_export
kernel_entry :: () #no_context {
    using kernel_globals;

    // We should avoid using the UEFI identity map because we'll need to get rid of it once we run user processes in low memory.
    boot_data = cast(*Boot_Data) (Boot_Data.BASE_ADDRESS + DIRECT_MAPPING_BASE);

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

    big_page := allocate_large_page();
    init_block_allocator(*physical_block_allocator, big_page, 0x20_0000);


    make_kernel_context(*main_thread_context);

    push_context main_thread_context {

        rtc_init();


        using framebuffer;

        for y: 0..y_resolution-1 {
            for x: 0..x_resolution-1 {
                red   := cast(int) (0xff * (1.0 / y_resolution) * y);
                green := cast(int) (0xff * (1.0 / x_resolution) * x);

                buffer[x + y * stride] = cast(u32) ((red << 16) | (green << 8));
            }
        }


        // Put a virtual memory heap after the direct mapping
        GB :: 0x4000_0000;
        direct_mapping_size := boot_data.page_tables.direct_pd.count * GB;

        heap_base := DIRECT_MAPPING_BASE + direct_mapping_size;
        heap_size := 64 * GB;

        init_block_allocator(*virtual_block_allocator, cast(u64) heap_base, cast(u64) heap_size);


        // Sequentially allocating interrupt gates, starting after the ISA exceptions
        memset(interrupt_descriptor_table.data, 0, size_of(type_of(interrupt_descriptor_table)));
        next_free_interrupt_gate = 32;


        rsdp := cast(*Acpi_RSDP__Root_System_Description_Pointer) boot_data.acpi_rsdp;
        acpi_version = rsdp.revision;

        assert(acpi_version == 0 || acpi_version == 2);

        if acpi_version >= 2 {
            root_acpi_table = xx (rsdp.xsdt_address + DIRECT_MAPPING_BASE);
        } else {
            root_acpi_table = xx (rsdp.rsdt_address + DIRECT_MAPPING_BASE);
        }

        initialize_apic();

        initialize_hpet();
        hpet_configure_timer(timer_index = 0, frequency = 10, true);


        task_switch :: () #foreign Interrupts;
        register_interrupt_gate(task_switch, TASK_SWITCH_GATE);

        tasks.allocator = context.allocator;
        next_task_id = 1;

        // uacpi_context_set_log_level(.DEBUG);

        // if uacpi_initialize(0) != .OK bluescreen();

        // fadt = New(acpi_fadt);
        // if uacpi_table_fadt(*fadt) != .OK bluescreen();

        // Get the time at the most recent second. Maybe use an interrupt to detect a more accurate boot time.
        boot_calendar_time := rtc_get_calendar_time();

        // Don't use Basic.calendar_to_apollo, because it's OS specific
        boot_time = native_calendar_to_apollo(boot_calendar_time);

        timestamp_counter_frequency = calibrate_tsc();


        core_begin_multitasking();

        find_all_pci_devices();
        for pci_devices {
            if it.class_code == .MASS_STORAGE && it.subclass == 0x6 {
                do_ahci_stuff(it);
            }
        }

        // startup_application_processors();
        // 
        // core := get_current_core();
        // for 1..4 {
        //     new_task := create_task();
        //     put_task_on_core(new_task, core);
        // }

        #asm { sti; }

        core := get_current_core();
        while true {
            time := get_monotonic_system_time();
            calendar := native_apollo_to_calendar(time);
            print("Time: %\n", calendar_to_string(calendar));

            print("This is thread % running on core %\n", core.scheduler.current_task.id, core.id);
            sleep_until(time + milliseconds_to_apollo(1000));

            reset_temporary_storage();
        }
    }
}


#program_export
simd_floating_point_exception :: (stack: *Interrupt_Stack()) #c_call {

    mxcsr: Mxcsr;
    pmxcsr := *mxcsr;

    #asm {
        stmxcsr [pmxcsr];
    }

    push_context {
        core := get_current_core();
        print("Floating point exception: % (thread %)\n", mxcsr, core.scheduler.current_task.id);
    }
} @InterruptRoutine


make_kernel_context :: (c: *#Context) #no_context {
    // initializer_of(#Context)(c); 

    c.assertion_failed = (location: Source_Code_Location, message: string) -> bool {
        write_string("Assertion failure");
        if message.count {
            write_strings(": ", message);
        }
        write_string("\n");

        print_stack_trace(context.stack_trace);
        bluescreen(location);
        return true;
    };

    c.logger = (message: string, data: *void, info: Log_Info) {
        write_string(message);
        if message[message.count-1] != #char "\n" {
            write_string("\n");
        }
    };

    c.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = 2;
    c.print_style.default_format_struct.use_newlines_if_long_form = true;

    c.allocator.proc = (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
        Scoped_Acquire(*kernel_globals.memory_spinlock);

        if mode == .ALLOCATE || mode == .RESIZE {
            if size == 0 {
                return null;
            }

            // Todo: handle resize
            physical := alloc_block(*kernel_globals.physical_block_allocator, cast(u64) size);

            virtual := cast(*void) physical + DIRECT_MAPPING_BASE;

            if mode == .RESIZE && old_memory != null {
                memcpy(virtual, old_memory, old_size);

                physical := cast(u64) old_memory - DIRECT_MAPPING_BASE;
                free_block(*kernel_globals.physical_block_allocator, physical);
            }

            return virtual;
        }

        if mode == .FREE {
            if old_memory == null {
                return null;
            }

            physical := cast(u64) old_memory - DIRECT_MAPPING_BASE;
            free_block(*kernel_globals.physical_block_allocator, physical);
        }

        if mode == .CAPS {
            return cast(*void) Allocator_Caps.FREE | .HINT_I_AM_A_GENERAL_HEAP_ALLOCATOR;
        }

        return null;
    };

    {
        acquire(*kernel_globals.memory_spinlock);
        ts_buffer_block := alloc_block(*kernel_globals.physical_block_allocator, 0x2000);
        c.temporary_storage = cast(*Temporary_Storage) get_4k_page();
        release(*kernel_globals.memory_spinlock);

        ts_buffer := cast(*void) ts_buffer_block + DIRECT_MAPPING_BASE;

        set_initial_data(c.temporary_storage, 0x2000, ts_buffer);

        c.temporary_storage.overflow_allocator = c.allocator;
    }
}

init_processor_core :: () #no_context {
    core: *X64_Core;

    enable_cpu_features();

    {
        my_local_apic_id := read_apic_register(.APIC_ID) >> 24;

        for* kernel_globals.processor_cores {
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
        tss_desc.base_address_0 = cast(u16)  tss_address;
        tss_desc.base_address_1 = cast(u8)  (tss_address >> 16);
        tss_desc.base_address_2 = cast(u8)  (tss_address >> 24);
        tss_desc.base_address_3 = cast(u32) (tss_address >> 32);
        tss_desc.flags_0        = 0b1_00_0_1001; // type=TSS non-busy | PRESENT

        using Gdt_Entry_Flags;

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

        init_segment_registers :: () #foreign Interrupts;
        init_segment_registers();
    }

    {
        // Interrupt descriptor table
        idt_desc: struct {
            limit: u16;
            base: *Interrupt_Gate_Descriptor #align 2;
        }

        idt_desc.limit = size_of(type_of(kernel_globals.interrupt_descriptor_table));
        idt_desc.base = kernel_globals.interrupt_descriptor_table.data;

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

        syscall_entry :: () #foreign Interrupts;
        write_msr(.LSTAR__syscall_address, cast(u64) cast(*void) syscall_entry);

        EFER_SCE__syscall_enable :: 1;

        efer := read_msr(.EFER__extended_features);
        efer |= EFER_SCE__syscall_enable;
        write_msr(.EFER__extended_features, efer);
    }
}

bluescreen :: (loc := #caller_location) #no_context {
    using kernel_globals.framebuffer;

    for y: 0..y_resolution-1 for x: 0..x_resolution-1 {
        buffer[x + y * stride] = cast(u32) (0xff0000ff);
    }

    write_string("Bluescreen!\nSource code location:\n");
    write_loc(loc);

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

    lock: Recursive_Spinlock;
}

allocate_large_page :: () -> u64 #no_context {

    using kernel_globals.large_page_allocator;
    acquire(*lock);

    if freelist != FREELIST_TAIL {
        address := freelist * 0x20_0000;

        desc := *kernel_globals.large_pages[freelist];
        desc.state = .ALLOCATED;
        freelist = desc.freelist;

        return cast(u64) address;
    }

    while max_large_page_used < kernel_globals.large_pages.count {

        desc := *kernel_globals.large_pages[max_large_page_used];

        page := max_large_page_used * 0x20_0000;
        max_large_page_used += 1;

        if desc.state == .RESERVED {
            continue;
        }

        desc.state = .ALLOCATED;
        return cast(u64) page;
    }

    // There are no free large pages, evict one from the disk cache.
    if lru_least != LRU_TAIL {
        page := cast(u64) lru_least * 0x20_0000;
        desc := *kernel_globals.large_pages[lru_least];
        evict_disk_cache_entry(page);

        desc.state = .ALLOCATED;
        return page;
    }

    // There's no free memory
    bluescreen();
    return 0;
}

find_or_add_disk_cache_entry :: (disk_address: u64) -> u64 {
    using kernel_globals;
    Scoped_Acquire(*large_page_allocator.lock);

    block_index := disk_address / 0x20_0000;
    block_index %= cast(u64) large_pages.count;

    hash_table_entry := *large_pages[block_index];
    lru_entry        := *large_pages[hash_table_entry.lru_entry];

    Cache_Page :: (page: u64) #expand {
        page_index := cast(s32) (page / 0x20_0000);

        lru_entry := *large_pages[page_index];
        lru_entry.state = .DISK_CACHE;

        `hash_table_entry.lru_current_block = `disk_address / 0x20_0000;
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
    page := cast(u64) hash_table_entry.lru_entry * 0x20_0000;

    // Todo: move the page to the front of the list

    return page;
}

evict_disk_cache_entry :: (page: u64) #no_context {
    using kernel_globals;

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
        kernel_globals.large_page_allocator.lru_least = lru_entry.more_recently_used;
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

    lock: Spinlock;
}

page_pool_index_to_address :: (pool: *Physical_4k_Page_Pool, index: s32) -> u64 #no_context {
    large_page_index := index / 512;
    page_index       := index % 512;

    large_page := *pool.large_pages[large_page_index];

    if pool.large_pages_used <= large_page_index {
        large_page.index = cast(s32) (allocate_large_page() / 0x20_0000);
        pool.large_pages_used += 1;
    }

    large_page.used += 1;

    address := cast(u64) large_page.index * 0x20_0000;
    address += cast(u64) page_index * 4096;

    return address;
}

get_4k_page :: () -> u64 #no_context {
    return get_4k_page(*kernel_globals.physical_page_pool);
}

get_4k_page :: (pool: *Physical_4k_Page_Pool) -> u64 #no_context {
    using pool;
    Scoped_Acquire(*lock);

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

}



get_or_create_page_table :: (table: *u64, entry: u64) -> *u64 {
    using Page_Flags;

    if table[entry] & xx PRESENT {
        physical := table[entry] & (~0xfff);
        return cast(*u64) (physical + DIRECT_MAPPING_BASE);
    }

    address := get_4k_page();

    table[entry] = address | xx PRESENT | READ_WRITE;

    return cast(*u64) (address + DIRECT_MAPPING_BASE);
}

map_page :: (virtual_address: *void, physical_address: u64, flags := Page_Flags.PRESENT | .READ_WRITE) {
    map_page(cast(u64) virtual_address, physical_address);
}

map_page :: (virtual_address: u64, physical_address: u64, flags := Page_Flags.PRESENT | .READ_WRITE, loc := #caller_location) {
    using Page_Flags;

    mask: u64 = 0b111111111;

    pml4_offset := (virtual_address >> 39) & mask;
    pdpt_offset := (virtual_address >> 30) & mask;
    pd\ _offset := (virtual_address >> 21) & mask;
    pt\ _offset := (virtual_address >> 12) & mask;

    pml4 := kernel_globals.boot_data.page_tables.pml4.data;

    pdpt := get_or_create_page_table(pml4, pml4_offset);
    pd   := get_or_create_page_table(pdpt, pdpt_offset);
    pt   := get_or_create_page_table(pd,   pd_offset);

    if pt[pt_offset] & xx PRESENT {
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
}

init_block_allocator :: (allocator: *Block_Allocator, base_address: u64, max_size: u64) #no_context {
    // Use a large page to hold block descriptors
    page := allocate_large_page();

    allocator.blocks.data = cast(*void) page + DIRECT_MAPPING_BASE;
    allocator.max_block_descriptors = 0x20_0000 / size_of(Block_Desc);

    allocator.base_address = base_address;
    allocator.max_size = max_size;

    allocator.blocks.count = 1;
    allocator.blocks[0] = .{
        base = 0,
        size = max_size,
        used = false,
    };
}

alloc_block :: (using allocator: *Block_Allocator, bytes_wanted: u64, loc := #caller_location) -> address: u64, Block_Desc #no_context {

    for* blocks {
        if !it.used && it.size >= bytes_wanted {
            it.used = true;

            remaining_bytes := it.size - bytes_wanted;
            it.size = bytes_wanted;

            if remaining_bytes != 0 {
                // We didn't use the whole block, make a new one and move the others over
                if blocks.count >= max_block_descriptors-1 {
                    bluescreen(loc);
                }

                blocks.count += 1;
                for#v2< it_index+2 .. blocks.count-1 {
                    blocks[it] = blocks[it-1];
                }

                blocks[it_index+1].base = it.base + bytes_wanted;
                blocks[it_index+1].size = remaining_bytes;
                blocks[it_index+1].used = false;
            }

            return cast(u64) (base_address + it.base), it.*;
        }
    }

    // If we get here there isn't a large enough free block
    bluescreen(loc);
    return 0, .{};
}

free_block :: (allocator: *Block_Allocator, address: u64) -> bool {
    // Find the block corresponding to that address using linear search

    looking_for := address - allocator.base_address;

    blocks := allocator.blocks;
    defer allocator.blocks = blocks;

    m := -1;

    for blocks {
        if it.base == looking_for {
            m = it_index;
            break;
        }
    }

    if m == -1 {
        print_stack_trace(context.stack_trace);
        bluescreen();
        return false;
    }

    block := *blocks[m];
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

    return true;
}



Acpi_RSDP__Root_System_Description_Pointer :: struct {
    signature: [8] u8;
    checksum: u8;
    oem_id: [6] u8;
    revision: u8;
    rsdt_address: u32;

    length: u32;
    xsdt_address: u64 #align 4;
    checksum_2: u8;
    reserved: [3] u8;
}

Acpi_Table_Header :: struct {
    signature: [4] u8;
    length: u32;
    revision: u8;
    checksum: u8;
    oem_id: [6] u8;
    oem_table_id: [8] u8;
    oem_revision: u32;
    creator_id: u32;
    creator_revision: u32;

    // Note that this is only aligned to 4 bytes, so if you put this in a struct followed by a u64, it will be wrong.
} #no_padding

find_acpi_table :: (signature: string) -> *Acpi_Table_Header {
    table_size := kernel_globals.root_acpi_table.length - size_of(Acpi_Table_Header);

    pointer_size := cast(u64) (ifx kernel_globals.acpi_version then 8 else 4);
    pointer_count := table_size / pointer_size;

    table_base := cast(u64) (kernel_globals.root_acpi_table + 1);

    for table_index: 0..pointer_count - 1 {
        offset := table_index * pointer_size + table_base;

        phys := ifx kernel_globals.acpi_version {
            << cast(*u64) offset;
        } else {
            cast(u64) << cast(*u32) offset;
        }

        header := cast(*Acpi_Table_Header) (phys + DIRECT_MAPPING_BASE);

        for 0..3 if header.signature[it] != signature[it] {
            continue table_index;
        }

        return header;
    }

    return null;
}



// This is implemented in Runtime_Support, so that write_string can go to serial
// serial_out :: (data: string)



load_fence :: () #expand {
    #asm { lfence; }
}

store_fence :: () #expand {
    #asm { sfence; }
}

memory_fence :: () #expand {
    #asm { mfence; }
}



Spinlock :: #type,distinct u32;

acquire :: (lock: *Spinlock) #no_context {
    carry: u8 = 1;

    while carry {
        while lock.* {
            #asm { pause; }
        }

        #asm {
            lock_bts.32 [lock], 0;
            setc carry;
        }
    }

    memory_fence();
}

release :: (lock: *Spinlock) #no_context {
    memory_fence();

    if !lock.* bluescreen();
    lock.* = 0;
}

Scoped_Acquire :: (lock: *Spinlock) #expand {
    acquire(lock);
    `defer release(lock);
}



Recursive_Spinlock :: struct {
    lock: Spinlock;

    held_by_core: int;
    recursion_count: int;
}

acquire :: (lock: *Recursive_Spinlock) #no_context {
    if !kernel_globals.processor_cores.count {
        // It's too early in boot for recursive spinlocks to work.
        return;
    }

    core := get_current_core();

    if lock.lock && lock.held_by_core == core.id {
        lock.recursion_count += 1;
        return;
    }

    acquire(*lock.lock);

    lock.held_by_core = core.id;
}

release :: (lock: *Recursive_Spinlock) #no_context {
    if !kernel_globals.processor_cores.count {
        // It's too early in boot for recursive spinlocks to work.
        return;
    }

    core := get_current_core();

    if lock.held_by_core != core.id bluescreen();

    if lock.recursion_count > 0 {
        lock.recursion_count -= 1;
        return;
    }

    release(*lock.lock);
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

            if (sequence & 1) == 0 break;

            #asm { pause; pause; pause; pause; }
        }
        load_fence();

        #insert body;

        load_fence();
        if lock.* == sequence break;
    }
}

sequence_write :: (lock: *Sequence_Lock, body: Code) #expand {
    lock.* += 1;
    store_fence();

    #insert body;

    store_fence();
    lock.* += 1;
}



FREELIST_TAIL :: -1;
LRU_TAIL      :: -1;



allocate_interrupt_gate :: (loc := #caller_location) -> int {
    using kernel_globals;

    if next_free_interrupt_gate == TASK_SWITCH_GATE {
        // Some gates need to be reserved as constants so they can be used in instruction immediates.
        // In the future we might need to support allocating specific gates anyway.
        next_free_interrupt_gate += 1;
    }

    assert(next_free_interrupt_gate < 0xff);

    result := next_free_interrupt_gate;
    next_free_interrupt_gate += 1;
    return result;
}




print_physical_memory_map :: () {
    using kernel_globals;
    context.print_style.default_format_float.trailing_width = 2;

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

    context.print_style.default_format_float.trailing_width = 2;
    for total_by_type {
        print("Total (%) % MB\n=======\n", cast(type_of(Memory_Region.type)) it_index, it / 256);
    }
    }

    print("Most recently used: %\nLeast recently used: %\n", large_page_allocator.lru_most, large_page_allocator.lru_least);

    for boot_data.large_pages {
        print("[% ->%] % (%<->%)\n", it_index, it.lru_entry, it.state, it.less_recently_used, it.more_recently_used);
    }
}

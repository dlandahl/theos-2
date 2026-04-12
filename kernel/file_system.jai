
#import,file "../modules/File_System.jai"(Mounted_File_System);

Mounted_File_System :: struct {
    disk_offset_in_bytes: u64;

    storage_device: Storage_Device;

    #as file_system: File_System; // Should eventually be a pointer to any type of file system. File_System is a specific driver for a specific on-disk format.

    maybe_dirty: [..] u64; // Temporary. Contains the hashes of all disk blocks that may be dirty in the cache.
}

mount_file_system :: (sd: Storage_Device, disk_offset: u64) -> *Mounted_File_System {

    // Must be set before calling format_file_system.
    pin_disk_block         = my_pin_disk_block;
    unpin_disk_block       = my_unpin_disk_block;

    mounted := New(Mounted_File_System,, global.small_objects); // The File_System module needs this to be a stable pointer.

    mounted.storage_device       = sd;
    mounted.disk_offset_in_bytes = disk_offset;
    mounted.file_system          = mount_file_system(mounted);

    return mounted;
}

flush_file_system :: (fs: *Mounted_File_System) {
    // Todo: Temporary.

    // In future we maybe should flush as much and as early as possible (whenever the user isn't requesting
    // explicit transfers with which we would compete for bandwidth) so that the disk cache doesn't
    // block regular memory allocations with disk ops, which would make all sorts of things very slow.

    transfer_done: Semaphore;

    for fs.maybe_dirty {
        transfer: Transfer_Request;

        hash_table_entry  := global.large_pages[it];

        disk_byte_address :=           hash_table_entry.lru_current_block * 0x20_0000;
        page_base         := cast(u64) hash_table_entry.lru_entry         * 0x20_0000;

        transfer.start_lba = cast(s64) disk_byte_address / 512;
        transfer.count_lba = 0x20_0000                   / 512;
        transfer.direction = .WRITE;
        transfer.semaphore = *transfer_done;
        transfer.physical_memory_address = page_base;

        // Todo: Lots of tracing for file system and disk cache.
        // log("FLUSH LBA % <-> address %", transfer.start_lba, hex(transfer.physical_memory_address));

        do_storage_transfer(fs.storage_device, transfer);
    }

    count := fs.maybe_dirty.count;

    for fs.maybe_dirty {
        // Todo: Racy.

        hash_table_entry  := global.large_pages[it];
        lru_entry         := global.large_pages[hash_table_entry.lru_entry];

        assert(lru_entry.state == .DISK_CACHE);

        if lru_entry.pinned == 0 {
            remove it;
        }
    }

    for 0..count-1 {
        wait_for(*transfer_done);
    }
}



map_file :: (fs: File_System, id: s64, virtual_base := null, read_only := false, for_userspace := false, arena: *Physical_Memory_Arena = null) -> string {
    // We don't do lazy loading yet. This will read the whole file into RAM and keep it there.

    inode := lookup_inode(fs, id);
    assert(inode && inode.type == .FILE);

    num_blocks := (inode.file_size + 0x1f_ffff) / BLOCK_SIZE;

    vm_it: VM_Iterator;
    vm_it.start_address = ifx virtual_base else cast(*void) alloc_block(*global.virtual_large_page_allocator, num_blocks * BLOCK_SIZE);
    vm_it.page_count    = num_blocks * 512; // VM Iterator works using 4k pages, disk cache works using 2MB pages.

    extra_flags: Page_Flags;

    if !read_only     extra_flags |= .READ_WRITE;
    if for_userspace  extra_flags |= .USER_SUPERVISOR;

    for vm_it {
        if it.level == 1 {
            assert(it.flags & .PRESENT == 0);

            current_page := it_index / 512;

            block_index := inode.data_blocks[current_page];
            assert(block_index != 0);

            block := pin_disk_block(fs.user_data, block_index);

            it.value  = cast(u64) block - DIRECT_MAPPING_BASE;
            it.flags |= .PRESENT | .PAGE_SIZE | extra_flags;

            continue;
        }

        if it.flags & .PRESENT continue;

        new_table := ifx arena then arena_get(arena, 4096, 4096) else get_4k_page();

        it.value  = new_table;
        it.flags |= .PRESENT | extra_flags;
    }

    return {inode.file_size, vm_it.start_address};
}

unmap_file :: (fs: File_System, id: s64, mapping: *void) {
    inode := lookup_inode(fs, id);
    assert(inode && inode.type == .FILE);

    num_blocks := (inode.file_size + 0x1f_ffff) / BLOCK_SIZE;

    vm_it: VM_Iterator;
    vm_it.start_address = mapping;
    vm_it.page_count    = num_blocks * 512;

    for vm_it {
        assert(it.flags & .PRESENT > 0);

        if it.level != 1 {
            continue;
        }

        unpin_disk_block(fs.user_data, it.virtual);
        it.value = 0;
    }

    free_block(*global.virtual_large_page_allocator, cast(u64) mapping);
}



my_pin_disk_block :: (fs: *Mounted_File_System, block_index: u32, overwrite := false) -> *void {
    disk_byte_address := fs.disk_offset_in_bytes + block_index * 0x20_0000;
    assert(fs.disk_offset_in_bytes & 0x1f_ffff == 0);

    disk_block_index  := disk_byte_address / 0x20_0000;
    block_hash        := disk_block_index % cast(u64) global.large_pages.count;

    array_add_if_unique(*fs.maybe_dirty, block_hash); // Todo: Temporary.

    page_base, was_present := find_or_add_disk_cache_entry(disk_byte_address);

    // "overwrite" means we don't care what was in this disk block before because the caller intends
    // to completely write over it. In that case, even if the block is not resident in the cache, we
    // don't have to spend time fetching it from disk.

    if !was_present && !overwrite {
        transfer: Transfer_Request;
        transfer_done: Semaphore;

        transfer.start_lba = cast(s64) disk_byte_address / 512;
        transfer.count_lba = 0x20_0000                   / 512;
        transfer.direction = .READ;
        transfer.semaphore = *transfer_done;
        transfer.physical_memory_address = page_base;

        // Todo: Lots of tracing for file system and disk cache.
        // log("CACHE LBA % <-> address %", transfer.start_lba, hex(transfer.physical_memory_address));

        do_storage_transfer(fs.storage_device, transfer);
        wait_for(*transfer_done);
    }

    return cast(*void) page_base + DIRECT_MAPPING_BASE;
}

my_unpin_disk_block :: (fs: *Mounted_File_System, address: *void) {
    physical  := get_physical_address(address);
    page_desc := global.large_pages[physical / 0x20_0000];

    assert(page_desc.pinned > 0 && page_desc.state == .DISK_CACHE);
    page_desc.pinned -= 1;
}




Opened_File :: struct {
    inode_id:       int;
    file_system:   *Mounted_File_System;
    opened_for:     enum { READING; WRITING; };
}


open_file :: (path_bytes: *u8, path_length: int, writable := false, create_if_not_existent := false) -> id: u64 {
    if check_user_address(path_bytes, path_length) {
        return 0;
    }

    path_string := string.{path_length, path_bytes};

    path, file_name := path_decomp(path_string);
    path             = trim(path, "\\/");

    parent_inode_id := resolve_path(global.file_system, 1, path);

    if !parent_inode_id || !file_name {
        set_syscall_failed();
        return 0;
    }

    file_inode_id := get_directory_entry(global.file_system, parent_inode_id, file_name);

    if !file_inode_id {
        if create_if_not_existent {
            // Todo: This redundantly checks all the directory entries to make sure it doesn't already exist, which we've already done.
            file_inode_id = create_file(global.file_system, parent_inode_id, file_name);
        } else {
            return 0;
        }
    }

    if !file_inode_id {
        set_syscall_failed();
        return 0;
    }

    process := get_current_task().process_context;
    // Todo: Race.
    new_file, id := array_add(*process.files);
    new_file.opened_for  = ifx writable then .WRITING else .READING;
    new_file.file_system = global.file_system; // There's always just one file system at the moment.
    new_file.inode_id    = file_inode_id;

    return id;
} @Syscall(40)

AT :: struct @SyscallAPI {
    _: void;
    low:  u64;
    high: s64;
}

File_Stats :: struct @SyscallAPI {
    _: void; // Program_Print.print_expression skips the first struct field...
    version := 1;
    size_bytes:          int;

    modified_consensus:  AT;
    modified_monotonic:  AT;
    created_consensus:   AT;
    created_monotonic:   AT;

    monotonic_clock_generation: int;
}

stat_file :: (id: u64, stats: *File_Stats) {

    if check_user_address(stats, size_of(File_Stats)) {
        return;
    }

    process := get_current_task().process_context;
    file    := lookup(*process.files, id);

    if file == null {
        set_syscall_failed();
        return;
    }

    inode := lookup_inode(global.file_system, file.inode_id);
    assert(!!inode);

    stats.size_bytes = inode.file_size;

    stats.modified_consensus = cast,FORCE(AT) inode.modified.consensus;
    stats.modified_monotonic = cast,FORCE(AT) inode.modified.monotonic;

    stats.created_consensus  = cast,FORCE(AT) inode.created.consensus;
    stats.created_monotonic  = cast,FORCE(AT) inode.created.monotonic;

    stats.monotonic_clock_generation = inode.modified.clock_generation;
} @Syscall(41)

create_file_mapping :: (id: u64, virtual_address: *void) {

    process := get_current_task().process_context;
    file    := lookup(*process.files, id);

    if file == null {
        set_syscall_failed();
        return;
    }

    inode := lookup_inode(file.file_system, file.inode_id);

    if check_user_address(virtual_address, inode.file_size) {
        return;
    }

    map_file(file.file_system, file.inode_id, virtual_address, file.opened_for == .READING, true, *process.arena);
} @Syscall(42)

flush_file :: (id: u64) {
    process := get_current_task().process_context;
    file    := lookup(*process.files, id);

    if file == null {
        set_syscall_failed();
        return;
    }

    // Todo: Race.
    flush_file_system(file.file_system);
} @Syscall(43)

read_file :: (id: u64, buffer: *void, bytes: int, offset: int) -> bytes_read: int {
    // Todo;
    assert(false);
    return 0;
} @Syscall(44)

write_to_file :: (id: u64, buffer: *void, bytes: int, offset: int) {

    if check_user_address(buffer, bytes) {
        return;
    }

    process := get_current_task().process_context;
    file    := lookup(*process.files, id);

    if file == null {
        set_syscall_failed();
        return;
    }

    write_file(file.file_system, file.inode_id, string.{bytes, buffer}, offset);
} @Syscall(45)

close_file :: (id: u64) {
    // Todo;
    flush_file(id);
} @Syscall(46)

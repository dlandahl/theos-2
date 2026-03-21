
#import,file "../modules/File_System.jai"(Mounted_File_System);

Mounted_File_System :: struct {
    disk_offset_in_bytes: u64;

    storage_device: Storage_Device;

    #as file_system: File_System;
}

format_and_mount_file_system :: (sd: Storage_Device, disk_offset: u64) -> *Mounted_File_System {

    m := New(Mounted_File_System,, global.small_objects); // The File_System module needs this to be a stable pointer.

    m.storage_device       = sd;
    m.disk_offset_in_bytes = disk_offset;

    pin_disk_block         = my_pin_disk_block;
    unpin_disk_block       = my_unpin_disk_block;

    m.file_system          = format_file_system(m);

    return m;
}



map_file :: (fs: File_System, id: s64) -> *void {
    // We don't do lazy loading yet. This will read the whole file into RAM and keep it there.

    inode := lookup_inode(fs, id);
    assert(inode && inode.type == .FILE);

    num_blocks := (inode.file_size + 0x1f_ffff) / BLOCK_SIZE;

    vm_it: VM_Iterator;
    vm_it.start_address = cast(*void) alloc_block(*global.virtual_large_page_allocator, num_blocks * BLOCK_SIZE);
    vm_it.page_count    = num_blocks * 512; // VM Iterator works using 4k pages, disk cache works using 2MB pages.

    for vm_it {
        if it.level == 1 {
            assert(it.flags & .PRESENT == 0);

            current_page := it_index / 512;

            block_index := inode.data_blocks[current_page];
            assert(block_index != 0);

            block := pin_disk_block(fs.user_data, block_index);

            it.value  = cast(u64) block - DIRECT_MAPPING_BASE;
            it.flags |= .PRESENT | .READ_WRITE | .PAGE_SIZE;

            continue;
        }

        if it.flags & .PRESENT continue;

        new_table := get_4k_page();

        it.value  = new_table;
        it.flags |= .PRESENT | .READ_WRITE;
    }

    return vm_it.start_address;
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
            continue; // Just leave the higher level mappings where they are for now, we don't track them yet.
        }

        unpin_disk_block(fs.user_data, it.virtual);
        it.value = 0;
    }

    free_block(*global.virtual_large_page_allocator, cast(u64) mapping);
}



my_pin_disk_block :: (fs: *Mounted_File_System, block_index: u32, overwrite := false) -> *void {
    disk_byte_address := fs.disk_offset_in_bytes + block_index * 0x20_0000;

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

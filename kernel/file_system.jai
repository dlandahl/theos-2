
Info_Node :: struct {
    type: enum u8 {
        FILE;
        DIRECTORY;
    }

    file_size: s64;
    #overlay(file_size) directory_entries: s64;

    created:  Apollo_Time;
    modified: Apollo_Time;

    data_blocks:         [8] u64;
    indirect_data_block:     u64;
}

Directory_Entry :: struct {
    inode_id:    s64;
    name_length: s64;
    name_bytes:  void;
}

Mounted_File_System :: struct {
    disk_offset_in_bytes: u64;

    storage_device: Storage_Device;

    // Important data structures that will remain pinned in memory the whole time the system is mounted.
    super_block:    *Super_Block;
    inodes_block: [] Info_Node;
}

#assert size_of(Super_Block) < 0x20_0000;

Super_Block :: struct {
    magic: u64;
    mount_count: int;
    last_mounted_timestamp: Apollo_Time;

    free_blocks: Bit_Tree;
    free_inodes: Bit_Tree;
}

format_file_system :: (sd: Storage_Device, offset: u64) -> Mounted_File_System {
    time_now := get_system_time();

    fs: Mounted_File_System;
    fs.storage_device = sd;
    fs.disk_offset_in_bytes = offset;

    sb := cast(*Super_Block) pin_disk_block(fs, 0, overwrite = true);
    memset(sb, 0, 0x20_0000);

    // Occupy the first two blocks, as they are the super block and the inodes block.
    sb.free_blocks.level_2[0] = 0b11;

    sb.mount_count = 1;
    sb.last_mounted_timestamp = time_now;

    fs.super_block = sb;

    fs.inodes_block.data  = pin_disk_block(fs, 1, overwrite = true);
    fs.inodes_block.count = 0x20_0000 / size_of(Info_Node);

    root_id := allocate_inode(fs);
    assert(root_id == 1);

    root := lookup_inode(fs, root_id);
    root.type              = .DIRECTORY;
    root.directory_entries = 0;
    root.created           = time_now;
    root.modified          = time_now;

    return fs;
}

allocate_inode :: (fs: Mounted_File_System) -> int {
    // Lets say inode identifier = 0 means invalid/unitialized.
    identifier := allocate_bit_tree_slot(*fs.super_block.free_inodes);
    return identifier + 1;
}

lookup_inode :: (fs: Mounted_File_System, identifier: int) -> *Info_Node {
    return *fs.inodes_block[identifier - 1];
}

allocate_block :: (fs: Mounted_File_System) -> u64 {
    index := allocate_bit_tree_slot(*fs.super_block.free_blocks);
    return cast(u64) index;
}

create_child_inode :: (fs: Mounted_File_System, parent_id: int, child_name: string) -> *Info_Node {
    time_now := get_system_time();

    parent := lookup_inode(fs, parent_id);
    new_inode_id := allocate_inode(fs);

    // Todo: Check if an entry with this name already exists.

    for *parent.data_blocks {
        if it.* == 0 {
            // The block has not been allocated, but we haven't found a free space yet. Allocate a new disk block.
            it.* = allocate_block(fs);
        }

        block  := pin_disk_block(fs, it.*);
        offset := 0;
        defer unpin_disk_block(block);

        // Look for a free space in the current block.
        while true {
            if offset + size_of(Directory_Entry) + 1 >= 0x20_0000 {
                // End of the disk block.
                break;
            }

            entry := cast(*Directory_Entry) (block + offset);

            if entry.inode_id != 0 {
                offset += entry.name_length + size_of(Directory_Entry);
                continue;
            }

            // Found a free entry. Is there enough space?
            space_available := ifx entry.name_length else 0x20_0000 - offset - size_of(Directory_Entry);

            if space_available >= child_name.count {
                // Found a suitable directory entry.

                entry.inode_id    = new_inode_id;
                entry.name_length = child_name.count;
                memcpy(*entry.name_bytes, child_name.data, child_name.count);

                parent.modified = time_now;
                parent.directory_entries += 1;

                return lookup_inode(fs, new_inode_id);
            }
        }
    }

    assert(false);
    return null;
}

get_child_inode :: (fs: Mounted_File_System, parent_id: int, child_name: string) {

}



pin_disk_block :: (fs: Mounted_File_System, block_index: u64, overwrite := false) -> *void {
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

unpin_disk_block :: (address: *void) {
    // You just pass in the virtual address you got from pin_disk_block.

    physical  := cast(u64) address - DIRECT_MAPPING_BASE;
    page_desc := global.large_pages[physical / 0x20_0000];

    assert(page_desc.pinned > 0 && page_desc.state == .DISK_CACHE);
    page_desc.pinned -= 1;
}



Bit_Tree :: struct {
    level_0:         u64;
    level_1: [64]    u64;
    level_2: [64*64] u64;
}

count_trailing_zeros :: inline (value: $T) -> u64 {
    result: u64;
    #asm { tzcnt?T result, value; }
    return result;
}

allocate_bit_tree_slot :: (bt: *Bit_Tree) -> int {
    assert(bt.level_0 != ~0, "Bit tree is full.");

    index_0 := count_trailing_zeros(~bt.level_0);
    index_1 := count_trailing_zeros(~bt.level_1[index_0]);
    index_2 := count_trailing_zeros(~bt.level_2[index_0 * 64 + index_1]);

         bt.level_2[index_0 * 64 + index_1]                     |= cast(u64) 1 << index_2;
    if !~bt.level_2[index_0 * 64 + index_1] bt.level_1[index_0] |= cast(u64) 1 << index_1;
    if !~bt.level_1[index_0]                bt.level_0          |= cast(u64) 1 << index_0;

    return cast(s64) (index_0 * 4096 + index_1 * 64 + index_2);
}

free_bit_tree_slot :: (bt: *Bit_Tree, index: int) {
    index_0 := (index / 4096);
    index_1 := (index / 64)   % 64;
    index_2 := (index)        % 64;

    assert(bt.level_2[index_0 * 64 + index_1] & cast(u64) (1 << index_2) > 0, "Attempting to free bit tree slot that wasn't occupied.");

    bt.level_0                         &= cast(u64) ~(1 << index_0);
    bt.level_1[index_0]                &= cast(u64) ~(1 << index_1);
    bt.level_2[index_0 * 64 + index_1] &= cast(u64) ~(1 << index_2);
}

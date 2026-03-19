
Info_Node :: struct {
    type: enum u8 {
        FILE;
        DIRECTORY;
    }

    file_size: s64;
    #overlay(file_size) directory_entries: s64;

    created:  Apollo_Time;
    modified: Apollo_Time;

    links: int; // How many directory entries reference me.

    data_blocks:         [8] u32;
    indirect_data_block:     u32;
}

Directory_Entry :: struct {
    inode_id:    s64 #align 4;
    name_length: s32;
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

allocate_inode :: (fs: Mounted_File_System) -> s64 {
    // Lets say inode identifier = 0 means invalid/unitialized.
    identifier := allocate_bit_tree_slot(*fs.super_block.free_inodes);
    return identifier + 1;
}

lookup_inode :: (fs: Mounted_File_System, identifier: s64) -> *Info_Node {
    assert(identifier != -1, "Tried to lookup invalid inode.");
    return *fs.inodes_block[identifier - 1];
}

allocate_block :: (fs: Mounted_File_System) -> u32 {
    index := allocate_bit_tree_slot(*fs.super_block.free_blocks);
    return cast(u32) index;
}

dirent_name :: (dirent: *Directory_Entry) -> string {
    return {cast(s64) dirent.name_length, *dirent.name_bytes};
}

create_directory_entry :: (fs: Mounted_File_System, parent_id: s64, child_id: s64, child_name: string) {
    time_now := get_system_time();

    parent := lookup_inode(fs, parent_id);

    found_slot: *Directory_Entry;

    for *parent.data_blocks { // Todo: Doesn't do indirect blocks. Not sure how we'll do directory blocks anyway.
        if it.* == 0 && !found_slot {
            // The block has not been allocated, but we haven't found a free space yet. Allocate a new disk block.
            it.* = allocate_block(fs);
            // Todo: Handle running out of disk blocks.
        }

        block := pin_disk_block(fs, it.*);
        defer  unpin_disk_block(block);

        offset := 0;

        // Look for a free space in the current block.
        while true {
            if offset + size_of(Directory_Entry) + 1 >= 0x20_0000 {
                // End of the disk block.
                break;
            }

            entry := cast(*Directory_Entry) (block + offset);

            log("Got entry % block % offset %", entry, block, offset);

            if entry.inode_id != 0 {
                assert(entry.name_length != 0);

                // Found a non-free entry. Make sure it's not a duplicate.
                name := dirent_name(entry);

                if equal_nocase(name, child_name) {
                    assert(false);
                    return; // Todo: Error code.
                }

                offset += entry.name_length + size_of(Directory_Entry);
                continue;
            }

            // Found a free entry. Is there enough space? (Empty length means the rest of the block is free.)
            space_available := ifx cast(s64) entry.name_length else 0x20_0000 - offset - size_of(Directory_Entry);

            if space_available >= child_name.count {
                // Found a suitable directory entry. Double-pin the block and remember this slot, but keep scanning to make sure there's no duplicate.
                found_slot = entry;
                pin_disk_block(fs, it.*);
            }

            // Go to the next slot.
            offset += space_available + size_of(Directory_Entry);
        }
    }

    if !found_slot {
        // Improbable, but may need to be handled in the future, depending on how the rest of the system works.
        assert(false);
        return;
    }

    found_slot.inode_id    = child_id;
    found_slot.name_length = cast(s32) child_name.count;
    memcpy(*found_slot.name_bytes, child_name.data, child_name.count);

    parent.modified = time_now;
    parent.directory_entries += 1;

    unpin_disk_block(found_slot); // Any direct-mapped virtual address in the block can be used to unpin the block.
}

remove_directory_entry :: (fs: Mounted_File_System, parent_id: s64, child_name: string) {
    // Todo: This code is very similar to get_directory_entry, deduplicate that.

    parent := lookup_inode(fs, parent_id);
    assert(parent.type == .DIRECTORY);

    for parent.data_blocks {
        if it == 0 {
            // The block has not been allocated and we haven't found the child entry.
            assert(false);
            break;
        }

        block := pin_disk_block(fs, it);
        defer unpin_disk_block(block);

        previous: *Directory_Entry;
        offset := 0;

        while true {
            if offset + size_of(Directory_Entry) + 1 >= 0x20_0000 {
                // End of the disk block.
                break;
            }

            entry := cast(*Directory_Entry) (block + offset);

            if entry.name_length == 0 {
                // Rest of the block is ununsed.
                break;
            }

            if entry.inode_id != 0 {
                name := dirent_name(entry);

                if equal_nocase(name, child_name) {
                    // Remove the entry and merge unused entries in both directions.
                    // Todo: This code is hard to read.

                    if previous && previous.inode_id == 0 {
                        previous.name_length += size_of(Directory_Entry) + entry.name_length;
                        entry = previous;
                    }

                    // Is there a next entry? Is it empty? If so, merge.
                    next_offset := cast(s64) entry - cast(s64) block + entry.name_length + size_of(Directory_Entry);

                    if next_offset < 0x20_0000 {
                        assert(next_offset < 0x20_0000 - size_of(Directory_Entry));

                        next := cast(*Directory_Entry) (block + next_offset);
                        assert(next.name_length != 0);

                        if next.inode_id == 0 {
                            entry.name_length += size_of(Directory_Entry) + next.name_length;
                        }
                    }

                    if previous unpin_disk_block(previous);
                    return;
                }
            }

            previous = entry;
            offset += entry.name_length + size_of(Directory_Entry);
        }
    }

    assert(false);
    return; // Failed to find it.
}

get_directory_entry :: (fs: Mounted_File_System, parent_id: s64, child_name: string) -> result_id: s64 {
    parent := lookup_inode(fs, parent_id);
    assert(parent.type == .DIRECTORY);

    for parent.data_blocks {
        if it == 0 {
            // The block has not been allocated and we haven't found the child entry.
            break;
        }

        block := pin_disk_block(fs, it);
        defer unpin_disk_block(block);

        offset := 0;

        while true {
            if offset + size_of(Directory_Entry) + 1 >= 0x20_0000 {
                // End of the disk block.
                break;
            }

            entry := cast(*Directory_Entry) (block + offset);

            if entry.name_length == 0 {
                // Rest of the block is ununsed.
                break;
            }

            name := dirent_name(entry);

            if equal_nocase(name, child_name) {
                return entry.inode_id;
            }

            offset += entry.name_length + size_of(Directory_Entry);
        }
    }

    return 0; // Failed to find it, return invalid inode id.
}

create_directory :: (fs: Mounted_File_System, parent_id: s64, name: string) -> id: s64 {
    time_now := get_system_time();

    child_id := allocate_inode(fs);
    create_directory_entry(fs, parent_id, child_id, name);

    inode := lookup_inode(fs, child_id);
    inode.type     = .DIRECTORY;
    inode.created  = time_now;
    inode.modified = time_now;

    create_directory_entry(fs, child_id, child_id,  ".");
    create_directory_entry(fs, child_id, parent_id, "..");

    inode.directory_entries = 2;

    return child_id;
}

create_file :: (fs: Mounted_File_System, parent_id: s64, name: string) -> id: s64 {
    time_now := get_system_time();

    child_id := allocate_inode(fs);
    create_directory_entry(fs, parent_id, child_id, name);

    inode := lookup_inode(fs, child_id);
    inode.type      = .FILE;
    inode.file_size = 0;
    inode.created   = time_now;
    inode.modified  = time_now;

    return child_id;
}

delete_file :: (fs: Mounted_File_System, parent_id: s64, name: string) {

}

write_file :: (fs: Mounted_File_System, id: s64, data: $T/.[string, []u8]) {
    inode := lookup_inode(fs, id);
    assert(inode.type == .FILE);

    inode.file_size = 0;
    append_to_file(fs, id, data);
}

append_to_file :: (fs: Mounted_File_System, id: s64, data: $T/.[string, []u8]) {
    inode := lookup_inode(fs, id);
    assert(inode && inode.type == .FILE); // Todo: Handle errors.

    current_block   := inode.file_size / 0x20_0000;
    offset_in_block := inode.file_size % 0x20_0000;

    written: int;

    while written < data.count {
        block_index: *u32;

        if current_block < Info_Node.data_blocks.count {
            block_index = *inode.data_blocks[current_block];

            // Todo: If this condition fails we need to use indirect blocks. Or something.
            assert(false);
        }

        if block_index.* == 0 block_index.* = allocate_block(fs);

        block := pin_disk_block(fs, block_index.*);

        bytes_to_write := min(data.count - written, 0x20_0000 - offset_in_block);
        memcpy(block + offset_in_block, data.data + written, bytes_to_write);

        written += bytes_to_write;

        current_block   += 1;
        offset_in_block  = 0;

        unpin_disk_block(block);
    }

    assert(written == data.count);
    inode.file_size += data.count;
    inode.modified = get_system_time();
}

resolve_path :: (fs: Mounted_File_System, path: string, root_id: s64) -> id: s64 {
    // This is a low level routine (like all the routines currently in this file) so this is not where user facing paths come into the system.

    segments := split(path, #char "/",, temp);

    current := root_id;
    for segments {
        assert(!!it); // Don't give us trailing, leading or double slashes.

        current = get_directory_entry(fs, current, it);
        if !current return 0;
    }

    return current;
}



pin_disk_block :: (fs: Mounted_File_System, block_index: u32, overwrite := false) -> *void {
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
    index_0 := (index >> 12);
    index_1 := (index >> 6)   & 63;
    index_2 := (index)        & 63;

    assert(bt.level_2[index_0 * 64 + index_1] & cast(u64) (1 << index_2) > 0, "Attempting to free bit tree slot that wasn't occupied.");

    bt.level_0                         &= cast(u64) ~(1 << index_0);
    bt.level_1[index_0]                &= cast(u64) ~(1 << index_1);
    bt.level_2[index_0 * 64 + index_1] &= cast(u64) ~(1 << index_2);
}

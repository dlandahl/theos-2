
#module_parameters (User_Data_Type := void);

// These callbacks allow the user to connect this file system implementation to their own disk cache system.
// The default versions assume that the whole partition is loaded contiguously in memory, with the base address
// provided through the user data pointer to format_file_system.
//
// Tried to make these module parameters but doesn't really seem to work.

pin_disk_block := (fs: *User_Data_Type, index: u32, overwrite := false) -> *void {
    return fs + index * BLOCK_SIZE;
}

unpin_disk_block := (fs: *User_Data_Type, address: *void) { } // Would probably be better if this got called with the disk block index rather than the virtual address.



File_System :: struct {
    #as user_data: *User_Data_Type;

    // Important data structures that will remain pinned in memory the whole time the system is mounted.
    super_block:    *Super_Block;
    inodes_block: [] Info_Node;
}



// Structs matching the on-disk layout of metadata.

BLOCK_SIZE :: 0x20_0000;

Info_Node :: struct {
    type: enum u8 {
        FILE;
        DIRECTORY;
    }

    file_size: s64;
    #overlay(file_size) directory_entries: s64;

    created:  Disk_Time;
    modified: Disk_Time;

    data_blocks:         [16] u32;
    indirect_data_block:      u32;
}

Directory_Entry :: struct {
    inode_id:    s64 #align 1;
    name_length: s32 #align 1;
    name_bytes:  void;
} #no_padding

#assert size_of(Super_Block) < BLOCK_SIZE;

Super_Block :: struct {
    magic: u64;
    mount_count: int;
    last_mounted_timestamp: Disk_Time;

    free_blocks:       Bit_Tree;
    free_inodes:       Bit_Tree;

    free_small_blocks: Bit_Tree;
    small_block_table: [0x1_0000] u32;
}

Disk_Time :: struct {
    consensus: Apollo_Time;
    monotonic: Apollo_Time;
    clock_generation: int;
}




format_file_system :: (user_data: *User_Data_Type) -> File_System {
    fs: File_System;
    fs.user_data = user_data;

    super_block := cast(*Super_Block) pin_disk_block(fs, 0, overwrite = true);
    memset(super_block, 0, BLOCK_SIZE);

    memcpy(*super_block.magic, "theosfs\0".data, 8);

    // Occupy the first two blocks, as they are the super block and the inodes block.
    super_block.free_blocks.level_2[0] = 0b11;

    time_now := get_disk_time();
    super_block.last_mounted_timestamp = time_now;
    super_block.mount_count = 1;

    fs.super_block = super_block;

    fs.inodes_block.data  = pin_disk_block(fs, 1, overwrite = true);
    fs.inodes_block.count = BLOCK_SIZE / size_of(Info_Node);

    root_id := allocate_inode(fs);
    assert(root_id == 1);

    root := lookup_inode(fs, root_id);
    root.type              = .DIRECTORY;
    root.directory_entries = 0;
    root.created           = time_now;
    root.modified          = time_now;

    create_directory_entry(fs, root_id, root_id, ".");
    create_directory_entry(fs, root_id, root_id, ".."); // It's common that root/.. gives you the root directory. Not sure how useful that is.

    return fs;
}

mount_file_system :: (user_data: *User_Data_Type) -> File_System {
    fs: File_System;
    fs.user_data = user_data;

    super_block := cast(*Super_Block) pin_disk_block(fs, 0);
    assert(super_block.magic == (.*) cast(*u64) "theosfs\0".data);

    time_now := get_disk_time();
    super_block.last_mounted_timestamp = time_now;
    super_block.mount_count += 1;

    fs.super_block = super_block;

    fs.inodes_block.data  = pin_disk_block(fs, 1);
    fs.inodes_block.count = BLOCK_SIZE / size_of(Info_Node);

    return fs;
}

allocate_inode :: (fs: File_System) -> s64 {
    // Lets say inode identifier = 0 means invalid/unitialized.
    identifier := allocate_bit_tree_slot(*fs.super_block.free_inodes);
    return identifier + 1;
}

lookup_inode :: (fs: File_System, identifier: s64) -> *Info_Node {
    assert(identifier > 0, "Tried to lookup invalid inode.");
    return *fs.inodes_block[identifier - 1];
}

allocate_block :: (fs: File_System) -> u32 {
    index := allocate_bit_tree_slot(*fs.super_block.free_blocks);
    return cast(u32) index;
}

get_name :: (entry: *Directory_Entry) -> string {
    return {cast(s64) entry.name_length, *entry.name_bytes};
}

create_directory_entry :: (fs: File_System, parent_id: s64, child_id: s64, child_name: string) {
    time_now := get_disk_time();

    parent := lookup_inode(fs, parent_id);

    found_slot: *Directory_Entry;

    for *parent.data_blocks { // Todo: Doesn't do indirect blocks. Not sure how we'll do directory blocks anyway.
        if it.* == 0 {
            if found_slot break;

            // The block has not been allocated, but we haven't found a free space yet. Allocate a new disk block.
            it.* = allocate_block(fs);
            // Todo: Handle running out of disk blocks.
        }

        block := pin_disk_block(fs, it.*);
        defer  unpin_disk_block(fs, block);

        offset := 0;

        // Look for a free space in the current block.
        while true {
            if offset + size_of(Directory_Entry) + 1 >= BLOCK_SIZE {
                // End of the disk block.
                break;
            }

            entry := cast(*Directory_Entry) (block + offset);

            if entry.inode_id != 0 {
                assert(entry.name_length != 0);

                // Found a non-free entry. Make sure it's not a duplicate.
                name := get_name(entry);

                if equal_nocase(name, child_name) {
                    assert(false);
                    return; // Todo: Error code.
                }

                offset += entry.name_length + size_of(Directory_Entry);
                continue;
            }

            // Found a free entry. Is there enough space? (Empty length means the rest of the block is free.)
            space_available := ifx cast(s64) entry.name_length else BLOCK_SIZE - offset - size_of(Directory_Entry);

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

    unpin_disk_block(fs, found_slot); // Any direct-mapped virtual address in the block can be used to unpin the block.
}

remove_directory_entry :: (fs: File_System, parent_id: s64, child_name: string) {
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
        defer unpin_disk_block(fs, block);

        previous: *Directory_Entry;
        offset := 0;

        while true {
            if offset + size_of(Directory_Entry) + 1 >= BLOCK_SIZE {
                // End of the disk block.
                break;
            }

            entry := cast(*Directory_Entry) (block + offset);

            if entry.name_length == 0 {
                // Rest of the block is ununsed.
                break;
            }

            if entry.inode_id != 0 {
                name := get_name(entry);
                assert(!!name);

                if equal_nocase(name, child_name) {
                    // Remove the entry and merge unused entries in both directions.
                    // Todo: This code is hard to read.

                    if previous && previous.inode_id == 0 {
                        previous.name_length += size_of(Directory_Entry) + entry.name_length;
                        entry = previous;
                    }

                    // Is there a next entry? Is it empty? If so, merge.
                    next_offset := cast(s64) entry - cast(s64) block + entry.name_length + size_of(Directory_Entry);

                    if next_offset < BLOCK_SIZE {
                        assert(next_offset < BLOCK_SIZE - size_of(Directory_Entry));

                        next := cast(*Directory_Entry) (block + next_offset);
                        assert(next.name_length != 0);

                        if next.inode_id == 0 {
                            entry.name_length += size_of(Directory_Entry) + next.name_length;
                        }
                    }

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

get_directory_entry :: (fs: File_System, parent_id: s64, child_name: string) -> result_id: s64 {
    parent := lookup_inode(fs, parent_id);
    assert(parent.type == .DIRECTORY);

    for parent.data_blocks {
        if it == 0 {
            // The block has not been allocated and we haven't found the child entry.
            break;
        }

        block := pin_disk_block(fs, it);
        defer unpin_disk_block(fs, block);

        offset := 0;

        while true {
            if offset + size_of(Directory_Entry) + 1 >= BLOCK_SIZE {
                // End of the disk block.
                break;
            }

            entry := cast(*Directory_Entry) (block + offset);

            if entry.name_length == 0 {
                // Rest of the block is ununsed.
                break;
            }

            name := get_name(entry);

            if equal_nocase(name, child_name) {
                return entry.inode_id;
            }

            offset += entry.name_length + size_of(Directory_Entry);
        }
    }

    return 0; // Failed to find it, return invalid inode id.
}

create_directory :: (fs: File_System, parent_id: s64, name: string) -> id: s64 {
    time_now := get_disk_time();

    child_id := allocate_inode(fs);
    create_directory_entry(fs, parent_id, child_id, name);

    inode := lookup_inode(fs, child_id);
    inode.type     = .DIRECTORY;
    inode.created  = time_now;
    inode.modified = time_now;

    create_directory_entry(fs, child_id, child_id,  ".");
    create_directory_entry(fs, child_id, parent_id, "..");

    return child_id;
}

create_file :: (fs: File_System, parent_id: s64, name: string) -> id: s64 {
    time_now := get_disk_time();

    child_id := allocate_inode(fs);
    create_directory_entry(fs, parent_id, child_id, name);

    inode := lookup_inode(fs, child_id);
    inode.type      = .FILE;
    inode.file_size = 0;
    inode.created   = time_now;
    inode.modified  = time_now;

    return child_id;
}

delete_file :: (fs: File_System, parent_id: s64, name: string) {

}

write_file :: (fs: File_System, id: s64, data: $T/.[string, []u8]) {
    inode := lookup_inode(fs, id);
    assert(inode.type == .FILE);

    inode.file_size = 0;
    append_to_file(fs, id, data);
}

append_to_file :: (fs: File_System, id: s64, data: $T/.[string, []u8]) {
    inode := lookup_inode(fs, id);
    assert(inode && inode.type == .FILE); // Todo: Handle errors.

    current_block   := inode.file_size / BLOCK_SIZE;
    offset_in_block := inode.file_size % BLOCK_SIZE;

    written: int;

    while written < data.count {
        block_index: *u32;

        if current_block < Info_Node.data_blocks.count {
            block_index = *inode.data_blocks[current_block];
        } else {
            // Todo: If this condition fails we need to use indirect blocks. Or something.
            assert(false);
        }

        if block_index.* == 0 block_index.* = allocate_block(fs);

        block := pin_disk_block(fs, block_index.*);

        bytes_to_write := min(data.count - written, BLOCK_SIZE - offset_in_block);
        memcpy(block + offset_in_block, data.data + written, bytes_to_write);

        written += bytes_to_write;

        current_block   += 1;
        offset_in_block  = 0;

        unpin_disk_block(fs, block);
    }

    assert(written == data.count);
    inode.file_size += data.count;
    inode.modified = get_disk_time();
}

resolve_path :: (fs: File_System, root_id: s64, path: string) -> id: s64 {
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

    bt.level_0                         &= ~(1 << index_0);
    bt.level_1[index_0]                &= ~(1 << index_1);
    bt.level_2[index_0 * 64 + index_1] &= ~(1 << index_2);
}



PARTITION_TYPE_GUID :: u8.[190, 186, 254, 202, 206, 250, 173, 219, 222, 202, 240, 0, 0, 0, 0, 0];



get_disk_time := () -> Disk_Time {
    t: Disk_Time;

    // Todo: these might need the user data pointer.
    // t.consensus = get_consensus_time();
    // t.monotonic = get_monotonic_time();
    // t.clock_generation = fs.super_block.mount_count; // Todo.
    return t;
}

#import "Basic";
#import "String";

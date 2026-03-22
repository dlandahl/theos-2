
#import,file "../modules/File_System.jai";
#import,file "../modules/GUID_Partition_Table.jai";

#import "Compiler";
#import "Basic";
#import "File";
#import "File_Utilities";
#import "String";

#run {
    set_build_options_dc(.{ do_output = false });

    push_allocator(temp);

    command_line := get_build_options().compile_time_command_line;

    if !command_line {
        log("Please provide a file on the compile time command line, e.g. \"jai extract_filesystem.jai - disk_image.img\"");
        return;
    }

    file, success := read_entire_file(command_line[0]);

    if !success {
        return;
    }

    file_system_bytes := cast([] u8) file;

    // Detect a GPT and use it to find the partition. Otherwise treat the whole file as containing the file system.
    success=, gpt := parse_gpt_disk_image(file);

    if success {
        for gpt.partition_table {
            if it.type_guid.(string) != PARTITION_TYPE_GUID.(string) continue;

            file_system_bytes.data += cast(s64) it.starting_lba * gpt.sector_size;
            file_system_bytes.count = cast(s64) (it.ending_lba - it.starting_lba) / gpt.sector_size;

            name: string;
            name.data = talloc(it.name.count / size_of(u16));

            for it.name {
                if !it break;

                name.data[it_index] = cast,trunc(u8) it;
                name.count += 1;
            }

            log("Found GPT partition named \"%\" at sector %", name, it.starting_lba);
        }
    }

    fs := mount_file_system(file_system_bytes.data);

    root: Tree_Node;
    root.info    = lookup_inode(fs, 1);
    root.name    = "root_extracted";
    root.entries = get_tree(fs, 1);

    print_tree(root);
    write_tree_out_to_files(fs, root);
}

Tree_Node :: struct {
    info: *Info_Node;
    name: string;

    entries: [] Tree_Node;
}

get_tree :: (fs: File_System, inode_id: s64) -> [] Tree_Node {
    nodes: [..] Tree_Node;

    parent := lookup_inode(fs, inode_id);
    assert(parent.type == .DIRECTORY);

    for parent.data_blocks {
        if it == 0 {
            break;
        }

        block := pin_disk_block(fs, it);

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

            assert(entry.inode_id > 0);
            name := get_name(entry);

            if name != "." && name != ".." {

                node := array_add(*nodes);
                node.name = name;
                node.info = lookup_inode(fs, entry.inode_id);

                if node.info.type == .DIRECTORY {
                    node.entries = get_tree(fs, entry.inode_id);
                }
            }

            offset += entry.name_length + size_of(Directory_Entry);
        }
    }

    return nodes;
}

path: Path;

write_tree_out_to_files :: (fs: *void, root: Tree_Node) {
    array_add(*path.words, root.name);

    current_path := path_to_string(path);
    make_directory_if_it_does_not_exist(current_path);

    for root.entries {
        if it.info.type == {
          case .DIRECTORY;
            write_tree_out_to_files(fs, it);

          case;
            total_bytes := it.info.file_size;
            written := 0;

            buffer := alloc(total_bytes);
            num_blocks := (total_bytes + 0x1f_ffff) / BLOCK_SIZE;

            for block_index: 0..num_blocks-1 {
                base := pin_disk_block(fs, it.info.data_blocks[block_index]);
                to_write := min(0x20_0000, total_bytes - written);

                memcpy(buffer + written, base, to_write);
                written += to_write;
            }

            file_name := join(current_path, "/", it.name);

            write_entire_file(file_name, {total_bytes, buffer});
            log("Extracted file %", file_name);
        }
    }

    path.words.count -= 1;
}

print_tree :: (root: Tree_Node) {

    b: String_Builder;

    Dir_Stack_Entry :: struct {
        using node: Tree_Node;
        entries_printed: int;
    }

    stack: [..] Dir_Stack_Entry;
    stack.allocator = temp;

    root_stack_entry := array_add(*stack);
    root_stack_entry.node = root;

    print(*b, "\n   root\n");

    while true {
        top := peek_pointer(stack);
        total_entries := top.entries.count;

        if top.entries_printed == total_entries {
            pop(*stack);
            if stack.count == 0 break;

            continue;
        }

        for stack {
            is_top       := it_index == stack.count-1;
            last_entry   := it.entries_printed == it.entries.count-1;
            more_entries := it.entries_printed <  it.entries.count;

            if last_entry && is_top {
                print(*b, "   └");
            } else if more_entries && is_top {
                print(*b, "   ├");
            } else if more_entries {
                print(*b, "   │");
            } else {
                print(*b, "    ");
            }
        }

        entry := top.entries[top.entries_printed];

        print(*b, "── %\n", entry.name);
        top.entries_printed += 1;

        if entry.info.type == .DIRECTORY {
            new := array_add(*stack);
            new.node = entry;
        }
    }

    print(*b, "\n");
    write_builder(*b);
}


// Vaguely based on https://developer.apple.com/support/downloads/Apple-File-System-Reference.pdf

// Memory :: #import "Memory";

BLOCK_SIZE :: 0x1000;

BTree_Node :: struct {
    // For now all B+ Trees support variable sized keys and values. We can optimize later once we know what they're used for.
    entries: u32;

    toc_length: u16; // Includes unused TOC space.
    toc_offset: u16;

    free_space_length: u16;
    free_space_offset: u16; // Measured from the beginning of the key area.
    padding_2: u32;

    key_free_list: BTree_Free_List;
    val_free_list: BTree_Free_List;
}

BTree_Free_List :: struct {
    offset: u16;
    length: u16;
}

BTree_Value :: #type,distinct BTree_Key;
BTree_Key :: struct {
    data: *void;
    length: u16;
}
Key_Compare_Func :: #type (a: BTree_Key, b: BTree_Key) -> int;

TOC_Entry :: struct {
    key_offset: u16;
    key_length: u16;

    val_offset: u16;
    val_length: u16;
}

BTree_Node_Expanded :: struct {
    // In-RAM representation of a B-Tree node with some values precomputed. They only become invalid when the node gets defragmented, in which case just call expand again.
    using node: *BTree_Node;

    toc_base: *void;
    key_base: *void;
    val_base: *void;

    compare_keys: Key_Compare_Func;
}

expand_btree_node :: (node: *BTree_Node, compare: Key_Compare_Func) -> BTree_Node_Expanded {
    ex: BTree_Node_Expanded;
    ex.node = node;
    ex.toc_base = cast(*void)(node+1) + node.toc_offset;
    ex.key_base = ex.toc_base + node.toc_length;
    ex.val_base = cast(*void) node + BLOCK_SIZE;
    ex.compare_keys = compare;
    return ex;
}

btree_lookup_entry :: (node: BTree_Node_Expanded, key: BTree_Key) -> BTree_Value {

    toc, exact := btree_find_toc_entry(node, key);
    if !exact {
        return .{};
    }

    val: BTree_Value;
    val.data = node.val_base - toc.val_offset;
    val.length = toc.val_length;

    return val;
}

btree_remove_entry :: no_inline (node: *BTree_Node_Expanded, key: BTree_Key) {

    toc, exact := btree_find_toc_entry(node, key);
    assert(exact);

    {
        // Remove the key by adding it to the free list.

        key_stored: BTree_Key;
        key_stored.data = node.key_base + toc.key_offset;
        key_stored.length = toc.key_length;

        assert(key_stored.length == key.length);
        assert(node.compare_keys(key, key_stored) == 0);

        old_free_list := node.key_free_list;

        node.key_free_list.offset = toc.key_offset;
        node.key_free_list.length += toc.key_length;

        old_free_list.length = toc.key_length;

        (.*) cast(*BTree_Free_List) key_stored.data = old_free_list;
    }

    {
        // Remove the value by adding it to the free list.

        val := node.val_base - toc.val_offset;

        old_free_list := node.val_free_list;

        node.val_free_list.offset = toc.val_offset;
        node.val_free_list.length += toc.val_length;

        old_free_list.length = toc.val_length;

        (.*) cast(*BTree_Free_List) val = old_free_list;
    }

    {
        // Remove the ToC entry by moving the others over.
        offset  := cast(u64) toc - cast(u64) node.toc_base;
        to_copy := cast(u64) (node.entries*size_of(TOC_Entry)) - offset;

        memcpy(toc, toc + 1, cast(s64) to_copy);
    }

    node.entries -= 1;
}

btree_add_entry :: (node: *BTree_Node_Expanded, key: BTree_Key, value: BTree_Value) {
    assert(key.length   % 8 == 0);
    assert(value.length % 8 == 0);

    toc: *TOC_Entry;

    {
        // Add entry to the table of contents.

        toc=, exact := btree_find_toc_entry(node, key);
        assert(!exact);

        offset  := cast(u64) toc - cast(u64) node.toc_base;
        to_copy := cast(u64) (node.entries * size_of(TOC_Entry)) - offset;

        memcpy(toc + 1, toc, cast(s64) to_copy);

        toc.key_length = key.length;
        toc.val_length = value.length;
    }

    {
        // Find a space for the key.
        found, offset := occupy_free_list_slot(*node.key_free_list, node.key_base, key.length, false);

        if found {
            target := node.key_base + offset;
            memcpy(target, key.data, key.length);

            toc.key_offset = offset;
        } else {
            assert(node.free_space_length >= key.length); // Todo: Split node.

            target := node.key_base + node.free_space_offset;
            toc.key_offset = node.free_space_offset;

            memcpy(target, key.data, key.length);

            node.free_space_length -= key.length;
            node.free_space_offset += key.length;
        }
    }

    {
        // Find a space for the value.
        found, offset := occupy_free_list_slot(*node.val_free_list, node.val_base, value.length, true);

        if found {
            target := node.val_base - offset;
            memcpy(target, value.data, value.length);

            toc.val_offset = offset;
        } else {
            assert(node.free_space_length >= value.length);

            target := node.key_base + node.free_space_offset + node.free_space_length - value.length;
            offset := node.val_base - target;

            toc.val_offset = cast(u16) offset;

            memcpy(target, value.data, value.length);

            node.free_space_length -= value.length;
        }
    }

    node.entries += 1;
}

btree_find_toc_entry :: (node: BTree_Node_Expanded, key: BTree_Key) -> *TOC_Entry, exact_match: bool {
    // Find key in the table of contents using binary search.

    l := 0;
    r := cast(int) node.entries - 1;

    while r >= l {
        m := (l + r) / 2;
        toc := cast(*TOC_Entry) node.toc_base + m;

        other_key: BTree_Key;
        other_key.data = node.key_base + toc.key_offset;
        other_key.length = toc.key_length;

        c := node.compare_keys(key, other_key);

        if c < 0 {
            l = m + 1;
        } else if c > 0 {
            r = m - 1;
        } else return toc, true;
    }

    toc := cast(*TOC_Entry) node.toc_base + l;
    return toc, false;
}

occupy_free_list_slot :: (free_list: *BTree_Free_List, base: *void, size: int, negative: bool) -> bool, u16 {

    if free_list.length < size {
        return false, 0;
    }

    curr := free_list;
    last: *BTree_Free_List;

    while curr.offset != 0xffff {

        {
            // Go to next entry. We do this at the beginning of the loop, to skip the special first entry in the node header.
            last = curr;

            if negative  curr = base - curr.offset;
            else         curr = base + curr.offset;
        }

        if curr.length >= size {
            found_offset := last.offset;

            if size == curr.length {
                // We use up the whole space. Remove this entire entry from the freelist.
                last.offset = curr.offset;
            } else {
                // Don't use up the whole space, leave a smaller freelist slot.
                // Todo: Defragment this when running out of space in the node, but when there is enough total space in the freelist.

                last.offset += cast(u16) size;
                curr.length -= cast(u16) size;
            }

            free_list.length -= cast(u16) size;
            return true, found_offset;
        }
    }

    return false, 0;
}



#run {
    #import "String";
    #import "Compiler";

    cl := get_toplevel_command_line();

    // Auto run the test without generating an executable, if the file gets passed to the compiler directly on the command line.
    if cl.count == 2 && ends_with(cl[1], "file_system.jai") {
        set_build_options_dc(.{do_output = false});
        btree_test();
    }
}

btree_test :: () {
    #import "Basic";

    compare_integers :: inline (a: BTree_Key, b: BTree_Key) -> int {
        ai: *int = a.data;
        bi: *int = b.data;

        return bi.* - ai.*;
    }

    node := cast(*BTree_Node) alloc(BLOCK_SIZE);
    node.entries = 0;
    node.toc_length = size_of(TOC_Entry) * 24;
    node.toc_offset = 0;
    node.free_space_length = BLOCK_SIZE - (size_of(BTree_Node) + node.toc_length);
    node.key_free_list.offset = 0xffff;
    node.val_free_list.offset = 0xffff;

    node_ex := expand_btree_node(node, compare_integers);

    for int.[6, 4, 8, 5, 10, 3, 2, 9, 1, 7] {
        k := BTree_Key.{*it, 8};
        v := BTree_Value.{*it, 8};

        btree_add_entry(*node_ex, k, v);
    }

    for int.[2, 1, 9, 5, 8] {
        k := BTree_Key.{*it, 8};
        btree_remove_entry(*node_ex, k);
    }

    for int.[9, 8, 5, 1, 2] {
        k := BTree_Key.{*it, 8};
        v := BTree_Value.{*it, 8};

        btree_add_entry(*node_ex, k, v);
    }

    for int.[3, 4, 10, 8, 7] {
        k := BTree_Key.{*it, 8};
        btree_remove_entry(*node_ex, k);
    }

    for int.[4, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20] {
        k := BTree_Key.{*it, 8};
        v := BTree_Value.{*it, 8};

        btree_add_entry(*node_ex, k, v);
    }

    for int.[4, 1, 2] {
        k := BTree_Key.{*it, 8};
        btree_remove_entry(*node_ex, k);
    }

    for int.[8, 7, 3, 4, 1, 2] {
        k := BTree_Key.{*it, 8};
        v := BTree_Value.{*it, 8};

        btree_add_entry(*node_ex, k, v);
    }

    for 1..20 {
        k := BTree_Key.{*it, 8};
        v := btree_lookup_entry(node_ex, k);

        if !v.data log("Not found: %", (.*) cast(*int) k.data);
        else log("Searching for % found %", (.*) cast(*int) k.data,  (.*) cast(*int) v.data);
    }
}


#import "Basic";
#import "Machine_X64";

main :: () {
    Item :: struct {
        a: int;
        node: List_Node(#this);
        padding: [0x2542]u8;
    }

    head: List_Node(Item);
    list_init(*head);

    for 1..100_000 {
        for 1..3 {
            pollution := alloc(cast(s64) (rdtsc() & 0xffff));
            if it % 2 == 0 free(pollution);
        }

        new := cast(*Item) alloc(size_of(Item) + cast(s64) (rdtsc() & 0xffff));
        new.a = it;

        list_append(*head, *new.node);
    }

    sum: int;

    start := current_time_monotonic();
    for head {
        sum += it.a;
        for 1..1000 #asm { xor r:, r; }
    }
    end   := current_time_monotonic();

    log("Sum: %, elapsed: %ms", sum, to_milliseconds(end - start));
}

prefetch :: (address: *void) #expand {
    #asm { prefetcht0 [address]; }
}









List_Node :: struct (Item: Type) {
    next: *List_Node(Item);
    prev: *List_Node(Item);
}

get_item :: (node: *$T/List_Node) -> *T.Item {

    offset :: #run -> int {
        ti_item := type_info(T.Item);
        ti_node := type_info(T);

        for ti_item.members {
            if it.type == ti_node {
                return it.offset_in_bytes;
            }
        }

        return -1;
    }

    #assert offset != -1;

    return cast(*void) node - offset;
}

list_init :: (head: *List_Node) {
    head.next = head;
    head.prev = head;
}

ensure_initialized :: no_inline (head: *List_Node) {
    if head.next == null {
        list_init(head);
    }
}

insert_after :: (node: *List_Node, prev: *List_Node) {
    next := prev.next;

    next.prev = node;
    prev.next = node;

    node.next = next;
    node.prev = prev;
}

list_append :: (head: *List_Node, node: *List_Node) {
    insert_after(node, head.prev);
}

list_prepend :: (head: *List_Node, node: *List_Node) {
    insert_after(node, head);
}

list_remove :: (node: *List_Node) {
    next := node.next;
    prev := node.prev;

    next.prev = prev;
    prev.next = next;

    node.prev = null;
    node.next = null;
}

list_pop :: (head: *List_Node) -> *head.Item {
    if is_empty(head) return null;

    last := head.prev;
    list_remove(last);

    return get_item(last);
}

is_empty :: (head: *List_Node) -> bool {
    return head.next == head;
}

for_expansion :: (head: *List_Node, body: Code, flags: For_Flags) #expand {

   `it_index := -1;
    node := head.next;

    while node != head {

       `it := get_item(node);
        it_index += 1;

        node = node.next;
        prefetch(node);

        #insert body;
    }
}

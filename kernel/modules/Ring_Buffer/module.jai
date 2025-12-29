
// SPSC ring buffer based on https://fgiesen.wordpress.com/2010/12/14/ring-buffers-and-queues.
// Size must be a power of 2.

Ring_Buffer :: struct {
    buffer: [] u8;

    read_cursor:  int #align 64;
    write_cursor: int #align 64;
}

write_ring_buffer :: (using ring: *Ring_Buffer, data: $T/.[[]u8, string]) -> bytes_written: int {

    used := write_cursor - read_cursor;
    free := buffer.count - used;

    to_write := min(free, data.count);

    wrapped := write_cursor & (buffer.count-1);

    first := min(to_write, buffer.count - wrapped);
    memcpy(buffer.data + wrapped, data.data, first);

    second := to_write - first;
    if second > 0 {
        memcpy(buffer.data, data.data + first, second);
    }

    write_cursor += to_write;
    return to_write;
}

read_ring_buffer :: (using ring: *Ring_Buffer, output: *u8, bytes_wanted: int) -> bytes_read: int {

    available := write_cursor - read_cursor;

    to_read := min(bytes_wanted, available);

    wrapped := read_cursor & (buffer.count-1);

    first := min(to_read, buffer.count - wrapped);
    memcpy(output, buffer.data + wrapped, first);

    second := to_read - first;
    if second > 0 {
        memcpy(output + first, buffer.data, second);
    }

    read_cursor += to_read;
    return to_read;
}

ring_buffer_size :: (using ring: Ring_Buffer) -> int {
    return write_cursor - read_cursor;
}

#scope_module

min :: (x,y) => ifx x < y then x else y;

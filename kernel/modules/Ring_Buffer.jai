
// Todo: "Virtual stream" https://fgiesen.wordpress.com/2010/12/14/ring-buffers-and-queues/

Ring_Buffer :: struct {
    buffer: [] u8;
    read_cursor:  int;
    write_cursor: int;
}

read_ring_buffer :: (using ring: *Ring_Buffer, output: *u8, bytes_wanted: int) -> bytes_read: int {
    wc := write_cursor;

    available := ifx wc >= read_cursor
        then wc - read_cursor
        else buffer.count - (read_cursor - wc);

    to_read := min(bytes_wanted, available);

    first := min(to_read, buffer.count - read_cursor);
    memcpy(output, buffer.data + read_cursor, first);

    second := to_read - first;
    if second > 0 {
        memcpy(output + first, buffer.data, second);
    }

    read_cursor = (read_cursor + to_read) % buffer.count;

    return to_read;
}

write_ring_buffer :: (using ring: *Ring_Buffer, _data: $T/.[[]u8, string]) -> bytes_written: int {
    data := _data;
    rc := read_cursor;

    used := ifx write_cursor >= rc
        then write_cursor - rc
        else buffer.count - (rc - write_cursor);

    free := buffer.count - used - 1;

    to_write := min(free, data.count);

    first := min(to_write, buffer.count - write_cursor);
    memcpy(buffer.data + write_cursor, data.data, first);

    second := to_write - first;
    if second > 0 {
        memcpy(buffer.data, data.data + first, second);
    }

    write_cursor = (write_cursor + to_write) % buffer.count;

    return to_write;
}

#scope_module

min :: (x,y) => ifx x < y then x else y;


#assert POSIX_THREADS;

#import "Basic";
#import "Thread";
#import "Random";
#import "POSIX";

ring: Ring_Buffer;

source: []int;
target: []int;

N :: 100_000_000;

MAX_READ_SIZE :: 64;
MAX_WRITE_SIZE :: 64;

main :: () {

    allocate_ring_buffer(*ring, 4096);

    producer: Thread;
    consumer: Thread;

    source = NewArray(N, int);
    target = NewArray(N, int);

    for 1..N {
        source[it-1] = it;
    }

    thread_init(*producer, (t: *Thread) -> int {
        produced: int;
        random_seed(cast(S128)current_time_monotonic());

        set_core_affinity(4);

        while produced < N {
            numbers_to_write := cast(int)(random_get() % MAX_WRITE_SIZE);
            numbers_to_write = min(numbers_to_write, N - produced);

            bytes_to_write := numbers_to_write * 8;

            buffer: []u8;
            buffer.count = bytes_to_write;
            buffer.data  = cast(*u8)source.data + produced * 8;

            written := write_ring_buffer(*ring, buffer);

            produced += written / 8;
        }

        return 0;
    });

    thread_init(*consumer, (t: *Thread) -> int {
        consumed: int;
        random_seed(cast(S128)current_time_monotonic());

        set_core_affinity(5);

        while consumed < N {
            numbers_to_read := cast(int)(random_get() % MAX_READ_SIZE);
            numbers_to_read = min(numbers_to_read, N - consumed);

            bytes_to_read := numbers_to_read * 8;

            output := cast(*u8)target.data + consumed * 8;

            read := read_ring_buffer(*ring, output, bytes_to_read);

            consumed += read / 8;
        }

        return 0;
    });

    start := current_time_monotonic();
    thread_start(*producer);
    thread_start(*consumer);

    thread_is_done(*producer, -1);
    thread_is_done(*consumer, -1);
    end := current_time_monotonic();

    log("Time elapsed: %ms", to_milliseconds(end - start));

    for 1..N {
        if target[it-1] != it assert(false);
    }
}

set_core_affinity :: (cores: ..int) {
    set: cpu_set_t;

    for core: cores {
        qword := core / 64;
        bit   := core % 64;

        set.__bits[qword] |= cast(u64)(1 << bit);
    }

    self := pthread_self();
    pthread_setaffinity_np(self, size_of(cpu_set_t), *set);
}




// SPSC ring buffer based on multiple articles by F.G.
//     https://fgiesen.wordpress.com/2012/07/21/the-magic-ring-buffer
//     https://fgiesen.wordpress.com/2010/12/14/ring-buffers-and-queues
//
// Size must be a power of 2 and a multiple of the page size.

Ring_Buffer :: struct {
    buffer: [] u8;

    physical_base: u64;

    _: void #align 64; // Cache block that the reader thread writes to.
    read_cursor:  int;
    reserved_read_bytes: int;    

    _: void #align 64; // Cache block that the writer thread writes to.
    write_cursor: int #align 64;
    reserved_write_bytes: int;
}

allocate_ring_buffer :: (ring: *Ring_Buffer, size: int) {
    path: [128] u8;
    static := "/dev/shm/ring-buffer-XXXXXX\0";
    memcpy(path.data, static.data, static.count);

    file_descriptor := mkstemp(path.data);
    assert(file_descriptor > 0);
    assert(unlink(path.data) == 0);

    ring.buffer.count = size;

    assert(ftruncate(file_descriptor, size) == 0);

    ring.buffer.data = mmap(null, xx (size * 2), PROT_NONE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);

    address_0 := mmap(ring.buffer.data, xx size, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_SHARED, file_descriptor, 0);
    assert(address_0 == ring.buffer.data);

    address_1 := mmap(ring.buffer.data + size, xx size, PROT_READ | PROT_WRITE, MAP_FIXED | MAP_SHARED, file_descriptor, 0);
    assert(address_1 == ring.buffer.data + size);

    close(file_descriptor);
}

ring_buffer_start_write :: (ring: *Ring_Buffer, size: int) -> *u8, reserved: int {
    wrapped := ring.write_cursor & (ring.buffer.count-1);
    base_address := ring.buffer.data + wrapped;

    ring.reserved_write_bytes = size;

    // If there is not enough space, just wait and call this again later. It will replace the old reservation.
    return base_address, get_space_available(ring);
}

ring_buffer_finish_write :: (ring: *Ring_Buffer) {
    ring.write_cursor += ring.reserved_write_bytes;
    ring.reserved_write_bytes = 0;
}

ring_buffer_start_read :: (ring: *Ring_Buffer, size: int) -> *u8, reserved: int {
    wrapped := ring.write_cursor & (ring.buffer.count-1);
    base_address := ring.buffer.data + wrapped;

    ring.reserved_read_bytes = size;

    // Same as writing with regards to not having got enough space in the reservation.
    return base_address, get_data_available(ring);
}

ring_buffer_finish_read :: (ring: *Ring_Buffer) {
    ring.read_cursor += ring.reserved_read_bytes;
    ring.reserved_read_bytes = 0;
}

// Slow and dumb API for code that's so.

write_ring_buffer_copy :: (using ring: *Ring_Buffer, data: $T/.[[]u8, string]) -> bytes_written: int {

    to_write := min(data.count, get_space_available(ring));
    wrapped  := write_cursor & (buffer.count-1);

    memcpy(buffer.data + wrapped, data.data, to_write);

    write_cursor += to_write;
    return to_write;
}

read_ring_buffer_copy :: (using ring: *Ring_Buffer, output: *u8, bytes_wanted: int) -> bytes_read: int {

    to_read := min(bytes_wanted, get_data_available(ring));
    wrapped := read_cursor & (buffer.count-1);

    memcpy(output, buffer.data + wrapped, to_read);

    read_cursor += to_read;
    return to_read;
}

get_space_available :: inline (using ring: Ring_Buffer) -> int {
    return write_cursor - read_cursor;
}

get_data_available :: inline (using ring: Ring_Buffer) -> int {
    return buffer.count - (write_cursor - read_cursor);
}

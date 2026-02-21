
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

            written := write_ring_buffer_copy(*ring, buffer);

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

            read := read_ring_buffer_copy(*ring, output, bytes_to_read);

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

    read_cursor:       int;
    read_reserve_size: int;    

    _: void #align 64; // Put stuff that each thread writes to into separate cache blocks.
    write_cursor:       int;
    write_reserve_size: int;
}

allocate_ring_buffer :: (ring: *Ring_Buffer, size: int) {
    // Todo: Think about implications (TLB shootdowns) of creating arbitrary custom memory mappings in the kernel. Because this data structure explicitly has two users (reader and writer) it's hopefully easy to track/clean up TLB.

    assert(size % 4096 == 0);
    page_count := size / 4096;

    physical_base, physical := allocate_page_aligned_physical_memory(size);
    virtual := cast(*void) alloc_block(*global.virtual_block_allocator, cast(u64) size * 2);

    map_pages(virtual,        physical, page_count);
    map_pages(virtual + size, physical, page_count);

    ring.buffer.count = size;
    ring.buffer.data  = virtual;
    ring.physical_base = physical_base;
}

ring_buffer_start_write :: (ring: *Ring_Buffer, size: int) -> *u8, reserved: int {
    // Note to user: If there is not enough space, just wait and call this again later. It will replace the old reservation.

    wrapped := ring.write_cursor & (ring.buffer.count-1);
    base_address := ring.buffer.data + wrapped;

    available := get_space_available(ring);
    ring.write_reserve_size = min(size, available);

    return base_address, available;
}

ring_buffer_finish_write :: (ring: *Ring_Buffer) {
    ring.write_cursor += ring.write_reserve_size;
    ring.write_reserve_size = 0;
}

ring_buffer_start_read :: (ring: *Ring_Buffer, size: int) -> *u8, reserved: int {
    wrapped := ring.write_cursor & (ring.buffer.count-1);
    base_address := ring.buffer.data + wrapped;

    // As with writing regarding available space.
    available := get_data_available(ring);
    ring.read_reserve_size = min(size, available);

    return base_address, ring.read_reserve_size;
}

ring_buffer_finish_read :: (ring: *Ring_Buffer) {
    ring.read_cursor += ring.read_reserve_size;
    ring.read_reserve_size = 0;
}

// API for when buffer read/write is just a memcpy.

write_ring_buffer_copy :: (ring: *Ring_Buffer, data: $T/.[[]u8, string]) -> bytes_written: int {
    assert(ring.write_reserve_size == 0);

    to_write := min(data.count, get_space_available(ring));
    wrapped  := ring.write_cursor & (ring.buffer.count-1);

    memcpy(ring.buffer.data + wrapped, data.data, to_write);

    ring.write_cursor += to_write;
    return to_write;
}

read_ring_buffer_copy :: (ring: *Ring_Buffer, output: *u8, bytes_wanted: int) -> bytes_read: int {
    assert(ring.read_reserve_size == 0);

    to_read := min(bytes_wanted, get_data_available(ring));
    wrapped := ring.read_cursor & (ring.buffer.count-1);

    memcpy(output, ring.buffer.data + wrapped, to_read);

    ring.read_cursor += to_read;
    return to_read;
}

get_space_available :: inline (ring: Ring_Buffer) -> int {
    return ring.buffer.count - (ring.write_cursor - ring.read_cursor);
}

get_data_available :: inline (ring: Ring_Buffer) -> int {
    return ring.write_cursor - ring.read_cursor;
}

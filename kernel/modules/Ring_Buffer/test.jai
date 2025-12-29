
#assert POSIX_THREADS;

#import,file "module.jai";

#import "Basic";
#import "Thread";
#import "Random";
#import "POSIX";

ring: Ring_Buffer;

source: []int;
target: []int;

N :: 100_000_000;

BUFFER_SIZE :: 512;
MAX_READ_SIZE :: 512;
MAX_WRITE_SIZE :: 512;

main :: () {

    ring.buffer = NewArray(BUFFER_SIZE, u8);

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

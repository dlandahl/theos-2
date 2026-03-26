
#import "Basic";
#import "Atomics";

Syscall :: #import "Syscall";

#import "Operating_System";

main :: () {
    log("Beginning thread priority test.");

    threads: [6] Thread_Handle;

    for *threads {
        // Make two threads at each priority level.
        priority  := 20 * it_index;
        name      := tprint("% priority", priority);

        it.* = create_thread(
            entry_point = proc,
            parameter   = xx priority,
            name        = name,
            cpu_core    = 1, // Put them all on the same core.
            priority    = priority,
        );
    }
    
    for threads start_thread(it);
    for threads join_thread(it);

    log("Finished.");
}

proc :: (param: *void) -> int {
    log("Starting thread.");

    start_cpu_time := get_cpu_time();

    start := get_monotonic_time();
    end   := start + seconds_to_apollo(5);

    while get_monotonic_time() < end {
        Syscall.sleep_for_milliseconds(100);

        for 1..1000 {
            if get_monotonic_time() >= end break;
            busy_wait(100);
        }
    }

    end_cpu_time := get_cpu_time();

    cpu_time := to_milliseconds(end_cpu_time - start_cpu_time);

    log("Thread with priority % got %ms of CPU time over 5s of wall clock time.", cast(int) param, cpu_time);

    return 0;
}



busy_wait :: (microseconds: s64) {
    start := get_monotonic_time();
    end   := start + microseconds_to_apollo(microseconds);

    assert(end >= start);

    while get_monotonic_time() < end #asm {
        pause;
    }
}

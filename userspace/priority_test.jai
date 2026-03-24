
#import "Basic";
#import "Atomics";
#import "Machine_X64";

#import "Syscall";

main :: () {
    log("Beginning thread priority test.");

    semaphore = Syscall.create_semaphore();

    for 0..5 {
        // Make two threads at each priority level.

        settings: Thread_Settings;
        settings.priority = 20 * it;

        settings.stack_memory = alloc(0x1_0000);
        settings.stack_size   = 0x1_0000;
        settings.name         = tprint("% priority", settings.priority);
        settings.cpu_core     = 1;

        Syscall.create_thread(proc, *settings);
    }

    for 0..5 Syscall.wait_semaphore(semaphore);

    log("Finished.");
}

counter: int;
semaphore: s64;

proc :: () #no_context {
    push_context,defer_pop;

    start_cpu_time := get_cpu_time();

    start := get_wall_time();
    end   := start + seconds_to_apollo(5);

    while get_wall_time() < end {
        Syscall.sleep_for_milliseconds(100);

        for 1..1000 {
            if get_wall_time() >= end break;
            busy_wait(100);
        }
    }

    end_cpu_time := get_cpu_time();

    cpu_time := end_cpu_time - start_cpu_time;
    log("Priority %ms", to_milliseconds(cpu_time));

    Syscall.signal_semaphore(semaphore);
    Syscall.stop_executing();
}



boot_time: Apollo_Time;
tsc_frequency: u64;

get_wall_time :: () -> Apollo_Time {
    if !tsc_frequency {
        Syscall.get_boot_time(*boot_time);
        tsc_frequency = Syscall.get_tsc_frequency();
    }

    timestamp: Apollo_Time;
    timestamp.low = rdtsc();

    FEMTOSECONDS_PER_SECOND :: 1_000_000_000_000_000;
    timestamp *= FEMTOSECONDS_PER_SECOND;
    timestamp /= cast(s64) tsc_frequency;

    return timestamp + boot_time;
}

get_cpu_time :: () -> Apollo_Time {
    result: Apollo_Time;
    Syscall.thread_cpu_time(*result);
    return result;
}



busy_wait :: (microseconds: s64) {
    start := get_wall_time();
    end   := start + microseconds_to_apollo(microseconds);

    assert(end >= start);

    while get_wall_time() < end #asm {
        pause;
    }
}


Syscall :: #import "Syscall";

main :: () {
    start := get_monotonic_time();

    for 1..100 {
        now := get_monotonic_time();
        log("%: %", it, to_seconds(now - start));

        Syscall.sleep_for_milliseconds(1000);
    }
}



boot_time: Apollo_Time;
tsc_frequency: u64;

get_monotonic_time :: () -> Apollo_Time {
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

#import "Basic";
#import "Machine_X64";

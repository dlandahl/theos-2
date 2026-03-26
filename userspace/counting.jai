
Syscall :: #import "Syscall";

main :: () {
    start := get_monotonic_time();

    for 1..100 {
        now := get_monotonic_time();
        log("%: %", it, to_seconds(now - start));

        Syscall.sleep_for_milliseconds(1000);
    }
}

#import "Operating_System";

#import "Basic";
#import "Machine_X64";

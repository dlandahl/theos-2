
Syscall :: #import "Syscall";

#import "Basic";
#import "Atomics";

main :: () {
    log("Hello world, from user space.");

    for 1..5 {
        settings: Syscall.Thread_Settings;

        settings.stack_size   = 0x1_0000; // 64 Kilobytes.
        settings.stack_memory = alloc(settings.stack_size);
        settings.name         = tprint("Worker %", it);

        Syscall.create_thread(other_thread, *settings);
    }

    for 1..5 {
        log("Main thread sleeping...");
        Syscall.sleep_for_milliseconds(200);
    }

    log("Exiting...");
    Syscall.quit_process();
}

count: int;

other_thread :: () #no_context {
    push_context,defer_pop;

    my_name := atomic_add(*count, 1);

    while true {
        log("Thread % sleeping...", my_name);
        Syscall.sleep_for_milliseconds(200);
    }
}

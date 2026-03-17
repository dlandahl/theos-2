
Syscall :: #import "Syscall";

#import "Basic";

main :: () {
    log("Hello world, from user space.\n");

    for 1..5 {
        stack_size   := 0x1_0000; // 64 Kilobytes.
        stack_memory := alloc(stack_size);

        Syscall.create_thread(other_thread, stack_memory, stack_size);
    }

    for 1..5 {
        log("Main thread sleeping...\n");
        Syscall.sleep_for_milliseconds(200);
    }

    log("Exiting...");
    Syscall.quit_execution_context();
}

count: int;

other_thread :: () #no_context {
    push_context,defer_pop;

    my_name := fetch_add(*count, 1);

    while true {
        log("Thread % sleeping...", my_name);
        Syscall.sleep_for_milliseconds(200);
    }
}

fetch_add :: (value: *$T, add: T) -> T #no_context {
    #asm {
        lock_xadd?T [value], add;
    }
    return add;
}

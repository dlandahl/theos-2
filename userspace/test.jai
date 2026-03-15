
Syscall :: #import "Syscall";

#import "Basic";

main :: () {
    write_string("Hello world, from user space.\n");

    {
        buffer := cast(*int) Syscall.allocate_memory(100);

        for 1..5 buffer[it] = it * 20;

        Syscall.free_memory(buffer);
    }

    for 1..5 Syscall.create_thread(other_thread);

    while true {
        write_string("Main thread sleeping...\n");
        Syscall.sleep_for_milliseconds(200);
    }
}

other_thread :: () #no_context {
    while true {
        write_string("Other thread sleeping...\n");
        Syscall.sleep_for_milliseconds(200);
    }
}

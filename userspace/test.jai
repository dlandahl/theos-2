
Syscall :: #import "Syscall";

#import "Basic";

main :: () {
    write_string("Hello world, from user space.\n");

    Syscall.create_thread(other_thread);

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


Syscall :: #import "Syscall";

#program_export
user_entry :: () #no_context {
    message := "Hello world, from user space.\n";

    Syscall.display_string(message.data, message.count);

    Syscall.stop_executing();
}

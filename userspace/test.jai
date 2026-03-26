
Syscall :: #import "Syscall";

#import "Basic";

main :: () {
    log("Hello world, from user space.");

    path := "text";
    text := "All men around the four seas are brothers.";

    file := Syscall.open_file(path.data, path.count, true, true);

    Syscall.write_to_file(file, text.data, text.count, 0);

    Syscall.close_file(file);

    log("Done.");
}

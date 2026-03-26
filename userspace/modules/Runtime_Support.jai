
Syscall :: #import "Syscall";

#import "Operating_System";

//
// Runtime_Support is less volatile than Preload and contains imports and various biggish code;
// it is considered reasonable that you can mess around with Runtime_Support and ship your own
// version of it.
//

#module_parameters(DEFINE_SYSTEM_ENTRY_POINT: bool, DEFINE_INITIALIZATION: bool, ENABLE_BACKTRACE_ON_CRASH: bool);

#scope_export

// @Cleanup: __element_duplicate should lose its c_call status, and also be faster...!
__element_duplicate :: (start: *u8, num_elements: s64, size: s64) #c_call #no_aoc {
    cursor := start + size;
    for 1..num_elements-1 {
        memcpy(cursor, start, size);
        cursor += size;
    }
}

write_nonnegative_number :: (n: u64, base := 10, to_standard_error := false) #no_context #no_abc #no_aoc {
    if n == 0 {
        write_string("0", to_standard_error);
        return;
    }

    if base > 16  base = 16;
    if base < 2   base = 2;

    ubase := cast,no_check(u64) base;

    // This is of course a horrible hack.
    // A u64 in base 2 can be up to 64 digits,
    // so we need at least that much space. Add a few more digits for superstition.
    buf: [69] u8;

    starting_cursor : s32 = buf.count;
    cursor := starting_cursor;


    while n {
        cursor -= 1;
        index := n % ubase;
        if index <= 9 {
            buf[cursor] = cast(u8)(index + #char "0");
        } else {
            buf[cursor] = cast(u8)(index - 10 + #char "a");
        }

        n /= ubase;
    }

    s: string = ---;
    s.data  = buf.data + cursor;
    s.count = starting_cursor - cursor;
    write_string(s, to_standard_error);
}

write_number :: (n: s64, base := 10, to_standard_error := false) #no_context #no_aoc {
    if n < 0 {
        write_string("-", to_standard_error);
        n = -n;  // Will overflow if this is the most negative s64.
    }

    write_nonnegative_number(cast,no_check(u64) n, base, to_standard_error = to_standard_error);
}

runtime_support_assertion_failed :: (loc: Source_Code_Location, message: string) -> bool {
    write_loc(loc, to_standard_error = true);
    write_string(": Assertion failed", to_standard_error = true);

    if message {
        write_strings(": ", message, "\n", to_standard_error = true);
    } else {
        write_string("!\n", to_standard_error = true);
    }

    print_stack_trace :: (node: *Stack_Trace_Node) {  // @Copypasta from modules/Basic, but without calling print.
        while node {
            // There are two different line numbers available.
            // node.info.location has a line number, but this is the location of
            // the start of the procedure. That may be useful in some cases, but often
            // what we really want is the line number of the procedure call, which is
            // stored in node.line_number. That's what we print in this case.

            if node.info {
                write_string(node.info.location.fully_pathed_filename, to_standard_error = true);
                write_string(":", to_standard_error = true);
                write_nonnegative_number(node.line_number, to_standard_error = true);
                write_string(": ", to_standard_error = true);
                if node.info.name write_string(node.info.name, to_standard_error = true);
                else write_string("(anonymous procedure)", to_standard_error = true);
                write_string("\n", to_standard_error = true);
            }

            node = node.next;
        }
    }

    if context.stack_trace {
        write_string("\nStack trace:\n", to_standard_error = true);
        print_stack_trace(context.stack_trace);
    } else {
        write_string("Exiting.\n", to_standard_error = true);
    }

    __runtime_support_disable_stack_trace = true;

    return true;
}

runtime_support_default_logger :: (message: string, data: *void, info: Log_Info) {
    if !message then return;

    to_standard_error := (info.common_flags & .ERROR) != 0;

    if message[message.count-1] != #char "\n" {
        write_strings(message, "\n", to_standard_error = to_standard_error);
    } else {
        write_string(message, to_standard_error = to_standard_error);
    }
}

c_style_strlen :: (str: *u8) -> s64 #no_context {
    p := str;
    while p.*  { p += 1; }
    return p - str;
}

to_string :: (c_string: *u8) -> string #no_context {
    if c_string == null return "";

    s: string = ---;
    s.data = c_string;
    s.count = c_style_strlen(c_string);

    return s;
}

// @Incomplete: Pass loc to Runtime_Support versions.
__array_bounds_check_fail :: (index: s64, limit: s64, line_number: s64, filename: *u8) #no_context {
    // @Volatile: It is a good idea for these to match the error reports in constant-expression evaluation inside the compiler.
    write_string("Array bounds check failed. (The attempted index is ", to_standard_error = true);
    write_number(index, to_standard_error = true);

    if limit > 0 {
        write_string(", but the highest valid index is ", to_standard_error = true);
        write_number(limit-1, to_standard_error = true);
    } else if limit == 0 {
        write_string(", but the array has dimension 0, so no index is valid", to_standard_error = true);
    } else {
        write_string(", but the array has invalid negative dimension ", to_standard_error = true);
        write_number(limit, to_standard_error = true);
    }

    write_string("). Site is ", to_standard_error = true);
    write_string(to_string(filename), to_standard_error = true);
    write_string(":", to_standard_error = true);
    write_number(line_number, to_standard_error = true);
    write_string(".\n", to_standard_error = true);

    my_panic();
}

__cast_bounds_check_fail :: (pre_value: s64, pre_flags: u32, post_value: s64, post_flags: u32, fatal: u8, line_number: s64, filename: *u8) #no_context {
    bits : s32 = 0;

    NUMBER_FLAG_SIGNED   :: 0x40;
    NUMBER_FLAG_8BIT     :: 0x100;
    NUMBER_FLAG_16BIT    :: 0x200;
    NUMBER_FLAG_32BIT    :: 0x400;
    NUMBER_FLAG_64BIT    :: 0x800;

    if post_flags & NUMBER_FLAG_64BIT bits = 64;
    if post_flags & NUMBER_FLAG_32BIT bits = 32;
    if post_flags & NUMBER_FLAG_16BIT bits = 16;
    if post_flags & NUMBER_FLAG_8BIT  bits = 8;

    write_string("Cast bounds check failed.  Number must be in [", to_standard_error = true);

    if post_flags & NUMBER_FLAG_SIGNED {
        high_value := (1 << (bits - 1)) - 1;
        low_value  := ~high_value;
        write_number(low_value, to_standard_error = true);
        write_string(", ", to_standard_error = true);
        write_number(high_value, to_standard_error = true);
    } else {
        // We don't yet have our stringent definition of left-shift, so, we are generating results
        // that will vary on different machines unless we check. So let's check.
        high_value: u64;
        if bits == 64 {
            high_value = 0xffff_ffff_ffff_ffff;
        } else {
            high_value = ((cast(u64)1) << bits) - 1;
        }

        write_string("0, ", to_standard_error = true);
        write_nonnegative_number(high_value, to_standard_error = true);
    }

    write_string("]; it was ", to_standard_error = true);

    if pre_flags & NUMBER_FLAG_SIGNED {
        write_number(pre_value, to_standard_error = true);
    } else {
        write_nonnegative_number(cast,no_check(u64) pre_value, to_standard_error = true);
    }

    write_string(".  Site is ", to_standard_error = true);

    write_string(to_string(filename), to_standard_error = true);
    write_string(":", to_standard_error = true);
    write_number(line_number, to_standard_error = true);
    write_string(".\n", to_standard_error = true);

    if fatal my_panic();
}

__null_pointer_check_fail :: (index: s64, line_number: s64, filename: *u8) #no_context {
    // @Volatile: It is a good idea for these to match the error reports in constant-expression evaluation inside the compiler.
    if index {
        // This is a procedure argument.
        write_string("Null pointer check failed: Argument ", to_standard_error = true);
        write_number(index, to_standard_error = true);
        write_string(" is undergoing an automatic dereference, but the pointer is null. Site is ", to_standard_error = true);
    } else {
        // It was a dereference that happened in some other way.
        write_string("Null pointer check failed: A pointer is undergoing an automatic dereference, but the pointer is null. Site is ", to_standard_error = true);
    }

    write_string(to_string(filename), to_standard_error = true);
    write_string(":", to_standard_error = true);
    write_number(line_number, to_standard_error = true);
    write_string(".\n", to_standard_error = true);

    my_panic();
}

__arithmetic_overflow :: (left: s64, right: s64, type_code: u16, line_number: s64, filename: *u8) #no_context #no_aoc {
    // We have some free bits in type_code...!
    fatal  := (type_code & 0x8000);
    signed := (type_code & 0x4000);
    operator_index := (type_code >> 7) & 0x3;
    size := (cast(u64)(type_code & 0x000f))*8;

    signed_string := ifx signed then "s" else "u";
    operator_string := " / ";

    if      operator_index == 1 then operator_string = " + ";
    else if operator_index == 2 then operator_string = " - ";
    else if operator_index == 3 then operator_string = " * ";

    write_string("Arithmetic overflow. We tried to compute:\n    ", to_standard_error = true);

    if signed  write_number(left, to_standard_error = true);
    else       write_nonnegative_number(cast,no_check(u64)left, to_standard_error = true);

    write_string(operator_string, to_standard_error = true);

    if signed  write_number(right, to_standard_error = true);
    else       write_nonnegative_number(cast,no_check(u64)right, to_standard_error = true);

    write_strings("\nThe operand type is ", signed_string, to_standard_error = true);
    write_nonnegative_number(size, to_standard_error = true);
    write_string(", but the result does not fit into this type.\n", to_standard_error = true);

    if fatal my_panic();
}

write_string_unsynchronized :: (s: string, to_standard_error := false) #no_context {
    Syscall.display_string(s.data, s.count);
}

write_string :: (s: string, to_standard_error := false) #no_context #compiler {
    // write_string is marked #compiler because, if called at compile-time, it
    // involves a different implementation that also syncs with the compiler's output.
    // This runtime version of write_string is just about syncing the threads
    // in your own program.

    one_time_init(*synch_initted, init_synchronization());

    runtime_support_acquire(*write_string_lock);
    write_string_unsynchronized(s, to_standard_error);
    runtime_support_release(*write_string_lock);
}

write_strings :: (strings: ..string, to_standard_error := false) #no_context #compiler {
    // write_strings is marked #compiler because, if called at compile-time, it
    // involves a different implementation that also syncs with the compiler's output.
    // This runtime version of write_strings is just about syncing the threads
    // in your own program.

    one_time_init(*synch_initted, init_synchronization());

    runtime_support_acquire(*write_string_lock);
    for strings write_string_unsynchronized(it, to_standard_error);
    runtime_support_release(*write_string_lock);
}

#scope_module;

write_loc :: (loc: Source_Code_Location, to_standard_error := false) #no_context {
    write_strings(loc.fully_pathed_filename, ":", to_standard_error = to_standard_error);
    write_number(loc.line_number, to_standard_error = to_standard_error);
    write_string(",", to_standard_error);
    write_number(loc.character_number, to_standard_error = to_standard_error);
}

my_panic :: () #no_context {
    write_string("Panic.\n", to_standard_error = true);
    debug_break();
}

__panic_due_to_runtime_call_of_compile_time_procedure :: (line_number: s64, filename: *u8) #no_context {
    write_string("Error: Attempt to call a compile-time procedure at runtime. The location of the call was: ", to_standard_error = true);
    write_string(to_string(filename), to_standard_error = true);
    write_string(":", to_standard_error = true);
    write_number(line_number, to_standard_error = true);
    write_string(".\n", to_standard_error = true);

    my_panic();
}

#if DEFINE_INITIALIZATION {
    // TEMPORARY_STORAGE_SIZE is defined by the compiler based on Build_Options.

    first_thread_context: #Context;
    first_thread_temporary_storage: Temporary_Storage;
    first_thread_temporary_storage_data: [TEMPORARY_STORAGE_SIZE] u8 #align 64;

    #scope_export
    #program_export
    __jai_runtime_init :: (argc: s32, argv: **u8) -> *#Context #c_call {
        __command_line_arguments.count = argc;
        __command_line_arguments.data  = argv;

        // We don't need this initializer_of call, but we're leaving it in a comment, in case there are
        // compiler bugs in Context init and you want to work around them by re-enabling it.
        // @Temporary: Putting it back for a bit since there is a bug exhibiting on Mac that might
        // also cause first_thread_context not to be fully filled out...
        initializer_of(#Context)(*first_thread_context);

        ts := *first_thread_temporary_storage;
        set_initial_data(ts, TEMPORARY_STORAGE_SIZE, first_thread_temporary_storage_data.data);
        first_thread_context.temporary_storage = ts;

        return *first_thread_context;
    }

    #program_export
    __jai_runtime_fini :: (_context: *void) #c_call {
        // Nothing here for now!
        // We don't bother shutting down the default allocator. The OS frees the memory.
    }
}

__instrumentation_first  :: () {
    // These are places to insert code, from a metaprogram, if you want
    // that code to run before main().
}

__instrumentation_second :: () {
}

#scope_module;

#if DEFINE_SYSTEM_ENTRY_POINT {
    #program_export "main"
    __system_entry_point :: (argc: s32, argv: **u8) -> s32 #c_call {
        __jai_runtime_init(argc, argv);

        // Really this module is supposed to be for the Jai runtime, not OS runtime. So we should initialize this earlier, before calling the system entry point.
        all_threads_mutex = Syscall.create_mutex();

        push_context first_thread_context {
            #if ENABLE_BACKTRACE_ON_CRASH {
                // It's possible we should move the init of the crash handler to after __instrumentation_*, so that
                // plugins can set it? But, plugin inits can crash. So maybe we need some other way for a plugin
                // to say it's taking over the crash handler.

                Handler :: #import "Runtime_Support_Crash_Handler";
                if false {
                    Handler.init();
                }
            }

            __instrumentation_first ();
            __instrumentation_second();

            __program_main :: () #entry_point;
            no_inline __program_main();
        }

        Syscall.quit_process();
        return 0;
    }
}

allocator_base := cast(*void) 0x4000_0000;
allocator_current_size: s64;

runtime_support_default_allocator_proc ::  (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    // In the future we can properly port the Default_Allocator module to our syscall set, but for now just use a linear bump allocator.

    if mode == {
      case .ALLOCATE;
        aligned_size := (size + 15) & -16;

        result_address     := allocator_base + allocator_current_size;
        allocator_new_size := allocator_current_size + aligned_size;

        pages_used   := (allocator_current_size + 0x1f_ffff) / 0x20_0000;
        pages_needed := (allocator_new_size     + 0x1f_ffff) / 0x20_0000;

        for pages_used .. pages_needed-1 {
            page_frame := Syscall.get_new_page_frame();
            Syscall.map_page(page_frame, allocator_base + it * 0x20_0000);
        }

        allocator_current_size = allocator_new_size;
        return result_address;

      case .RESIZE;
        new_memory := runtime_support_default_allocator_proc(.ALLOCATE, size, 0, null, null);
        memcpy(new_memory, old_memory, old_size);

        return new_memory;
    }

    return null;
}

#scope_export

compile_time_debug_break :: () #compiler #no_context;

debug_break :: () #no_context {
    if #compile_time {
        compile_time_debug_break();
    } else {
        // Break into the debugger, or stop the running process.
        #asm { int3; }
    }
}

// one_time_init is exposed because maybe user libraries want to use a similar thing.
one_time_init :: (synch_value: *s32, to_insert: Code) #expand {
    // A routine to run the code in 'to_insert' only once, even if
    // there are multiple threads. synch_value.* should be 0 at startup.

    // The values of synch_value.*:
    // 0 = uninitialized, 1 = in progress init, 2 = initialized.

    // Courtesy of Jeff Roberts.

    while 1 {
        // @Warning: Apparently this read may not work on ARM, we need to look into it.
        // The goal here is just to avoid the overhead of spamming the compare_and_swap.
        if synch_value.* == 2  break;

        success, old := compare_and_swap(synch_value, 0, 1);
        if old == {
          case 0;
            #insert to_insert;

            if !compare_and_swap(synch_value, 1, 2)  debug_break();  // Should not happen!
          case 1;
            // Maybe some exponential fall offy thing here?
            #if CPU == .X64 {
                for 1..4 #asm { pause; pause; pause; pause; pause; }
            }
            #if CPU == .ARM64 {
                #bytes .[0x3F, 0x20, 0x03, 0xD5]; // YIELD
            }
          case 2;
        }
    }
}

// @Volatile: Context_Base must match internal compiler settings in general.h
// It must exist and be relatively easy to compile (without requiring #run of
// procedures, for example). Context_Base is going to be annoying to edit because
// if you make an error of some kind, even a simple one like an undeclared identifier,
// you won't get a helpful error message.
Context_Base :: struct {
    context_info:  *Type_Info_Struct; // Allow libs or DLLs to see what context we are passing them. Will always be initialized to type_of(Context).

    thread_index   : u32;

    allocator      := default_allocator;

    logger         := runtime_support_default_logger;
    logger_data    :  *void;
    log_source_identifier: u64;      // Arbitrary identifier; settable by the main program.
    log_level      :  Log_Level;     // Settable by the main program to inform anyone who logs.

    temporary_storage: *Temporary_Storage;

    // Currently, for simplicity we don't #if this out right now when _STACK_TRACE is false
    // (but may later). It is probably convenient to let runtime code be able
    // to check context.stack_trace to see if it is null in some cases,
    // rather than needing all that to be #iffed as well. We will see.
    stack_trace: *Stack_Trace_Node;

    assertion_failed := runtime_support_assertion_failed;
    handling_assertion_failure := false;  // Used to avoid assert() infinite loops. Do not mess with this value.

    default_allocator :: Allocator.{runtime_support_default_allocator_proc, null};
}

Temporary_Storage :: struct {  // @Volatile: Must match general.h
    data:     *u8;
    size:     s64;
    current_page_bytes_occupied: s64;
    total_bytes_occupied: s64;
    high_water_mark: s64;
    last_set_mark_location: Source_Code_Location;

    overflow_allocator : Allocator;

    overflow_pages: *Overflow_Page;
    original_data: *u8;  // Data to restore after clearing overflow pages. @Simplify: Maybe could be an Overflow_Page, but maybe we want to be able to assert on overflow_pages==null to ensure performance.
    original_size: s64;

    Overflow_Page :: struct {
        next: *Overflow_Page;
        allocator: Allocator;
        size: s64;
    }
}

set_initial_data :: (ts: *Temporary_Storage, count: s64, data: *u8) #no_context {
    ts.data = data;
    ts.size = count;

    ts.original_data = data;
    ts.original_size = count;
}

#scope_module

init_synchronization :: () #no_context {
}

// Let the user fill this in, if desired.
write_string_lock: void;
runtime_support_acquire :: (lock: *$T) #no_context #expand {}
runtime_support_release :: (lock: *$T) #no_context #expand {}

synch_initted: s32 = 0;




#program_export
memset :: (target: *void, value: u8, count: s64) -> *void #c_call {
    #asm {
        cld;

        count  === c;
        target === di;
        value  === a;
        rep_stos.b target, value, count;
    }

    return target;
}

#program_export
memcpy :: (dst: *void, src: *void, count: s64) -> *void #c_call {
    #asm {
        cld;

        src   === si;
        dst   === di;
        count === c;
        rep_movs.b dst, src, count;
    }

    return dst;
}

libc :: #library,system "libc";

// For some reason the function interposition trick doesn't work with memcmp, even though it works with memset and memcpy.
_memcmp :: (a: *void, b: *void, count: u64) -> s16 #c_call {
    for 0..count-1 {
        if a.(*u8)[it] != b.(*u8)[it] return -1;
    }

    return 0;

    /*
    start := a;

    #asm {
        cld;
        
        count === c;
        a     === si;
        b     === di;
        repe_cmps.b b, a, count;
    }

    if start + count == a {
        return 0;
    }

    return cast(s16) (*(a-1) - *(b-1));
    */
}

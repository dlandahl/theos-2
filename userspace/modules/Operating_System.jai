
// This is a module of user space code to provide a more full featured API around system calls.

Thread_Data :: struct {
    thread_id: int;
    parameter: *void;

    semaphore_for_starting: u64;
    semaphore_for_joining:  u64;

    entry_point: (*void) -> int;
    result: int;
}

Thread_Handle :: Bucket_Locator;

all_threads:       Bucket_Array(Thread_Data, 64);
all_threads_mutex: u64;

create_thread :: (entry_point: (*void) -> int, parameter := null, name := "", priority := 50, cpu_core := -1) -> Thread_Handle {

    settings: Syscall.Thread_Settings;
    settings.priority     = priority;
    settings.stack_memory = alloc(0x1_0000);
    settings.stack_size   = 0x1_0000;
    settings.name         = name;
    settings.cpu_core     = cpu_core;

    Syscall.lock_mutex(all_threads_mutex);

    new_thread_data, locator := find_and_occupy_empty_slot(*all_threads, initialize = false);

    new_thread_data.semaphore_for_starting = Syscall.create_semaphore();
    new_thread_data.semaphore_for_joining  = Syscall.create_semaphore();
    new_thread_data.parameter              = parameter;
    new_thread_data.entry_point            = entry_point;
    new_thread_data.thread_id              = Syscall.create_thread(generic_thread_entry_point, *settings);

    Syscall.unlock_mutex(all_threads_mutex);

    return locator;
}

generic_thread_entry_point :: () #no_context {
    push_context,defer_pop;

    // Find my thread data.
    thread_data: *Thread_Data;
    my_id := Syscall.this_thread_id();

    {
        Syscall.lock_mutex(all_threads_mutex);
        defer Syscall.unlock_mutex(all_threads_mutex);

        // Todo: We could maybe get the operating system to help us with this, or use an additional data structure that's not O(n) to search through.
        for *all_threads {
            if it.thread_id == my_id {
                thread_data = it;
                break;
            }
        }

        assert(!!thread_data);
    }

    Syscall.wait_semaphore(thread_data.semaphore_for_starting);

    thread_data.result = thread_data.entry_point(thread_data.parameter);

    Syscall.signal_semaphore(thread_data.semaphore_for_joining);

    Syscall.stop_executing();
}

// Todo: This probably needs way more error checking.

start_thread :: (thread: Thread_Handle) {
    thread_data := bucket_array_find_pointer(*all_threads, thread);
    Syscall.signal_semaphore(thread_data.semaphore_for_starting);
}

join_thread :: (thread: Thread_Handle) {
    // Todo: Timeout?
    thread_data := bucket_array_find_pointer(*all_threads, thread);
    Syscall.wait_semaphore(thread_data.semaphore_for_joining);
}




read_variable :: (name: string, buffer: *$T) {
    Syscall.read_variable(name.data, name.count, buffer);
}

get_monotonic_time :: () -> Apollo_Time {
    if !tsc_frequency {
        read_variable("tsc_frequency", *tsc_frequency);
        read_variable("boot_time",     *boot_time);
    }

    timestamp: Apollo_Time;
    timestamp.low = rdtsc();

    FEMTOSECONDS_PER_SECOND :: 1_000_000_000_000_000;
    timestamp *= FEMTOSECONDS_PER_SECOND;
    timestamp /= cast(s64) tsc_frequency;

    return timestamp + boot_time;
}

get_cpu_time :: () -> Apollo_Time {
    result: Apollo_Time = ---;
    result.low, result.high = Syscall.thread_cpu_time();
    return result;
}

#scope_module

boot_time:     Apollo_Time;
tsc_frequency: u64;

Syscall :: #import "Syscall";

#import "Basic";
#import "Bucket_Array";
#import "Machine_X64";

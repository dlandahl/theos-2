
#import "Bucket_Array";

Task_Info :: struct {

    // These fields must match the task switch assembly routine
    rsp: *void;
    cr3: u64;
    xsave: Xsave_Area #align 16;

    id: int;
    name: string;

    entry_point: ();

    _context: *#Context;

    user_stack:   *void;
    kernel_stack: *void;

    sleeping: bool;
    waiting_for_mutex: bool;

    sleep_until: Apollo_Time;

    next_sleeping: *Task_Info;

    on_core: *X64_Core;

    cpu_time: Apollo_Time;
}

Scheduler :: struct {
    current_task: *Task_Info;
    idle_task:    *Task_Info;

    sleep_queue:  *Task_Info;

    waiting_to_run: Queue(*Task_Info);

    spinlock: Spinlock;

    last_task_switch_timestamp: Apollo_Time;
}

lock_scheduler_for_task :: (task: *Task_Info) -> X64_Flags {
    // We need to dereference on_core to lock a task, but it can be stale by the time we
    // get the lock. In practice it should almost always work the first time.

    while true {
        core := task.on_core;

        flags := acquire(*core.scheduler.spinlock);

        if task.on_core == core {
            return flags;
        }

        release(*core.scheduler.spinlock, flags);
    }

    return 0;
}

allocate_task_info :: () -> *Task_Info {
    using kernel_globals;

    Scoped_Acquire(*task_info_storage_spinlock);

    locator, task := bucket_array_add(*tasks, .{});
    task.id = next_task_id;
    next_task_id += 1;

    return task;
}

core_begin_multitasking :: () {

    core := get_current_core();
    scheduler := *core.scheduler;

    flags := acquire(*scheduler.spinlock);

    queue_reserve(*scheduler.waiting_to_run, 256);

    scheduler.current_task = allocate_task_info();
    scheduler.current_task.cr3 = cast(u64) *kernel_globals.page_tables.pml4 - DIRECT_MAPPING_BASE;
    scheduler.current_task._context = *context;
    scheduler.current_task.name = "Idle";
    scheduler.idle_task = scheduler.current_task;

    if core.id == 0 {
        // Temporary: during development, I want to keep using thread 0 to do stuff on the bootstrap core. So make a separate idle task.

        idle :: () {
            while true {
                #asm { hlt; }
                schedule_tasks();
            }
        }

        scheduler.idle_task = create_task(idle, 0x2000, name = "Idle");
        scheduler.current_task.name = "Kernel Main";
    }

    release(*scheduler.spinlock, flags);



    // Enable scheduling clock - either LAPIC or preferably TSC Deadline.

    lapic_timer: Apic_Lvt_Timer;

    if kernel_globals.tsc_deadline_support {
        set(*lapic_timer, .timer_mode, APIC_TIMER_MODE_TSC_DEADLINE);

        delay := kernel_globals.tsc_frequency / 10;
        write_msr(.TSC_DEADLINE, rdtsc() + delay);
    } else {
        write_apic_register(.TIC__TIMER_INITIAL, 0x0040_0000);
        set(*lapic_timer, .timer_mode, APIC_TIMER_MODE_PERIODIC);
    }

    set(*lapic_timer, .gate_index, kernel_globals.local_apic_timer_interrupt_gate);
    set(*lapic_timer, .mask,       0);

    write_apic_register(.LVT__TIMER, cast(u32)lapic_timer);
}

put_task_on_core :: (task: *Task_Info, core: *X64_Core) {
    // A weird procedure because tasks are never not associated with a core unless they have never run yet. So we could just put tasks on the core they were created from, and let the caller move them before waking them. That way on_core is never null on any Task_Info we deal with outside of create_task.

    scheduler := *core.scheduler;
    Scoped_Acquire(*scheduler.spinlock);

    if task.on_core != null {
        bluescreen();
    }

    task.on_core = core;
    queue_push(*scheduler.waiting_to_run, task);
}

create_task :: (entry_point: (), kernel_stack_size := 0x4000, user_stack_size := 0, mxcsr := Mxcsr.MASK_ALL, name := "") -> *Task_Info {
    new_task := allocate_task_info();
    new_task.cr3 = cast(u64) *kernel_globals.page_tables.pml4 - DIRECT_MAPPING_BASE;

    new_task.kernel_stack = alloc(kernel_stack_size) + kernel_stack_size;

    if user_stack_size != 0 {
        new_task.user_stack = alloc(user_stack_size) + user_stack_size;
    }

    Context_Switch_Stack :: struct {
        // Represents the stack layout used by the context_switch routine in first.jai
        registers: General_Registers;
        flags: X64_Flags;
        return_address: *void;
    }

    stack := cast(*Context_Switch_Stack) new_task.kernel_stack - 1;
    stack.return_address = cast(*void) new_task_start;
    stack.flags = 0;

    new_task.rsp = cast(*void) stack;
    new_task.xsave.mxcsr = mxcsr;
    new_task.entry_point = entry_point;
    new_task.name = name;

    return new_task;
}

pick_next_task_to_run :: (using scheduler: *Scheduler) -> *Task_Info {
    if !queue_is_empty(waiting_to_run) {
        return queue_pop(*waiting_to_run);
    }

    if !current_task.sleeping && !current_task.waiting_for_mutex {
        return current_task;
    }

    return idle_task;
}

yield_execution :: schedule_tasks; // Yielding is no different from calling into the scheduler on the current core, to see if something else is ready to run.

schedule_tasks :: () {
    core := get_current_core();
    scheduler := *core.scheduler;

    Scoped_Acquire(*scheduler.spinlock);

    time_now := get_monotonic_system_time();

    {
        // Wake sleeping tasks
        using scheduler;

        while sleep_queue && sleep_queue.sleep_until < time_now {
            to_wake := sleep_queue;

            sleep_queue = sleep_queue.next_sleeping;

            to_wake.sleeping = false;
            to_wake.next_sleeping = null;
            queue_push(*waiting_to_run, to_wake);
        }
    }

    current := scheduler.current_task;
    next := pick_next_task_to_run(scheduler);

    if next == current {
        return;
    }

    if !current.sleeping && !current.waiting_for_mutex && current != scheduler.idle_task {
        queue_push(*scheduler.waiting_to_run, current);
    }

    current.cpu_time += time_now - scheduler.last_task_switch_timestamp;
    scheduler.last_task_switch_timestamp = time_now;

    core.task_state_segment.rsp[0] = next.kernel_stack;
    scheduler.current_task = next;

    context_switch :: (current: *Task_Info, next: *Task_Info) #foreign Assembly;
    context_switch(current, next);
}

new_task_start :: () #no_context {
    // When booting a new kernel thread, we could go straight to its entry point, but we always
    // forward through this procedure to conveniently set up the Context and release the scheduler spinlock.

    push_context {
        core := get_current_core();

        release(*core.scheduler.spinlock, 0);

        task := core.scheduler.current_task;
        task._context = *context;

        task.entry_point();

        while true {
            schedule_tasks();
        }

        // Todo: remove the task from the scheduler properly
    }
}

#program_export
scheduling_timer_interrupt :: (stack: *Interrupt_Stack_Frame()) #c_call {
    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);

    if kernel_globals.tsc_deadline_support {
        delay := kernel_globals.tsc_frequency / 10;
        write_msr(.TSC_DEADLINE, rdtsc() + delay);
    }

    core := get_current_core();
    if core.preempt_disable_count > 0 {
        return;
    }

    if stack.cs == .RING0_CODE {
        // Todo: never preempting the kernel for now.
        return;
    }

    push_context {
        schedule_tasks();
    }
} @InterruptRoutine



sleep :: (n: s64, $units: enum {nanoseconds; microseconds; milliseconds; seconds;}) {
    time := #insert #run tprint("%_to_apollo(n);", units);
    sleep(time);
}

sleep :: (time: Apollo_Time) {
    sleep_until(get_monotonic_system_time() + time);
}

sleep_until :: (time: Apollo_Time) {

    scheduler := *get_current_core().scheduler;
    task := scheduler.current_task;

    {
        Scoped_Acquire(*scheduler.spinlock);

        task.sleeping = true;
        task.sleep_until = time;

        queue := scheduler.sleep_queue;
        previous: *Task_Info;

        if !queue {
            scheduler.sleep_queue = task;
            task.next_sleeping = null;
        } else while (true) {

            if !queue || queue.sleep_until > time {
                if queue == scheduler.sleep_queue {
                    scheduler.sleep_queue = task;
                }

                if previous previous.next_sleeping = task;
                task.next_sleeping = queue;

                break;
            }

            previous = queue;
            queue = queue.next_sleeping;
        }
    }

    yield_execution();
}



Mutex :: struct {
    spinlock: Spinlock;
    held_by: *Task_Info;
    queue: Queue(*Task_Info);
}

acquire_mutex :: (mutex: *Mutex) {
    core := get_current_core();
    current_task := core.scheduler.current_task;

    flags := acquire(*mutex.spinlock);

    if mutex.held_by == null {
        assert(queue_is_empty(mutex.queue));

        mutex.held_by = current_task;

        release(*mutex.spinlock, flags);
        return;
    }

    queue_push(*mutex.queue, current_task);
    current_task.waiting_for_mutex = true;

    release(*mutex.spinlock, flags);
    yield_execution();
}

release_mutex :: (mutex: *Mutex) {
    core := get_current_core();
    current_task := core.scheduler.current_task;

    Scoped_Acquire(*mutex.spinlock);

    assert(mutex.held_by == current_task);
    mutex.held_by = null;

    if !queue_is_empty(mutex.queue) {
        next := queue_pop(*mutex.queue);

        // Todo race
        Scoped_Acquire(*next.on_core.scheduler.spinlock);

        assert(next.waiting_for_mutex);

        next.waiting_for_mutex = false;

        queue_push(*next.on_core.scheduler.waiting_to_run, next);
        mutex.held_by = next;

        // Todo: IPI to wake/preempt the other core.
    }
}



yield_from_user_mode :: () #no_context {
    syscall_number := 1;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        syscall c:, _11:, syscall_number;
    }
}

get_current_core_from_user_mode :: () -> *X64_Core #no_context {
    syscall_number := 2;
    core: *X64_Core;

    #asm SYSCALL_SYSRET {
        rax: gpr === a;
        mov rax, syscall_number;
        syscall c:, _11:, rax;
        mov core, rax;
    }

    return core;
}

sleep_from_user_mode :: (time: Apollo_Time) #no_context {
    syscall_number := 3;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        mov low:  gpr === b, [*time + 0];
        mov high: gpr === d, [*time + 8];

        syscall c:, _11:, low, high, syscall_number;
    }
}

print_from_user_mode :: (format: string, args: .. Any) {

    builder: String_Builder;
    print(*builder, format, ..args);
    result := builder_to_string(*builder, do_reset=true);

    data  := result.data;
    count := result.count;

    syscall_number := 4;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        count === b;
        data === d;

        syscall c:, _11:, count, data, syscall_number;
    }
}

allocate_from_user_mode :: (size: int) -> *void {
    syscall_number := 5;

    buffer: *void;

    #asm SYSCALL_SYSRET {
        rax: gpr === a;
        mov rax, syscall_number;
        size === b;

        syscall c:, _11:, rax, size;
        mov buffer, rax;
    }

    return buffer;
}

#program_export
syscall_handler :: (data: *Syscall_Stack_Frame) #c_call {
    push_context,defer_pop;

    if data.rax == {
      case 1;
        yield_execution();

      case 2;
        data.rax = cast(u64) get_current_core();

      case 3;
        t: Apollo_Time;
        t.low  = data.rbx;
        t.high = cast(s64) data.rdx;

        sleep(t);

      case 4;
        s: string;
        s.count = cast(s64) data.rbx;
        s.data  = cast(*u8) data.rdx;
        write_string(s);

      case 5;
        bytes := cast(s64) data.rbx;
        buffer := alloc(bytes);
        data.rax = cast(u64) buffer;

      case;
        write_string("Invalid syscall parameter.\n");
        write_nonnegative_number(data.rax);
        write_string("\n");
        bluescreen();
    }
}

// This is needed by the syscall handler implemented in assembly in first.jai
#program_export
get_kernel_stack :: () -> *void #c_call {
    core := get_current_core();
    return core.scheduler.current_task.kernel_stack;
}

enter_user_mode :: (entry_point: () #c_call, user_stack: *void, flags := X64_Flags.IF__interrupt) #foreign Assembly;



task_do_work :: () {
    core := get_current_core();

    user_stack := core.scheduler.current_task.user_stack;
    entry_point := task_do_work_in_ring_3;

    enter_user_mode(entry_point, user_stack);
}

task_do_work_in_ring_3 :: () #c_call {

    push_context {
        context.allocator.proc = (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
            // Cannot call into the normal allocator as it will use a spinlock, which will disable interrupts, which user mode is not allowed to do.

            if mode != .ALLOCATE && mode != .RESIZE return null;

            buffer := allocate_from_user_mode(size);

            if mode == .RESIZE && old_memory != null {
                memcpy(buffer, old_memory, old_size);
            }

            return buffer;
        }

        core := get_current_core_from_user_mode();
        thread := core.scheduler.current_task;

        while true {
            print_from_user_mode("Thread \"%\" doing some work in user mode, on core %.\n", thread.name, core.id);

            for 1..15_000_000 {
                #asm { pause; }
            }

            ms := rdtsc() % 10000;

            print_from_user_mode("Sleeping for % ms\n", ms);
            sleep_from_user_mode(milliseconds_to_apollo(xx ms));
        }
    }
}

#program_export
spurious_interrupt :: (stack: Interrupt_Stack_Frame()) #c_call {
    write_string("Spurious...\n");
} @InterruptRoutine



Queue :: struct (Item_Type: Type) {
    // Using a resizeable array to hold the underlying data, to get the resizing logic from Basic/Array.jai.
    // items.count does not have any meaning (because count is tail - head), so it gets set such that maybe_grow does the right thing and bounds checking doesn't fail.
    items: [..] Item_Type;
    head: int;
    tail: int;
}

queue_push :: (using queue: *Queue) -> *queue.Item_Type {

    item := *items[tail];
    tail += 1;

    if tail >= items.allocated {
        tail = 0;
    }

    if tail == head {
        old_count := items.allocated;

        items.count = items.allocated + 1;
        maybe_grow(cast(*Resizable_Array) *queue.items, size_of(queue.Item_Type));
        items.count = items.allocated;

        memcpy(
            items.data + items.allocated - head - 1,
            items.data + head,
            (old_count - head + 1) * size_of(Item_Type)
        );

        tail = old_count;
        item = *items[tail-1];
    }

    return item;
}

queue_pop :: (using queue: *Queue) -> queue.Item_Type {
    assert(tail != head);

    item := items[head];
    head += 1;

    if head >= items.allocated {
        head = 0;
    }

    return item;
}

queue_push :: (using queue: *Queue, item: queue.Item_Type) {
    queue_push(queue).* = item;
}

queue_reserve :: (using queue: *Queue, capacity: int) {
    array_reserve(*queue.items, capacity);
    queue.items.count = queue.items.allocated;
}

queue_length :: (using queue: Queue) -> int {
    if tail > head return tail - head;

    return tail + items.allocated - head;
}

queue_is_empty :: (using queue: Queue) -> bool {
    return tail == head;
}

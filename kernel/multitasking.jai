
Task_Info :: struct {

    // These fields must match the task switch assembly routine
    rsp: *void;
    cr3: u64;
    xsave: Xsave_Area #align 16;

    id: int;
    name: string;

    entry_point: ();
    user_data: *void;

    temporary_storage: *Temporary_Storage;

    user_stack:   *void;
    kernel_stack: *void;

    flags: Task_Flags;

    priority: Task_Priority;

    sleep_until: Apollo_Time;

    #as using queue_node: List_Node(#this);

    on_core: *X64_Core;

    cpu_time: Apollo_Time;
}

Task_Priority :: enum {
    Low;
    Normal;
    High;
    Count;
}

Task_Flags :: enum_flags {
    sleeping;
    blocked;
    stopped;
}

Scheduler :: struct {
    current_task: *Task_Info;
    idle_task:    *Task_Info;

    sleeping: List_Node(Task_Info);
    waiting_to_run: [Task_Priority.Count] List_Node(Task_Info);

    spinlock: Spinlock(.IRQ);

    last_task_switch_timestamp: Apollo_Time;
}

lock_scheduler_for_task :: (task: *Task_Info) -> *Scheduler {
    // We need to dereference on_core to lock a task, but it can be stale by the time we
    // get the lock. In practice it should almost always work the first time.
    assert(task.on_core != null);

    while true {
        core := task.on_core;

        acquire(*core.scheduler.spinlock);

        if task.on_core == core {
            return *core.scheduler;
        }

        release(*core.scheduler.spinlock);
    }

    return null;
}

queue_to_run :: (task: *Task_Info) {
    scheduler := *task.on_core.scheduler;

    assert(is_held(scheduler.spinlock), "Caller should take the lock.");

    run_queue := *scheduler.waiting_to_run[task.priority];
    list_append(run_queue, task);
}

get_current_task :: () -> *Task_Info #no_context {
    return cast(*Task_Info) cpu_local_read("scheduler.current_task");
}

set_flag :: (flag: Task_Flags, task: *Task_Info) {
    offset := offset_of(Task_Info, "flags");
    #asm { lock_or?Task_Flags [task + offset], flag; }
}

unset_flag :: (flag: Task_Flags, task: *Task_Info) {
    offset := offset_of(Task_Info, "flags");
    #asm {
        not?Task_Flags flag;
        lock_and?Task_Flags [task + offset], flag;
    }
}

allocate_task_info :: () -> *Task_Info {
    using global;

    acquire(*task_info_storage_spinlock);

    locator, task := bucket_array_add(*tasks, .{});
    task.id = next_task_id;
    next_task_id += 1;

    release(*task_info_storage_spinlock);

    return task;
}

core_begin_multitasking :: () {

    core := get_current_core();
    using core.scheduler;

    current_task = allocate_task_info();
    current_task.cr3 = cast(u64) *global.page_tables.pml4 - DIRECT_MAPPING_BASE;
    current_task.name = sprint("Idle (Core %)", core.id);
    current_task.on_core = core;

    idle_task = current_task;

    if core.id == 0 {
        // Temporary: during development, I want to keep using thread 0 to do stuff on the bootstrap core. So make a separate idle task.

        idle_task = create_task(cpu_idle_loop, 0x8000, name = current_task.name);
        idle_task.on_core = core;

        current_task.name = "Kernel Main";
        current_task.priority = .Normal;
    }

    for *waiting_to_run list_init(it);
    list_init(*sleeping);

    core.online = true;

    // Enable scheduling clock - either LAPIC or preferably TSC Deadline.

    if global.tsc_deadline_support {
        configure_tsc_deadline_interrupt(global.scheduling_interrupt_gate);
    } else {
        configure_apic_timer_interrupt(0x2000000, global.scheduling_interrupt_gate);
    }
}

cpu_idle_loop :: () {
    while true {
        assert(get_rflags() & .IF__interrupt > 0);

        preempt_disable(); // Maybe this is dumb, but if the interrupt that causes 'hlt' to resume is the scheduling clock, we don't need the clock handler to call the scheduler because it will happen anyway. In the future, maybe interrupts should be able to report to whether they require the scheduler to run.
        #asm { hlt; }
        preempt_restore();

        schedule_tasks();
    }
}

put_task_on_core :: (task: *Task_Info, core: *X64_Core) {
    // A weird procedure because tasks are never not associated with a core unless they have never run yet. So we could just put tasks on the core they were created from, and let the caller move them before waking them. That way on_core is never null on any Task_Info we deal with outside of create_task.

    scheduler := *core.scheduler;
    acquire(*scheduler.spinlock);

    if task.on_core != null {
        bluescreen();
    }

    task.on_core = core;

    queue_to_run(task);

    release(*scheduler.spinlock);
}

create_task :: (entry_point: (), kernel_stack_size := 0x4_0000, user_stack_size := 0, name: string, user_data: *void = null) -> *Task_Info {

    new_task := allocate_task_info();
    new_task.cr3 = cast(u64) *global.page_tables.pml4 - DIRECT_MAPPING_BASE;

    new_task.kernel_stack = allocate_guarded_memory(kernel_stack_size, 0x1_0000);
    new_task.kernel_stack += kernel_stack_size;
    new_task.kernel_stack &= ~0xf;

    if user_stack_size != 0 {
        new_task.user_stack = allocate_guarded_memory(user_stack_size, 0x1_0000);
        new_task.user_stack += user_stack_size;
        new_task.user_stack &= ~0xf;

        // SYSRETQ does not push a return address to the stack, but the user mode entry point will push
        // the stack frame pointer, which will be seen by the stack tracing code. The stack tracing code
        // will read past the bottom of the stack trying to record the return address. We therefore need
        // to pad the stack and put a valid-looking return address there to make stack tracing succeed
        // when it meets an 'initial' sysret, that switches a thread to user mode the first time.

        new_task.user_stack -= 8;
        (.*) cast(*u64) new_task.user_stack = DIRECT_MAPPING_BASE;
    }

    Context_Switch_Stack :: struct {
        // This makes it so the stack doesn't become misaligned by the pointer arithmetic below.
        _: void #align 16;

        // Represents the stack layout used by the context_switch routine written in assembly.
        irq_disable_count: s64;
        interrupt_context_active: s64;
        registers: General_Registers;
        flags: X64_Flags;
        return_address: *void;
    }

    stack := cast(*Context_Switch_Stack) new_task.kernel_stack - 1;
    stack.flags = 0;
    stack.return_address = cast(*void) new_task_start;
    stack.irq_disable_count = 1; // The entry point will release the scheduler spinlock. Setting this to 1 will cause that to enable IRQs on that core.

    new_task.rsp = stack;
    new_task.xsave.mxcsr = .MASK_ALL;
    new_task.entry_point = entry_point;
    new_task.name = name;
    new_task.user_data = user_data;
    new_task.priority = .Normal;

    return new_task;
}

yield_execution :: schedule_tasks;

schedule_tasks :: () {

    {
        count := cpu_local_read("preempt_disable_count");
        assert(count == 0, "Context switch with preemption disabled is not allowed.");
    }

    current := get_current_task();
    scheduler := lock_scheduler_for_task(current);

    time_now := get_monotonic_system_time();

    {
        // Wake sleeping tasks.

        for scheduler.sleeping {
            if it.sleep_until > time_now break;

            unset_flag(.sleeping, it);

            list_remove(it);

            // We can get here if the sleep time of the current task was so short that it wakes itself before context switching. In that case we don't put ourselves back on the run queue because that already happens below as standard for the current task.
            if it != current {
                queue_to_run(it);
            }
        }
    }

    next: *Task_Info;

    current_task_still_wants_to_run := current != scheduler.idle_task;
    current_task_still_wants_to_run &&= current.flags & (.sleeping | .blocked | .stopped) == 0;

    // Pick next task to run.

    for<* run_queue: scheduler.waiting_to_run {
        if current_task_still_wants_to_run {
            run_queue_priority := cast(Task_Priority) it_index;

            if run_queue_priority < current.priority {
                break;
            }
        }

        next = list_pop(run_queue);
        if next break;
    }

    if !next {
        // Didn't find a task on any run queue.
        next = ifx current_task_still_wants_to_run then current else scheduler.idle_task;
    }

    if next == current {
        release(*scheduler.spinlock);
        return;
    }

    if current_task_still_wants_to_run {
        queue_to_run(current);
    }

    current.on_core.task_state_segment.rsp[0] = next.kernel_stack;

    current.cpu_time += time_now - scheduler.last_task_switch_timestamp;
    scheduler.last_task_switch_timestamp = time_now;

    trace(.context_switch, current.id, next.id);

    scheduler.current_task = next;

    context_switch(current, next);

    release(*scheduler.spinlock);
}

context_switch :: (current: *Task_Info, next: *Task_Info) #foreign Assembly;

new_task_start :: () #no_context {
    set_stack_trace_sentinel();

    push_context {
        core := get_current_core();
        release(*core.scheduler.spinlock);

        trace(.start_task);

        setup_temporary_storage();

        task := get_current_task();
        task.entry_point();

        shutdown_temporary_storage();

        set_flag(.stopped, task);
        yield_execution();
    }
}

DISABLE_KERNEL_PREEMPTION :: false;

#program_export
scheduling_timer_interrupt :: (stack: *Interrupt_Stack_Frame()) #c_call {
    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);

    defer if global.tsc_deadline_support {
        schedule_tsc_deadline_interrupt(delay_ms = 40);
    }

    core := get_current_core();
    trace(.scheduling_timer, core.preempt_disable_count);

    if core.preempt_disable_count > 0 {
        return;
    }

    if stack.cs == .RING0_CODE && DISABLE_KERNEL_PREEMPTION {
        return;
    }

    push_context {
        schedule_tasks();
    }
} @InterruptRoutine



INFINITE_TIMEOUT :: Apollo_Time.{0xffffffff_ffffffff, 0x7fffffff_ffffffff};

sleep :: (n: s64, $units: enum {nanoseconds; microseconds; milliseconds; seconds;}) {
    time := #insert #run tprint("%_to_apollo(n);", units);
    sleep(time);
}

sleep :: (time: Apollo_Time) {
    prepare_task_sleep(time);
    yield_execution();
}

sleep_until :: (time: Apollo_Time) {
    prepare_task_sleep_until(time);
    yield_execution();
}

// This is separate from prepare-and-yield above, because often you need to put the task to sleep under a lock, but not hold the lock while sleeping, to prevent lost wakeups.
prepare_task_sleep :: (time: Apollo_Time) {
    until := ifx time == INFINITE_TIMEOUT then INFINITE_TIMEOUT else get_monotonic_time() + time;
    prepare_task_sleep_until(until);
}

prepare_task_sleep_until :: (time: Apollo_Time) {
    task := get_current_task();
    scheduler := lock_scheduler_for_task(task);

    defer release(*scheduler.spinlock);

    set_flag(.sleeping, task);

    assert(time > get_monotonic_time());
    task.sleep_until = time;

    for* scheduler.sleeping {
        if it.sleep_until < time continue;

        insert_after(task, it.prev);

        return;
    }

    list_append(*scheduler.sleeping, task);
}

wake_task :: (task: *Task_Info) {
    scheduler := lock_scheduler_for_task(task);

    // By the time we got the lock, the task might not be sleeping anymore.
    if !(task.flags & .sleeping) {
        release(*scheduler.spinlock);
        return;
    }

    unset_flag(.sleeping, task);

    list_remove(task);
    queue_to_run(task);

    if task.priority > scheduler.current_task.priority {
        execute_ipi(.RESCHEDULE_IPI, task.on_core); // Maybe task_info should store the ID of the core rather than a pointer.
    }

    release(*scheduler.spinlock);
}



Mutex :: struct {
    spinlock: Spinlock;
    held_by: *Task_Info;
    queue: List_Node(Task_Info);
}

acquire :: (using mutex: *Mutex) {
    acquire(*spinlock);
    task := get_current_task();

    ensure_initialized(*queue);

    if held_by == null {
        assert(is_empty(*queue));

        held_by = task;

        release(*spinlock);
        return;
    }

    list_append(*queue, task);
    set_flag(.blocked, task);

    release(*spinlock);
    yield_execution();
}

release :: (using mutex: *Mutex) {
    acquire(*spinlock);
    task := get_current_task();

    ensure_initialized(*queue);

    assert(held_by == task);
    held_by = null;

    if is_empty(*queue) {
        release(*spinlock);
        return;
    }

    next := list_pop(*mutex.queue);
    held_by = next;
    release(*spinlock);

    scheduler := lock_scheduler_for_task(next);

    assert(next.flags & .blocked > 0);
    unset_flag(.blocked, next);

    queue_to_run(next);
    release(*scheduler.spinlock);
}

trylock :: (using mutex: *Mutex) -> bool {
    acquire(*spinlock);

    if held_by == null {
        ensure_initialized(*queue);
        assert(is_empty(*queue));

        held_by = get_current_task();

        release(*spinlock);
        return true;
    }

    release(*spinlock);
    return false;
}



Semaphore :: struct {
    counter: int;
    counter_max: int; // 0 means no max.

    Waiter :: struct {
        #as using queue_node: List_Node(#this);

        task: *Task_Info;

        // This is to prevent a race. If we get signalled, but then timeout before being woken, this flag will tell us that this happened and that we're now holding the semaphore despite having timed out.
        signalled: bool;
    }

    queue: List_Node(Waiter);
    spinlock: Spinlock(Lock_Type.IRQ);
}

wait_for :: (using sema: *Semaphore, timeout := INFINITE_TIMEOUT) -> bool {

    acquire(*spinlock);

    if counter > 0 {
        counter -= 1;
        release(*spinlock);
        return true;
    }

    ensure_initialized(*queue);

    waiter: Waiter;
    waiter.task = get_current_task();
    list_append(*queue, *waiter);

    end_time := get_monotonic_time() + timeout;
    remaining_timeout := timeout; // We need to track the timeout over multiple sleep calls due to spurious wakeups.

    while true {
        // Prevent lost-wakeup by setting the task to sleep while still holding the lock.
        prepare_task_sleep(remaining_timeout);

        release(*spinlock);

        yield_execution();

        acquire(*spinlock);

        if waiter.signalled {
            release(*spinlock);
            return true;
        }

        if timeout == INFINITE_TIMEOUT {
            continue;
        }

        woke_at_time := get_monotonic_time();

        if woke_at_time < end_time {
            remaining_timeout -= end_time - woke_at_time;
            continue;
        }

        list_remove(*waiter);

        release(*spinlock);
        return false; // Timeout hit.
    }
}

try_wait :: (using sem: *Semaphore) -> bool {
    acquire(*spinlock);

    if counter > 0 {
        counter -= 1;
        release(*spinlock);
        return true;
    }

    release(*spinlock);
    return false;
}

signal :: (using sema: *Semaphore) {
    acquire(*spinlock);

    ensure_initialized(*queue);

    if is_empty(*queue) {
        counter += 1;

        if counter_max && counter > counter_max {
            counter = counter_max;
        }

        release(*spinlock);
        return;
    }

    waiter := list_pop(*queue);
    waiter.signalled = true;

    wake_task(waiter.task);

    release(*spinlock);
}



Condition_Variable :: struct {
    // Not using a mutex, so that we can notify in interrupt contexts.
    lock: Spinlock(.IRQ);

    Waiter :: struct {
        semaphore: Semaphore;
        queue_node: List_Node(#this);
    }

    wait_queue: List_Node(Waiter);
}

notify :: (using var: *Condition_Variable) {
    acquire(*lock);
    ensure_initialized(*wait_queue);

    waiter := list_pop(*wait_queue);
    signal(*waiter.semaphore);

    release(*lock);
}

notify_all :: (using var: *Condition_Variable) {
    acquire(*lock);
    ensure_initialized(*wait_queue);

    for wait_queue {
        // Remove before signal because waiters may become stale as soon as they get signalled.
        list_remove(*it.queue_node);
        signal(*it.semaphore);
    }

    release(*lock);
}

wait_for :: (using var: *Condition_Variable, user_lock: *$T/Any_Lock, timeout := INFINITE_TIMEOUT) -> bool {
    acquire(*lock);

    waiter: Waiter;
    waiter.semaphore.counter_max = 1;

    ensure_initialized(*wait_queue);
    list_append(*wait_queue, *waiter.queue_node);

    release(*lock);

    release(user_lock);

    signalled := wait_for(*waiter.semaphore, timeout);
    if !signalled {
        // Timed out.
        return false;
    }

    acquire(user_lock);
    return true;
}

wait_for :: (using var: *Condition_Variable, user_lock: *$T/Any_Lock, $predicate: Code, timeout := INFINITE_TIMEOUT) -> bool #expand {
    while !(#insert predicate) {
        return wait_for(var, user_lock, timeout=timeout);
    }
}



Implicit_Lock_Condition_Variable :: struct (Lock := Spinlock) {
    // If you only need one cvar, and you supply both the state change and predicate as #code, the mutex doesn't need to be provided by the user code.
    cvar: Condition_Variable;
    user_lock: Lock;
}

wait_for_condition :: (var: *Implicit_Lock_Condition_Variable, $predicate: Code, timeout := INFINITE_TIMEOUT) -> bool #expand {
    acquire(*var.user_lock);

    result := wait_for(*var.cvar, *var.user_lock, predicate, timeout);

    release(*var.user_lock);
    return result;
}

fulfill_condition :: (var: *Implicit_Lock_Condition_Variable, $state_change: Code) #expand {
    acquire(*var.user_lock);

    #insert state_change;
    notify_all(*var.cvar);

    release(*var.user_lock);
}



simple_create_thread :: ($proc: (param: $T), user_data: T, name := "Simple", format: ..Any, core_id := 2) {
    simple_thread_entry :: () {
        task := get_current_task();
        user_data: T = (.*) cast(*T) task.user_data;

        inline proc(user_data);
    }

    data := alloc(size_of(T));
    memcpy(data, *user_data, size_of(T));

    task := create_task(simple_thread_entry, name = tprint(name, .. format), user_data = data);

    core := *global.processor_cores[core_id];
    assert(core.online);

    put_task_on_core(task, core);

}

simple_create_thread :: ($proc: (), name := "Simple", format: ..Any, core_id := 2) {
    wrapper :: (param: void) {
        inline proc();
    }

    x: void;
    simple_create_thread(wrapper, x, name, format, core_id);
}



// In the future we should generate these using metaprogramming, from a table.

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
    result := builder_to_string(*builder, do_reset=true,, temp);

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

trylock_from_user_mode :: (mutex: *Mutex) -> bool {
    if mutex.held_by != null return false;

    syscall_number := 6;

    success: u64;

    #asm SYSCALL_SYSRET {
        rax: gpr === a;
        mov rax, syscall_number;
        mutex === b;

        syscall c:, _11:, rax, mutex;
        mov success, rax;
    }

    return success > 0;
}

unlock_from_user_mode :: (mutex: *Mutex) {
    syscall_number := 7;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        mutex          === b;

        syscall c:, _11:, syscall_number, mutex;
    }
}

free_from_user_mode :: (address: *void) {
    syscall_number := 8;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        address        === b;

        syscall c:, _11:, syscall_number, address;
    }
}

#program_export
syscall_handler :: (data: *Syscall_Stack_Frame) #c_call {
    push_context,defer_pop;

    trace(.syscall, data.rax);

    task := get_current_task();
    context.temporary_storage = task.temporary_storage;

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
        size     := cast(s64) data.rbx;
        data.rax  = cast(u64) allocate_guarded_memory(size, 0x1_0000);

      case 6;
        mutex    := cast(*Mutex) data.rbx;
        data.rax  = cast(u64) trylock(mutex);

      case 7;
        mutex := cast(*Mutex) data.rbx;
        release(mutex);

      case 8;
        address := cast(*void) data.rbx;

        free_guarded_memory(address);
        
      case;
        write_string("Invalid syscall parameter.\n");
        write_nonnegative_number(data.rax);
        write_string("\n");
        bluescreen();
    }

    reset_temporary_storage();
}

// This is needed by the syscall handler implemented in assembly.
#program_export
get_kernel_stack :: () -> *void #c_call {
    task := get_current_task();
    return task.kernel_stack;
}

enter_user_mode :: (entry_point: () #c_call, user_stack: *void, flags := X64_Flags.IF__interrupt) #foreign Assembly;



task_do_work :: () {
    task := get_current_task();

    user_stack := task.user_stack;
    entry_point := task_do_work_in_ring_3;

    log("Task % entering user mode.", task.name);

    enter_user_mode(entry_point, user_stack);
}

ring_3_work_mutex: Mutex;

ring_3_allocator :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    if mode == {
      case .RESIZE;
        assert(false);

      case .ALLOCATE;
        return allocate_from_user_mode(size);

      case .FREE;
        free_from_user_mode(old_memory);
    }

    return null;
}

user_mode_stress_test :: (threads_per_core := 4, core_mask: u32 = 0xffff_ffff) {
    thread_index := 1;

    for *core: global.processor_cores {
        if core_mask & (1 << core.id) == 0 {
            continue;
        }

        for 1..threads_per_core {
            name := tprint("Do Work %:%", core.id, thread_index);
            task := create_task(task_do_work, kernel_stack_size = 0x4_0000, user_stack_size = 0x4_0000, name = name);
            put_task_on_core(task, core);

            thread_index += 1;
        }
    }
}


memory_test :: () {
    proc :: () {
        task := get_current_task();

        random_seed(rdtsc() ^ (cast(u64)task.id) ^ cast(u64)(task & 0xffff_ffff));

        memory_buffers: [4] struct {
            used: bool;
            size: int;
            data: *void;
            sentinel_value: u8;
        };

        total_clicks: u64;

        for 1..10_000_000 {
            r := random_get() % memory_buffers.count;
            buf := *memory_buffers[r];

            log("Managing memory. Buf = %\n", buf.*);

            start := rdtsc();

            if buf.used {
                for 0..buf.size-1 {
                    assert((.*) (cast(*u8) buf.data + it) == buf.sentinel_value);
                }

                free_guarded_memory(buf.data);
            } else {
                buf.size = cast(s64) (random_get() % 2000) * 4096;
                buf.data = allocate_guarded_memory(buf.size, 0x1_0000);

                buf.sentinel_value = cast,trunc(u8) random_get();

                for 0..buf.size-1 {
                    (.*) (cast(*u8) buf.data + it) = buf.sentinel_value;
                }
            }

            end := rdtsc();
            total_clicks += end - start;

            average_ms := ((total_clicks / cast(u64)it) * 1_000) / global.tsc_frequency;
            log("Running average: %ms", average_ms);

            buf.used = !buf.used;
        }
    }

    threads_per_core := 3;

    for *core: global.processor_cores {
        for 1..threads_per_core {
            task := create_task(proc, kernel_stack_size = 0x4_0000, name = "Memory Tester");
            put_task_on_core(task, core);

        }
    }
}

task_do_work_in_ring_3 :: () #c_call {

    push_context {
        context.allocator.proc = ring_3_allocator;

        ts: Temporary_Storage;
        set_initial_data(*ts, TEMPORARY_STORAGE_SIZE, alloc(TEMPORARY_STORAGE_SIZE));
        context.temporary_storage = *ts;

        core := get_current_core_from_user_mode();
        thread := core.scheduler.current_task;

        random_seed(rdtsc());

        while true {
            print_from_user_mode("Thread \"%\" doing some work in user mode, on core %.\n", thread.name, core.id);

            for 1..1_000_000 {
                #asm { pause; }
            }

            if core.id != 0 if trylock_from_user_mode(*ring_3_work_mutex) {
                print_from_user_mode("Thread \"%\" got the mutex - holding for one second.\n", thread.name);
                sleep_from_user_mode(seconds_to_apollo(1));
                print_from_user_mode("Thread \"%\" releasing mutex.\n", thread.name);
                unlock_from_user_mode(*ring_3_work_mutex);
            }

            ms := random_get() % 2000 + 500;

            print_from_user_mode("Sleeping for % ms.\n", ms);

            start := get_monotonic_time();
            sleep_from_user_mode(milliseconds_to_apollo(xx ms));
            end   := get_monotonic_time();

            print_from_user_mode("Sleep time error: %ms\n", to_milliseconds(end - start) - cast(s64) ms);
        }
    }
}



// Circular doubly linked list.

List_Node :: struct (Item: Type) {

    next: *List_Node(Item);
    prev: *List_Node(Item);

    #if LIST_DEBUG {
        using metadata: List_Debug_Metadata;
    }
}

get_item :: (node: *$T/List_Node) -> *T.Item {

    offset :: #run -> int {
        ti_item := type_info(T.Item);
        ti_node := type_info(T);

        for ti_item.members {
            if it.type == ti_node {
                return it.offset_in_bytes;
            }
        }

        return -1;
    }

    #assert offset != -1;

    return cast(*void) node - offset;
}

list_init :: (head: *List_Node) {
    DEBUG(head);

    head.next = head;
    head.prev = head;
}

ensure_initialized :: no_inline (head: *List_Node) {
    if head.next == null {
        list_init(head);
    }
}

insert_after :: (node: *List_Node, prev: *List_Node) {
    DEBUG(node, prev);

    next := prev.next;

    next.prev = node;
    prev.next = node;

    node.next = next;
    node.prev = prev;
}

list_append :: (head: *List_Node, node: *List_Node) {
    DEBUG(head, node);

    insert_after(node, head.prev);
}

list_prepend :: (head: *List_Node, node: *List_Node) {
    DEBUG(head, node);

    insert_after(node, head);
}

list_remove :: (node: *List_Node) {
    DEBUG(node);

    next := node.next;
    prev := node.prev;

    next.prev = prev;
    prev.next = next;

    node.prev = null;
    node.next = null;
}

list_pop :: (head: *List_Node) -> *head.Item {
    if is_empty(head) return null;

    last := head.prev;
    list_remove(last);

    return get_item(last);
}

is_empty :: (head: *List_Node) -> bool {
    DEBUG(head);
    return head.next == head;
}

for_expansion :: (head: *List_Node, body: Code, flags: For_Flags) #expand {
    DEBUG(head);

   `it_index := -1;
    node := head.next;

    while node != head {
        DEBUG(head, node);

       `it := get_item(node);
        it_index += 1;

        node = node.next;
        prefetch(node);

        #insert body;
    }
}



LIST_DEBUG :: true;

List_Debug_Metadata :: struct {
    is_head: bool;
    my_head: *void;

    // Todo: We could track the caller location of where the node was added to its current list. Then report that (and the expected value) if there's an issue.
}

DEBUG :: (a: *List_Node, b: *List_Node) #expand {
    #if LIST_DEBUG {

        detect_corruption :: (node: *List_Node) {
            assert(node.next != null);
            assert(node.prev != null);

            assert(node.next.prev == node);
            assert(node.prev.next == node);
            assert(node.prev.prev.next == node.prev);
            assert(node.next.next.prev == node.next);
        }

        init      :: #procedure_of_call(list_init    (a));
        insert    :: #procedure_of_call(insert_after (a, b));
        append    :: #procedure_of_call(list_append  (a, b));
        prepend   :: #procedure_of_call(list_prepend (a, b));
        delete    :: #procedure_of_call(list_remove  (a));
        empty     :: #procedure_of_call(is_empty     (a));

        // Can't use a case statement because I can't get the procedures to be constants with the same type as #this. Using compile-time #if == { would be much better though.

        if #this == xx init {
            assert(a.my_head == null);

            a.is_head = true;
            a.my_head = a;
        }

        else if #this == xx insert {
            detect_corruption(b);

            assert(a.my_head == null);
            assert(!a.is_head);

            a.my_head = b.my_head;
        }

        else if #this == xx append || #this == xx prepend || #this == xx empty {
            // 'b' is not in the list yet, or not used in the case of is_empty. 'a' is always a list head, so validate that.
            detect_corruption(a);

            assert(a.is_head);
            assert(a.my_head == a);
        }

        else if #this == xx delete {
            detect_corruption(a);

            assert(a.my_head != null);
            assert(!a.is_head);

            a.my_head = null;
        }

        else {
            // A bit brittle, but here we know it's the for expansion as that's the only other place the macro is expanded.

            if b == null {
                // It's the first DEBUG call, verify the head.
                detect_corruption(a);

                assert(a.is_head);
                assert(a.my_head == a);
            } else {
                // It's one of the subsequent calls, verify the node against the head.
                detect_corruption(b);

                assert(!b.is_head);
                assert(b.my_head == a);
            }
        }
    }
}

DEBUG :: (a: *List_Node) #expand { // Can't use a default null argument because of crazy polymorphism.
    DEBUG(a, cast(type_of(a)) null);
}

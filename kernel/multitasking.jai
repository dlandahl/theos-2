
Task_Info :: struct {

    // These fields must match the task switch assembly routine
    rsp: *void;
    cr3: u64;
    xsave: Xsave_Area #align 16;

    id: int;
    name: string;

    entry_point: ();
    user_data: *void;

    _context: *#Context;

    user_stack:   *void;
    kernel_stack: *void;

    sleeping: bool;
    blocked: bool;

    sleep_until: Apollo_Time;

    #as queue_node: List_Queue(*Task_Info).Node;

    on_core: *X64_Core;

    cpu_time: Apollo_Time;
}

Scheduler :: struct {
    current_task: *Task_Info;
    idle_task:    *Task_Info;

    sleeping:       List_Queue(*Task_Info);
    waiting_to_run: List_Queue(*Task_Info);

    spinlock: Spinlock;

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

get_current_task :: () -> *Task_Info #no_context {
    offset := offset_of(X64_Core, "scheduler.current_task");
    return cast(*Task_Info)gs_relative_read(offset);
}

allocate_task_info :: () -> *Task_Info {
    using global;

    Scoped_Acquire(*task_info_storage_spinlock);

    locator, task := bucket_array_add(*tasks, .{});
    task.id = next_task_id;
    next_task_id += 1;

    return task;
}

core_begin_multitasking :: () {

    core := get_current_core();
    using core.scheduler;

    current_task = allocate_task_info();
    current_task.cr3 = cast(u64) *global.page_tables.pml4 - DIRECT_MAPPING_BASE;
    current_task._context = *context;
    current_task.name = "Idle";
    current_task.on_core = core;
    current_task.queue_node.item = current_task;

    idle_task = current_task;

    if core.id == 0 {
        // Temporary: during development, I want to keep using thread 0 to do stuff on the bootstrap core. So make a separate idle task.

        idle :: () {
            while true {
                #asm { sti; hlt; }
                schedule_tasks();
            }
        }

        idle_task = create_task(idle, 0x2000, name = "Idle");
        idle_task.on_core = core;
        current_task.name = "Kernel Main";
    }

    waiting_to_run.name = sprint("Run Queue (%)", core.id);
    sleeping.name       = sprint("Sleep Queue (%)", core.id);

    core.online = true;

    // Enable scheduling clock - either LAPIC or preferably TSC Deadline.

    if global.tsc_deadline_support {
        configure_tsc_deadline_interrupt(global.scheduling_interrupt_gate);
    } else {
        configure_apic_timer_interrupt(0x400000, global.scheduling_interrupt_gate);
    }
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

create_task :: (entry_point: (), kernel_stack_size := 0x4_0000, user_stack_size := 0, name := "", user_data: *void = null) -> *Task_Info {

    new_task := allocate_task_info();
    new_task.cr3 = cast(u64) *global.page_tables.pml4 - DIRECT_MAPPING_BASE;

    new_task.kernel_stack = alloc(kernel_stack_size);
    new_task.kernel_stack += kernel_stack_size;
    new_task.kernel_stack &= ~0xf;

    if user_stack_size != 0 {
        new_task.user_stack = alloc(user_stack_size);
        new_task.user_stack += user_stack_size;
        new_task.user_stack &= ~0xf;
    }

    Context_Switch_Stack :: struct {
        // This makes it so the stack doesn't become misaligned by the pointer arithmetic below.
        aligner: void #align 16;

        // Represents the stack layout used by the context_switch routine written in assembly.
        registers: General_Registers;
        flags: X64_Flags;
        return_address: *void;
    }

    stack := cast(*Context_Switch_Stack) new_task.kernel_stack - 1;
    stack.return_address = cast(*void) new_task_start;
    stack.flags = 0;

    new_task.rsp = stack;
    new_task.xsave.mxcsr = .MASK_ALL;
    new_task.entry_point = entry_point;
    new_task.name = name;
    new_task.user_data = user_data;
    new_task.queue_node.item = new_task;

    return new_task;
}

yield_execution :: schedule_tasks;

schedule_tasks :: () {
    current := get_current_task();
    scheduler := lock_scheduler_for_task(current);

    time_now := get_monotonic_system_time();

    {
        // Wake sleeping tasks.
        using scheduler;

        for* sleeping {
            if it.sleep_until > time_now break;

            it.sleeping = false;

            remove it;

            // We can get here if the sleep time of the current task was so short that it wakes itself before context switching. In that case we don't put ourselves back on the run queue because that already happens below as standard for the current task.
            if it != current {
                queue_push(*waiting_to_run, it);
            }
        }
    }

    next: *Task_Info;
    current_task_wants_to_run := !current.sleeping && !current.blocked && current != scheduler.idle_task;

    {
        // Pick next task to run.
        if !queue_is_empty(scheduler.waiting_to_run) {
            next = queue_pop(*scheduler.waiting_to_run).item;
        }

        else if current_task_wants_to_run {
            next = current;
        }

        else next = scheduler.idle_task;
    }

    if next == current {
        release(*scheduler.spinlock);
        return;
    }

    if current_task_wants_to_run {
        queue_push(*scheduler.waiting_to_run, current);
    }

    current.cpu_time += time_now - scheduler.last_task_switch_timestamp;
    current.on_core.task_state_segment.rsp[0] = next.kernel_stack;

    scheduler.last_task_switch_timestamp = time_now;
    scheduler.current_task = next;

    context_switch(current, next);

    release(*scheduler.spinlock);
}

context_switch :: (current: *Task_Info, next: *Task_Info) #foreign Assembly;

new_task_start :: () #no_context {
    // When booting a new kernel thread, we could go straight to its entry point, but we always
    // forward through this procedure to conveniently set up the Context and release the scheduler spinlock.

    push_context {
        core := get_current_core();

        release(*core.scheduler.spinlock);

        task := get_current_task();
        task._context = *context;

        task.entry_point();

        // Todo: Hack. This stops the scheduler from putting the task back on the run queue.
        task.blocked = true;
        yield_execution();
    }
}

DISABLE_KERNEL_PREEMPTION :: false;

#program_export
scheduling_timer_interrupt :: (stack: *Interrupt_Stack_Frame()) #c_call {
    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);

    defer if global.tsc_deadline_support {
        schedule_tsc_deadline_interrupt(5);
    }

    core := get_current_core();
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

    task.sleeping = true;
    task.sleep_until = time;

    inserted: bool;

    for* scheduler.sleeping {
        if it.sleep_until < time continue;
        queue_insert(*scheduler.sleeping, it_prev, task);
        inserted = true;
        break;
    }

    if !inserted {
        queue_push(*scheduler.sleeping, task);
    }

    release(*scheduler.spinlock);
}

wake_task :: (task: *Task_Info) {
    scheduler := lock_scheduler_for_task(task);

    // By the time we got the lock, the task might not be sleeping anymore.
    if !task.sleeping {
        release(*scheduler.spinlock);
        return;
    }

    task.sleeping = false;

    queue_remove(*scheduler.sleeping, task);
    queue_push(*scheduler.waiting_to_run, task);

    release(*scheduler.spinlock);
}



Mutex :: struct {
    spinlock: Spinlock;
    held_by: *Task_Info;
    queue: List_Queue(*Task_Info);
}

acquire :: (using mutex: *Mutex) {
    acquire(*spinlock);
    task := get_current_task();

    if held_by == null {
        assert(queue_is_empty(queue));

        held_by = task;

        release(*spinlock);
        return;
    }

    queue_push(*queue, task);
    task.blocked = true;

    release(*spinlock);
    yield_execution();
}

release :: (using mutex: *Mutex) {
    acquire(*spinlock);
    task := get_current_task();

    assert(held_by == task);
    held_by = null;

    if queue_is_empty(queue) {
        release(*spinlock);
        return;
    }

    next := queue_pop(*mutex.queue).item;
    held_by = next;
    release(*spinlock);

    scheduler := lock_scheduler_for_task(next);

    assert(next.blocked);
    next.blocked = false;

    queue_push(*scheduler.waiting_to_run, next);
    release(*scheduler.spinlock);
}

trylock :: (using mutex: *Mutex) -> bool {
    Scoped_Acquire(*spinlock);

    task := get_current_task();

    if held_by == null {
        assert(queue_is_empty(queue));

        held_by = get_current_task();

        return true;
    }

    return false;
}



Semaphore :: struct {
    spinlock: Spinlock(Lock_Type.IRQ);
    counter: int;
    counter_max: int; // 0 means no max.

    Waiter :: struct {
        task: *Task_Info;

        // This is to prevent a race. If we get signalled, but then timeout before being woken, this flag will tell us that this happened and that we're now holding the semaphore despite having timed out.
        signalled: bool;
    }

    queue: List_Queue(Waiter);
}

wait_for :: (using sema: *Semaphore, timeout := INFINITE_TIMEOUT) -> bool {

    acquire(*spinlock);

    if counter > 0 {
        counter -= 1;
        release(*spinlock);
        return true;
    }

    task := get_current_task();

    task.blocked = true;

    waiter: queue.Node;
    waiter.task = task;
    queue_push(*queue, *waiter);

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

        queue_remove(*queue, *waiter);
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

    if queue_is_empty(queue) {
        counter += 1;

        if counter_max && counter > counter_max {
            counter = counter_max;
        }

        release(*spinlock);
        return;
    }

    waiter := queue_pop(*queue);
    waiter.signalled = true;
    waiter.task.blocked = false;

    wake_task(waiter.task);

    release(*spinlock);
}



Condition_Variable :: struct {
    // Not using a mutex, so that we can notify in interrupt contexts.
    lock: Spinlock(.IRQ);

    waiters: List_Queue(Semaphore);
}

notify :: (using var: *Condition_Variable) {
    acquire(*lock);

    waiter := queue_pop(*waiters);
    signal(*waiter.item);

    release(*lock);
}

notify_all :: (using var: *Condition_Variable) {
    acquire(*lock);

    for* waiters {
        // Remove before signal because waiters may become stale as soon as they get signalled.
        remove it;
        signal(*it.item);
    }

    release(*lock);
}

wait_for :: (using var: *Condition_Variable, user_lock: *$T/Any_Lock, timeout := INFINITE_TIMEOUT) -> bool {
    acquire(*lock);

    waiter: waiters.Node;
    waiter.item.counter_max = 1;
    queue_push(*waiters, *waiter);

    release(*lock);

    release(user_lock);

    signalled := wait_for(*waiter.item, timeout);
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



Implicit_Lock_Condition_Variable :: struct (Lock: Type = Spinlock) {
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

      case 6;
        mutex := cast(*Mutex) data.rbx;
        data.rax = cast(u64) trylock(mutex);

      case 7;
        mutex := cast(*Mutex) data.rbx;
        release(mutex);
        
      case;
        write_string("Invalid syscall parameter.\n");
        write_nonnegative_number(data.rax);
        write_string("\n");
        bluescreen();
    }
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
    if mode != .ALLOCATE && mode != .RESIZE return null;

    buffer := allocate_from_user_mode(size);
    if mode == .RESIZE && old_memory != null {
        memcpy(buffer, old_memory, old_size);
    }

    return buffer;
}

task_do_work_in_ring_3 :: () #c_call {

    push_context {
        context.allocator.proc = ring_3_allocator;

        core := get_current_core_from_user_mode();
        thread := core.scheduler.current_task;

        while true {
            print_from_user_mode("Thread \"%\" doing some work in user mode, on core %.\n", thread.name, core.id);

            for 1..1_500_000 {
                #asm { pause; }
            }

            if core.id != 0 if trylock_from_user_mode(*ring_3_work_mutex) {
                print_from_user_mode("Thread \"%\" got the mutex - holding for one second.\n", thread.name);
                sleep_from_user_mode(seconds_to_apollo(1));
                print_from_user_mode("Thread \"%\" releasing mutex.\n", thread.name);
                unlock_from_user_mode(*ring_3_work_mutex);
            }

            ms := rdtsc() % 10000;

            print_from_user_mode("Sleeping for % ms\n", ms);
            sleep_from_user_mode(milliseconds_to_apollo(xx ms));
        }
    }
}



List_Queue :: struct (Item_Type: Type) {
    Node :: struct {
        next: *Node;
        using item: Item_Type;

        // For debugging:
        in_list_queue: *List_Queue(Item_Type);
    }

    first: *Node;
    last:  *Node;

    name: string;
}

for_expansion :: (queue: *List_Queue, body: Code, flags: For_Flags) #expand {
    #assert !(flags & .REVERSE);

    `it_prev: *queue.Node;

    `it := queue.first;
    `it_index: int;

    while true {
        if it == null {
            break;
        }

        assert(it.in_list_queue == queue);

        // Inserted code must be allowed to edit it.next, e.g. to remove 'it' and put it into a different queue.
        it_next := it.next;

        removed: bool;

        defer {
            // Defer, to allow 'continue' to be #inserted below.

            // If the item was removed, the previous item in the list is still the same one as the last iteration.
            it_prev = ifx removed then it_prev else it;

            it = it_next;
            it_index += 1;
        }

        #insert (remove={
            if it_prev it_prev.next = it.next;
            else       queue.first  = it.next;

            if queue.last == it {
                queue.last = it_prev;
            }

            it.next = null;
            it.in_list_queue = null;

            removed = true;
        }) body;
    }
}

queue_insert :: (queue: *List_Queue, after: *queue.Node, item: *queue.Node) {

    assert(item.in_list_queue == null);
    item.in_list_queue = queue;

    if queue.last == after {
        queue.last = item;
    }

    if after == null {
        // If 'after' is null, that means put it at as the first item in the queue. This enables calling 'queue_insert' using 'it_prev' from the for_expansion.
        item.next = queue.first;
        queue.first = item;

        return;
    }

    assert(after.in_list_queue == queue);

    item.next = after.next;
    after.next = item;
}

queue_push :: (queue: *List_Queue, item: *queue.Node) {

    assert(item.in_list_queue == null);
    item.in_list_queue = queue;

    if queue.first == null {
        assert(queue.last == null);

        queue.first = item;
        queue.last = item;

        return;
    }

    assert(queue.last != null);

    queue.last.next = item;
    queue.last      = item;
}

queue_pop :: (queue: *List_Queue) -> *queue.Node {

    assert(queue.first != null);
    result := queue.first;

    queue.first = queue.first.next;
    if queue.first == null queue.last = null;

    assert(result.in_list_queue == queue);

    result.in_list_queue = null;
    result.next = null;
    return result;
}

queue_remove :: (queue: *List_Queue, item: *queue.Node) {
    for* queue.* if it == item {
        remove it;
        break;
    }
}

queue_is_empty :: (queue: List_Queue) -> bool {
    if queue.first == null {
        assert(queue.last == null);
        return true;
    }

    assert(queue.last != null);
    return false;
}



Queue :: struct (Item_Type: Type) {
    // Using a resizeable array to hold the underlying data, to get the resizing logic from Basic/Array.jai.
    // items.count does not have any meaning (because count is tail - head), so it gets set such that maybe_grow does the right thing and bounds checking doesn't fail.
    items: [..] Item_Type;
    head: int;
    tail: int;
}

queue_push :: (using queue: *Queue) -> *queue.Item_Type {
    if !items.allocated {
        queue_reserve(queue, 8);
    }

    item := *items[tail];
    tail += 1;

    if tail >= items.allocated {
        tail = 0;
    }

    if tail == head {
        old_count := items.allocated;

        items.count = items.allocated + 1;
        maybe_grow(cast(*Resizable_Array) *items, size_of(Item_Type));
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
    array_reserve(*items, capacity);
    items.count = items.allocated;
}

queue_length :: (using queue: Queue) -> int {
    if tail > head return tail - head;

    return tail + items.allocated - head;
}

queue_is_empty :: (using queue: Queue) -> bool {
    return tail == head;
}

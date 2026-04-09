
TRACE_ENTRIES_PER_BUFFER :: 0x20_0000 / size_of(Trace_Entry);

Trace_Tag :: enum u16 {
    context_switch;
    start_task;
    create_task;
    create_process;
    scheduling_timer;
    syscall;
    sysret;
    page_fault;
    small_object_alloc;
    small_object_free;
    block_alloc;
    block_free;
    block_resize;
    contended_spinlock;
    irq_disable;
    irq_restore;
    nvme_enqueue;
    nvme_success;
    nvme_failure;
    resched_by_wakeup;
    resched_by_quantum;
    section_break;
    signal_semaphore;
    wait_semaphore;
    message;
}

#assert enum_highest_value(Trace_Tag) <= 32; // Don't accidentally run out of slots in the trace tag mask.

Trace_Header :: struct {
    tsc_frequency:     u64;
    num_trace_entries: int;
    num_cpu_cores:     int;
    string_table_size: int;

    string_table: void;
}

// Outputting this at the start lets us easily skip whatever stuff UEFI wrote to COM2. It's also possible to disable some of that in the bootloader, but some things get output to COM2 before our bootloader runs.
KERNEL_TRACE_MAGIC_STRING :: "kerneltrace";

Trace_Entry :: struct {
    tsc:     u64;
    task_id: u32;
    core_id: u16;
    tag:     Trace_Tag;

    // Meaning of these depends on the trace tag. Could maybe use the new tagged union to type check these.
    user:        [2]  u64;
    stack_trace: [24] u32;
}

Trace_String :: #type,distinct s32;

#assert size_of(Trace_Entry) == 128; // Two cache blocks.

// This file will also be #load-ed by any trace analyser software we create, in which case we only need the above descriptions of the format.
#if TRACE_INCLUDE_RUNTIME_CODE {

    Trace_State :: struct {
        Trace_Buffer :: struct {
            data: [TRACE_ENTRIES_PER_BUFFER] Trace_Entry;
        }

        trace_buffers: [4] *Trace_Buffer;
        string_table:   []  u8;

        current_index: int;
        string_table_size: int;

        max_trace_entries: int;

        tracing_enabled: bool;
        trace_tag_mask: u32; // Set a bit to stop events with that tag from being recorded.
    }

    init_tracing :: () {
        using global.trace_state;

        for* trace_buffers {
            page := allocate_large_page();
            it.* = cast(*Trace_Buffer)(page + DIRECT_MAPPING_BASE);

            // Also store the addresses of the buffers at a known offset in memory, so we can find them in a memory dump, should we ever want to.
            global.boot_data.trace_buffers[it_index] = page;
        }

        max_trace_entries = trace_buffers.count * TRACE_ENTRIES_PER_BUFFER;

        string_table.data  = cast(*u8) allocate_large_page() + DIRECT_MAPPING_BASE;
        string_table.count = 0x20_0000;

        add_trace_string(""); // Make it so that trace string 0 is always an empty string.

        tracing_enabled = true;

        // Disable the spammy tags by default.
        using Trace_Tag;
        trace_tag_mask |= (1 << irq_disable)  | (1 << irq_restore);
        // trace_tag_mask |= (1 << nvme_enqueue) | (1 << nvme_SUCCESS) | (1 << nvme_FAILURE);
    }

    trace :: (tag: Trace_Tag, user_data: ..Any) #no_context {
        using global.trace_state;

        if !tracing_enabled {
            return;
        }

        if trace_tag_mask & (1 << tag) > 0 {
            return;
        }

        index := fetch_add(*current_index, 1);

        if index >= max_trace_entries {
            // Since trace buffers use no synchronization, it's possible to see this message multiple times from different CPU cores if they race.
            tracing_enabled = false; // write_string calls trace, so we have to set this before outputting the warning.
            write_string("Warning: Trace buffer overflow.\n");
            return;
        }

        entry: Trace_Entry;
        entry.tsc = rdtsc();
        entry.task_id = cast(u32) get_task_id();
        entry.core_id = cast(u16) get_core_id();
        entry.tag  = tag;

        for user_data {
            if it.type.runtime_size > size_of(u64) bluescreen();
            if it_index > entry.user.count         bluescreen();

            memcpy(*entry.user[it_index], it.value_pointer, it.type.runtime_size);
        }

        inline do_stack_trace(entry.stack_trace);

        buffer_index    := index / TRACE_ENTRIES_PER_BUFFER;
        index_in_buffer := index % TRACE_ENTRIES_PER_BUFFER;

        trace_buffers[buffer_index].data[index_in_buffer] = entry;
    }

    add_trace_string :: (value: string) -> Trace_String #no_context {
        using global.trace_state;

        if tracing_enabled {
            offset := fetch_add(*string_table_size, value.count + 1);
            memcpy(*string_table[offset], value.data, value.count);
            string_table[offset + value.count] = 0;

            return cast(Trace_String) offset;
        } else {
            return 0;
        }
    }

    serialize_trace_buffers :: (callback: (data: string, user_data: *void), user_data := null) -> num_written: int {
        using global.trace_state;

        // Because this procedure is to be called after completing a kernel test workload, we don't care about extra latency and it's more important to have as controlled an environment as possible.
        irq_disable();

        last_entry_index := min(current_index, max_trace_entries - 1);
        last_string_byte := string_table_size;

        callback(KERNEL_TRACE_MAGIC_STRING, user_data);

        {
            header: Trace_Header;
            header.tsc_frequency     = global.tsc_frequency;
            header.num_trace_entries = last_entry_index;
            header.num_cpu_cores     = global.processor_cores.count;
            header.string_table_size = string_table_size;

            s: string;
            s.data = cast(*u8) *header;
            s.count = size_of(Trace_Header);

            callback(s, user_data);
        }

        {
            s: string;
            s.data  = string_table.data;
            s.count = last_string_byte;
            callback(s, user_data);
        }

        buffer_index    := last_entry_index / TRACE_ENTRIES_PER_BUFFER;
        index_in_buffer := last_entry_index % TRACE_ENTRIES_PER_BUFFER;

        for b: 0..buffer_index {
            s: string;
            s.data = cast(*u8) trace_buffers[b].data.data;

            if b != buffer_index {
                // Write the whole buffer if this isn't the last one.
                s.count = 0x20_0000;
            } else {
                s.count = index_in_buffer * size_of(Trace_Entry);
            }

            callback(s, user_data);
        }

        irq_restore();
        return last_entry_index;
    }

    serialize_trace_buffers :: () -> String_Builder {
        trace: String_Builder;
        init_string_builder(*trace, 0x1_0000);

        callback :: (s: string, trace: *String_Builder) {
            append(trace, s);
        }

        serialize_trace_buffers(xx callback, *trace);

        return trace;
    }

    write_trace_buffers :: () -> int {
        callback :: (s: string, data: *void) {
            serial_out(s, *global.COM2);
        }

        count := serialize_trace_buffers(callback);

        return count;
    }
}

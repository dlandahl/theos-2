
//
// Tracing code restrictions: code in here should be very fast and simple, so that it can easily be called from
// anywhere and not falsify profiling information or influence memory or synchronization bugs. Therefore it
// should not allocate memory (aside from some physical pages during initalization) and it should not use locks
// (except to write out tracing data to the serial port). It should also be available early in boot, so we can debug
// the boot process using it. This means it cannot rely on e.g. CPU-local data or system time to be set up. It
// should also be very simple just to make it easy to keep it bug-free.
//

TRACE_ENTRIES_PER_BUFFER :: 0x20_0000 / size_of(Trace_Entry);

Trace_Tag :: enum u16 {
    context_switch;
}

Trace_Header :: struct {
    tsc_frequency:     u64;
    num_trace_entries: int;
    num_cpu_cores:     int;
    num_threads:       int;

    String_Table_Entry :: struct {
        thread_id:   int;
        name_length: int;
        data: void;
    }

    // An array of structs containing the id and length of each thread name as integers, followed by the actual variable length name.
    string_table: void;
}

// Outputting this at the start lets us easily skip whatever stuff UEFI wrote to COM2. It's also possible to disable some of that in the bootloader, but some things get output to COM2 before our bootloader runs.
KERNEL_TRACE_MAGIC_STRING :: "kerneltrace";

Trace_Entry :: struct {
    tsc:     u64;
    task_id: u16;
    core_id: u8;
    file:    u8;
    line:    u16;
    tag:     Trace_Tag;

    // Meaning of these depends on the trace tag. Could maybe use the new tagged union to type check these.
    user:    [4] u64;
}

// Index in this table will determine the file ID of a trace entry coming from that file.
file_table :: string.[
    "apic.jai",
    "file_system.jai",
    "kernel.jai",
    "multitasking.jai",
    "network.jai",
    "pci_express.jai",
    "time.jai",
    "trace.jai",
    "x64.jai",
];

#assert size_of(Trace_Entry) == 48;

// This file will also be #load-ed by any trace analyser software we create, in which case we only need the above descriptions of the format.
#if TRACE_INCLUDE_RUNTIME_CODE {

    Trace_State :: struct {
        Trace_Buffer :: struct {
            data: [TRACE_ENTRIES_PER_BUFFER] Trace_Entry;
        }

        trace_buffers: [4] *Trace_Buffer;

        current_index: int;

        tracing_enabled: bool;
    }

    init_tracing :: () #no_context {
        using global.trace_state;

        for* trace_buffers {
            page := allocate_large_page();
            it.* = cast(*Trace_Buffer)(page + DIRECT_MAPPING_BASE);

            // Also store the addresses of the buffers at a known offset in memory, so we can find them in a memory dump, should we ever want to.
            global.boot_data.trace_buffers[it_index] = page;
        }

        tracing_enabled = true;
    }

    trace :: inline (tag: Trace_Tag, user_data: ..Any, $loc := #caller_location) {
        // Forwarding through this inline procedure so we don't generate the big procedure below for every caller location just to get the file_id.
        using global.trace_state;

        if !tracing_enabled {
            return;
        }

        file_id :: #run -> u8 {
            for file_table {
                if it == path_filename(loc.fully_pathed_filename) {
                    return cast(u8)it_index;
                }
            }

            assert(false, loc.fully_pathed_filename);
            return 255;
        }

        trace_internal(tag, file_id, cast(u16)loc.line_number, .. user_data);
    }

    trace_internal :: (tag: Trace_Tag, file: u8, line: u16, user_data: ..Any) {
        using global.trace_state;

        index := fetch_add(*current_index, 1);

        entry: Trace_Entry;
        entry.tsc = rdtsc();
        entry.task_id = cast(u16)get_task_id();
        entry.core_id = cast(u8)get_core_id();
        entry.file = file;
        entry.line = line;
        entry.tag  = tag;

        assert(user_data.count <= entry.user.count); // Todo: Would like to compile-time check this.

        for user_data {
            assert(it.type.runtime_size <= size_of(u64));
            memcpy(*entry.user[it_index], it.value_pointer, it.type.runtime_size);
        }

        buffer_index    := index / TRACE_ENTRIES_PER_BUFFER;
        index_in_buffer := index % TRACE_ENTRIES_PER_BUFFER;

        if buffer_index >= trace_buffers.count {
            write_string("Warning: Trace buffer overflow.");
            tracing_enabled = false;
            return;
        }

        trace_buffers[buffer_index].data[index_in_buffer] = entry;
    }

    write_trace_buffers :: () {
        using global.trace_state;

        // Because this procedure is to be called after completing a kernel test workload, we don't care about extra latency and it's more important to have as controlled an environment as possible.
        irq_disable();

        serial_out(KERNEL_TRACE_MAGIC_STRING, *global.COM2);

        last_entry_index := current_index;
        thread_count := global.next_task_id-1;

        {
            header: Trace_Header;
            header.tsc_frequency     = global.tsc_frequency;
            header.num_trace_entries = last_entry_index;
            header.num_cpu_cores     = global.processor_cores.count;
            header.num_threads       = thread_count;

            s: string;
            s.data = cast(*u8) *header;
            s.count = size_of(Trace_Header);
            serial_out(s, *global.COM2);
        }

        {
            string_table_builder: String_Builder;

            // Maybe we want to eventually switch to a data structure where readers don't need to get the lock.
            acquire(*global.task_info_storage_spinlock);
            for global.tasks {
                if it.id > thread_count {
                    continue;
                }

                e: Trace_Header.String_Table_Entry;
                e.thread_id = it.id;
                e.name_length = it.name.count;

                append_by_pointer(*string_table_builder, *e);
                append(*string_table_builder, it.name);
            }
            release(*global.task_info_storage_spinlock);

            // Todo: Maybe do the #code thing suggested in 'modules/String_Builder.write_builder'
            assert(string_table_builder.current_buffer == null, "Todo: iterate string builder buffers and output each of them to the serial port.");

            base_buffer := get_base_buffer(*string_table_builder);

            s: string;
            s.data = get_buffer_data(base_buffer);
            s.count = base_buffer.count;
            serial_out(s, *global.COM2);
        }

        buffer_index    := last_entry_index / TRACE_ENTRIES_PER_BUFFER;
        index_in_buffer := last_entry_index % TRACE_ENTRIES_PER_BUFFER;

        for 0..buffer_index {

            s: string;
            s.data = cast(*u8)trace_buffers[it].data.data;

            if it != buffer_index {
                // Write the whole buffer if this isn't the last one.
                s.count = 0x20_0000;
            } else {
                s.count = index_in_buffer * size_of(Trace_Entry);
            }

            serial_out(s, *global.COM2);
        }

        irq_restore();
    }
}


//
// Tracing code restrictions: code in here should be very fast and simple, so that it can easily be called from
// anywhere and not falsify profiling information or influence memory or synchronization bugs. Therefore it
// should not allocate memory (aside from some physical pages during initalization) and it should not use locks
// (except to write out tracing data to the serial port). It should also be available early in boot, so we can debug
// the boot process using it. This means it cannot rely on e.g. CPU-local data or system time to be set up. It
// should also be very simple just to make it easy to keep it bug-free.
//

// Allocating four 2Mb pages works out to ~half a million trace entries, which should be fine for now.
TRACE_ENTRIES_PER_BUFFER :: 0x20_0000 / size_of(Trace_Entry);

Trace_Tag :: enum u16 {
    
}

Trace_Entry :: struct {
    tsc:       u64;
    task_id:   u16;
    core_id:   u8;
    file:      u8;
    line:      u16;
    tag:       Trace_Tag;
}

// Index in this table will determine the file ID of a trace entry coming from that file.
file_table :: string.[
    "apic.jai",
    "kernel.jai",
    "multitasking.jai",
    "network.jai",
    "pci_express.jai",
    "time.jai",
    "trace.jai",
    "x64.jai",
];

#assert size_of(Trace_Entry) == 16;

// This file will also be #load-ed by any trace analyser software we create, in which case we only need the above descriptions of the format.

#if TRACE_INCLUDE_RUNTIME_CODE {

    Trace_State :: struct {
        Trace_Buffer :: struct {
            data: [TRACE_ENTRIES_PER_BUFFER] Trace_Entry;
        }

        trace_buffers: [4] *Trace_Buffer;

        current_index: int;
    }

    init_tracing :: () #no_context {
        using global.trace_state;

        for* trace_buffers {
            page := allocate_large_page();
            it.* = cast(*Trace_Buffer)(page + DIRECT_MAPPING_BASE);

            // Also store the addresses of the buffers at a known offset in memory, so we can find them in a memory dump, should we ever want to.
            global.boot_data.trace_buffers[it_index] = page;
        }
    }

    trace :: inline (tag: Trace_Tag, $loc := #caller_location) {
        // Forwarding through this inline procedure so we don't generate the big procedure below for every caller location just to get the file_id.

        file_id :: #run -> u8 {
            for file_table {
                if it == path_filename(loc.fully_pathed_filename) {
                    return cast(u8)it;
                }
            }

            assert(false, loc.fully_pathed_filename);
            return 255;
        }

        trace_internal(tag, file_id, cast(u16)loc.line_number);
    }

    trace_internal :: (tag: Trace_Tag, file: u8, line: u16) {
        using global.trace_state;

        index := fetch_add(*current_index, 1);

        entry: Trace_Entry;
        entry.tsc = rdtsc();

        if global.multiprocessing_initialized {
            // Todo: multiprocessing_initialized doesn't mean that scheduling is initialized... so we can't actually do this.
            task := get_current_task();

            entry.core_id = cast(u8)task.on_core.id;
            entry.task_id = cast(u16)task.id;
        }

        entry.file = file;
        entry.line = line;
        entry.tag  = tag;

        buffer_index := index / 0x20_0000;
        index_in_buffer := index % 0x20_0000;

        trace_buffers[buffer_index].data[index_in_buffer] = entry;
    }
}

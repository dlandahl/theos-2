
#import "Basic";

syscall_names :: string.[
    "",
    "display_string",
    "stop_executing",
    "",
    "",
    "create_thread",
    "",
    "get_new_page_frame",
    "map_page",
    "quit_process",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "thread_cpu_time",
    "sleep_for_milliseconds",
    "get_boot_time",
    "get_tsc_frequency",
    "",
    "",
    "",
    "",
    "",
    "",
    "create_semaphore",
    "signal_semaphore",
    "wait_semaphore",
];

Thread_Settings :: struct {
    version := 1;
    stack_memory: *void;
    stack_size: int;
    priority := 50;
    name: string;
    cpu_core: int;
    parameter: *void;
}

display_string :: (data: *u8, count: s64) #no_context {
    syscall_number := 1;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        data === b;
        count === d;

        syscall c:, _11:, syscall_number, data, count;
    }
}

stop_executing :: () #no_context {
    syscall_number := 2;

    #asm SYSCALL_SYSRET {
        syscall_number === a;

        syscall c:, _11:, syscall_number;
    }
}

create_thread :: (entry_point: () #no_context, settings: *Thread_Settings) -> s64 #no_context {
    syscall_number := 5;

    result: u64;

    #asm SYSCALL_SYSRET {
        mov rax: gpr === a, syscall_number;
        entry_point === b;
        settings === d;

        syscall c:, _11:, rax, entry_point, settings;
        mov result, rax;
    }

    return cast(s64) result;
}

get_new_page_frame :: () -> int #no_context {
    syscall_number := 7;

    result: u64;

    #asm SYSCALL_SYSRET {
        mov rax: gpr === a, syscall_number;

        syscall c:, _11:, rax;
        mov result, rax;
    }

    return cast(int) result;
}

map_page :: (page_id: int, virtual_address: *void) #no_context {
    syscall_number := 8;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        page_id === b;
        virtual_address === d;

        syscall c:, _11:, syscall_number, page_id, virtual_address;
    }
}

quit_process :: () #no_context {
    syscall_number := 9;

    #asm SYSCALL_SYSRET {
        syscall_number === a;

        syscall c:, _11:, syscall_number;
    }
}

thread_cpu_time :: (apollo: *Apollo_Time) #no_context {
    syscall_number := 20;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        apollo === b;

        syscall c:, _11:, syscall_number, apollo;
    }
}

sleep_for_milliseconds :: (ms: int) #no_context {
    syscall_number := 21;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        ms === b;

        syscall c:, _11:, syscall_number, ms;
    }
}

get_boot_time :: (apollo: *Apollo_Time) #no_context {
    syscall_number := 22;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        apollo === b;

        syscall c:, _11:, syscall_number, apollo;
    }
}

get_tsc_frequency :: () -> u64 #no_context {
    syscall_number := 23;

    result: u64;

    #asm SYSCALL_SYSRET {
        mov rax: gpr === a, syscall_number;

        syscall c:, _11:, rax;
        mov result, rax;
    }

    return cast(u64) result;
}

create_semaphore :: (counter_max: int = 0, counter_start: int = 0) -> s64 #no_context {
    syscall_number := 30;

    result: u64;

    #asm SYSCALL_SYSRET {
        mov rax: gpr === a, syscall_number;
        counter_max === b;
        counter_start === d;

        syscall c:, _11:, rax, counter_max, counter_start;
        mov result, rax;
    }

    return cast(s64) result;
}

signal_semaphore :: (id: s64) #no_context {
    syscall_number := 31;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        id === b;

        syscall c:, _11:, syscall_number, id;
    }
}

wait_semaphore :: (id: s64) #no_context {
    syscall_number := 32;

    #asm SYSCALL_SYSRET {
        syscall_number === a;
        id === b;

        syscall c:, _11:, syscall_number, id;
    }
}

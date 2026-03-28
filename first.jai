
#import "Basic";
#import "Process";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";
#import "System";
#import "Metaprogram_Plugins";
#import "Program_Print";
#import "Sort";

#if OS == .WINDOWS {
    #import "Windows_Utf8";
    #import "Windows";
    #import "Windows_Subsystem_For_Linux";
    #import "VirtualBox";
}

#import "FAT16";
#import "File_System";
#import "GUID_Partition_Table";

#run main();

kernel_only      := false;
bootloader_only  := false;
userspace_only   := false;

main :: () {
    set_build_options_dc(.{ do_output = false });

    #if OS == .WINDOWS {

        log("You are on Windows, but this build program works only on Linux. Attempting to automatically relaunch in WSL.");

        JAI_ROOT_DIR    :: "/mnt/c/jai";
        WSL_DISTRO_NAME :: "Ubuntu";

        command_line := get_build_options().compile_time_command_line;
        context.print_style.default_format_array.begin_string = "";
        context.print_style.default_format_array.end_string = "";
        context.print_style.default_format_array.separator = " ";

        jai_command := tprint("%/bin/jai-linux first.jai - %", JAI_ROOT_DIR, command_line);

        stdin  := GetStdHandle(STD_INPUT_HANDLE);
        stdout := GetStdHandle(STD_OUTPUT_HANDLE);
        stderr := GetStdHandle(STD_ERROR_HANDLE);

        process: HANDLE;

        WslLaunch(utf8_to_wide(WSL_DISTRO_NAME), utf8_to_wide(jai_command), .TRUE, stdin, stdout, stderr, *process);
        WaitForSingleObject(process, INFINITE);

        init_plugins(.[], null, -1);

        return;
    }

    push_allocator(temp);

    nasm_result := run_command("nasm", "-v");
    if nasm_result.exit_code != 0 {
        log_error("\nThe NASM assembler is required by this build program to assemble the interrupt routines. Please install it and try again.");
        return;
    }

    args := get_build_options().compile_time_command_line;

    success, to_create, remaining_args := parse_plugin_arguments(args);
    if !success {
        log_error("Failed to parse plugin arguments.");
        return;
    }

    if !to_create {
        init_plugins(.[], null, -1); // Workaround for error messages when using plugins with multiple workspaces.
    }

    for remaining_args if it == {
        case "kernel";     kernel_only     = true;
        case "bootloader"; bootloader_only = true;
        case "userspace";  userspace_only  = true;
        case "format"; format_disk(); return;
        case; log_error("Command line argument not understood: %", it);
    }

    if to_create.count && !(bootloader_only ^ kernel_only) {
        log_error("Cannot use plugins with multiple targets. Specify either '- bootloader' or '- kernel' to use metaprogram plugins.");
        init_plugins(.[], null, -1);
        return;
    }

    make_directory_if_it_does_not_exist(".build/");

    if ((!userspace_only && !kernel_only) || bootloader_only) && !compile_bootloader(to_create) {
        log_error("Failed to compile the bootloader.");
        exit(1);
    }

    if ((!userspace_only && !bootloader_only) || kernel_only) && !compile_kernel(to_create) {
        log_error("Failed to compile the kernel.");
        exit(1);
    }

    if ((!kernel_only && !bootloader_only) || userspace_only) && !compile_userspace() {
        log_error("Failed to compile the userspace.");
        exit(1);
    }

    if !format_disk() {
        log_error("Failed to format the hard disk.");
        exit(1);
    }
}

compile_bootloader :: (to_create: [..] Plugin_To_Create) -> success: bool {
    log("Compiling UEFI bootloader");
    workspace := compiler_create_workspace("Bootloader");

    plugins: [..] *Metaprogram_Plugin;
    if to_create init_plugins(to_create, *plugins, workspace);

    {
        options := get_build_options(workspace);

        options.output_type = .OBJECT_FILE;
        options.output_executable_name = "bootloader";
        options.output_path = ".build/";
        options.text_output_flags = 0;
        options.disable_redzone = true;
        options.llvm_options.target_system_triple = "x86_64-unknown-windows";
        options.use_custom_link_command = true;
        options.entry_point_name = "";
        options.dead_code_elimination = .ALL;

        new_path: [..] string;
        array_add(*new_path, "bootloader/modules/");
        array_add(*new_path, ..options.import_path);
        options.import_path = new_path;

        set_build_options(options, workspace);
    }

    intercept_flags := Intercept_Flags.SKIP_ALL;
    for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);

    compiler_begin_intercept(workspace, intercept_flags);

    for plugins if it.add_source it.add_source(it);
    add_build_file("bootloader/bootloader.jai", workspace);

    success: bool;

    while true {
        message := compiler_wait_for_message();

        for plugins if it.message it.message(it, message);

        if message.kind == {
          case .COMPLETE;

            complete := cast(*Message_Complete) message;
            success = complete.error_code == .NONE;
            break;

          case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase == .READY_FOR_CUSTOM_LINK_COMMAND {
                link_command := tprint("%/bin/lld-linux -flavor link -subsystem:efi_application -driver -align:16 -base:0x200000 -entry:EfiMain .build/bootloader.o -out:.build/bootx64.efi", compiler_get_base_path());
                link_command_array := break_command_into_strings(link_command);

                result := run_command(.. link_command_array);
                if result.exit_code {
                    compiler_set_workspace_status(.FAILED, workspace);
                    log_error("Linking failed.");
                }

                compiler_custom_link_command_is_complete(workspace);
            }
        }
    }

    compiler_end_intercept(workspace);

    for plugins if it.finish   it.finish  (it);
    for plugins if it.shutdown it.shutdown(it);

    if success {
        command := break_command_into_strings("objdump -x .build/bootx64.efi -d -M intel --source");
        result, stdout := run_command(.. command, capture_and_return_output=true);
        write_entire_file(".build/bootloader.objdump.txt", stdout);
    }

    return success;
}

compile_kernel :: (to_create: [..] Plugin_To_Create) -> success: bool {

    {
        log("Assembling AP Startup Code");
        command := break_command_into_strings(
            "nasm kernel/ap_startup.asm -o .build/ap_startup.bin -f bin"
        );

        result := run_command(.. command);
        if result.exit_code != 0 {
            log_error("Failed to assemble AP startup code.");
            return false;
        }
    }

    log("Compiling kernel");
    workspace := compiler_create_workspace("Kernel");

    plugins: [..] *Metaprogram_Plugin;
    if to_create init_plugins(to_create, *plugins, workspace);

    {
        options := get_build_options(workspace);

        options.output_executable_name = "kernel";
        options.output_path = ".build";
        options.text_output_flags = 0;
        options.entry_point_name = "kernel_entry";
        options.disable_redzone = true;
        options.additional_linker_arguments = .["-ekernel_entry", "-Tlink.ld"];
        options.os_target = .LINUX;

        options.arithmetic_overflow_check = .FATAL;

        new_path: [..] string;
        array_add(*new_path, "kernel/modules/");
        array_add(*new_path, .. options.import_path);
        options.import_path = new_path;

        set_build_options(options, workspace);
    }

    intercept_flags := Intercept_Flags.SKIP_EXPRESSIONS_WITHOUT_NOTES;
    for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);

    compiler_begin_intercept(workspace, 0);

    for plugins if it.add_source it.add_source(it);

    add_build_file("kernel/kernel.jai", workspace);

    interrupt_assembly: String_Builder;
    append(*interrupt_assembly, read_entire_file("kernel/assembly.asm"));

    found_interrupts: [..] string;

    generated_syscall_dispatcher: bool;
    found_syscalls: [..] struct {
        number: int;
        using header: *Code_Procedure_Header;
    };

    found_syscall_api_declarations: [..] *Code_Struct;

    success: bool;

    while true {
        message := compiler_wait_for_message();

        if message.kind == .TYPECHECKED {
            typed := cast(*Message_Typechecked) message;

            for typed.structs {
                decl := it.expression;

                for decl.notes if it.text == "SyscallAPI" {
                    assert(!generated_syscall_dispatcher, "It appears there's a non-top-level syscall marker.");
                    array_add(*found_syscall_api_declarations, decl);
                    continue;
                }
            }

            for header: typed.procedure_headers {
                proc := header.expression;

                for proc.notes {
                    if begins_with(it.text, "InterruptRoutine") {
                        pop_error_code := "";
                        ip_offset := 15*8; // So we can find the return address, to create a stack frame for the stack tracer. 15 comes from the number of GPRs pushed to the stack after the CPU pushes the instruction pointer.
                        if begins_with(it.text, "InterruptRoutineWithErrorCode") {
                            pop_error_code = "    sub rsp, 8\n";
                            ip_offset += 8;
                        }

                        print_to_builder(*interrupt_assembly, INTERRUPT_STUB_FORMAT, proc.name, pop_error_code, ip_offset);
                        array_add(*found_interrupts, proc.name);
                    } else if begins_with(it.text, "Syscall") {
                        assert(!generated_syscall_dispatcher, "It appears there's a non-top-level syscall marker.");

                        number: int;
                        success := scan2(it.text, "Syscall(%)", *number);
                        assert(success, "Failed to scan syscall annotation: %", it.text);

                        array_add(*found_syscalls, { number, proc });
                    }
                }
            }
        }

        if message.kind == .PHASE {
            phase := cast(*Message_Phase) message;

            if phase.phase == .TYPECHECKED_ALL_WE_CAN {
                for found_interrupts {
                    add_build_string(tprint("isr__% :: () #foreign Assembly;", it), workspace);
                }

                array_reset(*found_interrupts);

                if !generated_syscall_dispatcher {
                    quick_sort(found_syscalls, (a, b) => a.number - b.number);

                    // The registers used to pass parameters in order to syscalls.
                    input_registers      :: string.["rbx", "rdx", "rsi", "rdi"];

                    // Jai's names for the same registers, omitting the size prefix/suffix.
                    input_registers_jai  :: string.["b",   "d",   "si",  "di"];

                    // Same thing for returns. Note r12 is used for the usermode stack by syscall_entry, r11 is used internally by SYSCALL to store RFLAGS.
                    // There's no reason we can't use the same registers for input and output, it just makes the syntax in the syscall wrappers noisier. 
                    output_registers     :: string.["r8", "r9", "r10", "r13"];
                    output_registers_jai :: string.[ "8",  "9",  "10",  "13"];

                    {
                        // Generate a case-statement for each syscall, for dispatching syscalls based on the value of RAX inside the kernel.
                        dispatcher_body: String_Builder;

                        for found_syscalls {

                            print(*dispatcher_body, "      case %;\n        ", it.number);

                            for it.returns {
                                // You can't have multiple return values and cast them.
                                if !it.name it.name = tprint("result%", it_index);

                                print_expression(*dispatcher_body, it);
                                append(*dispatcher_body, ";\n        ");
                            }

                            for ret: it.returns {
                                append(*dispatcher_body, ifx ret.name);

                                if it_index != it.returns.count-1 append(*dispatcher_body, ", ");
                                else                              append(*dispatcher_body, " = ");
                            }

                            append(*dispatcher_body, it.header.name);
                            append(*dispatcher_body, "(");
                            
                            for it.arguments print(*dispatcher_body, "xx data.%, ", input_registers[it_index]);

                            append(*dispatcher_body, ");\n");

                            for it.returns {
                                print(*dispatcher_body, "        data.% = xx %;\n", output_registers[it_index], it.name);
                            }

                            append(*dispatcher_body, "\n");
                        }

                        add_build_string(tprint(SYSCALL_DISPATCHER, builder_to_string(*dispatcher_body)), workspace);
                    }

                    call_wrappers: String_Builder;

                    // Write the names of the syscalls into an array, indexable by syscall number.
                    print(*call_wrappers, "\nsyscall_names :: string.[\n");
                    names_written: int;

                    for found_syscalls {
                        while names_written != it.number {
                            print(*call_wrappers, "    \"\",\n");
                            names_written += 1;
                        }

                        print(*call_wrappers, "    \"%\",\n", it.header.name);
                        names_written += 1;
                    }

                    print(*call_wrappers, "];\n\n");


                    for found_syscall_api_declarations {
                        print(*call_wrappers, "% :: ", it.defined_type.name);
                        print_expression(*call_wrappers, it);

                        append(*call_wrappers, "\n\n");
                    }


                    for found_syscalls {
                        print(*call_wrappers, "% :: (", it.header.name);

                        return_value_names := NewArray(it.returns.count, string); // Allow unnamed return values in the kernel syscall definitions, by generating names for them.
                        for it.returns {
                            return_value_names[it_index] = ifx it.name else tprint("result%", it_index);
                        }

                        // Find the longest return or argument name, to align the ===.
                        longest_name: int = "syscall_number".count;
                        for it.arguments          longest_name = max(longest_name, it.name.count);
                        for return_value_names    longest_name = max(longest_name, it.count);

                        for arg: it.arguments {
                            print_expression(*call_wrappers, arg);
                            if it_index != it.arguments.count - 1 append(*call_wrappers, ", ");
                        }

                        append(*call_wrappers, ")");

                        if it.returns append(*call_wrappers, " -> ");

                        for ret: it.returns {
                            print_expression(*call_wrappers, ret);
                            if it_index != it.returns.count - 1   append(*call_wrappers, ", ");
                        }

                        print(*call_wrappers, " #no_context {\n    syscall_number := %;\n\n", it.number);

                        for it.returns {
                            print(*call_wrappers, "    %: ", return_value_names[it_index]);
                            print_expression(*call_wrappers, it.type_inst);
                            print(*call_wrappers, ";\n");
                        }
                        if it.returns append(*call_wrappers, "\n");

                        append(*call_wrappers,    "    #asm SYSCALL_SYSRET {\n");
                        append(*call_wrappers,    "        syscall_number");
                        for 0..(longest_name - "syscall_number".count) append(*call_wrappers, " ");
                        append(*call_wrappers,    "=== a;\n");

                        for it.arguments {
                            print(*call_wrappers, "        %", it.name);
                            for 0..(longest_name - it.name.count) append(*call_wrappers, " ");
                            print(*call_wrappers, "=== %;\n", input_registers_jai[it_index]);
                        }

                        for return_value_names {
                            print(*call_wrappers, "        %", it);
                            for 0..(longest_name - it.count) append(*call_wrappers, " ");
                            print(*call_wrappers, "=== %;\n", output_registers_jai[it_index]);
                        }

                        append(*call_wrappers,    "\n        syscall c:, _11:, syscall_number");

                        for it.arguments {
                            print(*call_wrappers, ", %", it.name);
                        }

                        for return_value_names {
                            print(*call_wrappers, ", %", it);
                        }

                        append(*call_wrappers,    ";\n    }\n");

                        if  it.returns append(*call_wrappers, "\n    return ");
                        for return_value_names {
                            print(*call_wrappers, "%", it);
                            if it_index != return_value_names.count-1 append(*call_wrappers, ", ");
                        }
                        if it.returns append(*call_wrappers, ";\n");

                        append(*call_wrappers,    "}\n\n");
                    }

                    write_entire_file("userspace/modules/Syscall.jai", builder_to_string(*call_wrappers));

                    generated_syscall_dispatcher = true;
                }
            }

            if phase.phase == .ALL_TARGET_CODE_BUILT {
                log("Assembling interrupt routines");
                result_assembly_code := builder_to_string(*interrupt_assembly);

                {
                    // We save these on the stack during context switch, so assembly needs to know their offset within CPU-local data. Todo: Clean this up.
                    offset_ica := get_struct_field_offset_from_another_workspace("X64_Core", "interrupt_context_active", workspace);
                    offset_idq := get_struct_field_offset_from_another_workspace("X64_Core", "irq_disable_count", workspace);
                    offset_tss := get_struct_field_offset_from_another_workspace("X64_Core", "task_state_segment", workspace);
                    offset_rsp := get_struct_field_offset_from_another_workspace("Task_State_Segment", "rsp", workspace);

                    offset_string := tprint("\ninterrupt_context_active equ %\nirq_disable_count equ %\ntss_ring0_stack equ %\n\n", offset_ica, offset_idq, offset_tss + offset_rsp);
                    result_assembly_code = join(offset_string, result_assembly_code);
                }

                write_entire_file(".build/assembly.asm", result_assembly_code);
                command := break_command_into_strings("nasm -s .build/assembly.asm -o .build/assembly.so -f elf64 -g -F dwarf");

                result := run_command(.. command);
                if result.exit_code != 0 {
                    log_error("Failed to assemble interrupt routines.");
                    compiler_set_workspace_status(.FAILED, workspace);
                    success = false;
                }
            }
        }

        for plugins if it.message it.message(it, message);

        if message.kind == .COMPLETE {
            complete := cast(*Message_Complete) message;
            success = complete.error_code == .NONE;
            break;
        }
    }

    compiler_end_intercept(workspace);

    for plugins if it.finish   it.finish  (it);
    for plugins if it.shutdown it.shutdown(it);

    if success {
        command := break_command_into_strings("objdump -x .build/kernel -d -M intel --source");
        result, stdout := run_command(.. command, capture_and_return_output=true);
        write_entire_file(".build/kernel.objdump.txt", stdout);
    }

    return success;
}

compile_userspace :: () -> bool {
    log("Compiling userspace");

    make_directory_if_it_does_not_exist("userspace/artifacts");

    compile_one_program :: (file_name: string, name: string) -> bool {
        workspace := compiler_create_workspace("Userspace");

        {
            options := get_build_options(workspace);

            options.output_executable_name = name;
            options.output_path = "userspace/artifacts";
            options.text_output_flags = 0;
            options.entry_point_name = "main";
            options.os_target = .LINUX;
            options.additional_linker_arguments = .["-emain"];
            
            options.arithmetic_overflow_check = .FATAL;

            new_path: [..] string;
            array_add(*new_path, "userspace/modules/");
            array_add(*new_path, .. options.import_path);
            options.import_path = new_path;

            set_build_options(options, workspace);
        }

        compiler_begin_intercept(workspace);

        add_build_file(tprint("userspace/%", file_name), workspace);

        success: bool;

        while true {
            message := compiler_wait_for_message();

            if message.kind == .COMPLETE {
                complete := cast(*Message_Complete) message;
                success = complete.error_code == .NONE;
                break;
            }
        }

        compiler_end_intercept(workspace);

        if success {
            command := break_command_into_strings(tprint("objdump -x userspace/artifacts/% -d -M intel --source", name));
            result, stdout := run_command(.. command, capture_and_return_output=true);
            write_entire_file(tprint(".build/%.objdump.txt", name), stdout);
        }

        return success;
    }

    a := compile_one_program("test.jai", "Test");
    b := compile_one_program("priority_test.jai", "Priority Test");
    c := compile_one_program("counting.jai", "Counting");

    return a && b && c;
}

format_disk :: () -> bool {
    log("Formatting disk image");

    bootloader := read_entire_file(".build/bootx64.efi");
    kernel     := read_entire_file(".build/kernel");

    filesystem_size := 0xa0_0000; // 10 Meg
    disk_image_size := filesystem_size;
    disk_image_size += 0x20_0000; // Add two megabytes for alignment and partition table.
    disk_image_size += 0x1000_0000; // Add space for our custom file system.

    memory_buffer := NewArray(disk_image_size, u8);

    disk := format_gpt_disk_image(memory_buffer);

    {
        // Create the EFI boot partition.
        partition := create_partition(disk, PARTITION_TYPE_EFI_BASIC_DATA, "UEFI", 2048, filesystem_size / disk.sector_size);

        fat16     := fat16_create_file_system(partition, set_volume_label="THEOS BOOT");
        root      := fat16_get_root_directory(*fat16);

        fat16_create_directory(root, "EFI");
        fat16_create_directory(root, "EFI/BOOT");

        fat16_write_file(root, "EFI/BOOT/BOOTX64.EFI", bootloader);
        fat16_write_file(root, "kernel", kernel);
        fat16_write_file(root, "startup.nsh", "fs0:\nEFI\\BOOT\\BOOTX64.EFI");

        fat16_report_space(fat16);
        fat16_print_directory_tree(root);
        fat16_copy_fat_table(*fat16);
    }

    {
        // Create a partition containing our custom file system format.
        partition := create_partition(disk, PARTITION_TYPE_GUID, "File System", 4096 + filesystem_size / disk.sector_size, 0x1000_0000);
        assert((disk.all_file_data.data - partition.data) & 0x1f_ffff == 0);

        fs        := format_file_system(partition.data);
        subdir    := create_directory(fs, 1, "Software");

        userspace_programs := file_list("userspace/artifacts");

        for userspace_programs {
            file_content := read_entire_file(it);
            file_name    := basename(it);

            file := create_file(fs, subdir, file_name);
            write_file(fs, file, file_content);
        }
    }

    finalize_gpt_disk_image(disk);
    write_entire_file("disk_image.img", disk.all_file_data);

    array_free(memory_buffer);

    return true; // Todo: Check for errors.
}

get_struct_field_offset_from_another_workspace :: (struct_name: string, field_name: string, workspace: Workspace) -> int {
    tt := get_type_table(workspace);

    for tt {
        if it.type != .STRUCT continue;

        ti_struct := cast(*Type_Info_Struct) it;
        if ti_struct.name != struct_name continue;

        for ti_struct.members {
            if it.name != field_name continue;

            return it.offset_in_bytes;
        }
    }

    return -1;
}

INTERRUPT_STUB_FORMAT :: #string END

extern %1
global isr__%1

align 0x8
isr__%1:
    push_all

    ; For now, let's not have interrupt requests while other interrupt handlers are running.
    ; Todo: Very important to clarify this in the future.
    call irq_disable

    mov rdi, rsp

    ; Manually create a call stack frame that will tell the stack tracing code where the interrupt happened.
    mov rax, [rsp + %3] ; May or may not have to skip the error code to get the return address.
    push rax
    push rbp
    mov rbp, rsp

    inc qword [gs:interrupt_context_active]

    cld
    call %1

    dec qword [gs:interrupt_context_active]

    dec qword [gs:irq_disable_count]
    call maybe_reschedule

    ; Remove the manually created call stack frame from the stack.
    add rsp, 16

    pop_all
    %2
    iretq

END;

SYSCALL_DISPATCHER :: #string,\% END
do_auto_generated_syscall_dispatch :: (data: *Syscall_Stack_Frame) {
    if data.rax == {
      // Auto generated syscalls follow.
%
      case;
        log("Invalid syscall parameter. RAX = \%.\n", data.rax);
        bluescreen();
    }
}
END;



#if false do_virtualbox_things :: () {
    // WIP VirtualBox SDK attempt.

    load_virtualbox_api_pointers();
    print("Version: %\n", virtualbox_api.GetAPIVersion());

    client: *IVirtualBoxClient;
    virtualbox_api.ClientInitialize(null, *client);
    print("Client: %\n", client);



    virtualbox: *IVirtualBox;
    result := client.GetVirtualBox(client, *virtualbox);
    print("VirtualBox: % nsresult: %\n", virtualbox, result);

    ex: *IErrorInfo;
    virtualbox_api.GetException(*ex);

    ei: *IVirtualBoxErrorInfo;
    ex.QueryInterface(ex, *IID_IVirtualBoxErrorInfo, cast(**void) *ei);

    text: *u16;
    ei.GetText(ei, *text);

    while true {
        a: string;
        a.count = 1;
        if text {
            a.data = cast(*u8) text;
            text += 1;
            print("%", a);
        }
    }
    print("\n");

    session: *ISession;
    result = client.GetSession(client, *session);
    print("session: % nsresult: %\n", session, result);

    client.Release(client);
    virtualbox_api.ClientUninitialize();
    return;





    // machines: **IMachine;
    // count: u32 = 10;
    // virtualbox.GetMachines(virtualbox, *count, *machines);
    // print("Machine count = %\n", count);

    // session: *ISession;
    // client.GetSession(client, *session);
}

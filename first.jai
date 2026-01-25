
#import "Basic";
#import "Process";
#import "Compiler";
#import "File";
#import "String";
#import "System";
#import "Metaprogram_Plugins";

#if OS == .WINDOWS {
    #import "Windows_Utf8";
    #import "Windows";
    #import,file "modules/Windows_Subsystem_For_Linux.jai";
    #import,dir "modules/VirtualBox";
}

#import "FAT16";

#run,stallable main();

kernel_only := false;
bootloader_only := false;

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
        case "kernel";     kernel_only = true;
        case "bootloader"; bootloader_only = true;
        case; log_error("Command line argument not understood: %", it);
    }

    if to_create.count && !(bootloader_only ^ kernel_only) {
        log_error("Cannot use plugins with multiple targets. Specify either '- bootloader' or '- kernel' to use metaprogram plugins.");
        init_plugins(.[], null, -1);
        return;
    }

    make_directory_if_it_does_not_exist(".build/");

    if (!kernel_only || bootloader_only) && !compile_bootloader(to_create) {
        log_error("Failed to compile the bootloader.\n");
        exit(1);
    }

    if (!bootloader_only || kernel_only) && !compile_kernel(to_create) {
        log_error("Failed to compile the kernel.\n");
        exit(1);
    }

    if !format_disk() {
        log_error("Failed to format the hard disk.\n");
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
    if !kernel_only {
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

        new_path: [..] string;
        array_add(*new_path, "kernel/modules/");
        array_add(*new_path, .. options.import_path);
        options.import_path = new_path;

        set_build_options(options, workspace);
    }

    intercept_flags := Intercept_Flags.SKIP_ALL & ~.SKIP_PROCEDURE_HEADERS;
    for plugins if it.before_intercept it.before_intercept(it, *intercept_flags);

    compiler_begin_intercept(workspace, intercept_flags & ~.DO_PERFORMANCE_REPORT_RUNS);

    for plugins if it.add_source it.add_source(it);

    add_build_file("kernel/kernel.jai", workspace);

    interrupt_assembly: String_Builder;
    append(*interrupt_assembly, read_entire_file("kernel/assembly.asm"));
    found_interrupts: [..] string;

    success: bool;

    while true {
        message := compiler_wait_for_message();

        if message.kind == .TYPECHECKED {
            typed := cast(*Message_Typechecked) message;

            for header: typed.procedure_headers {
                proc := header.expression;

                for proc.notes {
                    if !begins_with(it.text, "InterruptRoutine") {
                        continue;
                    }

                    pop_error_code := "";
                    ip_offset := 15*8; // So we can find the return address, to create a stack frame for the stack tracer. 15 comes from the number of GPRs pushed to the stack after the CPU pushes the instruction pointer.
                    if begins_with(it.text, "InterruptRoutineWithErrorCode") {
                        pop_error_code = "    sub rsp, 8\n";
                        ip_offset += 8;
                    }

                    print_to_builder(*interrupt_assembly, INTERRUPT_STUB_FORMAT, proc.name, pop_error_code, ip_offset);
                    array_add(*found_interrupts, proc.name);
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
            }

            if phase.phase == .ALL_TARGET_CODE_BUILT {
                if !kernel_only {
                    log("Assembling interrupt routines");
                    result_assembly_code := builder_to_string(*interrupt_assembly,, temp);

                    {
                        // Use type info to get the offset of the interrupt-context-active flag in CPU local data, so we can access it from the interrupt service routines.
                        offset := get_struct_field_offset_from_another_workspace("X64_Core", "interrupt_context_active", workspace);
                        assert(offset != -1);

                        offset_constant := tprint("\ninterrupt_context_active equ %\n\n", offset);
                        result_assembly_code = join(offset_constant, result_assembly_code,, temp);
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

format_disk :: () -> success: bool {
    log("Formatting disk image\n\n");

    script :: string.[
        "dd if=/dev/zero of=fat.img bs=1M count=10",
        "mkfs.fat -F 16 fat.img",
        "mmd -i fat.img ::/EFI",
        "mmd -i fat.img ::/EFI/BOOT",
        "mcopy -i fat.img .build/bootx64.efi ::/EFI/BOOT",
        "mcopy -i fat.img .build/kernel ::",
        "mcopy -i fat.img startup.nsh ::",

        "mv fat.img disk_image.img",
    ];

    for script {
        if !it.count continue;

        command := break_command_into_strings(it);
        result := run_command(.. command);

        if result.exit_code != 0 {
            log_error("mtools disk formatting command failed: (\"%\").\nPlease make sure mtools is installed.", it);
            return false;
        }
    }

    disk_image := read_entire_file("disk_image.img");

    fat16_image := fat16_parse_disk_image(disk_image);

    return true;
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
    cli
    push_all

    mov rdi, rsp

    ; Manually create a call stack frame that will tell the stack tracing code where the interrupt happened.
    mov rax, [rsp + %3] ; May or may not have to skip the error code to get the return address.
    push rax
    push rbp
    mov rbp, rsp

    inc qword [gs:interrupt_context_active]

    call %1

    dec qword [gs:interrupt_context_active]

    add rsp, 16

    pop_all
    %2
    iretq

END;





#if false {
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

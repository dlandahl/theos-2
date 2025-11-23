
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

#run,stallable main();

kernel_only := false;
use_codex   := false;
compiler_performance_report := false;

main :: () {
    set_build_options_dc(.{ do_output = false });

    #if OS == .WINDOWS {
        log("You are on Windows, but this build program works only on Linux. Attempting to automatically relaunch in WSL");

        JAI_ROOT_DIR    :: "/mnt/c/jai";
        WSL_DISTRO_NAME :: "Ubuntu";

        command_line := get_build_options().compile_time_command_line;
        context.print_style.default_format_array.begin_string = "";
        context.print_style.default_format_array.end_string = "";

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
        log_error("\nThe NASM assembler is required by this build program to assemble the interrupt routines. Please install it and try again. The command might be \"sudo apt install nasm\"");
        return;
    }

    args := get_build_options().compile_time_command_line;

    for args if it == {
        case "kernel_only"; kernel_only = true;
        case "perf";        compiler_performance_report = true;
        case "codex";       use_codex = true;
        case; log_error("Command line argument not understood: %", it);
    }

    make_directory_if_it_does_not_exist(".build/");

    if !kernel_only && !compile_bootloader() {
        log_error("Failed to compile the bootloader.\n");
        exit(1);
    }

    if !compile_kernel() {
        log_error("Failed to compile the kernel.\n");
        exit(1);
    }

    if !format_disk() {
        log_error("Failed to format the hard disk.\n");
        exit(1);
    }
}

compile_bootloader :: () -> success: bool {
    log("Compiling UEFI bootloader");
    workspace := compiler_create_workspace("Bootloader");

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
    compiler_begin_intercept(workspace, intercept_flags);
    add_build_file("bootloader/bootloader.jai", workspace);

    success: bool;

    while true {
        message := compiler_wait_for_message();

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

    if success {
        command := break_command_into_strings("objdump -x .build/bootx64.efi -d -M intel --source");
        result, stdout := run_command(.. command, capture_and_return_output=true);
        write_entire_file(".build/bootloader.objdump.txt", stdout);
    }

    return success;
}

compile_kernel :: () -> success: bool {
    if !kernel_only {
        log("Assembling AP Startup Code");

        write_entire_file(".build/ap_startup.asm", AP_STARTUP_CODE);
        command := break_command_into_strings(
            "nasm .build/ap_startup.asm -o .build/ap_startup.bin -f bin"
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
    to_create: [..] Plugin_To_Create;

    if use_codex {
        array_add(*to_create, Plugin_To_Create.{ name = "Codex" });
    }

    if compiler_performance_report {
        array_add(*to_create, Plugin_To_Create.{ name = "Performance_Report" });
    }

    init_plugins(to_create, *plugins, workspace);


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
    append(*interrupt_assembly, ASSEMBLY_HEADER);
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
                    if it.text == "InterruptRoutineWithErrorCode" {
                        pop_error_code := "    sub rsp, 8\n";
                    }

                    print_to_builder(*interrupt_assembly, INTERRUPT_STUB_FORMAT, proc.name, pop_error_code);
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

                    write_entire_file(".build/assembly.asm", builder_to_string(*interrupt_assembly));
                    command := break_command_into_strings("nasm .build/assembly.asm -o .build/assembly.so -f elf64");

                    // Generate assembly wrappers for interrupts handlers using metaprogramming
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
        "dd if=/dev/zero of=fat.img bs=1k count=2880",
        "mformat -i fat.img -f 2880 ::",
        "mmd -i fat.img ::/EFI",
        "mmd -i fat.img ::/EFI/BOOT",
        "mcopy -i fat.img .build/bootx64.efi ::/EFI/BOOT",
        "mcopy -i fat.img .build/kernel ::",
        "mcopy -i fat.img startup.nsh ::",

        "mv fat.img disk_image.img",

        // "mv fat.img .build/iso",
        // "xorriso -as mkisofs -R -f -e fat.img -no-emul-boot -o disk_image.iso .build/iso",
    ];

    // make_directory_if_it_does_not_exist(".build/iso");

    for script {
        if !it.count continue;

        command := break_command_into_strings(it);
        result := run_command(.. command);

        if result.exit_code != 0 {
            log_error("mtools disk formatting command failed: (\"%\").\nPlease make sure mtools is installed.", it);
            return false;
        }
    }

    return true;
}



ASSEMBLY_HEADER :: #string END

section .text

[bits 64]

%macro push_all 0
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
%endmacro

%macro pop_all 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro


global context_switch

; *current_task is in rdi
; *new_task is in rsi

struc Task_Info
    .rsp:   resq 1
    .cr3:   resq 1
    .xsave: resq 1
endstruc

align 0x8
context_switch:
    ; Save RFLAGS and GPRs on the stack
    pushfq
    push_all

    ; Store FPU state in the old task's xsave_area
    fxsave64 [rdi + Task_Info.xsave]

    ; Store current stack on the old task
    mov [rdi + Task_Info.rsp], rsp

    ; Load FPU state from the new task's xsave_area
    fxrstor64 [rsi + Task_Info.xsave]

    ; Restore the stack pointer from the new task
    mov rsp, [rsi + Task_Info.rsp]

    ; Load the address space of the new task
    mov rdx, [rsi + Task_Info.cr3]
    mov cr3, rdx

    ; Restore RFLAGS and GPRs from the stack
    pop_all
    popfq

    ret



extern get_kernel_stack
extern syscall_handler
global syscall_entry

align 0x10
syscall_entry:
    pushfq
    push_all
    mov r12, rsp

    call get_kernel_stack
    mov rsp, rax

    mov rdi, r12
    call syscall_handler

    mov rsp, r12
    pop_all
    popfq

    o64 sysret


global enter_user_mode
align 0x10
enter_user_mode:
    mov rsp, rsi
    mov rcx, rdi
    mov r11, rdx

    o64 sysret


global get_rflags
align 0x10
get_rflags:
    pushfq
    pop rax
    ret


global init_segment_registers
align 0x10
init_segment_registers:
    push 0x8
    lea rax, [rel .reload_cs]
    push rax
    retfq
  .reload_cs:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    ret


global gs_relative_read
global gs_relative_write
global gs_relative_inc
global gs_relative_dec

align 0x10;
gs_relative_read:
    mov rax, [gs:rdi]
    ret

align 0x10;
gs_relative_write:
    mov [gs:rdi], rsi
    ret

align 0x10;
gs_relative_inc:
    inc qword [gs:rdi]
    ret

align 0x10;
gs_relative_dec:
    dec qword [gs:rdi]
    ret

END;


INTERRUPT_STUB_FORMAT :: #string END

extern %1
global isr__%1

align 0x8
isr__%1:
    cli
    push_all

    mov rdi, rsp
    call %1

    pop_all
    %2
    iretq

END;


AP_STARTUP_CODE :: #string END

[org 0x8000]
[bits 16]

%define code_segment     0x0008
%define data_segment     0x0010

ap_startup_asm:
start equ $
    cli
    cld

    lidt [idt]

    ; Enable paging and memory protection
    mov eax, 10100000b
    mov cr4, eax

    mov edx, [pml4]
    mov cr3, edx

    mov ecx, 0xc0000080
    rdmsr

    or eax, 0x00000100
    wrmsr

    mov ebx, cr0
    or ebx, 0x80000001
    mov cr0, ebx

    lgdt [gdt]

    jmp code_segment:ap_long_mode_start

align 8
gdt:
    dw .end - .start - 1
    dd .start

align 8
  .start:
    dq 0x0000000000000000
    dq 0x00209a0000000000
    dq 0x0000920000000000
  .end:

align 8
idt:
  .length       dw 0
  .base         dd 0

times 512-($-start) db 0
stack: dq 0
jai:   dq 0
pml4:  dq 0

serial:
    mov ax, 66
    mov dx, 0x3f8
    out dx, al
  .end:
    cli
    hlt
    jmp .end

[bits 64]

ap_long_mode_start:
    mov ax, data_segment
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov rsp, [stack]
    mov rbp, rsp

    call [jai]
    int3
    jmp $

times 4096-($-$$) db 0

END;




// Failed/WIP attempt to manually format the boot disk FAT

format_fat :: () {
    block_count := 128;
    BLOCK :: 512;

    disk := NewArray(512 * block_count, u8, initialized = true);

    mbr := cast(*Gpt_Master_Boot_Record) disk.data;
    mbr.* = .{};
    mbr.end_lba = xx (block_count - 1);

    entry := cast(*Gpt_Partition_Entry) (disk.data + BLOCK * 2);
    entry.partition_type = guid_string_to_binary(efi_system_partition_guid);
    entry.partition_guid = guid_string_to_binary("e3ed8a4a-1369-43e7-8d5d-24f41243213d");
    entry.start_lba = 3;
    entry.end_lba = xx (block_count - 34);
    entry.attributes = 3;
    entry.name = xx "E\0F\0I\0 \0S\0y\0s\0t\0e\0m\0";

    header := cast(*Gpt_Partition_Table_Header) (disk.data + BLOCK);
    header.signature           = xx "EFI PART";
    header.revision            = 1;
    header.header_size         = size_of(Gpt_Partition_Table_Header);
    header.this_lba            = 1;
    header.alternate_header    = xx (block_count - 1);
    header.data_start_lba      = 3;
    header.data_end_lba        = xx (block_count - 34);
    header.guid                = guid_string_to_binary("c1a26cfd-ada6-4d9e-be4a-4d5bd9d99d7f");
    header.partition_table_lba = 2;
    header.partition_count     = 1;
    header.partition_entry_size= 256;
    header.partition_table_crc = crc32(xx << cast(*[size_of(Gpt_Partition_Table_Header)] u8) entry);
    header.crc                 = crc32(xx << cast(*[0x5c] u8) header);

    // Repeat the partition table and header at the end of the disk
    memcpy(disk.data + disk.count - BLOCK, header, size_of(Gpt_Partition_Table_Header));
    memcpy(disk.data + disk.count - BLOCK * 33, entry, size_of(Gpt_Partition_Entry));

    write_entire_file("disk_image.img", disk.data, disk.count);
}

Fat16_Boot_Record :: struct {
    // "BIOS Parameter Block"
    jump_instruction: [3] u8;
    oem: [8] u8;
    bytes_per_sector: u16 #align 1;
    sectors_per_cluster: u8;
    reserved_sectors: u16;
    fat_count: u8;
}

efi_system_partition_guid :: "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";

#assert size_of(Gpt_Partition_Table_Header) == 0x5c;

Gpt_Master_Boot_Record :: struct {
    boot_indicator: u8  = 0x00;
    start_chs: [3] u8   = .[0x00, 0x02, 0x00];
    os_type: u8         = 0xee;
    end_chs: [3] u8     = .[0xff, 0xff, 0xff];
    start_lba: u32      = 1;
    end_lba: u32;
}

Gpt_Partition_Table_Header :: struct {
    signature:            [8] u8;
    revision:             u32;
    header_size:          u32;
    crc:                  u32;
    reserved:             u32;
    this_lba:             u64;
    alternate_header:     u64;
    data_start_lba:       u64;
    data_end_lba:         u64;
    guid:                 [16] u8;
    partition_table_lba:  u64;
    partition_count:      u32;
    partition_entry_size: u32;
    partition_table_crc:  u32;
} #no_padding

Gpt_Partition_Entry :: struct {
    partition_type: [16] u8;
    partition_guid: [16] u8;
    start_lba: u64;
    end_lba: u64;
    attributes: u64;
    name: [20] u8;
}

crc32 :: (s: string) -> u32 {
    sum : u32 = 0xffff_ffff;

    for byte: cast([] u8) s {
        tab_index := (sum ^ byte) & 0xff;

        sum = crc_table[tab_index] ^ (sum >> 8);
    }

    return ~sum;
}

crc_table : [256] u32 : .[
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
    0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
    0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
    0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172, 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
    0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
    0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
    0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
    0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
    0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
    0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0, 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
    0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
    0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
    0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
    0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
    0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
    0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236, 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
    0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
    0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
    0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
    0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
    0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
    0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94, 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
];

guid_string_to_binary :: ($$ in: string) -> [16] u8 {
    implementation :: (in: string) -> [16] u8 {
        fields := split(in, cast(u8) #char "-");
        result: [16] u8;

        cursor: int;
        for fields {
            // Field order is big endian, individual fields are little endian
            value := string_to_int(it, base=16, T=u64);
            memcpy(result.data + cursor, *value, it.count / 2);
            cursor += it.count / 2;
        }

        return result;
    }

    #if is_constant(in) {
        return #run implementation(in);
    } else {
        return implementation(in);
    }
}















#if false {
    // Failed/WIP VirtualBox SDK attempt
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

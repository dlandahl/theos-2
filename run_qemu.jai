
#import "Process";
#import "Compiler";
#import "File";
#import "Basic";

#run {
    set_build_options_dc(.{ do_output = false });

    make_directory_if_it_does_not_exist("logs");

    command := break_command_into_strings(#string QEMU_CMD
        qemu-system-x86_64
            -machine q35
            -cpu max,+apic,+fsgsbase,+tsc-deadline,+invtsc
            -bios OVMF.fd
            -drive format=raw,file=disk_image.img,id=nvm,if=none
            -device nvme,serial=cafebabe,drive=nvm
            -chardev stdio,id=char0,logfile=logs/qemu_serial.txt,signal=off
            -serial chardev:char0
            -chardev file,id=char1,path=logs/qemu_trace.bin
            -serial chardev:char1
            -m 256M
            -smp 4 
    QEMU_CMD);

#if OS == .LINUX {
    array_add(*command,
              "-accel", "kvm", "-display", "gtk,zoom-to-fit=on",
              // "-netdev", "user,id=net0", "-device", "e1000,netdev=net0"
             );
} else {
    array_add(*command, "-netdev", "user,id=n0,hostfwd=tcp:127.0.0.1:6001-:80", "-device", "e1000,netdev=n0");
    // array_add(*command, "-netdev", "tap,id=mynet0,ifname=tapwin", "-device", "e1000,netdev=mynet0");
}

    command_line := get_build_options().compile_time_command_line;
    array_add(*command, ..command_line);

    // --trace "*e1000*" 

    run_command(.. command);
}

#if false #run {
    // Handy page table calculator
    x := cast(u64) 256 * 1024 * 1024;

    mask: u64 = 0x1ff;

    #import "Basic";
    pml4_offset := (x >> 39) & mask;
    pdpt_offset := (x >> 30) & mask;
    pd\ _offset := (x >> 21) & mask;
    pt\ _offset := (x >> 12) & mask;
    page_offset := x & 0xfff;

    print("PML4: %, PDPT: %, PD: %, PT: %, offset in page: %",
          pml4_offset,
          pdpt_offset,
          pd\ _offset,
          pt\ _offset,
          page_offset);

    return;
}

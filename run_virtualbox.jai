
#import "Basic";
#import "Process";
#import "Compiler";
#import "File";

#run {
    set_build_options_dc(.{ do_output = false });

    file_delete("disk_image.vdi");

    path := get_absolute_path(".");

    commands := string.[
        tprint("VBoxManage modifyvm new_os --uartmode1 file \"%/logs/vbox_serial_log.txt\"", path),
        "VBoxManage modifyvm new_os --hpet on",
        "VBoxManage convertfromraw --format VDI disk_image.img disk_image.vdi",
        "VBoxManage storageattach new_os --storagectl AHCI --port 0 --medium none --device 0",
        "VBoxManage closemedium disk_image.vdi",
        "VBoxManage storageattach new_os --storagectl AHCI --port 0 --medium disk_image.vdi --device 0 --type hdd",
        "VBoxManage setextradata new_os GUI/DefaultCloseAction PowerOff",
        "VBoxManage startvm new_os -E VBOX_GUI_DBG_ENABLED=true",
    ];

    for commands {
        run_command(.. break_command_into_strings(it));
    }
}


Mouse_Packet :: struct {
    button: enum_flags {
        LEFT;
        RIGHT;
        MIDDLE;
    }

    x: s8;
    y: s8;
}

init_hid_device :: (socket: *USB_Controller.Socket) {
    log_category("HID");

    if socket.interface_descriptor.sub_class == 1 {
        if socket.interface_descriptor.protocol == 2 {
            log("Found a BOOT MOUSE.");
        } else if socket.interface_descriptor.protocol == 1 {
            log("Found a KEYBOARD.");
        }
    }
}

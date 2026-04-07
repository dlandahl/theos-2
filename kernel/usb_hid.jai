
Mouse_Packet :: struct {
    button: enum_flags u8 {
        LEFT;
        RIGHT;
        MIDDLE;
    }

    x: s8;
    y: s8;
    wheel: s8;
}

cursor: int;
buffer: [10] Mouse_Packet #align 64;

init_hid_device :: (controller: *USB_Controller, socket: *USB_Controller.Socket) {
    log_category("HID");

    if socket.interface_descriptor.sub_class != 1 return;
    if socket.interface_descriptor.protocol  != 2 return; // 1 = keyboard, 2 = mouse.

    for socket.endpoints {
        if !it.active continue;

        push_print_style().base = 16;
        log("Endpoint descriptor: %", it.descriptor.*);

        physical_base := get_physical_address(buffer.data);

        for* b: buffer {
            trb: Normal_TRB;
            trb.data_pointer = physical_base + cast(u64) it_index * size_of(Mouse_Packet);
            set(*trb.dword2, .transfer_length, size_of(Mouse_Packet));
            set(*trb.dword3, .interrupt_on_short_packet, 1);
            set(*trb.dword3, .interrupt_on_completion, 1);
            set(*trb.dword3, .trb_type, xx TRB_Type.NORMAL);

            queue_command(*it.transfer_ring, trb);
        }

        flush_commands(controller, socket.slot_id, cast(u32) it_index);
        cursor = 10;
    }
}

update_hid_device :: (controller: *USB_Controller, socket: *USB_Controller.Socket) {
    log_category("HID");

    if socket.interface_descriptor.sub_class != 1 return;
    if socket.interface_descriptor.protocol  != 2 return; // 1 = keyboard, 2 = mouse.

    log("%", buffer);

    for socket.endpoints {
        if !it.active continue;

        slot := cursor % buffer.count;

        trb: Normal_TRB;
        trb.data_pointer = get_physical_address(*buffer[slot]);
        set(*trb.dword2, .transfer_length, size_of(Mouse_Packet));
        set(*trb.dword3, .interrupt_on_short_packet, 1);
        set(*trb.dword3, .interrupt_on_completion, 1);
        set(*trb.dword3, .trb_type, xx TRB_Type.NORMAL);

        queue_command(*it.transfer_ring, trb);
        flush_commands(controller, socket.slot_id, cast(u32) it_index);

        cursor += 1;
    }
}

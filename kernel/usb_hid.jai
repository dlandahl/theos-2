
Mouse_Packet :: struct {
    button: enum_flags u8 {
        LEFT;
        RIGHT;
        MIDDLE;
    }

    x: s8;
    y: s8;
    scroll: s8;
}

buffer: [10] Mouse_Packet #align 64;

init_hid_device :: (controller: *USB_Controller, socket: *USB_Controller.Socket) {
    log_category("HID");

    if socket.interface_descriptor.sub_class != 1 return;
    if socket.interface_descriptor.protocol  != 2 return; // 1 = keyboard, 2 = mouse.

    for socket.endpoints {
        if !it.active   continue;
        if it_index < 2 continue;

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
    }
}

hid_transfer_completed :: (controller: *USB_Controller, socket: *USB_Controller.Socket, event: *Transfer_Event_TRB) {
    log_category("HID");

    if socket.interface_descriptor.sub_class != 1 return;
    if socket.interface_descriptor.protocol  != 2 return; // 1 = keyboard, 2 = mouse.

    endpoint_id := get(event.dword3, .endpoint_id);
    if endpoint_id < 2 return; // Todo: Transfer events for endpoint 1 are arriving here. But those are control events, so need to be handled differently.

    assert(endpoint_id > 1 && endpoint_id < 32);

    endpoint := *socket.endpoints[endpoint_id];
    assert(endpoint.active);

    completed_trb          := cast(*Normal_TRB)   (event.event_data           + DIRECT_MAPPING_BASE);
    completed_mouse_packet := cast(*Mouse_Packet) (completed_trb.data_pointer + DIRECT_MAPPING_BASE);
    log("Mouse input: %", completed_mouse_packet.*);

    trb: Normal_TRB;
    trb.data_pointer = completed_trb.data_pointer;
    set(*trb.dword2, .transfer_length, size_of(Mouse_Packet));
    set(*trb.dword3, .interrupt_on_short_packet, 1);
    set(*trb.dword3, .interrupt_on_completion, 1);
    set(*trb.dword3, .trb_type, xx TRB_Type.NORMAL);

    queue_command(*endpoint.transfer_ring, trb);
    flush_commands(controller, socket.slot_id, endpoint_id);
}

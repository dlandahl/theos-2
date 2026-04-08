
#load "usb_types.jai";
#load "usb_hid.jai";

USB_Controller :: struct {

    Socket :: struct {
        // Either of these may be null if the socket does not support that protocol.
        usb3_port: *XHCI_Port_Registers;
        usb2_port: *XHCI_Port_Registers;

        active_protocol: enum {
            NONE; USB3; USB2;
        }

        // Doesn't have a type, since the size of the context entries depends on capability
        // flags in the controller.
        device_context: *void;
        slot_id: int;

        device_descriptor: Device_Descriptor #align 64; // 64 byte aligned because we DMA the descriptor into here directly.
        string_description: string;

        // Todo: Support switching multiple interfaces.
        interface_descriptor: *Interface_Descriptor;

        endpoints: [32] Endpoint; // Indexed by device context index (DCI).
        #overlay (endpoints) control_endpoint: Endpoint;
    }

    Ring :: struct {
        buffer:   [] Normal_TRB;
        head:        int;
        cycle:       bool;
    }

    Endpoint :: struct {
        active: bool;

        descriptor: *Endpoint_Descriptor; // null for control endpoints.
        transfer_ring: Ring;
        max_transfer_size: int;
    }

    sockets: [] Socket;

    mmio_base: *void;

    using capability_registers:   *XHCI_Capability_Registers;
    using operational_registers:  *XHCI_Operational_Registers;
    using runtime_registers:      *XHCI_Runtime_Registers;

    port_registers:             [] XHCI_Port_Registers;

    doorbells:  [] u32;

    event_ring: [] Transfer_Event_TRB;
    event_ring_tail: int;
    event_ring_cycle: bool;

    command_ring: Ring;

    device_context_index: *Device_Context_Index;

    arena: Physical_Memory_Arena;
    semaphore: Semaphore;
}

#program_export
xhci_interrupt :: () #c_call {
    push_context,defer_pop;
    defer write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);

    xhci := *global.xhci;

    signal(*xhci.semaphore);
} @InterruptRoutine

init_usb_controller :: (device: *PCI_Device) {
    assert(device.combined_class_code == .UNIVERSAL_SERIAL_BUS);

    log_category("USB");

    ps := push_print_style();
    ps.base = 0x10;
    ps.use_newlines_if_long_form = true;

    if device.prog_if != 0x30 {
        // This is not XHCI, but rather UHCI, EHCI, something like that, which don't support USB 3.0.
        // Devices since about 2010 should have XHCI. XHCI supports USB 4.0 as well, but the book I have does
        // not cover it, so will need to research any changes in the newer XHCI specs. May be difficult to
        // test anyway.
        log_error("Unsupported controller type: %.", device.prog_if);
        return;
    }

    device.command |= .BUS_MASTER | .MEMORY_SPACE;
    device.command &= ~.INTERRUPT_DISABLE;

    xhci := *global.xhci;
    simple_create_thread(usb_thread);

    bar := read_base_address_register(device, 0);
    xhci.mmio_base = map_base_address_register(bar);
    
    parse_pci_capability_list(device);
    enabled := enable_msi_or_msi_x(device, isr__xhci_interrupt);    
    if enabled != .MSI_X {
        log_error("Controller does not support MSI-X.");
    }

    xhci.capability_registers    = cast(*XHCI_Capability_Registers)   xhci.mmio_base;
    xhci.operational_registers   = cast(*XHCI_Operational_Registers) (xhci.mmio_base + xhci.CAPLENGTH);
    xhci.runtime_registers       = cast(*XHCI_Runtime_Registers)     (xhci.mmio_base + xhci.RTSOFF);

    xhci.doorbells.data          = cast(*u32)                        (xhci.mmio_base + xhci.DBOFF);
    // Plus one for the command ring doorbell.
    xhci.doorbells.count         = get(xhci.HCSPARAMS1, .MaxSlots) + 1;

    xhci.port_registers.data     = *xhci.port_register_set_base;
    xhci.port_registers.count    = get(xhci.HCSPARAMS1, .MaxPorts);

    xecp := get(xhci.HCCPARAMS1, .xECP__extended_caps_pointer); 
    assert(xecp != 0);

    list := cast(*xHCI_Protocol_List_Entry) (xhci.mmio_base + xecp * 4);

    while true {
        if get(list.*, .id) == {
          case 1;
            // This is a firmware legacy support structure. Disable legacy support.
            list.dword0 |= (1 << 24);

            if Timeout(list.dword0 & (1 << 16) == 0) {
                log_error("Disable legacy mode timeout.");
                return;
            }
            
          case 2;
            // This is a supported protocol structure.
            assert(list.name == (.*) cast(*u32) "USB ".data);

            port_offset       := get(list.dword2, .compatible_port_offset) - 1; // One-based field, convert to zero-based.
            port_count        := get(list.dword2, .compatible_port_count);
            protocol_version  := get(list.*,      .revision_major);
            
            if port_count > xhci.sockets.count  array_resize(*xhci.sockets, port_count);

            // Find the register sets used by each socket for USB2 and USB3.

            for 0..port_count-1 {
                register_set := *xhci.port_registers[port_offset + it];
                socket       := *xhci.sockets[it];

                if protocol_version == {
                    case 2; socket.usb2_port = register_set;
                    case 3; socket.usb3_port = register_set;
                }
            }
        }

        next_offset := get(list.*, .next_offset);

        if !next_offset  break;
        list = cast(*void) list + next_offset * size_of(u32);
    }

    // Reset the controller.
    xhci.USBCMD &= ~.RS__run_stop;

    if Timeout(xhci.USBSTS & .HC_Halted) {
        log_error("Timeout, host controller not halted.");
        return;
    }
    
    xhci.USBCMD |= .HCRST__host_controller_reset;

    if Timeout(xhci.USBCMD & .HCRST__host_controller_reset == 0
            && xhci.USBSTS & .CNR__controller_not_ready    == 0) {
        log_error("Controller reset timeout.");
        return;
    }

    // Todo: In the book there's another sleep here, but he doesn't say how long or what it's for.

    page_size_flags := xhci.PAGESIZE & 0xffff;
    if page_size_flags & 1 == 0 {
        log_error("4K page size is not supported.");
        return;
    }

    xhci.arena.alignment = 64;

    {
        // Setup device context array.

        physical                  := arena_get(*xhci.arena, size_of(Device_Context_Index), 4096);
        xhci.device_context_index  = cast(*Device_Context_Index) (physical + DIRECT_MAPPING_BASE);

        // Allocate scratchpad buffers.
        number_of_scratchpad_buffers := get(xhci.HCSPARAMS2, .Max_Scratchpad_Bufs_Hi) << 5
                                      | get(xhci.HCSPARAMS2, .Max_Scratchpad_Bufs_Lo);

        log("Allocating % scratchpad buffers.", number_of_scratchpad_buffers);

        if number_of_scratchpad_buffers != 0 {
            size := align(64, number_of_scratchpad_buffers * size_of(u64));
            xhci.device_context_index.scratchpad_buffers = arena_get(*xhci.arena, size, 4096);

            write_pointer := cast(*u64) (xhci.device_context_index.scratchpad_buffers + DIRECT_MAPPING_BASE);

            for 0..number_of_scratchpad_buffers-1 {
                write_pointer[it] = arena_get(*xhci.arena, 4096, 4096);
            }
        }

        max_slots    :=     get    (xhci.HCSPARAMS1, .MaxSlots);
        context_size := ifx get_bit(xhci.HCCPARAMS1, .CSZ__context_size) then 2048 else 1024;

        for 0..max_slots-1 {
            // Todo: We don't really need to preallocate all these.
            xhci.device_context_index.device_contexts[it] = arena_get(*xhci.arena, context_size, 4096);
        }

        xhci.DCBAAP = physical;
    }


    // event_ring_max_segments := get(xhci.HCSPARAMS2, .ERST_Max);

    segment_table_physical := arena_get(*xhci.arena, align(64, size_of(Event_Ring_Segment_Table_Entry)), 0x1_0000);
    segment_table := cast(*Event_Ring_Segment_Table_Entry) (segment_table_physical + DIRECT_MAPPING_BASE);

    segment_table[0].size = 256;
    segment_table[0].base_address = arena_get(*xhci.arena, TRB_SIZE * 256, 4096);

    xhci.event_ring.data  = cast(*Transfer_Event_TRB) (segment_table[0].base_address + DIRECT_MAPPING_BASE);
    xhci.event_ring.count = 256;
    xhci.event_ring_cycle = true;

    primary_interrupter := *xhci.IR[0];
    primary_interrupter.* = {};
    primary_interrupter.IMAN__interrupter_management = .IP__interrupt_pending | .IE__interrupt_enable;
    primary_interrupter.ERSTSZ__event_ring_segment_table_size = 1;
    primary_interrupter.ERSTBA__event_ring_segment_table_base = segment_table_physical;
    primary_interrupter.ERDP__event_ring_dequeue_pointer = segment_table[0].base_address;


    command_ring_physical := arena_get(*xhci.arena, 4096, 4096);
    xhci.command_ring.buffer.data = cast(*Normal_TRB) (command_ring_physical + DIRECT_MAPPING_BASE);
    xhci.command_ring.buffer.count = 4096 / TRB_SIZE;
    xhci.command_ring.cycle = true;

    set_bit     (*xhci.CRCR, .RCS__ring_cycle_state);
    set_in_place(*xhci.CRCR, .command_ring_pointer, command_ring_physical);


    set(*xhci.CONFIG, .MaxSlotsEn, get(xhci.HCSPARAMS1, .MaxSlots));

    xhci.DNCTRL = 0x0002; // Notification type FUNCTION_WAKE. Todo: Magic number.

    xhci.USBSTS = .HSE__host_system_error
                | .EINT__event_interrupt
                | .PCD__port_change_detected
                | .HCE__host_controller_error;

    xhci.USBCMD = .RS__run_stop | .INTE__interrupter_enable | .HSEE__host_system_error_enable;

    if Timeout(xhci.USBSTS & .HC_Halted == 0) {
        log_error("Start schedule timeout, host xhci halted.");
        return;
    }

    // Reset ports.
    for *xhci.sockets {
        if      reset_port(xhci, it.usb3_port) it.active_protocol = .USB3;
        else if reset_port(xhci, it.usb2_port) it.active_protocol = .USB2;

        log("Resetting socket %. Active protocol: %", it_index+1, it.active_protocol);
    }


    sleep(5, .seconds);
    log_stats(xhci.arena);

    while true #asm { sti; hlt; }
}

reset_port :: (xhci: USB_Controller, port: *XHCI_Port_Registers) -> success: bool {
    if !port return false; // Allowed so the caller can treat USB2 and 3 ports on the same socket the same, even if one or the other is not present.

    if get(xhci.HCCPARAMS1, .PPC__port_power_control) {
        // Ports may need to be powered on manually.

        set_bit(*port.PORTSC, .PP__power);

        if Timeout(get_bit(port.PORTSC, .PP__power)) {
            log_error("Port power timeout.");
            return false;
        }
    }

    // Clear status change flags.
    // Todo: Bitfields don't have a good way to set multiple fields at once.
    set_bit(*port.PORTSC, .CSC__connect_status_change);
    set_bit(*port.PORTSC, .PEC__enabled_disabled_change);
    set_bit(*port.PORTSC, .WRC__warm_port_reset_change);
    set_bit(*port.PORTSC, .OCC__over_current_change);
    set_bit(*port.PORTSC, .PRC__reset_change);
    set_bit(*port.PORTSC, .PLC__link_change);
    set_bit(*port.PORTSC, .CEC__config_error_change);

    set_bit(*port.PORTSC, .PR__reset);

    if Timeout(get_bit(port.PORTSC, .PRC__reset_change), time_ms = 1) {
        // Not an error, there's just no device connected.
        return false;
    }

    return get_bit(port.PORTSC, .PED__enabled_disabled);
}

socket_from_port_id :: (xhci: *USB_Controller, port_id: int) -> *USB_Controller.Socket {
    // Todo: Remove this and just make an index table to go from port to socket.

    assert(port_id != 0);

    if port_id == 0                        return null;
    if port_id > xhci.port_registers.count return null;

    register_set := *xhci.port_registers[port_id - 1];

    for* xhci.sockets {
        if it.usb3_port != register_set && it.usb2_port != register_set continue;

        return it;
    }

    return null;
}

queue_command :: (ring: *USB_Controller.Ring, trb: Any) {
    assert(trb.type.runtime_size == TRB_SIZE);

    slot := *ring.buffer[ring.head];
    memcpy(slot, trb.value_pointer, TRB_SIZE);
    set_bit(*slot.dword3, .cycle_bit, ring.cycle);

    ring.head += 1;

    if ring.head == ring.buffer.count - 1 {
        link := cast(*Link_TRB) *ring.buffer[ring.head];
        link.* = {};

        link.ring_segment_pointer = get_physical_address(ring.buffer.data);
        set_bit(*link.dword3, .cycle_bit);
        set_bit(*link.dword3, .toggle_cycle);
        set    (*link.dword3, .trb_type, xx TRB_Type.LINK);

        ring.cycle = !ring.cycle;
        ring.head  = 0;
    }
}

flush_commands :: (xhci: *USB_Controller, slot_id := 0, endpoint: u32 = 0) {
    memory_fence();
    xhci.doorbells[slot_id] = endpoint;
}

usb_thread :: () {
    log_category("USB");

    xhci := *global.xhci;

    while true {
        wait_for(*xhci.semaphore);

        current_trb := *xhci.event_ring[xhci.event_ring_tail];

        if get_bit(current_trb.dword3, .cycle_bit) != xhci.event_ring_cycle {
            continue;
        }

        defer {
            // Maybe this doesn't actually need to be deferred.

            xhci.event_ring_tail += 1;

            if xhci.event_ring_tail == xhci.event_ring.count {
                xhci.event_ring_tail = 0;
                xhci.event_ring_cycle = !xhci.event_ring_cycle;
            }

            erdp_virtual := *xhci.event_ring[xhci.event_ring_tail];
            xhci.IR[0].ERDP__event_ring_dequeue_pointer = get_physical_address(erdp_virtual) | (1 << 3); // Todo: magic number.
            xhci.IR[0].IMAN__interrupter_management |= .IP__interrupt_pending;

            xhci.USBSTS = .HSE__host_system_error
                        | .EINT__event_interrupt
                        | .PCD__port_change_detected
                        | .HCE__host_controller_error;
        }

        type := cast(TRB_Type) get(current_trb.dword3, .trb_type);

        if type == {
          case .PORT_STATUS_CHANGE_EVENT;
            // Todo: Check if it was a detach rather than an attach.
            port := (current_trb.event_data >> 24) & 0xff;

            command: Normal_TRB;
            set(*command.dword3, .trb_type, cast(s64) TRB_Type.ENABLE_SLOT_COMMAND);
            set(*command.dword3, .interrupt_on_completion, 1);
            command.data_pointer = port; // Store the port ID in the user data value.

            queue_command(*xhci.command_ring, command);
            flush_commands(xhci);

          case .TRANSFER_EVENT;
            event    := cast(*Transfer_Event_TRB) current_trb;
            code     := cast(TRB_Completion_Code) get(event.dword2, .completion_code);
            slot_id  := get(event.dword3, .slot_id);

            socket: *USB_Controller.Socket;
            for* xhci.sockets if it.slot_id == slot_id { socket = it; break; }
            assert(!!socket);

            if code != .SUCCESS && code != .SHORT_PACKET {
                // Todo.
                log_error("Transfer failed with code %.", code);
                continue;
            }

            if socket.interface_descriptor.class == 3 {
                hid_transfer_completed(xhci, socket, event);
            }

          case .COMMAND_COMPLETION_EVENT;
            completed  := cast(*Command_Completion_TRB) current_trb;

            other_trb  := cast(*Normal_TRB) (current_trb.event_data + DIRECT_MAPPING_BASE);
            other_type := cast(TRB_Type) get(other_trb.dword3, .trb_type);

            code       := cast(TRB_Completion_Code) get(completed.dword2, .completion_code);

            if code != .SUCCESS {
                // Todo.
                log_error("Command of type % failed with code %.", other_type, code);
                continue;
            }

            if other_type == .CONFIGURE_ENDPOINT_COMMAND {
                slot_id := get(completed.dword3, .slot_id);
                log("Endpoint configured (Slot %).", slot_id);
                
                socket: *USB_Controller.Socket;
                for* xhci.sockets if it.slot_id == slot_id { socket = it; break; }
                assert(!!socket);

                if socket.interface_descriptor.class == 3 {
                    init_hid_device(xhci, socket);
                }
            }

            if other_type == .ADDRESS_DEVICE_COMMAND {
                // I don't know how to figure out the socket for this command other than looking for the slot ID.
                slot_id := get(completed.dword3, .slot_id);

                socket: *USB_Controller.Socket;
                for* xhci.sockets if it.slot_id == slot_id { socket = it; break; }
                assert(!!socket);

                slot_context: *Slot_Context = socket.device_context;
                slot_state := cast(Slot_State) get(slot_context.dword3, .slot_state);

                if slot_state == {
                  case .ADDRESSED;
                    using TRB_Type;

                    {
                        // Request device descriptor.
                        request: Device_Request_Packet;
                        set(*request.request_type, .direction, 1);
                        request.request      = .GET_DESCRIPTOR;
                        request.value        = .DEVICE;
                        request.length       = 18;

                        buffer := get_physical_address(*socket.device_descriptor);
                        execute_device_request(xhci, socket, *socket.control_endpoint, request, buffer);

                        log("Descriptor: %", socket.device_descriptor);
                    }

                    {
                        // Request product descriptor string.
                        string_buffer := arena_get(*xhci.arena, 64);

                        request: Device_Request_Packet;
                        set(*request.request_type, .direction, 1);
                        request.request      = .GET_DESCRIPTOR;
                        request.value        = .STRING;
                        request.value       |= xx socket.device_descriptor.product_index;
                        request.length       = 64;
                        request.index        = 0x0409; // American English. Todo: Hardcoded, magic number.

                        execute_device_request(xhci, socket, *socket.control_endpoint, request, string_buffer);

                        string_descriptor := cast(*String_Descriptor) (string_buffer + DIRECT_MAPPING_BASE);

                        socket.string_description.count = (string_descriptor.length - 2) / 2;
                        socket.string_description.data  = *string_descriptor.data;

                        // UTF16 to ASCII.
                        #no_abc {
                            for* socket.string_description it.* = socket.string_description[it_index * 2];
                        }

                        log("String: %", socket.string_description);
                    }

                    {
                        // Request configuration descriptor.
                        buffer := arena_get(*xhci.arena, 64);

                        request: Device_Request_Packet;
                        set(*request.request_type, .direction, 1);
                        request.request      = .GET_DESCRIPTOR;
                        request.value        = .CONFIGURATION;
                        request.length       = 64;

                        execute_device_request(xhci, socket, *socket.control_endpoint, request, buffer);

                        // Todo: Handle config descriptors larger than 64 bytes.
                        // Todo: This should probably be more robust against buggy USB devices.
                        // Todo: For now just use interface 0, even though for mouse it sometimes doesn't give you the scroll wheel.

                        header := cast(*Descriptor_Header) (buffer + DIRECT_MAPPING_BASE);

                        assert(header.type == .CONFIGURATION);

                        config   := cast(*Configuration_Descriptor) header;
                        end_byte := cast(*void) header + min(config.total_length, 64);

                        while header < end_byte {
                            if header.type == .INTERFACE {
                                if socket.interface_descriptor {
                                    break;
                                }

                                socket.interface_descriptor = cast(*Interface_Descriptor) header;
                            }

                            if header.type == .ENDPOINT {
                                assert(!!socket.interface_descriptor);

                                desc := cast(*Endpoint_Descriptor) header;

                                direction_bit   := get(desc.address, .direction);
                                endpoint_number := get(desc.address, .endpoint_number);

                                dci := 2 * endpoint_number + direction_bit;

                                assert(dci > 1 && dci < 32);

                                endpoint := *socket.endpoints[dci];
                                endpoint.descriptor = desc;
                                endpoint.max_transfer_size = desc.max_packet_size;
                                endpoint.active = true;
                            }

                            header = cast(*void) header + header.length;
                        }

                        log("Interface: %", socket.interface_descriptor.*);
                    }

                    {
                        // Now that we know the endpoints, we need to update the context array with new endpoint contexts.

                        input_context_physical := get_4k_page(); // Todo: Leak.
                        input_context_base     := cast(*void) input_context_physical + DIRECT_MAPPING_BASE;

                        context_size := ifx get_bit(xhci.HCCPARAMS1, .CSZ__context_size) then 64 else 32;

                        control_context: *Control_Context = input_context_base;
                        // Always copy the slot context, because the number of endpoints has changed.
                        control_context.add_flags |= 1;

                        // Copy the existing slot context.
                        slot_context: *Slot_Context = input_context_base + context_size;
                        memcpy(slot_context, socket.device_context, context_size);

                        highest_dci: int = 1;

                        for* socket.endpoints {
                            if !it.active       continue;
                            if  it_index < 2    continue; // Skip slot and control. Maybe 0 should be the control endpoint, but right now it's indexed by DCI, which is simpler and less confusing, but means that the first entry is meaningless.

                            direction_bit := get_bit(it.descriptor.address, .direction);
                            type          := cast(Endpoint_Type) it.descriptor.attributes & 0b11;
                            if direction_bit type += 4; // Translate from IN endpoint types to OUT.

                            dci := it_index;

                            control_context.add_flags |= cast(u32) (1 << dci);

                            endpoint_context := cast(*Endpoint_Context) (input_context_base + (dci + 1) * context_size); // +1 to skip the control context.

                            set(*endpoint_context.dword1, .endpoint_type,    xx type);
                            set(*endpoint_context.dword1, .error_count,      3);
                            set(*endpoint_context.dword1, .max_packet_size,  it.descriptor.max_packet_size);
                            endpoint_context.average_trb_length = 8;

                            transfer_ring_physical := arena_get(*xhci.arena, 4096, 4096);

                            it.transfer_ring.buffer.data  = cast(*Normal_TRB) (transfer_ring_physical + DIRECT_MAPPING_BASE);
                            it.transfer_ring.buffer.count = 4096 / TRB_SIZE;
                            it.transfer_ring.cycle        = true;

                            set_in_place(*endpoint_context.dword2_and_dword3, .tr_dequeue_pointer, transfer_ring_physical);
                            set_bit     (*endpoint_context.dword2_and_dword3, .dequeue_cycle_state);

                            highest_dci = max(dci, highest_dci);
                        }

                        set(*slot_context.dword0, .entry_count, highest_dci);

                        command: Normal_TRB;
                        set(*command.dword3, .trb_type, cast(s64) TRB_Type.CONFIGURE_ENDPOINT_COMMAND);
                        set(*command.dword3, .interrupt_on_completion, 1);
                        command.data_pointer = input_context_physical;
                        command.dword3 |= xx (socket.slot_id << 24);
                        
                        queue_command(*xhci.command_ring, command);
                        flush_commands(xhci);
                    }

                  case .DEFAULT;
                    log("Got here.");

                  case;
                    log("State error.");
                }
            }

            if other_type == .ENABLE_SLOT_COMMAND {
                // The controller has finished enabling a slot.

                port_id := cast(s64) other_trb.data_pointer;
                slot_id := get(completed.dword3, .slot_id);

                log("Enable slot completed, port: %, slot: %.", port_id, slot_id);

                socket := socket_from_port_id(xhci, port_id);
                if !socket {
                    log_error("Invalid port ID: %", port_id);
                    continue;
                }

                socket.slot_id = slot_id;
                socket.device_context = cast(*void) xhci.device_context_index.device_contexts[slot_id-1] + DIRECT_MAPPING_BASE;

                context_size := ifx get_bit(xhci.HCCPARAMS1, .CSZ__context_size) then 64 else 32;

                input_context_physical := get_4k_page(); // Todo: Leak.
                input_context_base     := cast(*void) input_context_physical + DIRECT_MAPPING_BASE;

                register_set := *xhci.port_registers[port_id - 1];

                control_context: *Control_Context = input_context_base;
                control_context.* = {};
                control_context.add_flags = 0b11;

                slot_context: *Slot_Context = input_context_base + context_size;
                slot_context.* = {};

                speed := get(register_set.PORTSC, .PSI__protocol_speed);
                log("Device has speed %.", cast(XHCI_Port_Speed) speed);

                set(*slot_context.dword0, .entry_count, 1);
                set(*slot_context.dword0, .speed, speed);
                slot_context.root_hub_port_number = cast(u8) (port_id);
                
                endpoint_context: *Endpoint_Context = input_context_base + 2 * context_size;
                endpoint_context.* = {};

                set(*endpoint_context.dword1, .endpoint_type,  xx Endpoint_Type.CONTROL);
                set(*endpoint_context.dword1, .error_count,    3);

                if cast(XHCI_Port_Speed) speed == {
                  case .UNDEFINED; #through;
                  case .LOW_SPEED; #through;
                  case .FULL_SPEED;
                    set(*endpoint_context.dword1, .max_packet_size, 8);

                  case .HIGH_SPEED;
                    set(*endpoint_context.dword1, .max_packet_size, 64);

                  case .SUPER_SPEED_GEN1_1X; #through;
                  case .SUPER_SPEED_GEN2_1X; #through;
                  case .SUPER_SPEED_GEN1_2X; #through;
                  case .SUPER_SPEED_GEN2_2X;
                    set(*endpoint_context.dword1, .max_packet_size, 512);

                  case;
                    assert(false); // Todo: Error.
                }

                // Allocate transfer ring and point endpoint dequeue pointer at it.
                // We need to make sure to reuse these transfer rings when different devices are added and
                // removed, because we can't free the memory, as it comes from the arena.
                transfer_ring_physical := arena_get(*xhci.arena, 4096, 4096);
                socket.control_endpoint.transfer_ring.buffer.data  = cast(*Normal_TRB) (transfer_ring_physical + DIRECT_MAPPING_BASE);
                socket.control_endpoint.transfer_ring.buffer.count = 4096 / TRB_SIZE;
                socket.control_endpoint.transfer_ring.cycle = true;
                socket.control_endpoint.max_transfer_size = get(endpoint_context.dword1, .max_packet_size);
                
                set_in_place(*endpoint_context.dword2_and_dword3, .tr_dequeue_pointer, transfer_ring_physical);
                set_bit     (*endpoint_context.dword2_and_dword3, .dequeue_cycle_state);
                endpoint_context.average_trb_length = 8;

                command: Normal_TRB;
                set(*command.dword3, .trb_type, cast(s64) TRB_Type.ADDRESS_DEVICE_COMMAND);
                set(*command.dword3, .interrupt_on_completion, 1);
                // set(*command.dword3, .block_event_interrupt, 1);
                command.data_pointer = input_context_physical;
                command.dword3 |= xx (slot_id << 24);

                queue_command(*xhci.command_ring, command);
                flush_commands(xhci);
            }
        }
    }
}

execute_device_request :: (xhci: *USB_Controller, socket: *USB_Controller.Socket, endpoint: *USB_Controller.Endpoint, packet: Device_Request_Packet, physical_memory_buffer: u64) {
    // Todo: Does not handle when the command ring is full.

    using TRB_Type;

    setup: Setup_Stage_TRB;
    setup.request = packet;
    set(*setup.dword2, .trb_transfer_length, 8);
    set(*setup.dword3, .immediate_data,      1);
    set(*setup.dword3, .trb_type,         xx SETUP_STAGE);
    set(*setup.dword3, .transfer_type,       3);
    
    queue_command(*endpoint.transfer_ring, setup);

    bytes_per_trb     := endpoint.max_transfer_size;
    bytes_transmitted := 0;

    trbs_needed := (packet.length + bytes_per_trb-1) / bytes_per_trb;
    assert(trbs_needed > 0);

    for 0..trbs_needed-1 {
        data: Data_Stage_TRB;
        data.data_pointer = physical_memory_buffer + cast(u64) bytes_transmitted;

        set(*data.dword2, .trb_transfer_length, min(packet.length - bytes_transmitted, bytes_per_trb));
        set(*data.dword3, .chain_bit,           1);
        set(*data.dword3, .trb_type,         xx DATA_STAGE);
        set(*data.dword3, .direction,           1);

        bytes_transmitted += bytes_per_trb;

        queue_command(*endpoint.transfer_ring, data);
    }

    status: Status_Stage_TRB;
    set(*status.dword3, .evaluate_next_trb,          1);
    set(*status.dword3, .interrupt_on_completion,    1);
    set(*status.dword3, .trb_type,                xx STATUS_STAGE);

    queue_command(*endpoint.transfer_ring, status);

    db_target := 1;

    if endpoint.descriptor {
        // Maybe we should store the DCI when we enumerate the endpoint, rather than parsing it out each transfer.
        direction_bit := get_bit(endpoint.descriptor.address, .direction);
        dci := 2 * get(endpoint.descriptor.address, .endpoint_number) + cast(int) direction_bit;

        db_target = dci;
    }

    flush_commands(xhci, socket.slot_id, cast(u32) db_target);
}

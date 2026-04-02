
#load "usb_structs.jai";

USB_Controller :: struct {
    Socket :: struct {
        // Either of these may be null if the socket does not support that protocol.
        usb3_port: *XHCI_Port_Register_Set;
        usb2_port: *XHCI_Port_Register_Set;

        active_protocol: enum {
            NONE; USB3; USB2;
        }

        device_context_index: int; // Index into the array in the Device_Context_Index struct.
        device_context: *void; // Doesn't have a type, since the size of the context entries depends on capability flags in the controller.
    }

    sockets: [] Socket;

    mmio_base: *void;

    using capability_registers:   *XHCI_Capability_Registers;
    using operational_registers:  *XHCI_Operational_Registers;
    using runtime_registers:      *XHCI_Runtime_Registers;

    port_registers:             [] XHCI_Port_Register_Set;

    doorbells:  [] u32;

    event_ring: [] Transfer_Event_TRB;
    event_ring_tail: int;
    event_ring_cycle: bool;

    command_ring: [] Normal_TRB;
    command_ring_head: int;
    command_ring_cycle: bool;

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
        return;
    }

    xhci.capability_registers    = cast(*XHCI_Capability_Registers)   xhci.mmio_base;
    xhci.operational_registers   = cast(*XHCI_Operational_Registers) (xhci.mmio_base + xhci.CAPLENGTH);
    xhci.runtime_registers       = cast(*XHCI_Runtime_Registers)     (xhci.mmio_base + xhci.RTSOFF);

    xhci.doorbells.data          = cast(*u32)                        (xhci.mmio_base + xhci.DBOFF);
    xhci.doorbells.count         = get(xhci.HCSPARAMS1, .MaxSlots) + 1; // Plus one for the command ring doorbell.

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
            register_set_base := cast(*XHCI_Port_Register_Set) *xhci.port_register_set_base;

            for 0..port_count-1 {
                register_set := register_set_base + port_offset + it;
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

        physical             := arena_get(*xhci.arena, size_of(Device_Context_Index), 4096);
        device_context_index := cast(*Device_Context_Index) (physical + DIRECT_MAPPING_BASE);

        // Allocate scratchpad buffers.
        number_of_scratchpad_buffers := get(xhci.HCSPARAMS2, .Max_Scratchpad_Bufs_Hi) << 5
                                      | get(xhci.HCSPARAMS2, .Max_Scratchpad_Bufs_Lo);

        log("Allocating % scratchpad buffers.", number_of_scratchpad_buffers);

        if number_of_scratchpad_buffers != 0 {
            size := align(64, number_of_scratchpad_buffers * size_of(u64));
            device_context_index.scratchpad_buffers = arena_get(*xhci.arena, size, 4096);

            write_pointer := cast(*u64) (device_context_index.scratchpad_buffers + DIRECT_MAPPING_BASE);

            for 0..number_of_scratchpad_buffers-1 {
                write_pointer[it] = arena_get(*xhci.arena, 4096, 4096);
            }
        }

        max_slots    :=     get    (xhci.HCSPARAMS1, .MaxSlots);
        context_size := ifx get_bit(xhci.HCCPARAMS1, .CSZ__context_size) then 2048 else 1024;

        for 0..max_slots-1 {
            device_context_index.device_contexts[it] = arena_get(*xhci.arena, context_size, 4096);
        }

        xhci.DCBAAP = physical;
    }


    // event_ring_max_segments := get(xhci.HCSPARAMS2, .ERST_Max);

    segment_table_physical := arena_get(*xhci.arena, align(64, size_of(Event_Ring_Segment_Table_Entry)), 0x1_0000);
    segment_table := cast(*Event_Ring_Segment_Table_Entry) (segment_table_physical + DIRECT_MAPPING_BASE);

    segment_table[0].size = 4096;
    segment_table[0].base_address = arena_get(*xhci.arena, size_of(Transfer_Event_TRB) * 4096, 0x1_0000);

    xhci.event_ring.data  = cast(*Transfer_Event_TRB) (segment_table[0].base_address + DIRECT_MAPPING_BASE);
    xhci.event_ring.count = 4096;
    xhci.event_ring_cycle = true;

    primary_interrupter := *xhci.IR[0];
    primary_interrupter.* = {};
    primary_interrupter.IMAN__interrupter_management = .IP__interrupt_pending | .IE__interrupt_enable;
    primary_interrupter.ERSTSZ__event_ring_segment_table_size = 1;
    primary_interrupter.ERSTBA__event_ring_segment_table_base = segment_table_physical;
    primary_interrupter.ERDP__event_ring_dequeue_pointer = segment_table[0].base_address;


    command_ring_physical := arena_get(*xhci.arena, 0x1_0000, 0x1_0000);
    xhci.command_ring.data  = cast(*Normal_TRB) (command_ring_physical + DIRECT_MAPPING_BASE);
    xhci.command_ring.count = 0x1_0000 / size_of(Normal_TRB);

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


    log_stats(xhci.arena);

    while true #asm { sti; hlt; }
}

reset_port :: (xhci: USB_Controller, port: *XHCI_Port_Register_Set) -> success: bool {
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

usb_thread :: () {
    xhci := *global.xhci;

    while true {
        wait_for(*xhci.semaphore);

        current_trb := *xhci.event_ring[xhci.event_ring_tail];

        if get_bit(current_trb.dword3, .cycle_bit) != xhci.event_ring_cycle {
            continue;
        }

        type := cast(TRB_Type) get(current_trb.dword3, .trb_type);
        log("Got TRB of type %.", type);

        if type == {
          case .PORT_STATUS_CHANGE_EVENT;
            port := (current_trb.event_data >> 24) & 0xff;
            log("Status change on port %", port);

            head := xhci.command_ring_head;
            xhci.command_ring[head] = {};
            set(*xhci.command_ring[head].dword3, .trb_type, cast(s64) TRB_Type.ENABLE_SLOT_COMMAND);
            set(*xhci.command_ring[head].dword3, .interrupt_on_completion, 1);
            set(*xhci.command_ring[head].dword3, .cycle_bit, 1);
            xhci.command_ring[head].data_pointer = (current_trb.event_data >> 24) & 0xff; // Store the port in the user data value.
            xhci.command_ring_head += 1;

            memory_fence();
            xhci.doorbells[0] = 0;

          case .COMMAND_COMPLETION_EVENT;
            other_trb  := cast(*Normal_TRB) (current_trb.event_data + DIRECT_MAPPING_BASE);
            other_type := cast(TRB_Type) get(other_trb.dword3, .trb_type);

            if other_type == .ENABLE_SLOT_COMMAND {
                // The controller has finished enabling a slot.
                port    := cast(s64) other_trb.data_pointer;
                slot_id := get(current_trb.dword3, .slot_id);

                log("Enable slot completed, port: %, slot: %", port, slot_id);

                if port >= xhci.port_registers.count {
                    // Todo: Error.
                }

                // Find the USB socket that has been connected-to.
                // register_set := *xhci.port_registers[port];
                for xhci.sockets {

                }
            }
        }

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
}

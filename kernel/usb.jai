
USB_Prog_IF :: enum {
    UHCI :: 0x00;
    OHCI :: 0x10;
    EHCI :: 0x20;
    XHCI :: 0x30;
}

USB_Controller :: struct {
    Socket :: struct {
        // Either of these may be null if the socket does not support that protocol.
        usb3_port: *XHCI_Port_Register_Set;
        usb2_port: *XHCI_Port_Register_Set;

        usb3_active: bool;
        usb2_active: bool;
    }

    sockets: [] Socket;

    mmio: *void;

    caps: *XHCI_Capability_Registers;
    ops:  *XHCI_Operational_Registers;

    arena: Physical_Memory_Arena;
}

init_usb_controller :: (device: *PCI_Device) {
    log_category("USB");

    ps := push_print_style();
    ps.base = 0x10;
    ps.use_newlines_if_long_form = true;

    log("Found device with vendor %, interface %.", device.vendor_id, device.prog_if);

    controller_type := cast(USB_Prog_IF) device.prog_if;

    if controller_type != .XHCI {
        log_error("Unsupported controller type: %.", controller_type);
        return;
    }

    using controller: USB_Controller;

    bar  := read_base_address_register(device, 0);
    mmio  = map_base_address_register(bar);

    parse_pci_capability_list(device);
    enabled := enable_msi_or_msi_x(device, null);
    log("Enabled interrupts: %", enabled);

    caps = cast(*XHCI_Capability_Registers)   mmio;
    ops  = cast(*XHCI_Operational_Registers) (mmio + caps.CAPLENGTH);

    xecp := get(caps.HCCPARAMS1, .xECP__extended_caps_pointer); 
    assert(xecp != 0);

    list := cast(*xHCI_Protocol_List_Entry) (mmio + xecp * 4);

    protocols: [..] struct {
        port_offset:      int;
        port_count:       int;
        protocol_version: int;
    };
    protocols.allocator = temp;

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

            offset := get(list.dword2, .compatible_port_offset) - 1; // One-based field, convert to zero-based.
            count  := get(list.dword2, .compatible_port_count);
            major  := get(list.*,      .revision_major);

            array_add(*protocols, {offset, count, major});
        }

        next_offset := get(list.*, .next_offset);

        if !next_offset  break;
        list = cast(*void) list + next_offset * 4;
    }

    {
        // Find the highest port number to find the number of physical sockets.
        number_of_sockets: int;

        for protocols {
            number_of_sockets = max(number_of_sockets, it.port_count);
        }

        sockets = NewArray(number_of_sockets, USB_Controller.Socket);

        // Find the register sets used by each socket for USB2 and USB3.
        register_set_base := cast(*XHCI_Port_Register_Set) *ops.port_register_set_base;

        for protocols {
            for port: 0..it.port_count-1 {
                register_set := register_set_base + it.port_offset + port;
                socket       := *sockets[port];

                if it.protocol_version == {
                    case 2; socket.usb2_port = register_set;
                    case 3; socket.usb3_port = register_set;
                }
            }
        }

        // All USB3 ports should be USB2 compatible.
        for sockets {
            log("%", it);
            if it.usb3_port assert(!!it.usb2_port);
        }
    }

    // Reset the controller.
    ops.USBCMD &= ~.RS__run_stop;

    if Timeout(ops.USBSTS & .HC_Halted) {
        log_error("Timeout, host controller not halted.");
        return;
    }

    ops.USBCMD |= .HCRST__host_controller_reset;

    if Timeout(ops.USBCMD & .HCRST__host_controller_reset == 0
            && ops.USBSTS & .CNR__controller_not_ready    == 0) {
        log_error("Controller reset timeout.");
        return;
    }

    // Todo: In the book there's another sleep here, but he doesn't say how long or what it's for.

    page_size_flags := controller.ops.PAGE_SIZE & 0xffff;
    if page_size_flags & 1 == 0 {
        log_error("4K page size is not supported.");
        return;
    }

    controller.arena.alignment = 64;

    device_context_index := arena_get(*controller.arena, size_of(Device_Context_Index), 4096);

    // Allocate scratchpad buffers.
    number_of_scratchpad_buffers := get(caps.HCSPARAMS2, .Max_Scratchpad_Bufs_Hi) << 5
                                  | get(caps.HCSPARAMS2, .Max_Scratchpad_Bufs_Lo);

    if number_of_scratchpad_buffers != 0 {
        size := align(64, number_of_scratchpad_buffers * size_of(u64));
        device_context_index.scratchpad_buffers = arena_get(*controller.arena, size, 4096);

        write_pointer := cast(*u64) (device_context_index.scratchpad_buffers + DIRECT_MAPPING_BASE);

        for 0..number_of_scratchpad_buffers-1 {
            write_pointer[it] = arena_get(*controller.arena, 4096, 4096);
        }
    }

    max_slots    :=     get    (caps.HCSPARAMS1, .MaxSlots);
    context_size := ifx get_bit(caps.HCCPARAMS1, .CSZ__context_size) then 2048 else 1024;

    for 0..max_slots-1 {
        device_context.device_contexts[it] = arena_get(*controller.arena, context_size, 4096);
    }

    command_ring   := get_4k_page();

    ops.DCBAAP = device_context;

    crcr := ops.CRCR;
    set_bit     (*crcr, .RCS__ring_cycle_state);
    set_in_place(*crcr, .command_ring_pointer, command_ring);
    ops.CRCR = crcr;

    set(*ops.CONFIG, .MaxSlotsEn, max_slots);

    ops.DNCTRL = 0x0002; // Notification type FUNCTION_WAKE. Todo: Magic number.

    ops.USBCMD = .RS__run_stop | .INTE__interrupter_enable | .HSEE__host_system_error_enable;

    if Timeout(ops.USBSTS & .HC_Halted == 0) {
        log_error("Start schedule timeout, host controller halted.");
        return;
    }

    // Reset ports.
    for sockets {
        it.usb3_active = reset_port(controller, it.usb3_port);
        it.usb2_active = reset_port(controller, it.usb2_port);
    }
}

Device_Context_Index :: struct {
    _: void #align 64;

    scratchpad_buffers:       u64;
    device_contexts:    [255] u64;
}

Slot_Context :: struct {
    // First entry in a device context data block, pointed-to by an entry in the device context index array.
    dword0: enum u32 {
        route_string    :: 20;
        speed           :: 4;
        _               :: 1;
        multi_tt        :: 1;
        hub             :: 1;
        entry_count     :: 5;
    }

    max_exit_latency:     u16;
    root_hub_port_number: u8;
    number_of_ports:      u8;

    dword2: enum u32 {
        tt_hub_slot_id     :: 8;
        tt_port_number     :: 8;
        tt_think_time      :: 2;
        _                  :: 4;
        interrupter_target :: 10;
    }
}

reset_port :: (controller: USB_Controller, port: *XHCI_Port_Register_Set) -> success: bool {
    if !port return false; // Allowed so the caller can treat USB2 and 3 ports on the same socket the same, even if one or the other is not present.

    if get(controller.caps.HCCPARAMS1, .PPC__port_power_control) {
        // Ports may need to be powered on manually.

        set_bit(*port.PORTSC, .PP__power);

        if Timeout(get_bit(port.PORTSC, .PP__power)) {
            log_error("Port power timeout.");
            return false;
        }
    }

    // if get_bit(port.PORTSC, .CCS__current_connect_status) {
    //     return true; // Ports that are already
    // }

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

    if Timeout(get_bit(port.PORTSC, .PRC__reset_change), time_ms = 10) {
        // Not an error, there's just no device connected.
        return false;
    }

    return get_bit(port.PORTSC, .PED__enabled_disabled);
}

XHCI_Operational_Registers :: struct {
    start: void;

    USBCMD: enum_flags u32 {
        RS__run_stop;
        HCRST__host_controller_reset;
        INTE__interrupter_enable;
        HSEE__host_system_error_enable;
        _;
        _;
        _;
        LHCRST__light_host_controller_reset;
    }

    USBSTS: enum_flags u32 {
        HC_Halted;
        _;
        HSE__host_system_error;
        PCD__port_change_detected;
        _;
        _;
        _;
        SSS__save_state_status;
        RSS__save_restore_status;
        SRE__save_restore_error;
        CNR__controller_not_ready;
        HCE__host_controller_error;
       
    }

    PAGESIZE:      u32;
    _:         [2] u32;
    DNCTRL:        u32;
    CRCR:     enum u64 {
        RCS__ring_cycle_state :: 1;
        CS__command_stop      :: 1;
        CA__command_abort     :: 1;
        CRR__command_ring_running :: 1;
        _                     :: 2;
        command_ring_pointer  :: 58;
    }
    _:         [4] u32;
    DCBAAP:        u64;
    CONFIG:   enum u32 {
        MaxSlotsEn   :: 8;
        U3E          :: 1;
        CIE          :: 1;
        _            :: 22;
    }

    // Create enough room for overlay.
    _: [0x2000] u8;

    #overlay(start) using _: struct {
        _: [0x400] u8;

        port_register_set_base: void; // Array of [HCSPARAMS1.MaxPorts] XHCI_Port_Register_Set
    }
}

XHCI_Port_Register_Set :: struct {
    PORTSC: enum u32 {
        CCS__current_connect_status     :: 1;
        PED__enabled_disabled           :: 1;
        _                               :: 1;
        OCA__over_current_active        :: 1;
        PR\__reset                      :: 1;
        PLS__link_state                 :: 4;
        PP\__power                      :: 1;
        PSI__protocol_speed             :: 4;
        PIC__indicator_control          :: 2;
        LWS__link_state_write_strobe    :: 1;
        CSC__connect_status_change      :: 1;
        PEC__enabled_disabled_change    :: 1;
        WRC__warm_port_reset_change     :: 1;
        OCC__over_current_change        :: 1;
        PRC__reset_change               :: 1;
        PLC__link_change                :: 1;
        CEC__config_error_change        :: 1;
        CAS__cold_attach_status         :: 1;
        WCE__wake_on_connect_enable     :: 1;
        WDE__wake_on_disconnect_enable  :: 1;
        WOE__wake_on_overcurrent_enable :: 1;
        _                               :: 2;
        DR\__device_removable           :: 1;
        WPR__warm_port_reset            :: 1;
    }
    PORTPMSC:  u32;
    PORTLI:    u32;
    PORTHLPMC: u32;
}

XHCI_Capability_Registers :: struct {
    CAPLENGTH:       u8;
    _:               u8;
    HCIVERSION:      u16;

    HCSPARAMS1:      enum u32 {
        MaxSlots     :: 8;
        MaxIntrs     :: 11;
        _            :: 5;
        MaxPorts     :: 8;
    }

    HCSPARAMS2:      enum u32 {
        IST                    :: 4;
        ERST_Max               :: 4;
        _                      :: 13;
        Max_Scratchpad_Bufs_Hi :: 5;
        SPR                    :: 1;
        Max_Scratchpad_Bufs_Lo :: 5;
    }

    HCSPARAMS3:      enum u32 {
        U1_Device_Exit_Latency   :: 8;
        _                        :: 8;
        U2_Device_Exit_Latency   :: 16;
    }

    HCCPARAMS1:      enum u32 {
        AC64          :: 1;
        BNC           :: 1;
        CSZ__context_size       :: 1;
        PPC__port_power_control :: 1;
        PIND          :: 1;
        LHRC          :: 1;
        LTC           :: 1;
        NSS           :: 1;
        PAE           :: 1;
        SPC           :: 1;
        SEC           :: 1;
        CFC           :: 1;
        MaxPSASize    :: 4;
        xECP__extended_caps_pointer :: 16;
    }

    DBOFF:           u32;
    RTSOFF:          u32;

    HCCPARAMS2:      enum_flags u32 {
        U3C           :: 0x1;
        CMC           :: 0x2;
        FSC           :: 0x4;
        CTC           :: 0x8;
        LEC           :: 0x10;
        CIC           :: 0x20;
        ETC           :: 0x40;
        ETC_TSC       :: 0x80;
        GSC           :: 0x100;
        VTC           :: 0x200;
    }

    VTIOSOFF:        u32;
}

#assert size_of(XHCI_Capability_Registers) == 0x24;

xHCI_Protocol_List_Entry :: struct {
    #as dword0: enum u32 { // My physical hardware supports misaligned accesses here, but QEMU doesn't... WTH.
        id               :: 8;
        next_offset      :: 8;
        revision_minor   :: 8;
        revision_major   :: 8;
    }

    name: u32;

    dword2: enum u32 { // Todo: Bitfield module doesn't support multiple #as members.
        compatible_port_offset  :: 8;
        compatible_port_count   :: 8;
        protocol_defined        :: 12;
        PSIC__protocol_speed_id :: 4;
    }

    slot_type: u32;
}

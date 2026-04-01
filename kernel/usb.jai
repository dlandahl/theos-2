
USB_Controller :: struct {
    Socket :: struct {
        // Either of these may be null if the socket does not support that protocol.
        usb3_port: *XHCI_Port_Register_Set;
        usb2_port: *XHCI_Port_Register_Set;

        active_protocol: enum {
            NONE; USB3; USB2;
        }
    }

    sockets: [] Socket;

    mmio_base: *void;

    using capability_registers:   *XHCI_Capability_Registers;
    using operational_registers:  *XHCI_Operational_Registers;
    using runtime_registers:      *XHCI_Runtime_Registers;

    doorbells: *u32;

    arena: Physical_Memory_Arena;
}

#program_export
xhci_interrupt :: () #c_call {
    write_string("\n\nXHCI interrupt received.\n\n\n");
    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);
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

    xhci: USB_Controller;

    bar := read_base_address_register(device, 0);
    xhci.mmio_base = map_base_address_register(bar);
    
    parse_pci_capability_list(device);
    enabled := enable_msi_or_msi_x(device, isr__xhci_interrupt);
    log("Enabled interrupts: %", enabled);

    xhci.capability_registers    = cast(*XHCI_Capability_Registers)   xhci.mmio_base;
    xhci.operational_registers   = cast(*XHCI_Operational_Registers) (xhci.mmio_base + xhci.CAPLENGTH);
    xhci.runtime_registers       = cast(*XHCI_Runtime_Registers)     (xhci.mmio_base + xhci.RTSOFF);
    xhci.doorbells               = cast(*u32)                        (xhci.mmio_base + xhci.DBOFF);

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

    // All USB3 ports should be USB2 compatible.
    for xhci.sockets {
        if it.usb3_port assert(!!it.usb2_port);
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


    command_ring_physical := arena_get(*xhci.arena, 0x1_0000, 0x1_0000);

    set_bit     (*xhci.CRCR, .RCS__ring_cycle_state);
    set_in_place(*xhci.CRCR, .command_ring_pointer, command_ring_physical);

    // event_ring_max_segments := get(xhci.HCSPARAMS2, .ERST_Max);

    segment_table_physical := arena_get(*xhci.arena, align(64, size_of(Event_Ring_Segment_Table_Entry)), 0x1_0000);
    segment_table := cast(*Event_Ring_Segment_Table_Entry) (segment_table_physical + DIRECT_MAPPING_BASE);

    segment_table[0].size = 4096;
    segment_table[0].base_address = arena_get(*xhci.arena, size_of(Transfer_Event_TRB) * 4096, 0x1_0000);

    primary_interrupter := *xhci.IR[0];
    primary_interrupter.* = {};
    primary_interrupter.IMAN__interrupter_management = .IP__interrupt_pending | .IE__interrupt_enable;
    primary_interrupter.ERSTSZ__event_ring_segment_table_size = 1;
    primary_interrupter.ERSTBA__event_ring_segment_table_base = segment_table_physical;
    primary_interrupter.ERDP__event_ring_dequeue_pointer = segment_table[0].base_address;


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


    command_ring := cast(*Normal_TRB) (command_ring_physical + DIRECT_MAPPING_BASE);
    set(*command_ring[0].dword3, .trb_type, 9);
    set(*command_ring[0].dword3, .interrupt_on_completion, 1);
    set(*command_ring[0].dword3, .cycle_bit, 1);

    memory_fence();
    xhci.doorbells[0] = 0;

    log("Interrupter management: %", primary_interrupter.IMAN__interrupter_management);

    event_ring := cast(*Transfer_Event_TRB) (segment_table[0].base_address + DIRECT_MAPPING_BASE);
    log("% % %", event_ring[0].event_data, to_string(event_ring[0].dword2), to_string(event_ring[0].dword3));

    while true #asm { hlt; }
}

Device_Context_Index :: struct {
    _: void #align 64;

    scratchpad_buffers:       u64;
    device_contexts:    [255] u64;
}

#assert size_of(Device_Context_Index) == 2048;

Endpoint_Context :: struct {
    dword0: enum u32 {
        endpoint_state       :: 3;
        _                    :: 5;
        mult                 :: 2;
        max_primary_streams  :: 5;
        linear_stream_array  :: 1;
        interval             :: 8;
        max_endpoint_service_time_interval_payload_high :: 8;
    }

    dword1: enum u32 {
        _                     :: 1;
        error_count           :: 2;
        endpoint_type         :: 3;
        _                     :: 1;
        host_initiate_disable :: 1;
        max_burst_size        :: 8;
        max_packet_size       :: 8;
    }

    dword2_and_dword3 :: enum u64 {
        dequeue_cycle_state   :: 1;
        _                     :: 3;
        tr_dequeue_pointer    :: 63;
    }

    averate_trb_length: u16;
    max_endpoint_service_time_interval_payload_low: u16;

    _: [3] u32; // Used by the hardware.
}

Normal_TRB :: struct {
    data_pointer: u64;

    dword2: enum u32 {
        transfer_length    :: 17;
        td_size            :: 5;
        interrupt_target   :: 10;
    }

    dword3: enum u32 {
        cycle_bit                 :: 1;
        evaluate_next_trb         :: 1;
        interrupt_on_short_packet :: 1;
        no_snoop                  :: 1;
        chain_bit                 :: 1;
        interrupt_on_completion   :: 1;
        immediate_data            :: 1;
        _                         :: 2;
        block_event_interrupt     :: 1;
        trb_type                  :: 6;
        _                         :: 16;
    }
}

Setup_Stage_TRB :: struct {
    bm_request_type: u8;
    b_request: u8;
    w_value: u16;

    w_index: u16;
    w_length: u16;

    dword2: enum u32 {
        trb_transfer_length     :: 17;
        _                       :: 5;
        interrupt_target        :: 10;
    }

    dword3: enum u32 {
        cycle_bit               :: 1;
        _                       :: 4;
        interrupt_on_completion :: 1;
        immediate_data          :: 1;
        _                       :: 3;
        trb_type                :: 6;
        transfer_type           :: 2;
        _                       :: 14;
    }
}

Data_Stage_TRB :: struct {
    data_pointer: u64;

    dword2: enum u32 {
        trb_transfer_length    :: 17;
        td_size                :: 5;
        interrupt_target       :: 10;
    }

    dword3: enum u32 {
        cycle_bit                 :: 1;
        evaluate_next_trb         :: 1;
        interrupt_on_short_packet :: 1;
        no_snoop                  :: 1;
        chain_bit                 :: 1;
        interrupt_on_completion   :: 1;
        immediate_data            :: 1;
        _                         :: 3;
        trb_type                  :: 6;
        direction                 :: 1;
        _                         :: 15;
    }
}

Status_Stage_TRB :: struct {
    _: u64;

    dword2: enum u32 {
        _                :: 22;
        interrupt_target :: 10;
    }

    dword3: enum u32 {
        cycle_bit               :: 1;
        evaluate_next_trb       :: 1;
        _                       :: 2;
        chain_bit               :: 1;
        interrupt_on_completion :: 1;
        _                       :: 4;
        trb_type                :: 6;
        direction               :: 1;
        _                       :: 15;
    }
}

Command_Completion_TRB :: struct {
    command_trb_pointer: u64;

    dword2: enum u32 {
        _                 :: 24;
        completion_code   :: 8;
    }

    dword3: enum u32 {
        cycle_bit         :: 1;
        _                 :: 9;
        trb_type          :: 6;
        vf_id             :: 8;
        slod_id           :: 8;
    }
}

Link_TRB :: struct {
    ring_segment_pointer: u64;

    dword2: enum u32 {
        _                :: 22;
        interrupt_target :: 10;
    }

    dword3: enum u32 {
        cycle_bit               :: 1;
        toggle_cycle            :: 1;
        _                       :: 2;
        chain_bit               :: 1;
        interrupt_on_completion :: 1;
        _                       :: 4;
        trb_type                :: 6;
        _                       :: 16;
    }
}

Event_Data_TRB :: struct {
    event_data: u64;

    dword2: enum u32 {
        _                :: 22;
        interrupt_target :: 10;
    }

    dword3: enum u32 {
        cycle_bit               :: 1;
        evaluate_next_trb       :: 1;
        _                       :: 2;
        chain_bit               :: 1;
        interrupt_on_completion :: 1;
        _                       :: 3;
        block_event_interrupt   :: 1;
        trb_type                :: 6;
        _                       :: 16;
    }
}

Transfer_Event_TRB :: struct {
    event_data: u64;

    dword2: enum u32 {
        trb_transfer_length     :: 24;
        completion_code         :: 8;
    }

    dword3: enum u32 {
        cycle_bit               :: 1;
        _                       :: 1;
        event_data              :: 1;
        interrupt_on_completion :: 7;
        trb_type                :: 6;
        endpoint_id             :: 5;
        _                       :: 3;
        slot_id                 :: 8;
    }
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

    // No reason for this to be a bitfield, but maybe it should be one for consistency.
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

    dword3: enum u32 {
        device_address     :: 8;
        _                  :: 19;
        slot_state         :: 5;
    }

    // There may be four zeroed DWORDS here, depending on HCCPARAMS1.CSZ.
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
        EINT__event_interrupt;
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

XHCI_Runtime_Registers :: struct {
    // Base address of this register space is (caps + xhci.RTSOFF) (section 5.3.8).

    MFINDEX:       u32;
    _:         [7] u32;
    IR:     [1024] XHCI_Interrupter_Register_Set;
}

XHCI_Interrupter_Register_Set :: struct {
    IMAN__interrupter_management: enum_flags u32 {
        IP__interrupt_pending;
        IE__interrupt_enable;
    }

    // IMOD (interrupter moderation) register.
    IMOD__interrupter_moderation: enum u32 {
        IMODI__interval  :: 16;
        IMODC__counter   :: 16;
    }

    ERSTSZ__event_ring_segment_table_size: u32;
    _: u32;

    ERSTBA__event_ring_segment_table_base: u64;
    ERDP__event_ring_dequeue_pointer:    u64;
}

#assert size_of(XHCI_Interrupter_Register_Set) == 0x20;

xHCI_Protocol_List_Entry :: struct {
    #as dword0: enum u32 { // My physical hardware supports misaligned accesses here, but QEMU doesn't...
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

Event_Ring_Segment_Table_Entry :: struct {
    // Pointed-to by XHCI_Interrupter_Register_Set.ERSTBA

    base_address: u64;
    size: u16;

    _:  u16;
    _:  u32;
}

#assert size_of(Event_Ring_Segment_Table_Entry) == 16;

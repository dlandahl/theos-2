
// Register sets, MMIO. All reads and writes must be 4 byte aligned.

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

        port_register_set_base: void; // Array of [HCSPARAMS1.MaxPorts] XHCI_Port_Registers
    }
}

XHCI_Port_Registers :: struct {
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

XHCI_Port_Speed :: enum u16 {
    UNDEFINED           :: 0;
    FULL_SPEED          :: 1;
    LOW_SPEED           :: 2;
    HIGH_SPEED          :: 3;
    SUPER_SPEED_GEN1_1X :: 4;
    SUPER_SPEED_GEN2_1X :: 5;
    SUPER_SPEED_GEN1_2X :: 6;
    SUPER_SPEED_GEN2_2X :: 7;
}

XHCI_Runtime_Registers :: struct {
    // Base address of this register space is (xhci.mmio_base + xhci.RTSOFF) (section 5.3.8).

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



// Context stuff (in RAM.)

Device_Context_Index :: struct {
    _: void #align 64;

    scratchpad_buffers:       u64;
    device_contexts:    [255] u64;
}

#assert size_of(Device_Context_Index) == 2048;

Control_Context :: struct {
    drop_flags:   u32;
    add\_flags:   u32;

    // This may be padded to 32 or 64 bytes depending on HCCPARAMS1.CSZ.
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
        max_packet_size       :: 16;
    }

    dword2_and_dword3: enum u64 {
        dequeue_cycle_state   :: 1;
        _                     :: 3;
        tr_dequeue_pointer    :: 60;
    }

    average_trb_length: u16;
    max_endpoint_service_time_interval_payload_low: u16;

    _: [3] u32; // Used by the hardware.
}

Event_Ring_Segment_Table_Entry :: struct {
    // Pointed-to by XHCI_Interrupter_Register_Set.ERSTBA

    base_address: u64;
    size: u16;

    _:  u16;
    _:  u32;
}

#assert size_of(Event_Ring_Segment_Table_Entry) == 16;


// TRBs.
// Todo: There's a bunch of overlap between fields in the different TRB types, so maybe we can reduce the number of separate declarations.

TRB_Type :: enum {
    RESERVED                                 :: 0;
    NORMAL                                   :: 1;
    SETUP_STAGE                              :: 2;
    DATA_STAGE                               :: 3;
    STATUS_STAGE                             :: 4;
    ISOCH                                    :: 5;
    LINK                                     :: 6;
    EVENT_DATA                               :: 7;
    NO_OP                                    :: 8;
    ENABLE_SLOT_COMMAND                      :: 9;
    DISABLE_SLOT_COMMAND                     :: 10;
    ADDRESS_DEVICE_COMMAND                   :: 11;
    CONFIGURE_ENDPOINT_COMMAND               :: 12;
    EVALUATE_CONTEXT_COMMAND                 :: 13;
    RESET_ENDPOINT_COMMAND                   :: 14;
    STOP_ENDPOINT_COMMAND                    :: 15;
    SET_TR_DEQUEUE_POINTER_COMMAND           :: 16;
    RESET_DEVICE_COMMAND                     :: 17;
    FORCE_EVENT_COMMAND                      :: 18;
    NEGOTIATE_BANDWIDTH_COMMAND              :: 19;
    SET_LATENCY_TOLERANCE_VALUE_COMMAND      :: 20;
    GET_PORT_BANDWIDTH_COMMAND               :: 21;
    FORCE_HEADER_COMMAND                     :: 22;
    NO_OP_COMMAND                            :: 23;
    GET_EXTENDED_PROPERTY_COMMAND            :: 24;
    SET_EXTENDED_PROPERTY_COMMAND            :: 25;
    TRANSFER_EVENT                           :: 32;
    COMMAND_COMPLETION_EVENT                 :: 33;
    PORT_STATUS_CHANGE_EVENT                 :: 34;
    BANDWIDTH_REQUEST_EVENT                  :: 35;
    DOORBELL_EVENT                           :: 36;
    HOST_CONTROLLER_EVENT                    :: 37;
    DEVICE_NOTIFICATION_EVENT                :: 38;
    MFINDEX_WRAP_EVENT                       :: 39;
}

TRB_SIZE :: 16;

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
    request: Device_Request_Packet;

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
        slot_id           :: 8;
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

TRB_Completion_Code :: enum {
    INVALID                        :: 0;
    SUCCESS                        :: 1;
    DATA_BUFFER_ERROR              :: 2;
    BABBLE_DETECTED_ERROR          :: 3;
    USB_TRANSACTION_ERROR          :: 4;
    TRB_ERROR_ASSERTED             :: 5;
    STALL_ERROR_ASSERTED           :: 6;
    RESOURCE_ERROR                 :: 7;
    BANDWIDTH_ERROR                :: 8;
    NO_SLOTS_AVAILABLE_ERROR       :: 9;
    INVALID_STREAM_TYPE_ERROR      :: 10;
    SLOT_NOT_ENABLED_ERROR         :: 11;
    ENDPOINT_NOT_ENABLED_ERROR     :: 12;
    SHORT_PACKET                   :: 13;
    RING_UNDERRUN                  :: 14;
    RING_OVERRUN                   :: 15;
    VF_EVENT_RING_FULL_ERROR       :: 16;
    PARAMETER_ERROR                :: 17;
    BANDWIDTH_OVERRUN_ERROR        :: 18;
    CONTEXT_STATE_ERROR            :: 19;
    NO_PING_RESPONSE_ERROR         :: 20;
    EVENT_RING_FULL_ERROR          :: 21;
    INCOMPATIBLE_DEVICE_ERROR      :: 22;
    MISSED_SERVICE_ERROR           :: 23;
    COMMAND_RING_STOPPED           :: 24;
    COMMAND_ABORTED                :: 25;
    STOPPED                        :: 26;
    STOPPED_LENGTH_INVALID         :: 27;
    STOPPED_SHORT_PACKET           :: 28;
    MAX_EXIT_LATENCY_TOO_LARGE_ERROR   :: 29;
    ISOCH_BUFFER_OVERRUN           :: 31;
    EVENT_LOST_ERROR               :: 32;
    UNDEFINED_ERROR                :: 33;
    INVALID_STREAM_ID_ERROR        :: 34;
    SECONDARY_BANDWIDTH_ERROR      :: 35;
    SPLIT_TRANSACTION_ERROR        :: 36;
}

#assert size_of(Setup_Stage_TRB)        == TRB_SIZE
     && size_of(Data_Stage_TRB)         == TRB_SIZE
     && size_of(Status_Stage_TRB)       == TRB_SIZE
     && size_of(Command_Completion_TRB) == TRB_SIZE
     && size_of(Link_TRB)               == TRB_SIZE
     && size_of(Event_Data_TRB)         == TRB_SIZE
     && size_of(Transfer_Event_TRB)     == TRB_SIZE
     && size_of(Normal_TRB)             == TRB_SIZE;

Slot_State :: enum {
    DISABLED_ENABLED    :: 0;
    DEFAULT             :: 1;
    ADDRESSED           :: 2;
    CONFIGURED          :: 3;
}

Device_Request_Packet :: struct {
    request_type: enum u8 {
        recipient   :: 5; // 0 = Device, 1 = Interface, 2 = Endpoint, 3 = Other.
        type        :: 2; // 00 = Standard, 01 = Class, 10 = Vendor.
        direction   :: 1; // 0 = Host to Device, 1 = Device to Host.
    }

    request: enum u8 {
        GET_STATUS          :: 0;
        CLEAR_FEATURE       :: 1;
        _                   :: 2;
        SET_FEATURE         :: 3;
        _                   :: 4;
        SET_ADDRESS         :: 5;
        GET_DESCRIPTOR      :: 6;
        SET_DESCRIPTOR      :: 7;
        GET_CONFIGURATION   :: 8;
        SET_CONFIGURATION   :: 9;
        GET_INTERFACE       :: 10;
        SET_INTERFACE       :: 11;
        SYNCH_FRAME         :: 12;
        SET_ENCRYPTION      :: 13; // Not a typo. Earlier GET was always first, now SET is first.
        GET_ENCRYPTION      :: 14;
        SET_HANDSHAKE       :: 15;
        GET_HANDSHAKE       :: 16;
        SET_CONNECTION      :: 17;
        SET_SECURITY_DATA   :: 18;
        GET_SECURITY_DATA   :: 19;
        SET_WUSB_DATA       :: 20;
        LOOPBACK_DATA_WRITE :: 21;
        LOOPBACK_DATA_READ  :: 22;
        SET_INTERFACE_DS    :: 23;

        SET_ISOCH_DELAY     :: 49;
    }

    value: enum u16 {
        DEVICE          :: 0x100;
        CONFIGURATION   :: 0x200;
        STRING          :: 0x300;
        INTERFACE       :: 0x400;
        ENDPOINT        :: 0x500;
        // ...
    }

    index: u16;
    length: u16;
}

Descriptor_Header :: struct {
    length: u8;
    type: enum u8 {
        // Todo: This is the same enum as the high byte in the value of the device request.
        DEVICE          :: 1;
        CONFIGURATION   :: 2;
        STRING          :: 3;
        INTERFACE       :: 4;
        ENDPOINT        :: 5;
        SUPER_SPEED_ENDPOINT_COMPANION :: 0x30;
    }
}

Device_Descriptor :: struct {
    using header: Descriptor_Header;
    usb_version:           u16;
    device_class:          u8;
    device_sub_class:      u8;
    device_protocol:       u8;
    max_packet_size:       u8;

    vendor_id:             u16;
    product_id:            u16;
    device_release_number: u16;
    manufacturer_index:    u8;
    product_index:         u8;
    serial_number_index:   u8;
    num_configurations:    u8;
}

String_Descriptor :: struct {
    using header: Descriptor_Header;
    data: void; // Some number of u16s.
}

Configuration_Descriptor :: struct {
    using header: Descriptor_Header;
    total_length: u16;
    interface_count: u8;
    configuration_value: u8;
    configuration_index: u8;
    attributes: u8;
    max_power: u8;
}

Interface_Descriptor :: struct {
    using header: Descriptor_Header;
    interface_count:     u8;
    alternate_setting:   u8;
    endpoint_count:      u8;
    interface_class:     u8;
    interface_sub_class: u8;
    interface_protocol:  u8;
    interface_index:     u8;
}

Endpoint_Descriptor :: struct {
    using header: Descriptor_Header;

    address:    enum u8 {
        endpoint_number    :: 4;
        _                  :: 3;
        direction          :: 1;
    }

    attributes:          u8;
    max_packet_size:     u8;
    interval:            u8;
}

Endpoint_Type :: enum {
    INVALID          :: 0;
    ISOCH_OUT        :: 1;
    BULK_OUT         :: 2;
    INTERRUPT_OUT    :: 3;
    CONTROL          :: 4;
    ISOCH_IN         :: 5;
    BULK_IN          :: 6;
    INTERRUPT_IN     :: 7;
}

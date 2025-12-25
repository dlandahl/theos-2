
#import "Bit_Array";

Acpi_Mcfg :: struct {
    using header: Acpi_Table_Header;
    reserved: u64 #align 4;
}

Ecam_Entry :: struct {
    base_address: u64;
    segment_group: u16;
    start_bus: u8;
    end_bus: u8;
    reserved: u32;
}

find_all_pci_devices :: () {
    for global.pci_ecam {
        for bus: it.start_bus..it.end_bus {
            for device: 0..255 {
                header := read_configuration_space(it.base_address, bus, device, 0);
                if !header continue;

                if bus != 0 {
                     // Todo.
                    log_error("We assume there's only one bus when registering legacy PCI interrupts, but a device was found on a non-0 index PCI bus.");
                }

                new_device := array_add(*pci_devices);
                new_device.configuration_space = header;
                new_device.bus_address = .{bus, device.(u8), 0};

                if header.header_type & 0x80 == 0 {
                    // Device is not multi-function.
                    continue;
                }

                for function: 1..7 {
                    header = read_configuration_space(it.base_address, bus, device, function);
                    if !header continue;

                    new_device := array_add(*pci_devices);
                    new_device.configuration_space = header;
                    new_device.bus_address = .{bus, device.(u8), function.(u8)};
                }
            }
        }
    }

    find_routing_table_under_bridge :: (user: *void, node: *uacpi_namespace_node, depth: u32) -> uacpi_iteration_decision #c_call {
        node_info: *uacpi_namespace_node_info;
        uacpi_get_namespace_node_info(node, *node_info);

        routing: *uacpi_pci_routing_table;
        uacpi_get_pci_routing_table(node, *routing);

        entries := cast(*uacpi_pci_routing_table_entry) (routing + 1);

        global.pci_routing_table.count = cast(s64) routing.num_entries;
        global.pci_routing_table.data = entries;

        return .BREAK;
    }

    uacpi_find_devices("PNP0A03", find_routing_table_under_bridge, null);

    if global.pci_routing_table.data == null {
        uacpi_find_devices("PNP0A08", find_routing_table_under_bridge, null);
    }

    assert(global.pci_routing_table.data != null);
}

pci_devices: [..] Pci_Device;

Pci_Device :: struct {
    using configuration_space: *Pci_Configuration_Space;

    #overlay(configuration_space) registers: *u32;

    bus_address: Pci_Bus_Address;

    union {
        msi: *Pci_Capability_Msi;
        msi64: *Pci_Capability_Msi64;
    }
    msi_64bit_address: bool;

    msi_x: *Pci_Capability_Msi_X;
    msi_x_table: [] Msi_X_Table_Entry;
    msi_x_pending: Bit_Array;
}

Pci_Bus_Address :: struct {
    bus: u8;
    device: u8;
    function: u8;
}

read_configuration_space :: (base_address: u64, bus: int, device: int, function: int) -> *Pci_Configuration_Space {
    device_offset := cast(u64, bus * 256 + device * 8 + function);
    address := base_address + device_offset * PCI_CONFIGURATION_SPACE_SIZE;

    header := cast(*Pci_Configuration_Space, address + DIRECT_MAPPING_BASE); // Todo: does cache need to be disabled for this memory?

    if header.vendor_id == PCI_VENDOR_ID_NO_DEVICE {
        return null;
    }

    if header.class_code == .UNCLASSIFIED {
        return null;
    }

    return header;
}

Pci_Configuration_Space :: struct {
    start: void;

    vendor_id:       u16;
    device_id:       u16;
    command:         Pci_Command;
    status:          u16;
    revision_id:     u8;
    prog_if:         u8;
    subclass:        u8;
    class_code:      Pci_Class;
    cache_line_size: u8;
    latency_timer:   u8;
    header_type:     u8;
    bist:            u8;

    // Todo: probably put BARs here to simplify the BAR reading code.

    space_for_overlays: [0x100] u8;

    #overlay(start) using _: struct {
        _: [0x34] u8;
        capability_pointer: u32;
    }

    #overlay(start) using _: struct {
        _: [0x3c] u8;
        interrupt_line: u8;
        interrupt_pin:  u8;
    }
}

Pci_Capability :: struct {
    id: enum u8 {
        NULL                           :: 0x0;
        POWER_MANAGEMENT_INTERFACE     :: 0x1;
        ACCELERATED_GRAPHICS_PORT      :: 0x2;
        VITAL_PRODUCT_DATA             :: 0x3;
        SLOT_ID                        :: 0x4;
        MESSAGE_SIGNALLED_INTERRUPT    :: 0x5;

        PCI_EXPRESS                    :: 0x10;
        MSI_X                          :: 0x11;

        // More of these IDs listed at https://pcisig.com/sites/default/files/files/PCI_Code-ID_r_1_11__v24_Jan_2019.pdf
    };

    next: u8;
}

Msi_Control_Flags :: enum_flags u16 {
    ENABLE  :: 0x1;
    _64_BIT :: 0x80;
}

Pci_Capability_Msi :: struct {
    #as cap: Pci_Capability;

    control: Msi_Control_Flags;
    address: u32;
    data: u16;
}

Pci_Capability_Msi64 :: struct {
    #as cap: Pci_Capability;

    control: Msi_Control_Flags;
    address: u64 #align 1;
    data: u16;
}

Msi_X_Control :: enum u16 {
    table_size    :: 11;
    _             :: 3;
    function_mask :: 1;
    enable        :: 1;
} @Bitfield

Pci_Capability_Msi_X :: struct {
    #as cap: Pci_Capability;

    control: Msi_X_Control;
    table_offset: u32;
    pending_offset: u32;
}

Msi_X_Table_Entry :: struct {
    message_address: u64;
    message_data: u32;

    vector_control: enum_flags u32 {
        MASK :: 0x1;
    };
}

parse_pci_capability_list :: (device: *Pci_Device) {

    // Todo: this code (and probably code in other places) will likely generate non-DWORD aligned and sized accesses to PCI registers, which is not necessarily supported by the hardware.

    capability: *Pci_Capability = cast(*void) device.configuration_space + device.capability_pointer;

    while true {
        log("Found capability %.", capability.id);

        if capability.id == {
          case .MESSAGE_SIGNALLED_INTERRUPT;
            device.msi = cast(*Pci_Capability_Msi) capability;
            device.msi_64bit_address = device.msi.control & ._64_BIT > 0;

          case .MSI_X;
            device.msi_x = cast(*Pci_Capability_Msi_X) capability;
        }

        if !capability.next {
            break;
        }

        capability = cast(*void) device.configuration_space + capability.next;
    }
}

enable_msi_or_msi_x :: (device: *Pci_Device, interrupt_handler: () #c_call) -> enum { NONE; MSI; MSI_X; } {

    if device.msi_x {
        log("Enabling MSI-X");

        table_bar_index   := device.msi_x.table_offset   & 0b111;
        pending_bar_index := device.msi_x.pending_offset & 0b111;

        table_offset      := device.msi_x.table_offset   & ~0b111;
        pending_offset    := device.msi_x.pending_offset & ~0b111;

        // Todo: this BAR might be one that has already been mapped, or will be mapped for other purposes by the driver.
        // Need to add a general system for detecting when a BAR is already mapped and returning the existing memory region.
        // Mapping a BAR twice should in theory not cause errors, it just "wastes" virtual memory. Maybe all base address
        // registers that have valid addresses should be mapped when the device is detected.

        bar := read_base_address_register(device, table_bar_index);
        device.msi_x_table.data = map_base_address_register(bar) + table_offset;

        bar = read_base_address_register(device, pending_bar_index);
        device.msi_x_pending.slots.data = map_base_address_register(bar) + pending_offset;

        table_size := get(device.msi_x.control, .table_size) + 1;

        device.msi_x_table.count = table_size;
        device.msi_x_pending.count = table_size;
        device.msi_x_pending.slots.count = table_size / size_of(s64) + 1;

        gate := allocate_interrupt_gate();
        register_interrupt_gate(interrupt_handler, gate);

        for* device.msi_x_table {
            it.message_address = 0xfee0_0000;
            it.message_data    = xx gate;
            it.vector_control &= ~.MASK;
        }

        set(*device.msi_x.control, .enable, 1);
        set(*device.msi_x.control, .function_mask, 0);

        return .MSI_X;
    }

    if device.msi {
        log("Enabling MSI");

        gate := allocate_interrupt_gate();
        register_interrupt_gate(interrupt_handler, gate);

        device.msi.control |= .ENABLE;
        device.msi.address = 0xfee0_0000;

        // core := get_current_core();
        // device.msi.address |= core.local_apic_id << 12;

        if device.msi.control & ._64_BIT {
            device.msi64.data = xx gate;
        } else {
            device.msi.data = xx gate;
        }

        return .MSI;
    }

    return .NONE;
}

PCI_VENDOR_ID_NO_DEVICE :: 0xffff;
PCI_CONFIGURATION_SPACE_SIZE :: 4096;

Pci_Bar :: struct {
    base: u64;
    limit: u32;
}

read_base_address_register :: (device: Pci_Device, bar_index: int) -> Pci_Bar {
    bar := device.registers[0x4 + bar_index];

    if bar & 0b001 {
        log_error("IO-space base address registers are not supported. Device: %", device.configuration_space.*);
        bluescreen();
    }

    _64bit := cast(bool, bar & 0b100);

    mask: u64 = 0xfffffff0;
    base: u64 = bar & mask;

    if _64bit {
        bar1 := device.registers[0x4 + bar_index + 1];
        base |= cast(u64, bar1) << 32;
    }

    device.registers[0x4 + bar_index] = 0xffffffff;
    limit := device.registers[0x4 + bar_index];

    device.registers[0x4 + bar_index] = bar;

    limit = cast,trunc(u32) ~(limit & mask) + 1;

    return .{base, limit};
}

map_base_address_register :: (bar: Pci_Bar) -> *void {

    uncacheable_flags := Page_Flags.READ_WRITE | .PRESENT | .CACHE_DISABLE;

    if bar.base & 0xfff {
        // Doesn't currently handle BARs with unaligned base addresses.
        bluescreen();
    }

    virtual := alloc_block(*global.virtual_block_allocator, bar.limit);

    {
        push_print_style().default_format_int.base = 16;
        log("Mapping BAR % to address %", bar, cast(*void)virtual);
    }

    for 0..(bar.limit-1) / 4096 {
        offset := it * 4096;
        map_page(virtual + offset, bar.base + offset, uncacheable_flags);
    }

    return cast(*void) virtual;
}

register_legacy_pci_interrupt :: (pci: *Pci_Device, interrupt_handler: () #c_call) -> bool {
        
    for entry: global.pci_routing_table {
        device := (entry.address >> 16) & 0xFFFF;

        if device != pci.bus_address.device {
            continue;
        }

        if pci.interrupt_pin-1 != entry.pin {
            continue;
        }

        gate := allocate_interrupt_gate();
        register_interrupt_gate(interrupt_handler, gate);

        ioapic_add_interrupt_redirection_table_entry(entry.index, cast(u64)gate | (1 << 13) | (1 << 15));
        return true;
    }

    log_error("Failed to find routing entry for Device %d, Pin %d", pci.bus_address.device, pci.interrupt_pin);
    return false;
}

// Links for modern Realtek ethernet cards (todo):
// https://forum.osdev.org/viewtopic.php?t=57618
// https://wiki.osdev.org/RTL8169
// http://www.bitsavers.org/components/realtek/RTL8139/RTL8110S_8169S_DataSheet_1.3_200309.pdf



mac_address_print_style := Print_Style.{
    default_format_int.base = 16,
    default_format_int.minimum_digits = 2,

    default_format_array.separator = ":",
    default_format_array.begin_string = "",
    default_format_array.end_string = "",
};

I8254x_Registers :: struct {
    start: void;

    CTRL__device_control: I8254x_CTRL__Device_Control;
    STATUS__device_status: u32 #align 8;

    // Create enough room for overlay.
    _: [0x6000] u8;

    // This code was prettier with #place.
    #overlay(start) using _: struct {
        _: [0x28] u8;

        FCAL__flow_control_address_low: u32;
        FCAH__flow_control_address_high: u32;
        FCT__flow_control_type:  u32;
    }

    #overlay(start) using _: struct {
        _: [0xc0] u8;

        ICR__interrupt_cause_read: I8254x_ICR__Interrupt_Cause_Read;
        ITR: u32;
        ICS: u32;
        IMS__interrupt_mask_set: u32 #align 8;
        IMC__interrupt_mask_clear: u32 #align 8;
    }

    #overlay(start) using _: struct {
        _: [0x100] u8;
        RCTL__receive_control: I8254x_RCTL__Receive_Control;
    }

    #overlay(start) using _: struct {
        _: [0x400] u8;
        TCTL__transmit_control: I8254x_TCTL__Transmit_Control;

        // Inter-packet-gap configuration
        TIPG__transmit_ipg: enum u32 {
            IPGT__ipg_transmit_time   :: 10;
            IPGR1__ipg_receive_time_1 :: 10;
            IPGR2__ipg_receive_time_2 :: 10;
            _                         :: 2;
        } #align 16;
    }

    #overlay(start) using _: struct {
        _: [0x2800] u8;
        RDBAL__receive_descriptor_base_low: u32;
        RDBAH__receive_descriptor_base_high: u32;

        RDLEN__receive_descriptor_length: u32;
        RDH__receive_descriptor_head: u32 #align 8;
        RDT__receive_descriptor_tail: u32 #align 8;

        RDTR__receive_delay_timer_register: enum_flags u32 {
            FPD__flush_partial_descriptor_block :: 0x8000_0000;
        } #align 8;
    }

    #overlay(start) using _: struct {
        _: [0x3800] u8;
        TDBAL__transmit_descriptor_base_low: u32;
        TDBAH__transmit_descriptor_base_high: u32;

        TDLEN__transmit_descriptor_length: u32;
        TDH__transmit_descriptor_head: u32 #align 8;
        TDT__transmit_descriptor_tail: u32 #align 8;
    }

    #overlay(start) using _: struct {
        _: [0x3828] u8;
        TXDCTL__transmit_descriptor_control: I8254x_TXDCTL__Transmit_Descriptor_Control;
    }

    #overlay(start) using _: struct {
        _: [0x4000] u8;
        CRCERRS__crc_error_count: u32;
        ALGNERRC__alignment_error_count: u32;
    }

    #overlay(start) using _: struct {
        _: [0x40c0] u8;
        TORL__total_octets_received_low: u32;
        TORH__total_octets_received_high: u32;
        TOTL__total_octets_transmitted_low: u32;
        TOTH__total_octets_transmitted_high: u32;
        TPR__total_packets_received: u32;
        TPT__total_packets_transmitted: u32;
        PTC64__packets_transmitted_64_count: u32;
    }

    #overlay(start) using _: struct {
        _: [0x5200] u8;
        MTA__multicast_table_array: [128] u32;

        RAL__receive_address_low: u32;
        RAH__receive_address_high: u32;
    }
}

I8254x_CTRL__Device_Control :: enum_flags u32 {
    LRST__link_reset              :: 0x8;

    ASDE__auto_speed_detection    :: 0x20;
    SLU__set_link_up              :: 0x40;
    ILOS__invert_los              :: 0x80;

    RST__device_reset             :: 0x400_0000;
    RFCE__receive_flow_control    :: 0x800_0000;
    TFCE__transmit_flow_control   :: 0x1000_0000;

    VME__vlan_mode_enable         :: 0x4000_0000;
    PHY_RST__phy_reset            :: 0x8000_0000;
}

I8254x_RCTL__Receive_Control :: enum_flags u32 {
    EN__enable                    :: 0x2;
    SBP__store_bad_packets        :: 0x4;
    UPE__unicast_promiscuous      :: 0x8;
    MPE__multicast_promiscuous    :: 0x10;

    RDMTS0__minimum_threshold_0   :: 0x100;
    RDMTS1__minimum_threshold_1   :: 0x200;

    BAM__broadcast_accept_mode    :: 0x8000;
    BSIZE0__buffer_size_bit_0     :: 0x1_0000;
    BSIZE1__buffer_size_bit_1     :: 0x2_0000;
    BSEX__buffer_size_extension   :: 0x200_0000;
}

I8254x_TCTL__Transmit_Control :: enum_flags u32 {
    EN__enable                    :: 0x2;
    PSP__pad_short_packets        :: 0x8;
    RTLC__retransmit_on_late_collision :: 0x100_0000;
}

I8254x_TXDCTL__Transmit_Descriptor_Control :: enum u32 {
    PTHRESH__prefetch_threshold :: 6;
    _                           :: 2;
    HTHRESH__host_threshold     :: 6;
    _                           :: 2;
    WTHRESH__write_back_threshold :: 6;
    _                           :: 2;
    GRAN__granularity           :: 1;
    LWTHRESH__transmit_descriptor_low_threshold :: 7;
}

I8254x_Receive_Descriptor :: struct {
    buffer_address: u64;
    length: u16;
    checksum: u16;

    status: enum_flags u8 {
        DD__descriptor_done    :: 0x1;
        EOP__end_of_packet     :: 0x2;
        IXSM__ignore_checksum  :: 0x4;
        VP__vlan_packet        :: 0x8;
        RSV__reserved          :: 0x10;
        TCPCS__tcp_crc_calculated  :: 0x20;
        IPCS__ip_crc_calculated    :: 0x40;
        PIF__passed_inexact_filter :: 0x80;
    }

    errors: enum_flags u8 {
        CE__crc_or_alignment_error   :: 0x1;
        SE__symbol_error             :: 0x2;
        SEQ__sequence_error          :: 0x4;
        RSV_reserved_error           :: 0x8;
        CXE__carrier_extension_error :: 0x10;
        TCPE__tcp_crc_error          :: 0x20;
        IPE__ip_crc_error            :: 0x40;
        RXE__rx_data_error           :: 0x80;
    }

    special: u16;
}

I8254x_Tcpip_Data_Descriptor :: struct {
    buffer_address: u64;

    #as bitfield: enum u64 {
        DTALEN__data_length    :: 20;
        DTYP__data_type        :: 4;
        DCMD_IDE               :: 1;
        DCMD_VLE               :: 1;
        DCMD_DEXT__extension   :: 1;
        DCMD_RSV               :: 1;
        DCMD_RS__report_status :: 1;
        DCMD_TSE               :: 1;
        DCMD_IFCS              :: 1;
        DCMD_EOP               :: 1;
        STA__status            :: 4;
        RSV__reserved          :: 4;
        POPTS__packet_options  :: 8;
        SPECIAL                :: 16;
    }
}

I8254x_Transmit_Descriptor :: struct {
    buffer_address: u64;
    length: u16;

    checksum_offset: u8;
    command: enum_flags u8 {
        EOP__end_of_packet :: 0x1;
        IFCS__insert_fcs   :: 0x2;
        RS__report_status  :: 0x8;
    }

    status: u8;
    checksum_start: u8;

    special: u16;
}

I8254x_ICR__Interrupt_Cause_Read :: enum_flags u32 {
    TXDW__Transmit_Descriptor_Written_Back   :: 0x1;
    TXQE__Transmit_Queue_Empty               :: 0x2;
    LSC__Link_Status_Change                  :: 0x4;
    RXSEQ__Receive_Sequence_Error            :: 0x8;
    RXDMT0__Receive_Desc_Min_Threshold_Hit   :: 0x10;
    _                                        :: 0x20;
    RXO__Receiver_Overrun                    :: 0x40;
    RXT0__Receiver_Timer_Interrupt           :: 0x80;
    _                                        :: 0x100;
    MDAC__MDI_Interface_Access_Complete      :: 0x200;
    RXCFG__Receive_Configuration_Change      :: 0x400;
    _                                        :: 0x800;
    PHYINT__PHY_Interrupt                    :: 0x1000;
    GPI_SDP6__General_Purpose_Interrupt_SDP6 :: 0x2000;
    GPI_SDP7__General_Purpose_Interrupt_SDP7 :: 0x4000;
    GPI__General_Purpose_Interrupt           :: 0x8000;
    TXD_LOW__Transmit_Low_Threshold_Hit      :: 0x10000;
    SRPD__Small_Receive_Packet_Detected      :: 0x20000;
}

I8254x_MAC :: union {
    struct { ral, rah: u32; }
    array: [6] u8;
}

#program_export
i8254x_interrupt :: (stack: *void) #c_call {

    // Todo: Should have a special interrupt Context, that ensures interrupts don't accidentally use temporary storage etc.
    push_context {
        net := *global.network_connection;
        cause := net.adapter.ICR__interrupt_cause_read;

        if cause & .RXT0__Receiver_Timer_Interrupt {
            signal(*net.work_to_do);
        }

        write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);
    }
} @InterruptRoutine

I8254x_Network_Interface_Card :: struct {
    using mmio: *I8254x_Registers;

    tx_queue_tail: u32;
    rx_queue_head: int;

    tx_queue: [] I8254x_Transmit_Descriptor;
    rx_queue: [] I8254x_Receive_Descriptor;

    mac_address: [6] u8;
}

init_i8254x :: (device: *Pci_Device) -> I8254x_Network_Interface_Card {
    log_category("8254x");

    log("Vendor ID: %", hex(device.vendor_id));
    log("Device ID: %", hex(device.device_id));

    device.command |= .BUS_MASTER | .MEMORY_SPACE;
    device.command &= ~.INTERRUPT_DISABLE;

    success := register_legacy_pci_interrupt(device, isr__i8254x_interrupt);

//    parse_pci_capability_list(device);
//    enabled := enable_msi_or_msi_x(device, isr__i8254x_interrupt);
//
//    if enabled == .NONE {
//        if !success {
//            log_error("Failed to set up interrupt.");
//            bluescreen();
//        } else {
//            log("Enabled legacy interrupts.");
//        }
//    }

    nic: I8254x_Network_Interface_Card;

    bar0 := read_base_address_register(device, 0);
    nic.mmio = map_base_address_register(bar0);

    {
        // Reset the controller

        // The bit should be readable after one microsecond, and should eventually clear once reset is complete.
        // Spin for 2us to be safe.

        nic.CTRL__device_control |= .RST__device_reset;
        busy_wait(2);

        if Timeout(nic.CTRL__device_control & .RST__device_reset == 0) {
            log_error("Timeout during device reset.");
            return nic;
        }

        // To reset the PHY, PHY_RST should be asserted for 10ms. Spin for 15ms to be safe.

        nic.CTRL__device_control |= .PHY_RST__phy_reset;
        busy_wait(15_000);
        nic.CTRL__device_control &= ~.PHY_RST__phy_reset;
    }

    // Disable interrupts
    nic.IMC__interrupt_mask_clear = 0xffff_ffff;
    _ := nic.ICR__interrupt_cause_read;

    // Get MAC address
    mac: I8254x_MAC;
    mac.ral = nic.RAL__receive_address_low;
    mac.rah = nic.RAH__receive_address_high;
    nic.mac_address = mac.array;

    {
        push_print_style(mac_address_print_style);
        log("MAC address: %", nic.mac_address);
    }

    {
        // General configuration
        ctrl := nic.CTRL__device_control;

        ctrl &= ~.LRST__link_reset;
        ctrl &= ~.ILOS__invert_los;
        ctrl &= ~.VME__vlan_mode_enable;
        ctrl &= ~.RFCE__receive_flow_control;
        ctrl &= ~.TFCE__transmit_flow_control;

        ctrl |= .ASDE__auto_speed_detection;
        ctrl |= .SLU__set_link_up;

        nic.CTRL__device_control = ctrl;

        for* nic.MTA__multicast_table_array it.* = 0;

        // Disable flow control
        nic.FCAL__flow_control_address_low = 0;
        nic.FCAH__flow_control_address_high = 0;
        nic.FCT__flow_control_type = 0;

        nic.IMS__interrupt_mask_set = 0xffff_ffff;
    }

    {
        // Transmit packets

        // Allocate transmit descriptor queue
        transmit_desc_buffer := get_4k_page();

        nic.tx_queue.data = cast(*I8254x_Transmit_Descriptor, transmit_desc_buffer + DIRECT_MAPPING_BASE); // Todo: does cache need to be disabled for this memory?
        nic.tx_queue.count = 4096 / size_of(I8254x_Transmit_Descriptor);

        nic.TDBAL__transmit_descriptor_base_low  = cast(u32, transmit_desc_buffer & 0xffff_ffff);
        nic.TDBAH__transmit_descriptor_base_high = cast(u32, transmit_desc_buffer >> 32);

        nic.TDLEN__transmit_descriptor_length = 4096;

        nic.TDT__transmit_descriptor_tail = 0;
        nic.TDH__transmit_descriptor_head = 0;

        txdctl: I8254x_TXDCTL__Transmit_Descriptor_Control;
        set(*txdctl, .PTHRESH__prefetch_threshold, 0x3f);
        set(*txdctl, .HTHRESH__host_threshold, 0x3f);
        set(*txdctl, .WTHRESH__write_back_threshold, 0x1);
        nic.TXDCTL__transmit_descriptor_control = txdctl;

        tctl := I8254x_TCTL__Transmit_Control
              .PSP__pad_short_packets
            | .RTLC__retransmit_on_late_collision
            | .EN__enable;

        // COLD and CT, todo: magic numbers
        tctl |= (0x0f << 4) | (0x40 << 12);

        nic.TCTL__transmit_control = tctl;

        ipg: type_of(nic.TIPG__transmit_ipg);
        set(*ipg, .IPGT__ipg_transmit_time, 10);
        set(*ipg, .IPGR1__ipg_receive_time_1, 10);
        set(*ipg, .IPGR2__ipg_receive_time_2, 10);
        nic.TIPG__transmit_ipg = ipg;
    }

    {
        // Receive packets

        // Allocate receive descriptor queue
        receive_desc_buffer := get_4k_page();

        nic.rx_queue.data = cast(*I8254x_Receive_Descriptor, receive_desc_buffer + DIRECT_MAPPING_BASE); // Todo: does cache need to be disabled for this memory?
        nic.rx_queue.count = 4096 / size_of(I8254x_Receive_Descriptor);

        nic.RDBAL__receive_descriptor_base_low  = cast(u32, receive_desc_buffer & 0xffff_ffff);
        nic.RDBAH__receive_descriptor_base_high = cast(u32, receive_desc_buffer >> 32);

        nic.RDLEN__receive_descriptor_length = 4096;

        nic.RCTL__receive_control =
              .BSIZE0__buffer_size_bit_0
            | .BSIZE1__buffer_size_bit_1
            | .BSEX__buffer_size_extension
            | .BAM__broadcast_accept_mode
        //  | .UPE__unicast_promiscuous
        //  | .MPE__multicast_promiscuous
            | .RDMTS1__minimum_threshold_1
            | .EN__enable;

        for* nic.rx_queue {
            it.buffer_address = get_4k_page();
        }

        nic.RDH__receive_descriptor_head = 0;
        nic.RDT__receive_descriptor_tail = cast(u32, nic.rx_queue.count-1);
    }

    return nic;
}

i8254x_get_newly_received_packets :: (nic: *I8254x_Network_Interface_Card) -> [] Network_Packet {

    new_head := nic.RDH__receive_descriptor_head;
    packets_received := NewArray(new_head - nic.rx_queue_head, Network_Packet,, temp);

    for* packets_received {
        i8254_packet := *nic.rx_queue[nic.rx_queue_head];

        it.data = cast(*void, i8254_packet.buffer_address + DIRECT_MAPPING_BASE);
        it.length = i8254_packet.length;

        nic.rx_queue_head += 1;
    }

    return packets_received;
}

i8254x_transmit_packet :: (nic: *I8254x_Network_Interface_Card, packet: Network_Packet) -> bool {
    log_category("8254x");

    if !packet.data || !packet.length {
        log_error("Uninitialized packet: %", packet);
        return false;
    }

    success := true;

    desc := *nic.tx_queue[nic.tx_queue_tail];

    desc.buffer_address = get_physical_address(packet.data);
    desc.length = cast(u16) packet.length;
    desc.command = .RS__report_status | .IFCS__insert_fcs | .EOP__end_of_packet;

    barrier();

    nic.tx_queue_tail += 1;
    nic.TDT__transmit_descriptor_tail = nic.tx_queue_tail;

    if Timeout(nic.TPT__total_packets_transmitted) {
        log_error("Failed to transmit network packet. (%)", desc.status);
        success = false;
    }

    if desc.status > 1 { // I don't know why it's sometimes 0... we expect it to always be at least 1 after transmission due to the RS__report status flag.
        log("Transmit descriptor status: %", desc.status);
    }

    return success;
}




Nvme_Controller :: struct {
    using mmio: *Nvme_Property_Memory_Map;

    queue_size: u32;

    admin_sq_tail: u32;
    admin_sq: *Nvme_Submission_Queue_Entry;

    admin_cq_head: u32;
    admin_cq: *Nvme_Completion_Queue_Entry;

    io_sq_tail: u32;
    io_sq: *Nvme_Submission_Queue_Entry;

    io_cq_head: u32;
    io_cq: *Nvme_Completion_Queue_Entry;

    // A namespace ID identifies a drive.
    nsid: u32;
}

Nvme_Property_Memory_Map :: struct {
    start: void;

    CAP__capabilities:            Nvme_Controller_Capabilities;
    VS__version:                  Nvme_Specification_Version_Descriptor;
    INTMS:                        u32;
    INTMC:                        u32;
    CC__controller_config:        Nvme_Controller_Configuration;
    _:                            u32;
    CSTS__controller_status:      Nvme_Controller_Status;
    NSSR:                         u32;
    AQA__admin_queue_attributes:  Nvme_Admin_Queue_Attributes;
    ASQ__admin_sq:  u64;
    ACQ__admin_cq:  u64;

    space_for_overlay: [0x2000] u8;

    // Would be nice to be able to give a constant to #place
    #overlay(start) using _: struct {
        offset_for_transport_specific_properties: [0x1000] u8;
        doorbell_base: void;

        SQ0TDBL__submission_queue_0_tail_doorbell: u32;
        CQ0HDBL__completion_queue_0_head_doorbell: u32;
    }
}

Nvme_Controller_Capabilities :: enum u64 {
    MQES__maximum_queue_entries          :: 16;
    CQR__contiguous_queue_entries        :: 1;
    AMS__arbitration_mechanism_supported :: 2;
    _                                    :: 5;
    TO__timeout                          :: 8;
    DSTRD__doorbell_stride               :: 4;
    NSSRS__nvm_subsystem_reset           :: 1;
    NCSS__nvm_command_set_support        :: 1;
    _                                    :: 5;
    IOCSS__io_command_set_support        :: 1;
    NOIOCSS__no_io_command_set_support   :: 1;

    BPS    :: 1;
    CPS    :: 2;
    MPSMIN :: 4;
    MPSMAX :: 4;
    PMRS   :: 1;
    CMBS   :: 1;
    NSSS   :: 1;
    CRMS   :: 2;
    NSSES  :: 1;
    _      :: 2;
} @Bitfield

Nvme_Specification_Version_Descriptor :: struct {
    ter__teritary: u8;
    mnr__minor:    u8;
    mjr__major:    u16;
}

Nvme_Controller_Configuration :: enum u32 {
    EN__enable                   :: 1;
    _                            :: 3;
    CSS__io_command_set          :: 3;
    MPS__memory_page_size        :: 4;
    AMS__arbitration_mechanism   :: 3;
    SHN__shutdown_notification   :: 2;
    IOSQES__io_submission_entry_size :: 4;
    IOCQES__io_completion_entry_size :: 4;

    __rest_of_the_bits :: 8;
} @Bitfield

Nvme_Controller_Status :: enum_flags u32 {
    RDY__READY                   :: 0x1;
    CFS__CONTROLLER_FATAL_STATUS :: 0x2;
    SHST__SHUTDOWN_STATUS0       :: 0x4;
    SHST__SHUTDOWN_STATUS1       :: 0x8;
    ST__SHUTDOWN_TYPE            :: 0x40;
}

Nvme_Admin_Queue_Attributes :: struct {
    ASQS__submission_queue_size: u16;
    ACQS__completion_queue_size: u16;
}

Nvme_Submission_Queue_Entry :: struct {
    OPC__opcode: Nvme_Opcode;
    FUSE_and_PSDT: u8;
    CID__command_id: u16;
    NSID__namespace_id: u32;

    CDW2__command_dword_2: u32;
    CDW3__command_dword_3: u32;

    MPTR__metadata_pointer: u64;
    DPTR__data_pointer:     [2] u64;

    union {
        CDW__command_dwords_10_to_15: [6] u32;

        // For IDENTIFY commands:
        CNS__controller_or_namespace: Nvme_Controller_Or_Namespace_Structure;

        struct {
            // For CREATE_IO_*_QUEUE:
            QID__queue_identifier: u16;
            QSIZE__queue_size: u16;

            PC__physically_contiguous: u16;
            CQID__completion_queue_identifier: u16;
        }

        struct {
            // For IO READ:
            SLBA__starting_lba: u64;
            NLB__number_of_logical_blocks: u16;
        }
    }
}

Nvme_Completion_Queue_Entry :: struct {
    DW0: u32;
    DW1: u32;

    SQHD__sq_head_pointer: u16;
    SQID__sq_identifier: u16;

    CID__command_identifier: u16;
    STATUS__status: u16;
}

Nvme_Opcode :: enum u8 {
    // Admin opcodes
    DELETE_IO_SUBMISSION_QUEUE :: 0x0;
    CREATE_IO_SUBMISSION_QUEUE :: 0x1;
    GET_LOG_PAGE               :: 0x2;
    DELETE_IO_COMPLETION_QUEUE :: 0x4;
    CREATE_IO_COMPLETION_QUEUE :: 0x5;
    IDENTIFY                   :: 0x6;
    ABORT                      :: 0x8;

    // IO opcodes
    FLUSH                      :: 0x0;
    WRITE                      :: 0x1;
    READ                       :: 0x2;
}

Nvme_Controller_Or_Namespace_Structure :: enum u8 {
    IDENTIFY_NAMESPACE       :: 0x0;
    IDENTIFY_CONTROLLER      :: 0x1;
    ACTIVE_NAMESPACE_ID_LIST :: 0x2;
}

Nvme_Identify_Controller_Structure :: struct {
    VID__pci_vendor_id: u16;
    SSVID__pci_subsystem_vendor_id: u16;
    SN__serial_number: [20] u8;
    MN__model_number:  [40] u8;
}

#assert size_of(Nvme_Submission_Queue_Entry) == 64;

#program_export
nvme_interrupt :: (stack: *void) {
    write_string("NVMe interrupt recieved.\n");

    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);
} @InterruptRoutine

init_nvme_controller :: (device: *Pci_Device) -> Nvme_Controller {
    log_category("NVMe");

    if device.class_code != .MASS_STORAGE bluescreen();
    if device.subclass   != 0x8           bluescreen();

    device.command |= .BUS_MASTER | .MEMORY_SPACE;
    device.command &= ~.INTERRUPT_DISABLE;

    parse_pci_capability_list(device);

    // enabled := enable_msi_or_msi_x(device, isr__nvme_interrupt);
    // assert(enabled == .MSI_X);
    register_legacy_pci_interrupt(device, isr__nvme_interrupt);

    // Mask out the admin queue interrupt. Just spin on the phase bit for now
    // device.msi_x_table[0].vector_control |= .MASK;

    nvme: Nvme_Controller;

    bar := read_base_address_register(device, bar_index = 0);
    nvme.mmio = map_base_address_register(bar);

    nvme.queue_size = 4096 / size_of(Nvme_Submission_Queue_Entry);

    nvme_reset_controller(*nvme);

    {
        // Send IDENTIFY command.
        admin_command: Nvme_Submission_Queue_Entry;
        admin_command.OPC__opcode = .IDENTIFY;
        admin_command.CNS__controller_or_namespace = .IDENTIFY_CONTROLLER;
        admin_command.DPTR__data_pointer[0] = get_4k_page();

        nvme_send_admin_command(*nvme, admin_command);

        identify := cast(*Nvme_Identify_Controller_Structure, admin_command.DPTR__data_pointer[0] + DIRECT_MAPPING_BASE);

        sn := cast(string) identify.SN__serial_number;
        mn := cast(string) identify.MN__model_number;
        for sn if it == #char " " { sn.count = it_index; break; }
        for mn if it == #char " " { mn.count = it_index; break; }

        log("Found controller with serial number '%' and model number '%'.", sn, mn);
        free_4k_page(admin_command.DPTR__data_pointer[0]);
    }

    {
        // Get active namespace ID list.
        admin_command: Nvme_Submission_Queue_Entry;
        admin_command.OPC__opcode = .IDENTIFY;
        admin_command.CNS__controller_or_namespace = .ACTIVE_NAMESPACE_ID_LIST;
        admin_command.DPTR__data_pointer[0] = get_4k_page();

        nvme_send_admin_command(*nvme, admin_command);

        nsid_list := cast(*[1024]u32) (admin_command.DPTR__data_pointer[0] + DIRECT_MAPPING_BASE);

        for nsid_list.* if it != 0 {
            nvme.nsid = it;
            break;
        }

        if nvme.nsid == 0 {
            log_error("No active namespace ID found");
            bluescreen();
        }

        log("Found NSID %.", nvme.nsid);
        free_4k_page(admin_command.DPTR__data_pointer[0]);
    }

    {
        // Create IO queues.
        io_cq_base := get_4k_page();
        io_sq_base := get_4k_page();

        admin_command: Nvme_Submission_Queue_Entry;
        admin_command.OPC__opcode = .CREATE_IO_COMPLETION_QUEUE;
        admin_command.DPTR__data_pointer[0] = io_cq_base;
        admin_command.NSID__namespace_id = nvme.nsid;
        admin_command.QSIZE__queue_size = cast(u16) nvme.queue_size;
        admin_command.QID__queue_identifier = 1;
        admin_command.PC__physically_contiguous = 1;

        nvme_send_admin_command(*nvme, admin_command);

        admin_command.OPC__opcode = .CREATE_IO_SUBMISSION_QUEUE;
        admin_command.DPTR__data_pointer[0] = io_sq_base;
        admin_command.CQID__completion_queue_identifier = 1;

        nvme_send_admin_command(*nvme, admin_command);

        nvme.io_sq = xx (io_sq_base + DIRECT_MAPPING_BASE); // Todo: does cache need to be disabled for this memory?
        nvme.io_cq = xx (io_cq_base + DIRECT_MAPPING_BASE);
    }

    {
        // Read bootsector test.
        buffer := get_4k_page();

        io_command: Nvme_Submission_Queue_Entry;
        io_command.OPC__opcode = .READ;
        io_command.DPTR__data_pointer[0] = buffer;
        io_command.NSID__namespace_id = nvme.nsid;
        io_command.SLBA__starting_lba = 0;
        io_command.NLB__number_of_logical_blocks = 0; // This means 1 block

        nvme_send_io_command(*nvme, io_command);

        if (.*) cast(*u16) (buffer + 510 + DIRECT_MAPPING_BASE) == 0xaa55 {
            log("Success");
        } else {
            log("Failure");
        }
    }

    return nvme;
}

nvme_reset_controller :: (nvme: *Nvme_Controller) {
    if (nvme.CSTS__controller_status & .SHST__SHUTDOWN_STATUS0) || (nvme.CSTS__controller_status & .SHST__SHUTDOWN_STATUS1) {
        log("Shutdown status.");
    }

    if nvme.CC__controller_config & .EN__enable {
        set(*nvme.CC__controller_config, .EN__enable, 0);
    }

    if Timeout(!(nvme.CSTS__controller_status & .RDY__READY)) {
        log_error("Reset timeout (RDY is set.)");
        return;
    }

    // Initialize admin queues.
    admin_sq := get_4k_page();
    admin_cq := get_4k_page();

    // Subtract one, because the field is zero based.
    queue_size := nvme.queue_size - 1;

    nvme.AQA__admin_queue_attributes = .{
        cast(u16) queue_size,
        cast(u16) queue_size
    };

    nvme.ASQ__admin_sq = admin_sq;
    nvme.ACQ__admin_cq = admin_cq;

    virt := alloc_block(*global.virtual_block_allocator, 4096 * 2);
    map_page(virt,        admin_sq, .PRESENT | .READ_WRITE | .CACHE_DISABLE);
    map_page(virt + 4096, admin_cq, .PRESENT | .READ_WRITE | .CACHE_DISABLE);

    nvme.admin_sq = cast(*Nvme_Submission_Queue_Entry) virt;
    nvme.admin_cq = cast(*Nvme_Completion_Queue_Entry) (virt + 4096);

    NOIOCSS := get(nvme.CAP__capabilities, .NOIOCSS__no_io_command_set_support);
    IOCSS   := get(nvme.CAP__capabilities, .IOCSS__io_command_set_support);
    NCSS    := get(nvme.CAP__capabilities, .NCSS__nvm_command_set_support);

    if NOIOCSS         set(*nvme.CC__controller_config, .CSS__io_command_set, 0b111);
    if IOCSS           set(*nvme.CC__controller_config, .CSS__io_command_set, 0b110);
    if !IOCSS && NCSS  set(*nvme.CC__controller_config, .CSS__io_command_set, 0b000);

    set(*nvme.CC__controller_config, .AMS__arbitration_mechanism, 0);
    set(*nvme.CC__controller_config, .MPS__memory_page_size, 0);

    // Todo, detect these values
    set(*nvme.CC__controller_config, .IOSQES__io_submission_entry_size, 6);
    set(*nvme.CC__controller_config, .IOCQES__io_completion_entry_size, 4);

    barrier();

    set(*nvme.CC__controller_config, .EN__enable, 1);

    if Timeout_Block(#code {
        if nvme.CSTS__controller_status & .RDY__READY break;

        fatal := nvme.CSTS__controller_status & .CFS__CONTROLLER_FATAL_STATUS;
        if fatal {
            log_error("Controller fatal status during reset.");
            bluescreen();
        }
    }) {
        log("Reset timeout (RDY is unset.)");
    }
}

nvme_send_admin_command :: (using nvme: *Nvme_Controller, command: Nvme_Submission_Queue_Entry) {
    log_category("NVMe");
    admin_sq[admin_sq_tail] = command;

    start_phase := admin_cq[admin_cq_head].STATUS__status & 1;

    admin_sq_tail += 1;
    if admin_sq_tail == queue_size then admin_sq_tail = 0;

    barrier();
    SQ0TDBL__submission_queue_0_tail_doorbell = admin_sq_tail;

    Timeout((admin_cq[admin_cq_head].STATUS__status & 1) != start_phase);

    status := admin_cq[admin_cq_head].STATUS__status >> 1;
    if status != 0 {
        log_error("Admin command failed with status %", status);
    }

    admin_cq_head += 1;
    if admin_cq_head == queue_size then admin_cq_head = 0;

    barrier();
    CQ0HDBL__completion_queue_0_head_doorbell = admin_cq_head;
}

nvme_send_io_command :: (using nvme: *Nvme_Controller, command: Nvme_Submission_Queue_Entry) {
    log_category("NVMe");
    io_sq[io_sq_tail] = command;

    start_phase := io_cq[io_cq_head].STATUS__status & 1;

    io_sq_tail += 1;
    if io_sq_tail == queue_size then io_sq_tail = 0;

    sq_tail_doorbell := *doorbell_base;
    sq_tail_doorbell += 2 * (4 << get(CAP__capabilities, .DSTRD__doorbell_stride));

    barrier();
    cast(*u32, sq_tail_doorbell).* = io_sq_tail;

    Timeout((io_cq[io_cq_head].STATUS__status & 1) != start_phase);

    status := io_cq[io_cq_head].STATUS__status >> 1;
    if status != 0 {
        log_error("IO command failed with status %", status);
    }

    io_cq_head += 1;
    if io_cq_head == queue_size then io_cq_head = 0;

    cq_head_doorbell := *doorbell_base;
    cq_head_doorbell += 3 * (4 << get(CAP__capabilities, .DSTRD__doorbell_stride));

    barrier();
    cast(*u32, cq_head_doorbell).* = io_cq_head;
}





Ahci_Controller :: struct {
    command_list: [] Ahci_Command_Header;
    command_table: [32] *Ahci_Command_Table;

    received_fis: *Ahci_Received_Fis;
    port: *Ahci_Port;
    ahci: *Ahci_Memory_Region;
}

#program_export
ahci_interrupt :: (data: *void) {
    write_string("Handling AHCI Interrupt.\n");
    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);
} @InterruptRoutine

init_ahci_controller :: (device: *Pci_Device) -> c: Ahci_Controller = .{}, success: bool {
    log_category("AHCI");

    device.command |= .BUS_MASTER | .MEMORY_SPACE;
    device.command &= ~.INTERRUPT_DISABLE;

    parse_pci_capability_list(device);
    enable_msi_or_msi_x(device, isr__ahci_interrupt);

    bar := read_base_address_register(device, bar_index = 5);
    if !bar.base {
        log_error("Controller has no base address set");
        return success = false;
    }

    ahci := cast(*Ahci_Memory_Region) map_base_address_register(bar);

    log("Interrupt status is %.\n", ahci.IS__interrupt_status);

    ahci.GHC__global_host_control |= .AE__ahci_enable | .IE__interrupt_enable;

    if !(ahci.CAP__host_capabilities & .S64A__64bit_addressing) {
        log_error("Controller without 64-bit addressing not supported");
        return success = false;
    }

    if !(ahci.CAP__host_capabilities & .SAM__supports_ahci_only) {
        ahci.GHC__global_host_control |= .HR__hba_reset;
    }

    // Todo bitfield
    num_ports          := cast(int,  ahci.CAP__host_capabilities       & 0b11111) + 1;
    command_slot_count := cast(int, (ahci.CAP__host_capabilities >> 8) & 0b11111) + 1;

    max_ports := 32;

    for 0..max_ports-1 {
        if !(ahci.PI__ports_implemented & (1 << it)) {
            continue;
        }

        port := *ahci.ports[it];

        if ahci_port_is_running(port) {
            port.CMD__command_status &= ~.ST__start;

            if Timeout(!(port.CMD__command_status & .CR__command_list_running)) {
                log_error("Port not idle timeout (command list running)");
                return success = false;
            }

            port.CMD__command_status &= ~.FRE__fis_receive_enable;

            if Timeout(!(port.CMD__command_status & .FR__receive_running)) {
                log_error("Port not idle timeout (receive running)");
                return success = false;
            }
        }
    }

    for 0..max_ports-1 {
        if !(ahci.PI__ports_implemented & (1 << it)) continue;

        port := *ahci.ports[it];
        if !(port.CMD__command_status & .SUD__spin_up_device) {
            log_error("Port not spun up");
            return success = false;
        }

        // if ahci.CAP__host_capabilities & .STAGGERED_SPIN_UP {
        // }

        detection := port.SSTS__sata_status & .DET_MASK;
        if detection != .DET_ESTABLISHED continue;

        ipm := port.SSTS__sata_status & .IPM_MASK;
        if ipm != .IPM_ACTIVE {
            log_error("Port power management interface state is not active. See 3.3.10 (PxSSTS)");
            return success = false;
        }

        if port.SIG__signature != .ATA {
            log_error("We only handle the \"ATA\" device signature");
            return success = false;
        }

        log("Interrupt status (port) is %.\n", port.IS__interrupt_status);

        // Need a better allocator for cache-disabled memory
        list_size := align(4096, size_of(Ahci_Command_Header) * command_slot_count);
        fis_size  := align(4096, size_of(Ahci_Received_Fis));

        memory_needed := cast(u64, list_size + fis_size + command_slot_count * 4096 + 4096);

        using global;
        virtual  := cast(*void) alloc_block(*virtual_block_allocator,  memory_needed);
        physical :=             alloc_block(*physical_block_allocator, memory_needed);

        // The virtual memory gets aligned by the allocator
        physical = xx align(4096, xx physical);

        page_flags := Page_Flags.READ_WRITE | .PRESENT | .CACHE_DISABLE;
        pages_needed := memory_needed / 4096;

        for 0..pages_needed-1 {
            offset := cast(u64) it * 4096;
            map_page(virtual + offset, physical + offset, page_flags);
        }

        controller: Ahci_Controller;
        controller.command_list.count = command_slot_count;

        controller.command_list.data = virtual;
        controller.received_fis      = virtual + list_size;

        port.CLB__command_list_base  = physical;
        port.FB__fis_base            = physical + cast(u64) list_size;

        controller.port = port;

        for* controller.command_list {
            offset := list_size + fis_size + it_index * 4096;
            controller.command_table[it_index] = virtual + offset;

            it.CTBA__command_table_base = physical + cast(u64) offset;
        }

        port.IE__interrupt_enable = 0xffff_ffff;

        port.CMD__command_status |= .FRE__fis_receive_enable;

        if Timeout(port.CMD__command_status & .FR__receive_running) {
            log_error("Port idle timeout (receive running)");
            return success = false;
        }

        port.CMD__command_status |= .ST__start;

        if Timeout(port.CMD__command_status & .CR__command_list_running) {
            log_error("Port idle timeout (command list running)");
            return success = false;
        }

        controller.ahci = ahci;
        return controller, true;
    }

    bluescreen();
    return success = false;
}

ahci_port_is_running :: (port: *Ahci_Port) -> bool {
    return (port.CMD__command_status & .ST__start)
        || (port.CMD__command_status & .CR__command_list_running)
        || (port.CMD__command_status & .FRE__fis_receive_enable)
        || (port.CMD__command_status & .FR__receive_running);
}

Transfer_Direction :: enum {
    READ;
    WRITE;
}

ahci_transfer :: (controller: *Ahci_Controller, direction: Transfer_Direction, memory_address: u64, number_of_bytes: u64, disk_address: u64) {
    log_category("AHCI");

    assert(cast(u64) memory_address % 0x200 == 0);

    sector_count : u64 = (number_of_bytes + 0x1ff) / 0x200;
    lba          : u64 = (disk_address    + 0x1ff) / 0x200;

    if sector_count == 0 return;

    // DMA hardware does not support memory accesses that cross a 64k boundary in physical memory.
    // This code splits the operation into 64k blocks.

    first_sector_count := (0x1_0000 - memory_address % 0x1_0000) / 0x200;
    if first_sector_count > sector_count first_sector_count = sector_count;
    sector_count -= first_sector_count;

    ahci_transfer_sectors(controller, direction, memory_address, cast(u32) lba, xx first_sector_count);

    lba            += first_sector_count;
    memory_address += first_sector_count * 0x200;

    while sector_count > 128 {
        ahci_transfer_sectors(controller, direction, memory_address, cast(u32) lba, 128);
        memory_address += 0x1_0000;
        lba += 128;
        sector_count -= 128;
    }

    if sector_count {
        ahci_transfer_sectors(controller, direction, memory_address, xx lba, xx sector_count);
    }
}

ahci_transfer_sectors :: (controller: *Ahci_Controller, direction: Transfer_Direction, physical: u64, lba: u64, sector_count: int) {
    log_category("AHCI");

    fis: Ahci_Command_Fis;
    fis.flags = .IS_COMMAND;
    fis.command = ifx direction == .READ then Ata_Command.READ_DMA_EX else .WRITE_DMA_EX;
    fis.device = 1 << 6; // Todo magic number

    fis.sectors_low  = cast(u8, sector_count);
    fis.sectors_high = cast(u8, sector_count >> 8);

    fis.lba_0 = cast(u8, lba);
    fis.lba_1 = cast(u8, lba >> 8);
    fis.lba_2 = cast(u8, lba >> 16);
    fis.lba_3 = cast(u8, lba >> 24);
    fis.lba_4 = cast(u8, lba >> 32);
    fis.lba_5 = cast(u8, lba >> 40);

    table := controller.command_table[0];
    table.CFIS__command_fis = fis;

    // Todo: This driver uses only one physical region at a time, in one command list entry at a time, on one port.
    // It needs to be generalised to access drives on any port, and should dynamically allocate command lists that
    // contain more physical region descriptors, to reduce software overhead of disk access.
    controller.command_list[0].PRDTL__prd_table_length = 1;
    controller.command_list[0].PRDBC__prd_byte_count = 0;
    controller.command_list[0].flags = size_of(Ahci_Command_Fis) / 4;

    if direction == .WRITE {
        controller.command_list[0].flags |= .WRITE;
    }

    prdt := *table.PRDT__physical_region_descriptor_table[0];
    prdt.DBA__data_base_address = physical;
    prdt.DBC__data_byte_count = cast(u16) sector_count * 0x200 - 1;
    prdt.I__interrupt_on_completion = .YES;

    {
        push_print_style();
        context.print_style.default_format_int.base = 16;
        log("PRDT: %\n", prdt.*);
    }

    if Timeout_Block(#code {
        if controller.port.SACT__sata_active & 1 continue;

        ata_status := cast(u32, Ata_Status.BUSY | .TRANSFER_REQUESTED);

        if controller.port.TFD__task_file_data & ata_status {
            continue;
        }

        break;
    }) {
        log_error("SATA busy timeout");
        return;
    }

    barrier();
    assert(!(controller.port.CI__command_issue & 1));
    controller.port.CI__command_issue |= 1;

    if Timeout(!(controller.port.CI__command_issue & 1)) {
        log_error("SATA command issue timeout");
    }


    for 1..1_000_000 #asm { pause; }

    log("(Transfer) Interrupt status is %.\n", controller.ahci.IS__interrupt_status);
    log("(Transfer) Interrupt status (port) is %.\n", controller.port.IS__interrupt_status);

}

Ata_Command :: enum u8 {
    READ_PIO     :: 0x20;
    READ_DMA     :: 0xc8;
    READ_DMA_EX  :: 0x25;
    WRITE_PIO    :: 0x30;
    WRITE_DMA    :: 0xca;
    WRITE_DMA_EX :: 0x35;
    IDENTIFY     :: 0xec;
}

Ata_Status :: enum_flags u8 {
    NONE                :: 0x0;
    ERROR               :: 0x1;
    INDEX               :: 0x2;
    CORRECTED_DATA      :: 0x4;
    TRANSFER_REQUESTED  :: 0x8;
    SEEK_COMPLETE       :: 0x10;
    DEVICE_FAULT        :: 0x20;
    READY               :: 0x40;
    BUSY                :: 0x80;
}

Ahci_Command_Header :: struct {
    flags: enum u16 {
        WRITE :: 0x40;
    }

    PRDTL__prd_table_length: u16;
    PRDBC__prd_byte_count: u32;
    CTBA__command_table_base: u64;
    
    reserved: [4] u32;
}

Ahci_Command_Table :: struct {
    CFIS__command_fis:   Ahci_Command_Fis;
    RSV0__reserved:      [44] u8;
    ACMD__atapi_command: [16] u8;
    RSV1__reserved:      [48] u8;

    PRDT__physical_region_descriptor_table: [1] Ahci_Physical_Region_Descriptor;
}

Ahci_Physical_Region_Descriptor :: struct {
    DBA__data_base_address: u64;
    _: u32;
    DBC__data_byte_count: u16;

// #place DBC__data_byte_count;
    I__interrupt_on_completion: enum u16 { NO; YES :: 0x8000; };
}

Fis_Type :: enum u8 {
    INVALID      :: 0x0;
    REGISTER_H2D :: 0x27;
    REGISTER_D2H :: 0x34;
    DMA_ACTIVATE :: 0x39;
    DMA_SETUP    :: 0x41;
    DATA         :: 0x46;
    BIST         :: 0x58;
    PIO_SETUP    :: 0x5f;
    DEV_BITS     :: 0xa1;
}

Ahci_Received_Fis :: struct {
    DSFIS__dma_setup: [32] u8;
    PSFIS__pio_setup: [32] u8;
    RFIS__d2h_register: Ahci_Command_Fis = .{ fis_type = .REGISTER_D2H };
    SDBFIS__set_device_bits: u64;
    UFIS__unknown: [64] u8;

    reserved: [96] u8;
}

Ahci_Command_Fis :: struct {
    fis_type := Fis_Type.REGISTER_H2D;
    flags: enum u8 { NONE :: 0x0; IS_COMMAND :: 0x80; };
    command: Ata_Command;
    features0: u8;

    lba_0: u8;
    lba_1: u8;
    lba_2: u8;
    device: u8;

    lba_3: u8;
    lba_4: u8;
    lba_5: u8;
    features1: u8;

    sectors_low: u8;
    sectors_high: u8;
    icc: u8;
    control: u8;

    reserved: u32;
}

Ahci_Memory_Region :: struct {
    CAP__host_capabilities:            HBA_CAP__Ahci_Capabilities;
    GHC__global_host_control:          HBA_GHC__Ahci_Global_Host_Control;
    IS__interrupt_status:              u32;
    PI__ports_implemented:             u32;
    VS__version:                       u32;
    CCC_CTL__cmd_coalescing_control:   u32;
    CCC_PTS__cmd_coalescing_ports:     u32;
    EM_LOC__enclosure_mgmt_location:   u32;
    EM_CTL__enclosure_mgmt_control:    u32;
    CAP2__extended_host_capabilities:  u32;
    BOHC__bios_handoff_control:        u32;

    reserved:                          [116] u8;
    vendor_specific:                   [96] u8;

    ports:                             [32] Ahci_Port;
}

Ahci_Port :: struct {
    CLB__command_list_base:    u64 #align 4;
    FB__fis_base:              u64 #align 4;
    IS__interrupt_status:      u32;
    IE__interrupt_enable:      u32;
    CMD__command_status:       HBA_PxCMD__Ahci_Port_Command_Status;
    RSV0__reserved:            u32;
    TFD__task_file_data:       u32;
    SIG__signature:            HBA_PxSIG__Ahci_Port_Signature;
    SSTS__sata_status:         HBA_PxSSTS__Ahci_Port_Status;
    SCTL__sata_control:        u32;
    SERR__sata_error:          u32;
    SACT__sata_active:         u32;
    CI__command_issue:         u32;
    SNTF__sata_notif:          u32;
    FBS__fis_based_switching:  u32;
    DEVSLP__device_sleep:      u32;

    RSV1__reserved:            [40] u8;
    vendor_specific:           [16] u8;
}

#assert size_of(Ahci_Received_Fis)     == 0x100;
#assert size_of(Ahci_Command_Header)   == 0x20;
#assert size_of(Ahci_Command_Table)    == 0x80 + size_of(Ahci_Physical_Region_Descriptor);
#assert size_of(Ahci_Port)             == 0x80;

HBA_GHC__Ahci_Global_Host_Control :: enum_flags u32 {
    HR__hba_reset                      :: 0x1;
    IE__interrupt_enable               :: 0x2;
    MRSM__msi_revert_to_single_message :: 0x4;
    AE__ahci_enable                    :: 0x8000_0000;
}

HBA_CAP__Ahci_Capabilities :: enum_flags u32 {
    SAM__supports_ahci_only :: 0x4_0000;
    S64A__64bit_addressing  :: 0x8000_0000;
}

HBA_PxSSTS__Ahci_Port_Status :: enum u32 {
    DET_ESTABLISHED :: 0x3;
    IPM_ACTIVE      :: 0x100;

    DET_MASK   :: 0b0000_0000_1111;
    SPD_MASK   :: 0b0000_1111_0000;
    IPM_MASK   :: 0b1111_0000_0000;
}

HBA_PxCMD__Ahci_Port_Command_Status :: enum_flags u32 {
    ST__start                 :: 0x1;
    SUD__spin_up_device       :: 0x2;
    FRE__fis_receive_enable   :: 0x10;
    FR__receive_running       :: 0x4000;
    CR__command_list_running  :: 0x8000;
}

HBA_PxSIG__Ahci_Port_Signature :: enum u32 {
    ATA   :: 0x0000_0101;
    ATAPI :: 0xeb14_0101;
    SEMB  :: 0xc33c_0101;
    PM    :: 0x9669_0101;
}



High_Definition_Audio :: struct {
    using mmio: *Intel_HDA_Memory_Region;

    // Measured in commands not bytes.
    corb_size: int;
    rirb_size: int;

    corb: *[256]HDA_Codec_Verb;
}

Intel_HDA_Memory_Region :: struct {
    start: void;

    GCAP: u16;
    VMIN: u8;
    VMAJ: u8;
    OUTPAY: u16;
    INPAY:  u16;

    GCTL__global_control: HDA_GCTL__Global_Control;
    WAKEEN: u16;
    STATESTS__state_change_status: u16;
    GSTS: u16;

    OUTSTRMPAY: u16 #align 8;
    INSTRMPAY:  u16;

    overlay_space: [0x100] u8;

    #overlay(start) using _: struct {
        _: [0x40] u8;

        CORBLBASE__corb_lower_base: u32;
        CORBUBASE__corb_upper_base: u32;

        CORBWP__corb_write_pointer: u16;
        CORBRP__corb_read_pointer: u16;
        CORBCTL__corb_control: enum_flags u8 {
            CMEIE   :: 1;
            CORBRUN :: 2;
        };

        CORBSTS__corb_status: u8;
        CORBSIZE__corb_size: HDA_RB_Size;
    }

    #overlay(start) using _: struct {
        _: [0x50] u8;

        RIRBBLBASE__rirb_lower_base: u32;
        RIRBBUBASE__rirb_upper_base: u32;

        RIRBWP__rirb_write_pointer: u16;
        RINTCNT__interrupt_count: u16;
        RIRBCTL__rirb_control: u8;
        RIRBSTS__rirb_status: u8;
        RIRBSIZE__rirb_size: HDA_RB_Size;
    }
}

HDA_RB_Size :: enum u8 {
    RBSIZE  :: 2;
    _       :: 2;
    RBSZCAP :: 4;
};

HDA_GCTL__Global_Control :: enum u32 {
    CRST__controller_reset :: 1;
    FCNTRL__flush_control  :: 1;
    _                      :: 6;
    UNSOL                  :: 8;
    _                      :: 16;
}

HDA_Codec_Verb :: enum u32 {
    payload       :: 20;
    node_id       :: 8;
    codec_address :: 4;
}

init_high_definition_audio_controller :: (device: *Pci_Device) {
    log_category("HDA");

    log("Found an INTEL HDA audio device");

    hda: High_Definition_Audio;

    bar0 := read_base_address_register(device, 0);
    hda.mmio = cast(*Intel_HDA_Memory_Region)map_base_address_register(bar0);

    {
        // Reset controller.

        set_bit(*hda.GCTL__global_control, .CRST__controller_reset);
        barrier();

        if Timeout(get_bit(*hda.GCTL__global_control, .CRST__controller_reset)) {
            log_error("Failed to reset (CRST remains low).");
            return;
        }

        busy_wait(521);
    }

    // Detect active codecs.

    statests := hda.STATESTS__state_change_status;
    bits := formatInt(statests, base=2);
    log("Active codecs: %", bits);

    ringbuffer_memory := get_4k_page(); // Todo: ensure this is low (sub-4Gb) memory. We will need some reserved physical memory for that purpose.
    assert(ringbuffer_memory < 0x1_0000_0000);

    {
        // Set up Command Output Ring Buffer (CORB).

        hda.CORBCTL__corb_control &= ~.CORBRUN;
        if Timeout(hda.CORBCTL__corb_control & .CORBRUN) {
            log_error("Failed to stop CORB.");
            return;
        }

        corbszcap := get(hda.CORBSIZE__corb_size, .RBSZCAP);
        if corbszcap & 0b0100 == 0 {
            log_error("Large output buffer size is not supported by the device. Todo.");
            return;
        }
        set(*hda.CORBSIZE__corb_size, .RBSIZE, 0b10);

        hda.CORBRP__corb_read_pointer |= 1 << 15;
        hda.CORBWP__corb_write_pointer &= 0xff_00;

        hda.corb_size = 256;

        hda.CORBLBASE__corb_lower_base = cast(u32)ringbuffer_memory;
        hda.CORBUBASE__corb_upper_base = 0;

        hda.CORBCTL__corb_control |= .CORBRUN;
    }
}

hda_submit_command :: (hda: *High_Definition_Audio, verb: HDA_Codec_Verb) -> enum {success; buffer_full;} {
    rp := cast(int) hda.CORBRP__corb_read_pointer & 0xff;
    wp := cast(int) hda.CORBWP__corb_write_pointer & 0xff;

    wp = (wp + 1) % hda.corb_size;
    if wp == rp {
        return .buffer_full;
    }

    // hda.corb[wp] = verb;
    // hda.CORBWP__corb_write_pointer = cast(u16) next_wp;

    // ...

    return .success;
}



Pci_Class :: enum u8 {
    UNCLASSIFIED             :: 0x0;
    MASS_STORAGE             :: 0x1;
    NETWORK                  :: 0x2;
    DISPLAY_DEVICE           :: 0x3;
    MULTIMEDIA               :: 0x4;
    MEMORY_CONTROLLER        :: 0x5;
    BRIDGE                   :: 0x6;
    COMMUNICATION            :: 0x7;
    SYSTEM_PERIPHERAL        :: 0x8;
    INPUT_DEVICE             :: 0x9;
    DOCKING_STATION          :: 0xa;
    PROCESSOR                :: 0xb;
    SERIAL_BUS               :: 0xc;
    WIRELESS_CONTROLLER      :: 0xd;
}

Pci_Command :: enum_flags u16 {
    IO_SPACE                    :: 1 << 0;
    MEMORY_SPACE                :: 1 << 1;
    BUS_MASTER                  :: 1 << 2;
    SPECIAL_CYCLES              :: 1 << 3;
    MEMORY_WRITE_AND_INVALIDATE :: 1 << 4;
    VGA_PALETTE_SNOOP           :: 1 << 5;
    PARITY_ERROR_RESPONSE       :: 1 << 6;
    S_ERR_ENABLE                :: 1 << 8;
    FAST_BACK_TO_BACK_ENABLE    :: 1 << 9;
    INTERRUPT_DISABLE           :: 1 << 10;
}

PCI_SUBCLASSES :: ([] string).[
    .[
        "Non VGA Compatible Unclassified",
        "VGA Compatible Unclassified"
    ],
    .[
        "SCSI Bus Controller",
        "IDE Controller",
        "Floppy Disk Controller",
        "IPI Bus Controller",
        "RAID Controller",
        "ATA Controller",
        "Serial ATA Controller",
        "Serial Attached SCSI Controller",
        "Non-Volatile Memory Controller",
    ],
    .[
        "Ethernet Controller",
        "Token Ring Controller",
        "FFDI Controller",
        "ATM Controller",
        "ISDN Controller",
        "WorldFip Controller",
        "PICMG 2.14 Multi Computing Controller",
        "Infiniband Controller",
        "Fabric Controller",
    ],
    .[
        "VGA Compatible Controller",
        "XGA Controller",
        "3D Controller",
    ],
    .[
        "Multimedia Video Controller",
        "Multimedia Audio Controller",
        "Computer Telephony Device",
        "Audio Device",
    ],
    .[
        "RAM Controller",
        "Flash Controller",
    ],
    .[
        "Host Bridge",
        "ISA Bridge",
        "EISA Bridge",
        "MCA Bridge",
        "PCI-to-PCI Bridge",
        "PCMCIA Bridge",
        "NuBus Bridge",
        "CardBus Bridge",
        "RACEway Bridge",
        "PCI-to-PCI Bridge (Semi Transparent)",
        "InfiniBand-to-PCI Host Bridge",
    ],
    .[
        "Serial Controller",
        "Parallel Controller",
        "Multiport Serial Controller",
        "Modem",
        "IEEE 488.1/2 (GPIB) Controller",
        "Smart Card Controller",
    ],
    .[
        "Programmable Interrupt Controller",
        "DMA Controller",
        "Timer",
        "RTC Controller",
        "PCI Hot-Plug Controller",
        "SD Host Controller",
        "IOMMU",
    ],
    .[
        "Keyboard Controller",
        "Digitizer Pen",
        "Mouse Controller",
        "Scanner Controller",
        "Gameport Controller",
    ],
    .[
        "Generic",
    ],
    .[
        "386 Processor",
        "486 Processor",
        "Pentium",
        "Pentium Pro",
    ],
    .[
        "FireWire (IEEE 1394) Controller",
        "ACCESS Bus Controller",
        "SSA",
        "USB Controller",
        "Fibre Channel",
        "SMBus Controller",
        "InfiniBand Controller",
        "IPMI Interface",
        "SERCOS Interface (IEC 61491)",
        "CANbus Controller",
    ],
    .[
        "iRDA Compatible Controller",
        "Consumer IR Controller",
        "RF Controller",
        "Bluetooth Controller",
        "Broadband Controller",
        "Ethernet Controller (802.1a)",
        "Ethernet Controller (802.1b)",
    ],
    .[
        "I20",
    ],
    .[
        "Satellite TV Controller",
        "Satellite Audio Controller",
        "Satellite Voice Controller",
        "Satellite Data Controller",
    ],
    .[
        "Network and Computing Encryption/Decryption",
    ],
    .[
        "DPIO Modules",
        "Performance Counters",
    ],
];

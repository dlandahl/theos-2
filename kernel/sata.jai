
Sata_Controller :: struct {
    command_list:  []    Sata_Command_Header;
    command_table: [32] *Sata_Command_Table;

    received_fis: *Sata_Received_Fis;
    port:         *Sata_Port;
    mmio:         *Sata_Memory_Region;

    initialized: bool;
}

#program_export
sata_interrupt :: (data: *void) #c_call {
    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);
} @InterruptRoutine

init_sata_controller :: (device: *Pci_Device) -> c: *Sata_Controller = null, success: bool {
    log_category("SATA");

    device.command |= .BUS_MASTER | .MEMORY_SPACE;
    device.command &= ~.INTERRUPT_DISABLE;

    parse_pci_capability_list(device);
    enable_msi_or_msi_x(device, isr__sata_interrupt);

    bar := read_base_address_register(device, bar_index = 5);
    if !bar.base {
        log_error("Controller has no base address set");
        return success = false;
    }

    sata := cast(*Sata_Memory_Region) map_base_address_register(bar);

    sata.GHC__global_host_control |= .AE__sata_enable | .IE__interrupt_enable;

    if !(sata.CAP__host_capabilities & .S64A__64bit_addressing) {
        log_error("Controller without 64-bit addressing not supported");
        return success = false;
    }

    if !(sata.CAP__host_capabilities & .SAM__supports_sata_only) {
        sata.GHC__global_host_control |= .HR__hba_reset;
    }

    // Todo bitfield
    num_ports          := cast(int,  sata.CAP__host_capabilities       & 0b11111) + 1;
    command_slot_count := cast(int, (sata.CAP__host_capabilities >> 8) & 0b11111) + 1;

    max_ports := 32;

    for 0..max_ports-1 {
        if !(sata.PI__ports_implemented & (1 << it)) {
            continue;
        }

        port := *sata.ports[it];

        if sata_port_is_running(port) {
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
        if !(sata.PI__ports_implemented & (1 << it)) continue;

        port := *sata.ports[it];
        if !(port.CMD__command_status & .SUD__spin_up_device) {
            log_error("Port not spun up");
            return success = false;
        }

        // if sata.CAP__host_capabilities & .STAGGERED_SPIN_UP {
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

        list_size := align(4096, size_of(Sata_Command_Header) * command_slot_count);
        fis_size  := align(4096, size_of(Sata_Received_Fis));

        // Todo: Make this easier to understand.
        memory_needed := list_size + fis_size + command_slot_count * 4096 + 4096;

        virtual  := cast(*void) alloc_block(*global.virtual_block_allocator, cast(u64) memory_needed);
        _, physical := allocate_page_aligned_physical_memory(memory_needed);

        pages_needed := cast(int) memory_needed / 4096;
        map_pages(virtual, physical, pages_needed, .READ_WRITE | .PRESENT | .CACHE_DISABLE);

        controller := New(Sata_Controller,, global.small_objects);
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

        controller.mmio = sata;
        controller.initialized = true;
        return controller, true;
    }

    log_error("No active port found.");
    return success = false;
}

sata_port_is_running :: (port: *Sata_Port) -> bool {
    return (port.CMD__command_status & .ST__start)
        || (port.CMD__command_status & .CR__command_list_running)
        || (port.CMD__command_status & .FRE__fis_receive_enable)
        || (port.CMD__command_status & .FR__receive_running);
}



sata_transfer :: (device: *void, request: Transfer_Request) {
    log_category("SATA");

    controller := cast(*Sata_Controller) device;
    assert(controller.initialized);

    memory_address := request.physical_memory_address;

    assert(cast(u64) memory_address % 0x200 == 0);

    sector_count := cast(u64) request.count_lba;
    lba          := cast(u64) request.start_lba;

    assert(sector_count != 0);

    first_sector_count := (0x1_0000 - memory_address % 0x1_0000) / 0x200;
    if first_sector_count > sector_count first_sector_count = sector_count;
    sector_count -= first_sector_count;

    sata_transfer_sectors(controller, request.direction, memory_address, lba, xx first_sector_count);

    lba            += first_sector_count;
    memory_address += first_sector_count * 0x200;

    while sector_count > 128 {
        sata_transfer_sectors(controller, request.direction, memory_address, lba, 128);

        memory_address += 0x1_0000;
        lba            += 128;
        sector_count   -= 128;
    }

    if sector_count {
        sata_transfer_sectors(controller, request.direction, memory_address, lba, xx sector_count);
    }

    if request.semaphore {
        signal(request.semaphore);
    }
}

sata_transfer_sectors :: (controller: *Sata_Controller, direction: type_of(Transfer_Request.direction), physical: u64, lba: u64, sector_count: int) {
    log_category("SATA");

    assert(controller.initialized);

    fis: Sata_Command_Fis;
    fis.flags = .IS_COMMAND;
    fis.command = ifx direction == .READ then Ata_Command.READ_DMA_EX else .WRITE_DMA_EX;
    fis.device = 1 << 6; // Todo magic number

    fis.sectors_low  = cast(u8) (sector_count);
    fis.sectors_high = cast(u8) (sector_count >> 8);

    fis.lba_0 = cast(u8) (lba      ) & 0xff;
    fis.lba_1 = cast(u8) (lba >> 8 ) & 0xff;
    fis.lba_2 = cast(u8) (lba >> 16) & 0xff;
    fis.lba_3 = cast(u8) (lba >> 24) & 0xff;
    fis.lba_4 = cast(u8) (lba >> 32) & 0xff;
    fis.lba_5 = cast(u8) (lba >> 40) & 0xff;

    table := controller.command_table[0];
    table.CFIS__command_fis = fis;

    controller.command_list[0].PRDTL__prd_table_length = 1;
    controller.command_list[0].PRDBC__prd_byte_count = 0;
    controller.command_list[0].flags = size_of(Sata_Command_Fis) / 4;

    if direction == .WRITE {
        controller.command_list[0].flags |= .WRITE;
    }

    prdt := *table.PRDT__physical_region_descriptor_table[0];
    prdt.DBA__data_base_address = physical;
    prdt.DBC__data_byte_count = cast(u16) (sector_count * 0x200 - 1);
    prdt.I__interrupt_on_completion = .YES;

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

    memory_fence();
    assert(!(controller.port.CI__command_issue & 1));
    controller.port.CI__command_issue |= 1;

    if Timeout(!(controller.port.CI__command_issue & 1)) {
        log_error("SATA command issue timeout");
    }
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

Sata_Command_Header :: struct {
    flags: enum u16 {
        WRITE :: 0x40;
    }

    PRDTL__prd_table_length: u16;
    PRDBC__prd_byte_count: u32;
    CTBA__command_table_base: u64;
    
    reserved: [4] u32;
}

Sata_Command_Table :: struct {
    CFIS__command_fis:   Sata_Command_Fis;
    RSV0__reserved:      [44] u8;
    ACMD__atapi_command: [16] u8;
    RSV1__reserved:      [48] u8;

    PRDT__physical_region_descriptor_table: [1] Sata_Physical_Region_Descriptor;
}

Sata_Physical_Region_Descriptor :: struct {
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

Sata_Received_Fis :: struct {
    DSFIS__dma_setup: [32] u8;
    PSFIS__pio_setup: [32] u8;
    RFIS__d2h_register: Sata_Command_Fis = .{ fis_type = .REGISTER_D2H };
    SDBFIS__set_device_bits: u64;
    UFIS__unknown: [64] u8;

    reserved: [96] u8;
}

Sata_Command_Fis :: struct {
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

Sata_Memory_Region :: struct {
    CAP__host_capabilities:            HBA_CAP__Sata_Capabilities;
    GHC__global_host_control:          HBA_GHC__Sata_Global_Host_Control;
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

    ports:                             [32] Sata_Port;
}

Sata_Port :: struct {
    CLB__command_list_base:    u64 #align 4;
    FB__fis_base:              u64 #align 4;
    IS__interrupt_status:      u32;
    IE__interrupt_enable:      u32;
    CMD__command_status:       HBA_PxCMD__Sata_Port_Command_Status;
    RSV0__reserved:            u32;
    TFD__task_file_data:       u32;
    SIG__signature:            HBA_PxSIG__Sata_Port_Signature;
    SSTS__sata_status:         HBA_PxSSTS__Sata_Port_Status;
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

#assert size_of(Sata_Received_Fis)     == 0x100;
#assert size_of(Sata_Command_Header)   == 0x20;
#assert size_of(Sata_Command_Table)    == 0x80 + size_of(Sata_Physical_Region_Descriptor);
#assert size_of(Sata_Port)             == 0x80;

HBA_GHC__Sata_Global_Host_Control :: enum_flags u32 {
    HR__hba_reset                      :: 0x1;
    IE__interrupt_enable               :: 0x2;
    MRSM__msi_revert_to_single_message :: 0x4;
    AE__sata_enable                    :: 0x8000_0000;
}

HBA_CAP__Sata_Capabilities :: enum_flags u32 {
    SAM__supports_sata_only :: 0x4_0000;
    S64A__64bit_addressing  :: 0x8000_0000;
}

HBA_PxSSTS__Sata_Port_Status :: enum u32 {
    DET_ESTABLISHED :: 0x3;
    IPM_ACTIVE      :: 0x100;

    DET_MASK   :: 0b0000_0000_1111;
    SPD_MASK   :: 0b0000_1111_0000;
    IPM_MASK   :: 0b1111_0000_0000;
}

HBA_PxCMD__Sata_Port_Command_Status :: enum_flags u32 {
    ST__start                 :: 0x1;
    SUD__spin_up_device       :: 0x2;
    FRE__fis_receive_enable   :: 0x10;
    FR__receive_running       :: 0x4000;
    CR__command_list_running  :: 0x8000;
}

HBA_PxSIG__Sata_Port_Signature :: enum u32 {
    ATA   :: 0x0000_0101;
    ATAPI :: 0xeb14_0101;
    SEMB  :: 0xc33c_0101;
    PM    :: 0x9669_0101;
}

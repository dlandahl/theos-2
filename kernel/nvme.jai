
#scope_export

Nvme_Controller :: struct {
    using mmio: *Nvme_Property_Memory_Map;

    admin_queue: Nvme_Command_Queue;
    io_queue:    Nvme_Command_Queue;

    identify: *Nvme_Identify_Controller_Structure;

    maximum_transfer_size_in_blocks: int;
    maximum_queue_entries: int;

    // These are properties of the namespace, will need to be moved into a separate struct when we support multiple drives connected to the same controller.
    block_size: int;
    nsid: u32;

    initialized: bool;

    active_transfers: [..] Nvme_Transfer_Metadata;
    metadata_lock: Spinlock;
}

nvme_transfer :: (device_specific: *void, request: Transfer_Request) {
    // One issue with this transfer request API currently is that transfers are contiguous. So the caller might need to use more requests, and therefore semaphores than they want.
    nvme := cast(*Nvme_Controller) device_specific;

    lba_to_native :: (lba: s64) -> s64 #expand {
        ratio := nvme.block_size / 512;
        return lba / ratio;
    }

    first_block  := lba_to_native(request.start_lba);
    block_count  := lba_to_native(request.count_lba);

    max_blocks      := nvme.maximum_transfer_size_in_blocks;

    full_transfers  := block_count / max_blocks;
    remainder       := block_count % max_blocks;


    acquire(*nvme.metadata_lock);
    metadata := array_add(*nvme.active_transfers);

    metadata.prp_pages.allocator = temp;

    metadata.first_command   = nvme.io_queue.next_command_id;
    metadata.total_commands  = full_transfers + cast(int) (remainder > 0);
    metadata.semaphore = request.semaphore;
    release(*nvme.metadata_lock);

    memory_base := cast(*void) request.physical_memory_address + DIRECT_MAPPING_BASE;

    for 0..full_transfers-1 {
        blocks_done := it * max_blocks;

        start_block := first_block + blocks_done;
        memory      := memory_base + blocks_done * nvme.block_size;

        do_single_transfer(nvme, cast(u64) start_block, memory, max_blocks, request.direction, *metadata.prp_pages);
    }

    // Do the final transfer, if the requested transfer size doesn't divide into the max transfer size of the device.

    if remainder {
        start_block := first_block + block_count - remainder;
        memory      := memory_base + block_count * nvme.block_size - remainder * nvme.block_size;

        do_single_transfer(nvme, cast(u64) start_block, memory, max_blocks, request.direction, *metadata.prp_pages);
    }
}

init_nvme_controller :: (device: *Pci_Device) -> Storage_Device {
    log_category("NVMe");

    assert(device.class_code == .MASS_STORAGE);
    assert(device.subclass   == 0x8);

    device.command |= .BUS_MASTER | .MEMORY_SPACE;
    device.command &= ~.INTERRUPT_DISABLE;

    parse_pci_capability_list(device);

    enabled := enable_msi_or_msi_x(device, isr__nvme_interrupt);
    assert(enabled == .MSI_X);

    nvme := New(Nvme_Controller,, global.small_objects);

    bar := read_base_address_register(device, bar_index = 0);
    nvme.mmio = map_base_address_register(bar);

    reset_controller(nvme);

    {
        // Send IDENTIFY command.
        identify_page := get_4k_page();

        admin_command: Nvme_Submission_Queue_Entry;
        admin_command.OPC__opcode = .IDENTIFY;
        admin_command.CNS__controller_or_namespace = .IDENTIFY_CONTROLLER;
        admin_command.DPTR__data_pointer[0] = identify_page;

        send_command_synchronous(*nvme.admin_queue, admin_command);

        nvme.identify = cast(*Nvme_Identify_Controller_Structure) (identify_page + DIRECT_MAPPING_BASE);

        sn := cast(string) nvme.identify.SN__serial_number;
        mn := cast(string) nvme.identify.MN__model_number;
        for sn if it == #char " " { sn.count = it_index; break; }
        for mn if it == #char " " { mn.count = it_index; break; }

        mps_min := get(nvme.CAP__capabilities, .MPSMIN);
        assert(mps_min == 0); // Zero means 4k. Controller should always support 4k memory page size.

        mdts := nvme.identify.MDTS__maximum_data_transfer_size;
        if mdts == 0 {
            // 0 Means no limit.
            nvme.maximum_transfer_size_in_blocks = 0x1000;
        } else {
            nvme.maximum_transfer_size_in_blocks = 1 << nvme.identify.MDTS__maximum_data_transfer_size;
        }

        nvme.maximum_queue_entries = cast(s64) get(nvme.CAP__capabilities, .MQES__maximum_queue_entries);

        log("Found controller with model number '%'. Maximum transfer size % blocks, maximum queue size % entries.", mn, nvme.maximum_transfer_size_in_blocks, nvme.maximum_queue_entries);
    }

    {
        // Get active namespace ID list.
        nsid_page := get_4k_page();

        admin_command: Nvme_Submission_Queue_Entry;
        admin_command.OPC__opcode = .IDENTIFY;
        admin_command.CNS__controller_or_namespace = .ACTIVE_NAMESPACE_ID_LIST;
        admin_command.DPTR__data_pointer[0] = nsid_page;

        send_command_synchronous(*nvme.admin_queue, admin_command);

        nsid_list := cast(*[1024] u32) (nsid_page + DIRECT_MAPPING_BASE);

        for nsid_list.* if it != 0 {
            nvme.nsid = it;
            break;
        }

        if nvme.nsid == 0 {
            log_error("No active namespace ID found");
            bluescreen();
        }

        log("Found NSID %.", nvme.nsid);
        free_4k_page(nsid_page);
    }

    {
        // Identify namespace (drive).

        identify_page := get_4k_page();

        admin_command: Nvme_Submission_Queue_Entry;
        admin_command.OPC__opcode = .IDENTIFY;
        admin_command.CNS__controller_or_namespace = .IDENTIFY_NAMESPACE;
        admin_command.NSID__namespace_id = nvme.nsid;
        admin_command.DPTR__data_pointer[0] = identify_page;

        send_command_synchronous(*nvme.admin_queue, admin_command);
        identify := cast(*Nvme_Identify_Namespace_Structure) (identify_page + DIRECT_MAPPING_BASE);

        index := identify.FLBAS__formatted_lba_size & 0xf;

        lba_format := identify.LBAF__lba_format_support[index];
        nvme.block_size = 1 << lba_format.LBADS__lba_data_size;

        assert(nvme.block_size == 4096 || nvme.block_size == 512, "Todo: Nvme block size % not supported.", nvme.block_size);
    }

    {
        // Create IO queues.

        space_for_queues := allocate_large_page();
        queue_size       := cast(u64) min(0x4000, nvme.maximum_queue_entries+1);

        assert(queue_size * size_of(Nvme_Submission_Queue_Entry) + queue_size * size_of(Nvme_Completion_Queue_Entry) < 0x20_0000);

        io_sq_base := space_for_queues;
        io_cq_base := space_for_queues + queue_size * size_of(Nvme_Submission_Queue_Entry);

        {
            admin_command: Nvme_Submission_Queue_Entry;
            admin_command.OPC__opcode = .CREATE_IO_COMPLETION_QUEUE;
            admin_command.DPTR__data_pointer[0] = io_cq_base;
            admin_command.NSID__namespace_id = nvme.nsid;
            admin_command.QSIZE__queue_size = cast(u16) queue_size-1;
            admin_command.QID__queue_identifier = 1;
            admin_command.flags |= .PC__physically_contiguous;
            admin_command.flags |= .IEN__interrupts_enabled;
            admin_command.IV__interrupt_vector = 1;

            send_command_synchronous(*nvme.admin_queue, admin_command);
        }

        {
            admin_command: Nvme_Submission_Queue_Entry;
            admin_command.OPC__opcode = .CREATE_IO_SUBMISSION_QUEUE;
            admin_command.DPTR__data_pointer[0] = io_sq_base;
            admin_command.NSID__namespace_id = nvme.nsid;
            admin_command.QSIZE__queue_size = cast(u16) queue_size-1;
            admin_command.QID__queue_identifier = 1;
            admin_command.CQID__completion_queue_identifier = 1;
            admin_command.flags |= .PC__physically_contiguous;

            send_command_synchronous(*nvme.admin_queue, admin_command);
        }

        nvme.io_queue.sq.data = xx (io_sq_base + DIRECT_MAPPING_BASE); // Todo: does cache need to be disabled for this memory?
        nvme.io_queue.cq.data = xx (io_cq_base + DIRECT_MAPPING_BASE);

        nvme.io_queue.sq.count = cast(s64) queue_size;
        nvme.io_queue.cq.count = cast(s64) queue_size;

        nvme.io_queue.tail_doorbell = *nvme.doorbell_base + 2 * (4 << get(nvme.CAP__capabilities, .DSTRD__doorbell_stride));
        nvme.io_queue.head_doorbell = *nvme.doorbell_base + 3 * (4 << get(nvme.CAP__capabilities, .DSTRD__doorbell_stride));

        nvme.io_queue.async_completion_enabled = true;
        nvme.io_queue.semaphore.counter_max = 1;
    }

    thread := create_task(completion_thread, name = "NVMe");
    thread.user_data = nvme;
    put_task_on_core(thread, *global.processor_cores[1]);

    sd: Storage_Device;
    sd.data_pointer = nvme;
    sd.transfer = nvme_transfer;

    nvme.initialized = true;
    return sd;
}

nvme_fence :: (using nvme: *Nvme_Controller) {
    spin_drain_queue(*io_queue);
}

#scope_file

Nvme_Command_Queue :: struct {
    tail_doorbell: *u32;
    head_doorbell: *u32;

    sq_tail: u32;
    cq_head: u32;

    sq: [] Nvme_Submission_Queue_Entry;
    cq: [] Nvme_Completion_Queue_Entry;

    current_phase: bool;

    async_completion_enabled: bool;
    semaphore: Semaphore;

    next_command_id: u16;
    last_seen_sqhd:  u16; // Up to this index, submission queue entries are guaranteed to be available for software to write to.
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
    CID__command_identifier: u16;
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

            flags: enum_flags u16 {
                PC__physically_contiguous :: 1;
                IEN__interrupts_enabled   :: 2;
            }

            union {
                CQID__completion_queue_identifier: u16; // For submission queues.
                IV__interrupt_vector: u16;              // For completion queues.
            }
        }

        struct {
            // For IO READ:
            SLBA__starting_lba: u64;
            NLB__number_of_logical_blocks: u16;
        }
    }
}

#assert size_of(Nvme_Submission_Queue_Entry) == 64;

Nvme_Completion_Queue_Entry :: struct {
    DW0: u32;
    DW1: u32;

    SQHD__sq_head_pointer: u16;
    SQID__sq_identifier: u16;

    CID__command_identifier: u16;

    STATUS__status: enum u16 {
        PHASE                    :: 1;
        SC__STATUS_CODE          :: 8;
        SCT__STATUS_CODE_TYPE    :: 3;
        CRD__COMMAND_RETRY_DELAY :: 2;
        M__MORE                  :: 1;
        DNR__DO_NOT_RETRY        :: 1;
    }
}

#assert size_of(Nvme_Completion_Queue_Entry) == 16;

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
    FR__firmware_revision: u64 #align 1;
    RAB__recommended_arbitration_burst: u8;
    IEEE_ieee_oui_identifier: [3]u8;
    CMIC: u8;
    MDTS__maximum_data_transfer_size: u8;
}

Nvme_Identify_Namespace_Structure :: struct {
    start: void;

    NSIZE__size: u64;
    NCAP__capacity: u64;
    NUSE__utilization: u64;
    NSFEAT: u8;
    NLBAF__lba_format_count: u8;
    FLBAS__formatted_lba_size: u8;

    _: [0x100] u8;

    #overlay(start) using _: struct {
        offset: [128] u8;
        LBAF__lba_format_support: [64] Nvme_LBA_Format;
    }
}

Nvme_LBA_Format :: struct {
    MS__metadata_size:    u16;
    LBADS__lba_data_size: u8;

    RP__relative_performance: enum u8 {
        best     :: 0b00;
        better   :: 0b01;
        good     :: 0b10;
        degraded :: 0b11;
    }
}

#assert size_of(Nvme_Identify_Controller_Structure) == 78;

reset_controller :: (nvme: *Nvme_Controller) {
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

    {
        // Initialize admin queues.

        admin_sq := get_4k_page();
        admin_cq := get_4k_page();

        depth := 4096 / cast(u16) max(
            size_of(Nvme_Submission_Queue_Entry),
            size_of(Nvme_Completion_Queue_Entry)
        );

        assert(depth == 64);

        nvme.AQA__admin_queue_attributes = .{
            // Subtract one, because the field is zero based.
            depth-1, depth-1 // Todo: Hardcoded.
        };

        nvme.ASQ__admin_sq = admin_sq;
        nvme.ACQ__admin_cq = admin_cq;

        nvme.admin_queue.sq.data = cast(*Nvme_Submission_Queue_Entry) (admin_sq + DIRECT_MAPPING_BASE);
        nvme.admin_queue.cq.data = cast(*Nvme_Completion_Queue_Entry) (admin_cq + DIRECT_MAPPING_BASE);

        nvme.admin_queue.sq.count = depth;
        nvme.admin_queue.cq.count = depth;

        nvme.admin_queue.tail_doorbell = *nvme.SQ0TDBL__submission_queue_0_tail_doorbell;
        nvme.admin_queue.head_doorbell = *nvme.CQ0HDBL__completion_queue_0_head_doorbell;

        nvme.admin_queue.async_completion_enabled = true;
    }

    {
        // Initialize config register.

        config  := nvme.CC__controller_config;
        caps    := nvme.CAP__capabilities;

        NOIOCSS := get(caps, .NOIOCSS__no_io_command_set_support);
        IOCSS   := get(caps, .IOCSS__io_command_set_support);
        NCSS    := get(caps, .NCSS__nvm_command_set_support);

        if NOIOCSS         set(*config, .CSS__io_command_set, 0b111);
        if IOCSS           set(*config, .CSS__io_command_set, 0b110);
        if !IOCSS && NCSS  set(*config, .CSS__io_command_set, 0b000);

        set(*config, .AMS__arbitration_mechanism, 0);
        set(*config, .MPS__memory_page_size, 0);

        // Todo, detect these values
        set(*config, .IOSQES__io_submission_entry_size, 6);
        set(*config, .IOCQES__io_completion_entry_size, 4);

        set(*config, .EN__enable, 1);

        nvme.CC__controller_config = config;
    }

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

enqueue_command :: (using queue: *Nvme_Command_Queue, command: Nvme_Submission_Queue_Entry) {
    trace(.nvme_enqueue, sq_tail, queue.next_command_id);

    #no_aoc {
        while (sq_tail == queue.last_seen_sqhd - 1) || (sq_tail == 0 && queue.last_seen_sqhd == sq.count-1) {
            pause(); // Todo: This blocks the thread that made the transfer request. Really we should enqueue commands on the "completion_thread" to prevent this.
        }
    }

    sq[sq_tail] = command;
    sq[sq_tail].CID__command_identifier = queue.next_command_id;

    #no_aoc {
        queue.next_command_id += 1;
    }

    sq_tail += 1;
    sq_tail %= cast(u32)sq.count;

    memory_fence();
    tail_doorbell.* = sq_tail;
}

begin_dequeueing_command :: (using queue: *Nvme_Command_Queue) -> *Nvme_Completion_Queue_Entry {

    cqe := *cq[cq_head];

    if get_bit(cqe.STATUS__status, .PHASE) == queue.current_phase {
        // This command has not finished yet.
        return null;
    }

    queue.last_seen_sqhd = cqe.SQHD__sq_head_pointer;

    return cqe;
}

finish_dequeueing_command :: (using queue: *Nvme_Command_Queue) {
    cq_head += 1;

    if cq_head == cq.count {
        cq_head = 0;
        current_phase = !current_phase;
    }

    memory_fence();
    head_doorbell.* = cq_head;
}

report_errors :: (cqe: *Nvme_Completion_Queue_Entry) {
    status := cqe.STATUS__status;

    clear_bit(*status, .PHASE);

    if status != 0 {
        trace(.nvme_failure, cqe.CID__command_identifier);

        ps := push_print_style();
        ps.use_newlines_if_long_form = true;
        ps.base = 16;

        s := to_string(status,, temp);
        log_error("Command failed with status: %", s);
    } else {
        trace(.nvme_success, cqe.CID__command_identifier);
    }
}

spin_drain_queue :: (using queue: *Nvme_Command_Queue) {
    // Calling this only works if interrupts are enabled, and the queue is configured to get consumed by the interrupts.

    assert(get_rflags() & .IF__interrupt > 0);
    assert(queue.async_completion_enabled);

    while cq_head != sq_tail {
        #asm { pause; }
    }
}

send_command_synchronous :: (using queue: *Nvme_Command_Queue, command: Nvme_Submission_Queue_Entry) {
    log_category("NVMe");

    spin_drain_queue(queue); // Wait for commands that will be asynchronously dequeued by interrupts.
    queue.async_completion_enabled = false;

    enqueue_command(queue, command);

    command_has_been_processed :: #code get_bit(cq[cq_head].STATUS__status, .PHASE) != queue.current_phase;
    assert(!Timeout(command_has_been_processed));

    completed := begin_dequeueing_command(queue);
    assert(completed != null);

    report_errors(completed);

    finish_dequeueing_command(queue);

    queue.async_completion_enabled = true;
}



Nvme_Transfer_Metadata :: struct {
    prp_pages: [..] u64;
    semaphore: *Semaphore;

    first_command:       int;
    total_commands:      int;
    completed_commands:  int;
}

#program_export
nvme_interrupt :: (stack: *void) #c_call {
    push_context,defer_pop;

    controller := global.nvme;

    if controller && controller.initialized {
        queue := *controller.io_queue;

        if queue.async_completion_enabled {
            signal(*queue.semaphore);
        }
    }

    write_apic_register(.EOI__END_OF_INTERRUPT, 0x0);
} @InterruptRoutine

completion_thread :: () {
    log_category("NVMe");

    task        := get_current_task();
    controller  := cast(*Nvme_Controller) task.user_data;

    while true {
        wait_for(*controller.io_queue.semaphore);

        while true {
            completed := begin_dequeueing_command(*controller.io_queue);

            if completed == null {
                break;
            }

            report_errors(completed);

            found_metadata := false;
            acquire(*controller.metadata_lock);

            cid := completed.CID__command_identifier;

            for *controller.active_transfers {

                last_command := it.first_command + it.total_commands;
                last_command %= 0xffff;

                if last_command > it.first_command {
                    if !(it.first_command <= cid && cid < last_command) continue;
                } else {
                    if !(it.first_command <= cid || cid < last_command) continue;
                }

                found_metadata = true;

                it.completed_commands += 1;

                if it.completed_commands == it.total_commands {
                    if it.semaphore {
                        signal(it.semaphore);
                    }

                    for it.prp_pages {
                        free_4k_page(it);
                    }

                    array_free(it.prp_pages);
                    remove it;
                }

                break;
            }

            release(*controller.metadata_lock);
            assert(found_metadata, "Completion queue entry not associated with any transfer metadata.");

            finish_dequeueing_command(*controller.io_queue);
        }
    }
}

do_single_transfer :: (using nvme: *Nvme_Controller, starting_disk_block: u64, memory_buffer: *void, number_of_blocks: int, direction: type_of(Transfer_Request.direction), pages_allocated: *[..] u64) {

    assert(number_of_blocks <= maximum_transfer_size_in_blocks, "NVMe transfer exceeds maximum transfer size.");

    command: Nvme_Submission_Queue_Entry;
    command.OPC__opcode = ifx direction == .READ then .READ else .WRITE;

    // Fill in PRP (physical region page) list. Todo: This code is too hard to read.

    number_of_bytes := number_of_blocks * nvme.block_size;

    offset_in_page  := cast(s64) memory_buffer & 0xfff;
    number_of_pages := (number_of_bytes + offset_in_page + 4095) / 4096;

    first_page := get_physical_address(memory_buffer);

    assert(first_page & 0b11 == 0);
    command.DPTR__data_pointer[0] = first_page;

    if number_of_pages == 2 {
        second_page := get_physical_address(memory_buffer + 4096);
        second_page &= ~0xfff;

        command.DPTR__data_pointer[1] = second_page;
    } else if number_of_pages > 2 {
        page_index := 1;

        next_prp_list_phys_base := get_4k_page();
        array_add(pages_allocated, next_prp_list_phys_base);

        prp_list := cast(*u64) (next_prp_list_phys_base + DIRECT_MAPPING_BASE);

        command.DPTR__data_pointer[1] = next_prp_list_phys_base;

        while page_index < number_of_pages {

            remaining_pages   := number_of_pages - page_index;
            is_final_prp_list := remaining_pages <= 512;

            current_prp_list_length := min(remaining_pages, ifx is_final_prp_list then 512 else 511);

            for 0..current_prp_list_length-1 {
                page := get_physical_address(memory_buffer + 4096 * page_index);
                page &= ~0xfff;

                prp_list[it] = page;

                page_index += 1;
            }

            if !is_final_prp_list {
                next_prp_list_phys_base = get_4k_page();
                array_add(pages_allocated, next_prp_list_phys_base);

                prp_list[511] = next_prp_list_phys_base;
                prp_list = cast(*u64) (next_prp_list_phys_base + DIRECT_MAPPING_BASE);
            }
        }
    }

    command.NSID__namespace_id = nvme.nsid;
    command.SLBA__starting_lba = starting_disk_block;
    command.NLB__number_of_logical_blocks = cast(u16) number_of_blocks - 1;

    enqueue_command(*nvme.io_queue, command);
}

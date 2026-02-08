
X64_Flags :: enum_flags u64 {
    CF__carry     :: 0x1;
    PF__parity    :: 0x4;
    AF__adjust    :: 0x10;
    ZF__zero      :: 0x40;
    SF__sign      :: 0x80;
    TF__trap      :: 0x100;
    IF__interrupt :: 0x200;
    DF__direction :: 0x400;
    OF__overflow  :: 0x800;
    RF__resume    :: 0x10000;
}

General_Registers :: struct {
    // The stack layout resulting from the push_all assembly macro.

    r15:  u64;
    r14:  u64;
    r13:  u64;
    r12:  u64;
    r11:  u64;
    r10:  u64;
    r9:   u64;
    r8:   u64;
    rbp:  u64;
    rdi:  u64;
    rsi:  u64;
    rdx:  u64;
    rcx:  u64;
    rbx:  u64;
    rax:  u64;
}

Syscall_Stack_Frame :: General_Registers;

Interrupt_Stack_Frame :: struct (with_error_code := false) {
    using registers: General_Registers;

    Architectural_Part :: struct {
        #if with_error_code {
            error_code: u64;
        }

        ip:    *void;
        cs:    Segment_Selector #align 8;
        flags: X64_Flags;
        sp:    *void;
        ss:    Segment_Selector #align 8;
    }

    using arch: Architectural_Part;
}

Gate_Descriptor_Flags :: enum u8 {
    gate_type             :: 4;
    reserved              :: 1;
    protection_level      :: 2;
    present               :: 1;
} @Bitfield

Interrupt_Gate_Descriptor :: struct {
    offset_1: u16;
    segment:  Segment_Selector;
    ist:      u8;
    flags:    Gate_Descriptor_Flags;
    offset_2: u16;
    offset_3: u32;
    reserved: u32;
}

register_interrupt_gate :: (handler: () #c_call, index: int, trap := false, ist: u8 = 0) {
    desc := *global.interrupt_descriptor_table[index];
    desc.* = .{};

    address := cast(u64) cast(*void) handler;
    desc.offset_1 = xx  address        & 0xffff;
    desc.offset_2 = xx (address >> 16) & 0xffff;
    desc.offset_3 = xx (address >> 32) & 0xffffffff;

    desc.segment  = .RING0_CODE;

    set(*desc.flags, .protection_level, 3);
    set(*desc.flags, .present, 1);
    set(*desc.flags, .gate_type, ifx trap 0b1111 else 0b1110);

    desc.ist = ist;
}

Global_Descriptor_Table :: struct {
    null_entry: u64;
    ring0_code: Gdt_Entry;
    ring0_data: Gdt_Entry;
    ring3_data: Gdt_Entry;
    ring3_code: Gdt_Entry;
    task_state: System_Segment_Descriptor;
    terminator: u64;
}

Segment_Selector :: enum u16 {
    RING0_CODE :: 0x08;
    RING0_DATA :: 0x10;
    RING3_DATA :: 0x18|3;
    RING3_CODE :: 0x20|3;
}

Gdt_Entry :: enum u64 {
    AVAILABLE       :: 0x01 << 52;
    LONG_MODE_CODE  :: 0x02 << 52;
    SIZE            :: 0x04 << 52;
    GRANULARITY     :: 0x08 << 52;
    ACCESSED        :: 0x01 << 40;
    READ_WRITE      :: 0x02 << 40;
    DIRECTION       :: 0x04 << 40;
    EXECUTABLE      :: 0x08 << 40;
    DESCRIPTOR_TYPE :: 0x10 << 40;
    PRIVILEGE0      :: 0x20 << 40;
    PRIVILEGE1      :: 0x40 << 40;
    PRESENT         :: 0x80 << 40;
}

Task_State_Segment :: struct {
    reserved_0: u32;
    rsp:        [3] *void #align 4;
    reserved_1: [2] u32;
    ist:        [7] u64 #align 4;
    reserved_2: [2] u32;
    reserved_3: u16;
    iopb:       u16;
}

Tss_With_Iopb :: struct {
    using tss: Task_State_Segment;
    bitmap: [8192] u8;
}

System_Segment_Descriptor :: struct {
    segment_limit:  u16;
    base_address_0: u16;
    base_address_1: u8;
    flags_0:        u8;
    flags_1:        u8;
    base_address_2: u8;
    base_address_3: u32;
    reserved:       u32;
}



Ia32_Model_Specific_Register :: enum {
    APIC_BASE                 :: 0x0000_001b;
    PAT__page_attribute_table :: 0x0000_0277;
    TSC_DEADLINE              :: 0x0000_06e0;
    EFER__extended_features   :: 0xc000_0080;
    STAR__syscall_segment     :: 0xc000_0081;
    LSTAR__syscall_address    :: 0xc000_0082;
    SFMASK__syscall_flags     :: 0xc000_0084;
    GS_BASE                   :: 0xc000_0101;
}

write_msr :: (msr: Ia32_Model_Specific_Register, value: u64) #no_context {
    high := value >> 32;
    low := value & 0xffff_ffff;

    #asm {
        msr === c;
        high === d;
        low  === a;

        wrmsr high, low, msr;
    }
}

read_msr :: (msr: Ia32_Model_Specific_Register) -> u64 #no_context {
    low: u64;
    high: u64;

    #asm {
        msr === c;
        high === d;
        low === a;

        rdmsr high, low, msr;
    }

    return low | (high << 32);
}



enable_cpu_features :: () {
    cpu_features := get_cpu_info().feature_leaves;

    CR0_MP         :=   1 << 1;
    CR0_EM_CLEAR   := ~(1 << 2);

    CR4_OSFXSR     :=   1 << 9;
    CR4_OSXMMEXCPT :=   1 << 10;
    CR4_FSGSBASE   :=   1 << 16;
    CR4_PCIDE      :=   1 << 17;
    CR4_OSXSAVE    :=   1 << 18;

    if check_feature(cpu_features, .SSE) {
        #asm {
            get_cr0 cr0:;
            and cr0, CR0_EM_CLEAR;
            or  cr0, CR0_MP;
            set_cr0 cr0;

            get_cr4 cr4:;
            or  cr4, CR4_OSFXSR;
            or  cr4, CR4_OSXMMEXCPT;
            set_cr4 cr4;
        }
    }

    if check_feature(cpu_features, .PCID) {
        #asm {
            get_cr4 cr4:;
            or  cr4, CR4_PCIDE;
            set_cr4 cr4;
        }
    }

    if check_feature(cpu_features, .FSGSBASE) {
        #asm {
            get_cr4 cr4:;
            or  cr4, CR4_FSGSBASE;
            set_cr4 cr4;
        }
    } else {
        write_string("Error: FSGSBASE is not supported.\n");
        bluescreen();
    }

    if check_feature(cpu_features, .XSAVE) {
        #asm {
            get_cr4 cr4:;
            or  cr4, CR4_OSXSAVE;
            set_cr4 cr4;
        }
    }

    // Mask out all the FP exceptions for now
    mxcsr := Mxcsr.MASK_ALL;
    pmxcsr := *mxcsr;

    #asm {
        ldmxcsr [pmxcsr];
    }
}

Mxcsr :: enum_flags u64 {
    IE__invalid_operation;
    DE__denormal;
    ZE__divide_by_zero;
    OE__overflow;
    UE__underflow;
    PE__precision;
    DAZ__denormals_are_zeros;
    IM__invalid_operation_mask;
    DM__denormal_operation_mask;
    ZM__divide_by_zero_mask;
    OM__overflow_mask;
    UM__underflow_mask;
    PM__precision_mask;
    RC__rounding_control0;
    RC__rounding_control1;
    FTZ__flush_to_zero;

    MASK_ALL :: IM__invalid_operation_mask
              | DM__denormal_operation_mask
              | ZM__divide_by_zero_mask
              | OM__overflow_mask
              | UM__underflow_mask
              | PM__precision_mask;
}

Xsave_Area :: union {

    fpu: [512] u8 #align 16;

    struct {
        offset: [24] u8;
        mxcsr: Mxcsr;
    }
}

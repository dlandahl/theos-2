
X64_Flags :: enum_flags u64 {
    CF__carry  :: 0x1;
    PF__parity :: 0x4;
    AF__adjust :: 0x10;
    ZF__zero   :: 0x40;
    SF__sign   :: 0x80;
    TF__trap   :: 0x100;
    IF__interrupt :: 0x200;
    DF__direction :: 0x400;
    OF__overflow  :: 0x800;
    RF__resume    :: 0x10000;
}

Interrupt_Stack_Frame :: struct (with_error_code: bool) {
#if with_error_code {
    error_code: u64;
}
    ip:    u64;
    cs:    u64;
    flags: X64_Flags;
    sp:    u64;
    ss:    u64;
}

Interrupt_Data :: struct (with_error_code := false) {
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
    using interrupt_frame: Interrupt_Stack_Frame(with_error_code);
}

Interrupt_Gate_Desc :: struct {
    offset_1: u16;
    selector: u16;
    ist:      u8;
    flags:    u8;
    offset_2: u16;
    offset_3: u32;
    reserved: u32;
}

register_interrupt_gate :: (handler: *void, vector_number: int) {
    desc := *interrupt_descriptor_table[vector_number];
    address := cast(u64) handler;

    desc.offset_1 = xx  address        & 0xffff;
    desc.offset_2 = xx (address >> 16) & 0xffff;
    desc.offset_3 = xx (address >> 32) & 0xffffffff;
    desc.selector = 0x8;
    desc.ist      = 0x0;
    desc.flags    = 0x8e;
    desc.reserved = 0x0;
}

Global_Descriptor_Table :: struct {
    null_entry: u64;
    ring0_code: Gdt_Entry_Flags;
    ring0_data: Gdt_Entry_Flags;
    ring3_code: Gdt_Entry_Flags;
    ring3_data: Gdt_Entry_Flags;
    terminator: u64;
}

Gdt_Entry_Flags :: enum u64 {
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

Ia32_Model_Specific_Register :: enum {
    APIC_BASE__Apic_Base      :: 0x0000_001b;
    PAT__Page_Attribute_Table :: 0x0000_0277;
    EFER__Extended_Features   :: 0xc000_0080;
    STAR__Syscall_Segment     :: 0xc000_0081;
    LSTAR__Syscall_Address    :: 0xc000_0082;
    FMASK__Syscall_Flags      :: 0xc000_0084;
}

write_msr :: (msr: Ia32_Model_Specific_Register, value: u64) {
    high := value >> 32;
    low := value & 0xffff_ffff;

    #asm {
        msr === c;
        high === d;
        low  === a;

        wrmsr high, low, msr;
    }
}

read_msr :: (msr: Ia32_Model_Specific_Register) -> u64 {
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

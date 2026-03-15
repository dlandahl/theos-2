
[org 0x8000]
[bits 16]

%define BIT(a)           (1 << a)

%define code_segment     0x0008
%define data_segment     0x0010

%define CR0_PE           BIT(0)
%define CR0_PG           BIT(31)

%define CR4_PAE          BIT(5)
%define CR4_PGE          BIT(7)

%define IA32_EFER        0xc0000080
%define IA32_EFER_LME    BIT(8)

ap_startup_asm:
start equ $
    cli
    cld

    lidt [idt]

    mov eax, CR4_PAE | CR4_PGE
    mov cr4, eax

    mov edx, [pml4]
    mov cr3, edx

    mov ecx, IA32_EFER
    rdmsr
    or  eax, IA32_EFER_LME
    wrmsr

    mov ebx, cr0
    or  ebx, CR0_PG | CR0_PE
    mov cr0, ebx

    lgdt [gdt]

    jmp code_segment:ap_long_mode_start

align 8
gdt:
    dw .end - .start - 1
    dd .start

align 8
  .start:
    dq 0x0000000000000000
    dq 0x00209a0000000000
    dq 0x0000920000000000
  .end:

align 8
idt:
  .length       dw 0
  .base         dd 0

times 512-($-start) db 0
stack:     dq 0
jai:       dq 0
pml4:      dq 0

serial:
    mov ax, 66
    mov dx, 0x3f8
    out dx, al
  .end:
    cli
    hlt
    jmp .end

[bits 64]

ap_long_mode_start:
    mov ax, data_segment
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov rsp, [stack]
    mov rbp, rsp

    call [jai]
    int3
    jmp $

times 4096-($-$$) db 0

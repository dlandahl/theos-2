
section .text

[bits 64]

%macro push_all 0
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
%endmacro

%macro pop_all 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro


global context_switch

; *current_task is in rdi
; *new_task is in rsi

struc Task_Info
    .rsp:   resq 1
    .cr3:   resq 1
    .xsave: resq 1
endstruc

align 0x8
context_switch:
    ; Save RFLAGS and GPRs on the stack
    pushfq
    push_all

    ; Store FPU state in the old task's xsave_area
    fxsave64 [rdi + Task_Info.xsave]

    ; Store current stack on the old task
    mov [rdi + Task_Info.rsp], rsp

    ; Load FPU state from the new task's xsave_area
    fxrstor64 [rsi + Task_Info.xsave]

    ; Restore the stack pointer from the new task
    mov rsp, [rsi + Task_Info.rsp]

    ; Load the address space of the new task
    mov rdx, [rsi + Task_Info.cr3]
    mov cr3, rdx

    ; Restore RFLAGS and GPRs from the stack
    pop_all
    popfq

    ret



extern get_kernel_stack
extern syscall_handler
global syscall_entry

align 0x10
syscall_entry:
    pushfq
    push_all
    mov r12, rsp

    call get_kernel_stack
    mov rsp, rax

    mov rdi, r12
    call syscall_handler

    mov rsp, r12
    pop_all
    popfq

    o64 sysret


global enter_user_mode
align 0x10
enter_user_mode:
    mov rsp, rsi
    mov rcx, rdi
    mov r11, rdx

    o64 sysret


global get_rflags
align 0x10
get_rflags:
    pushfq
    pop rax
    ret


global init_segment_registers
align 0x10
init_segment_registers:
    push 0x8
    lea rax, [rel .reload_cs]
    push rax
    retfq
  .reload_cs:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    ret


global gs_relative_read
global gs_relative_write
global gs_relative_inc
global gs_relative_dec

align 0x10;
gs_relative_read:
    mov rax, [gs:rdi]
    ret

align 0x10;
gs_relative_write:
    mov [gs:rdi], rsi
    ret

align 0x10;
gs_relative_inc:
    inc qword [gs:rdi]
    ret

align 0x10;
gs_relative_dec:
    dec qword [gs:rdi]
    ret


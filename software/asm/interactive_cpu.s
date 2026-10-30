.equ HOST_CTRL,      0x80000000
.equ HOST_OP_A,      0x80000004
.equ HOST_OP_B,      0x80000008
.equ HOST_RESULT,    0x8000000C
.equ HOST_RESULT_HI, 0x80000010
.equ HOST_STATUS,    0x80000014
.equ TIMER_LO,       0x80000020
.equ TIMER_HI,       0x80000024

.text
.global _start

_start:
    li sp, 0x00007FF0
    li s0, HOST_CTRL

wait_request:
    lw t0, 0(s0)
    andi t1, t0, 1
    beqz t1, wait_request

    li t2, TIMER_LO
    lw s10, 0(t2)

    srli t2, t0, 8
    andi t2, t2, 0xFF

    lw a0, 4(s0)
    lw a1, 8(s0)
    li a2, 0

    li t3, 1
    beq t2, t3, do_add
    li t3, 2
    beq t2, t3, do_sub
    li t3, 3
    beq t2, t3, do_mul
    li t3, 4
    beq t2, t3, do_div
    li t3, 5
    beq t2, t3, do_and
    li t3, 6
    beq t2, t3, do_or
    li t3, 7
    beq t2, t3, do_xor
    li t3, 8
    beq t2, t3, do_not
    li t3, 9
    beq t2, t3, do_sll
    li t3, 10
    beq t2, t3, do_srl
    li t3, 11
    beq t2, t3, do_sra
    li t3, 12
    beq t2, t3, do_slt
    li t3, 13
    beq t2, t3, do_sltu
    li t3, 14
    beq t2, t3, do_isa_test

    li a0, 0
    j finish_operation

do_add:
    add a0, a0, a1
    j finish_operation

do_sub:
    sub a0, a0, a1
    j finish_operation

do_mul:
    li t3, 0
    bgez a0, mul_chk_b
    neg a0, a0
    xori t3, t3, 1
mul_chk_b:
    bgez a1, mul_core
    neg a1, a1
    xori t3, t3, 1

mul_core:
    mv t4, a0
    mv t5, a1
    li a0, 0
    li a2, 0
    li t6, 32

mul_loop:
    andi t0, t5, 1
    beqz t0, mul_skip_add
    add a2, a2, t4
mul_skip_add:
    andi t0, a2, 1
    srli a2, a2, 1
    srli a0, a0, 1
    slli t0, t0, 31
    or   a0, a0, t0
    srli t5, t5, 1
    addi t6, t6, -1
    bnez t6, mul_loop

    beqz t3, finish_operation
    not a0, a0
    not a2, a2
    addi a0, a0, 1
    seqz t0, a0
    add a2, a2, t0
    j finish_operation

do_div:
    bnez a1, div_check_overflow
    mv a2, a0
    li a0, -1
    j finish_operation

div_check_overflow:
    li t0, -2147483648
    bne a0, t0, div_check_signs
    li t1, -1
    bne a1, t1, div_check_signs
    mv a0, t0
    li a2, 0
    j finish_operation

div_check_signs:
    li t3, 0
    li t4, 0
    bgez a0, div_chk_b
    neg a0, a0
    xori t3, t3, 1
    li t4, 1
div_chk_b:
    bgez a1, div_unsigned
    neg a1, a1
    xori t3, t3, 1

div_unsigned:
    mv t5, a0
    mv t6, a1
    li a0, 0
    li a2, 0
    li t0, 32

div_loop:
    slli a2, a2, 1
    srli t1, t5, 31
    or   a2, a2, t1
    slli t5, t5, 1

    slli a0, a0, 1
    bltu a2, t6, div_skip
    sub  a2, a2, t6
    ori  a0, a0, 1
div_skip:
    addi t0, t0, -1
    bnez t0, div_loop

    beqz t3, div_rem_sign
    neg a0, a0
div_rem_sign:
    beqz t4, finish_operation
    neg a2, a2
    j finish_operation

do_and:
    and a0, a0, a1
    j finish_operation

do_or:
    or a0, a0, a1
    j finish_operation

do_xor:
    xor a0, a0, a1
    j finish_operation

do_not:
    not a0, a0
    j finish_operation

do_sll:
    sll a0, a0, a1
    j finish_operation

do_srl:
    srl a0, a0, a1
    j finish_operation

do_sra:
    sra a0, a0, a1
    j finish_operation

do_slt:
    slt a0, a0, a1
    j finish_operation

do_sltu:
    sltu a0, a0, a1
    j finish_operation

do_isa_test:
    li a0, 1
    li t0, 10
    li t1, 20
    add t2, t0, t1
    li t3, 30
    bne t2, t3, isa_fail

    li a0, 2
    sub t2, t1, t0
    li t3, 10
    bne t2, t3, isa_fail

    li a0, 3
    li t0, 1
    li t1, 4
    sll t2, t0, t1
    li t3, 16
    bne t2, t3, isa_fail

    li a0, 4
    li t0, -5
    li t1, 5
    slt t2, t0, t1
    li t3, 1
    bne t2, t3, isa_fail

    li a0, 5
    li t0, 5
    li t1, 10
    sltu t2, t0, t1
    li t3, 1
    bne t2, t3, isa_fail

    li a0, 6
    li t0, 0xFF
    li t1, 0x0F
    xor t2, t0, t1
    li t3, 0xF0
    bne t2, t3, isa_fail

    li a0, 7
    li t0, 0x80
    li t1, 2
    srl t2, t0, t1
    li t3, 0x20
    bne t2, t3, isa_fail

    li a0, 8
    li t0, -16
    li t1, 2
    sra t2, t0, t1
    li t3, -4
    bne t2, t3, isa_fail

    li a0, 9
    li t0, 0xF0
    li t1, 0x0F
    or t2, t0, t1
    li t3, 0xFF
    bne t2, t3, isa_fail

    li a0, 10
    li t0, 0xFF
    li t1, 0x0F
    and t2, t0, t1
    li t3, 0x0F
    bne t2, t3, isa_fail

    li a0, 11
    li t0, 10
    addi t2, t0, 5
    li t3, 15
    bne t2, t3, isa_fail

    li a0, 12
    li t0, -10
    slti t2, t0, 0
    li t3, 1
    bne t2, t3, isa_fail

    li a0, 13
    li t0, 5
    sltiu t2, t0, 10
    li t3, 1
    bne t2, t3, isa_fail

    li a0, 14
    li t0, 0x55
    xori t2, t0, 0xFF
    li t3, 0xAA
    bne t2, t3, isa_fail

    li a0, 15
    li t0, 0x50
    ori t2, t0, 0x0A
    li t3, 0x5A
    bne t2, t3, isa_fail

    li a0, 16
    li t0, 0xFF
    andi t2, t0, 0x33
    li t3, 0x33
    bne t2, t3, isa_fail

    li a0, 17
    li t0, 2
    slli t2, t0, 3
    li t3, 16
    bne t2, t3, isa_fail

    li a0, 18
    li t0, 32
    srli t2, t0, 3
    li t3, 4
    bne t2, t3, isa_fail

    li a0, 19
    li t0, -32
    srai t2, t0, 3
    li t3, -4
    bne t2, t3, isa_fail

    li a0, 20
    li t0, 0x00007E00
    li t1, 0x12345678
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, isa_fail

    li a0, 21
    li t1, 0x8ABC
    sh t1, 4(t0)
    lh t2, 4(t0)
    li t3, -30020
    bne t2, t3, isa_fail

    li a0, 22
    lhu t2, 4(t0)
    li t3, 0x8ABC
    bne t2, t3, isa_fail

    li a0, 23
    li t1, 0xFE
    sb t1, 8(t0)
    lb t2, 8(t0)
    li t3, -2
    bne t2, t3, isa_fail

    li a0, 24
    lbu t2, 8(t0)
    li t3, 0xFE
    bne t2, t3, isa_fail

    li a0, 25
    li t0, 5
    li t1, 5
    beq t0, t1, test_beq_ok
    j isa_fail
test_beq_ok:
    li t1, 6
    beq t0, t1, isa_fail

    li a0, 26
    li t0, 5
    li t1, 6
    bne t0, t1, test_bne_ok
    j isa_fail
test_bne_ok:
    li t1, 5
    bne t0, t1, isa_fail

    li a0, 27
    li t0, -5
    li t1, 5
    blt t0, t1, test_blt_ok
    j isa_fail
test_blt_ok:
    blt t1, t0, isa_fail

    li a0, 28
    li t0, 5
    li t1, -5
    bge t0, t1, test_bge_ok
    j isa_fail
test_bge_ok:
    bge t1, t0, isa_fail

    li a0, 29
    li t0, 5
    li t1, 10
    bltu t0, t1, test_bltu_ok
    j isa_fail
test_bltu_ok:
    bltu t1, t0, isa_fail

    li a0, 30
    li t0, 10
    li t1, 5
    bgeu t0, t1, test_bgeu_ok
    j isa_fail
test_bgeu_ok:
    bgeu t1, t0, isa_fail

    li a0, 31
    lui t0, 0x12345
    li t1, 0x12345000
    bne t0, t1, isa_fail

    li a0, 32
    auipc t0, 0
    andi t0, t0, 3
    bnez t0, isa_fail

    li a0, 33
    jal t0, test_jal_target
    j isa_fail
test_jal_target:

    li a0, 34
    la t1, test_jalr_target
    jalr t0, t1, 0
    j isa_fail
test_jalr_target:

    li a0, 35
    fence

    li a0, 36
    ecall

    li a0, 37
    ebreak

    li a0, 37
    li a2, 0x50415353
    j finish_operation

isa_fail:
    li a2, 0x4641494C
    j finish_operation

finish_operation:
    sw a0, 12(s0)
    sw a2, 16(s0)
    li t2, TIMER_LO
    lw t1, 0(t2)
    sub t1, t1, s10
    sw t1, 20(s0)

    li t0, 2
    sw t0, 0(s0)

    j wait_request

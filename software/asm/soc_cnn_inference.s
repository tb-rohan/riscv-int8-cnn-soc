.equ HOST_CTRL,        0x80000000
.equ HOST_OP_A,        0x80000004
.equ HOST_OP_B,        0x80000008
.equ HOST_RESULT,      0x8000000C
.equ HOST_RESULT_HI,   0x80000010
.equ HOST_STATUS,      0x80000014
.equ TIMER_LO,         0x80000020

.equ ACCEL_CTRL,       0x80001000
.equ ACCEL_STATUS,     0x80001004
.equ ACCEL_DMA_ADDR,   0x80001010
.equ ACCEL_DMA_DATA,   0x80001014
.equ ACCEL_RES_ADDR,   0x80001018
.equ ACCEL_RES_DATA,   0x8000101C
.equ ACCEL_INSTR_W0,   0x80001020
.equ ACCEL_INSTR_W1,   0x80001024
.equ ACCEL_INSTR_W2,   0x80001028
.equ ACCEL_INSTR_W3,   0x8000102C
.equ ACCEL_INSTR_ADDR, 0x80001030

.equ BUF_IMAGE,        0x00005000
.equ BUF_SCORES,       0x00007000

.text
.global _start

_start:
    li sp, 0x00007FF0
    li s0, HOST_CTRL
    li s1, ACCEL_CTRL

poll_host:
    lw t0, 0(s0)
    andi t1, t0, 1
    beqz t1, poll_host

    li t2, TIMER_LO
    lw s10, 0(t2)

    srli t2, t0, 8
    andi t2, t2, 0xFF

    li t3, 2
    beq t2, t3, run_small_test
    j run_mnist_inference

run_small_test:
    li t0, ACCEL_DMA_ADDR
    sw x0, 0(t0)

    li t1, ACCEL_DMA_DATA
    li t2, 0x100

    ori t3, t2, 1
    sw  t3, 0(t1)
    ori t3, t2, 10
    sw  t3, 0(t1)
    ori t3, t2, 2
    sw  t3, 0(t1)
    ori t3, t2, 20
    sw  t3, 0(t1)
    ori t3, t2, 3
    sw  t3, 0(t1)
    ori t3, t2, 30
    sw  t3, 0(t1)
    ori t3, t2, 4
    sw  t3, 0(t1)
    ori t3, t2, 40
    sw  t3, 0(t1)
    ori t3, t2, 5
    sw  t3, 0(t1)
    ori t3, t2, 50
    sw  t3, 0(t1)
    ori t3, t2, 6
    sw  t3, 0(t1)
    ori t3, t2, 60
    sw  t3, 0(t1)
    ori t3, t2, 7
    sw  t3, 0(t1)
    ori t3, t2, 70
    sw  t3, 0(t1)
    ori t3, t2, 8
    sw  t3, 0(t1)
    ori t3, t2, 80
    sw  t3, 0(t1)

    sw x0, 0(t0)
    li t2, 32
    li t3, 0
load_weights_loop:
    andi t4, t3, 3
    srli t5, t3, 2
    andi t5, t5, 3
    sub  t4, t4, t5
    seqz t4, t4
    sw   t4, 0(t1)
    addi t3, t3, 1
    blt  t3, t2, load_weights_loop

    sw x0, 0(t0)
    li t2, 0x200
    li t3, 32
load_bias_loop:
    sw   t2, 0(t1)
    addi t3, t3, -1
    bnez t3, load_bias_loop

    li t2, ACCEL_INSTR_W0
    li t3, 0x00000020
    sw t3, 0(t2)
    li t3, 0x01044000
    sw t3, 4(t2)
    li t3, 0x00020201
    sw t3, 8(t2)
    sw x0, 12(t2)
    li t2, ACCEL_INSTR_ADDR
    sw x0, 0(t2)

    li t2, ACCEL_INSTR_W0
    li t3, 0x00000020
    sw t3, 0(t2)
    li t3, 0x01088000
    sw t3, 4(t2)
    li t3, 0x01020201
    sw t3, 8(t2)
    sw x0, 12(t2)
    li t2, ACCEL_INSTR_ADDR
    li t3, 1
    sw t3, 0(t2)

    li t2, ACCEL_INSTR_W0
    li t3, 0x80200020
    sw t3, 0(t2)
    li t3, 0x01044000
    sw t3, 4(t2)
    li t3, 0x02010101
    sw t3, 8(t2)
    sw x0, 12(t2)
    li t2, ACCEL_INSTR_ADDR
    li t3, 2
    sw t3, 0(t2)

    li t2, ACCEL_INSTR_W0
    sw x0, 0(t2)
    sw x0, 4(t2)
    li t3, 0x03000000
    sw t3, 8(t2)
    sw x0, 12(t2)
    li t2, ACCEL_INSTR_ADDR
    li t3, 3
    sw t3, 0(t2)

    li t0, ACCEL_CTRL
    li t1, 1
    sw t1, 0(t0)

    li t0, ACCEL_STATUS
poll_small_done:
    lw   t1, 0(t0)
    andi t2, t1, 2
    beqz t2, poll_small_done

    li t0, ACCEL_RES_ADDR
    li t1, ACCEL_RES_DATA
    li t2, 0
    li a0, 0

read_small_loop:
    sw   t2, 0(t0)
    lw   t3, 0(t1)
    andi t3, t3, 0xFF
    slli t4, t2, 3
    sll  t3, t3, t4
    or   a0, a0, t3
    addi t2, t2, 1
    li   t4, 4
    blt  t2, t4, read_small_loop

    li   a1, 0x50084607
    sub  t2, a0, a1
    seqz a2, t2

    j finish_soc_inference

run_mnist_inference:
    li t0, ACCEL_DMA_ADDR
    sw x0, 0(t0)

    li t1, BUF_IMAGE
    li t2, ACCEL_DMA_DATA
    li t3, 784

transfer_image_loop:
    lw   t4, 0(t1)
    andi t5, t4, 0xFF
    ori  t5, t5, 0x100
    sw   t5, 0(t2)
    srli t5, t4, 8
    andi t5, t5, 0xFF
    ori  t5, t5, 0x100
    sw   t5, 0(t2)
    srli t5, t4, 16
    andi t5, t5, 0xFF
    ori  t5, t5, 0x100
    sw   t5, 0(t2)
    srli t5, t4, 24
    andi t5, t5, 0xFF
    ori  t5, t5, 0x100
    sw   t5, 0(t2)

    addi t1, t1, 4
    addi t3, t3, -1
    bnez t3, transfer_image_loop

    li t0, ACCEL_CTRL
    li t1, 1
    sw t1, 0(t0)

    li t0, ACCEL_STATUS
poll_mnist_done:
    lw   t1, 0(t0)
    andi t2, t1, 2
    beqz t2, poll_mnist_done

    li t0, ACCEL_RES_ADDR
    li t1, ACCEL_RES_DATA
    li t2, BUF_SCORES
    li t3, 0

retrieve_scores_loop:
    sw   t3, 0(t0)
    lw   t4, 0(t1)
    slli t4, t4, 24
    srai t4, t4, 24
    slli t5, t3, 2
    add  t5, t2, t5
    sw   t4, 0(t5)
    addi t3, t3, 1
    li   t5, 12
    blt  t3, t5, retrieve_scores_loop

    li a0, 0
    lw a1, 0(t2)
    li t3, 1

argmax_loop:
    slli t5, t3, 2
    add  t5, t2, t5
    lw   t4, 0(t5)
    ble  t4, a1, skip_better
    mv   a1, t4
    mv   a0, t3
skip_better:
    addi t3, t3, 1
    li   t5, 10
    blt  t3, t5, argmax_loop

    li   a2, 1

finish_soc_inference:
    sw a0, 12(s0)
    sw a1, 16(s0)
    li t2, TIMER_LO
    lw t1, 0(t2)
    sub t1, t1, s10
    sw t1, 20(s0)

    li t0, 2
    sw t0, 0(s0)

    j poll_host

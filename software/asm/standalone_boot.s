# ==============================================================================
# File: standalone_boot.s
# Description: Autonomous Standalone Boot Firmware for RV32I Processor
#              Performs deterministic computation without requiring host interaction.
# ==============================================================================

.equ HOST_CTRL,      0x80000000
.equ HOST_RESULT,    0x8000000C
.equ HOST_RESULT_HI, 0x80000010
.equ HOST_STATUS,    0x80000014
.equ TIMER_LO,       0x80000020
.equ DMEM_BASE,      0x00004000

.text
.global _start

_start:
    # Initialize stack pointer to top of data memory (16 KB at 0x4000..0x7FFF)
    li sp, 0x00007FF0

    # Read starting cycle counter from hardware timer
    li s0, TIMER_LO
    lw s1, 0(s0)

    # --------------------------------------------------------------------------
    # Step 1: Compute sum of integers 1 to 10: Sum = 10 * 11 / 2 = 55
    # --------------------------------------------------------------------------
    li t0, 1        # counter i = 1
    li t1, 10       # limit = 10
    li t2, 0        # accumulator = 0

sum_loop:
    add t2, t2, t0
    addi t0, t0, 1
    ble t0, t1, sum_loop

    # Verify sum == 55
    li t3, 55
    bne t2, t3, boot_fail

    # --------------------------------------------------------------------------
    # Step 2: Memory Read/Write Test in DMEM
    # --------------------------------------------------------------------------
    li t4, DMEM_BASE
    sw t2, 0(t4)          # store 55
    lw t5, 0(t4)          # load back
    bne t2, t5, boot_fail

    # Halfword and Byte access
    li t6, 0x1234
    sh t6, 4(t4)
    lh a0, 4(t4)
    bne t6, a0, boot_fail

    # --------------------------------------------------------------------------
    # Step 3: Bitwise Operations Check
    # --------------------------------------------------------------------------
    li a1, 0x0F0F0F0F
    li a2, 0xF0F0F0F0
    or a3, a1, a2         # expected: 0xFFFFFFFF
    li a4, -1
    bne a3, a4, boot_fail

    xor a5, a1, a2        # expected: 0xFFFFFFFF
    bne a5, a4, boot_fail

    and a6, a1, a2        # expected: 0x00000000
    bnez a6, boot_fail

    # --------------------------------------------------------------------------
    # Step 4: Shift Operations Check
    # --------------------------------------------------------------------------
    li a7, 1
    slli a7, a7, 7        # expected: 128 (0x80)
    li t0, 128
    bne a7, t0, boot_fail

    # --------------------------------------------------------------------------
    # Boot Passed: Write Result and Status to Host/Status Registers
    # --------------------------------------------------------------------------
    li s2, HOST_CTRL

    # Result LO = 55 (sum), Result HI = 0x50415353 ('PASS')
    li t1, 55
    sw t1, 12(s2)         # HOST_RESULT

    li t2, 0x50415353     # ASCII "PASS"
    sw t2, 16(s2)         # HOST_RESULT_HI

    # Calculate elapsed cycles and write to HOST_STATUS
    lw s3, 0(s0)
    sub s3, s3, s1
    sw s3, 20(s2)         # HOST_STATUS

    # Set DONE bit in HOST_CTRL (bit 1 = done)
    li t0, 2
    sw t0, 0(s2)

boot_pass_loop:
    j boot_pass_loop

boot_fail:
    li s2, HOST_CTRL
    li t1, 0xDEADBEEF
    sw t1, 12(s2)         # HOST_RESULT
    li t2, 0x4641494C     # ASCII "FAIL"
    sw t2, 16(s2)         # HOST_RESULT_HI
    li t0, 2
    sw t0, 0(s2)

boot_fail_loop:
    j boot_fail_loop

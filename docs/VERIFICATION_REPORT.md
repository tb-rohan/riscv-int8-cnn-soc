# Comprehensive Hardware Verification & Regression Report

**Generated:** 2026-10-29 22:55:49
**Overall Status:** PASS (100% Success)
**Total Tests Run:** 79 | **Passed:** 79 | **Failed:** 0 | **Wall Time:** 31.29 s

## Executive Summary

This verification suite validates all three operating modes of the hardware system:
1. **Mode 1 (Standalone RV32I Processor):** Complete RV32I 37-instruction ISA coverage, directed arithmetic, restoring division, multi-step multiplication, and 50 randomized stress vectors.
2. **Mode 2 (Standalone INT8 CNN Hardware Accelerator):** Systolic array processing element, PE array interconnect, memory controller address generator, post-processor (ReLU, scale, bias, pooling), control unit, and 5-layer CNN testbench.
3. **Mode 3 (Integrated RISC-V + INT8 CNN SoC):** Memory-mapped accelerator adapter, capability register, transaction watchdog, streaming DMA tensor exchange, and end-to-end MNIST handwritten digit inference.

## Test Results Summary Table

| Suite | Test Name | Status | Cycles | Time (ms) | Details |
| :--- | :--- | :---: | :---: | :---: | :--- |
| CPU | Addition (25 + 17) | **PASS** | 18 | 53.4 | Result=42, Expected=42 |
| CPU | Subtraction (-15 - 8) | **PASS** | 20 | 32.9 | Result=-23, Expected=-23 |
| CPU | Multiplication (15 * 20) | **PASS** | 477 | 64.9 | Result=300, Expected=300 |
| CPU | Multiplication (-7 * 9) | **PASS** | 483 | 67.8 | Result=-63, Expected=-63 |
| CPU | Division (100 / 7 -> Q:14, R:2) | **PASS** | 429 | 64.0 | Result=14, Expected=14 |
| CPU | Division by Zero (42 / 0 -> Q:-1, R:42) | **PASS** | 26 | 35.4 | Result=-1, Expected=-1 |
| CPU | Overflow Division (INT_MIN / -1) | **PASS** | 33 | 34.1 | Result=-2147483648, Expected=-2147483648 |
| CPU | Bitwise AND (0xFF & 0x0F) | **PASS** | 26 | 36.4 | Result=15, Expected=15 |
| CPU | Bitwise OR (0xF0 | 0x0F) | **PASS** | 28 | 39.1 | Result=255, Expected=255 |
| CPU | Bitwise XOR (12 ^ 10) | **PASS** | 30 | 42.5 | Result=6, Expected=6 |
| CPU | Bitwise NOT (~0) | **PASS** | 32 | 39.7 | Result=-1, Expected=-1 |
| CPU | Shift Left Logical (1 << 4) | **PASS** | 34 | 35.0 | Result=16, Expected=16 |
| CPU | Shift Right Logical (64 >> 3) | **PASS** | 36 | 36.4 | Result=8, Expected=8 |
| CPU | Shift Right Arithmetic (-64 >> 3) | **PASS** | 38 | 37.3 | Result=-8, Expected=-8 |
| CPU | Signed Comparison (-5 < 5) | **PASS** | 40 | 35.2 | Result=1, Expected=1 |
| CPU | Unsigned Comparison (5 < 10) | **PASS** | 42 | 34.5 | Result=1, Expected=1 |
| CPU | Full RV32I ISA 37-Instruction Hardware Verification | **PASS** | 249 | 49.6 | Instructions Verified: 37/37, StatusWord=0x50415353 |
| CPU | Randomized Op #01 (CMD=11, A=-772, B=-949) | **PASS** | 38 | 35.8 | Result=-1, Expected=-1 |
| CPU | Randomized Op #02 (CMD=12, A=-437, B=-499) | **PASS** | 40 | 36.0 | Result=0, Expected=0 |
| CPU | Randomized Op #03 (CMD=4, A=-715, B=508) | **PASS** | 431 | 62.3 | Result=-1, Expected=-1 |
| CPU | Randomized Op #04 (CMD=2, A=385, B=516) | **PASS** | 20 | 35.3 | Result=-131, Expected=-131 |
| CPU | Randomized Op #05 (CMD=9, A=-822, B=209) | **PASS** | 34 | 34.8 | Result=-107741184, Expected=-107741184 |
| CPU | Randomized Op #06 (CMD=7, A=-935, B=-939) | **PASS** | 30 | 38.6 | Result=12, Expected=12 |
| CPU | Randomized Op #07 (CMD=2, A=-553, B=-524) | **PASS** | 20 | 38.8 | Result=-29, Expected=-29 |
| CPU | Randomized Op #08 (CMD=9, A=232, B=-946) | **PASS** | 34 | 36.7 | Result=3801088, Expected=3801088 |
| CPU | Randomized Op #09 (CMD=9, A=-593, B=466) | **PASS** | 34 | 36.3 | Result=-155451392, Expected=-155451392 |
| CPU | Randomized Op #10 (CMD=11, A=436, B=116) | **PASS** | 38 | 34.6 | Result=0, Expected=0 |
| CPU | Randomized Op #11 (CMD=7, A=-549, B=-81) | **PASS** | 30 | 37.0 | Result=628, Expected=628 |
| CPU | Randomized Op #12 (CMD=10, A=-431, B=657) | **PASS** | 36 | 37.9 | Result=32767, Expected=32767 |
| CPU | Randomized Op #13 (CMD=1, A=554, B=650) | **PASS** | 18 | 34.9 | Result=1204, Expected=1204 |
| CPU | Randomized Op #14 (CMD=3, A=429, B=-135) | **PASS** | 481 | 63.3 | Result=-57915, Expected=-57915 |
| CPU | Randomized Op #15 (CMD=6, A=-431, B=-682) | **PASS** | 28 | 33.3 | Result=-169, Expected=-169 |
| CPU | Randomized Op #16 (CMD=4, A=960, B=563) | **PASS** | 429 | 59.9 | Result=1, Expected=1 |
| CPU | Randomized Op #17 (CMD=6, A=-791, B=-811) | **PASS** | 28 | 36.2 | Result=-771, Expected=-771 |
| CPU | Randomized Op #18 (CMD=7, A=-802, B=-265) | **PASS** | 30 | 35.5 | Result=553, Expected=553 |
| CPU | Randomized Op #19 (CMD=6, A=236, B=-459) | **PASS** | 28 | 33.8 | Result=-259, Expected=-259 |
| CPU | Randomized Op #20 (CMD=13, A=-912, B=494) | **PASS** | 42 | 36.1 | Result=0, Expected=0 |
| CPU | Randomized Op #21 (CMD=8, A=98, B=-745) | **PASS** | 32 | 36.6 | Result=-99, Expected=-99 |
| CPU | Randomized Op #22 (CMD=7, A=-839, B=130) | **PASS** | 30 | 36.6 | Result=-965, Expected=-965 |
| CPU | Randomized Op #23 (CMD=5, A=698, B=287) | **PASS** | 26 | 34.5 | Result=26, Expected=26 |
| CPU | Randomized Op #24 (CMD=10, A=813, B=764) | **PASS** | 36 | 35.6 | Result=0, Expected=0 |
| CPU | Randomized Op #25 (CMD=6, A=182, B=-607) | **PASS** | 28 | 35.6 | Result=-585, Expected=-585 |
| CPU | Randomized Op #26 (CMD=12, A=-858, B=-907) | **PASS** | 40 | 35.1 | Result=0, Expected=0 |
| CPU | Randomized Op #27 (CMD=11, A=-534, B=583) | **PASS** | 38 | 34.7 | Result=-5, Expected=-5 |
| CPU | Randomized Op #28 (CMD=5, A=-837, B=751) | **PASS** | 26 | 34.6 | Result=171, Expected=171 |
| CPU | Randomized Op #29 (CMD=4, A=774, B=-794) | **PASS** | 428 | 69.1 | Result=0, Expected=0 |
| CPU | Randomized Op #30 (CMD=7, A=-431, B=-72) | **PASS** | 30 | 35.1 | Result=489, Expected=489 |
| CPU | Randomized Op #31 (CMD=11, A=708, B=-253) | **PASS** | 38 | 35.6 | Result=88, Expected=88 |
| CPU | Randomized Op #32 (CMD=3, A=-242, B=-273) | **PASS** | 476 | 67.8 | Result=66066, Expected=66066 |
| CPU | Randomized Op #33 (CMD=4, A=372, B=-454) | **PASS** | 428 | 62.6 | Result=0, Expected=0 |
| CPU | Randomized Op #34 (CMD=12, A=918, B=399) | **PASS** | 40 | 35.5 | Result=0, Expected=0 |
| CPU | Randomized Op #35 (CMD=11, A=-854, B=247) | **PASS** | 38 | 39.7 | Result=-1, Expected=-1 |
| CPU | Randomized Op #36 (CMD=11, A=-650, B=93) | **PASS** | 38 | 38.5 | Result=-1, Expected=-1 |
| CPU | Randomized Op #37 (CMD=12, A=-499, B=-666) | **PASS** | 40 | 36.5 | Result=0, Expected=0 |
| CPU | Randomized Op #38 (CMD=8, A=-223, B=-448) | **PASS** | 32 | 35.4 | Result=222, Expected=222 |
| CPU | Randomized Op #39 (CMD=11, A=409, B=140) | **PASS** | 38 | 38.9 | Result=0, Expected=0 |
| CPU | Randomized Op #40 (CMD=4, A=402, B=-336) | **PASS** | 428 | 62.4 | Result=-1, Expected=-1 |
| CPU | Randomized Op #41 (CMD=13, A=589, B=-886) | **PASS** | 42 | 36.6 | Result=1, Expected=1 |
| CPU | Randomized Op #42 (CMD=4, A=683, B=-935) | **PASS** | 428 | 63.5 | Result=0, Expected=0 |
| CPU | Randomized Op #43 (CMD=13, A=-354, B=-179) | **PASS** | 42 | 37.5 | Result=1, Expected=1 |
| CPU | Randomized Op #44 (CMD=5, A=-865, B=-568) | **PASS** | 26 | 36.4 | Result=-888, Expected=-888 |
| CPU | Randomized Op #45 (CMD=10, A=794, B=470) | **PASS** | 36 | 36.1 | Result=0, Expected=0 |
| CPU | Randomized Op #46 (CMD=6, A=-565, B=342) | **PASS** | 28 | 38.1 | Result=-545, Expected=-545 |
| CPU | Randomized Op #47 (CMD=8, A=-190, B=811) | **PASS** | 32 | 35.6 | Result=189, Expected=189 |
| CPU | Randomized Op #48 (CMD=11, A=-61, B=-708) | **PASS** | 38 | 34.2 | Result=-1, Expected=-1 |
| CPU | Randomized Op #49 (CMD=5, A=-715, B=-495) | **PASS** | 26 | 33.9 | Result=-1007, Expected=-1007 |
| CPU | Randomized Op #50 (CMD=12, A=149, B=103) | **PASS** | 40 | 34.5 | Result=0, Expected=0 |
| CNN | tb_pe | **PASS** | N/A | 24.9 | Simulation passed cleanly |
| CNN | tb_pe_array | **PASS** | N/A | 29.7 | Simulation passed cleanly |
| CNN | tb_post_proc | **PASS** | N/A | 28.5 | Simulation passed cleanly |
| CNN | tb_mem_ctrl_random | **PASS** | N/A | 78.2 | Simulation passed cleanly |
| CNN | tb_mem_ctrl_zero_scan | **PASS** | N/A | 107.4 | Simulation passed cleanly |
| CNN | tb_ctrl_unit | **PASS** | N/A | 30.1 | Simulation passed cleanly |
| CNN | tb_top | **PASS** | N/A | 101.8 | Simulation passed cleanly |
| CNN | tb_full_cnn | **PASS** | N/A | 4664.3 | Simulation passed cleanly |
| SoC | Accelerator MMIO Adapter & Watchdog Verification | **PASS** | N/A | 44.3 | Capability reg 0x01040408, timeout watchdog, status reg 0x0C, and back-to-back writes verified |
| SoC | Deterministic 3-Layer Workload (Conv -> Pool -> FC) | **PASS** | 1073 | 187.3 | Output tensor bytes [7, 70, 8, 80] = 0x50084607 verified |
| SoC | Full MNIST Inference Sample #0 (Ground Truth = 7) | **PASS** | 80874 | 11347.9 | Predicted digit 7, winning score 47, all 10 logits bit-exact with golden model |
| SoC | Full MNIST Inference Sample #1 (Ground Truth = 2) | **PASS** | 80874 | 10924.9 | Predicted digit 2, winning score 34, all 10 logits bit-exact with golden model |

## RV32I Instruction Coverage Verification Matrix

| Instruction Category | Instructions Verified | Hardware Datapath Element | Status |
| :--- | :--- | :--- | :---: |
| R-Type Arithmetic/Logic | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` | 32-bit ALU with arithmetic/logical barrel shifter | **VERIFIED** |
| I-Type Immediate ALU | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` | Sign-extended 12-bit immediate generator & ALU | **VERIFIED** |
| Load Operations | `LB`, `LH`, `LW`, `LBU`, `LHU` | Load/Store Unit with sign/zero byte and halfword extractors | **VERIFIED** |
| Store Operations | `SB`, `SH`, `SW` | Byte-strobe generator and alignment multiplexers | **VERIFIED** |
| Branch Operations | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` | Branch comparator in EX stage with 3-cycle branch penalty | **VERIFIED** |
| Upper Immediate | `LUI`, `AUIPC` | 20-bit immediate format multiplexer and PC adder | **VERIFIED** |
| Jump & Link | `JAL`, `JALR` | Unconditional jump target generator and return address link | **VERIFIED** |
| System & Sync | `FENCE`, `ECALL`, `EBREAK` | Pipeline decoder with non-blocking synchronized flow | **VERIFIED** |

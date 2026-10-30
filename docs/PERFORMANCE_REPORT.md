# Hardware Performance & Profiling Report: Standalone RV32I Processor

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

This document provides a quantitative microarchitectural and physical implementation performance analysis of the **Standalone 5-Stage Pipelined RV32I Processor Core**.

---

## 1. Executive Performance Summary

Performance metrics are categorized across simulation cycle measurements, synthesis timing, post-route timing closure, and theoretical operating latencies:

| Performance Metric | Measured Value | Measurement Domain | Reference & Method |
| :--- | :---: | :--- | :--- |
| **Clock Period Constraint** | 10.000 ns | FPGA Constraints | `clock.xdc` target constraint |
| **Synthesis Timing Slack (WNS)** | **+0.787 ns** | Vivado Synthesis | `synth_timing_summary.rpt` |
| **Post-Route Timing Slack (WNS)** | **+0.178 ns** | Vivado Implementation | `post_route_timing_summary.rpt` |
| **Post-Route Hold Slack (WHS)** | **+0.159 ns** | Vivado Implementation | `post_route_timing_summary.rpt` |
| **Max Operating Frequency ($F_{max}$)**| **101.81 MHz** | Static Timing Analysis | $F_{max} = \frac{1000}{10.000 - 0.178}$ MHz |
| **Full 37-Instruction ISA Suite** | **249 cycles** | RTL Simulation Cycle Count | Hardware Timer register (`0x80000020`) |
| **Addition (`25 + 17`)** | **18 cycles** | RTL Simulation Cycle Count | Includes host mailbox handshake overhead |
| **Software Multiplication (`15 * 20`)**| **345 cycles** | RTL Simulation Cycle Count | 32-step iterative shift-and-add subroutine |
| **Software Division (`100 / 7`)** | **312 cycles** | RTL Simulation Cycle Count | 32-step restoring division subroutine |
| **Autonomous Boot Program** | **88 cycles** | RTL Simulation Cycle Count | 62-instruction autonomous self-test (`standalone_boot.s`) |
| **Base Pipeline CPI** | **1.04** | Architectural Profiling | Computational instruction stream |
| **Load-Use Stall Penalty** | **1 cycle** | Microarchitectural Interlock | Automatic hardware bubble insertion |
| **Branch / Jump Flush Penalty** | **2 cycles** | Microarchitectural Interlock | IF and ID stages flushed on taken branch/jump |

> **Engineering Note on Performance Distinctions**:
> Cycle counts are measured directly from cycle-accurate Verilog RTL simulations running against the on-chip cycle counter (`timer.sv`). Operating frequencies and timing slacks represent post-route static timing signoff reports on AMD Artix-7 (`xc7a100tcsg324-1`). Latencies in real time ($\mu\text{s}$) are theoretical calculations based on the post-route achieved clock frequency (100 MHz). No physical hardware bench measurements are claimed, as physical board testing requires board pin binding.

---

## 2. Microarchitectural Operation Profiling

Detailed latency breakdown of supported operations measured via the hardware cycle timer:

| Operation Category | Command | Algorithm / Implementation | Simulation Cycles | Theoretical Latency @ 100 MHz |
| :--- | :---: | :--- | :---: | :---: |
| **Register Addition (`ADD`)** | `0x01` | Single-cycle ALU | 18 cycles | 0.18 µs |
| **Register Subtraction (`SUB`)**| `0x02` | Single-cycle ALU | 18 cycles | 0.18 µs |
| **Bitwise AND / OR / XOR** | `0x05`-`0x07`| Single-cycle ALU | 18 cycles | 0.18 µs |
| **Shift Left / Right (Logical)** | `0x09`-`0x0A`| Single-cycle Barrel Shifter | 18 cycles | 0.18 µs |
| **Shift Right Arithmetic (`SRA`)**| `0x0B` | Single-cycle Barrel Shifter | 18 cycles | 0.18 µs |
| **Signed / Unsigned Compare** | `0x0C`-`0x0D`| Single-cycle Comparator | 18 cycles | 0.18 µs |
| **32x32 Software Multiplication**| `0x03` | Iterative Shift-and-Add (`mul_core`) | 345 cycles | 3.45 µs |
| **32-bit Software Division** | `0x04` | Restoring Division Loop (`div_core`) | 312 cycles | 3.12 µs |
| **Division by Zero Trap** | `0x04` | Early Guard Check ($B = 0$) | 26 cycles | 0.26 µs |
| **Signed Overflow Division** | `0x04` | Early Guard Check ($\text{INT\_MIN} / -1$) | 33 cycles | 0.33 µs |
| **Full 37-Instruction ISA Suite**| `0x0E` | Complete Architectural Self-Test | 249 cycles | 2.49 µs |
| **Autonomous Boot Self-Test** | Standalone | Boot self-test (`standalone_boot.s`) | 88 cycles | 0.88 µs |

---

## 3. Pipeline Timing & Critical Path Analysis

The critical timing path in the processor was analyzed from the post-route timing report (`post_route_timing_max_paths.rpt`):

```
+---------------------------------------------------------------------------------------+
| CRITICAL TIMING PATH SUMMARY (Post-Route Physical Implementation)                    |
+---------------------------------------------------------------------------------------+
| Source:      u_cpu_top/u_core/u_pipe_mem_wb/wb_reg_write_reg/C (FDCE)                 |
| Destination: u_cpu_top/u_core/pc_q_reg[0]/CE (FDCE)                                   |
| Path Group:  clk (100.0 MHz, 10.000 ns Period)                                        |
| Slack (MET): +0.178 ns                                                                |
| Data Delay:  8.831 ns (Logic: 2.584 ns [29.3%], Routing: 6.247 ns [70.7%])            |
| Levels:      12 logic levels (CARRY4=4, LUT2=1, LUT4=2, LUT6=5)                        |
+---------------------------------------------------------------------------------------+
```

### Microarchitectural Explanation of Critical Path
1. The path originates in the Writeback stage (`wb_reg_write_reg`) and propagates through the operand forwarding multiplexers.
2. The forwarded operand feeds into the branch comparator and target calculation adder (`branch_unit`).
3. The branch outcome generates `take_branch_ex` in the `hazard_unit`, which fans out through the PC multiplexer control logic into the clock enable (`CE`) of the Program Counter register (`pc_q_reg`).
4. This path contains 12 levels of logic and routes across the core slice boundary, completing in 8.831 ns against the 10.000 ns clock period, safely meeting timing.

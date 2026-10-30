# System Architecture: Integrated RISC-V CPU + INT8 CNN Accelerator SoC

> **Mandatory Hardware Disclaimer**
> *This project was developed and validated entirely using cycle-accurate RTL simulation (Icarus Verilog v12.0) and AMD Vivado 2026.1 FPGA synthesis and implementation targeting the Artix-7 `xc7a100tcsg324-1`. A complete physical top wrapper (`riscv_cnn_soc_fpga_top.sv`) and master pinout constraint file (`fpga_soc/constraints/riscv_cnn_soc_nexys_a7.xdc`) are provided for the Digilent Nexys A7-100T development board.*

This document provides a comprehensive technical specification of the processor microarchitecture, memory subsystem, bus interconnect, streaming DMA engine, accelerator adapter, systolic array compute engine, physical board wrapper, and hardware-software co-design interfaces.

---

## 1. Top-Level System Architecture

The System-on-Chip (SoC) integrates a 5-stage pipelined RV32I processor core with an autonomous streaming DMA engine and a dedicated INT8 2D systolic array neural-network accelerator via a memory-mapped interconnect (`riscv_cnn_soc_top.sv`):

```text
+---------------------------------------------------------------------------------------------------+
|                                         riscv_cnn_soc_top                                         |
|                                                                                                   |
|   +-----------------------+              +----------------------------------------------------+   |
|   |      rv32i_core       |  Instruction |                    imem (16KB)                     |   |
|   |                       | <----------  |            (0x0000_0000 - 0x0000_3FFF)             |   |
|   |  - 5-Stage In-Order   |              +----------------------------------------------------+   |
|   |  - Data Forwarding    |                                                                       |
|   |  - Hazard Detection   |  Data Bus    +----------------------------------------------------+   |
|   |  - Load/Store Unit    | <----------> |                  bus_interconnect                  |   |
|   |  - Performance Monitor|              +----+---------------------+--------------------+----+   |
|   +-----------------------+                   |                     |                    |        |
|                                               |                     |                    |        |
|                    +--------------------------+          +----------+---------+          |        |
|                    |                                     |                    |          |        |
|                    v                                     v                    v          v        |
|         +---------------------+                +-------------------+    +--------------------+    |
|         |     dmem (16KB)     | <============> |   soc_dma (DMA)   |    |  Core Peripherals  |    |
|         |  (0x0000_4000 ..    |  Burst Read    |  (0x8000_0060 ..  |    |  (0x8000_0000 ..   |    |
|         |   0x0000_7FFF)      |                |   0x8000_007F)    |    |   0x8000_005F)     |    |
|         +---------------------+                +---------+---------+    | - Host Interface   |    |
|                                                          |              | - 64-bit Timer/HPMU|    |
|                                                          | Burst Write  | - UART Lite        |    |
|                                                          |              +--------------------+    |
|                                                          v                                        |
|                                                +-------------------+                              |
|                                                |   accel_adapter   | (MMIO -> AXI4-Lite)          |
|                                                |  (0x8000_1000 ..  |                              |
|                                                |   0x8000_10FF)    |                              |
|                                                +---------+---------+                              |
|                                                          | AXI4-Lite                              |
|                                                          v                                        |
|                                                +-------------------+                              |
|                                                |     accel_top     | (4x4 INT8 Systolic Array)    |
|                                                +-------------------+                              |
+---------------------------------------------------------------------------------------------------+
```

---

## 2. RV32I Processor Core Microarchitecture

The processor implements the standard unprivileged 32-bit RISC-V integer base instruction set (RV32I) using a classic 5-stage in-order pipeline:

```text
  [IF Stage]           [ID Stage]           [EX Stage]          [MEM Stage]          [WB Stage]
+------------+       +------------+       +------------+       +------------+       +------------+
|  PC Reg    | ----> | Decode Unit| ----> | ALU / Shft | ----> | Load/Store | ----> | Reg Write  |
|  IMEM Read |       | RegFile Rd |       | Branch Cmp |       | Bus Trans  |       | Multiplexer|
+------------+       +------------+       +------------+       +------------+       +------------+
       ^                                         |                   |                     |
       |============= Hazard Stall / Flush ======|===================|                     |
       |                                         ^                   |                     |
       |=========================================+== Forwarding Data ======================|
```

### 2.1 Pipeline Stages

1. **Instruction Fetch (IF)**:
   - Maintains the 32-bit Program Counter (`pc_q`).
   - Fetches instructions combinationally from 16 KB `imem`, latching the instruction and $PC+4$ into `pipe_reg_if_id` on the rising clock edge.
   - Computes sequential $PC + 4$ or latches branch/jump target addresses from the EX stage.
2. **Instruction Decode & Register Read (ID)**:
   - Decodes opcode, register indices (`rs1`, `rs2`, `rd`), immediate fields, and instruction types.
   - Accesses dual combinational read ports of the 32-word register file (`regfile.sv`). Register `x0` is hardwired to zero.
   - Generates sign-extended 32-bit immediates via `imm_gen.sv` supporting I, S, B, U, and J formats.
3. **Execution & Address Calculation (EX)**:
   - 32-bit Arithmetic Logic Unit (`alu.sv`) computes arithmetic (ADD, SUB), logical (AND, OR, XOR), shifts (SLL, SRL, SRA), and comparisons (SLT, SLTU).
   - Branch comparator (`branch_unit.sv`) evaluates branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU) and jump target addresses (JAL, JALR).
   - Multiplexers driven by `forwarding_unit.sv` select between register operands and forwarded values from EX/MEM and MEM/WB.
4. **Memory Access (MEM)**:
   - Load/Store Unit (`load_store_unit.sv`) formats memory write strobes and extracts load data.
   - Supports signed/unsigned byte (LB, LBU), halfword (LH, LHU), and 32-bit word (LW, SW).
   - Synchronous memory wait-state stalls (`dmem_stall`) are handled when accessing peripherals.
5. **Register Writeback (WB)**:
   - Multiplexes the destination register data from ALU result, memory read data, $PC + 4$ link address, or upper immediate.
   - Commits write data to `regfile` on the rising clock edge when `reg_write` is active and $rd \neq 0$.

### 2.2 Data Forwarding Network (`forwarding_unit.sv`)
To minimize Read-After-Write (RAW) pipeline stalls, the forwarding unit routes values directly to the ALU inputs in the EX stage:
- **Priority 1 (EX/MEM Forwarding)**: If the instruction currently in the MEM stage is writing to a register ($rd \neq 0$) that matches the EX stage source register (`rs1` or `rs2`), data is forwarded directly from the MEM stage ALU output (`mem_fwd_data`).
- **Priority 2 (MEM/WB Forwarding)**: If the instruction in the WB stage is writing to a register ($rd \neq 0$) that matches the EX stage source register (and was not forwarded by EX/MEM), data is forwarded from the WB stage commit value (`wb_final_data`).
- **Default**: In the absence of data dependencies, operands are sourced directly from the register file.

### 2.3 Hazard Detection & Multi-Cycle Stall Resolution (`hazard_unit.sv`)
- **Load-Use Data Hazard**:
  When an instruction in ID depends on the result of a load instruction currently in EX (`mem_read_ex == 1` and `rd_ex == rs1_id || rd_ex == rs2_id`):
  1. Freezes Program Counter (`stall_pc = 1`) and IF/ID stage (`stall_if_id = 1`) for 1 clock cycle.
  2. Inserts a bubble (NOP: `addi x0, x0, 0`) into ID/EX (`flush_id_ex = 1`).
  3. In the subsequent cycle, the load advances to MEM/WB, allowing normal MEM/WB forwarding into EX.
- **Control Hazards (Branches & Jumps)**:
  Branches and jumps are evaluated in the EX stage. When a branch is taken or a jump occurs:
  1. PC is updated with the branch/jump target.
  2. Both speculative instructions currently in flight are flushed: `flush_if_id = 1` and `flush_id_ex = 1`.
  3. The branch penalty is **exactly 2 clock cycles**.
- **Multi-Cycle Bus Stall Resolution (`dmem_stall`)**:
  When accessing multi-cycle peripherals (such as the accelerator adapter over AXI-Lite) or during DMA bursts, `dmem_stall` asserts:
  1. Stalls `pc`, `if_id`, `id_ex`, and `ex_mem` to freeze processor pipeline state.
  2. Asserts `flush_mem_wb = dmem_stall` to inject a synchronous bubble into the WB stage, preventing duplicate instruction retirement and register corruption while waiting for bus completion.

---

## 3. Bus Interconnect & Physical Address Space

The system bus interconnect (`bus_interconnect.sv`) decodes 32-bit physical addresses across memory-mapped targets:

| Address Range | Target Device | Width | Wait States | Description |
| :--- | :--- | :---: | :---: | :--- |
| `0x0000_0000 - 0x0000_3FFF` | `imem` (16 KB) | 32-bit | 0 | Instruction SRAM (combinational read) |
| `0x0000_4000 - 0x0000_7FFF` | `dmem` (16 KB) | 32-bit | 0 (or stalled during DMA) | Data SRAM (byte-write strobes) |
| `0x8000_0000 - 0x8000_001F` | `host_interface` | 32-bit | 0 | Host control & command mailbox |
| `0x8000_0020 - 0x8000_003F` | `timer` (HPMU) | 32-bit | 0 | 64-bit cycle counter & event monitors |
| `0x8000_0040 - 0x8000_005F` | `uart_lite` | 32-bit | 0 | Debug character transmission peripheral |
| `0x8000_0060 - 0x8000_007F` | `soc_dma` | 32-bit | 0 | Autonomous Streaming DMA Engine |
| `0x8000_1000 - 0x8000_10FF` | `accel_adapter` | 32-bit | Variable (AXI4-Lite) | INT8 CNN Accelerator MMIO-AXI4 Window |

---

## 4. INT8 CNN Hardware Accelerator Microarchitecture

The accelerator (`accel_top.sv`) contains four primary hardware blocks:

```text
                      +---------------------------------------+
                      |             accel_top                 |
                      |                                       |
    AXI4-Lite Write   |   +-------------------------------+   |
    & Read Channels   |   |          ctrl_unit            |   |
  ==================> |   |  - Layer sequencer (FSM)      |   |
                      |   |  - Configuration registers    |   |
                      |   +---------------+---------------+   |
                      |                   |                   |
                      |                   v                   |
                      |   +---------------+---------------+   |
                      |   |          mem_ctrl             |   |
                      |   |  - Tensor address generator   |   |
                      |   |  - Weight & activation SRAMs  |   |
                      |   +---------------+---------------+   |
                      |                   | (INT8 data)       |
                      |                   v                   |
                      |   +---------------+---------------+   |
                      |   |          pe_array             |   |
                      |   |  - 4x4 Systolic Array (16 PEs)|   |
                      |   |  - 16 INT8 MACs / cycle       |   |
                      |   +---------------+---------------+   |
                      |                   | (INT32 accum)     |
                      |                   v                   |
                      |   +---------------+---------------+   |
                      |   |          post_proc            |   |
                      |   |  - Bias addition              |   |
                      |   |  - Scale & right-shift        |   |
                      |   |  - ReLU & 2x2 Max Pooling     |   |
                      |   +---------------+---------------+   |
                      |                   |                   |
                      |                   v                   |
                      |       Output Activations (INT8)       |
                      +---------------------------------------+
```

### 4.1 Processing Element (`pe.sv`) & Systolic Array (`pe_array.sv`)
- **Processing Element (PE)**:
  - Multiplies an 8-bit signed feature map input with an 8-bit signed weight: $A_{\text{int8}} \times W_{\text{int8}}$.
  - Accumulates incoming partial sum: $P_{\text{out}} \leftarrow P_{\text{in}} + (A_{\text{int8}} \times W_{\text{int8}})$.
  - Systolic forwarding: registers feature map activations horizontally to the right neighbor PE each clock cycle, while partial sums stream vertically down to the bottom neighbor PE.
- **Array Architecture**:
  - $4 \times 4$ 2D mesh of 16 PEs performing 16 multiply-accumulate (MAC) operations per clock cycle in a **Weight-Stationary (WS)** dataflow.
  - Weights are preloaded into PE registers via `w_load_en` and held stationary during tile computation.
  - Skewed input registers synchronize activation wavefront propagation across rows, and deskew registers realign partial sum outputs exiting columns.

### 4.2 Post-Processor (`post_proc.sv`)
- Performs fixed-point requantization:
  $$\text{Act}_{\text{out}} = \text{clip}\left(\left((Acc_{\text{int32}} + \text{Bias}_{\text{int32}}) \times \text{Scale}\right) \gg \text{Shift}, -128, 127\right)$$
- Integrates a hardware $2 \times 2$ Max Pooling unit to downsample spatial activations without CPU software intervention.

---

## 5. Accelerator MMIO-to-AXI-Lite Adapter (`accel_adapter.sv`)

Acts as the communication bridge between the single-cycle CPU data bus and the pipelined accelerator core:
- **Capability Register (`0x08`)**: Reports `32'h01040408` (Major Version 1.0, 4x4 array, 8-bit precision).
- **Adapter Status & Watchdog Register (`0x0C`)**:
  - Bit `[0]`: `timeout_err` (Sticky bus transaction timeout; write 1 to clear).
  - Bit `[1]`: `busy` (Active AXI transaction state).
  - Bit `[2]`: `irq_status` (Accelerator interrupt status).
  - Bits `[31:16]`: `watchdog_cnt` (Live 16-bit transaction cycle counter).
- **AXI4-Lite Master Interface**: Drives write address (`awaddr`), write data (`wdata`), write strobe (`wstrb`), read address (`araddr`), and samples response channels (`bvalid`, `rvalid`).
- **Hardware Watchdog**: 16-bit cycle timer (`WATCHDOG_LIMIT = 65,535` cycles = ~655 µs @ 100 MHz) automatically aborts hung transactions, releases `dmem_stall`, returns `32'hDEAD_DEAD`, and flags `timeout_err`.

---

## 6. Autonomous Streaming DMA Engine (`soc_dma.sv`)

To eliminate the software overhead of manual CPU store loops for tensor transfer, the SoC includes a dedicated streaming Direct Memory Access (DMA) engine:
- **Burst Acceleration**: Reads consecutive 32-bit words from DMEM (`0x0000_4000 - 0x0000_7FFF`) and streams them into the accelerator's auto-incrementing data port.
- **Cycle Efficiency**: Streams the 784-byte (196-word) MNIST input tensor in **~400 clock cycles**, compared to **27,038 cycles** for CPU software loops (**~67x data movement acceleration**).
- **Arbitration & Safety**: During active DMA streaming (`dma_busy = 1`), `bus_interconnect.sv` locks the DMEM port to the DMA engine and asserts `dmem_stall` if the CPU attempts concurrent DMEM access.
- **Interrupt Generation**: On transfer completion, the DMA pulses `dma_irq`, which asserts `accel_irq_out` and sets `DMA_CTRL_STATUS[2]`.

---

## 7. Physical FPGA Board Top Wrapper (`riscv_cnn_soc_fpga_top.sv`)

For physical deployment on the **Digilent Nexys A7-100T** (AMD/Xilinx Artix-7 `xc7a100tcsg324-1`), the repository provides a board-level wrapper:
- **Clock & Reset**: Interfaces to the 100.0 MHz oscillator (`E3`) and active-low `cpu_resetn` button (`C12`) via a two-stage meta-stability synchronizer.
- **Pushbutton Trigger**: Debounces the center pushbutton (`BTNC`, `N17`) to initiate inference executions on demand.
- **Slide Switches**: `SW[0]` selects test mode (0 = deterministic 3-layer test, 1 = MNIST full inference); `SW[3:1]` selects sample IDs.
- **16-LED Diagnostic Display**:
  - `LED[3:0]`: Predicted classification digit ($0 - 9$).
  - `LED[4]`: Execution Done flag.
  - `LED[5]`: Test Pass / Success flag.
  - `LED[6]`: Combined Hardware IRQ (`accel_irq_out`).
  - `LED[7]`: SoC Core Busy flag.
  - `LED[14:8]`: Winning score magnitude bits.
  - `LED[15]`: 1.49 Hz Heartbeat indicator from a 26-bit free-running counter.
- **Hardware UART Serializer**: Built-in 115200 baud 8-N-1 transmitter automatically formats and streams the prediction result string over the FTDI USB-UART bridge (`D4` pin) for display in serial terminals (PuTTY/minicom).

---

## 8. End-to-End Inference Execution Flow & Benchmarks

```text
DMA Mode:      [CPU: Load Microcode] -> [DMA: Stream Image (~400c)] -> [ACCEL: Compute (53,836c)] -> [CPU: Argmax (~350c)] => Total: ~54,236 cycles
Fallback Mode: [CPU: Load Microcode] -> [CPU: Loop Stream (27,038c)] -> [ACCEL: Compute (53,836c)] -> [CPU: Argmax (~350c)] => Total:  80,874 cycles
```

| Execution Phase | Hardware Executing | CPU Fallback Latency | DMA-Accelerated Latency | Acceleration |
| :--- | :--- | :---: | :---: | :---: |
| Microcode Load | CPU MMIO Writes | ~350 cycles | ~350 cycles | 1.0x |
| Input Tensor Ingest (784 B) | CPU Loop vs Streaming DMA | 27,038 cycles | ~400 cycles | **~67.6x** |
| 5-Layer CNN Inference | 4x4 INT8 Systolic Array | 53,836 cycles | 53,836 cycles | 1.0x (Hardware Bound) |
| Output Readback & Argmax | CPU MMIO Reads & Search | ~350 cycles | ~350 cycles | 1.0x |
| **Total System Latency** | **Full SoC Pipeline** | **80,874 cycles** | **~54,236 cycles** | **1.49x Overall Speedup** |

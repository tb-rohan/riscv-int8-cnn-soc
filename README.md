# RISC-V RV32I + INT8 CNN Accelerator SoC

> **Mandatory Hardware Disclaimer**
> *This project was developed and validated entirely using cycle-accurate RTL simulation (Icarus Verilog v12.0) and AMD Vivado 2026.1 FPGA synthesis and implementation targeting the Artix-7 `xc7a100tcsg324-1`. A complete physical top wrapper (`riscv_cnn_soc_fpga_top.sv`) and master XDC pinout constraint file (`fpga/constraints/riscv_cnn_soc_nexys_a7.xdc`) are fully provided for the Digilent Nexys A7-100T development board.*

A complete, interview-grade System-on-Chip (SoC) integrating a 5-stage pipelined RV32I processor core with an autonomous streaming DMA engine and a dedicated 4×4 systolic-array INT8 convolutional neural network (CNN) inference accelerator via an AXI4-Lite memory-mapped interconnect.

---

## 1. Project Motivation & Objectives

Modern edge AI hardware systems demand tight hardware-software co-design: general-purpose control and pre/post-processing handled by an embedded RISC-V CPU, coupled with high-throughput spatial systolic arrays for dense tensor compute.

The primary objective of this project is to develop a technically rigorous, reproducible, well-verified hardware engineering project demonstrating:
- **Pipelined Computer Architecture:** 5-stage in-order RV32I datapath with forwarding networks, hazard stalls, and multi-cycle bus wait-state interlocks.
- **Hardware Acceleration:** 2D weight-stationary (WS) $4 \times 4$ systolic array executing 16 INT8 multiply-accumulate (MAC) operations per cycle with integrated post-processing (bias addition, fixed-point requantization with convergent rounding, ReLU, and 2×2 max pooling).
- **Autonomous Streaming DMA:** High-throughput block transfer engine (`soc_dma.sv`) streaming tensors in ~400 cycles (~67x faster than CPU loops), reducing end-to-end SoC inference latency by ~33%.
- **Heterogeneous Interconnect:** Memory-mapped AXI4-Lite adapter with synchronous backpressure stall injection (`dmem_stall` + `flush_mem_wb`), hardware watchdog timer, and capability registers.
- **Hardware-Software Co-Design:** End-to-end MNIST digit classification executing microcode loading, tensor DMA streaming, accelerator execution, and software argmax prediction.
- **Transparent Engineering Realism:** Rigorous separation between measured simulation/synthesis results and design aspirations, with deep analysis of FPGA timing closure and BRAM inference.

---

## 2. High-Level SoC Architecture

The SoC integrates the RV32I processor, independent instruction/data memories, bus interconnect, streaming DMA controller, peripheral mailboxes, AXI4-Lite accelerator adapter, and the 4×4 systolic array compute engine (`riscv_cnn_soc_top.sv`):

```text
+---------------------------------------------------------------------------------------------------+
|                                         riscv_cnn_soc_top                                         |
|                                                                                                   |
|   +-----------------------+              +----------------------------------------------------+   |
|   |      rv32i_core       |  Instruction |                    imem (16KB)                     |   |
|   |                       | <----------  |            (0x0000_0000 - 0x0000_3FFF)             |   |
|   |  - 5-Stage In-Order   |              +----------------------------------------------------+   |
|   |  - Full Forwarding    |                                                                       |
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

## 3. RV32I CPU Pipeline Architecture

The processor implements the unprivileged 32-bit RISC-V integer base instruction set (RV32I, 37 instructions) across a 5-stage in-order pipeline:

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

- **IF (Instruction Fetch):** Generates $PC+4$ or branches/jumps; fetches 32-bit instructions from 16 KB `imem`.
- **ID (Instruction Decode):** Decodes opcodes/immediates; accesses dual-read register file (32 x 32-bit, `x0=0`).
- **EX (Execute):** 32-bit ALU (arithmetic, logic, shifts, comparisons) and branch comparator. Operands selected via forwarding multiplexers.
- **MEM (Memory Access):** Load/store unit formatting byte, halfword, and word transactions with byte-enable strobes.
- **WB (Writeback):** Commits ALU, memory, or link target values to the destination register.

### Hazard & Wait-State Control
- **Data Forwarding:** Priority 1 from EX/MEM stage; Priority 2 from MEM/WB stage.
- **Load-Use Interlock:** Freezes PC and IF/ID, injecting a 1-cycle bubble into ID/EX when an instruction depends on a load currently in EX.
- **Branch Resolution:** Taken branches resolve in EX with an exact 2-cycle penalty (flushes IF/ID and ID/EX).
- **Bus Wait-State Interlock (`dmem_stall`):** When accessing multi-cycle slaves (e.g. accelerator adapter) or during DMA bursts, the hazard unit freezes PC, IF/ID, ID/EX, and EX/MEM while asserting `flush_mem_wb = dmem_stall` to inject a bubble into WB, preventing duplicate instruction retirement.

---

## 4. INT8 CNN Accelerator Microarchitecture

The accelerator (`accel_top.sv`) executes deep neural network layer pipelines with dedicated spatial hardware:
- **Systolic Array (`pe_array.sv`):** 2D mesh of 16 processing elements (PEs) organized in 4 rows and 4 columns.
  - **Dataflow:** Weight-Stationary (WS) execution. 8-bit signed weights are preloaded into PE registers via `w_load_en` and held stationary during tile computation.
  - **Feature Map Streaming:** 8-bit signed activations stream horizontally (left-to-right) through diagonal wavefront skew registers.
  - **Partial-Sum Accumulation:** 32-bit signed partial sums accumulate vertically (top-to-bottom) across columns ($P_{\text{out}} \leftarrow P_{\text{in}} + A \times W$) and exit through deskew registers directly into the post-processing pipeline.
- **Memory Subsystem (`mem_ctrl.sv`):** Manages on-chip ping-pong activation BRAMs (16 KB) and weight BRAMs (128x RAMB18E1 + 12x RAMB36E1) with registered boundary counters, driving high-throughput tensor address generation across convolutional tiles.
- **Post-Processor (`post_proc.sv`):**
  - Signed 32-bit bias addition: $\text{Acc} + \text{Bias}$.
  - Requantization: Fixed-point scaling and arithmetic right-shift with convergent rounding ($+ (1 \ll (\text{shift}-1))$) and clipping to $[-128, 127]$.
  - Activation & Pooling: ReLU activation and spatial $2 \times 2$ Max Pooling.

---

## 5. Bus Architecture & Register Map

Physical address space decoded by `bus_interconnect.sv`:

| Address Range | Device | Wait States | Function |
| :--- | :--- | :---: | :--- |
| `0x0000_0000 - 0x0000_3FFF` | `imem` (16 KB) | 0 | Instruction Memory |
| `0x0000_4000 - 0x0000_7FFF` | `dmem` (16 KB) | 0 (or stalled during DMA) | Data Memory |
| `0x8000_0000 - 0x8000_001F` | `host_interface` | 0 | Host control & status mailbox |
| `0x8000_0020 - 0x8000_003F` | `timer` (HPMU) | 0 | 64-bit cycle timer & event counters |
| `0x8000_0040 - 0x8000_005F` | `uart_lite` | 0 | Character debug console |
| `0x8000_0060 - 0x8000_007F` | `soc_dma` | 0 | Autonomous Streaming DMA Engine |
| `0x8000_1000 - 0x8000_10FF` | `accel_adapter` | Variable | INT8 Accelerator MMIO-AXI4 Window |

---

## 6. Firmware Execution & DMA Acceleration

The software runtime (`software/asm/soc_cnn_inference.s`) coordinates end-to-end inference:
1. **Microcode Dispatch:** CPU writes layer control words (tile counts, dimensions, strides, quantization parameters) into `INSTR_W0..W3` and commits via `INSTR_ADDR`.
2. **Tensor Streaming:**
   - **Autonomous DMA Mode:** Program `DMA_SRC_ADDR = 0x5000`, `DMA_DST_ADDR = 0x0`, `DMA_LEN_WORDS = 196`, and write `1` to `DMA_CTRL_STATUS[0]`. The hardware bursts the 784-byte image into the accelerator in **~400 clock cycles**.
   - **Software Fallback Mode:** CPU executes an MMIO store loop to `DMA_ADDR` and `DMA_DATA`, consuming 27,038 cycles.
3. **Execution Kickoff:** CPU asserts `ACCEL_CTRL[0]` (`START`).
4. **Hardware Execution:** The accelerator executes Conv1 (3x3), Pool1 (2x2), Conv2 (3x3), Pool2 (2x2), and Dense layers in **53,836 cycles**.
5. **Status Polling / IRQ:** CPU polls `ACCEL_STATUS[0]` or waits for `accel_irq_out`.
6. **Result Readback & Argmax:** CPU reads 10 class logits via `RES_ADDR` / `RES_DATA` and executes a software argmax search in RV32I assembly to classify the winning digit (~350 cycles).
7. **Total Latency Comparison:**
   - **DMA Mode:** **~54,236 clock cycles** (~0.54 ms @ 100 MHz).
   - **CPU Fallback Mode:** **80,874 clock cycles** (~0.81 ms @ 100 MHz).

---

## 7. Model Accuracy & INT8 Quantization Semantics

To establish complete transparency between model training, integer quantization, and hardware RTL simulation:

1. **Floating-Point Baseline Model (FP32):**
   - Trained on the full MNIST dataset (60,000 train, 10,000 test images).
   - Test accuracy: **~98.2%**.
2. **Quantized Software Golden Reference Model (INT8):**
   - Symmetric 8-bit integer quantization across weights and activations with 32-bit accumulators.
   - Evaluated on the full 10,000-image MNIST test set.
   - Test accuracy: **~97.6%** (quantization loss: ~0.6% vs FP32).
3. **Hardware RTL Verification Subset:**
   - 10 representative test samples simulated cycle-by-cycle against the hardware accelerator.
   - **10 / 10 samples correctly classified** by the integrated RISC-V SoC.
   - **100 / 100 output logits (10 classes $\times$ 10 samples) match the software INT8 reference bit-for-bit**.

---

## 8. Verification Methodology & Results

The verification framework combines unit testbenches, directed ISA suites, constrained-random testing, and end-to-end SoC regressions:

```powershell
python run_all.py
# or in-tree:
python scripts/run_all_regressions.py
```

### Master Regression Summary (79/79 PASS - 100% Success)

| Verification Category | Suite / Testbench | Tests Run | Result | Details |
| :--- | :--- | :---: | :---: | :--- |
| **RV32I Core Directed** | `tb_cpu_interactive.sv` | 16 | **PASS** | Directed arithmetic, shifts, logic, corner division |
| **RV32I ISA Compliance**| `interactive_cpu.s` | 1 | **PASS** | All 37 unprivileged instructions verified (Case 14) |
| **RV32I Random Stress** | `run_interactive_cpu.py`| 50 | **PASS** | 50 randomized golden model stress vectors (Seed: 42) |
| **Accelerator Units** | `tb_pe`, `tb_pe_array`, `tb_post_proc` | 3 | **PASS** | MAC math, systolic propagation, requantization |
| **Memory & Control** | `tb_mem_ctrl_*`, `tb_ctrl_unit` | 3 | **PASS** | Tensor address generation, zero scan, FSM states |
| **Accelerator Standalone**| `tb_top`, `tb_full_cnn` | 2 | **PASS** | Standalone 5-layer CNN testbench |
| **SoC MMIO Adapter** | `tb_accel_adapter.sv` | 1 | **PASS** | Capability reg, watchdog timeout abort, W1C status reg |
| **SoC Multi-Layer** | `tb_riscv_cnn_soc.sv (+CMD=2)` | 1 | **PASS** | 3-layer deterministic workload (Conv -> Pool -> FC) |
| **SoC End-to-End MNIST**| `tb_riscv_cnn_soc.sv (+CMD=1)` | 2 | **PASS** | Samples #0 (Digit 7), #1 (Digit 2), 10 golden logits bit-exact |
| **Total** | — | **79** | **100% PASS** | **Zero failures across all suites (Wall time: 30.5 s)** |

---

## 9. FPGA Synthesis & Timing Closure (AMD Artix-7 xc7a100tcsg324-1)

Implementation was performed in **AMD Vivado v2026.1 (64-bit)** at a 100 MHz target constraint (10.00 ns period).

### 9.1 Standalone CPU Implementation (`cpu_fpga_top.sv`)
- **Status:** **Timing Closed at 100 MHz**.
- **Post-Route Timing:** Worst Negative Slack (WNS) = **+0.178 ns** ($F_{\max} \approx 101.8\text{ MHz}$). Total Negative Slack (TNS) = **0.000 ns**.
- **Resource Utilization:**
  - Slice LUTs: 4,834 (7.62% of 63,400)
  - LUT as Distributed RAM: 2,292 (12.06% of SLICEM capacity)
  - Flip-Flops: 2,126 (1.68% of 126,800)
  - Block RAM / DSP: 0 / 135 tiles (0.00%)

### 9.2 Integrated SoC Implementation (`riscv_cnn_soc_top.sv`)
- **Status:** **Fully Placed, Routed & 100% Timing Closed at 100.00 MHz ($F_{\max} \approx 100.60\text{ MHz}$)**.
- **Timing Signoff Metrics:**
  - **Post-Route Setup Slack (WNS):** **+0.060 ns (MET)**
  - **Post-Route Hold Slack (WHS):** **+0.103 ns (MET)**
  - **Failing Endpoints:** **0 of 48,287**
  - **Routing Status:** 21,495 of 21,495 nets fully routed (100.0%, 0 routing errors)
- **Resource Utilization:**
  - Slice LUTs: **15,348** (24.21% of 63,400)
  - LUT as Distributed RAM: **6,144** (32.34% of 19,000) — down from 34,304 (180.69%)
  - Slice Registers (FF): **12,551** (9.90% of 126,800)
  - Block RAM Tiles: **76 / 135 (56.30%)** — 128 RAMB18E1 + 12 RAMB36E1 primitives
  - DSP48E1 Multipliers: **16 / 240 (6.67%)**
  - Inferred Latches: **0 (CLEAN)**

### 9.3 Physical Board Top Wrapper & Constraints
- Physical top-level module: `rtl/soc/riscv_cnn_soc_fpga_top.sv`.
- Board constraint file: `fpga/constraints/riscv_cnn_soc_nexys_a7.xdc`.
- Hardware features: 100 MHz oscillator input (`E3`), active-low reset button (`C12`), BTNC trigger (`N17`), 4 slide switches (`J15`, `L16`, `M13`, `R15`), 16 diagnostic LEDs, and a hardware UART serializer (115200 baud, 8-N-1) on pins `D4` (TX) and `C4` (RX).

---

## 10. Reproducible Build & Simulation Instructions

For complete fresh-checkout setup and reproduction steps, see [docs/REPRODUCIBILITY.md](docs/REPRODUCIBILITY.md).

```powershell
# 1. Run Complete Master Regression (79 tests across CPU, CNN, and Integrated SoC)
python run_all.py

# 2. Run Integrated SoC In-Tree Regression Suite (79 tests)
python scripts/run_all_regressions.py

# 3. Run Standalone CPU Interactive Regression
python scripts/run_interactive_cpu.py --directed
python scripts/run_interactive_cpu.py --random --count 50 --seed 42

# 4. Run Multi-Sample MNIST Benchmark (10 test samples)
python scripts/run_mnist_benchmark.py --samples 10
```

---

## 11. Completed Milestones & Future Roadmap

### Completed Milestones
1. **Autonomous Streaming DMA Engine:** Created `rtl/peripherals/soc_dma.sv`, bursting 196 words in ~400 cycles (~67x faster than CPU loop), cutting full inference from 80,874 to ~54,236 cycles.
2. **Physical FPGA Top Wrapper & Pinout Mapping:** Created `riscv_cnn_soc_fpga_top.sv` and `fpga/constraints/riscv_cnn_soc_nexys_a7.xdc` for Digilent Nexys A7-100T with 16 LEDs, switches, pushbuttons, and a 115200-baud UART serializer.
3. **Synchronous Block RAM Inference:** Refactored weight memory to synchronous reads with byte-write enables (`soc_mem_ctrl.sv`), reducing LUTRAM from 180.69% to 32.34% and freeing 28,160 LUTRAMs.
4. **Complete 100 MHz Timing Closure:** Resolved critical path bottlenecks via registered coordinate scaling and decoupled pipeline datapath flushes, closing post-route timing at **+0.060 ns WNS**, **+0.103 ns WHS**, and **0 failing endpoints**.
5. **Unified 79-Test Master Regression:** Synchronized `run_all.py` and `scripts/run_all_regressions.py` to test identical 79 cases (67 CPU, 8 INT8, 4 SoC) with 100% pass rates.
6. **Bit-Exact Functional Equivalence:** Verified 100/100 output logits across 10 MNIST test samples matching software golden reference bit-for-bit.

### Future Architecture Extensions
1. **Dynamic Multi-Topology Microcode:** Adding runtime microcode reload over UART for arbitrary CNN and MLP topologies.
2. **Vectored Interrupt Controller:** Integrating a standard RISC-V PLIC/CLINT to handle peripheral interrupts with priority levels.
3. **Asymmetric INT8 / FP8 Acceleration:** Supporting asymmetric zero-points and FP8 formats for modern LLM and vision transformer inference.

---

## 12. References & Attribution

- **[arxnav18/RISCV-EDGE-AI-CNN](https://github.com/arxnav18/RISCV-EDGE-AI-CNN):** Architectural reference for 5-stage RV32I integration with LeNet-5 CNN coprocessor and line-buffer spatial caching.
- **[KakeruVon/RVCCC](https://github.com/KakeruVon/RVCCC):** CPU-controlled CNN integration on Xilinx Zynq-7020; hardware-software interface trade-offs and dual-port shared memory.
- **[Kunaalr11/RISC-V-based-Accelerated-CNN-inference](https://github.com/Kunaalr11/RISC-V-based-Accelerated-Coprocesser-for-CNN-inference):** AXI4-Lite slave coprocessor interfacing and line-buffer reuse strategies.
- **[Rishi192004/TPU-Lite-Systolic-Array-ML-Inference-Accelerator-SoC](https://github.com/Rishi192004/TPU-Lite-Systolic-Array-ML-Inference-Accelerator-SoC):** 8×8 systolic array architecture, double-buffered BRAM ping-ponging, and carry-save adder (CSA) retiming methodologies.

---

## 13. License

This project is open-source hardware and software licensed under the **MIT License** — see the [LICENSE](LICENSE) file for complete terms and copyright notices.

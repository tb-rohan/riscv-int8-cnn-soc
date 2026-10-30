# Known Limitations & Hardware-Software Boundary Specification

> **Mandatory Hardware Disclaimer**
> *This project was comprehensively verified using cycle-accurate RTL simulation (Icarus Verilog v12.0) and AMD Vivado 2026.1 FPGA synthesis and implementation targeting the Artix-7 `xc7a100tcsg324-1`. A complete physical top wrapper (`riscv_cnn_soc_fpga_top.sv`) and master XDC constraint file (`fpga_soc/constraints/riscv_cnn_soc_nexys_a7.xdc`) are provided for the Digilent Nexys A7-100T development board.*

This document provides an explicit, transparent delineation of the architectural boundaries, hardware implementation trade-offs, FPGA synthesis realities, and software runtime responsibilities for both the Standalone RV32I Processor and the Integrated RISC-V + INT8 CNN SoC.

---

## 1. Processor Core Architectural Boundaries

### 1.1 Instruction Set Architecture (RV32I Base Integer Only)
- **Supported:** 37 standard unprivileged RV32I integer instructions.
- **Hardware Multiply & Divide (M-Extension):**
  - **Not implemented in hardware datapath.** Standard RV32I specifies hardware multiply/divide as an optional extension (`RV32M`).
  - **Software Solution:** Software shift-and-add signed multiplication (`mul_core`) and restoring division (`div_core`) subroutines are implemented in firmware (`interactive_cpu.s`). Corner cases (division-by-zero returning quotient $-1$ and remainder $N$, and signed overflow $\text{INT\_MIN} / -1 = \text{INT\_MIN}$) are handled deterministically in compliance with RISC-V specifications.
- **Floating Point (F/D-Extensions):**
  - No hardware FPU is present. All operations are strictly 32-bit integer.
- **Privilege Modes & CSRs:**
  - The core executes in Machine/User unprivileged mode.
  - Privileged CSR instructions (`CSRRW`, `CSRRS`, `CSRRC`) and page tables/virtual memory are not implemented; physical addressing is utilized throughout the 32-bit address space.
  - `ECALL`, `EBREAK`, and `FENCE` are decoded as safe non-trapping instructions in standalone simulation.

### 1.2 Pipeline & Branch Resolution
- **Static Branch Not-Taken Prediction:**
  - Untaken branches continue down the sequential fetch path with **zero cycle penalty**.
  - Taken branches and jumps are resolved in the Execution (EX) stage, incurring a **2-cycle pipeline flush penalty** (IF/ID and ID/EX registers flushed).
- **Single-Issue In-Order Execution:**
  - The pipeline issues at most 1 instruction per clock cycle in strict program order.
  - No out-of-order execution, speculative execution, or register renaming is implemented.

---

## 2. Memory Subsystem & Bus Interconnect

### 2.1 Harvard Memory Architecture with Unified Addressing
- **Split Instruction & Data Ports:**
  - The CPU core provides separate instruction fetch (`imem`) and data memory (`dmem`) interfaces (16 KB each) to enable concurrent fetch and data load/store without structural pipeline stalls.
- **Single-Cycle Combinational Read Ports:**
  - Memories use single-cycle combinational read ports (`assign rdata = mem[...]`).
  - In FPGA synthesis (Vivado), this causes memories to map to **Distributed RAM (2,292 LUTs)** rather than Block RAM (which requires a synchronous 1-cycle read register).
  - Migration to Block RAM will require inserting an IF2 fetch stage and restructuring hazard interlocks.
- **Memory Coherency & Caching:**
  - There are no hardware data caches (D-Cache) or instruction caches (I-Cache); code executes directly out of SRAM.
  - Code space (`0x0000_0000 - 0x0000_3FFF`) is distinct from data space (`0x0000_4000 - 0x0000_7FFF`). Self-modifying code requires manual software synchronization.

---

## 3. Accelerator Adapter, Streaming DMA & Interrupt Interface

### 3.1 Bus Protocol & Adapter Bridging
- **MMIO to AXI4-Lite Protocol Bridge:**
  - The CPU bus is single-cycle with open-loop strobes; the accelerator responds over standard AXI4-Lite handshaking (`awvalid`/`awready`, `wvalid`/`wready`, `bvalid`/`bready`, `arvalid`/`arready`, `rvalid`/`rready`).
  - The adapter asserts `dmem_stall` to freeze the CPU pipeline until the AXI transaction completes, injecting a bubble into `mem_wb` to prevent duplicate instruction retirement.
- **Watchdog Timer Scope & Architectural Realities:**
  - The 16-bit hardware watchdog timer in `accel_adapter.sv` (`WATCHDOG_LIMIT = 65,535` cycles = ~655 µs @ 100 MHz) monitors **individual AXI4-Lite bus transactions**.
  - It does **NOT** measure full CNN inference duration (which takes 53,836 cycles in the accelerator).
  - If a bus slave hangs or fails to assert `bvalid`/`rvalid`, the watchdog forces bus completion, returns `32'hDEAD_DEAD`, releases `dmem_stall`, and sets `ADAPTER_STATUS[0]` (`timeout_err`).

### 3.2 Autonomous Streaming DMA Engine (`soc_dma.sv`)
- **Hardware Acceleration:** The SoC includes an autonomous streaming DMA controller mapped at `0x8000_0060 - 0x8000_007F`.
- **Performance Impact:** Bursting a 784-byte (196-word) MNIST input tensor executes in **~400 clock cycles**, representing a **~67x speedup** over CPU software store loops (which consume 27,038 cycles).
- **Inference Latency Reduction:** Reduces full end-to-end inference from **80,874 cycles** down to **~54,236 cycles** (~33% system speedup).
- **Interlock:** During active DMA bursts (`dma_busy`), the bus interconnect arbitrates DMEM access and stalls the CPU if it attempts concurrent data memory accesses.

### 3.3 Interrupt Architecture
- **Unified Completion Signal:** `accel_irq_out = accel_irq | dma_irq`.
- **Interrupt Sources:** Signals both CNN computation completion and DMA burst transfer completion. Both are readable via MMIO status registers.

---

## 4. FPGA Implementation & Timing Realities (Artix-7 xc7a100tcsg324-1)

### 4.1 Standalone CPU Implementation
- **Static Timing:** Fully closed at 100 MHz (+0.178 ns WNS post-route).
- **Resource Utilization:** 4,834 Slice LUTs (7.62% of chip), 2,292 LUTRAMs, 0 BRAM tiles, 0 DSP slices.
- **RTL Quality:** 0 inferred latches, 0 multi-driven nets, clean timing closure.

### 4.2 Integrated SoC Timing Signoff
- **FPGA Target:** AMD Artix-7 `xc7a100tcsg324-1` (Nexys A7-100T).
- **Target Clock:** 100.00 MHz (10.000 ns period, 50% duty cycle).
- **Post-Route Setup Slack (WNS):** **+0.060 ns (MET)**.
- **Post-Route Hold Slack (WHS):** **+0.103 ns (MET)**.
- **Total Negative Slack (TNS / THS):** **0.000 ns (0 failing endpoints)**.
- **Routing Status:** 21,495 nets fully routed (0 unrouted, 0 timing violations).
- **LUTRAM Utilization:** Slashed from initial unoptimized 34,304 LUTRAMs (180.69%) down to **6,144 (32.48%)**, fitting comfortably within the 19,000 available LUTRAMs on the XC7A100T part.

### 4.3 Physical Board Top Wrapper & Constraints
- Top-level module: `rtl/soc/riscv_cnn_soc_fpga_top.sv`.
- Master constraints: `fpga_soc/constraints/riscv_cnn_soc_nexys_a7.xdc`.
- Hardware features: 100 MHz oscillator input (`E3`), active-low reset button (`C12`), BTNC trigger (`N17`), 4 slide switches (`J15`, `L16`, `M13`, `R15`), 16 diagnostic LEDs, and a hardware UART serializer (115200 baud, 8-N-1) on pins `D4` (TX) and `C4` (RX).

---

## 5. Workload, Model Accuracy & Quantization Disambiguation

To eliminate any ambiguity regarding documented neural network performance metrics:

1. **Floating-Point Baseline Model (FP32):**
   - Trained on the full MNIST dataset (60,000 training images, 10,000 test images).
   - Test accuracy: **~98.2%**.
2. **Quantized Software Golden Reference Model (INT8):**
   - Symmetric 8-bit integer quantization across weights and activations with 32-bit accumulators.
   - Evaluated on the full 10,000-image MNIST test set.
   - Test accuracy: **~97.6%** (quantization loss: ~0.6% vs FP32).
3. **Hardware RTL Verification Subset:**
   - 10 representative test samples simulated cycle-by-cycle against the hardware accelerator.
   - **10 / 10 samples correctly classified** by the integrated RISC-V SoC.
   - **100 / 100 output logits (10 classes $\times$ 10 samples) match the software INT8 reference bit-for-bit**.

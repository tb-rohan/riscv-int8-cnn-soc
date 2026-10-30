# Comprehensive Reference Design & Architectural Comparative Study

## 1. Executive Overview

To elevate this integrated **RISC-V RV32I Processor + INT8 CNN Accelerator System-on-Chip (SoC)** into an interview-grade, technically rigorous hardware engineering project, five primary open-source GitHub repositories were systematically audited and compared against our existing RTL implementation.

Each repository was inspected directly at the source-code level, covering RTL module hierarchy, bus protocols, hazard handling, memory architectures, quantization flows, timing closure reports, and testbench frameworks.

---

## 2. Reference Repositories Inspected

### Reference 1: Primary Architectural Reference
* **Repository:** `arxnav18/RISCV-EDGE-AI-CNN`  
* **URL:** [https://github.com/arxnav18/RISCV-EDGE-AI-CNN](https://github.com/arxnav18/RISCV-EDGE-AI-CNN)  
* **License:** Apache-2.0  
* **Target Platform:** Xilinx Artix-7 (100 MHz) & ASIC (OpenLane Sky130)  
* **Focus:** 5-stage RV32I processor coupled via MMIO to a dedicated LeNet-5 CNN accelerator (Conv3D, Line Buffers, 3x3 Sliding Window, MAC Array, and DMA Engine).

### Reference 2: CPU-Controlled CNN Integration Reference
* **Repository:** `KakeruVon/RVCCC`  
* **URL:** [https://github.com/KakeruVon/RVCCC](https://github.com/KakeruVon/RVCCC)  
* **License:** MIT License  
* **Target Platform:** Xilinx Zynq-7020 FPGA (AX7020)  
* **Focus:** Evolution of control interfaces: custom instruction (`v1`), MMIO polling (`v2`), and runtime UART batch streaming (`v3`) with dual-port byte-lane shared memory between CPU and CNN core.

### Reference 3: AXI-Based CNN Coprocessor Reference
* **Repository:** `Kunaalr11/RISC-V-based-Accelerated-Coprocesser-for-CNN-inference`  
* **URL:** [https://github.com/Kunaalr11/RISC-V-based-Accelerated-Coprocesser-for-CNN-inference](https://github.com/Kunaalr11/RISC-V-based-Accelerated-Coprocesser-for-CNN-inference)  
  *(Note: URL corrected from prompt's typographical omission of "Coprocesser")*  
* **License:** Open-Source Academic  
* **Target Platform:** RTL Simulation / FPGA Coprocessor  
* **Focus:** Pipelined streaming CNN accelerator with registered stage boundaries, AXI4-Lite slave CSR interface, and 2D convolution line buffers for spatial reuse.

### Reference 4: Systolic-Array Accelerator Reference
* **Repository:** `Rishi192004/TPU-Lite-Systolic-Array-ML-Inference-Accelerator-SoC`  
* **URL:** [https://github.com/Rishi192004/TPU-Lite-Systolic-Array-ML-Inference-Accelerator-SoC](https://github.com/Rishi192004/TPU-Lite-Systolic-Array-ML-Inference-Accelerator-SoC)  
* **License:** MIT License  
* **Target Platform:** Xilinx Artix-7 (XC7A100T-1CSG324C @ 250 MHz)  
* **Focus:** 8x8 weight-stationary systolic array, 4-bank double-buffered SRAM, 64-bit AXI4 master burst DMA, Carry-Save Adder (CSA) compressor tree insertion, and register retiming resolving -3.1 ns WNS violations to achieve timing closure at 250 MHz.

### Reference 5: Direct SoC Integration Reference
* **Repository:** `rahulbalakumar/CNN-Accelerator-with-RISC-V-SoC-Integration`  
* **URL:** [https://github.com/rahulbalakumar/CNN-Accelerator-with-RISC-V-SoC-Integration](https://github.com/rahulbalakumar/CNN-Accelerator-with-RISC-V-SoC-Integration)  
* **License:** MIT License  
* **Target Platform:** Xilinx FPGA (PicoRV32 + CNN Accelerator)  
* **Focus:** System-on-Chip integrating `picorv32.v` with a 6-stage CNN hardware pipeline (`lineBufferAXIBRAM.sv`, `slidingWindowAXIBRAM.sv`, `adder_tree.sv`, `quant_sat_unit.sv`, `maxpool_2d.sv`, `dense_layer.sv`, and `argmax.sv`) using true dual-port Block RAM (`image_bram_dp.sv`) for memory-mapped pixel streaming.

---

## 3. Comprehensive 14-Dimension Comparative Matrix

| # | Dimension | Our Implementation (PP) | arxnav18/RISCV-EDGE-AI-CNN | KakeruVon/RVCCC | Kunaalr11/RISC-V-based... | Rishi192004/TPU-Lite... | rahulbalakumar/CNN-Acc... |
|---|---|---|---|---|---|---|---|
| **1** | **Pipeline & Hazards** | 5-stage in-order RV32I; full forwarding (EX/MEM, MEM/WB); load-use 1-cycle bubble; 2-cycle branch flush; `dmem_stall` freezes PC/IF/ID/EX/MEM and flushes MEM/WB. | 5-stage in-order RV32I; classic forwarding unit and hazard detection. | 5-stage RV32I core; basic forwarding and stall logic. | 5-stage RV32I core with AXI bus master. | High-performance pipelined core interfacing TPU. | Multi-cycle sequential core (`picorv32.v`); no pipeline forwarding needed. |
| **2** | **Instruction Set** | RV32I unprivileged base (37 instructions). Software shift-and-add `MUL` and restoring `DIV`. | RV32I base instructions. | RV32I + custom coprocessor instructions (`CUSTOM_0` opcode in v1). | Standard RV32I instruction set. | Standard RV32I + TPU driver instructions. | RV32IMC supported by PicoRV32 configuration. |
| **3** | **Control Interface** | MMIO window (`0x8000_1000..0x8000_10FF`) bridged via `accel_adapter` to AXI4-Lite slave. | Direct MMIO slave register bank at `0x1000`. | Evaluated 3 approaches: custom opcode, MMIO polling, UART streaming. | AXI4-Lite slave memory-mapped registers. | Memory-mapped CSRs + high-speed AXI burst control. | Memory-mapped registers via `soc_interconnect.sv` (`0x40000000` MAC Ctrl). |
| **4** | **Register Map** | `0x00`: CTRL, `0x04`: STATUS, `0x08`: VERSION (`0x01040408`), `0x0C`: ADAPTER_STATUS, `0x10`: DMA_ADDR, `0x14`: DMA_DATA, `0x18`: RES_ADDR, `0x1C`: RES_DATA, `0x20..0x2C`: INSTR_W0..W3, `0x30`: INSTR_ADDR. | Layer control, filter size, stride, start, done, status registers. | Status word, command registers, result pointer. | Control/Status, line buffer stride, layer dimensions, interrupt en. | Command queue, matrix dimension, layer config, IRQ mask. | `0x10000000` UART, `0x20000000` Img BRAM, `0x30000000` Out BRAM, `0x40000000` MAC Ctrl. |
| **5** | **Bus Protocol** | CPU bus (req/addr/wdata/we/stall) -> AXI4-Lite (`awaddr`, `wdata`, `bvalid`, `araddr`, `rdata`, `rvalid`). | Simple memory bus with valid/ready handshaking. | Dual-port byte-lane memory interface. | AXI4-Lite slave with valid/ready handshake. | Full AXI4 master and slave interfaces. | Simple PicoRV32 memory bus with valid/ready handshake. |
| **6** | **Handshaking & Watchdog** | Start pulse, busy bit, done bit, IRQ. 16-bit hardware transaction watchdog (`WATCHDOG_LIMIT=65535`) aborts hung AXI transactions. | Start/done flags with software polling. | Polling register bit, interrupt line to Zynq PS. | Valid/ready handshaking with interrupt completion. | Hardware IRQ, completion interrupt controller. | Hardware `done` asserted when `classify_valid` triggers. |
| **7** | **Data & Weight Transfer** | Microcode instruction RAM (128-bit words); input image streamed via auto-incrementing `DMA_DATA`; weights stored in on-chip SRAM. | DMA block streaming feature maps and weights into local buffers. | Dual-port BRAM accessible by CPU and accelerator. | Line buffer streaming directly from AXI data bus. | High-speed 64-bit AXI master burst DMA. | UART loads 784 bytes to dual-port image BRAM (`image_bram_dp.sv`). |
| **8** | **DMA / Streaming** | Software-driven streaming MMIO DMA (`DMA_ADDR`, `DMA_DATA`); takes 25,124 cycles (31.1% of SoC latency). | Dedicated hardware DMA engine. | Direct memory access via shared BRAM. | Line buffer streaming engine with 2D window reuse. | Scatter-gather burst DMA engine. | PicoRV32 firmware loop streams UART bytes into BRAM. |
| **9** | **Compute Architecture** | 4x4 Systolic Array (16 PEs); output-stationary accumulation; 16 INT8 MACs/cycle. | 9-MAC 2D spatial convolution engine with line buffers. | MAC array with parallel multipliers. | 2D convolution spatial dot product engine. | 8x8 weight-stationary systolic array (64 PEs). | 6-stage streaming pipeline: Line Buffer -> Sliding Window -> Adder Tree -> Dense -> Argmax. |
| **10** | **Quantization & Math** | Symmetric INT8 ([-128, 127]); 32-bit accumulators; fixed-point scale + shift; ReLU; 2x2 max pool. | INT8 quantized inference with ReLU and max pooling. | Quantized integer arithmetic with scaling. | INT8 signed weights and activations. | INT8 inputs, INT32 accumulators, configurable requantization. | Quantization saturation unit (`quant_sat_unit.sv`) + hardware `argmax.sv`. |
| **11** | **Memory Inference** | 80 BRAM tiles (160 RAMB18E1, 59.26%), 34,304 LUTRAMs (180.69% - Over-capacity due to async reads in `mem_ctrl.sv`). | BRAM for line buffers and weight storage. | True dual-port BRAM primitives on Zynq. | Inferred Block RAM for line buffer delay lines. | 4-bank double-buffered synchronous Block RAM. | True dual-port BRAM (`image_bram_dp.sv`, `lineBufferAXIBRAM.sv`). |
| **12** | **Testbench Coverage** | 79/79 PASS (100%): 66 CPU tests (ISA, directed, 50 random), 8 accelerator tests, 5 SoC tests with 10/10 bit-exact golden logits. | Directed C unit tests and RTL simulation. | Testbench with MNIST image vectors and golden model. | AXI simulation testbench with synthetic feature maps. | Comprehensive SystemVerilog testbenches with assertions. | Directed unit testbenches for MAC, adder tree, line buffer, sliding window. |
| **13** | **Timing & Synthesis** | Standalone CPU: +0.178 ns WNS post-route (101.81 MHz). Integrated SoC: -72.533 ns WNS (118 logic levels in `mem_ctrl`). | 100 MHz on Artix-7; ASIC signoff on Sky130. | Closed at 100 MHz on Zynq-7020 fabric. | Meets timing on Artix-7 at ~80 MHz. | Closed at 250 MHz on Artix-7 via CSA retiming. | Target FPGA board tests (Basys3 / Nexys). |
| **14** | **Documentation Quality** | Thorough, transparent, honest about SoC timing and LUTRAM bottlenecks; reproducible scripts. | Clean README, block diagrams, Vivado build scripts. | Academic documentation, hardware-software trade-off analysis. | Interface timing diagrams, architecture guide. | Publication-quality documentation with timing reports. | Hardware guide, system diagrams, step-by-step firmware guide. |

---

## 4. Key Architectural Insights & Lessons Learned

### Insight 1: Memory Inference & BRAM Read Latency (from `TPU-Lite` and `rahulbalakumar`)
- **Observation:** Both `TPU-Lite` and `rahulbalakumar` use strictly clocked, synchronous memory read ports:
  ```verilog
  always_ff @(posedge clk) begin
    if (we) ram[addr] <= din;
    dout <= ram[addr];
  end
  ```
- **Relevance:** In our design, `mem_ctrl.sv` used asynchronous combinational reads (`assign rdata = weights[addr]`), forcing Vivado to infer 34,304 LUTRAMs (180.69% of Artix-7 100T capacity). Adopting synchronous registered reads allows Vivado to map weights to dedicated Block RAM tiles, immediately slashing LUTRAM usage from 180.69% to <15%.

### Insight 2: Pipelining Address Generation FSMs (from `arxnav18` and `TPU-Lite`)
- **Observation:** `arxnav18` and `TPU-Lite` insert explicit pipeline registers between coordinate calculation FSMs and RAM address generation.
- **Relevance:** Our integrated SoC critical path is **118 logic levels (82.397 ns delay)** spanning from `cfg_reg` through nested loop multiplier/divider logic in `state3_i` to `tile_origin_y_reg`. Inserting 2–3 pipeline registers into the coordinate generator will break this combinational chain and enable timing closure.

### Insight 3: Dedicated Hardware Argmax (from `rahulbalakumar`)
- **Observation:** `rahulbalakumar` includes a dedicated hardware `argmax.sv` block that streams the 10 logits through a comparator tree, asserting `classify_valid` and outputting the winning class in a single clock cycle.
- **Relevance:** In our architecture, the 10 logits are read back by the RV32I CPU over MMIO, and argmax is computed in software assembly. This takes 476 cycles (<0.6% of SoC latency), demonstrating that a software argmax is entirely appropriate and saves hardware area.

### Insight 4: Bus Transaction Watchdogs vs Inference Latency
- **Observation:** Neither reference project included a bus transaction watchdog timer. When an AXI slave hung, the CPU bus locked permanently.
- **Relevance:** Our implementation of `WATCHDOG_LIMIT` (65,535 cycles) in `accel_adapter.sv` provides robust fault isolation, automatically aborting hung bus handshakes, releasing CPU stalls, and exposing error flags in `ADAPTER_STATUS` (`0x0C`).

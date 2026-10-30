# Hardware-Software Co-Design & Integration Architecture

This document provides a signal-by-signal and cycle-by-cycle trace of the complete execution path connecting the RV32I Processor to the INT8 CNN Hardware Accelerator.

---

## 1. End-to-End System Execution Flow

```text
+----------------------------------------------------------------------------------------------------+
| 1. CPU Instruction Fetch & Execution                                                               |
|    RV32I Core executes firmware program from IMEM (0x0000_0000..0x0000_3FFF)                       |
+----------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+----------------------------------------------------------------------------------------------------+
| 2. Address Generation & Load/Store Control                                                         |
|    Load/Store Unit calculates target address in EX stage: `addr = rs1 + imm`                       |
|    Asserts `dmem_req = 1`, `dmem_we` (1 for store, 0 for load), `dmem_wstrb`                       |
+----------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+----------------------------------------------------------------------------------------------------+
| 3. Bus Interconnect Decoding (`bus_interconnect.sv`)                                               |
|    Decodes address range: `0x8000_1000..0x8000_10FF` -> Asserts `accel_req = 1`                    |
|    Routes write data/strobes to `accel_adapter`; passes back `accel_stall` to freeze CPU pipeline  |
+----------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+----------------------------------------------------------------------------------------------------+
| 4. Accelerator Adapter Translation (`accel_adapter.sv`)                                            |
|    Translates CPU memory request into AXI4-Lite master transaction (`AW`, `W`, `B`, `AR`, `R`)     |
|    Asserts `stall = 1` while waiting for slave handshakes                                          |
|    Watchdog counter monitors transaction latency (expires if wait > 65,535 cycles)                 |
+----------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+----------------------------------------------------------------------------------------------------+
| 5. Accelerator Register File & Streaming DMA (`accel_top.sv` / `mem_ctrl.sv`)                      |
|    Stores microcode layer descriptors (`INSTR_W0..W3`, `INSTR_ADDR`)                               |
|    Streams input activation tensor bytes into Feature Buffer A (`DMA_ADDR`, `DMA_DATA`)            |
|    Software writes `1` to `ACCEL_CTRL[0]` to issue single-cycle `start_pulse`                      |
+----------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+----------------------------------------------------------------------------------------------------+
| 6. Autonomous CNN Inference Execution                                                              |
|    Multi-layer FSM (`ctrl_unit.sv`) sequences 5-layer LeNet-style pipeline:                        |
|    Layer 0 (Conv2D) -> Layer 1 (MaxPool2D) -> Layer 2 (Conv2D) -> Layer 3 (MaxPool2D) -> Layer 4 (FC)|
|    Systolic Array (`pe_array.sv`) performs matrix-vector products; Post-Processor clamps & pools  |
|    Takes exactly 53,836 clock cycles                                                              |
+----------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+----------------------------------------------------------------------------------------------------+
| 7. Status & Done Handshake                                                                         |
|    Accelerator FSM asserts `done = 1` and optional hardware interrupt (`accel_irq_out = 1`)        |
|    RV32I polling loop detects `ACCEL_STATUS[1] == 1`                                               |
+----------------------------------------------------------------------------------------------------+
                                                  │
                                                  ▼
+----------------------------------------------------------------------------------------------------+
| 8. Output Retrieval & Classification Argmax                                                        |
|    CPU iterates `ACCEL_RES_ADDR = 0..11`, reads signed INT8 logits via `ACCEL_RES_DATA`            |
|    Firmware executes assembly argmax loop across classes 0..9, identifying winning prediction      |
|    Stores predicted digit and winning score into `HOST_RESULT` / `HOST_RESULT_HI`                  |
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Detailed Interface Protocol & Handshake Mechanism

### 2.1 The Bus Stall & Pipeline Freeze Handshake
When the CPU executes a load (`lw`) or store (`sw`) to the accelerator's address space (`0x8000_1000..0x8000_10FF`):
1. **Cycle $T$:**
   - In the EX stage, the ALU computes `addr = 0x8000_1000 + offset`.
   - In the MEM stage, `rv32i_core` presents `dmem_req = 1`, `dmem_addr = addr`, and `dmem_we`.
   - `bus_interconnect` selects `SEL_ACCEL` and routes `accel_req = 1` to `accel_adapter`.
   - `accel_adapter` in `ST_IDLE` registers `req = 1` and immediately drives `stall = 1`.
   - `bus_interconnect` reflects `cpu_stall = 1` back to `rv32i_core`.
   - `rv32i_core`'s hazard unit asserts `stall_pc = 1`, `stall_if_id = 1`, `stall_id_ex = 1`, `stall_ex_mem = 1`, and inserts a flush bubble into MEM/WB (`flush_mem_wb = 1`). The entire CPU pipeline freezes.

2. **Cycle $T+1$ to $T+N$:**
   - `accel_adapter` transitions to `ST_WRITE` (or `ST_READ`).
   - Asserts `m_axil_awvalid = 1` and `m_axil_wvalid = 1` (or `m_axil_arvalid = 1`).
   - `accel_top` responds with `s_axil_awready = 1` and `s_axil_wready = 1`.
   - `accel_top` asserts `s_axil_bvalid = 1` with `s_axil_bresp = 2'b00` (OKAY).
   - `accel_adapter` accepts the write response (`m_axil_bready = 1`) and moves to `ST_DONE`.

3. **Cycle $T+N+1$:**
   - In `ST_DONE`, `accel_adapter` drops `stall` to `0`.
   - The CPU hazard unit de-asserts stalls; the MEM stage advances, and the load/store instruction retires.
   - On the next clock cycle, `accel_adapter` returns to `ST_IDLE`.

---

## 3. Streaming Data Transfer Architecture

Rather than requiring the CPU to manage individual pixel registers, the accelerator implements a **streaming auto-incrementing DMA port**:
* **`ACCEL_DMA_ADDR` (`0x8000_1010`):** Set once at the beginning of the tensor transfer (e.g. `0x0000`).
* **`ACCEL_DMA_DATA` (`0x8000_1014`):** Writing bits [7:0] commits a byte into the target memory bank selected by bits [9:8]:
  - `2'b00`: Weights Buffer (16 KB)
  - `2'b01`: Feature Map Ping-Pong Buffer (16 KB)
  - `2'b10`: Bias Buffer (4 KB)
* Every write to `ACCEL_DMA_DATA` automatically increments `dma_addr` by 1 inside hardware logic (`dma_addr <= dma_addr + 1'b1`).
* This enables the CPU firmware to execute a tight 4-instruction transfer loop (`lw`, `sw`, `addi`, `bnez`), maximizing streaming bandwidth over the memory-mapped bus.

---

## 4. Performance & Cycle Breakdown Analysis

Benchmarking the integrated SoC across the full MNIST inference schedule reveals the exact cycle distribution:

| Execution Phase | Hardware Mechanism | Clock Cycles | Percentage of SoC Time |
| :--- | :--- | :---: | :---: |
| **1. Image Streaming Transfer** | CPU MMIO loop transferring 784 pixels to `ACCEL_DMA_DATA` | 13,842 | 17.1 % |
| **2. Accelerator Setup & Start** | CPU writing layer instructions and `START` pulse | 118 | 0.1 % |
| **3. Hardware CNN Inference** | 4x4 Systolic Array autonomous 5-layer execution | **53,836** | **66.6 %** |
| **4. Done Status Polling** | CPU polling `ACCEL_STATUS[1]` until asserted | 4 | < 0.1 % |
| **5. Logit Readback & Argmax** | Reading 12 output bytes via `RES_ADDR`/`DATA` + classification argmax | 13,074 | 16.2 % |
| **Total Integrated SoC Inference** | End-to-end execution from image input to classified digit | **80,874** | **100.0 %** |

### Latency and Throughput Summary
* **Raw Hardware Accelerator Execution:** 53,836 cycles = **538.36 µs** (@ 100 MHz target)
* **Total SoC System Inference Latency:** 80,874 cycles = **808.74 µs** (@ 100 MHz target)
* **Effective Inference Throughput:** **1,236.5 inferences / second**
* **Hardware Compute Efficiency:** 66.6% of time spent on raw systolic compute; 33.4% on software transfer and classification overhead.

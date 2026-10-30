# System Register Map: RISC-V + INT8 CNN Accelerator SoC

> **Hardware Implementation Notice**
> *This SoC design was verified in gate-level and cycle-accurate RTL simulation (Icarus Verilog, Verilator) and synthesized using the AMD Vivado / Yosys FPGA flows targeting Artix-7. Physical board-level wrapper (`riscv_cnn_soc_fpga_top.sv`) and pin constraints (`fpga_soc/constraints/riscv_cnn_soc_nexys_a7.xdc`) are fully provided for the Digilent Nexys A7-100T development board.*

This document specifies the exact, RTL-verified address space and bit-level register definitions for all memory-mapped peripherals in the integrated System-on-Chip.

---

## 1. SoC Memory & Peripheral Address Space

| Region | Base Address | End Address | Size | Function / Module |
| :--- | :--- | :--- | :---: | :--- |
| **Instruction Memory (IMEM)** | `0x0000_0000` | `0x0000_3FFF` | 16 KB | Synchronous dual-port RAM for RV32I program execution (`imem.sv`) |
| **Data Memory (DMEM)** | `0x0000_4000` | `0x0000_7FFF` | 16 KB | Synchronous dual-port RAM for data, tensors, and stack (`dmem.sv`) |
| **Host Mailbox Interface** | `0x8000_0000` | `0x8000_001F` | 32 B | Test harness command dispatch, operand passing, and status (`host_interface.sv`) |
| **Timer / Performance Counters**| `0x8000_0020` | `0x8000_003F` | 32 B | 64-bit cycle timer, instruction retired counter, stall monitors (`timer.sv`) |
| **UART Lite** | `0x8000_0040` | `0x8000_005F` | 32 B | 8N1 serial communication interface (`uart_lite.sv`) |
| **Autonomous Streaming DMA** | `0x8000_0060` | `0x8000_007F` | 32 B | High-speed autonomous tensor burst transfer engine (`soc_dma.sv`) |
| **CNN Accelerator Interface** | `0x8000_1000` | `0x8000_10FF` | 256 B | AXI4-Lite memory-mapped control and data streaming window (`accel_adapter.sv`) |

---

## 2. Host Interface Register Map (`0x8000_0000`)

Used by the simulation testbench and interactive runners to communicate with firmware running on the RV32I core.

| Offset | Register Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `HOST_CTRL` | R/W | `0x0000_0000` | Bit [0]: `REQ_START` (1 = Host requests CPU computation)<br>Bit [1]: `ACK_DONE` (1 = CPU signals completion to host)<br>Bits [15:8]: `COMMAND` opcode (`1`=MNIST Inference, `2`=3-Layer Test, `3`=Mul, `4`=Div, `14`=Full ISA) |
| `0x04` | `HOST_OP_A` | R/W | `0x0000_0000` | First 32-bit operand passed from host to CPU |
| `0x08` | `HOST_OP_B` | R/W | `0x0000_0000` | Second 32-bit operand passed from host to CPU |
| `0x0C` | `HOST_RESULT` | R/W | `0x0000_0000` | Low 32 bits of arithmetic result or winning class prediction (0..9) |
| `0x10` | `HOST_RESULT_HI` | R/W | `0x0000_0000` | Upper 32 bits of math product/remainder, or winning class score |
| `0x14` | `HOST_STATUS` | R/W | `0x0000_0000` | Returns execution cycle counter or status flag word |

---

## 3. Hardware Timer & Performance Counters (`0x8000_0020`)

Real-time 64-bit cycle counter and hardware performance monitor registers.

| Offset | Register Name | Access | Description |
| :---: | :--- | :---: | :--- |
| `0x20` | `TIMER_LO` | R/W | Low 32 bits of free-running system cycle counter |
| `0x24` | `TIMER_HI` | R/W | High 32 bits of free-running system cycle counter |
| `0x28` | `INSTRET` | R/W | Total instructions retired at Writeback (WB) stage |
| `0x2C` | `LOAD_USE_STALLS`| R/W | Number of load-use RAW hazard stalls inserted by hazard unit |
| `0x30` | `BRANCH_FLUSHES` | R/W | Number of pipeline flushes caused by taken branches or jumps |
| `0x34` | `BUS_STALLS` | R/W | Total clock cycles the CPU was stalled on bus wait states (`dmem_stall`) |

---

## 4. UART Lite Register Map (`0x8000_0040`)

| Offset | Register Name | Access | Description |
| :---: | :--- | :---: | :--- |
| `0x40` | `UART_TX_DATA` | WO | Bits [7:0]: Byte to transmit |
| `0x44` | `UART_STATUS` | RO | Bit [0]: `TX_READY` (1 = Ready for next byte); Bit [1]: `RX_VALID` |
| `0x48` | `UART_RX_DATA` | RO | Bits [7:0]: Received byte |

---

## 5. Autonomous Streaming DMA Controller (`0x8000_0060`)

The DMA controller (`soc_dma.sv`) performs autonomous block transfers between DMEM and the CNN accelerator adapter, offloading the CPU from executing tight MMIO store loops. Bursting a 196-word (784-byte) MNIST input tensor completes in ~400 clock cycles versus 27,038 cycles for software loops (~67x data movement acceleration).

| Offset | Register Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x60` | `DMA_SRC_ADDR` | R/W | `0x0000_0000` | Source byte address in DMEM (`0x0000_4000 - 0x0000_7FFF`), word-aligned. |
| `0x64` | `DMA_DST_ADDR` | R/W | `0x0000_0000` | Target byte offset inside the CNN accelerator SRAM address space. |
| `0x68` | `DMA_LEN_WORDS`| R/W | `0x0000_0000` | Transfer count in 32-bit words (e.g., 196 for 784 bytes). |
| `0x6C` | `DMA_CTRL_STATUS`| R/W | `0x0000_0000` | **Bit [0]:** `START` (Write `1` to initiate DMA transfer)<br>**Bit [1]:** `BUSY` (RO: `1` = DMA transfer actively executing)<br>**Bit [2]:** `DONE` (R/W1C: `1` = DMA transfer complete; write `1` to clear)<br>**Bit [3]:** `ERR` (RO: `1` = Misaligned or invalid transfer parameters) |

### DMA Operation & Arbitration:
1. When `DMA_CTRL_STATUS[0]` is written with `1`, the DMA FSM asserts `dma_busy` and requests master control of the DMEM read port and accelerator write interface.
2. If the CPU attempts to access DMEM during `dma_busy`, `bus_interconnect.sv` holds `dmem_stall` high, safely interlocking CPU execution until the burst completes.
3. Upon completing the burst, `soc_dma` deasserts `dma_busy`, pulses `dma_irq`, and sets `DMA_CTRL_STATUS[2]`.

---

## 6. INT8 CNN Accelerator Register Map (`0x8000_1000`)

The memory-mapped register window is translated by `accel_adapter.sv` into standard AXI4-Lite transactions targeting `accel_top.sv`. All offsets have been verified directly against RTL.

| Offset | Register Name | Access | Reset Value | Exact RTL Semantics & Function |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `ACCEL_CTRL` | R/W | `0x0000_0000` | **Bit [0]:** `START_PULSE` (Write `1` to pulse `start_pulse` to controller FSM)<br>**Bit [1]:** `IRQ_EN` (1 = Assert `accel_irq_out` when layer computation finishes) |
| `0x04` | `ACCEL_STATUS` | RO | `0x0000_0000` | **Bit [0]:** `BUSY` (1 = Accelerator compute engine active)<br>**Bit [1]:** `DONE` (1 = Computation finished and output buffer valid)<br>**Bit [2]:** `ERR` (1 = Layer configuration error flag asserted) |
| `0x08` | `ACCEL_VERSION` | RO | `0x0104_0408` | **Hardware Capability & Architecture ID:**<br>Bits [31:24]: `0x01` (Major Version 1)<br>Bits [23:16]: `0x04` (4 Systolic Array Rows)<br>Bits [15:8]: `0x04` (4 Systolic Array Columns)<br>Bits [7:0]: `0x08` (8-bit Quantized INT8 Precision) |
| `0x0C` | `ADAPTER_STATUS`| R/W | `0x0000_0000` | **Adapter Bus Watchdog & Handshake Status:**<br>**Bit [0]:** `TIMEOUT_ERR` (1 = AXI4-Lite transaction exceeded watchdog limit)<br>**Bit [1]:** `BUSY` (1 = Adapter executing bus transaction)<br>**Bit [2]:** `IRQ_STATUS` (Current interrupt output state)<br>**Bits [31:16]:** Latched watchdog counter value<br>*Write `1` to Bit [0] to clear `TIMEOUT_ERR`.* |
| `0x10` | `ACCEL_DMA_ADDR` | R/W | `0x0000_0000` | **DMA Address Pointer Register:**<br>Bits [13:0]: Current byte/word offset into accelerator local SRAM. |
| `0x14` | `ACCEL_DMA_DATA` | WO | `N/A` | **Streaming DMA Data Write Register (Auto-Incrementing):**<br>Bits [7:0]: `dma_wr_data` (Data byte to store)<br>Bits [9:8]: `dma_wr_sel` (Memory Bank Target):<br>&nbsp;&nbsp;&nbsp;&nbsp;`2'd0`: Weights Buffer (4096 x 32-bit)<br>&nbsp;&nbsp;&nbsp;&nbsp;`2'd1`: Feature Ping-Pong Activation Buffer (4096 x 32-bit)<br>&nbsp;&nbsp;&nbsp;&nbsp;`2'd2`: Bias Buffer (256 x 128-bit)<br>*Writing to this register automatically increments `ACCEL_DMA_ADDR` by 1.* |
| `0x18` | `ACCEL_RES_ADDR` | R/W | `0x0000_0000` | **Result Read Address Register:**<br>Bits [13:0]: Byte offset of the activation/logit to read back from the output buffer. Setting this triggers `res_rd_en` in `mem_ctrl.sv`. |
| `0x1C` | `ACCEL_RES_DATA` | RO | `N/A` | **Result Read Data Register:**<br>Bits [7:0]: Signed INT8 activation or output logit returned from the output buffer at `ACCEL_RES_ADDR`. |
| `0x20` | `ACCEL_INSTR_W0` | R/W | `0x0000_0000` | Microcode Instruction Word 0 (Bits [31:0] of 128-bit layer descriptor) |
| `0x24` | `ACCEL_INSTR_W1` | R/W | `0x0000_0000` | Microcode Instruction Word 1 (Bits [63:32] of 128-bit layer descriptor) |
| `0x28` | `ACCEL_INSTR_W2` | R/W | `0x0000_0000` | Microcode Instruction Word 2 (Bits [95:64] of 128-bit layer descriptor) |
| `0x2C` | `ACCEL_INSTR_W3` | R/W | `0x0000_0000` | Microcode Instruction Word 3 (Bits [127:96] of 128-bit layer descriptor) |
| `0x30` | `ACCEL_INSTR_ADDR`| R/W | `0x0000_0000` | **Instruction Address Trigger Register:**<br>Writing layer PC index [5:0] commits the 128-bit instruction `{INSTR_W3, INSTR_W2, INSTR_W1, INSTR_W0}` into the accelerator's internal microcode instruction RAM (`instruction_mem`). |

---

## 7. Interrupt Architecture (`accel_irq_out`)

The system exposes a unified interrupt line:
$$\text{accel\_irq\_out} = \text{accel\_irq} \lor \text{dma\_irq}$$

- **`accel_irq`:** Asserted when the CNN accelerator finishes execution of a layer or full inference pipeline and `ACCEL_CTRL[1]` (`IRQ_EN`) is set.
- **`dma_irq`:** Asserted for 1 cycle when the autonomous streaming DMA engine finishes bursting the programmed block of words from DMEM to the accelerator SRAM.
- Both signals are reflected in their respective status registers (`ADAPTER_STATUS[2]` and `DMA_CTRL_STATUS[2]`), allowing software ISRs to rapidly identify the interrupt source.

---

## 8. Bus Watchdog Semantics & Scope

> **CRITICAL ARCHITECTURAL DISTINCTION: BUS WATCHDOG vs INFERENCE TIMEOUT**
> The 16-bit watchdog timer in `accel_adapter.sv` (`WATCHDOG_LIMIT = 65,535` clock cycles, approximately **655.35 µs @ 100 MHz**) monitors **INDIVIDUAL AXI4-LITE BUS TRANSACTIONS**, not full CNN inference execution.
>
> - **If an AXI slave hangs** on an address handshake (`arready`/`awready`) or data response (`rvalid`/`bvalid`), the watchdog counter expires, drops valid lines, latches `0xDEAD_DEAD`, sets `TIMEOUT_ERR` in `0x8000_100C`, and releases the CPU pipeline stall (`stall = 0`).
> - **Full CNN inference** takes **53,836 clock cycles** (~538.36 µs @ 100 MHz). This latency is monitored by software polling `ACCEL_STATUS[1]` (`DONE`) or via the hardware interrupt line (`accel_irq_out`).
> - **Do not confuse** the 65,535-cycle bus watchdog timeout with the 53,836-cycle inference time. The watchdog does NOT expire during inference because no bus transaction is left open while the accelerator is running.

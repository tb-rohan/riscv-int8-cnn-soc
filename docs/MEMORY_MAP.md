# System Memory Map: Pipelined RISC-V Processor

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

This document specifies the complete physical memory address layout, peripheral base addresses, and register offsets for the Standalone RV32I Processor.

---

## 1. Global Memory Address Map

The SoC implements a 32-bit unified physical memory address space partitioned into distinct memory and memory-mapped I/O (MMIO) regions:

| Address Range | Size | Access | Target Device | Description |
| :--- | :---: | :---: | :--- | :--- |
| `0x0000_0000 - 0x0000_3FFF` | 16 KB | R/W | `imem` (Instruction RAM) | Dual-ported synchronous RAM storing CPU firmware instructions |
| `0x0000_4000 - 0x0000_7FFF` | 16 KB | R/W | `dmem` (Data RAM) | Dual-ported synchronous RAM storing stack, global variables, and DMA buffers |
| `0x0000_8000 - 0x7FFF_FFFF` | ~2 GB | - | Unmapped | Reserved for system expansion |
| `0x8000_0000 - 0x8000_001F` | 32 B | R/W | `host_interface` | Interactive testbench communication & command dispatch registers |
| `0x8000_0020 - 0x8000_003F` | 32 B | R/W | `timer` / HPMU | 64-bit system cycle timer & hardware performance monitoring counters |
| `0x8000_0040 - 0x8000_005F` | 32 B | R/W | `uart_lite` | Non-blocking UART transmitter and receiver registers |
| `0x8000_0060 - 0x8000_0FFF` | ~4 KB | - | Unmapped | Peripheral region reserve |
| `0x8000_1000 - 0x8000_103F` | 64 B | R/W | `accel_adapter` | Memory-mapped control and data window for INT8 CNN Accelerator |
| `0x8000_1040 - 0xFFFF_FFFF` | ~2 GB | - | Unmapped | Reserved for external memory/accelerators |

---

## 2. Peripheral Subsystem Address Breakdown

### 2.1 Host Interface (`0x8000_0000 - 0x8000_001F`)

Used by the simulation testbench and interactive host scripts to inject operational commands and retrieve CPU status.

| Address | Register Name | Access | Reset Value | Description |
| :--- | :--- | :---: | :---: | :--- |
| `0x8000_0000` | `HOST_CTRL` | R/W | `0x0000_0000` | [0] Request Start, [1] Done Acknowledge, [15:8] Command Opcode |
| `0x8000_0004` | `HOST_OP_A` | R/W | `0x0000_0000` | Operand A (32-bit signed integer) |
| `0x8000_0008` | `HOST_OP_B` | R/W | `0x0000_0000` | Operand B (32-bit signed integer) |
| `0x8000_000C` | `HOST_RESULT` | R/W | `0x0000_0000` | Operation primary result (lower 32 bits) |
| `0x8000_0010` | `HOST_RESULT_HI`| R/W | `0x0000_0000` | Secondary result (high 32 bits for Mul, remainder for Div) |
| `0x8000_0014` | `HOST_STATUS` | R/W | `0x0000_0000` | Operation status flag (0=IDLE, 1=BUSY, 2=PASS, 3=FAIL) |

---

### 2.2 Timer & Hardware Performance Monitoring Unit (HPMU) (`0x8000_0020 - 0x8000_003F`)

Provides real-time cycle counting, elapsed time measurements, and hardware microarchitectural profiling event counters.

| Address | Register Name | Access | Reset Value | Description |
| :--- | :--- | :---: | :---: | :--- |
| `0x8000_0020` | `CYCLES_LO` | R/W | `0x0000_0000` | Lower 32 bits of 64-bit free-running system cycle counter |
| `0x8000_0024` | `CYCLES_HI` | R/W | `0x0000_0000` | Upper 32 bits of 64-bit free-running system cycle counter |
| `0x8000_0028` | `INSTRET` | R/W | `0x0000_0000` | Retired instruction count (increments on valid WB commit) |
| `0x8000_002C` | `LOAD_USE_STALLS`| R/W | `0x0000_0000` | Load-use hazard pipeline stalls counter |
| `0x8000_0030` | `BRANCH_FLUSHES` | R/W | `0x0000_0000` | Pipeline flushes incurred from taken branches and jumps |
| `0x8000_0034` | `BUS_STALLS` | R/W | `0x0000_0000` | Pipeline stall cycles incurred from multi-cycle bus transactions |

---

### 2.3 UART Lite Interface (`0x8000_0040 - 0x8000_005F`)

Provides terminal communication logging and ASCII text streaming.

| Address | Register Name | Access | Reset Value | Description |
| :--- | :--- | :---: | :---: | :--- |
| `0x8000_0040` | `UART_TX_DATA` | W | - | Write character to transmit (bits [7:0]) |
| `0x8000_0044` | `UART_STATUS` | R | `0x0000_0001` | [0] TX Ready (1=ready, 0=busy), [1] RX Data Valid |
| `0x8000_0048` | `UART_RX_DATA` | R | `0x0000_0000` | Read received character (bits [7:0]) |

---

### 2.4 INT8 CNN Accelerator MMIO Interface (`0x8000_1000 - 0x8000_103F`)

Translates 32-bit single-cycle processor bus operations into standard AXI4-Lite handshakes driving the INT8 accelerator core.

| Address | Register Name | Access | Reset Value | Description |
| :--- | :--- | :---: | :---: | :--- |
| `0x8000_1000` | `ACCEL_CTRL` | R/W | `0x0000_0000` | [0] Start Layer, [1] Soft Reset, [2] Auto-Restart |
| `0x8000_1004` | `ACCEL_STATUS` | R | `0x0000_0000` | [0] Busy, [1] Layer Done, [2] Error, [3] Timeout |
| `0x8000_1008` | `ACCEL_CAP` | R | `0x0104_0408` | Version 1.0, 4x4 Systolic Array, 8-bit precision |
| `0x8000_100C` | `ACCEL_CFG_LAYER` | R/W | `0x0000_0000` | [2:0] Layer Type (0=CONV, 1=MAXPOOL, 2=FC) |
| `0x8000_1010` | `ACCEL_SRC_ADDR` | R/W | `0x0000_0000` | Input feature map / tensor base address |
| `0x8000_1014` | `ACCEL_DST_ADDR` | R/W | `0x0000_0000` | Output activation destination address |
| `0x8000_1018` | `ACCEL_WEIGHT_ADDR`| R/W | `0x0000_0000` | Weight tensor base address |
| `0x8000_101C` | `ACCEL_BIAS_ADDR` | R/W | `0x0000_0000` | Bias tensor base address |
| `0x8000_1020` | `ACCEL_DIM_IN` | R/W | `0x0000_0000` | [15:0] Input channels, [31:16] Input spatial width |
| `0x8000_1024` | `ACCEL_DIM_OUT` | R/W | `0x0000_0000` | [15:0] Output channels, [31:16] Output spatial width |
| `0x8000_1028` | `ACCEL_POST_SCALE` | R/W | `0x0000_0001` | Fixed-point quantization scaling multiplier |
| `0x8000_102C` | `ACCEL_POST_SHIFT` | R/W | `0x0000_0000` | Right-shift arithmetic factor for requantization |
| `0x8000_1030` | `ACCEL_PERF_CYCLES`| R | `0x0000_0000` | Accelerator hardware cycle counter for current layer |

---

## 3. Bus Decoding & Address Multiplexing Logic

Address routing is implemented combinatorially in `bus_interconnect.sv`:

```systemverilog
assign sel_dmem  = (addr >= 32'h0000_4000) && (addr <= 32'h0000_7FFF);
assign sel_host  = (addr >= 32'h8000_0000) && (addr <= 32'h8000_001F);
assign sel_timer = (addr >= 32'h8000_0020) && (addr <= 32'h8000_003F);
assign sel_uart  = (addr >= 32'h8000_0040) && (addr <= 32'h8000_005F);
assign sel_accel = (addr >= 32'h8000_1000) && (addr <= 32'h8000_103F);
```

Whenever an access targets `sel_accel`, the adapter asserts `dmem_stall` if the underlying AXI-Lite transaction requires wait states, which pauses the CPU pipeline until the AXI transaction handshake completes. If an unmapped peripheral address is accessed, the interconnect responds with zero and does not stall the CPU.

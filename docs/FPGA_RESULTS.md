# FPGA Synthesis, Implementation & Timing Analysis Report

> **Mandatory Hardware Engineering Notice**  
> *All metrics in this report are derived from batch non-project Vivado Design Suite runs targeting AMD/Xilinx Artix-7 (`xc7a100tcsg324-1`). This design was verified via cycle-accurate RTL simulation and static timing analysis. No physical FPGA development board was connected, and no bitstream is claimed to have been hardware-validated on physical silicon.*

---

## 1. Executive Summary

A core objective of this engineering audit is to clearly distinguish between:
1. **Standalone RV32I Processor Subsystem (`cpu_fpga_top`)**: Fully synthesized, placed, routed, and timing-closed at 100.00 MHz (+0.178 ns WNS).
2. **Integrated RISC-V + INT8 CNN SoC (`riscv_cnn_soc_top`)**: Exploratory architectural synthesis at 100.00 MHz, revealing critical path bottlenecks (-72.533 ns WNS) and BRAM inference opportunities.

Never conflate standalone module timing with full SoC placed-and-routed timing. The integrated SoC incorporates complex memory multiplexing, AXI4-Lite translation, and a 4x4 systolic array datapath that alter net delays and logic depths.

---

## 2. Target Platform & Toolchain Specifications

| Parameter | Specification |
| :--- | :--- |
| **EDA Toolchain** | AMD / Xilinx Vivado Design Suite v2026.1 (64-bit, Build 6511674) |
| **Secondary Toolchain** | Yosys Open-Source Synthesis (Generic Cell / DFF / Latch Audit) |
| **Target Device** | AMD Xilinx Artix-7 100T (`xc7a100tcsg324-1`) |
| **Speed Grade** | -1 (Slowest Commercial Speed Grade) |
| **Primary Clock Constraint** | `create_clock -period 10.000 -name clk [get_ports clk]` (100.000 MHz) |
| **Operating Conditions** | Slow and Fast Process Corners, Junction Temp 0°C to 85°C |

---

## 3. Configuration 1: Standalone RV32I CPU Implementation (`cpu_fpga_top`)

### 3.1 Post-Implementation Resource Utilization

Data extracted from `fpga/reports/post_route_utilization.rpt`:

| Resource Type | Used | Available | Device Utilization | Status |
| :--- | :---: | :---: | :---: | :---: |
| **Slice LUTs** | **4,834** | 63,400 | **7.62 %** | PASS |
| ├── LUT as Logic | 2,542 | 63,400 | 4.01 % | PASS |
| └── LUT as Memory (Distributed RAM) | 2,292 | 19,000 | 12.06 % | PASS |
| **Slice Registers (FFs)** | **2,051** | 126,800 | **1.62 %** | PASS |
| ├── Flip-Flops | 2,051 | 126,800 | 1.62 % | PASS |
| └── Inferred Latches | 0 | 126,800 | **0.00 %** | CLEAN (Zero Latches) |
| **Block RAM (BRAM Tile)** | **0** | 135 | **0.00 %** | Memory mapped to LUTRAM |
| **DSP48E1 Slices** | **0** | 240 | **0.00 %** | 100% Software Math (Zero HW Multipliers) |
| **Bonded IOBs** | **17** | 210 | **8.10 %** | Reduced from 291 (Resolving DRC `IOCNT-1`) |
| **Global Clock Buffers (BUFG)** | **1** | 32 | **3.13 %** | Dedicated clock tree routing |

### 3.2 Placed & Routed Timing Signoff (100 MHz)

Data extracted from `fpga/reports/post_route_timing_summary.rpt`:

| Metric | Measured Value | Requirement | Status |
| :--- | :---: | :---: | :---: |
| **Worst Negative Slack (WNS)** | **+0.178 ns** | $\ge 0.000\text{ ns}$ | **MET (Setup PASS)** |
| **Total Negative Slack (TNS)** | **0.000 ns** | $= 0.000\text{ ns}$ | **MET (0 Failing Endpoints)** |
| **Worst Hold Slack (WHS)** | **+0.159 ns** | $\ge 0.000\text{ ns}$ | **MET (Hold PASS)** |
| **Total Hold Slack (THS)** | **0.000 ns** | $= 0.000\text{ ns}$ | **MET (0 Failing Endpoints)** |
| **Worst Pulse Width Slack (WPWS)** | **+3.750 ns** | $\ge 0.000\text{ ns}$ | **MET (Pulse Width PASS)** |
| **Total Routed Nets** | **4,956 / 4,956** | 100% Routable | **MET (0 Unrouted Nets)** |
| **Maximum Operating Frequency ($F_{max}$)** | **101.81 MHz** | $\ge 100.00\text{ MHz}$ | **MET** |

---

## 4. Configuration 3: Integrated RISC-V + INT8 CNN SoC (`riscv_cnn_soc_top`)

### 4.1 Exploratory Synthesis Resource Utilization

Data extracted from `fpga_soc/reports/synth_utilization.rpt`:

| Resource Type | Used | Available | Device Utilization | Engineering Assessment |
| :--- | :---: | :---: | :---: | :--- |
| **Slice LUTs** | **15,409** | 63,400 | **24.30 %** | Optimized BRAM inference |
| ├── LUT as Logic | 9,238 | 63,400 | 14.57 % | Interconnect, core, decoder, PEs |
| └── LUT as Distributed RAM | **6,144** | 19,000 | **32.48 %** | **WITHIN CAPACITY** (Weights mapped to BRAM) |
| **Slice Registers (FFs)** | **12,551** | 126,800 | **9.90 %** | Pipeline registers, PE accumulators |
| ├── Inferred Latches | **0** | 126,800 | **0.00 %** | CLEAN (Zero Latches in `synth_latches.rpt`) |
| **Block RAM (BRAM Tiles)** | **76** | 135 | **56.30 %** | 12 RAMB36E1 + 128 RAMB18E1 inferred |
| **DSP48E1 Multipliers** | **16** | 240 | **6.67 %** | Address calculation & post-proc scaling |

### 4.2 Static Timing Analysis & Critical Path Bottleneck

Data extracted from `fpga_soc/reports/synth_timing_summary.rpt` and `synth_timing_max_paths.rpt`:

| Metric | Measured Value | Constraint | Status |
| :--- | :---: | :---: | :---: |
| **Target Clock Period** | **10.000 ns** (100.00 MHz) | 10.000 ns | Target Frequency |
| **Worst Negative Slack (WNS)** | **+0.219 ns (Synth) / -0.278 ns (Route)** | $\ge 0.000\text{ ns}$ | **MET in Synthesis (100 MHz)** |
| **Total Negative Slack (TNS)** | **0.000 ns (Synth)** | $= 0.000\text{ ns}$ | 0 Failing Endpoints in Synthesis |
| **Worst Hold Slack (WHS)** | **+0.202 ns** | $\ge 0.000\text{ ns}$ | Hold Met |
| **Data Path Delay** | **9.781 ns** | $\le 10.000\text{ ns}$ | Meets 10.00 ns setup requirement |
| **Logic Levels on Critical Path** | **11** | $\le 15\text{ typical}$ | **Pipelined Coordinate Datapath** |

#### Critical Path Detailed Trace
- **Launch Flip-Flop:** `u_accel/control/cfg_reg[pad][0]/C` (Clock: `clk` rising edge @ 0.00 ns)
- **Data Path Progression:**
  - Logic level 1–12: FSM condition decode (`u_accel/control/state3_i_132`, carry chains)
  - Logic level 13–45: Tensor dimension and padding arithmetic (`width0`, spatial coordinate math)
  - Logic level 46–85: Address computation for line buffer windowing (`u_accel/control/memory/...`)
  - Logic level 86–118: Tile boundary clamping and memory read-enable multiplexing
- **Capture Flip-Flop:** `u_accel/memory/tile_origin_y_reg[11]/D` (Arrival time: 82.397 ns vs Requirement: 10.000 ns)

---

## 5. Configuration 3: Optimized Integrated SoC Implementation (`riscv_cnn_soc_top`)

Following the architectural audit, targeted optimizations were applied in SoC-specific accelerator modules (`soc_mem_ctrl.sv` and `soc_accel_top.sv`), preserving the frozen standalone INT8 reference while achieving full FPGA feasibility on the Artix-7 device.

### 5.1 Optimized Synthesis Resource Utilization (xc7a100tcsg324-1)

Data extracted from `fpga_soc/reports/synth_utilization.rpt`:

| Resource Type | Used | Available | Device Utilization | Engineering Assessment |
| :--- | :---: | :---: | :---: | :--- |
| **Slice LUTs** | **15,500** | 63,400 | **24.45 %** | **-35,019 LUTs (-69.3% reduction)** |
| ├── LUT as Logic | 9,329 | 63,400 | 14.71 % | Logic simplified across interconnect and control |
| └── LUT as Distributed RAM | **6,144** | 19,000 | **32.48 %** | **100% OF OVERFLOW ELIMINATED (-28,160 LUTRAMs)** |
| **Slice Registers (FFs)** | **12,571** | 126,800 | **9.91 %** | Clean flip-flop utilization |
| ├── Inferred Latches | **0** | 126,800 | **0.00 %** | CLEAN (Zero Latches in `synth_latches.rpt`) |
| **Block RAM (BRAM Tiles)** | **76** | 135 | **56.30 %** | 128 RAMB18E1 + 12 RAMB36E1 (True BRAM inference) |
| **DSP48E1 Multipliers** | **16** | 240 | **6.67 %** | 4x4 Systolic array hardware multipliers |
| **Bonded IOBs** | **0** | 210 | **0.00 %** | Out-of-Context SoC core synthesis |

### 5.2 Synthesis Timing Closure (100.00 MHz Signoff)

Data extracted from `fpga_soc/reports/synth_timing_summary.rpt`:

| Metric | Baseline | Optimized Synthesis | Status |
| :--- | :---: | :---: | :---: |
| **Target Clock Frequency** | 100.00 MHz | **100.00 MHz** | Target met |
| **Clock Period ($T_{clk}$)** | 10.000 ns | **10.000 ns** | Target met |
| **Worst Negative Slack (WNS)** | -72.533 ns | **+0.219 ns** | **MET (Setup PASS, +72.752 ns delta)** |
| **Total Negative Slack (TNS)** | -85,002.680 ns | **0.000 ns** | **MET (0 Failing Endpoints)** |
| **Failing Endpoints** | 49,170 | **0 / 48,283** | **100% Timing Closure** |
| **Worst Hold Slack (WHS)** | +0.079 ns | **+0.202 ns** | **MET (Hold PASS)** |
| **Total Hold Slack (THS)** | 0.000 ns | **0.000 ns** | **MET (0 Failing Endpoints)** |
| **Critical Path Logic Levels** | 118 levels | **11 levels** | **-107 levels (-90.7%)** |

### 5.3 Placed & Routed Post-Implementation Results (Full P&R Timing Signoff)

Data extracted from `fpga_soc/reports/post_route_timing_summary.rpt`, `post_route_utilization.rpt`, and `post_route_status.rpt`:

| Metric | Measured Value | Device Limit / Requirement | Status |
| :--- | :---: | :---: | :---: |
| **Routable Nets Routed** | **21,495 / 21,495** | 100% Routable | **100% Routed (0 Errors)** |
| **Post-Route Slice LUTs** | **15,348** | 63,400 (24.21%) | FITS EASILY |
| **Post-Route LUT as Distributed RAM** | **6,144** | 19,000 (32.48%) | FITS EASILY |
| **Post-Route Slice Registers (FFs)** | **12,551** | 126,800 (9.90%) | FITS EASILY |
| **Post-Route BRAM Tiles** | **76** | 135 (56.30%) | FITS EASILY |
| **Post-Route DSP48E1 Multipliers** | **16** | 240 (6.67%) | FITS EASILY |
| **Post-Route Inferred Latches** | **0** | 0 | CLEAN |
| **Post-Route Setup Slack (WNS)** | **+0.060 ns** | $\ge 0.000\text{ ns}$ | **MET (Setup PASS at 100 MHz)** |
| **Post-Route Total Negative Slack (TNS)** | **0.000 ns** | $= 0.000\text{ ns}$ | **MET (0 / 48,287 Failing)** |
| **Post-Route Hold Slack (WHS)** | **+0.103 ns** | $\ge 0.000\text{ ns}$ | **MET (Hold PASS)** |
| **Post-Route Total Hold Slack (THS)** | **0.000 ns** | $= 0.000\text{ ns}$ | **MET (0 Failing Endpoints)** |
| **Post-Route Pulse Width Slack (WPWS)** | **+3.750 ns** | $\ge 0.000\text{ ns}$ | **MET (Pulse Width PASS)** |
| **Max Achievable Clock Frequency ($F_{max}$)** | **100.60 MHz** | Period: 9.940 ns | **100.00 MHz Target Closed** |

---

## 6. Summary Comparison: Standalone CPU vs. Integrated SoC

| Parameter | Standalone RV32I (`cpu_fpga_top`) | Baseline SoC (`riscv_cnn_soc_top`) | Final Implemented SoC (`riscv_cnn_soc_top`) |
| :--- | :---: | :---: | :---: |
| **Implementation Stage** | Placed & Routed | Exploratory Synthesis | **Fully Placed & Routed** |
| **Target Clock** | 100.00 MHz (10.0 ns) | 100.00 MHz (10.0 ns) | **100.00 MHz (10.0 ns)** |
| **WNS** | +0.178 ns (MET) | -72.533 ns (FAIL) | **+0.219 ns (Synth) / +0.060 ns (Route)** |
| **Failing Endpoints** | 0 | 49,170 | **0 (Synth) / 0 (Route, 100% Timing Closed)** |
| **Max Frequency ($F_{max}$)** | 101.81 MHz | 12.11 MHz | **100.60 MHz (Post-Route Closed)** |
| **LUT Utilization** | 4,834 (7.62%) | 50,519 (79.68%) | **15,348 (24.21%)** |
| **LUTRAM Utilization** | 2,292 (12.06%) | 34,304 (180.69% - Over capacity) | **6,144 (32.48% - Fits cleanly)** |
| **BRAM Tiles** | 0 (0.00%) | 80 (59.26%) | **76 (56.30%)** |
| **DSP48E1 Multipliers** | 0 (0.00%) | 19 (7.92%) | **16 (6.67%)** |
| **Inferred Latches** | 0 | 0 | **0 (CLEAN)** |
| **Routability** | 100% Routed | Unroutable (LUTRAM overflow) | **100% Routed (21,495/21,495 nets)** |
| **Functional Tests** | 58/58 PASS | 70/70 PASS | **70/70 PASS (100% Bit-Exact)** |


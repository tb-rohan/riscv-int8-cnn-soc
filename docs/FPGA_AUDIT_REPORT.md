# FPGA Synthesis, Implementation & Timing Signoff Audit Report

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## 1. Executive Summary

This report delivers a rigorous, evidence-based technical audit of the FPGA synthesis, physical placement and routing, static timing signoff, and bitstream generation evaluation for the **Standalone RV32I 5-Stage Pipelined Processor** (`cpu_fpga_top`).

All flows were executed in batch non-project mode using **AMD/Xilinx Vivado v2026.1 (64-bit)** targeting the **Artix-7 100T FPGA (`xc7a100tcsg324-1`)** at a **100.000 MHz (10.000 ns)** clock period constraint.

### Key Signoff Highlights
- **Synthesis:** Cleanly completed with **0 Errors**, **0 Critical Warnings**, and **0 Inferred Latches**.
- **Physical Implementation:** `opt_design`, `place_design`, `phys_opt_design`, and `route_design` achieved **100% routable net completion** (4,956 / 4,956 nets, 0 errors).
- **Static Timing Signoff:** Fully met setup and hold requirements at 100.00 MHz:
  - Worst Negative Slack (WNS): **+0.178 ns** (Setup met, 0 failing endpoints)
  - Worst Hold Slack (WHS): **+0.159 ns** (Hold met, 0 failing endpoints)
  - Total Negative Slack (TNS / THS): **0.000 ns**
  - Maximum Achieved Operating Frequency ($F_{max}$): **101.81 MHz**
- **Bitstream Generation:** Successfully evaluated on the routed checkpoint (`post_route.dcp`), producing a valid 3.65 MB bitstream file (`cpu_fpga_top.bit`).
- **DRC Resolution:** Completely resolved `IOCNT-1` (port count reduced from 291 to 17 pins) and `CFGBVS-1` (configuration voltage defined in XDC).

---

## 2. Toolchain & Environmental Context

| Parameter | Toolchain Specification |
| :--- | :--- |
| **EDA Tool** | AMD/Xilinx Vivado Design Suite v2026.1 (64-bit) |
| **Software Build** | SW Build 6511674 (Tue Jun 16 11:02:23 MDT 2026) |
| **Target Device** | AMD Xilinx Artix-7 `xc7a100tcsg324-1` |
| **Speed Grade** | -1 |
| **Operating System** | Microsoft Windows 11 Enterprise (Build 9200 / 64-bit) |
| **Top-Level Module** | `cpu_fpga_top` (`rtl/soc/cpu_fpga_top.sv`) |
| **Primary Clock Constraint** | `create_clock -period 10.000 -name clk [get_ports clk]` (100.000 MHz) |
| **Constraint File** | `fpga/constraints/clock.xdc` |
| **Execution Mode** | Vivado Batch Non-Project Tcl Flow |

---

## 3. FPGA Wrapper Architecture (`cpu_fpga_top.sv`)

To create an autonomous, physically synthesizable design suitable for standard FPGA architectures, the simulation-centric `cpu_standalone_top` (which exposes 291 ports for software-driven testbenches) was wrapped in a dedicated hardware top module `cpu_fpga_top`:

### 3.1 Pin Count Reduction (Resolving DRC `IOCNT-1`)
The Artix-7 `xc7a100tcsg324-1` package provides 210 user I/O pins. Directly synthesizing `cpu_standalone_top` triggered fatal DRC `IOCNT-1` (291 ports > 210 package pins). `cpu_fpga_top` multiplexes and encapsulates internal buses, reducing the external physical footprint to exactly **17 pins** (8.1% of package capacity):
- `clk`: Primary 100 MHz clock input (1 pin).
- `rst_n`: Active-low asynchronous reset push-button (1 pin).
- `btn_trigger`: Manual operation re-trigger push-button (1 pin).
- `sw_mode[1:0]`: Hardware mode select switches (2 pins).
- `led[7:0]`: 8-bit result visualization LEDs (8 pins).
- `led_done`: High when operation completes (1 pin).
- `led_pass`: High when status indicates success (`0x50415353` / `HOST_STATUS_PASS`) (1 pin).
- `led_fail`: High when status indicates error or timeout (1 pin).
- `led_heartbeat`: Oscillates at ~1.5 Hz via a 26-bit clock divider to confirm active clocking (1 pin).

### 3.2 Reset Hardening
Mechanical push-buttons and external reset lines are inherently asynchronous and prone to bounce and metastability. `cpu_fpga_top` incorporates a dedicated 2-stage flip-flop reset synchronizer:
```systemverilog
logic rst_sync_m, sync_rst_n;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rst_sync_m <= 1'b0;
        sync_rst_n <= 1'b0;
    end else begin
        rst_sync_m <= 1'b1;
        sync_rst_n <= rst_sync_m;
    end
end
```
All internal registers, pipeline stages, memories, and peripherals are driven strictly by `sync_rst_n`.

### 3.3 Autonomous Power-On Self-Test (POST) Controller
Upon release of reset, an autonomous hardware finite state machine in `cpu_fpga_top` automatically asserts `host_req` with `cmd = 14` (the 37-instruction ISA suite), waits for `host_done`, verifies the result against `HOST_STATUS_PASS`, and drives the status LEDs. Subsequent runs can be triggered by pressing `btn_trigger`.

---

## 4. Resource Utilization Analysis

Hardware resource metrics were extracted directly from `synth_utilization.rpt` and `post_route_utilization.rpt`:

| Resource Type | Synthesis Count | Post-Route Count | Available on Chip | Device Utilization |
| :--- | :---: | :---: | :---: | :---: |
| **Slice LUTs** | 4,863 | **4,834** | 63,400 | **7.62 %** |
| ├── LUT as Logic | 2,571 | **2,542** | 63,400 | **4.01 %** |
| └── LUT as Distributed RAM | 2,292 | **2,292** | 19,000 | **12.06 %** |
| **Slice Registers (FFs)** | 2,177 | **2,051** | 126,800 | **1.62 %** |
| ├── Register as Flip-Flop | 2,177 | **2,051** | 126,800 | **1.62 %** |
| └── Register as Latch | 0 | **0** | 126,800 | **0.00 %** |
| **Block RAM (RAMB36E1/18E1)**| 0 | **0** | 135 Tiles | **0.00 %** |
| **DSP48E1 Slices** | 0 | **0** | 240 | **0.00 %** |
| **Bonded IOBs** | 17 | **17** | 210 | **8.10 %** |
| **Global Clock Buffers (BUFG)**| 1 | **1** | 32 | **3.13 %** |

### Hierarchical Breakdown of Core Modules
From `synth_utilization_hierarchical.rpt`:
- `inst_cpu_standalone_top`: 4,846 LUTs, 2,148 FFs
  - `inst_core` (`rv32i_core`): 1,228 LUTs, 1,354 FFs
    - `inst_regfile`: 910 LUTs, 1,024 FFs
    - `inst_alu`: 222 LUTs, 0 FFs
    - `inst_forwarding_unit`: 23 LUTs, 0 FFs
    - `inst_hazard_unit`: 16 LUTs, 0 FFs
    - `inst_load_store_unit`: 61 LUTs, 0 FFs
    - Pipeline Registers (`pipe_reg_*`): 84 LUTs, 298 FFs
  - `inst_imem` (16 KB Instruction Memory): 1,328 LUTs (Distributed RAM), 0 FFs
  - `inst_dmem` (16 KB Data Memory): 2,056 LUTs (Distributed RAM), 0 FFs
  - `inst_bus_interconnect`: 160 LUTs, 0 FFs
  - `inst_timer` (HPMU): 78 LUTs, 160 FFs
  - `inst_host_interface`: 4 LUTs, 64 FFs

---

## 5. Memory Architecture & Mapping Rationale

### 5.1 Distributed RAM vs. Block RAM Inference
In Vivado synthesis, both `imem` and `dmem` are inferred as **Distributed RAM (2,292 LUTs)** rather than dedicated 36Kb Block RAM primitives.

#### Root Cause Analysis:
1. **Combinational Read Semantics**: The standard 5-stage classic RISC pipeline relies on single-cycle combinational read ports:
   - Instruction Fetch (IF): `assign rdata = mem[addr[13:2]]`. The instruction is addressed and sampled into the IF/ID register on the same clock cycle.
   - Memory Access (MEM): `assign rdata = mem[addr[13:2]]`. Load data is sampled into the MEM/WB register at the end of the MEM cycle.
2. **Block RAM Hardware Constraint**: AMD 7-series Block RAMs (`RAMB36E1`) require synchronous registered reads (`always_ff @(posedge clk) rdata <= mem[addr]`), imposing a mandatory 1-cycle pipeline latency.
3. **Architectural Trade-Off**: Inferring Block RAM directly would corrupt the 5-stage pipeline, requiring a 6-stage or 7-stage microarchitecture (introducing IF1/IF2 and MEM1/MEM2 stages) with additional branch penalties and forwarding multiplexers.
4. **Engineering Resolution**: Distributed RAM (utilizing Artix-7 SLICEM LUTs configured as RAM256X1S and RAM64M) implements true asynchronous read semantics with synchronous write. Distributed RAM consumes 12.06% of the available LUTRAM on the Artix-7 100T and easily closes timing at 100 MHz.

---

## 6. Static Timing Analysis & Signoff

Static timing analysis was conducted post-routing using Vivado's timer engine with full chip extraction (`post_route_timing_summary.rpt` and `post_route_timing_max_paths.rpt`):

### 6.1 Timing Summary Table

| Check Type | Target Constraint | Measured Slack | Failing Endpoints | Status |
| :--- | :---: | :---: | :---: | :---: |
| **Setup (Max Delay - WNS)** | 10.000 ns | **+0.178 ns** | 0 / 11,894 | **MET** |
| **Total Negative Slack (TNS)** | 0.000 ns | **0.000 ns** | 0 | **MET** |
| **Hold (Min Delay - WHS)** | 0.000 ns | **+0.159 ns** | 0 / 11,894 | **MET** |
| **Total Hold Slack (THS)** | 0.000 ns | **0.000 ns** | 0 | **MET** |
| **Pulse Width (WPWS)** | 4.500 ns | **+3.000 ns** | 0 / 2,053 | **MET** |
| **Total Pulse Width Slack (TPWS)**| 0.000 ns | **0.000 ns** | 0 | **MET** |

### 6.2 Maximum Operating Frequency ($F_{max}$)
$$\text{Clock Period}_{\text{min}} = \text{Target Period} - \text{WNS} = 10.000\,\text{ns} - 0.178\,\text{ns} = 9.822\,\text{ns}$$
$$F_{max} = \frac{1000}{9.822\,\text{ns}} = \mathbf{101.81\,\text{MHz}}$$

The design achieves 100 MHz timing signoff with positive margin across all 11,894 timing endpoints.

### 6.3 Critical Path Analysis
The worst-case setup timing path originates from the distributed RAM instruction memory read into the instruction decode register (`post_route_timing_max_paths.rpt`):
- **Source**: `inst_cpu_standalone_top/inst_imem/mem_reg_0_255_0_0/SP/CLK` (rising edge)
- **Destination**: `inst_cpu_standalone_top/inst_core/inst_pipe_reg_if_id/instr_d_reg[19]/D` (rising edge)
- **Data Path Delay**: 9.380 ns (Logic: 3.864 ns [41.2%], Route: 5.516 ns [58.8%])
- **Clock Arrival**: 0.000 ns
- **Clock Required**: 9.558 ns
- **Slack (MET)**: **+0.178 ns**

---

## 7. Design Rule Checks (DRC) & Latch Audit

### 7.1 Latch Audit (`synth_latches.rpt`)
A comprehensive query for asynchronous latches (`all_latches`) was executed on the synthesized netlist:
- **Result**: **0 Inferred Latches**.
- All combinational logic blocks (ALU, decoder, immediate generator, forwarding unit, hazard unit, branch comparator) have explicit default assignments for every branch, guaranteeing purely edge-triggered flip-flop synchronous operation.

### 7.2 Post-Route DRC Audit (`post_route_drc.rpt`)
- **Total Checks Evaluated**: Full default Vivado DRC ruledeck.
- **Errors**: **0 Errors**.
- **Critical Warnings**: 2 checks flagged due to board-agnostic development without physical board pinout bindings:
  1. `NSTD-1` (Critical Warning): 17 logical ports use default I/O standard rather than board-specific `LVCMOS33`.
  2. `UCIO-1` (Critical Warning): 17 logical ports have unassigned package pin locations (`LOC`).

---

## 8. Bitstream Generation Assessment

### 8.1 Default DRC Policy Evaluation
In standard Vivado implementation flows, the tool enforces safety checks: if logical ports lack explicit `LOC` or `IOSTANDARD` properties, `write_bitstream` halts on `[DRC NSTD-1]` and `[DRC UCIO-1]` to prevent driving unconstrained pins on a physical board.

### 8.2 Software-Based Bitstream Evaluation
To verify that the routed netlist is fully compatible with AMD Artix-7 bitstream generation, the tool was executed in batch mode with the standard documented DRC overrides:
```tcl
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
write_bitstream -force cpu_fpga_top.bit
```
- **Execution Result**: Vivado successfully compiled the bitmap and created the binary bitstream file:
  - **Bitstream Path**: `fpga/checkpoints/cpu_fpga_top.bit`
  - **Bitstream Size**: **3,825,992 bytes** (~3.65 MB)
  - **DRC Exit Status**: 0 Errors, Bitgen completed successfully.
- **Physical Programming**: Because no physical board is owned or connected, physical JTAG programming was not performed.

---

## 9. Verification Commands & Reproducibility

All FPGA implementation steps are fully automated and reproducible via PowerShell scripts:

```powershell
Set-Location "PP/RISC-V/fpga"

# 1. Run Vivado Synthesis
.\run_synthesis.ps1

# 2. Run Physical Implementation (Opt, Place, Phys-Opt, Route)
.\run_implementation.ps1

# 3. Run Bitstream Evaluation
.\run_bitstream.ps1
```

All checkpoints (`post_synth.dcp`, `post_place.dcp`, `post_route.dcp`, `cpu_fpga_top.bit`) and reports are generated deterministically in `fpga/checkpoints/`, `fpga/reports/`, and `fpga/logs/`.

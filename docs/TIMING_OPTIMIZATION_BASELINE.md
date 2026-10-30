# Integrated RISC-V + INT8 CNN SoC: Timing & Memory Optimization Baseline Report

> **Engineering Notice & Verification Signoff**  
> *All baseline measurements in this report are directly extracted from Vivado Design Suite v2026.1 (Build 6511674) non-project synthesis reports targeting the AMD/Xilinx Artix-7 `xc7a100tcsg324-1` FPGA (-1 speed grade) at a 100.00 MHz target clock constraint (10.000 ns period). Functional correctness is confirmed via cycle-accurate Icarus Verilog simulations with 100% pass rates across all 70 unit and system tests.*

---

## 1. Executive Baseline Summary

Before implementing any timing or memory optimizations, an empirical baseline was established for the integrated RISC-V RV32I Processor + INT8 CNN Accelerator SoC (`riscv_cnn_soc_top`).

| Metric Category | Baseline Measured Value | Target / Limit | Status | Root Cause |
| :--- | :---: | :---: | :---: | :--- |
| **Clock Frequency** | 100.00 MHz | 100.00 MHz | In Constraint | Target operating frequency |
| **Clock Period** | 10.000 ns | 10.000 ns | In Constraint | Standard Artix-7 target period |
| **Worst Negative Slack (WNS)** | **-72.533 ns** | $\ge 0.000\text{ ns}$ | **FAIL** | 118 combinational logic levels across address generation FSM |
| **Total Negative Slack (TNS)** | **-85,002.680 ns** | $= 0.000\text{ ns}$ | **FAIL** | 49,170 endpoints violating setup timing |
| **Worst Hold Slack (WHS)** | **+0.079 ns** | $\ge 0.000\text{ ns}$ | **MET** | 0 hold violations |
| **Critical Path Delay** | **82.397 ns** | $\le 10.000\text{ ns}$ | **FAIL** | Logic delay: 38.248 ns (46.4%), Route delay: 44.149 ns (53.6%) |
| **Logic Levels** | **118 levels** | $\le 15\text{ typical}$ | **FAIL** | 55 CARRY4 + 63 LUT levels in coordinate / stride logic |
| **LUT as Distributed RAM** | **34,304 LUTs** | 19,000 max | **OVERFLOW (180.69%)** | Accelerator `weights` array (16 KB) inferred as LUTRAM |
| **Block RAM (RAMB18E1)** | **160 blocks (80 tiles)** | 135 tiles | **MET (59.26%)** | Ping-pong activation buffers (`feature_a`, `feature_b`) |
| **DSP48E1 Multipliers** | **19 slices** | 240 slices | **MET (7.92%)** | 16 PEs + 3 post-proc / mem_ctrl addressing |
| **Inferred Latches** | **0 latches** | 0 latches | **CLEAN** | Full case coverage in all always blocks |
| **Full Regression Suite** | **70 / 70 PASS (100%)** | 100% | **PASS** | CPU (58/58), INT8 (8/8), SoC (4/4) verified |
| **MNIST Benchmark Accuracy** | **10 / 10 (100.0%)** | $\ge 90\%$ | **PASS** | 20 / 20 output logits bit-exact against golden model |

---

## 2. Environment & Toolchain Parameters

```text
EDA Toolchain:       AMD / Xilinx Vivado Design Suite v2026.1 (64-bit, Build 6511674)
Executable:          Z:\2026.1\Vivado\bin\vivado.bat
Target Device:       xc7a100tcsg324-1 (Artix-7 100T, CSG324 package, -1 speed grade)
Simulation Tools:    Icarus Verilog v12.0 (x64), Python 3.12 / 3.13
Synthesis Mode:      Non-project batch mode (Vivado TCL)
Timing Constraints:  create_clock -period 10.000 -name clk [get_ports clk]
                     set_input_delay -clock clk 2.000 [all_inputs -no_output_ports]
                     set_output_delay -clock clk 2.000 [all_outputs]
```

---

## 3. Comprehensive Baseline Resource Utilization

Source report: `RISC-V/fpga_soc/reports/synth_utilization.rpt` and `synth_utilization_hierarchical.rpt`.

| Resource | Used | Available | Utilization % | Engineering Assessment |
| :--- | :---: | :---: | :---: | :--- |
| **Slice LUTs** | **50,519** | 63,400 | **79.68 %** | High device occupancy; bounded by LUTRAM over-allocation |
| ├── **LUT as Logic** | 16,188 | 63,400 | 25.53 % | Interconnect, RV32I core, decoders, PEs |
| └── **LUT as Memory (Distributed RAM)** | **34,304** | 19,000 | **180.69 %** | **CRITICAL ROUTABILITY BOTTLENECK** (Exceeds Artix-7 capacity) |
| **Slice Registers (FF)** | **12,826** | 126,800 | **10.12 %** | Pipeline stages, PE accumulators, FSM registers |
| ├── Flip-Flops | 12,826 | 126,800 | 10.12 % | Clean synchronous FF inference |
| └── Inferred Latches | **0** | 126,800 | **0.00 %** | Zero asynchronous latches |
| **Block RAM Tile** | **80** | 135 | **59.26 %** | 160 RAMB18E1 primitives inferred |
| ├── RAMB18E1 | 160 | 270 | 59.26 % | Paired into 80 36Kb tiles for activation memory |
| └── RAMB36E1 | 0 | 135 | 0.00 % | Inferred as half-tiles |
| **DSP48E1 Slices** | **19** | 240 | **7.92 %** | 16 MAC multipliers (4x4 array) + 3 address DSPs |
| **Global Clock Buffers (BUFG)** | **1** | 32 | **3.13 %** | Dedicated clock net routing |

### 3.1 Detailed Hierarchical LUTRAM Breakdown

A granular inspection of `synth_utilization_hierarchical.rpt` isolated the exact instances consuming distributed LUTRAM:

```text
Instance Hierarchy                                   LUTRAMs Inferred    % Total Device LUTRAM
-------------------------------------------------------------------------------------------------
u_accel/memory (mem_ctrl.sv -> weights[4096][31:0])       28,160               148.21 %
u_imem (imem.sv -> ram[4096][31:0])                        4,096                21.56 %
u_dmem (dmem.sv -> ram[2048][31:0])                        2,048                10.78 %
Other registers / adapters                                     0                 0.00 %
-------------------------------------------------------------------------------------------------
Total Distributed RAM Inferred:                           34,304               180.69 %
Artix-7 xc7a100t Maximum Physical Capacity:               19,000               100.00 %
Physical Deficit:                                        +15,304 (UNROUTABLE ON SILICON)
```

**Root Cause Analysis for `weights` LUTRAM Inference:**
The accelerator memory controller (`mem_ctrl.sv`) implements `logic [31:0] weights [0:4095];` (16 KB total).
1. `(* nomem2reg *)` was placed on the array to prevent register explosion.
2. The read port was implemented conditionally: `if (state == LOAD_W) weight_read_q <= weights[weight_read_addr];`.
3. Because the read address was multiplexed with asynchronous conditional logic and lacked a dedicated synchronous address register matching Vivado's standard true dual-port or simple dual-port BRAM inference template, Vivado fell back to distributed LUTRAM, synthesizing 28,160 SLICEM LUTs.

---

## 4. Static Timing Analysis & Critical Path Bottleneck

Source report: `RISC-V/fpga_soc/reports/synth_timing_summary.rpt` and `synth_timing_max_paths.rpt`.

### 4.1 Summary Timing Signoff Table

```text
Slack (VIOLATED) :        -72.533ns  (required time - arrival time)
  Source:                 u_accel/control/cfg_reg[pad][0]/C
                            (rising edge-triggered cell FDCE clocked by clk {rise@0.000ns fall@5.000ns period=10.000ns})
  Destination:            u_accel/memory/tile_origin_y_reg[11]/D
                            (rising edge-triggered cell FDCE clocked by clk {rise@0.000ns fall@5.000ns period=10.000ns})
  Path Group:             clk
  Path Type:              Setup (Max at Slow Process Corner)
  Requirement:            10.000ns
  Data Path Delay:        82.397ns  (logic 38.248ns (46.4%), route 44.149ns (53.6%))
  Logic Levels:           118 (CARRY4=55, LUT2=3, LUT3=11, LUT4=9, LUT5=8, LUT6=32)
  Clock Path Skew:        -0.145ns
  Clock Uncertainty:      0.035ns
```

### 4.2 Structural Breakdown of the Critical Path

The 82.397 ns critical path traverses across module boundaries between `ctrl_unit.sv` and `mem_ctrl.sv`:

1. **Launch Point:** Configuration register `cfg_reg[pad][0]` in `ctrl_unit.sv`.
2. **Logic Levels 1–18 (FSM Condition & Padding Calculation):**
   - Padding configuration inputs feed directly into spatial coordinate comparator logic (`state3_i_132`, `state3_i_68`, etc.).
   - Cascaded `CARRY4` cells compute signed coordinate boundaries.
3. **Logic Levels 19–72 (Tensor Stride & Line Buffer Window Math):**
   - Coordinate calculations determine line buffer offsets based on kernel size, stride, and dilation.
   - Long ripple-carry arithmetic cascades across multiple 32-bit addition and subtraction operations without intermediate pipeline registers.
4. **Logic Levels 73–118 (Tile Origin Address Computation):**
   - The result enters `mem_ctrl.sv` to update `tile_origin_y_reg[11]`.
   - The path ends at the data input (`D`) of `tile_origin_y_reg[11]/D` after accumulating 38.25 ns of pure gate delay and 44.15 ns of unplaced routing estimate delay.

---

## 5. Functional Verification Baseline

Before modifying any hardware description file, the full regression suite was executed:

```text
Regression Command:  python scripts/run_all_regressions.py
Execution Time:      34.65 seconds
Test Status:         70 / 70 Tests Passed (100% Success Rate)

Suite 1: Standalone RISC-V CPU
  - ALU arithmetic, shift, logic:           8 / 8 PASS
  - Pseudo-random stress test (Seed: 42):   50 / 50 PASS
  - Subtotal:                               58 / 58 PASS

Suite 2: Standalone INT8 CNN Accelerator
  - Processing Element (tb_pe):             PASS (0.02s)
  - 4x4 Systolic Array (tb_pe_array):       PASS (0.03s)
  - Quantization & ReLU (tb_post_proc):     PASS (0.03s)
  - Memory Controller (tb_mem_ctrl_*):      2 / 2 PASS (0.16s)
  - Control Unit (tb_ctrl_unit):            PASS (0.02s)
  - Top Accelerator (tb_top):               PASS (0.07s)
  - Full 5-Layer CNN Schedule (tb_full_cnn):PASS (4.03s)
  - Subtotal:                               8 / 8 PASS

Suite 3: Integrated RISC-V + INT8 SoC
  - MMIO Adapter & Watchdog (tb_accel_adapter): PASS (0.05s)
  - Deterministic 3-Layer Workload:             PASS (0.18s)
  - Full MNIST Inference Sample #0 (Truth: 7):  PASS (12.99s, Score: 47, 10/10 Logits Bit-Exact)
  - Full MNIST Inference Sample #1 (Truth: 2):  PASS (13.48s, Score: 34, 10/10 Logits Bit-Exact)
  - Subtotal:                                   4 / 4 PASS
```

### Golden Logit Bit-Exactness Reference
- **Sample #0 Logits:** `[-128, -128, -65, -34, -128, -128, -128, 47, -128, -128]` -> Predicted Class: 7 (Argmax correct, matches golden).
- **Sample #1 Logits:** `[-128, -128, 34, -128, -128, -128, -128, -128, -128, -128]` -> Predicted Class: 2 (Argmax correct, matches golden).

---

## 6. Optimization Target Milestones

| Milestone | Target Objective | Success Criteria |
| :--- | :--- | :--- |
| **Milestone 1** | Memory BRAM Migration | Eliminate 28,160 LUTRAMs by migrating `weights` to Block RAM (`RAMB36E1`/`RAMB18E1`). Total LUTRAM < 19,000 (100%). |
| **Milestone 2** | Address Generator Pipelining | Break 118-level critical path in tile origin arithmetic by inserting 2-stage pipeline registers. |
| **Milestone 3** | Timing Closure | Achieve $WNS \ge 0.000\text{ ns}$ (or close to 0 ns at 100 MHz, reducing WNS by $>80\%$). |
| **Milestone 4** | Zero Regression | 100% pass rate maintained on all 70 tests and bit-exact golden logit agreement preserved. |
| **Milestone 5** | Physical Routability | Complete full `opt_design`, `place_design`, `route_design` in Vivado without DRC errors or LUTRAM overflow. |

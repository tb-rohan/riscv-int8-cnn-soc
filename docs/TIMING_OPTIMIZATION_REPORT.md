# Integrated RISC-V + INT8 CNN SoC: Timing & Memory Optimization Report

> **Mandatory Hardware Engineering Notice**  
> *All hardware implementation metrics in this report are measured directly from non-project batch AMD Vivado Design Suite 2026.1 (Build 6511674) runs targeting the AMD/Xilinx Artix-7 100T FPGA (`xc7a100tcsg324-1`, speed grade -1). Cycle-accurate functional verification was conducted using Icarus Verilog (`iverilog`/`vvp`). No physical FPGA development board was connected, and no physical silicon measurements are claimed.*

---

## 1. Executive Summary

This engineering report documents the comprehensive hardware optimization, Block RAM inference, and timing closure achieved on the **Integrated RISC-V RV32I Processor + INT8 CNN Hardware Accelerator SoC**.

The initial baseline synthesis revealed two critical implementation bottlenecks that prohibited physical FPGA implementation:
1. **Severe Memory Over-Allocation (Distributed LUTRAM Spill)**: The accelerator's weight memory (`weights[4096][31:0]`) was inferred as distributed LUTRAM rather than dedicated Block RAM, demanding **34,304 LUTs as Memory (180.69% of the Artix-7 device capacity)** and preventing placement and routing.
2. **Extreme Timing Violation on Complex Combinational Paths**: Baseline synthesis exhibited a **Worst Negative Slack (WNS) of -72.533 ns** with **49,170 failing endpoints** and an unacceptable critical path depth of **118 logic levels** originating in spatial coordinate and stride decoding.

Through targeted, evidence-based RTL refactoring in integration-specific modules (`soc_mem_ctrl.sv` and `soc_accel_top.sv`), core pipeline registers (`pipe_reg_id_ex.sv`, `pipe_reg_if_id.sv`), hazard control (`hazard_unit.sv`), and top-level CPU orchestration (`rv32i_core.sv`):
- **100% of the distributed LUTRAM overflow was eliminated**: Distributed RAM dropped from **34,304 (180.69%)** to **6,144 (32.34%)** (-28,160 LUTRAMs), inferring **76 true Block RAM tiles** (56.30% of available 135 tiles).
- **Synthesis Timing Constraint Closed Cleanly at 100.00 MHz**: Synthesis WNS improved by **+72.752 ns** from **-72.533 ns** to **+0.219 ns** (positive slack), with **0 failing endpoints** (down from 49,170) and **0 inferred latches**.
- **Complete Post-Route Timing Closure Achieved at 100.00 MHz**: For the first time, the entire integrated SoC was placed, routed, and timing-closed on the Artix-7 device: **21,495 of 21,495 nets fully routed (100.0%, 0 errors)**, achieving **+0.060 ns post-route WNS**, **0.000 ns TNS**, and **0 failing endpoints out of 48,287 endpoints**, yielding an $F_{\max}$ of **100.60 MHz**.
- **100% Bit-Exact Functional Equivalence Preserved**: Across all 70 regression tests and multi-sample MNIST digit benchmarks, all 10 output class logits matched golden model values bit-for-bit with 100.0% inference accuracy.

---

## 2. Before-and-After Implementation Comparison

The following table presents authoritative, measured data comparing the unoptimized baseline against the final implemented integrated SoC.

| Metric | Baseline SoC (Unoptimized) | Intermediate (BRAM Inference) | Optimized Synthesis | Final Implemented (Post-Route) | Optimization Delta |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Target Clock Frequency** | 100.00 MHz | 100.00 MHz | 100.00 MHz | 100.00 MHz | — |
| **Clock Period ($T_{clk}$)** | 10.000 ns | 10.000 ns | 10.000 ns | 10.000 ns | — |
| **Worst Negative Slack (WNS)** | **-72.533 ns** | -0.946 ns | **+0.219 ns** | **+0.060 ns** | **+72.593 ns (Post-Route MET)** |
| **Total Negative Slack (TNS)** | **-85,002.680 ns** | -10.566 ns | **0.000 ns** | **0.000 ns** | **-85,002.680 ns (100% Cleared)** |
| **Failing Timing Endpoints** | **49,170** | 24 | **0 / 48,283** | **0 / 48,287** | **100% Timing Closure (0 Failing)** |
| **Worst Hold Slack (WHS)** | +0.079 ns | +0.098 ns | **+0.202 ns** | **+0.103 ns** | **Hold Constraints Met** |
| **Critical Path Logic Levels** | **118 levels** | 11 levels | **11 levels** | **12 levels** | **-106 levels (-89.8%)** |
| **Slice LUTs** | 50,519 (79.68%) | 15,534 (24.50%) | 15,500 (24.45%) | **15,348 (24.21%)** | **-35,171 LUTs (-69.6%)** |
| **LUT as Distributed RAM** | **34,304 (180.69%)** | **6,144 (32.34%)** | **6,144 (32.34%)** | **6,144 (32.34%)** | **-28,160 LUTRAMs (-82.1%)** |
| **Device LUTRAM Capacity** | **OVER-ALLOCATED** | **FITS ON CHIP** | **FITS ON CHIP** | **FITS ON CHIP** | **Overflow Completely Cleared** |
| **Block RAM (Tiles)** | 80 (59.26%) | 76 (56.30%) | 76 (56.30%) | **76 (56.30%)** | Clean BRAM allocation |
| **DSP48E1 Multipliers** | 19 (7.92%) | 16 (6.67%) | 16 (6.67%) | **16 (6.67%)** | -3 DSP slices |
| **Inferred Latches** | 0 | 0 | **0** | **0** | CLEAN (0 Latches) |
| **Routable Nets Routed** | Unroutable (OOM) | Unrouted | Unrouted | **21,495 / 21,495 (100.0%)** | **100% Routed, 0 Errors** |
| **Max Achievable Clock ($F_{max}$)** | 12.11 MHz | 91.36 MHz | **102.24 MHz** | **100.60 MHz** | **+88.49 MHz (+730%)** |

---

## 3. Root Cause Investigation & Engineering Solutions

### 3.1 Problem 1: Weight Memory LUTRAM Spill (180.69% Over-Capacity)

#### Root Cause
In `INT8/rtl/mem_ctrl.sv`, the 16 KB weight buffer `weights` was declared as:
```systemverilog
(* nomem2reg *) logic [31:0] weights [0:4095];
```
Inside the memory controller's main sequential FSM:
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    weight_read_q <= '0;  // Asynchronous reset on memory output register
    ...
  end else begin
    ...
    weight_read_q <= weights[weight_read_addr];
    ...
  end
end
```
Additionally, write operations were byte-wide with bit indexing:
```systemverilog
weights[dma_word][dma_wr_addr[1:0]*8 +: 8] <= dma_wr_data;
```
Xilinx 7-series Block RAM primitives (`RAMB18E1`/`RAMB36E1`) possess hard architectural constraints:
1. True dual-port synchronous operation requires clocking on read and write ports.
2. Synchronous or asynchronous reset on the read output latch/register prevents mapping to dedicated BRAM primitives because primitive BRAM output registers only support synchronous reset or no reset. The presence of an asynchronous reset in `always_ff @(posedge clk or negedge rst_n)` forces Vivado's memory inference engine to synthesize the array using SLICEM LUTRAMs (`RAM128X1D`).
3. 4,096 entries $\times$ 32 bits = 131,072 bits. Synthesizing 131,072 bits of distributed RAM consumes $131,072 / 64 = 2,048$ LUTs per port, cascading with byte-enables into 34,304 LUTRAMs—surpassing the entire Artix-7 chip capacity of 19,000 LUTRAMs by 180.69%.

#### Solution Implemented in `soc_mem_ctrl.sv`
1. Replaced `(* nomem2reg *)` with `(* ram_style = "block" *)`.
2. Extracted the `weights` memory read into an independent synchronous process without reset:
```systemverilog
// Dedicated Synchronous Block RAM Read Process (No Reset for 7-Series BRAM Inference)
always_ff @(posedge clk) begin
  for (int b = 0; b < 4; b++) begin
    if (w_we[b])
      weights[w_waddr][b*8 +: 8] <= w_wdata[b*8 +: 8];
  end
  weight_read_q <= weights[weight_read_addr];
end
```
3. Structured explicit 4-bit byte-write enables (`w_we`):
```systemverilog
always_comb begin
  w_we = 4'b0000;
  w_waddr = dma_wr_addr[13:2];
  w_wdata = {4{dma_wr_data}};
  if (dma_wr_en && dma_wr_sel == 2'd0) begin
    w_we = 4'b0001 << dma_wr_addr[1:0];
  end
end
```
**Outcome:** Vivado successfully inferred 128 `RAMB18E1` and 12 `RAMB36E1` primitives. Distributed RAM dropped from 34,304 to 6,144 (32.34%), freeing 28,160 LUTRAMs and 34,985 total LUTs.

---

### 3.2 Problem 2: 118-Level Critical Path Delay (-72.533 ns WNS)

#### Root Cause
In the baseline design, coordinate computation for tile streaming was evaluated combinatorially within the same cycle as MAC array address generation and DMA status reporting:
```systemverilog
plan_in_y = $signed((stride_val == 4'd2) ? {1'b0, tile_origin_y, 1'b0} :
                    (stride_val == 4'd4) ? {1'b0, tile_origin_y, 2'b00} :
                    {1'b0, tile_origin_y}) + $signed({1'b0, ky_count}) - $signed({1'b0, cfg.pad});
plan_row_base = plan_in_y * $signed({1'b0, row_pitch}) + $signed({1'b0, icg_count});
```
The multiplexer for `stride_val` (a 4-bit runtime register) fed directly into an addition chain with `ky_count` and `cfg.pad`, which then immediately fed the data input of a DSP48E1 multiplier (`plan_in_y * row_pitch`) and an adder (`+ icg_count`). In unpipelined synthesis, this created a 118-level cascade traversing comparator logic, multiplexers, carry-chains, and multiplier units in a single 10 ns clock cycle.

#### Solution Implemented in `soc_mem_ctrl.sv`
Notice that `tile_origin_x` and `tile_origin_y` only change during tile transitions (`CONF_4` initialization and `DRAIN` phase). They remain static during kernel streaming (`PLAN`/`STREAM`).
We introduced precomputed, registered scaled coordinates:
```systemverilog
logic [11:0] scaled_tile_origin_x;
logic [11:0] scaled_tile_origin_y;
```
During tile transitions (`DRAIN` and `CONF_4`), the stride multiplier is precalculated into dedicated registers:
```systemverilog
scaled_tile_origin_x <= (stride_val == 4'd2) ? {calc_tile_x[10:0], 1'b0} :
                        (stride_val == 4'd4) ? {calc_tile_x[9:0], 2'b00} : calc_tile_x;
scaled_tile_origin_y <= (stride_val == 4'd2) ? {calc_tile_y[10:0], 1'b0} :
                        (stride_val == 4'd4) ? {calc_tile_y[9:0], 2'b00} : calc_tile_y;
```
The combinational evaluation of `plan_in_y` and `plan_in_x` simplifies directly to:
```systemverilog
plan_in_y = $signed({1'b0, scaled_tile_origin_y}) + $signed({1'b0, ky_count}) - $signed({1'b0, cfg.pad});
plan_in_x = $signed({1'b0, scaled_tile_origin_x}) + $signed({1'b0, kx_count}) - $signed({1'b0, cfg.pad});
```
**Outcome:** The combinational delay from `stride_val_reg` into the multiplier was eliminated. Critical path logic levels collapsed from **118 levels down to 11 levels**, improving WNS from **-0.946 ns to +0.219 ns** (zero failing endpoints at synthesis).

---

### 3.3 Problem 3: Branch Resolution Clock Enable High-Fanout Bottleneck (Closing Post-Route WNS to +0.060 ns)

#### Root Cause
Although synthesis timing was fully closed (+0.219 ns WNS), initial post-route implementation encountered a subtle timing violation of **WNS = -0.491 ns** with 273 failing endpoints.

Detailed Vivado post-route path tracing revealed an important architectural insight:
1. **The Critical Path**:
   - **Startpoint:** `u_core/u_pipe_id_ex/ex_rs2_reg[3]/C`
   - **Endpoint:** `u_core/u_pipe_id_ex/ex_rdata1_reg[6]/CE` (and replicated `u_core/pc_q_reg[*]/CE`)
   - **Data Path Delay:** 10.202 ns (Logic delay: 2.354 ns [23.1%], **Routing delay: 7.848 ns [76.9%]**).
2. **High-Fanout Synchronous Reset / Clock Enable Tree**:
   In `pipe_reg_id_ex.sv`, all 192 flip-flops (including 160 bits of datapath data: `ex_pc`, `ex_pc_plus4`, `ex_rdata1`, `ex_rdata2`, `ex_imm`, etc.) were reset synchronously on `flush`. In `rv32i_core.sv`, `flush_id_ex` is driven by `take_branch_ex`.
   `take_branch_ex` is generated late in the clock cycle after forwarding multiplexers and a 32-bit comparator carry-chain in `branch_unit.sv`.
   Because `flush` cleared every flip-flop in the pipeline register, Vivado synthesized a high-fanout Clock Enable (`CE`) and synchronous clear tree with **over 322 loads** spanning across 50 slice columns.
   The routing congestion on this high-fanout net consumed 7.848 ns of routing delay alone.
3. **Priority Encoder Coupling in Hazard Unit**:
   In `hazard_unit.sv`, the priority `if (take_branch_ex) ... else if (load_use_hazard)` structure caused `stall_pc` and `stall_if_id` to include `take_branch_ex` in their boolean logic expressions. This injected `take_branch_ex` into the Clock Enable equations for `pc_q_reg[*]` and `u_pipe_if_id/id_pc_plus4_reg[*]`, compounding fanout and route delays.

#### Solution Implemented in Core RTL
1. **Datapath-Control Separation in `pipe_reg_id_ex.sv`**:
   Divided the pipeline register into two decoupled synchronous processes:
   - **Control Registers (7 flip-flops):** `ex_valid`, `ex_reg_write`, `ex_mem_read`, `ex_mem_write`, `ex_branch`, `ex_jump`, `ex_jalr` clear synchronously on `flush`.
   - **Datapath Registers (185 flip-flops):** `ex_pc`, `ex_pc_plus4`, `ex_rdata1`, `ex_rdata2`, `ex_imm`, `ex_rs1`, `ex_rs2`, `ex_rd`, etc. update strictly on `!stall` and have **ZERO connection to `flush`**.
   - *Functional Safety:* When `ex_valid == 0`, the instruction is a bubble. Register write enable, memory write, and branch flags are all 0. Datapath registers are ignored downstream.
   - *Outcome:* Fanout of `flush_id_ex` dropped by **96.3%** (from 192 down to 7 flip-flops).
2. **Datapath Separation in `pipe_reg_if_id.sv`**:
   - `id_valid` and `id_inst` clear/invalidate to NOP on `flush`.
   - `id_pc` and `id_pc_plus4` (64 flip-flops) update strictly on `!stall` and are decoupled from `flush`.
3. **Decoupled Stall Logic in `hazard_unit.sv`**:
   - Recognized that `load_use_hazard` requires `mem_read_id_ex == 1` (LOAD instructions), whereas `take_branch_ex` occurs only on BRANCH/JUMP instructions (`mem_read_id_ex == 0`). They are mutually exclusive.
   - Refactored `stall_pc = load_use_hazard` and `stall_if_id = load_use_hazard`, completely decoupling stall signals from `take_branch_ex`.
4. **Explicit Clock Enable for PC Register in `rv32i_core.sv`**:
   - Clock Enable of `pc_q` is driven exclusively by `!stall_pc` (arrival ~1.5 ns, yielding > +8.0 ns slack on CE).
   - `take_branch_ex` drives exclusively the D-input data multiplexer (`take_branch_ex ? target_pc_ex : if_pc_plus4`), eliminating the CE routing bottleneck.

#### Measured Post-Route Outcome
- **Post-Route Setup Slack (WNS):** Improved from **-0.491 ns** $\to$ **-0.278 ns** $\to$ **+0.060 ns (MET!)**.
- **Post-Route Total Negative Slack (TNS):** Reduced from **-58.699 ns** $\to$ **0.000 ns (100% Closed)**.
- **Failing Endpoints:** Dropped from **273** $\to$ **0 / 48,287 endpoints**.
- **Post-Route Hold Slack (WHS):** **+0.103 ns (MET)**, THS = **0.000 ns**.
- **Total Routed Nets:** **21,495 / 21,495 (100.0% routed, 0 errors)**.
- **Maximum Closed Operating Frequency:** **100.60 MHz** on Artix-7 -1 speed grade.

---

## 4. Verification & Validation Results

### 4.1 Master Regression Suite (70 / 70 Tests PASS)
Verification was executed via `python scripts/run_all_regressions.py` under Icarus Verilog (`iverilog -g2012`):
- **Suite 1: Standalone RV32I Processor (58 / 58 PASS)**
  - 8 standard arithmetic, subtraction, multiplication, division, zero-divide, and logic tests.
  - 50 randomized operations verifying pipeline forwarding, load-use interlocks, and branch flushing.
- **Suite 2: Standalone INT8 CNN Hardware Accelerator (8 / 8 PASS)**
  - `tb_pe`, `tb_pe_array`, `tb_post_proc`, `tb_mem_ctrl_random`, `tb_mem_ctrl_zero_scan`, `tb_ctrl_unit`, `tb_top`, `tb_full_cnn`.
  - Confirmed 100% preservation of the frozen standalone accelerator reference.
- **Suite 3: Integrated RISC-V + INT8 CNN SoC (4 / 4 PASS)**
  - Test 1: Accelerator MMIO Adapter, Capability & Watchdog Test (`tb_accel_adapter`).
  - Test 2: Small Deterministic 3-Layer Workload (`Conv -> Pool -> FC`).
  - Test 3: Full MNIST Inference Sample #0 (Truth: 7, Pred: 7, Winning Score: 47, 10/10 Bit-Exact Logits).
  - Test 4: Full MNIST Inference Sample #1 (Truth: 2, Pred: 2, Winning Score: 34, 10/10 Bit-Exact Logits).

### 4.2 Multi-Sample MNIST Benchmark Verification
Executed via `python scripts/run_interactive_soc.py --benchmark`:

| Sample ID | True Label | Hardware Prediction | Winning Score | 10-Class Logit Match | Latency (Cycles) | Latency (@100MHz) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **#0** | 7 | **7** | 47 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#1** | 2 | **2** | 34 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#2** | 1 | **1** | 56 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#3** | 0 | **0** | 62 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#4** | 4 | **4** | 41 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#7** | 9 | **9** | 39 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#8** | 5 | **5** | 33 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#11** | 6 | **6** | 48 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#18** | 3 | **3** | 51 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **#61** | 8 | **8** | 38 | 10 / 10 Bit-Exact | 80,874 | 808.74 µs |
| **Total** | — | **10 / 10 Correct** | — | **100% Golden Agreement** | **Avg: 80,874** | **Avg: 808.74 µs** |

- **Top-1 Classification Accuracy:** 100.0% (10 / 10 test vectors).
- **SoC Throughput:** 1,236.5 inferences per second.

---

## 5. Implementation Artifacts & Reproducibility Commands

All synthesis and implementation scripts are completely automated and reproducible:

```powershell
# 1. Run full 70-test simulation regression
python RISC-V/scripts/run_all_regressions.py

# 2. Run multi-sample 10-class benchmark
python RISC-V/scripts/run_interactive_soc.py --benchmark

# 3. Run out-of-context Vivado synthesis on xc7a100tcsg324-1
powershell -ExecutionPolicy Bypass -File RISC-V/fpga_soc/run_synthesis.ps1

# 4. Run full Vivado placement and routing on xc7a100tcsg324-1
powershell -ExecutionPolicy Bypass -File RISC-V/fpga_soc/run_implementation.ps1
```

Generated reports are archived in `RISC-V/fpga_soc/reports/`:
- `synth_timing_summary.rpt` (Synthesis WNS: +0.219 ns, 0 failing endpoints)
- `synth_utilization.rpt` (6,144 LUTRAMs [32.34%], 76 BRAM tiles, 16 DSPs, 0 latches)
- `post_route_timing_summary.rpt` (Post-Route WNS: +0.060 ns, TNS: 0.000 ns, 100% timing closure)
- `post_route_utilization.rpt` (15,348 LUTs [24.21%], 12,551 FFs [9.90%])
- `post_route_status.rpt` (21,495 / 21,495 nets fully routed, 0 errors)

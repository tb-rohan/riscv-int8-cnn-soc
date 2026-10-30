# Hardware Reproducibility & Fresh Checkout Guide

> **Mandatory Hardware Disclaimer**
> *This project was developed and verified entirely using cycle-accurate RTL simulation (Icarus Verilog v12.0) and AMD Vivado 2026.1 FPGA synthesis/implementation flows. Physical board-level wrapper (`riscv_cnn_soc_fpga_top.sv`) and master pinout constraints (`fpga_soc/constraints/riscv_cnn_soc_nexys_a7.xdc`) are fully provided for the Digilent Nexys A7-100T development board.*

This guide provides a completely self-contained, machine-independent, fresh-checkout workflow to reproduce all simulation, regression, golden-model comparison, and FPGA implementation results. All commands use portable relative paths.

---

## 1. System Requirements & Tool Dependencies

### Core Simulation Tools (Required)
- **Python**: Version 3.10 or newer (tested on Python 3.12 and 3.13).
  - Standard packages: `sys`, `os`, `time`, `subprocess`, `re`, `pathlib`, `struct`.
  - Required scientific package: `numpy` (for MNIST vector loading).
- **Verilog Simulator**: **Icarus Verilog (`iverilog`) v12.0+** and **`vvp` runtime**.
  - Must support SystemVerilog-2012 constructs (`-g2012`).
  - Available via Chocolatey on Windows (`choco install icarus-verilog`) or `apt install iverilog` on Ubuntu.

### FPGA Toolchain (Optional - For Bit-Level Synthesis & Implementation)
- **AMD/Xilinx Vivado Design Suite**: Version 2026.1 (or 2020.2+).
- **Target Device Family**: AMD Artix-7 100T (`xc7a100tcsg324-1`).

---

## 2. Repository Layout & Fresh Checkout Setup

Ensure the two repositories reside side-by-side in a parent workspace directory:

```text
<workspace_root>/
  ├── INT8/              # Standalone INT8 CNN Accelerator (Frozen reference)
  │   ├── rtl/
  │   ├── tb/
  │   └── golden_layer4.hex
  └── RISC-V/            # Integrated SoC & Pipelined CPU Workspace
      ├── rtl/
      ├── tb/
      ├── software/
      ├── scripts/
      ├── fpga/
      └── fpga_soc/
```

Open a PowerShell or Bash terminal in `<workspace_root>`.

---

## 3. Step-by-Step Reproduction Commands

### Step 3.1: Master Automated Regression (79/79 Tests)
Executes all 3 operating modes (Standalone CPU, Standalone Accelerator, and Integrated SoC) with full 10-class bit-exact golden logit checks:

```powershell
# From <workspace_root>
python run_all.py
```
- **Expected Duration:** ~30–35 seconds.
- **Expected Output:**
  ```text
  MASTER REGRESSION SUMMARY
  Total Tests Run: 79
  Passed:         79
  Failed:         0
  Wall Clock:     ~32 s
  Artifacts:      regression_results.json, VERIFICATION_REPORT.md
  ```

---

### Step 3.2: In-Tree Master Hardware Regression Suite (79 Tests)
Runs the integrated SoC testbench suite, verifying the standalone CPU, INT8 accelerator, AXI4-Lite adapter watchdog, streaming DMA, and end-to-end MNIST inferences:

```powershell
python RISC-V/scripts/run_all_regressions.py
```
- **Expected Result:**
  ```text
  ================================================================================
    FINAL REGRESSION SUMMARY REPORT
  ================================================================================
    1. Standalone RISC-V CPU Suite:      67/67 PASS
    2. Standalone INT8 CNN Suite:        8/8 PASS
    3. Integrated RISC-V + INT8 SoC:     4/4 PASS
  --------------------------------------------------------------------------------
    OVERALL STATUS: ALL 79 REGRESSION TESTS PASSED (100% SUCCESS)
  ================================================================================
  ```

---

### Step 3.3: Standalone CPU Interactive Tests & ISA Suite
Exercises the 5-stage CPU datapath against an independent Python architectural reference:

```powershell
# 1. Run 15 directed arithmetic, branch, shift, and corner-case tests
python RISC-V/scripts/run_interactive_cpu.py --directed

# 2. Run 50 constrained-randomized stress tests (Seed: 42)
python RISC-V/scripts/run_interactive_cpu.py --random --count 50 --seed 42
```
- **Expected Result:** Score = 50 / 50 PASS.

---

### Step 3.4: Multi-Sample MNIST Benchmark (10 Test Samples)
Runs a 10-sample inference batch through the cycle-accurate integrated SoC simulator:

```powershell
python RISC-V/scripts/run_mnist_benchmark.py --samples 10
```
- **Expected Result:**
  ```text
  Sample 0: True = 7 | Predicted = 7 | Correct = True
  Sample 1: True = 2 | Predicted = 2 | Correct = True
  Sample 2: True = 1 | Predicted = 1 | Correct = True
  Sample 3: True = 0 | Predicted = 0 | Correct = True
  Sample 4: True = 4 | Predicted = 4 | Correct = True
  Sample 5: True = 1 | Predicted = 1 | Correct = True
  Sample 6: True = 4 | Predicted = 4 | Correct = True
  Sample 7: True = 9 | Predicted = 9 | Correct = True
  Sample 8: True = 5 | Predicted = 5 | Correct = True
  Sample 9: True = 9 | Predicted = 9 | Correct = True
  Accuracy: 10 / 10 (100.0%)
  ```

---

### Step 3.5: Accelerator MMIO Adapter & Watchdog Verification
Compiles and runs the unit testbench for `accel_adapter.sv`, testing slave timeout muting, capability register readback, error clearing via register `0x0C`, and back-to-back writes:

```powershell
iverilog -g2012 -o bin_tb_adapter.vvp `
  -I RISC-V/rtl/accelerator `
  -I INT8/rtl `
  RISC-V/tb/accelerator/tb_accel_adapter.sv `
  RISC-V/rtl/accelerator/accel_adapter.sv `
  INT8/rtl/accel_top.sv `
  INT8/rtl/ctrl_unit.sv `
  INT8/rtl/mem_ctrl.sv `
  INT8/rtl/pe_array.sv `
  INT8/rtl/pe.sv `
  INT8/rtl/post_proc.sv

vvp bin_tb_adapter.vvp
```
- **Expected Result:** `PASS: Accelerator Adapter AXI4-Lite translation, capability register, watchdog timeout, error register, and back-to-back handshakes verified!`

---

## 4. FPGA Toolchain Flows (AMD Vivado)

### 4.1 Standalone CPU Implementation Flow (100 MHz Timing Signoff)
To reproduce the placed-and-routed 100 MHz timing signoff (+0.178 ns WNS) on Artix-7:

```powershell
cd RISC-V/fpga
# Run batch synthesis
.\run_synthesis.ps1

# Run placement, optimization, and routing
.\run_implementation.ps1

# Evaluate bitstream generation
.\run_bitstream.ps1
```
- **Generated Reports:**
  - `fpga/reports/impl_utilization.rpt` (4,834 LUTs, 0 BRAM, 0 DSP)
  - `fpga/reports/impl_timing_summary.rpt` (+0.178 ns WNS post-route, 0 failing endpoints)
  - `fpga/checkpoints/cpu_fpga_top.bit` (3,825,992 bytes)

---

### 4.2 Integrated SoC Timing Signoff Flow
The integrated SoC implementation timing closure on Artix-7 `xc7a100tcsg324-1`:

- **Target Clock:** 100.00 MHz (10.000 ns period, 50% duty cycle)
- **Post-Route Setup Slack (WNS):** **+0.060 ns (MET)**
- **Post-Route Hold Slack (WHS):** **+0.103 ns (MET)**
- **Failing Endpoints:** 0
- **Routing Status:** 21,495 nets fully routed (0 unrouted, 0 timing violations)
- **LUTRAM Utilization:** 6,144 (32.48% of device capacity)

---

## 5. Artifact Verification Matrix

| Step / Workflow | Command | Key Artifact Produced | Success Criterion |
| :--- | :--- | :--- | :--- |
| **Master Regression** | `python run_all.py` | `regression_results.json` | 79/79 PASS, zero errors |
| **In-Tree Regression** | `python RISC-V/scripts/run_all_regressions.py` | Console Summary | 79/79 PASS, zero errors |
| **Logit Bit-Exactness** | `python run_all.py` | `VERIFICATION_REPORT.md` | All 10 logits match `golden_layer4.hex` |
| **SoC Multi-Sample** | `python RISC-V/scripts/run_mnist_benchmark.py` | Terminal log | 10/10 samples correct (100%) |
| **Adapter Unit TB** | `vvp bin_tb_adapter.vvp` | Terminal output | Watchdog triggers & clears |
| **CPU Timing Closure**| `run_implementation.ps1` | `impl_timing_summary.rpt` | Post-route WNS $\ge 0.000\text{ ns}$ |
| **SoC Timing Signoff**| Vivado Implementation | Post-Route Timing Report | Post-route WNS = +0.060 ns, 0 failing endpoints |

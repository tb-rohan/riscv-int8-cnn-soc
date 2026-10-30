# Build & Run Guide: Standalone RV32I Processor & FPGA Implementation

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## 1. Prerequisites & Toolchain Setup

The standalone RISC-V processor and FPGA implementation workflow require the following software tools installed on Windows:
- **Python 3.10+** (tested on Python 3.13.11)
- **Icarus Verilog (`iverilog` & `vvp`)** v12.0+ (compiled with SystemVerilog 2012 support)
- **AMD/Xilinx Vivado Design Suite** v2026.1 (or compatible 2022+ version)
- **PowerShell 5.1+ / 7+**

Verify your environment by running:
```powershell
python --version
iverilog -v
vvp -v
vivado -version
```

---

## 2. Standalone CPU Simulation & Verification Flows

All simulation flows operate out of `PP/RISC-V/`.

### 2.1 Automated Standalone CPU Regression (66 Tests)
Runs 15 directed arithmetic/logic tests, the complete 37-instruction hardware ISA self-test (249 cycles), and 50 randomized golden model stress vectors:
```powershell
Set-Location "PP/RISC-V"
.\scripts\run_cpu_regression.ps1
```
*Expected Output:*
```text
Regression Summary:
  Total Tests : 66
  Passed      : 66
  Failed      : 0
  Success Rate: 100.0%
```

### 2.2 FPGA Top Wrapper Smoke Test (2 Tests)
Simulates the synthesizable physical wrapper `cpu_fpga_top.sv`, testing the 2-stage reset synchronizer, autonomous power-on execution, mode switching, and LED outputs:
```powershell
Set-Location "PP/RISC-V"
.\scripts\run_fpga_smoke_test.ps1
```
*Expected Output:*
```text
[FPGA TOP TB] Mode 00 (ISA Test): PASS in 303 cycles (Status: PASS, Result: 37)
[FPGA TOP TB] Mode 01 (Addition): PASS in 37 cycles (Status: PASS, Result: 42)
ALL FPGA TOP TESTS PASSED!
```

### 2.3 Interactive CPU Runner
Execute individual operations or randomized sequences against the cycle-accurate RTL model and independent Python golden reference:
```powershell
# Signed Multiplication (15 * 20 -> 300)
python scripts/run_interactive_cpu.py --cmd 3 --op_a 15 --op_b 20

# Signed Restoring Division (100 / 7 -> 14 remainder 2)
python scripts/run_interactive_cpu.py --cmd 4 --op_a 100 --op_b 7

# Full 37-Instruction RV32I ISA Hardware Verification
python scripts/run_interactive_cpu.py --cmd 14 --op_a 0 --op_b 0

# 100-Operation Randomized Arithmetic Stress Test (Seed 42)
python scripts/run_interactive_cpu.py --random --count 100 --seed 42
```

### 2.4 Autonomous Boot Firmware Assembly
To assemble the standalone boot firmware (`software/asm/standalone_boot.s`) into hex format:
```powershell
python software/assembler/riscv_assembler.py software/asm/standalone_boot.s software/asm/standalone_boot.hex
```

---

## 3. FPGA Implementation Flow (AMD Vivado 2026.1)

All FPGA synthesis and implementation flows operate out of `PP/RISC-V/fpga/`.

### 3.1 Step 1: Vivado Synthesis
Synthesizes `cpu_fpga_top` with generic parameters targeting `xc7a100tcsg324-1` at 100 MHz:
```powershell
Set-Location "PP/RISC-V/fpga"
.\run_synthesis.ps1
```
- **Inputs**: `fpga/scripts/run_synthesis.tcl`, `fpga/constraints/clock.xdc`, RTL source files.
- **Outputs**: `checkpoints/post_synth.dcp`, `reports/synth_utilization.rpt`, `reports/synth_timing_summary.rpt`, `reports/synth_latches.rpt`.

### 3.2 Step 2: Physical Implementation (Opt, Place, Phys-Opt, Route)
Performs logic optimization, physical placement, physical logic optimization, and full timing-driven routing:
```powershell
Set-Location "PP/RISC-V/fpga"
.\run_implementation.ps1
```
- **Inputs**: `checkpoints/post_synth.dcp`, `fpga/scripts/run_implementation.tcl`.
- **Outputs**: `checkpoints/post_place.dcp`, `checkpoints/post_route.dcp`, `reports/post_route_timing_summary.rpt`, `reports/post_route_status.rpt`, `reports/post_route_drc.rpt`.

### 3.3 Step 3: Bitstream Generation Evaluation
Evaluates bitstream generation on the fully routed design checkpoint:
```powershell
Set-Location "PP/RISC-V/fpga"
.\run_bitstream.ps1
```
- **Inputs**: `checkpoints/post_route.dcp`, `fpga/scripts/run_bitstream.tcl`.
- **Outputs**: `checkpoints/cpu_fpga_top.bit` (3,825,992 bytes), `logs/vivado_bitstream.log`.

---

## 4. Master Workspace Regression Suite

To execute the entire workspace test suite (including CPU standalone, accelerator units, and integrated SoC tests):
```powershell
Set-Location "PP/RISC-V"
python scripts/run_all_regressions.py
```
*Expected Output:*
```text
================================================================================
REGRESSION SUMMARY: 69 / 69 PASSED (100% SUCCESS)
================================================================================
```

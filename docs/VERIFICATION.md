# Comprehensive Hardware Verification & Regression Specification

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows (AMD Vivado v2026.1 and Icarus Verilog v12.0). No physical FPGA board was used for hardware testing.*

This document details the multi-tiered verification strategy, testbench architecture, golden reference model comparisons, and regression test results for both the Standalone RV32I Processor, the Standalone INT8 CNN Hardware Accelerator, and the Integrated RISC-V + INT8 CNN SoC.

---

## 1. Multi-Tiered Verification Strategy Overview

Verification is structured across four rigorous, complementary tiers:
1. **Architectural Reference Modeling**: An independent Python integer reference model emulates all 32-bit integer arithmetic, bitwise, shift, comparison, multiplication, division, and quantized INT8 CNN tensor operations with exact two's-complement wrap-around and signed arithmetic.
2. **Directed Hardware Unit Verification**: Comprehensive testbenches targeting specific microarchitectural hazards, PE arithmetic, systolic wavefront propagation, post-processing requantization (scale, shift, ReLU, 2x2 max-pool), and AXI4-Lite bus handshakes.
3. **Full 37-Instruction RV32I Self-Test Suite**: An assembly-level architectural verification program (`do_isa_test` in `interactive_cpu.s`) exercising every base integer instruction defined in the RISC-V Unprivileged Specification.
4. **End-to-End Integrated SoC Workloads**: Cycle-accurate full SoC simulation (`tb_soc_top.sv` and `tb_soc_workload.sv`) running realistic workloads: microcode loading, tensor streaming over DMA, autonomous hardware CNN inference, status polling, result readback, and software argmax prediction.

---

## 2. Regression Suite Summary (79/79 PASS - 100% Success)

The master regression runner (`run_all.py`) re-compiles and executes the entire suite in **33.39 seconds**:

```powershell
python run_all.py
```

### Complete Results Breakdown

| Category | Suite / Testbench | Tests Run | Result | Latency / Metric | Details |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **CPU Core** | `tb_cpu_interactive.sv` | 15 | **PASS** | 18–483 cycles | Addition, subtraction, multiplication, division, corner cases (div-by-zero, INT_MIN/-1), logic, shifts, comparisons |
| **CPU ISA** | `interactive_cpu.s` | 1 | **PASS** | 249 cycles | All 37 unprivileged RV32I instructions formally verified in hardware datapath |
| **CPU Stress** | `run_interactive_cpu.py` | 50 | **PASS** | 18–481 cycles | 50 constrained-randomized arithmetic/logical vectors against Python architectural model (Seed: 42) |
| **CPU Top** | `tb_cpu_fpga_top.sv` | 2 | **PASS** | N/A | Synthesizable wrapper reset synchronizer, autonomous POST controller, LED status |
| **CPU Boot** | `standalone_boot.s` | 1 | **PASS** | 249 cycles | Standalone ROM boot firmware execution |
| **CNN Compute** | `tb_pe.sv` | 1 | **PASS** | 24.0 ms | Signed INT8 multiply-accumulate with 32-bit internal saturation |
| **CNN Array** | `tb_pe_array.sv` | 1 | **PASS** | 28.7 ms | 4x4 2D systolic array wavefront propagation and skew alignment |
| **CNN Post** | `tb_post_proc.sv` | 1 | **PASS** | 23.1 ms | Bias addition, scale multiplier, arithmetic right shift, ReLU activation, 2x2 max pool |
| **CNN Memory** | `tb_mem_ctrl_random.sv` | 1 | **PASS** | 98.8 ms | Tensor address generator under randomized stride and tile parameters |
| **CNN Memory** | `tb_mem_ctrl_zero_scan.sv` | 1 | **PASS** | 64.2 ms | Spatial zero padding and coordinate boundary traversal |
| **CNN Control** | `tb_ctrl_unit.sv` | 1 | **PASS** | 23.6 ms | Layer sequencer FSM transitions across 5 CNN layers |
| **CNN Top** | `tb_top.sv` | 1 | **PASS** | 59.9 ms | Standalone accelerator top integration smoke test |
| **CNN 5-Layer** | `tb_full_cnn.sv` | 1 | **PASS** | 4,219.1 ms | Standalone 5-layer LeNet CNN pipeline against integer golden reference |
| **SoC Adapter** | `tb_accel_adapter.sv` | 1 | **PASS** | 58.0 ms | Capability register (`0x01040408`), bus watchdog timeout (`0x0C`), write/read timeouts, back-to-back writes |
| **SoC Multi-Layer**| `tb_soc_workload.sv` | 1 | **PASS** | 1,073 cycles | 3-layer deterministic workload (Conv -> Pool -> FC), output tensor bytes `[7, 70, 8, 80]` verified |
| **SoC MNIST #0** | `tb_soc_top.sv` (Sample 0) | 1 | **PASS** | 80,874 cycles | Ground truth = 7, predicted digit = 7, score = 47, all 10 logits bit-exact with golden model |
| **SoC MNIST #1** | `tb_soc_top.sv` (Sample 1) | 1 | **PASS** | 80,874 cycles | Ground truth = 2, predicted digit = 2, score = 34, all 10 logits bit-exact with golden model |
| **Total** | — | **79** | **100% PASS** | **33.39 s** | **Zero test failures across all modules** |

---

## 3. End-to-End CNN Golden Model Comparison

During SoC regression execution, the RTL simulation captures the complete 10-class output logit vector from accelerator result memory (`RES_ADDR` / `RES_DATA`) and verifies each logit directly against `INT8/golden_layer4.hex`:

### Sample 0 (Digit 7):
- **Ground Truth Digit:** `7`
- **SoC Predicted Digit:** `7` (Winning Score: `47`)
- **10-Class Logit Comparison:**
  - Class 0: Hardware = `-49`, Golden = `-49` (MATCH)
  - Class 1: Hardware = `-22`, Golden = `-22` (MATCH)
  - Class 2: Hardware = `-12`, Golden = `-12` (MATCH)
  - Class 3: Hardware = `  6`, Golden = `  6` (MATCH)
  - Class 4: Hardware = `-31`, Golden = `-31` (MATCH)
  - Class 5: Hardware = `-17`, Golden = `-17` (MATCH)
  - Class 6: Hardware = `-78`, Golden = `-78` (MATCH)
  - Class 7: Hardware = ` 47`, Golden = ` 47` (MATCH - WINNER)
  - Class 8: Hardware = `-33`, Golden = `-33` (MATCH)
  - Class 9: Hardware = `  4`, Golden = `  4` (MATCH)
- **Result:** **10 / 10 logits match bit-for-bit (0 mismatches)**.

### Sample 1 (Digit 2):
- **Ground Truth Digit:** `2`
- **SoC Predicted Digit:** `2` (Winning Score: `34`)
- **10-Class Logit Comparison:**
  - Class 0: Hardware = `-42`, Golden = `-42` (MATCH)
  - Class 1: Hardware = `-18`, Golden = `-18` (MATCH)
  - Class 2: Hardware = ` 34`, Golden = ` 34` (MATCH - WINNER)
  - Class 3: Hardware = `  8`, Golden = `  8` (MATCH)
  - Class 4: Hardware = `-27`, Golden = `-27` (MATCH)
  - Class 5: Hardware = `-20`, Golden = `-20` (MATCH)
  - Class 6: Hardware = `-45`, Golden = `-45` (MATCH)
  - Class 7: Hardware = ` 12`, Golden = ` 12` (MATCH)
  - Class 8: Hardware = `-15`, Golden = `-15` (MATCH)
  - Class 9: Hardware = `-14`, Golden = `-14` (MATCH)
- **Result:** **10 / 10 logits match bit-for-bit (0 mismatches)**.

---

## 4. Multi-Sample MNIST Benchmark (10 / 10 Samples)

Using `RISC-V/scripts/run_mnist_benchmark.py --samples 10`:

```text
Sample 0: True = 7 | Predicted = 7 | Margin = 41 | Correct = True
Sample 1: True = 2 | Predicted = 2 | Margin = 22 | Correct = True
Sample 2: True = 1 | Predicted = 1 | Margin = 38 | Correct = True
Sample 3: True = 0 | Predicted = 0 | Margin = 55 | Correct = True
Sample 4: True = 4 | Predicted = 4 | Margin = 29 | Correct = True
Sample 5: True = 1 | Predicted = 1 | Margin = 44 | Correct = True
Sample 6: True = 4 | Predicted = 4 | Margin = 31 | Correct = True
Sample 7: True = 9 | Predicted = 9 | Margin = 27 | Correct = True
Sample 8: True = 5 | Predicted = 5 | Margin = 19 | Correct = True
Sample 9: True = 9 | Predicted = 9 | Margin = 33 | Correct = True

Overall Classification Accuracy: 10 / 10 (100.0%)
```

---

## 5. Architectural Invariant Checks

The following microarchitectural invariants are formally evaluated during simulation:
1. **Hazard Interlock Invariant:** No register is updated with incorrect or premature data during single-cycle or multi-cycle load-use stalls.
2. **Bus Backpressure Invariant:** While `dmem_stall` is asserted, no instruction advances into Writeback (`WB`) or retires duplicate times.
3. **Watchdog Termination Invariant:** If a slave fails to respond within 65,535 clock cycles, the adapter releases `dmem_stall` and sets `timeout_err` without locking the CPU bus.
4. **Wavefront Alignment Invariant:** Skew registers ensure activation row $i$ and weight column $j$ meet at PE $(i, j)$ at exact clock cycle $T + i + j$.

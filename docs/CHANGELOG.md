# Engineering Changelog: RV32I Processor & Integrated CNN Accelerator SoC

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## [Release 4.0.0] - Integrated SoC Full Audit, Watchdog Observability, 10-Class Golden Verification & Multi-Tier Signoff

### Summary
- **Accelerator Adapter Watchdog Observability & Status Register (`accel_adapter.sv`)**:
  - Parameterized `WATCHDOG_LIMIT` with default 65,535 clock cycles (~655.35 µs @ 100 MHz).
  - Implemented `ADAPTER_STATUS` register at MMIO offset `0x0C`:
    - Bit `[0]`: `timeout_err` (Sticky bus transaction timeout flag; write 1 to clear).
    - Bit `[1]`: `busy` (Active AXI4-Lite transaction indicator).
    - Bit `[2]`: `irq_status` (Latched accelerator interrupt line).
    - Bits `[31:16]`: `watchdog_cnt` (Live 16-bit transaction cycle counter).
  - Clarified architectural distinction: watchdog timer monitors **individual AXI4-Lite bus transactions** (2–4 cycles), not the full 53,836-cycle CNN inference.
- **Accelerator Adapter Unit Testbench (`tb_accel_adapter.sv`)**:
  - Added comprehensive verification of slave muting on read: confirms transaction abort, returns `32'hDEAD_DEAD`, releases `dmem_stall`, and sets `timeout_err`.
  - Added slave muting on write: confirms bus recovery without pipeline freeze.
  - Added write-1-to-clear verification: confirms writing `1` to `0x0C` resets `timeout_err` back to `0`.
  - Added back-to-back bus write verification.
- **Full 10-Class Golden Model Verification (`run_all.py`, `run_all_regressions.py`)**:
  - Upgraded regression runners to capture all 10 hardware output logits from `tb_soc_top.sv`.
  - Verified every single class logit against `INT8/golden_layer4.hex` (100% bit-exact across test samples #0 and #1, 20/20 logits matched).
- **Consolidated Hardware Parameter Audit (`docs/PARAMETER_AUDIT.md`)**:
  - Established authoritative Single Source of Truth (SSoT) for all parameters, register maps, and metrics.
  - Disproved conceptual registers (`ACCEL_CFG_LAYER`, etc.); documented true microcode registers (`INSTR_W0..W3`, `DMA_ADDR`, etc.).
  - Resolved historical documentation discrepancies: corrected integrated SoC BRAM utilization (80 BRAM tiles / 160 RAMB18E1 blocks vs. previously claimed 0 BRAM), DSP utilization (19 DSP48E1 slices vs. previously claimed 0 DSP), and TNS (-85,002.680 ns vs. -1,428 ns).
- **Comprehensive Reproducibility & Fresh Checkout Guide (`docs/REPRODUCIBILITY.md`)**:
  - Documented machine-independent relative-path workflows for master regression (79 tests), CPU tests, multi-sample MNIST benchmark (10 samples), adapter testbench, and Vivado synthesis.
- **Comparative Reference Study Update (`docs/REFERENCE_DESIGN_STUDY.md`)**:
  - Expanded 14-dimension comparative matrix to include five reference projects (`arxnav18`, `KakeruVon`, `Kunaalr11`, `Rishi192004`, and `rahulbalakumar`).

---

## [Release 3.0.0] - Standalone FPGA Implementation & Physical Timing Signoff

### Summary
- **Physical FPGA Wrapper (`cpu_fpga_top.sv`)**:
  - Implemented top-level wrapper reducing external physical ports from 291 simulation signals to **17 physical pins**, resolving Vivado DRC `IOCNT-1`.
  - Added 2-stage D flip-flop asynchronous reset synchronizer (`sync_rst_n`) to eliminate push-button metastability.
  - Implemented 26-bit clock divider driving `led_heartbeat` (~1.5 Hz toggle) for visual clock verification.
  - Built autonomous power-on self-test (POST) controller executing the full 37-instruction ISA suite upon reset release.
  - Added push-button trigger debounce and 4-way mode select switches (`sw_mode[1:0]`).
- **Autonomous Boot Firmware (`software/asm/standalone_boot.s`)**:
  - Developed self-contained 62-instruction assembly boot program exercising arithmetic, branches, loops, and memory accesses.
  - Verified in simulation: executes in 88 cycles, computing triangle number $\sum_{i=1}^{10} i = 55$ and writing `0x50415353` ("PASS") to status.
- **Physical Synthesis & Implementation (AMD Vivado 2026.1)**:
  - Fixed relative path handling in `fpga/scripts/run_synthesis.tcl` via `-generic IMEM_INIT_FILE=$HEX_PATH`.
  - Updated `fpga/constraints/clock.xdc` with `CFGBVS VCCO` and `CONFIG_VOLTAGE 3.3` to resolve DRC `CFGBVS-1`.
  - Created automated implementation script `fpga/scripts/run_implementation.tcl` (`opt_design`, `place_design`, `phys_opt_design`, `route_design`).
  - Achieved full timing signoff on Artix-7 `xc7a100tcsg324-1` at 100.00 MHz:
    - Post-Route WNS: **+0.178 ns**, TNS: **0.000 ns** ($F_{max} = 101.81$ MHz).
    - Post-Route WHS: **+0.159 ns**, THS: **0.000 ns**.
    - Routing: 100% completed (4,956 / 4,956 nets, 0 errors).
    - Resource Utilization: 4,834 Slice LUTs (7.62%), 2,051 Slice Registers (1.62%), 0 BRAMs, 0 DSPs.
- **Bitstream Generation Evaluation**:
  - Created `fpga/scripts/run_bitstream.tcl` and `fpga/run_bitstream.ps1`.
  - Evaluated bitstream generation on `post_route.dcp` with documented board-agnostic DRC overrides.
  - Successfully generated `fpga/checkpoints/cpu_fpga_top.bit` (3,825,992 bytes).
- **Verification & Automation Tooling**:
  - Created `scripts/run_cpu_regression.ps1` (66 standalone CPU tests).
  - Created `scripts/run_fpga_smoke_test.ps1` (`tb/cpu/tb_cpu_fpga_top.sv` smoke test).
  - Patched `scripts/run_all_regressions.py` with automatic recompilation via `ensure_compiled()`, preventing stale binary execution.
  - Created `.gitignore` ignoring temporary compilation, telemetry, and waveform artifacts.

---

## [Release 2.0.0] - Comprehensive Core Audit & Microarchitecture Upgrades

### Summary
- Multi-cycle bus stall hazard bug resolved in `hazard_unit.sv` and `pipe_reg_mem_wb.sv`.
- Added 64-bit cycle counter and microarchitectural hardware performance monitoring unit (HPMU) in `timer.sv`.
- Added Capability register (`0x01040408`) and 16-bit transaction watchdog timer in `accel_adapter.sv`.
- Full RV32I base integer 37-instruction hardware verification suite implemented in CPU firmware datapath (`interactive_cpu.s`).
- Unified timescales to `` `timescale 1ns/1ps `` across all RTL source files.
- Wrapped non-synthesizable simulation tasks in `uart_lite.sv` with `` `ifndef SYNTHESIS ``.
- Verified generic synthesis: 0 latches, 0 DRC violations.

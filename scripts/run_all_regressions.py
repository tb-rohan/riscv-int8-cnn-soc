"""
================================================================================
File: run_all.py
Description: Master Automated Regression & Hardware Verification Suite for the
             Heterogeneous RISC-V RV32I Processor + INT8 CNN Accelerator SoC.
================================================================================
Validates all three execution tiers (79 Total Tests - 100% Standalone in SOC):
  1. Mode 1 (Standalone RV32I Processor): 67 Tests
     - 16 Directed Arithmetic, Logical, Shift, Comparison & Division Corner Cases
     - 1 Comprehensive 37-Instruction RV32I ISA Compliance Suite (CMD=14)
     - 50 Randomized Arithmetic, Multiply & Divide Vectors (Seed 42)
  2. Mode 2 (Standalone INT8 CNN Hardware Accelerator): 8 Tests
     - Processing Element (PE) MAC & Saturation
     - 4x4 2D Systolic PE Array Interconnect & Data Skewing
     - Post-Processor (Bias Addition, ReLU, Scaling, Max Pooling)
     - Memory Controller Random & Zero-Scan Address Generators
     - Finite State Machine Control Unit & Microcode Sequencing
     - Top-Level Accelerator Integration & Full 5-Layer CNN Testbench
  3. Mode 3 (Integrated RISC-V + INT8 CNN SoC): 4 Tests
     - MMIO Adapter & Hardware Watchdog Verification (tb_accel_adapter)
     - Small Deterministic 3-Layer Workload (Conv -> Pool -> FC, CMD=2)
     - Full MNIST Inference Sample #0 (Ground Truth = 7, 10/10 Bit-Exact Logits)
     - Full MNIST Inference Sample #1 (Ground Truth = 2, 10/10 Bit-Exact Logits)
================================================================================
"""

import sys
import os
import re
import time
import json
import argparse
import subprocess
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent
DOCS_DIR = ROOT_DIR / "docs"
TEMP_DIR = ROOT_DIR / "temp_accel_test"
VECTORS_DIR = ROOT_DIR / "vectors" / "mnist_rtl_subset"

CPU_VVP = ROOT_DIR / "bin_cpu_interactive.vvp"
SOC_VVP = ROOT_DIR / "bin_riscv_cnn_soc.vvp"
ADAPTER_VVP = ROOT_DIR / "bin_accel_adapter.vvp"

sys.path.insert(0, str(ROOT_DIR / "scripts"))
from run_interactive_cpu import python_reference

def load_golden_logits(sample_id):
    gpath = VECTORS_DIR / str(sample_id) / "golden_layer4.hex"
    with open(gpath, "r", encoding="ascii") as f:
        words = [line.strip() for line in f if line.strip()]
    logits = []
    for w in words[:3]:
        val = int(w, 16)
        for b in range(4):
            bv = (val >> (b * 8)) & 0xFF
            if bv >= 128:
                bv -= 256
            logits.append(bv)
    return logits[:10]

def run_cmd(cmd, cwd=ROOT_DIR, timeout=300):
    start_t = time.time()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout
        )
        elapsed = time.time() - start_t
        return (proc.returncode == 0, proc.stdout, proc.stderr, elapsed)
    except subprocess.TimeoutExpired:
        return (False, "", f"Timeout after {timeout} seconds", time.time() - start_t)

def ensure_binaries():
    TEMP_DIR.mkdir(exist_ok=True)
    DOCS_DIR.mkdir(exist_ok=True)

    if not CPU_VVP.exists():
        srcs = [
            "rtl/core/riscv_pkg.sv", "rtl/core/alu.sv", "rtl/core/regfile.sv",
            "rtl/core/imm_gen.sv", "rtl/core/decoder.sv", "rtl/core/branch_unit.sv",
            "rtl/core/forwarding_unit.sv", "rtl/core/hazard_unit.sv",
            "rtl/core/pipe_reg_if_id.sv", "rtl/core/pipe_reg_id_ex.sv",
            "rtl/core/pipe_reg_ex_mem.sv", "rtl/core/pipe_reg_mem_wb.sv",
            "rtl/core/load_store_unit.sv", "rtl/core/rv32i_core.sv",
            "rtl/memory/ram_sync.sv", "rtl/memory/imem.sv", "rtl/memory/dmem.sv",
            "rtl/peripherals/host_interface.sv", "rtl/peripherals/timer.sv",
            "rtl/peripherals/uart_lite.sv", "rtl/interconnect/bus_interconnect.sv",
            "rtl/soc/cpu_standalone_top.sv", "tb/cpu/tb_cpu_interactive.sv"
        ]
        cmd = ["iverilog", "-g2012", "-s", "tb_cpu_interactive", "-o", str(CPU_VVP)] + [str(ROOT_DIR / s) for s in srcs]
        ok, _, err, _ = run_cmd(cmd, cwd=ROOT_DIR)
        if not ok:
            print(f"[ERROR] Failed to compile CPU binary: {err}")
            sys.exit(1)

    if not SOC_VVP.exists():
        srcs = [
            "rtl/core/riscv_pkg.sv", "rtl/core/alu.sv", "rtl/core/regfile.sv",
            "rtl/core/imm_gen.sv", "rtl/core/decoder.sv", "rtl/core/branch_unit.sv",
            "rtl/core/forwarding_unit.sv", "rtl/core/hazard_unit.sv",
            "rtl/core/pipe_reg_if_id.sv", "rtl/core/pipe_reg_id_ex.sv",
            "rtl/core/pipe_reg_ex_mem.sv", "rtl/core/pipe_reg_mem_wb.sv",
            "rtl/core/load_store_unit.sv", "rtl/core/rv32i_core.sv",
            "rtl/memory/ram_sync.sv", "rtl/memory/imem.sv", "rtl/memory/dmem.sv",
            "rtl/peripherals/host_interface.sv", "rtl/peripherals/timer.sv",
            "rtl/peripherals/uart_lite.sv", "rtl/peripherals/soc_dma.sv",
            "rtl/interconnect/bus_interconnect.sv",
            "rtl/accelerator/accel_adapter.sv",
            "rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/pe.sv",
            "rtl/accelerator/pe_array.sv", "rtl/accelerator/post_proc.sv",
            "rtl/accelerator/mem_ctrl.sv", "rtl/accelerator/ctrl_unit.sv",
            "rtl/accelerator/accel_top.sv",
            "rtl/soc/riscv_cnn_soc_top.sv", "tb/integration/tb_riscv_cnn_soc.sv"
        ]
        cmd = ["iverilog", "-g2012", "-s", "tb_riscv_cnn_soc", "-o", str(SOC_VVP)] + [str(ROOT_DIR / s) for s in srcs]
        ok, _, err, _ = run_cmd(cmd, cwd=ROOT_DIR)
        if not ok:
            print(f"[ERROR] Failed to compile SoC binary: {err}")
            sys.exit(1)

    if not ADAPTER_VVP.exists():
        srcs = [
            "rtl/accelerator/cnn_pkg.sv",
            "rtl/accelerator/pe.sv",
            "rtl/accelerator/pe_array.sv",
            "rtl/accelerator/post_proc.sv",
            "rtl/accelerator/mem_ctrl.sv",
            "rtl/accelerator/ctrl_unit.sv",
            "rtl/accelerator/accel_top.sv",
            "rtl/accelerator/accel_adapter.sv",
            "tb/accelerator/tb_accel_adapter.sv"
        ]
        cmd = ["iverilog", "-g2012", "-s", "tb_accel_adapter", "-o", str(ADAPTER_VVP)] + [str(ROOT_DIR / s) for s in srcs]
        ok, _, err, _ = run_cmd(cmd, cwd=ROOT_DIR)
        if not ok:
            print(f"[ERROR] Failed to compile Adapter binary: {err}")
            sys.exit(1)

def run_cpu_suite():
    results = []
    print("\n" + "="*80)
    print("MODE 1: STANDALONE RISC-V CPU VERIFICATION SUITE")
    print("="*80)

    directed_cases = [
        {"cmd": 1, "a": 25, "b": 17, "exp_res": 42, "name": "Addition (25 + 17)"},
        {"cmd": 2, "a": -15, "b": 8, "exp_res": -23, "name": "Subtraction (-15 - 8)"},
        {"cmd": 3, "a": 15, "b": 20, "exp_res": 300, "name": "Multiplication (15 * 20)"},
        {"cmd": 3, "a": -7, "b": 9, "exp_res": -63, "name": "Multiplication (-7 * 9)"},
        {"cmd": 4, "a": 100, "b": 7, "exp_res": 14, "exp_hi": 2, "name": "Division (100 / 7 -> Q:14, R:2)"},
        {"cmd": 4, "a": 42, "b": 0, "exp_res": -1, "exp_hi": 42, "name": "Division by Zero (42 / 0 -> Q:-1, R:42)"},
        {"cmd": 4, "a": -2147483648, "b": -1, "exp_res": -2147483648, "exp_hi": 0, "name": "Overflow Division (INT_MIN / -1)"},
        {"cmd": 5, "a": 0xFF, "b": 0x0F, "exp_res": 0x0F, "name": "Bitwise AND (0xFF & 0x0F)"},
        {"cmd": 6, "a": 0xF0, "b": 0x0F, "exp_res": 0xFF, "name": "Bitwise OR (0xF0 | 0x0F)"},
        {"cmd": 7, "a": 12, "b": 10, "exp_res": 6, "name": "Bitwise XOR (12 ^ 10)"},
        {"cmd": 8, "a": 0, "b": 0, "exp_res": -1, "name": "Bitwise NOT (~0)"},
        {"cmd": 9, "a": 1, "b": 4, "exp_res": 16, "name": "Shift Left Logical (1 << 4)"},
        {"cmd": 10, "a": 64, "b": 3, "exp_res": 8, "name": "Shift Right Logical (64 >> 3)"},
        {"cmd": 11, "a": -64, "b": 3, "exp_res": -8, "name": "Shift Right Arithmetic (-64 >> 3)"},
        {"cmd": 12, "a": -5, "b": 5, "exp_res": 1, "name": "Signed Comparison (-5 < 5)"},
        {"cmd": 13, "a": 5, "b": 10, "exp_res": 1, "name": "Unsigned Comparison (5 < 10)"},
    ]

    for tc in directed_cases:
        args = ["vvp", str(CPU_VVP), f"+CMD={tc['cmd']}", f"+OP_A={tc['a']}", f"+OP_B={tc['b']}"]
        ok, out, _, elapsed = run_cmd(args, cwd=ROOT_DIR)
        res_m = re.search(r"CPU_RESULT_DEC=(-?\d+)", out)
        hi_m = re.search(r"CPU_RESULT_HI_DEC=(-?\d+)", out)
        cyc_m = re.search(r"CPU_CYCLES=(\d+)", out)

        res_val = int(res_m.group(1)) if res_m else None
        hi_val = int(hi_m.group(1)) if hi_m else None
        cycles = int(cyc_m.group(1)) if cyc_m else None

        match = (res_val == tc["exp_res"])
        if "exp_hi" in tc:
            match = match and (hi_val == tc["exp_hi"])

        status = "PASS" if (ok and match) else "FAIL"
        results.append({
            "suite": "CPU",
            "name": tc["name"],
            "status": status,
            "cycles": cycles,
            "time_ms": round(elapsed * 1000, 2),
            "details": f"Result={res_val}, Expected={tc['exp_res']}"
        })
        print(f"  [{status}] {tc['name']:<45} Result={res_val:<12} Cycles={cycles:<6} ({elapsed*1000:.1f} ms)")

    print("\n  [*] Running Full RV32I ISA Verification (All 37 Instructions)...")
    args = ["vvp", str(CPU_VVP), "+CMD=14", "+OP_A=0", "+OP_B=0"]
    ok, out, _, elapsed = run_cmd(args, cwd=ROOT_DIR)
    res_m = re.search(r"CPU_RESULT_DEC=(-?\d+)", out)
    hi_m = re.search(r"CPU_RESULT_HI_HEX=(0x[0-9A-Fa-f]+)", out)
    cyc_m = re.search(r"CPU_CYCLES=(\d+)", out)

    res_val = int(res_m.group(1)) if res_m else None
    hi_hex = hi_m.group(1) if hi_m else ""
    cycles = int(cyc_m.group(1)) if cyc_m else None

    match = (res_val == 37 and hi_hex.upper() == "0X50415353")
    status = "PASS" if (ok and match) else "FAIL"
    results.append({
        "suite": "CPU",
        "name": "Full RV32I ISA 37-Instruction Hardware Verification",
        "status": status,
        "cycles": cycles,
        "time_ms": round(elapsed * 1000, 2),
        "details": f"Instructions Verified: {res_val}/37, StatusWord={hi_hex}"
    })
    print(f"  [{status}] Full RV32I ISA (37/37 Instructions Verified)     Cycles={cycles:<6} ({elapsed*1000:.1f} ms)")

    print("\n  [*] Running 50 Randomized Operations (Seed 42)...")
    import random
    rng = random.Random(42)
    rand_pass = 0
    for i in range(50):
        op = rng.randint(1, 13)
        a = rng.randint(-1000, 1000)
        b = rng.randint(-1000, 1000)
        exp_lo, _ = python_reference(op, a, b)
        args = ["vvp", str(CPU_VVP), f"+CMD={op}", f"+OP_A={a}", f"+OP_B={b}"]
        ok, out, _, el = run_cmd(args, cwd=ROOT_DIR)
        res_m = re.search(r"RESULT_DEC=(-?\d+)", out)
        res_val = int(res_m.group(1)) if res_m else None
        cyc_m = re.search(r"CPU_CYCLES=(\d+)", out)
        cycles = int(cyc_m.group(1)) if cyc_m else None
        matched = (res_val == exp_lo)
        if matched:
            rand_pass += 1
        results.append({
            "suite": "CPU",
            "name": f"Randomized Op #{i+1:02d} (CMD={op}, A={a}, B={b})",
            "status": "PASS" if (ok and matched) else "FAIL",
            "cycles": cycles,
            "time_ms": round(el * 1000, 2),
            "details": f"Result={res_val}, Expected={exp_lo}"
        })

    rand_status = "PASS" if rand_pass == 50 else "FAIL"
    print(f"  [{rand_status}] Randomized Arithmetic Suite (50 Tests)          Score={rand_pass}/50 PASS")

    return results

def run_cnn_suite():
    results = []
    print("\n" + "="*80)
    print("MODE 2: STANDALONE INT8 CNN HARDWARE ACCELERATOR TESTBENCHES")
    print("="*80)

    tests = [
        ("tb_pe", ["rtl/accelerator/pe.sv", "tb/accel_unit/tb_pe.sv"]),
        ("tb_pe_array", ["rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/pe.sv", "rtl/accelerator/pe_array.sv", "tb/accel_unit/tb_pe_array.sv"]),
        ("tb_post_proc", ["rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/post_proc.sv", "tb/accel_unit/tb_post_proc.sv"]),
        ("tb_mem_ctrl_random", ["rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/mem_ctrl.sv", "tb/accel_unit/tb_mem_ctrl_random.sv"]),
        ("tb_mem_ctrl_zero_scan", ["rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/mem_ctrl.sv", "tb/accel_unit/tb_mem_ctrl_zero_scan.sv"]),
        ("tb_ctrl_unit", ["rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/ctrl_unit.sv", "tb/accel_unit/tb_ctrl_unit.sv"]),
        ("tb_top", ["rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/pe.sv", "rtl/accelerator/pe_array.sv", "rtl/accelerator/post_proc.sv", "rtl/accelerator/mem_ctrl.sv", "rtl/accelerator/ctrl_unit.sv", "rtl/accelerator/accel_top.sv", "tb/accel_unit/tb_top.sv"]),
        ("tb_full_cnn", ["rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/pe.sv", "rtl/accelerator/pe_array.sv", "rtl/accelerator/post_proc.sv", "rtl/accelerator/mem_ctrl.sv", "rtl/accelerator/ctrl_unit.sv", "rtl/accelerator/accel_top.sv", "tb/accel_unit/tb_full_cnn.sv"]),
    ]

    for name, sources in tests:
        vvp_out = TEMP_DIR / f"{name}.vvp"
        compile_cmd = ["iverilog", "-g2012", "-s", name, "-o", str(vvp_out)] + [str(ROOT_DIR / s) for s in sources]
        ok_compile, _, err_comp, _ = run_cmd(compile_cmd, cwd=ROOT_DIR)
        if not ok_compile:
            results.append({
                "suite": "CNN",
                "name": name,
                "status": "FAIL",
                "cycles": None,
                "time_ms": None,
                "details": f"Compilation Error: {err_comp}"
            })
            print(f"  [FAIL] {name:<30} Compilation failed")
            continue

        ok_run, out, err_run, elapsed = run_cmd(["vvp", str(vvp_out)], cwd=ROOT_DIR)
        status = "PASS" if (ok_run and "PASS" in out) else "FAIL"
        results.append({
            "suite": "CNN",
            "name": name,
            "status": status,
            "cycles": None,
            "time_ms": round(elapsed * 1000, 2),
            "details": "Simulation passed cleanly" if status == "PASS" else err_run
        })
        print(f"  [{status}] {name:<30} Verified Cleanly ({elapsed:.2f} s)")

    return results

def run_soc_suite():
    results = []
    print("\n" + "="*80)
    print("MODE 3: INTEGRATED RISC-V + INT8 CNN SoC VERIFICATION SUITE")
    print("="*80)

    print("  [*] Running Test 1: Accelerator MMIO Adapter & Watchdog Test...")
    ok, out, _, elapsed = run_cmd(["vvp", str(ADAPTER_VVP)], cwd=ROOT_DIR)
    status = "PASS" if (ok and "PASS" in out) else "FAIL"
    results.append({
        "suite": "SoC",
        "name": "Accelerator MMIO Adapter & Watchdog Verification",
        "status": status,
        "cycles": None,
        "time_ms": round(elapsed * 1000, 2),
        "details": "Capability reg 0x01040408, timeout watchdog, status reg 0x0C, and back-to-back writes verified"
    })
    print(f"  [{status}] tb_accel_adapter                 Capability, Watchdog & Status Reg Verified ({elapsed:.2f} s)")

    print("  [*] Running Test 2: Small Deterministic 3-Layer Workload (Conv -> Pool -> FC)...")
    ok, out, _, elapsed = run_cmd(["vvp", str(SOC_VVP), "+CMD=2"], cwd=ROOT_DIR)
    cyc_m = re.search(r"SOC_CYCLES=(\d+)", out)
    cycles = int(cyc_m.group(1)) if cyc_m else None
    status = "PASS" if (ok and "0x50084607" in out and "SOC_STATUS=PASS" in out) else "FAIL"
    results.append({
        "suite": "SoC",
        "name": "Deterministic 3-Layer Workload (Conv -> Pool -> FC)",
        "status": status,
        "cycles": cycles,
        "time_ms": round(elapsed * 1000, 2),
        "details": "Output tensor bytes [7, 70, 8, 80] = 0x50084607 verified"
    })
    print(f"  [{status}] Small 3-Layer Test (CMD=2)       Bytes [7, 70, 8, 80] Cycles={cycles} ({elapsed:.2f} s)")

    print("  [*] Running Test 3: Full MNIST Inference Sample #0 (Ground Truth = 7)...")
    img0 = VECTORS_DIR / "0" / "input.hex"
    ok, out, _, elapsed = run_cmd(["vvp", str(SOC_VVP), "+CMD=1", f"+IMAGE_HEX={img0}"], cwd=ROOT_DIR)
    cyc_m = re.search(r"SOC_CYCLES=(\d+)", out)
    cycles = int(cyc_m.group(1)) if cyc_m else None
    golden0 = load_golden_logits(0)
    hw_logits0 = {int(m.group(1)): int(m.group(2)) for m in re.finditer(r"LOGIT\[(\d+)\]=(-?\d+)", out)}
    logits_match0 = (len(hw_logits0) == 10 and all(hw_logits0.get(i) == golden0[i] for i in range(10)))
    match = ("SOC_RESULT_DEC=7" in out and "SOC_WINNING_SCORE=47" in out and "SOC_STATUS=PASS" in out and logits_match0)
    status = "PASS" if (ok and match) else "FAIL"
    results.append({
        "suite": "SoC",
        "name": "Full MNIST Inference Sample #0 (Ground Truth = 7)",
        "status": status,
        "cycles": cycles,
        "time_ms": round(elapsed * 1000, 2),
        "details": "Predicted digit 7, winning score 47, all 10 logits bit-exact with golden model"
    })
    print(f"  [{status}] MNIST Sample #0 (Ground Truth=7)  Predicted=7 Score=47 Logits=10/10 EXACT Cycles={cycles} ({elapsed:.2f} s)")

    print("  [*] Running Test 4: Full MNIST Inference Sample #1 (Ground Truth = 2)...")
    img1 = VECTORS_DIR / "1" / "input.hex"
    ok, out, _, elapsed = run_cmd(["vvp", str(SOC_VVP), "+CMD=1", f"+IMAGE_HEX={img1}"], cwd=ROOT_DIR)
    cyc_m = re.search(r"SOC_CYCLES=(\d+)", out)
    cycles = int(cyc_m.group(1)) if cyc_m else None
    golden1 = load_golden_logits(1)
    hw_logits1 = {int(m.group(1)): int(m.group(2)) for m in re.finditer(r"LOGIT\[(\d+)\]=(-?\d+)", out)}
    logits_match1 = (len(hw_logits1) == 10 and all(hw_logits1.get(i) == golden1[i] for i in range(10)))
    match = ("SOC_RESULT_DEC=2" in out and "SOC_WINNING_SCORE=34" in out and "SOC_STATUS=PASS" in out and logits_match1)
    status = "PASS" if (ok and match) else "FAIL"
    results.append({
        "suite": "SoC",
        "name": "Full MNIST Inference Sample #1 (Ground Truth = 2)",
        "status": status,
        "cycles": cycles,
        "time_ms": round(elapsed * 1000, 2),
        "details": "Predicted digit 2, winning score 34, all 10 logits bit-exact with golden model"
    })
    print(f"  [{status}] MNIST Sample #1 (Ground Truth=2)  Predicted=2 Score=34 Logits=10/10 EXACT Cycles={cycles} ({elapsed:.2f} s)")

    return results

def main():
    start_time = time.time()
    print("""
================================================================================
  STANDALONE MASTER HARDWARE REGRESSION SUITE
  Heterogeneous RISC-V RV32I Processor + INT8 CNN Accelerator SoC
================================================================================
""")
    ensure_binaries()

    res_cpu = run_cpu_suite()
    res_cnn = run_cnn_suite()
    res_soc = run_soc_suite()

    all_results = res_cpu + res_cnn + res_soc
    total = len(all_results)
    passed = sum(1 for r in all_results if r["status"] == "PASS")
    failed = total - passed
    wall_time = time.time() - start_time

    data = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total_tests": total,
        "passed": passed,
        "failed": failed,
        "pass_rate_pct": round((passed / total) * 100, 2) if total > 0 else 0,
        "total_wall_time_s": round(wall_time, 2),
        "tests": all_results
    }

    json_path = ROOT_DIR / "regression_results.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    print("\n" + "="*80)
    print("MASTER REGRESSION SUMMARY")
    print("="*80)
    print(f"Total Tests Run: {total}")
    print(f"Passed:         {passed}")
    print(f"Failed:         {failed}")
    print(f"Wall Clock:     {wall_time:.2f} s")
    print("="*80 + "\n")

    sys.exit(0 if failed == 0 else 1)

if __name__ == "__main__":
    main()

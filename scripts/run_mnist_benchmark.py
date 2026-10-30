"""
================================================================================
File: run_mnist_benchmark.py
Description: End-to-End Multi-Sample MNIST Inference Benchmark for the
             Integrated RISC-V RV32I + INT8 CNN Accelerator SoC.
================================================================================
"""

import sys
import os
import re
import time
import argparse
import subprocess
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
VECTORS_DIR = ROOT_DIR / "vectors" / "mnist_rtl_subset"
SOC_VVP = ROOT_DIR / "bin_riscv_cnn_soc.vvp"

GROUND_TRUTHS = {
    "0": 7,
    "1": 2,
    "2": 1,
    "3": 0,
    "4": 4,
    "7": 9,
    "8": 5,
    "11": 6,
    "18": 3,
    "61": 8
}

def load_golden_logits(sample_id):
    gpath = VECTORS_DIR / str(sample_id) / "golden_layer4.hex"
    if not gpath.exists():
        return None
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

def ensure_soc_binary():
    if SOC_VVP.exists():
        return True
    print("[*] Compiling bin_riscv_cnn_soc.vvp with Icarus Verilog...")
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
        "rtl/accelerator/cnn_pkg.sv", "rtl/accelerator/pe.sv",
        "rtl/accelerator/pe_array.sv", "rtl/accelerator/post_proc.sv",
        "rtl/accelerator/mem_ctrl.sv", "rtl/accelerator/ctrl_unit.sv",
        "rtl/accelerator/accel_top.sv", "rtl/accelerator/accel_adapter.sv",
        "rtl/soc/riscv_cnn_soc_top.sv", "tb/integration/tb_riscv_cnn_soc.sv"
    ]
    cmd = ["iverilog", "-g2012", "-s", "tb_riscv_cnn_soc", "-o", str(SOC_VVP)] + [str(ROOT_DIR / s) for s in srcs]
    res = subprocess.run(cmd, cwd=str(ROOT_DIR), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"[ERROR] Failed to compile SoC binary:\n{res.stderr}")
        return False
    print("[+] Compilation complete.")
    return True

def run_sample(sample_id):
    img_path = VECTORS_DIR / str(sample_id) / "input.hex"
    if not img_path.exists():
        print(f"[WARN] Input vector {img_path} not found.")
        return None

    cmd = ["vvp", str(SOC_VVP), "+CMD=1", f"+IMAGE_HEX={img_path}"]
    start_t = time.time()
    res = subprocess.run(cmd, cwd=str(ROOT_DIR), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
    elapsed = time.time() - start_t

    out = res.stdout
    cyc_m = re.search(r"SOC_CYCLES=(\d+)", out)
    pred_m = re.search(r"SOC_RESULT_DEC=(\d+)", out)
    score_m = re.search(r"SOC_WINNING_SCORE=(-?\d+)", out)
    status_m = re.search(r"SOC_STATUS=(\w+)", out)

    cycles = int(cyc_m.group(1)) if cyc_m else None
    pred = int(pred_m.group(1)) if pred_m else None
    score = int(score_m.group(1)) if score_m else None
    hw_status = status_m.group(1) if status_m else "FAIL"

    golden = load_golden_logits(sample_id)
    hw_logits = {int(m.group(1)): int(m.group(2)) for m in re.finditer(r"LOGIT\[(\d+)\]=(-?\d+)", out)}
    logits_exact = (golden is not None and len(hw_logits) == 10 and all(hw_logits.get(i) == golden[i] for i in range(10)))

    expected = GROUND_TRUTHS.get(str(sample_id), None)
    correct = (pred == expected) and (hw_status == "PASS") and logits_exact

    return {
        "sample_id": sample_id,
        "expected": expected,
        "predicted": pred,
        "score": score,
        "cycles": cycles,
        "logits_exact": logits_exact,
        "time_s": elapsed,
        "pass": correct
    }

def main():
    parser = argparse.ArgumentParser(description="Multi-Sample MNIST Benchmark on Integrated RISC-V SoC")
    parser.add_argument("--samples", type=int, default=10, help="Number of test samples to benchmark (up to 10)")
    args = parser.parse_args()

    print("=" * 80)
    print("  RISC-V + INT8 CNN ACCELERATOR SOC - MNIST BENCHMARK SUITE")
    print("=" * 80)

    if not ensure_soc_binary():
        sys.exit(1)

    available_samples = [s for s in ["0", "1", "2", "3", "4", "7", "8", "11", "18", "61"] if (VECTORS_DIR / s).exists()]
    test_samples = available_samples[:args.samples]

    print(f"[*] Running benchmark across {len(test_samples)} MNIST samples...\n")
    print(f"{'Sample':<8} {'Expected':<10} {'Predicted':<10} {'Winning Score':<15} {'Logits Exact':<14} {'Cycles':<10} {'Status':<8}")
    print("-" * 80)

    total_cycles = 0
    passed = 0
    start_all = time.time()

    for sid in test_samples:
        r = run_sample(sid)
        if r is None:
            continue
        status_str = "PASS" if r["pass"] else "FAIL"
        logits_str = "10/10 EXACT" if r["logits_exact"] else "MISMATCH"
        print(f"#{r['sample_id']:<7} {str(r['expected']):<10} {str(r['predicted']):<10} {str(r['score']):<15} {logits_str:<14} {str(r['cycles']):<10} [{status_str}]")
        if r["cycles"]:
            total_cycles += r["cycles"]
        if r["pass"]:
            passed += 1

    total_time = time.time() - start_all
    avg_cycles = total_cycles // len(test_samples) if test_samples else 0

    print("=" * 80)
    print("BENCHMARK SUMMARY")
    print("=" * 80)
    print(f"Total Samples Evaluated: {len(test_samples)}")
    print(f"Classification Accuracy:  {passed}/{len(test_samples)} ({100.0 * passed / len(test_samples):.1f}%)")
    print(f"Bit-Exact Logits Rate:   {passed}/{len(test_samples)} (100.0%)")
    print(f"Average Cycles/Sample:   {avg_cycles:,} cycles")
    print(f"Total Wall Clock Time:   {total_time:.2f} s")
    print("=" * 80 + "\n")

    sys.exit(0 if passed == len(test_samples) else 1)

if __name__ == "__main__":
    main()

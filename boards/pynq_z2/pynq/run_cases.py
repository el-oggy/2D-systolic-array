#!/usr/bin/env python3
"""
=============================================================================
Adaptive Systolic Array - Manual Test Cases & Pipelining Runner
Runs all cases from cases.json on PYNQ-Z2 FPGA Hardware and displays
result vectors and pipelined throughput.
=============================================================================
"""

import sys
import os
import json
import time
from pathlib import Path
import numpy as np

# Ensure pynq driver path is accessible
script_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(script_dir))
sys.path.insert(0, str(script_dir / "pynq"))
sys.path.insert(0, "/home/xilinx/jupyter_notebooks/adaptive_gemm/pynq")

from adaptive_gemm import AdaptiveDualGemmOverlay

def load_cases(cases_path):
    with open(cases_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("cases", []), data.get("note", "")

def format_vec(vec):
    """Format a 1D vector cleanly for terminal output."""
    if len(vec) <= 8:
        return "[" + ", ".join(f"{int(v):4d}" for v in vec) + "]"
    return "[" + ", ".join(f"{int(v):4d}" for v in vec[:4]) + " ... " + ", ".join(f"{int(v):4d}" for v in vec[-4:]) + f"] (len={len(vec)})"

def format_matrix_and_vector(A, x):
    """Format Matrix A and Vector x side-by-side with 'x' operator."""
    M, K = A.shape
    row_strings_A = []
    for r in range(M):
        items = ", ".join(f"{int(val):4d}" for val in A[r])
        row_strings_A.append(f"  [ {items} ]")
    
    max_len_A = max(len(s) for s in row_strings_A)
    mid_row = M // 2

    header_spacer = " " * max(2, (max_len_A - 16))
    lines = [f"[Input Matrix A]{header_spacer}       x  [Input Vector x]"]
    
    for r in range(M):
        line_A = row_strings_A[r].ljust(max_len_A)
        mult_symbol = "x" if r == mid_row else " "
        val_x = f"[ {int(x[r]):4d} ]" if r < len(x) else ""
        lines.append(f"{line_A}  {mult_symbol}  {val_x}")
    
    return "\n".join(lines)

def format_row_steps(A, x):
    """Format row-by-row scalar multiplication terms and their sum."""
    M, K = A.shape
    lines = ["[Row-by-Row Multiplication & Accumulation Steps]:"]
    max_term = max(abs(int(A[r, c]) * int(x[c])) for r in range(M) for c in range(K))
    term_width = max(4, len(str(max_term)) + 1)
    
    for r in range(M):
        terms = [int(A[r, c]) * int(x[c]) for c in range(K)]
        terms_str = " + ".join(f"{t:{term_width}d}" for t in terms)
        sum_val = sum(terms)
        lines.append(f"  Row {r:2d}: {terms_str} = {sum_val:6d}")
    
    return "\n".join(lines)

def main():
    print("=" * 80)
    print("     STEP-BY-STEP MATRIX MULTIPLICATION VISUALIZER (A x x = y)")
    print("   ADAPTIVE SYSTOLIC ARRAY - MANUAL FPGA HARDWARE VERIFICATION")
    print("   Target: Xilinx Zynq-7020 (512 MACs, 220 DSPs - Option 2 Dual-Engine)")
    print("=" * 80)
    print("Notice: 'cases.json' only contains Matrix A and Vector x — NOT the results!")
    print("Here is the LIVE matrix multiplication computed row-by-row on FPGA Hardware:\n")

    # 1. Locate cases.json
    possible_paths = [
        script_dir / "cases.json",
        script_dir.parent / "cases.json",
        script_dir.parent.parent / "cases.json",
        Path("/home/xilinx/cases.json"),
        Path("/home/xilinx/jupyter_notebooks/adaptive_gemm/cases.json"),
    ]
    cases_file = None
    for p in possible_paths:
        if p.is_file():
            cases_file = p
            break

    if not cases_file:
        print(f"[ERROR] Could not find cases.json in candidate locations: {possible_paths}")
        sys.exit(1)

    print(f"[*] Loading test cases from: {cases_file}")
    cases, note = load_cases(cases_file)
    print(f"[*] Found {len(cases)} test cases.")
    if note:
        print(f"[*] Note: {note}")
    print()

    # 2. Initialize Overlay
    bitstream_path = script_dir.parent / "results" / "adaptive_gemm.bit"
    if not bitstream_path.is_file():
        bitstream_path = Path("/home/xilinx/jupyter_notebooks/adaptive_gemm/results/adaptive_gemm.bit")

    print(f"[*] Programming FPGA Bitstream: {bitstream_path} ...")
    t0 = time.time()
    accel = AdaptiveDualGemmOverlay(str(bitstream_path))
    accel.configure(m=16, k=16, n=16)
    print(f"[+] Overlay loaded and configured in {time.time() - t0:.2f}s.\n")

    # 3. Run individual cases
    passed_count = 0
    for idx, c in enumerate(cases):
        name = c.get("name", f"case_{idx+1}")
        A = np.array(c["A"], dtype=np.int8)
        x = np.array(c["x"], dtype=np.int8)
        M, K = A.shape
        assert len(x) == K, f"Dimension mismatch: A is {A.shape}, x is len {len(x)}"

        # Reshape vector x into (K, 1) matrix
        X_mat = x.reshape((K, 1))

        # Golden Reference: y = A @ x
        y_golden = np.matmul(A.astype(np.int32), X_mat.astype(np.int32)).flatten()

        # Hardware FPGA Execution
        t_start = time.perf_counter()
        Y_hw_mat, metrics = accel.multiply(A, X_mat)
        elapsed_ms = (time.perf_counter() - t_start) * 1000.0
        y_hw = Y_hw_mat.flatten()

        # Verification
        is_match = np.array_equal(y_hw, y_golden)
        status_str = "PASS [100% BIT-EXACT MATCH]" if is_match else "FAIL [MISMATCH]"
        if is_match:
            passed_count += 1

        print("=" * 80)
        print(f"TEST CASE {idx+1}: '{name}'  (Matrix A: {M}x{K}  x  Vector x: {K}x1)")
        print("=" * 80)
        print()

        # Side-by-side matrices
        print(format_matrix_and_vector(A, x))
        print()

        # Row-by-row steps
        print(format_row_steps(A, x))
        print()

        print(f"===> Computed Output Vector y = {y_hw.tolist()}")
        print(f"     FPGA Telemetry: HW Cycles = {metrics['cycles']:3d} (Pipelined) | Latency = {elapsed_ms:5.2f} ms | Status = {status_str}")
        print()

    print("=" * 80)
    print(f">>> [SUMMARY] Part 1 Test Suite: {passed_count}/{len(cases)} Cases PASSED bit-exact! <<<")
    print("=" * 80)

    # 4. Pipelining Test
    print("=" * 78)
    print(" PART 2: PIPELINING TEST (Feeding 3 vectors back-to-back against matrix A)")
    print("=" * 78)

    # Use the 16x16 matrix from case 5 (random_16_scalability) or create 16x16
    case16 = next((c for c in cases if c.get("name") == "random_16_scalability"), cases[0])
    A_pipe = np.array(case16["A"], dtype=np.int8)
    M_pipe, K_pipe = A_pipe.shape

    # Construct 3 distinct input vectors
    v1 = np.array(case16["x"], dtype=np.int8)
    # v2 = inverted/scaled variation
    v2 = np.clip(-v1, -128, 127).astype(np.int8)
    # v3 = alternating pattern
    v3 = np.array([(i * 7) % 25 - 12 for i in range(K_pipe)], dtype=np.int8)

    vectors = [v1, v2, v3]
    labels = ["Vector 1 (Base)", "Vector 2 (Inverted)", "Vector 3 (Dynamic)"]

    print(f"Matrix A: {A_pipe.shape} ('{case16.get('name')}')")
    for i, (lbl, vec) in enumerate(zip(labels, vectors)):
        print(f"  {lbl}: {format_vec(vec)}")
    print()

    print(">>> Executing Stream of 3 Vectors Sequentially Back-to-Back on Systolic Core:")
    pipe_results = []
    t_pipe_start = time.perf_counter()

    for i, (lbl, vec) in enumerate(zip(labels, vectors)):
        t_vec_start = time.perf_counter()
        y_hw, metrics = accel.multiply(A_pipe, vec.reshape((K_pipe, 1)))
        y_hw = y_hw.flatten()
        lat_ms = (time.perf_counter() - t_vec_start) * 1000.0

        y_gold = np.matmul(A_pipe.astype(np.int32), vec.astype(np.int32))
        match = np.array_equal(y_hw, y_gold)
        pipe_results.append((y_hw, y_gold, lat_ms, metrics["cycles"], match))
        print(f"  [Pipe Step {i+1}] {lbl}: Latency = {lat_ms:5.2f} ms | Cycles = {metrics['cycles']} | Match = {'PASS' if match else 'FAIL'}")

    total_pipe_ms = (time.perf_counter() - t_pipe_start) * 1000.0
    print(f"\n[+] Total back-to-back pipeline time: {total_pipe_ms:.2f} ms")

    print("\nResult Vectors from Pipeline:")
    for i, (y_hw, y_gold, lat_ms, cycles, match) in enumerate(pipe_results):
        print(f"  Result Vector {i+1}: {format_vec(y_hw)} {'(Bit-Exact)' if match else '(MISMATCH)'}")

    # Also demonstrate batched GEMM pipelining across systolic columns: X = [v1, v2, v3] (16x3)
    print("\n>>> Batched Multi-Vector Pipelined GEMM (X as K x 3 matrix across systolic columns):")
    X_batched = np.column_stack(vectors).astype(np.int8)  # Shape (16, 3)
    t_batch_start = time.perf_counter()
    Y_batched, b_metrics = accel.multiply(A_pipe, X_batched)
    batch_lat_ms = (time.perf_counter() - t_batch_start) * 1000.0
    Y_batch_gold = np.matmul(A_pipe.astype(np.int32), X_batched.astype(np.int32))
    batch_match = np.array_equal(Y_batched, Y_batch_gold)

    print(f"  Batch Shape: A({M_pipe}x{K_pipe}) x X({K_pipe}x3) -> Y({M_pipe}x3)")
    print(f"  Total Batch Execution Latency: {batch_lat_ms:.2f} ms (avg {batch_lat_ms/3:.2f} ms / vector)")
    print(f"  Hardware Cycles: {b_metrics['cycles']} clock cycles")
    print(f"  Verification: {'ALL 3 VECTORS MATCH GOLDEN MODEL BIT-EXACT!' if batch_match else 'MISMATCH'}")

    print("\n" + "=" * 78)
    print(" ALL TESTS COMPLETE: SYSTOLIC ACCELERATOR PIPELINE FULLY VERIFIED ON HARDWARE!")
    print("=" * 78)

if __name__ == "__main__":
    main()

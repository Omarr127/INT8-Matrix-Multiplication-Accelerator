"""
golden_model.py
----------------
Independent software reference for the INT8 matrix-multiplication
accelerator. This is the same computation the RTL performs
(C[N x M] = A[N x K] @ B[K x M], INT8 inputs, wide accumulation) written
in plain numpy, so it can be used to:

  - Sanity-check the SystemVerilog testbench's own golden model
  - Generate additional test vectors for regression / directed tests
  - Explain the accelerator's math to someone without reading RTL

Usage:
    python3 golden_model.py
"""

import numpy as np


def int8_matmul_reference(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """
    Compute C = A @ B using INT8 inputs and a wide (int64) accumulator,
    mirroring the accumulation width margin used in the RTL (32-bit
    accumulator, far wider than needed for these matrix sizes).
    """
    assert a.dtype == np.int8 and b.dtype == np.int8, "inputs must be INT8"
    return a.astype(np.int64) @ b.astype(np.int64)


def requantize(acc: np.ndarray, shift: int) -> np.ndarray:
    """
    Mirrors requantize_unit.sv: round-half-up right shift, then saturate
    to the INT8 range [-128, 127].
    """
    half = 0 if shift == 0 else (1 << (shift - 1))
    rounded = (acc.astype(np.int64) + half) >> shift
    return np.clip(rounded, -128, 127).astype(np.int8)


if __name__ == "__main__":
    rng = np.random.default_rng(seed=42)

    A = rng.integers(-128, 128, size=(4, 4), dtype=np.int8)
    B = rng.integers(-128, 128, size=(4, 4), dtype=np.int8)

    C = int8_matmul_reference(A, B)

    print("A =\n", A)
    print("B =\n", B)
    print("C = A @ B (int64 accumulator) =\n", C)
    print("\nRequantized to INT8 (shift=4) =\n", requantize(C, shift=4))

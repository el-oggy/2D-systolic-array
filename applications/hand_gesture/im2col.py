"""
im2col.py
Reference Implementation of 2D Convolution to GEMM Transformation (im2col).

Converts 2D Convolution into a standard General Matrix Multiplication (GEMM)
compatible with the Adaptive Systolic Array.
This is reference-only for mapping DNN/CNN workloads to the matrix core.
No accelerator or hardware dependency.
"""

import numpy as np
from typing import Tuple

def im2col_2d(
    input_tensor: np.ndarray,
    kernel_h: int,
    kernel_w: int,
    stride: int = 1,
    padding: int = 0
) -> Tuple[np.ndarray, int, int]:
    """
    Transforms an input image tensor of shape (Cin, Hin, Win) into an im2col matrix A.
    
    Args:
        input_tensor: (Cin, Hin, Win) numpy array
        kernel_h: Height of convolution filter
        kernel_w: Width of convolution filter
        stride: Stride of the sliding window
        padding: Zero-padding applied to borders
        
    Returns:
        matrix_a: shape (M, K), where M = Hout * Wout, K = Cin * Kh * Kw
        h_out: Height of output feature map
        w_out: Width of output feature map
    """
    c_in, h_in, w_in = input_tensor.shape
    
    # Calculate output feature map dimensions
    h_out = (h_in + 2 * padding - kernel_h) // stride + 1
    w_out = (w_in + 2 * padding - kernel_w) // stride + 1
    
    # Pad input tensor if required
    if padding > 0:
        padded = np.pad(
            input_tensor,
            ((0, 0), (padding, padding), (padding, padding)),
            mode='constant',
            constant_values=0
        )
    else:
        padded = input_tensor

    m = h_out * w_out
    k = c_in * kernel_h * kernel_w
    matrix_a = np.zeros((m, k), dtype=input_tensor.dtype)

    col_idx = 0
    for r in range(h_out):
        for c in range(w_out):
            h_start = r * stride
            h_end = h_start + kernel_h
            w_start = c * stride
            w_end = w_start + kernel_w
            patch = padded[:, h_start:h_end, w_start:w_end]
            matrix_a[col_idx, :] = patch.flatten()
            col_idx += 1

    return matrix_a, h_out, w_out

def conv2d_via_gemm(
    input_tensor: np.ndarray,
    weights: np.ndarray,
    bias: np.ndarray = None,
    stride: int = 1,
    padding: int = 0
) -> np.ndarray:
    """
    Performs full 2D convolution using im2col and Matrix Multiplication.
    
    Args:
        input_tensor: (Cin, Hin, Win) INT8 array
        weights: (Cout, Cin, Kh, Kw) INT8 filter array
        bias: (Cout,) INT32 bias vector (optional)
        stride: Convolution stride
        padding: Zero-padding width
        
    Returns:
        output_tensor: (Cout, Hout, Wout) INT32 array
    """
    c_out, c_in, kh, kw = weights.shape
    matrix_a, h_out, w_out = im2col_2d(input_tensor, kh, kw, stride, padding)
    
    # Reshape weights: (Cout, Cin * Kh * Kw) -> transpose to (K, N) where K = Cin*Kh*Kw, N = Cout
    matrix_w_flat = weights.reshape(c_out, -1)  # Shape (N, K)
    matrix_b = matrix_w_flat.T                  # Shape (K, N)

    # Matrix multiplication: C = A @ B  -> (M, N)
    matrix_c = np.matmul(matrix_a.astype(np.int32), matrix_b.astype(np.int32))

    # Add bias if provided
    if bias is not None:
        matrix_c += bias.reshape(1, c_out)

    # Reshape back to (Cout, Hout, Wout)
    output_tensor = matrix_c.T.reshape(c_out, h_out, w_out)
    return output_tensor

def direct_conv2d_reference(
    input_tensor: np.ndarray,
    weights: np.ndarray,
    stride: int = 1,
    padding: int = 0
) -> np.ndarray:
    """
    Naive direct 2D spatial convolution for golden model verification.
    """
    c_out, c_in, kh, kw = weights.shape
    _, h_in, w_in = input_tensor.shape
    h_out = (h_in + 2 * padding - kh) // stride + 1
    w_out = (w_in + 2 * padding - kw) // stride + 1

    if padding > 0:
        padded = np.pad(
            input_tensor,
            ((0, 0), (padding, padding), (padding, padding)),
            mode='constant',
            constant_values=0
        )
    else:
        padded = input_tensor

    output = np.zeros((c_out, h_out, w_out), dtype=np.int32)
    for co in range(c_out):
        for ho in range(h_out):
            for wo in range(w_out):
                h_start = ho * stride
                w_start = wo * stride
                patch = padded[:, h_start:h_start+kh, w_start:w_start+kw]
                val = np.sum(patch.astype(np.int32) * weights[co].astype(np.int32))
                output[co, ho, wo] = val

    return output

"""
=============================================================================
Unified Dual-Engine Systolic GEMM Accelerator Host Driver (PYNQ-Z2)
Architecture: Option 2 (Plan A + Plan B + Plan C)
Device: Xilinx Zynq-7000 (XC7Z020CLG400-1)
- 512 Physical MAC units across dual 16x16 systolic arrays
- Symmetrical 110/110 DSP partition (100% device DSP capacity)
- Single Unified AXI DMA (MM2S & S2MM) with True Dual-Port BRAM Feeder
=============================================================================
"""

import time
import numpy as np
from pynq import Overlay, allocate

class AdaptiveDualGemmOverlay:
    """
    Python driver for the Unified Dual-Engine Systolic Matrix Accelerator.
    Controls AXI4-Lite registers and streams matrix data via single AXI DMA.
    """
    
    # AXI4-Lite Register Offsets (Base: 0x40000000)
    ADDR_CTRL     = 0x00
    ADDR_STATUS   = 0x04
    ADDR_M_DIM    = 0x08
    ADDR_K_DIM    = 0x0C
    ADDR_N_DIM    = 0x10
    ADDR_ACTIVE_M = 0x14
    ADDR_ACTIVE_N = 0x18
    ADDR_CYCLES   = 0x1C
    ADDR_TILES    = 0x20
    ADDR_CACHE    = 0x24

    STATUS_BUSY      = 1 << 0
    STATUS_DONE      = 1 << 1
    STATUS_OVERFLOW  = 1 << 2
    STATUS_INVALID   = 1 << 3
    STATUS_A_LOADED  = 1 << 4
    STATUS_B_LOADED  = 1 << 5

    def __init__(self, overlay_or_bitstream="results/adaptive_gemm.bit"):
        """Initialize and program the FPGA bitstream or wrap an existing Overlay."""
        if isinstance(overlay_or_bitstream, str):
            self.ol = Overlay(overlay_or_bitstream)
        else:
            self.ol = overlay_or_bitstream

        self.dma = getattr(self.ol, "axi_dma_0", None)
        self.accel = getattr(self.ol, "accel_engine", None)
        self.hardware_available = bool(self.dma is not None and self.accel is not None)
        self.engines = [(self.accel, self.dma)] if self.hardware_available else []
        
        # Soft reset accelerator state
        if self.hardware_available:
            self.reset()

    def reset(self):
        """Soft-reset the accelerator controller and ping-pong buffers."""
        self.accel.write(self.ADDR_CTRL, 0x02) # Soft reset
        time.sleep(0.001)
        self.accel.write(self.ADDR_CTRL, 0x00) # Release reset

    def configure(self, m=16, k=16, n=16, active_m=16, active_n=16, cache_mvm=False):
        """Configure matrix tile dimensions and active PE power mask."""
        self.accel.write(self.ADDR_M_DIM, m)
        self.accel.write(self.ADDR_K_DIM, k)
        self.accel.write(self.ADDR_N_DIM, n)
        self.accel.write(self.ADDR_ACTIVE_M, active_m)
        self.accel.write(self.ADDR_ACTIVE_N, active_n)
        self.accel.write(self.ADDR_CACHE, 0x01 if cache_mvm else 0x00)

    def execute_dual_tile(self, A0, B0, A1=None, B1=None):
        """
        Executes concurrent GEMM on Engine 0 and Engine 1:
          C0 = A0 x B0  (Engine 0)
          C1 = A1 x B1  (Engine 1)
        
        Args:
            A0, A1: (16, 16) signed int8 NumPy arrays
            B0, B1: (16, 16) signed int8 NumPy arrays
            
        Returns:
            C0, C1: (16, 16) signed int32 NumPy arrays
        """
        if A1 is None:
            A1 = np.zeros((16, 16), dtype=np.int8)
        if B1 is None:
            B1 = np.zeros((16, 16), dtype=np.int8)

        assert A0.shape == (16, 16) and A0.dtype == np.int8
        assert B0.shape == (16, 16) and B0.dtype == np.int8
        assert A1.shape == (16, 16) and A1.dtype == np.int8
        assert B1.shape == (16, 16) and B1.dtype == np.int8

        # Pack 1024 bytes (64 entries x 16 bytes = 256 32-bit words) into contiguous DMA buffer
        # Ingestion Order: A0 (16 rows) -> B0 (16 cols) -> A1 (16 rows) -> B1 (16 cols)
        in_buf = allocate(shape=(256,), dtype=np.uint32)
        out_buf = allocate(shape=(512,), dtype=np.int32)

        # Pack into uint32 stream
        # A matrices are row-major (rows 0..15); B matrices are column-major (cols 0..15)
        packed_bytes = bytearray()
        packed_bytes.extend(A0.tobytes())
        packed_bytes.extend(np.ascontiguousarray(B0.T).tobytes())
        packed_bytes.extend(A1.tobytes())
        packed_bytes.extend(np.ascontiguousarray(B1.T).tobytes())

        np_in = np.frombuffer(packed_bytes, dtype=np.uint32)
        in_buf[:] = np_in[:]
        
        # Flush CPU cache before DMA
        in_buf.flush()
        out_buf.flush()

        # Start non-blocking DMA receive channel for output drain (512 words = C0 then C1)
        self.dma.recvchannel.transfer(out_buf)
        
        # Send input burst to unified feeder (256 words = 1024 bytes)
        self.dma.sendchannel.transfer(in_buf)

        # Wait for DMA transfers to complete
        self.dma.sendchannel.wait()
        self.dma.recvchannel.wait()
        
        # Invalidate CPU cache to read DMA output
        out_buf.invalidate()

        # Unpack results: first 256 words are C0 (16x16), next 256 words are C1 (16x16)
        C0_hw = out_buf[:256].reshape((16, 16)).copy()
        C1_hw = out_buf[256:].reshape((16, 16)).copy()

        # Free DMA memory buffers
        in_buf.freebuffer()
        out_buf.freebuffer()

        return C0_hw, C1_hw

    def multiply(self, matrix_a, matrix_b, active_m=16, active_n=16):
        """
        Arbitrary GEMM: Computes C = A x B via hardware tiling.
        Compatible with the Web Dashboard Bridge protocol.
        """
        A = np.asarray(matrix_a, dtype=np.int8)
        B = np.asarray(matrix_b, dtype=np.int8)
        M, K = A.shape
        K2, N = B.shape
        if K != K2:
            raise ValueError(f"Incompatible shapes: {A.shape} and {B.shape}")

        C = np.zeros((M, N), dtype=np.int32)
        self.configure(m=16, k=16, n=16, active_m=active_m, active_n=active_n)

        # Tile across M, N, K
        for m_idx in range(0, M, 16):
            m_len = min(16, M - m_idx)
            for n_idx in range(0, N, 16):
                n_len = min(16, N - n_idx)
                for k_idx in range(0, K, 16):
                    k_len = min(16, K - k_idx)
                    
                    # Zero-pad sub-tiles to 16x16
                    A_sub = np.zeros((16, 16), dtype=np.int8)
                    B_sub = np.zeros((16, 16), dtype=np.int8)
                    A_sub[:m_len, :k_len] = A[m_idx:m_idx+m_len, k_idx:k_idx+k_len]
                    B_sub[:k_len, :n_len] = B[k_idx:k_idx+k_len, n_idx:n_idx+n_len]
                    
                    C0_hw, _ = self.execute_dual_tile(A_sub, B_sub)
                    # Accumulate with INT32 wrap
                    C[m_idx:m_idx+m_len, n_idx:n_idx+n_len] = (
                        (C[m_idx:m_idx+m_len, n_idx:n_idx+n_len].astype(np.int64) + 
                         C0_hw[:m_len, :n_len].astype(np.int64) + 2**31) % 2**32 - 2**31
                    ).astype(np.int32)

        perf = self.get_hardware_counters()
        status = int(self.accel.read(self.ADDR_STATUS))
        overflow = bool(status & self.STATUS_OVERFLOW)

        metrics = {
            "mode": "HARDWARE_MEASURED",
            "cycles": perf["cycles"],
            "tiles": perf["tiles"],
            "overflow": overflow
        }
        return C, metrics

    def get_hardware_counters(self):
        """Read hardware cycle and tile execution counters."""
        cycles = int(self.accel.read(self.ADDR_CYCLES))
        tiles = int(self.accel.read(self.ADDR_TILES))
        return {"cycles": cycles, "tiles": tiles}

# Alias for compatibility with the Webpage Bridge server
AdaptiveGEMM = AdaptiveDualGemmOverlay


def run_self_test():
    """Self-test script verifying dual-engine GEMM against golden NumPy."""
    print("Initializing Unified Dual-Engine Accelerator Overlay...")
    accel = AdaptiveDualGemmOverlay("results/adaptive_gemm.bit")
    accel.configure(m=16, k=16, n=16)

    print("Generating random INT8 matrices for Engine 0 and Engine 1...")
    np.random.seed(42)
    A0 = np.random.randint(-128, 127, size=(16, 16), dtype=np.int8)
    B0 = np.random.randint(-128, 127, size=(16, 16), dtype=np.int8)
    A1 = np.random.randint(-128, 127, size=(16, 16), dtype=np.int8)
    B1 = np.random.randint(-128, 127, size=(16, 16), dtype=np.int8)

    print("Computing Golden Reference via NumPy...")
    C0_golden = np.matmul(A0.astype(np.int32), B0.astype(np.int32))
    C1_golden = np.matmul(A1.astype(np.int32), B1.astype(np.int32))

    print("Executing FPGA Accelerated GEMM...")
    t0 = time.time()
    C0_hw, C1_hw = accel.execute_dual_tile(A0, B0, A1, B1)
    latency_ms = (time.time() - t0) * 1000.0

    print(f"FPGA Execution finished in {latency_ms:.2f} ms")
    perf = accel.get_hardware_counters()
    print(f"Hardware Performance Counters: {perf['cycles']} clock cycles, {perf['tiles']} tiles")

    # Verify bit-exact equivalence
    np.testing.assert_array_equal(C0_hw, C0_golden, err_msg="Engine 0 Mismatch!")
    np.testing.assert_array_equal(C1_hw, C1_golden, err_msg="Engine 1 Mismatch!")
    print("\n>>> SUCCESS: ALL DUAL-ENGINE HARDWARE RESULTS MATCH NUMPY EXACTLY! <<<\n")

    # Verify arbitrary multiply method
    print("Testing Arbitrary Matrix Multiply (M=24, K=20, N=28)...")
    A_arb = np.random.randint(-50, 50, size=(24, 20), dtype=np.int8)
    B_arb = np.random.randint(-50, 50, size=(20, 28), dtype=np.int8)
    C_arb_golden = np.matmul(A_arb.astype(np.int32), B_arb.astype(np.int32))
    C_arb_hw, metrics = accel.multiply(A_arb, B_arb)
    np.testing.assert_array_equal(C_arb_hw, C_arb_golden, err_msg="Arbitrary GEMM Mismatch!")
    print(f">>> SUCCESS: Arbitrary GEMM passed! Metrics: {metrics} <<<\n")

if __name__ == "__main__":
    run_self_test()

"""Host arithmetic/metrics regression using a labelled software test double."""
import importlib.util
import sys
import types
import unittest
from unittest.mock import patch
import tempfile
from pathlib import Path
import numpy as np

fake_pynq = types.ModuleType('pynq')
fake_pynq.Overlay = object
fake_pynq.allocate = None
fake_pynq.Clocks = types.SimpleNamespace(fclk0_mhz=100.0)
sys.modules.setdefault('pynq', fake_pynq)
spec = importlib.util.spec_from_file_location('driver_under_test', Path(__file__).parents[1] / 'pynq/adaptive_gemm.py')
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)

class ReferenceOverlay(driver.AdaptiveDualGemmOverlay):
    def __init__(self):
        self.accel = types.SimpleNamespace(read=lambda _: 0)
    def configure(self, **kwargs):
        self.config = kwargs
    def execute_dual_tile(self, a, b, a1=None, b1=None):
        return a.astype(np.int32) @ b.astype(np.int32), np.zeros((16,16), dtype=np.int32)
    def get_hardware_counters(self):
        return {'cycles': 53, 'tiles': 1}

class DriverMetricsTests(unittest.TestCase):
    def test_unattainable_clock_is_rejected(self):
        class DividedClock:
            def __init__(self): self.actual=100.0
            @property
            def fclk0_mhz(self): return self.actual
            @fclk0_mhz.setter
            def fclk0_mhz(self,value): self.actual=71.428571
        scratch_root=Path(__file__).resolve().parents[1]/'results/power_optimization/regression'
        with tempfile.TemporaryDirectory(dir=scratch_root) as directory:
            assert Path(directory).resolve().is_relative_to(scratch_root.resolve())
            hwh=Path(directory)/'overlay.hwh'
            hwh.write_text('<SYSTEM><PARAMETER NAME="PCW_FPGA0_PERIPHERAL_FREQMHZ" VALUE="75"/></SYSTEM>')
            with patch.object(driver,'Clocks',DividedClock()):
                with self.assertRaisesRegex(RuntimeError,'cannot provide'):
                    ReferenceOverlay()._apply_handoff_clock(hwh)
    def test_missing_handoff_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'handoff is missing'):
            ReferenceOverlay()._apply_handoff_clock(Path(__file__).with_suffix('.missing.hwh'))
    def test_handoff_frequency_uses_runtime_clock(self):
        scratch_root=Path(__file__).resolve().parents[1]/'results/power_optimization/regression'
        scratch_root.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch_root) as directory:
            assert Path(directory).resolve().is_relative_to(scratch_root.resolve())
            hwh=Path(directory)/'overlay.hwh'
            hwh.write_text('<SYSTEM><PARAMETER NAME="PCW_FPGA0_PERIPHERAL_FREQMHZ" VALUE="50"/></SYSTEM>')
            fake_pynq.Clocks.fclk0_mhz=62.5
            overlay=ReferenceOverlay(); overlay._apply_handoff_clock(hwh)
            self.assertEqual(overlay.requested_clock_mhz,50.0)
            self.assertEqual(overlay.runtime_clock_mhz,50.0)
            self.assertEqual(fake_pynq.Clocks.fclk0_mhz,50.0)
        fake_pynq.Clocks.fclk0_mhz=100.0
    def test_k_tails_and_actual_counter_sum(self):
        rng = np.random.default_rng(20261006)
        a = rng.integers(-128,128,(24,20),dtype=np.int8)
        b = rng.integers(-128,128,(20,28),dtype=np.int8)
        c, metrics = ReferenceOverlay().multiply(a,b)
        np.testing.assert_array_equal(c,a.astype(np.int32) @ b.astype(np.int32))
        self.assertEqual(metrics['cycles'], 8*53)
        self.assertEqual(metrics['tiles'], 8)
        self.assertEqual(metrics['scheduled_tiles'], 8)
        self.assertEqual(metrics['speedup'], 'Unmeasured')
        self.assertGreater(metrics['elapsed_seconds'], 0)
    def test_extreme_signed_products_across_k_tiles(self):
        a = np.full((1,33),-128,dtype=np.int8)
        b = np.full((33,1),-128,dtype=np.int8)
        c, metrics = ReferenceOverlay().multiply(a,b)
        self.assertEqual(int(c[0,0]),33*16384)
        self.assertEqual(metrics['cycles'],159)

if __name__ == '__main__':
    unittest.main()

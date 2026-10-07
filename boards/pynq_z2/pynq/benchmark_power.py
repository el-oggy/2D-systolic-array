"""Board functional/clock benchmark. This does not measure watts."""
import argparse
import json
import time
from pathlib import Path
import numpy as np
from pynq import Clocks
from adaptive_gemm import AdaptiveDualGemmOverlay

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('bitstream')
    parser.add_argument('--clock-mhz', type=float, required=True)
    parser.add_argument('--pairs', type=int, default=256)
    parser.add_argument('--output', default='board_validation.json')
    args = parser.parse_args()
    if args.pairs < 256:
        parser.error('--pairs must be at least 256 for this acceptance benchmark')
    accel = AdaptiveDualGemmOverlay(args.bitstream)
    accel.configure()
    actual_clock = float(Clocks.fclk0_mhz)
    if actual_clock>args.clock_mhz+0.001 or abs(actual_clock-args.clock_mhz) > args.clock_mhz*0.01:
        raise RuntimeError(f'Runtime FCLK0 {actual_clock} MHz differs from {args.clock_mhz}')
    records = []
    patterns=[('random',1),('random',42),('random',20261006),('negative_extreme',1),
              ('positive_extreme',1),('zeros',1),('alternating',1),('cancellation',1)]
    for pattern,seed in patterns:
        rng = np.random.default_rng(seed)
        started = time.perf_counter()
        counter_cycles = 0
        for _ in range(args.pairs):
            a0,b0,a1,b1 = (rng.integers(-128,128,(16,16),dtype=np.int8) for _ in range(4))
            if pattern in ('negative_extreme','positive_extreme','zeros'):
                value={'negative_extreme':-128,'positive_extreme':127,'zeros':0}[pattern]
                a0,b0,a1,b1=(np.full((16,16),value,dtype=np.int8) for _ in range(4))
            elif pattern=='alternating':
                a0=np.where(np.indices((16,16)).sum(axis=0)%2,-128,127).astype(np.int8)
                b0=np.flip(a0,axis=1).copy(); a1=b0.copy(); b1=a0.copy()
            elif pattern=='cancellation':
                a0=np.full((16,16),127,dtype=np.int8)
                b0=np.repeat(np.where(np.arange(16)%2,-127,127).astype(np.int8)[:,None],16,axis=1)
                a1=a0.copy(); b1=b0.copy()
            c0,c1 = accel.execute_dual_tile(a0,b0,a1,b1)
            np.testing.assert_array_equal(c0,a0.astype(np.int32) @ b0.astype(np.int32))
            np.testing.assert_array_equal(c1,a1.astype(np.int32) @ b1.astype(np.int32))
            counter_cycles += accel.get_hardware_counters()['cycles']
        records.append({'pattern':pattern,'seed':seed,'pairs':args.pairs,'elapsed_seconds':time.perf_counter()-started,'compute_controller_cycles':counter_cycles})
    tail_a=rng.integers(-128,128,(24,33),dtype=np.int8)
    tail_b=rng.integers(-128,128,(33,20),dtype=np.int8)
    tail_c,tail_metrics=accel.multiply(tail_a,tail_b)
    np.testing.assert_array_equal(tail_c,tail_a.astype(np.int32) @ tail_b.astype(np.int32))
    report = {'functional_pass':True,'runtime_clock_mhz':actual_clock,'watts_measured':False,
        'runs':records,'host_k_accumulation_and_tail_pass':True,'tail_metrics':tail_metrics,
        'bitstream':str(Path(args.bitstream).resolve())}
    Path(args.output).write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))

if __name__ == '__main__':
    main()

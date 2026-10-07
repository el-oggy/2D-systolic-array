"""Exercise release gates with complete and deliberately invalid evidence."""
import hashlib
import json
import sys
import os
import ctypes
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'board_implementation/vivado'))
from qualify_candidate import check,sha
from run_timing_power import parse_saif,merge_tree,emit_saif,run,validate_elaboration
from write_export_manifest import FILES,write_manifest
import run_timing_power

class QualificationTests(unittest.TestCase):
    def setUp(self):
        scratch=ROOT/'results/power_optimization/regression'
        scratch.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=scratch)
        self.c=Path(self.temp.name).resolve()
        assert self.c.is_relative_to(scratch.resolve())
        self.addCleanup(self.temp.cleanup)
        for name in [*FILES,'drc.rpt','source.sv','bench.sv','capture.tcl']:
            (self.c/name).write_text(name)
        (self.c/'adaptive_gemm.hwh').write_text('<SYSTEM><PARAMETER NAME="PCW_FPGA0_PERIPHERAL_FREQMHZ" VALUE="100"/></SYSTEM>')
        self.write('routed_clock.json',{'period_ns':10,'frequency_mhz':100})
        self.write('artifact_manifest.json',{name:sha(self.c/name) for name in FILES})
        (self.c/'elaborate.log').write_text('INFO: [XSIM 43-3452] SDF backannotation was successful for SDF file "board.sdf", for root module "/tb_board_power/dut".')
        (self.c/'timing_routed.rpt').write_text('All user specified timing constraints are met.')
        (self.c/'route_status.rpt').write_text('# of routable nets..........: 10\n# of fully routed nets.......: 10\n# of nets with routing errors: 0\n')
        self.write('route_status.json',dict(wns_ns=.1,whs_ns=.01,critical_drc=0,clock_mhz=100))
        self.write('source_hashes.json',{'source.sv':sha(self.c/'source.sv')})
        activity=[]; power=[]; hashes={}
        for p,s in [(0,1),(0,42),(0,20261006),(1,1),(2,1),(3,1),(4,1),(5,1)]:
            for m in ['compute','transaction']:
                saif=self.c/f'{p}_{s}_{m}.saif'; saif.write_text('fixture')
                rpt=saif.with_suffix('.rpt'); rpt.write_text('fixture')
                a=dict(pattern=p,seed=s,mode=m,windows=256,path=str(saif),
                       saif_sha256=sha(saif),
                       capture_inputs={str(self.c/'capture.tcl'):sha(self.c/'capture.tcl')})
                activity.append(a)
                power.append(dict(a,saif_sha256=sha(saif),power_report=str(rpt),
                                  power_report_sha256=sha(rpt),pl_dynamic_estimate_w=.8))
                hashes[str(saif)]=sha(saif)
        self.write('activity_manifest.json',dict(smoke_only=False,accelerator_only=False,partial_workload=False,
            clock_mhz=100,compiled_inputs={'sources':{str(self.c/'bench.sv'):sha(self.c/'bench.sv'),
                str(self.c/'elaborate.log'):sha(self.c/'elaborate.log')},
                'sdf_annotation':{'mode':'maximum','root':'/tb_board_power/dut'}},runs=activity))
        self.write('power_summary.json',dict(clock_mhz=100,routed_sha256=sha(self.c/'routed.dcp'),runs=power))
        self.write('coverage_review.json',dict(reviewed=True,routed_sha256=sha(self.c/'routed.dcp'),
            saif_sha256=hashes,blocking_unannotated_pl_blocks=[]))
    def write(self,name,value): (self.c/name).write_text(json.dumps(value))
    def alter(self,name,mutate):
        value=json.loads((self.c/name).read_text()); mutate(value); self.write(name,value)
    def test_complete_evidence_passes(self): self.assertEqual(check(self.c,self.c),[])
    def test_changed_sources_fail(self):
        (self.c/'source.sv').write_text('changed')
        self.assertIn('Source changed: source.sv',check(self.c,self.c))
    def test_incomplete_patterns_fail(self):
        self.alter('power_summary.json',lambda v:v['runs'].pop())
        self.assertTrue(any('patterns' in e for e in check(self.c,self.c)))
    def test_power_up_to_12_w_is_accepted(self):
        self.alter('power_summary.json',lambda v:v['runs'][0].update(pl_dynamic_estimate_w=1.2))
        self.assertEqual(check(self.c,self.c),[])
    def test_rounding_cannot_hide_power_above_12_w(self):
        self.alter('power_summary.json',lambda v:v['runs'][0].update(pl_dynamic_estimate_w=1.202))
        self.assertTrue(any('exceeds 1.2 W' in e for e in check(self.c,self.c)))
    def test_unreviewed_coverage_fails(self):
        self.alter('coverage_review.json',lambda v:v.update(reviewed=False))
        self.assertTrue(any('Unannotated' in e for e in check(self.c,self.c)))
    def test_clock_mismatch_fails(self):
        self.alter('activity_manifest.json',lambda v:v.update(clock_mhz=75))
        self.assertIn('Clock provenance mismatch',check(self.c,self.c))
    def test_changed_simulation_input_fails(self):
        (self.c/'bench.sv').write_text('changed')
        self.assertTrue(any('Simulation input changed' in e for e in check(self.c,self.c)))
    def test_unannotated_power_capture_is_rejected(self):
        self.alter('activity_manifest.json',lambda v:v['compiled_inputs'].pop('sdf_annotation'))
        self.assertTrue(any('SDF' in e for e in check(self.c,self.c)))
    def test_power_capture_cannot_claim_annotation_without_matching_log(self):
        (self.c/'elaborate.log').write_text('Built simulation snapshot power_sim')
        self.alter('activity_manifest.json',lambda v:v['compiled_inputs']['sources'].update({
            str(self.c/'elaborate.log'):sha(self.c/'elaborate.log')}))
        self.assertTrue(any('SDF' in e for e in check(self.c,self.c)))
    def test_incomplete_route_fails(self):
        (self.c/'route_status.rpt').write_text('# of routable nets: 10\n# of fully routed nets: 9\n# of nets with routing errors: 0')
        self.assertTrue(any('Routing is incomplete' in e for e in check(self.c,self.c)))
    def test_wrong_frequency_handoff_is_rejected(self):
        (self.c/'adaptive_gemm.hwh').write_text('<SYSTEM><PARAMETER NAME="PCW_FPGA0_PERIPHERAL_FREQMHZ" VALUE="75"/></SYSTEM>')
        self.alter('artifact_manifest.json',lambda v:v.update({'adaptive_gemm.hwh':sha(self.c/'adaptive_gemm.hwh')}))
        self.assertTrue(any('handoff frequency' in e.lower() for e in check(self.c,self.c)),
                        'A 100 MHz route must reject a 75 MHz handoff')
    def test_changed_handoff_is_rejected(self):
        (self.c/'adaptive_gemm.hwh').write_text('another handoff')
        self.assertTrue(any('handoff' in e.lower() for e in check(self.c,self.c)),
                        'The handoff must be bound to the routed export')
    def test_routed_clock_export_cannot_disagree_with_handoff(self):
        self.write('routed_clock.json',{'frequency_mhz':50,'period_ns':20})
        self.alter('artifact_manifest.json',lambda v:v.update({'routed_clock.json':sha(self.c/'routed_clock.json')}))
        self.assertTrue(any('routed clock' in e.lower() for e in check(self.c,self.c)),
                        'Matching metadata and HWH cannot override the clock exported from the DCP')
    def test_saif_aggregation_preserves_compute_duration_and_toggles(self):
        first=parse_saif('(SAIFILE (DURATION 100) (INSTANCE dut (NET (a (T0 60) (T1 40) (TX 0) (TZ 0) (TC 4) (IG 1)))))')
        second=parse_saif('(SAIFILE (DURATION 200) (INSTANCE dut (NET (a (T0 120) (T1 80) (TX 0) (TZ 0) (TC 8) (IG 2)))))')
        merge_tree(first,second)
        combined=emit_saif(first)
        for stat in ['(DURATION 300)','(T0 180)','(T1 120)','(TC 12)','(IG 3)']:
            self.assertIn(stat,combined)
    def test_missing_sdf_annotation_is_rejected_even_when_snapshot_builds(self):
        with self.assertRaisesRegex(RuntimeError,'annotation'):
            validate_elaboration('Built simulation snapshot power_sim', '/tb_board_power/dut')
    def test_sdf_warning_is_rejected_even_with_success_message(self):
        log='WARNING: [XSIM 43-3918] Unable to determine HDL language type of design hierarchy in SDF.\n'
        log+='INFO: [XSIM 43-3452] SDF backannotation was successful for SDF file "board.sdf", for root module "/tb_board_power/dut".'
        with self.assertRaisesRegex(RuntimeError,'annotation'):
            validate_elaboration(log, '/tb_board_power/dut')
    def test_annotation_must_match_requested_scope(self):
        log='INFO: [XSIM 43-3452] SDF backannotation was successful for SDF file "board.sdf", for root module "/dut".'
        with self.assertRaisesRegex(RuntimeError,'annotation'):
            validate_elaboration(log, '/tb_board_power/dut')
    def test_explicit_successful_annotation_is_accepted(self):
        log='INFO: [XSIM 43-3452] SDF backannotation was successful for SDF file "board.sdf", for root module "/tb_board_power/dut".'
        validate_elaboration(log, '/tb_board_power/dut')
    def test_xsim_zero_exit_and_pass_marker_cannot_hide_timing_violation(self):
        # This warning format was reproduced using a real annotated FDRE.
        warning='WARNING: "FDRE.v" Line 153: Timing violation in scope /tb_board_power/dut/ff at time 200100 ps $setuphold (posedge C,posedge D) $hold violation detected.\n'
        binary=self.c/'toolchain/bin'
        glbl=binary.parent/'data/verilog/src/glbl.v'
        glbl.parent.mkdir(parents=True)
        glbl.write_text('// fixture global reset model')
        def fake_tool(cmd,cwd,log,env=None):
            if 'xelab.bat' in cmd:
                text='INFO: [XSIM 43-3452] SDF backannotation was successful for SDF file "board.sdf", for root module "/tb_board_power/dut".'
            elif 'xsim.bat' in cmd:
                text=warning+'PASS: 4 full-board tile pairs, 2048 DDR result words\n'
            else: text='Compilation complete'
            Path(log).write_text(text)
        argv=['run_timing_power',str(self.c),'--clock-mhz','100','--smoke',
              '--smoke-pairs','4','--vivado-bin',str(binary)]
        with patch.object(sys,'argv',argv),patch.object(run_timing_power,'run',fake_tool):
            with self.assertRaisesRegex(RuntimeError,'Timing simulation did not pass'):
                run_timing_power.main()
        self.assertFalse((self.c/'smoke_manifest.json').exists(),
                         'A warned run must never record accepted activity')
    @unittest.skipUnless(os.name=='nt','Windows process-tree cleanup')
    def test_tool_child_process_is_cleaned_up(self):
        pidfile=self.c/'child.pid'
        code='import subprocess,sys,pathlib; p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"]); pathlib.Path(sys.argv[1]).write_text(str(p.pid))'
        run([sys.executable,'-c',code,str(pidfile)],self.c,self.c/'child.log')
        api=ctypes.WinDLL('kernel32',use_last_error=True)
        api.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32]
        api.OpenProcess.restype=ctypes.c_void_p
        api.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
        api.WaitForSingleObject.restype=ctypes.c_uint32
        api.CloseHandle.argtypes=[ctypes.c_void_p]
        handle=api.OpenProcess(0x100000,False,int(pidfile.read_text()))
        if handle:
            try: self.assertEqual(api.WaitForSingleObject(handle,1000),0)
            finally: api.CloseHandle(handle)

if __name__=='__main__': unittest.main()

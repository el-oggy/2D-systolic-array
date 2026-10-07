"""Fail closed on timing, routing, activity, coverage, or provenance gaps."""
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from write_export_manifest import FILES
from run_timing_power import validate_elaboration

MAX_PL_DYNAMIC_W = 1.2

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def check(candidate,root):
    errors=[]
    required=['routed.dcp','adaptive_gemm.hwh','timing_routed.rpt','route_status.rpt','drc.rpt',
              'route_status.json','source_hashes.json','activity_manifest.json','power_summary.json','coverage_review.json',
              'artifact_manifest.json']
    for name in required:
        if not (candidate/name).is_file(): errors.append(f'Missing {name}')
    for name in FILES:
        if not (candidate/name).is_file(): errors.append(f'Missing routed export: {name}')
    if errors: return errors
    route=json.loads((candidate/'route_status.json').read_text())
    artifacts=json.loads((candidate/'artifact_manifest.json').read_text())
    for name in FILES:
        if artifacts.get(name)!=sha(candidate/name):
            errors.append(f'Routed export or hardware handoff changed: {name}')
    for name,digest in artifacts.items():
        path=candidate/name
        if not path.is_file() or sha(path)!=digest:
            errors.append(f'Export artifact changed or missing: {name}')
    routed_clock=json.loads((candidate/'routed_clock.json').read_text())
    if abs(routed_clock['frequency_mhz']-route['clock_mhz'])>0.01 or abs(1000.0/routed_clock['period_ns']-route['clock_mhz'])>0.01:
        errors.append('Exported routed clock differs from candidate frequency')
    try:
        frequencies=[float(p.attrib['VALUE']) for p in ET.parse(candidate/'adaptive_gemm.hwh').iter('PARAMETER')
                     if p.attrib.get('NAME')=='PCW_FPGA0_PERIPHERAL_FREQMHZ']
        if len(frequencies)!=1 or abs(frequencies[0]-route['clock_mhz'])>0.001:
            errors.append('Hardware handoff frequency differs from routed clock')
    except (ET.ParseError,ValueError,KeyError):
        errors.append('Hardware handoff does not declare a valid routed clock')
    if route['wns_ns']<0 or route['whs_ns']<0 or route['critical_drc']!=0:
        errors.append('Routed timing or critical DRC failed')
    timing=(candidate/'timing_routed.rpt').read_text()
    if 'All user specified timing constraints are met.' not in timing:
        errors.append('Timing summary does not certify all constraints met')
    routes=(candidate/'route_status.rpt').read_text()
    counts={label:int(match[1]) for label in ['routable nets','fully routed nets','nets with routing errors']
            if (match:=re.search(r'# of '+label+r'[.\s]*:\s*(\d+)',routes,re.I))}
    if len(counts)!=3 or counts.get('nets with routing errors')!=0 or counts.get('routable nets')!=counts.get('fully routed nets'):
        errors.append('Routing is incomplete or has errors')
    sources=json.loads((candidate/'source_hashes.json').read_text())
    for name,digest in sources.items():
        path=root/name
        if not path.is_file() or sha(path)!=digest: errors.append(f'Source changed: {name}')
    activity=json.loads((candidate/'activity_manifest.json').read_text())
    power=json.loads((candidate/'power_summary.json').read_text())
    review=json.loads((candidate/'coverage_review.json').read_text())
    if activity['smoke_only'] or activity['accelerator_only']: errors.append('Insufficient activity scope')
    if activity.get('partial_workload',True): errors.append('Activity suite is incomplete')
    for name,digest in activity.get('compiled_inputs',{}).get('sources',{}).items():
        path=Path(name)
        if not path.is_file() or sha(path)!=digest: errors.append(f'Simulation input changed: {name}')
    if not activity.get('compiled_inputs',{}).get('sources'): errors.append('Simulation provenance missing')
    annotation=activity.get('compiled_inputs',{}).get('sdf_annotation',{})
    if annotation!={'mode':'maximum','root':'/tb_board_power/dut'}:
        errors.append('Maximum full-board SDF annotation provenance missing')
    logs=[Path(name) for name in activity.get('compiled_inputs',{}).get('sources',{}) if Path(name).name=='elaborate.log']
    try:
        if len(logs)!=1 or not logs[0].is_file():
            raise RuntimeError('Elaboration log missing or ambiguous')
        validate_elaboration(logs[0].read_text(errors='replace'),'/tb_board_power/dut')
    except RuntimeError as exc:
        errors.append('SDF annotation evidence rejected: '+str(exc))
    expected={(p,s,m) for p,s in [(0,1),(0,42),(0,20261006),(1,1),(2,1),(3,1),(4,1),(5,1)] for m in ['compute','transaction']}
    actual={(r['pattern'],r['seed'],r['mode']) for r in power['runs'] if r['windows']>=256}
    if actual!=expected: errors.append('Required power patterns, seeds, or windows missing')
    if power['routed_sha256']!=sha(candidate/'routed.dcp') or review.get('routed_sha256')!=power['routed_sha256']:
        errors.append('Power or coverage review belongs to another routed design')
    if not review.get('reviewed') or review.get('blocking_unannotated_pl_blocks', ['Not reviewed']):
        errors.append('Unannotated PL activity has not been resolved')
    if activity['clock_mhz']!=route['clock_mhz'] or power['clock_mhz']!=route['clock_mhz']:
        errors.append('Clock provenance mismatch')
    for r in power['runs']:
        matching=[a for a in activity['runs'] if (a['pattern'],a['seed'],a['mode'])==(r['pattern'],r['seed'],r['mode'])]
        if len(matching)!=1 or not matching[0].get('capture_inputs'):
            errors.append('Capture provenance missing or ambiguous')
        else:
            if matching[0].get('saif_sha256')!=r['saif_sha256']:
                errors.append('Power activity does not match its checked capture')
            for name,digest in matching[0]['capture_inputs'].items():
                path=Path(name)
                if not path.is_file() or sha(path)!=digest: errors.append(f'Capture input changed: {name}')
        path=Path(r['path'])
        if not path.is_file() or sha(path)!=r['saif_sha256']: errors.append(f'Activity changed: {path}')
        if review.get('saif_sha256',{}).get(str(path))!=r['saif_sha256']: errors.append(f'Activity not reviewed: {path}')
        if not Path(r['power_report']).is_file() or sha(r['power_report'])!=r['power_report_sha256']:
            errors.append(f'Power report changed: {r["power_report"]}')
        if r['pl_dynamic_estimate_w']>MAX_PL_DYNAMIC_W:
            errors.append(f'PL power exceeds 1.2 W acceptance ceiling: {r["mode"]} pattern {r["pattern"]} seed {r["seed"]}')
    return errors

def main():
    p=argparse.ArgumentParser(); p.add_argument('candidate',type=Path)
    args=p.parse_args(); candidate=args.candidate.resolve(); root=Path(__file__).resolve().parents[2]
    metadata=candidate/'build_metadata.json'
    if metadata.exists(): root=Path(json.loads(metadata.read_text()).get('current_workspace_root',root))
    errors=check(candidate,root)
    report={'vivado_qualified':not errors,'board_verified':False,'physical_power_measured':False,'blockers':errors}
    (candidate/'qualification.json').write_text(json.dumps(report,indent=2))
    if errors: raise SystemExit('Candidate rejected:\n'+'\n'.join(errors))
    print('Vivado estimate qualified; board functional/clock verification remains required.')

if __name__=='__main__': main()

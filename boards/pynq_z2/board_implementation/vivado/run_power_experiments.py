"""Reproducible candidate matrix. No failed candidate is exported as a release.

Long Vivado/XSim commands run serially to bound RAM/CPU usage. Coverage review
is deliberately an evidence gate; this script never invents a disposition.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from run_timing_power import run,batch_command
from qualify_candidate import check

ROOT=Path(__file__).resolve().parents[2]

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def snapshot():
    files=[]
    for directory in ['src','simulation','board_implementation','pynq']:
        files.extend(p for p in (ROOT/directory).rglob('*') if p.is_file() and p.suffix in {'.sv','.v','.xdc','.tcl','.py','.ps1'})
    hashes={p.relative_to(ROOT).as_posix():digest(p) for p in sorted(files)}
    identity=hashlib.sha256(json.dumps(hashes,sort_keys=True).encode()).hexdigest()[:12]
    target=ROOT/'results/power_optimization/sources'/identity
    for p in files:
        dest=target/p.relative_to(ROOT); dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists() and digest(dest)!=hashes[p.relative_to(ROOT).as_posix()]:
            raise RuntimeError(f'Immutable snapshot changed: {dest}')
        if not dest.exists(): shutil.copy2(p,dest)
    (target/'manifest.json').write_text(json.dumps(hashes,indent=2))
    hardware={name:value for name,value in hashes.items() if name.startswith('src/') or name.endswith('.xdc') or name in {
        'board_implementation/vivado/create_project.tcl','board_implementation/vivado/block_design.tcl'}}
    return target,hardware

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--dsp',nargs='+',type=int,choices=[110,96,80,64],default=[110,96,80,64])
    p.add_argument('--mhz',nargs='+',type=int,choices=[100,75,50],default=[100,75,50])
    p.add_argument('--power-opt',nargs='+',type=int,choices=[0,1],default=[0,1])
    p.add_argument('--route-only',action='store_true')
    p.add_argument('--tag',default='',help='Short label for a preserved retry or a repeated implementation seed')
    p.add_argument('--placed-base',type=Path,help='Use this matching placed candidate for one power-opt-on comparison')
    p.add_argument('--vivado-bin',type=Path,default=Path('C:/Xilinx/2025.1/Vivado/bin'))
    p.add_argument('--vivado-threads',type=int,choices=[1,2,4],default=1,
                   help='Vivado worker limit; serial synthesis bounds memory on this host')
    args=p.parse_args()
    tool_env=os.environ.copy()
    tool_env.setdefault('PYNQ_POWER_PYTHON',sys.executable)
    if args.tag and not re.fullmatch(r'[a-z0-9_-]{1,12}',args.tag): p.error('--tag must be 1-12 lowercase letters, digits, underscores or hyphens')
    if args.placed_base and (args.power_opt!=[1] or len(args.dsp)!=1 or len(args.mhz)!=1):
        p.error('--placed-base requires one DSP limit, one frequency and --power-opt 1')
    suffix='_'+args.tag if args.tag else ''
    snap,hashes=snapshot()
    output=ROOT/'results/power_optimization'
    index=output/'experiment_matrix.json'
    records=json.loads(index.read_text()) if index.exists() else []
    new_records=[]
    for dsp in args.dsp:
        for mhz in args.mhz:
            for opt in args.power_opt:
                candidate=output/f'd{dsp}_f{mhz}_p{opt}_{snap.name[:6]}{suffix}'
                if candidate.exists():
                    raise RuntimeError(f'Candidate already exists; inspect it before rerunning: {candidate}')
                candidate.mkdir()
                (candidate/'source_hashes.json').write_text(json.dumps(hashes,indent=2))
                (candidate/'build_metadata.json').write_text(json.dumps({'snapshot':str(snap),
                    'current_workspace_root':str(ROOT),
                    'started_utc':datetime.now(timezone.utc).isoformat(),'dsp_per_engine':dsp,
                    'clock_mhz':mhz,'post_place_power_opt':bool(opt),'vivado_bin':str(args.vivado_bin),
                    'vivado_threads':args.vivado_threads},indent=2))
                record={'candidate':str(candidate),'dsp_per_engine':dsp,'clock_mhz':mhz,'power_opt':opt,'qualified':False}
                try:
                    reuse=[]
                    base=output/f'd{dsp}_f{mhz}_p0_{snap.name[:6]}{suffix}'
                    if args.placed_base: base=args.placed_base.resolve()
                    if args.placed_base and not ((base/'placed.dcp').is_file() and (base/'adaptive_gemm.hwh').is_file()):
                        raise RuntimeError('Placed base checkpoint or matching HWH is missing')
                    if opt and (base/'placed.dcp').exists() and (base/'adaptive_gemm.hwh').exists():
                        base_metadata=json.loads((base/'build_metadata.json').read_text())
                        if base_metadata['clock_mhz']!=mhz or base_metadata['dsp_per_engine']!=dsp:
                            raise RuntimeError('Placed base parameters do not match')
                        if json.loads((base/'source_hashes.json').read_text())!=hashes:
                            raise RuntimeError('Placed comparison source hashes do not match')
                        reuse=[str(base)]
                        metadata=json.loads((candidate/'build_metadata.json').read_text())
                        metadata.update(placed_base=str(base),placed_sha256=digest(base/'placed.dcp'),
                                        hwh_sha256=digest(base/'adaptive_gemm.hwh'))
                        (candidate/'build_metadata.json').write_text(json.dumps(metadata,indent=2))
                    command=batch_command(args.vivado_bin/'vivado.bat',['-mode','batch','-nojournal','-nolog',
                             '-source',str(snap/'board_implementation/vivado/build_power_candidate.tcl'),
                             '-tclargs',str(candidate),str(dsp),str(mhz),str(opt),
                             reuse[0] if reuse else '',str(args.vivado_threads)])
                    run(command,ROOT,candidate/'build.log',tool_env)
                    export=batch_command(args.vivado_bin/'vivado.bat',['-mode','batch','-nojournal','-nolog',
                            '-source',str(snap/'board_implementation/vivado/export_timing_candidate.tcl'),'-tclargs',str(candidate)])
                    run(export,ROOT,candidate/'export.log',tool_env)
                    record['route_pass']=True
                    if not args.route_only:
                        run([sys.executable,str(snap/'board_implementation/vivado/run_timing_power.py'),str(candidate),
                             '--clock-mhz',str(mhz),'--vivado-bin',str(args.vivado_bin)],ROOT,candidate/'activity.log',tool_env)
                        run([sys.executable,str(snap/'board_implementation/vivado/analyze_power.py'),str(candidate),
                             '--vivado-bin',str(args.vivado_bin)],ROOT,candidate/'analysis.log',tool_env)
                        record['blockers']=check(candidate,ROOT)
                        record['qualified']=not record['blockers']
                except Exception as exc:
                    record['error']=str(exc)
                records.append(record)
                new_records.append(record)
                (output/'experiment_matrix.json').write_text(json.dumps(records,indent=2))
                print(json.dumps(record),flush=True)
    # Recheck saved qualifications: current sources and artifacts may have changed.
    passing=[r for r in records if r.get('qualified') and not check(Path(r['candidate']),ROOT)]
    if passing:
        # At equal frequency compare worst workload power, then prefer 110 DSP
        # and no extra power transform when estimates differ by <= 1 mW.
        for r in passing:
            r['worst_pl_w']=json.loads((Path(r['candidate'])/'power_summary.json').read_text())['worst_pl_dynamic_estimate_w']
        fastest=max(r['clock_mhz'] for r in passing)
        choices=[r for r in passing if r['clock_mhz']==fastest]
        minimum=min(r['worst_pl_w'] for r in choices)
        choices=[r for r in choices if r['worst_pl_w']<=minimum+0.001]
        best=sorted(choices,key=lambda r:(-r['dsp_per_engine'],r['power_opt']))[0]
        (output/'selected_candidate.json').write_text(json.dumps(best,indent=2))
        print(f'Selected: {best["candidate"]}; board validation remains required')
    elif not args.route_only:
        raise SystemExit('No candidate qualified. See experiment_matrix.json; no constraints were relaxed.')
    elif not any(r.get('route_pass') for r in new_records):
        raise SystemExit('No requested candidate passed routing/timing. See experiment_matrix.json.')

if __name__=='__main__': main()

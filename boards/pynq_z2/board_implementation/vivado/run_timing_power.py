"""Post-route PL activity, including DMA and interconnect through a PS7 BFM.

Aggregate actual compute windows without averaging them with idle time. The
PS7 boundary model is excluded from PL power; Linux is not simulated.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path
from process_job import WindowsJob

STATS = {'T0','T1','TX','TZ','TC','IG','DURATION'}

def parse_saif(text):
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|\(|\)|[^\s()]+',text)
    stack = [[]]
    for token in tokens:
        if token == '(':
            node = []
            stack[-1].append(node)
            stack.append(node)
        elif token == ')':
            stack.pop()
        else:
            stack[-1].append(token)
    if len(stack) != 1:
        raise ValueError('Malformed SAIF')
    return stack[0][0]

def merge_tree(a,b):
    if a[0] in STATS:
        a[1] = str(int(a[1])+int(b[1]))
        return
    if len(a) != len(b) or a[0] != b[0]:
        raise ValueError('Inconsistent SAIF topology')
    for left,right in zip(a,b):
        if isinstance(left,list):
            merge_tree(left,right)

def emit_saif(node):
    return '('+' '.join(emit_saif(x) if isinstance(x,list) else x for x in node)+')'

def run(cmd,cwd,log,env=None):
    with open(log,'w') as stream:
        job=WindowsJob(); process=None
        try:
            process=subprocess.Popen(cmd,cwd=cwd,env=env,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT,
                                     creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            job.assign(process)
            code=process.wait()
        finally:
            if process is not None and process.poll() is None:
                process.kill(); process.wait()
            job.close()
    if code:
        raise RuntimeError(f'Command failed ({code}); see {log}')

def batch_command(binary,args):
    # cmd's batch argument parser treats unquoted '=' as a separator. Quote
    # every argument, particularly XSim plusargs and xelab generic overrides.
    values=[str(binary).replace('\\','/'),*(str(value).replace('\\','/') for value in args)]
    if any(re.search(r'["%!\r\n]',value) for value in values):
        raise ValueError('Unsupported batch argument character')
    return 'cmd.exe /d /s /c "'+' '.join('"'+value+'"' for value in values)+'"'

def validate_elaboration(log_text,root):
    # XSim may build a snapshot and return success after declining SDF. Delay
    # annotation therefore needs positive evidence and a separate warning gate.
    bad = re.search(r'(?:ERROR|WARNING).*?(?:SDF|back.?annotation|instance path)',log_text,re.I)
    roots = re.findall(r'SDF backannotation was successful[^\n]*root module "([^"]+)"',log_text)
    if bad or root not in roots:
        raise RuntimeError('Timing-delay annotation failed or lacked explicit success for '+root)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('candidate',type=Path)
    p.add_argument('--clock-mhz',type=float,required=True)
    p.add_argument('--vivado-bin',type=Path,default=Path('C:/Xilinx/2025.1/Vivado/bin'))
    p.add_argument('--elab-threads',choices=['off','2','4'],default='off',
                   help='XSim elaboration threads; lower values reduce peak compiler memory')
    p.add_argument('--elab-opt',choices=['0','1','2','3'],default='1',
                   help='XSim optimizer level; basic optimization limits compiler memory')
    p.add_argument('--elab-verbose',choices=['0','1','2'],default='0',
                   help='Compiler diagnostic verbosity; does not change timing or activity settings')
    p.add_argument('--smoke',action='store_true',help='Diagnostic jobs to verify timing simulation, never power signoff')
    p.add_argument('--smoke-pairs',type=int,default=1,choices=range(1,17),help='Diagnostic smoke size, up to 16 pairs; never power signoff')
    p.add_argument('--smoke-activity',action='store_true',help='Also exercise SAIF logging during diagnostic smoke jobs')
    p.add_argument('--accelerator-only',action='store_true',help='Diagnostic scope; cannot qualify whole PL power')
    p.add_argument('--reuse-snapshot',action='store_true',help='Reuse a snapshot whose recorded inputs and clock match')
    p.add_argument('--pattern',type=int,choices=range(6),help='Partial diagnostic workload; does not qualify the full pattern suite')
    p.add_argument('--seed',type=int,help='Partial diagnostic workload')
    p.add_argument('--mode',choices=['transaction','compute'],help='Partial diagnostic workload')
    args = p.parse_args()
    if args.smoke_activity and not args.smoke: p.error('--smoke-activity requires --smoke')
    if args.smoke_pairs!=1 and not args.smoke: p.error('--smoke-pairs requires --smoke')
    pairs=args.smoke_pairs if args.smoke else 256
    candidate = args.candidate.resolve()
    root = Path(__file__).resolve().parents[2]
    work = candidate/'simulation'
    work.mkdir(exist_ok=True)
    tools = args.vivado_bin
    bat = lambda name,rest: batch_command(tools/(name+'.bat'),rest)
    top = 'tb_power_regression' if args.accelerator_only else 'tb_board_power'
    tb = root/f'simulation/{top}.sv'
    stem = 'accel' if args.accelerator_only else 'board'
    glbl = tools.parent/'data/verilog/src/glbl.v'
    inputs=[tb,candidate/f'{stem}_timesim.v',candidate/f'{stem}_timesim.sdf',glbl]
    if not args.accelerator_only: inputs.append(candidate/'ps7_binding.vh')
    sdf_root=f'/{top}/dut'
    fingerprint={'clock_mhz':args.clock_mhz,'top':top,'debug':'wave','elab_threads':args.elab_threads,
        'elab_opt':args.elab_opt,'sdf_annotation':{'mode':'maximum','root':sdf_root},
        'sources':{str(path):hashlib.sha256(path.read_bytes()).hexdigest()
        for path in inputs}}
    compiled=work/'compiled_inputs.json'
    if args.reuse_snapshot:
        fingerprint['sources'][str(work/'elaborate.log')]=hashlib.sha256((work/'elaborate.log').read_bytes()).hexdigest()
        if not compiled.exists() or json.loads(compiled.read_text())!=fingerprint:
            raise RuntimeError('Compiled snapshot input provenance does not match')
        validate_elaboration((work/'elaborate.log').read_text(errors='replace'),sdf_root)
    else:
        run(bat('xvlog',['--sv','--define','GATE_DUT','--include',str(candidate),str(candidate/f'{stem}_timesim.v'),str(tb),str(glbl)]),work,work/'compile.log')
        run(bat('xelab',[top,'glbl','-incr','-generic_top',f'CLK_PERIOD={1000/args.clock_mhz}',
        '-L','simprims_ver','-L','unisims_ver','-L','secureip','-debug','wave',f'--O{args.elab_opt}',
        '-sdfmax',f'{sdf_root}={candidate / (stem+"_timesim.sdf")}',
        '-transport_int_delays','-pulse_r','0','-pulse_int_r','0',
        '-s','power_sim','-mt',args.elab_threads,'-stats','-verbose',args.elab_verbose]),work,work/'elaborate.log')
        validate_elaboration((work/'elaborate.log').read_text(errors='replace'),sdf_root)
        fingerprint['sources'][str(work/'elaborate.log')]=hashlib.sha256((work/'elaborate.log').read_bytes()).hexdigest()
        compiled.write_text(json.dumps(fingerprint,indent=2))
    seeds = [(0,1),(0,42),(0,20261006),(1,1),(2,1),(3,1),(4,1),(5,1)]
    if args.pattern is not None: seeds=[s for s in seeds if s[0]==args.pattern]
    if args.seed is not None: seeds=[s for s in seeds if s[1]==args.seed]
    if not seeds: raise ValueError('No matching pattern/seed combination')
    modes=[args.mode or 'transaction'] if args.smoke else ([args.mode] if args.mode else ['transaction','compute'])
    manifest=candidate/('smoke_manifest.json' if args.smoke else 'activity_manifest.json')
    records = []
    if args.reuse_snapshot and not args.smoke and manifest.exists():
        previous=json.loads(manifest.read_text())
        if not previous['smoke_only'] and previous['compiled_inputs']==fingerprint:
            records=previous['runs']
    for pattern,seed in seeds[:1] if args.smoke else seeds:
        for mode in modes:
            name = f'p{pattern}_s{seed}_{mode}'
            out = work/name
            out.mkdir(exist_ok=True)
            env = os.environ.copy()
            scopes=candidate/'activity_scopes.txt'
            if args.accelerator_only:
                core=(candidate/'accelerator_instance.txt').read_text().strip()
                scopes=work/'accelerator_scopes.txt'
                scopes.write_text('.\n'+'\n'.join(line[len(core)+1:] for line in
                    (candidate/'activity_scopes.txt').read_text().splitlines() if line.startswith(core+'/'))+'\n')
            env.update(POWER_ACTIVITY_MODE=mode,POWER_PERIOD_NS=str(1000/args.clock_mhz),POWER_TEST_TOP=top,
                       POWER_ACTIVITY_SCOPES=str(scopes),POWER_PAIRS=str(pairs))
            capture = root/'board_implementation/vivado/capture_power_activity.tcl'
            if args.smoke and not args.smoke_activity:
                capture = out/'smoke.tcl'
                capture.write_text(f'run all\nif {{[get_value -radix bin /{top}/finished] ne "1"}} {{ error "Smoke test did not complete" }}\nquit\n')
            capture_inputs={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [capture,scopes]}
            env['POWER_SCOPE_SIGNATURE']=hashlib.sha256(json.dumps([fingerprint,capture_inputs],sort_keys=True).encode()).hexdigest()
            existing=[r for r in records if (r['pattern'],r['seed'],r['mode'])==(pattern,seed,mode)]
            if existing:
                saved=existing[0]
                for path,digest in saved['capture_inputs'].items():
                    if not Path(path).is_file() or hashlib.sha256(Path(path).read_bytes()).hexdigest()!=digest:
                        raise RuntimeError('Saved capture inputs changed; preserve the existing evidence in a new candidate')
                if not Path(saved['path']).is_file() or hashlib.sha256(Path(saved['path']).read_bytes()).hexdigest()!=saved.get('saif_sha256'):
                    raise RuntimeError('Saved activity changed or is missing')
                print(f'{name}: reused verified capture',flush=True)
                continue
            # xsim uses a snapshot relative to cwd; retain compiled simulation
            # in work and give capture files their own directory after each run.
            aggregator_error = []
            aggregate = [None]
            stop = threading.Event()
            def collect():
                index = 0
                while not stop.is_set() or (work/f'compute_{index:04d}.saif').exists():
                    f = work/f'compute_{index:04d}.saif'
                    if not f.exists():
                        time.sleep(0.05)
                        continue
                    # A following file or completion sentinel proves close_saif
                    # finished writing the current file.
                    if not (work/f'compute_{index+1:04d}.saif').exists() and not (work/'capture_complete.txt').exists():
                        time.sleep(0.05)
                        continue
                    try:
                        tree = parse_saif(f.read_text())
                        if aggregate[0] is None:
                            aggregate[0] = tree
                        else:
                            merge_tree(aggregate[0],tree)
                        f.unlink()
                        index += 1
                    except Exception as exc:
                        aggregator_error.append(str(exc)); return
            worker = None
            if mode == 'compute':
                if list(work.glob('compute_*.saif')):
                    raise RuntimeError('Incomplete compute capture files remain; preserve or move them before rerunning')
                sentinel = work/'capture_complete.txt'
                if sentinel.exists(): sentinel.unlink()
                worker = threading.Thread(target=collect,daemon=True); worker.start()
            cmd = bat('xsim',['power_sim','-tclbatch',str(capture),'-testplusarg','POWER',
                '-testplusarg',f'PAIRS={pairs}',
                '-testplusarg',f'PATTERN={pattern}','-testplusarg',f'SEED={seed}'])
            try:
                run(cmd,work,out/'run.log',env)
            finally:
                stop.set()
                if worker: worker.join(timeout=60)
            log_text = (out/'run.log').read_text(errors='replace')
            if 'PASS:' not in log_text or re.search(r'FATAL|Timing violation|ERROR:|(?:ERROR|WARNING).*SDF|SDF.*(?:ERROR|WARNING)',log_text,re.I):
                raise RuntimeError(f'Timing simulation did not pass: {out / "run.log"}')
            if not args.accelerator_only and f'PASS: {pairs} full-board tile pairs, {pairs*512} DDR result words' not in log_text:
                raise RuntimeError('Timing simulation workload count did not match the request')
            if mode == 'compute':
                if aggregator_error or aggregate[0] is None or worker.is_alive():
                    raise RuntimeError(f'Compute SAIF aggregation failed: {aggregator_error}')
                (out/'activity.saif').write_text(emit_saif(aggregate[0]))
                windows = int((work/'capture_complete.txt').read_text())
                (work/'capture_complete.txt').unlink()
                (work/'compute_window_signal.txt').replace(out/'compute_window_signal.txt')
            elif not args.smoke or args.smoke_activity:
                (work/'transaction.saif').replace(out/'activity.saif')
                windows = pairs
            else:
                windows = pairs
            if not args.smoke or args.smoke_activity:
                cache=work/'activity_objects.tcllist'
                capture_inputs[str(cache)]=hashlib.sha256(cache.read_bytes()).hexdigest()
            records=[r for r in records if (r['pattern'],r['seed'],r['mode'])!=(pattern,seed,mode)]
            records.append({'pattern':pattern,'seed':seed,'mode':mode,'windows':windows,'path':str(out/'activity.saif'),
                            'capture_inputs':capture_inputs,'saif_sha256':hashlib.sha256((out/'activity.saif').read_bytes()).hexdigest()
                            if not args.smoke or args.smoke_activity else None})
            manifest.write_text(json.dumps({'smoke_only':args.smoke,
                'accelerator_only':args.accelerator_only,'clock_mhz':args.clock_mhz,
                'partial_workload':len(records)!=16,'compiled_inputs':fingerprint,
                'ps_boundary_model':'GP0 MMIO and HP0 DDR slave, zero deliberate transaction gaps',
                'runs':records},indent=2))
            print(f'{name}: timing simulation passed',flush=True)
    manifest.write_text(json.dumps({'smoke_only':args.smoke,
        'accelerator_only':args.accelerator_only,'clock_mhz':args.clock_mhz,
        'partial_workload':len(records)!=16,'compiled_inputs':fingerprint,
        'ps_boundary_model':'GP0 MMIO and HP0 DDR slave, zero deliberate transaction gaps',
        'runs':records},indent=2))

if __name__ == '__main__':
    main()

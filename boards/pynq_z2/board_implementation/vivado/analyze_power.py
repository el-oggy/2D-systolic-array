"""Analyze full-board routed SAIF. Qualification requires coverage review."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from run_timing_power import run

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def table_value(text,label):
    match=re.search(r'^\|\s*'+re.escape(label)+r'\s*\|\s*([\d.]+)',text,re.M)
    if not match: raise ValueError(f'Missing power row: {label}')
    return float(match[1])

def main():
    p=argparse.ArgumentParser()
    p.add_argument('candidate',type=Path)
    p.add_argument('--vivado-bin',type=Path,default=Path('C:/Xilinx/2025.1/Vivado/bin'))
    args=p.parse_args(); candidate=args.candidate.resolve()
    manifest=json.loads((candidate/'activity_manifest.json').read_text())
    if manifest['smoke_only'] or manifest['accelerator_only']:
        raise RuntimeError('Whole-PL power requires full-board workload activity')
    records=[]
    for entry in manifest['runs']:
        saif=Path(entry['path']); prefix=saif.parent/'routed'
        if entry.get('saif_sha256')!=sha(saif):
            raise RuntimeError(f'Activity changed after its simulation check: {saif}')
        cmd=['cmd.exe','/d','/c',str(args.vivado_bin/'vivado.bat'),'-mode','batch','-nojournal','-nolog',
             '-source',str(Path(__file__).with_name('analyze_activity.tcl')),
             '-tclargs',str(candidate),str(saif),str(prefix),'tb_board_power']
        run(cmd,candidate,prefix.with_suffix('.log'))
        text=Path(str(prefix)+'_power.rpt').read_text()
        total=table_value(text,'Dynamic (W)'); ps=table_value(text,'PS7')
        coverage=re.search(r'^\|\s*Design Nets Matched\s*\|\s*([^|]+)',text,re.M)
        records.append({**entry,'dynamic_total_w':total,'ps7_dynamic_w':ps,
            'pl_dynamic_estimate_w':round(total-ps,6),
            'design_nets_matched':coverage.group(1).strip() if coverage else 'Unavailable',
            'saif_sha256':sha(saif),'power_report_sha256':sha(str(prefix)+'_power.rpt'),
            'power_report':str(prefix)+'_power.rpt','coverage_report':str(prefix)+'_coverage.rpt',
            'switching_report':str(prefix)+'_switching.rpt'})
        print(f"{entry['pattern']}/{entry['seed']}/{entry['mode']}: PL estimate {total-ps:.3f} W",flush=True)
    result={'estimate_not_measurement':True,'routed_sha256':sha(candidate/'routed.dcp'),
        'clock_mhz':manifest['clock_mhz'],'coverage_review_required':True,
        'worst_pl_dynamic_estimate_w':max(r['pl_dynamic_estimate_w'] for r in records),'runs':records}
    (candidate/'power_summary.json').write_text(json.dumps(result,indent=2))

if __name__=='__main__': main()

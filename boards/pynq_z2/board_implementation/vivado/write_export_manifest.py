"""Bind a completed routed export and its handoff; never overwrite old evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

FILES=['routed.dcp','adaptive_gemm.hwh','board_timesim.v','board_timesim.sdf',
       'accel_timesim.v','accel_timesim.sdf','ps7_binding.vh','activity_scopes.txt','routed_clock.json']

def write_manifest(candidate):
    clock=json.loads((candidate/'route_status.json').read_text())['clock_mhz']
    routed_clock=json.loads((candidate/'routed_clock.json').read_text())
    if abs(routed_clock['frequency_mhz']-clock)>0.01:
        raise RuntimeError('Clock exported from the routed DCP differs from candidate metadata')
    frequencies=[float(p.attrib['VALUE']) for p in ET.parse(candidate/'adaptive_gemm.hwh').iter('PARAMETER')
                 if p.attrib.get('NAME')=='PCW_FPGA0_PERIPHERAL_FREQMHZ']
    if len(frequencies)!=1 or abs(frequencies[0]-clock)>0.001:
        raise RuntimeError('Hardware handoff frequency differs from routed clock')
    hashes={name:hashlib.sha256((candidate/name).read_bytes()).hexdigest() for name in FILES}
    target=candidate/'artifact_manifest.json'
    if target.exists() and json.loads(target.read_text())!=hashes:
        raise RuntimeError('Preserve the original export manifest; use a new candidate for changed artifacts')
    if not target.exists(): target.write_text(json.dumps(hashes,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('candidate',type=Path)
    write_manifest(parser.parse_args().candidate.resolve())

#!/usr/bin/env python3
"""Retain source/pin/mode controls and incoming bundled-notice checks together.

Use record_gate.py around this command once the reconciled source is saved.
This driver never resolves dependencies, changes source, or inspects user files.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo',type=Path,required=True)
    ap.add_argument('--quds',type=Path,required=True)
    ap.add_argument('--parser',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args()
    repo,quds,parser,output=[p.resolve() for p in [args.repo,args.quds,args.parser,args.output]]
    if output.exists() and any(output.iterdir()):
        ap.error('output must be empty; preserve prior attempts')
    output.mkdir(parents=True,exist_ok=True)
    driver=repo/'docs/evidence/storage-carving-20261115/local-resume-20261115T1010/source-integrity/run_source_only_controls.py'
    commands=[
        ('source-controls',[sys.executable,str(driver),'--repo',str(repo),'--quds',str(quds),'--parser',str(parser),'--output',str(output/'source')]),
        ('bundled-notices',[sys.executable,'tool/verify_bundled_notices.py']),
        ('bundled-notice-guards',[sys.executable,'-m','unittest','discover','-s','tool','-p','test_bundled_notice_guards.py','-v']),
    ]
    rows=[]
    for name,command in commands:
        started=datetime.now(timezone.utc).isoformat()
        result=subprocess.run(command,cwd=repo,capture_output=True,check=False)
        (output/(name+'.stdout.log')).write_bytes(result.stdout)
        (output/(name+'.stderr.log')).write_bytes(result.stderr)
        match=re.search(rb'Ran (\d+) tests? in',result.stderr)
        row={'name':name,'argv':command,'cwd':str(repo),'started_at':started,
             'finished_at':datetime.now(timezone.utc).isoformat(),
             'returncode':result.returncode,'unittest_count':int(match.group(1)) if match else None}
        rows.append(row)
        (output/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
        print(f'{name}: exit {result.returncode}',flush=True)
    source_summary_path=output/'source/summary.json'
    source_summary=json.loads(source_summary_path.read_text()) if source_summary_path.exists() else {}
    source_proof_path=output/'source/comparison/source-verification.json'
    source_proof=json.loads(source_proof_path.read_text()) if source_proof_path.exists() else {}
    expected_counts=source_summary.get('python_control_tests')==82 and rows[-1]['unittest_count']==3
    success=all(row['returncode']==0 for row in rows) and source_summary.get('success',False) and source_proof.get('success',False) and expected_counts
    summary={'schema':1,'at':datetime.now(timezone.utc).isoformat(),'commands':rows,
             'source_checks_passed':source_summary.get('success',False),
             'managed_files':source_proof.get('managed_files_verified'),
             'tracked_files':source_proof.get('tracked_files_verified'),
             'source_commit':source_proof.get('source_commit'),
             'canonical_pins':source_proof.get('canonical_pins'),
             'source_control_tests':source_summary.get('python_control_tests'),
             'bundled_notice_control_tests':rows[-1]['unittest_count'],
             'total_python_controls':(source_summary.get('python_control_tests') or 0)+(rows[-1]['unittest_count'] or 0),
             'expected_control_counts_match':expected_counts,'success':success,
             'scope':'Fresh full-checkout and managed SHA256/Git blob/mode checks against both canonical pins, guarded-sync dry runs, 82 source/inventory controls and 3 incoming notice guard controls. No native/runtime, external corpus, Office rendering or generated-document oracle claim.'}
    (output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    manifest={str(path.relative_to(output)):{'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size':path.stat().st_size}
              for path in sorted(output.rglob('*')) if path.is_file()}
    (output/'artifacts-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(summary,indent=2))
    return 0 if success else 1


if __name__=='__main__':
    raise SystemExit(main())

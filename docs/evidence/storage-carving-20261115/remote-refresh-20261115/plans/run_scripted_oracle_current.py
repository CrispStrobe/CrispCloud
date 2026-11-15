#!/usr/bin/env python3
"""Current-continuation oracle driver bound to the passed engine output fingerprints."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--generation-receipt', type=Path, required=True)
    args = ap.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    engine = repo / 'packages/quds_office_engine'
    produced = engine / 'build/fidelity-scripted'
    if output.exists() and any(output.iterdir()):
        ap.error('output must be empty')
    output.mkdir(parents=True, exist_ok=True)
    expected = {f'{kind}/{name}.{extension}'
                for kind, extension in [('word', 'docx'), ('sheet', 'xlsx'), ('slide', 'pptx')]
                for name in ['edited', 'roundtrip-1', 'roundtrip-2', 'roundtrip-3']}

    def fingerprints():
        names = {str(p.relative_to(produced)) for p in produced.rglob('*')
                 if p.suffix in {'.docx', '.xlsx', '.pptx'}}
        if names != expected:
            raise RuntimeError(f'Engine output inventory mismatch: missing={sorted(expected-names)}, extra={sorted(names-expected)}')
        return {name: {'sha256': hashlib.sha256((produced/name).read_bytes()).hexdigest(),
                       'size': (produced/name).stat().st_size} for name in sorted(names)}

    before = fingerprints()
    generation = json.loads(args.generation_receipt.read_text())
    if before != generation["files"]:
        raise RuntimeError("Oracle input bytes differ from the passed engine generator gate")
    commands = [
        ('oracle', [sys.executable, 'tool/fidelity/scripted_oracle.py']),
        ('controls', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tool/fidelity', '-p', 'test_scripted_oracle.py', '-v']),
    ]
    rows = []
    for name, command in commands:
        result = subprocess.run(command, cwd=engine, capture_output=True)
        (output/f'{name}.stdout.log').write_bytes(result.stdout)
        (output/f'{name}.stderr.log').write_bytes(result.stderr)
        match = re.search(rb'Ran (\d+) tests? in', result.stderr)
        rows.append({'name': name, 'argv': command, 'cwd': str(engine),
                     'returncode': result.returncode, 'tests': int(match.group(1)) if match else None})
        print(f'{name}: exit {result.returncode}', flush=True)
    after = fingerprints()
    for name in sorted(expected | {'oracle-report.json'}):
        destination = output/'produced'/name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(produced/name, destination)
    report = json.loads((output/'produced/oracle-report.json').read_text())
    success = (all(row['returncode'] == 0 for row in rows)
               and rows[1]['tests'] == 17 and before == after
               and report['exports'] == 12 and not report['failures'])
    summary = {'success': success, 'commands': rows, 'before': before, 'after': after,
               'generation_receipt_sha256': hashlib.sha256(args.generation_receipt.read_bytes()).hexdigest(),
               'generation_tested_head': generation['tested_head'],
               'generation_source_resolution_sha256': generation['source_resolution_sha256'],
               'produced_outputs_unchanged': before == after, 'oracle': report,
               'scope': 'Twelve genuine engine-produced DOCX/XLSX/PPTX edits and roundtrips against authored semantic expectations; 17 positive/negative oracle controls. Not external application rendering or broad schema conformance.'}
    (output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    artifacts = {str(p.relative_to(output)): {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'size': p.stat().st_size}
                 for p in sorted(output.rglob('*')) if p.is_file()}
    (output/'artifacts-sha256.json').write_text(json.dumps(artifacts, indent=2)+'\n')
    print(json.dumps({'success': success, 'exports': report['exports'], 'controls': rows[1]['tests'], 'produced_outputs_unchanged': before == after}, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())

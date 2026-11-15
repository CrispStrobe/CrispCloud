#!/usr/bin/env python3
"""Generate fresh comments workbooks and verify them with an independent reader."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def fingerprint(path):
    data = path.read_bytes()
    return {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error('Use a new output directory; retain every earlier attempt.')
    output.mkdir(parents=True, exist_ok=True)
    engine = repo / 'packages/quds_office_engine'
    fixture = engine / 'tool/fidelity/comment_schema_fixture.dart'
    verifier = Path(__file__).resolve().with_name('verify_comments.py')
    generated = output / 'workbooks'
    commands = [
        ('generate', [str(args.dart), 'run', str(fixture), str(generated)]),
        ('independent-reader', [sys.executable, str(verifier), '--input-dir',
                                str(generated), '--report', str(output / 'reader-report.json')]),
    ]
    records = []
    for name, command in commands:
        started = datetime.now(timezone.utc).isoformat()
        result = subprocess.run(command, cwd=engine, capture_output=True, check=False)
        (output / (name + '.stdout.log')).write_bytes(result.stdout)
        (output / (name + '.stderr.log')).write_bytes(result.stderr)
        records.append({'name': name, 'argv': command, 'cwd': str(engine),
                        'started_at': started, 'finished_at': datetime.now(timezone.utc).isoformat(),
                        'returncode': result.returncode})
        (output / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
        if result.returncode:
            break
    expected = {f'comments-cycle-{cycle}.xlsx' for cycle in range(1, 4)} | {'expected-comments.json'}
    actual = {p.name for p in generated.iterdir() if p.is_file()} if generated.is_dir() else set()
    report_path = output / 'reader-report.json'
    report = json.loads(report_path.read_text()) if report_path.is_file() else {}
    success = len(records) == 2 and all(r['returncode'] == 0 for r in records) and actual == expected and report.get('success') is True
    summary = {'schema': 1, 'success': success, 'commands': records,
               'generator': fingerprint(fixture), 'verifier': fingerprint(verifier),
               'expected_outputs_match': actual == expected,
               'scope': 'Three fresh XLSX save/reopen cycles, six exact plain comment texts/authors, namespace/relationship structure, and independent openpyxl readback. No broad Open XML schema or native Office rendering claim.'}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    files = {str(p.relative_to(output)): fingerprint(p) for p in sorted(output.rglob('*')) if p.is_file()}
    (output / 'artifacts-sha256.json').write_text(json.dumps(files, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())

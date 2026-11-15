#!/usr/bin/env python3
"""Run existing source/inventory controls and retain every command receipt."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import time


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--quds', type=Path, required=True)
    ap.add_argument('--parser', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    repo, quds, parser, output = (p.resolve() for p in (args.repo, args.quds, args.parser, args.output))
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((repo / 'tool/office_fidelity_manifest.json').read_text())
    commands = [
        ('managed-office-verifier', [sys.executable, 'tool/verify_office_fidelity.py', '--source', str(quds), '--legacy-source', str(parser), '--require-tracked']),
        ('full-source-and-mode-verifier', [sys.executable, str(Path(__file__).with_name('verify_current_source.py')), '--repo', str(repo), '--quds', str(quds), '--parser', str(parser), '--output', str(output / 'comparison')]),
        ('quds-guarded-sync-dry-run', [sys.executable, 'tool/sync_office_fidelity.py', '--source', str(quds), '--ref', manifest['source_commit']]),
        ('parser-guarded-sync-dry-run', [sys.executable, 'tool/sync_legacy_doc_parser.py', '--source', str(parser), '--ref', manifest['standalone_sources']['packages/legacy_doc_parser']['commit']]),
        ('quds-sync-controls', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tool', '-p', 'test_sync_office_fidelity.py', '-v']),
        ('parser-sync-controls', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tool', '-p', 'test_sync_legacy_doc_parser.py', '-v']),
        ('inventory-controls', [sys.executable, '-m', 'unittest', 'discover', '-s', 'packages/quds_office_engine/tool/fidelity', '-p', 'test_inventory.py', '-v']),
        ('scripted-oracle-controls', [sys.executable, '-m', 'unittest', 'discover', '-s', 'packages/quds_office_engine/tool/fidelity', '-p', 'test_scripted_oracle.py', '-v']),
    ]
    rows = []
    for name, command in commands:
        start = time.monotonic()
        started_at = datetime.now(timezone.utc).isoformat()
        result = subprocess.run(command, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        (output / (name + '.stdout.log')).write_bytes(result.stdout)
        (output / (name + '.stderr.log')).write_bytes(result.stderr)
        match = re.search(rb'Ran (\d+) tests? in', result.stderr)
        row = {'name': name, 'command': command, 'cwd': str(repo), 'started_at': started_at,
               'elapsed_seconds': time.monotonic() - start, 'returncode': result.returncode,
               'unittest_count': int(match.group(1)) if match else None}
        rows.append(row)
        print(f'{name}: exit {result.returncode}' + (f', {row["unittest_count"]} tests' if match else ''), flush=True)
    summary = {'schema': 1, 'commands': rows, 'command_count': len(rows), 'success': all(r['returncode'] == 0 for r in rows),
               'python_control_tests': sum(r['unittest_count'] or 0 for r in rows),
               'scope': 'Source identity, source synchronization and synthetic inventory/oracle controls; no native execution, Office rendering, produced-output inventory or external schema acceptance.'}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({k:v for k,v in summary.items() if k != 'commands'}, indent=2))
    return not summary['success']


if __name__ == '__main__':
    raise SystemExit(main())

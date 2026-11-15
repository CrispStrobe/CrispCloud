#!/usr/bin/env python3
"""Capture scoped canonical merge development; this is not a clean host gate."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path('/workspace/scratch/aed049b7e8bd/canonical/quds_office_suite')
OUT = Path(__file__).resolve().parent
FILES = [
    'packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart',
    'packages/quds_office_engine/lib/src/sheet/styles/sml_styles.dart',
    'packages/quds_office_engine/test/ods_sheet_reader_test.dart',
    'packages/quds_office_engine/test/sheet_time_number_format_test.dart',
    'packages/quds_office_engine/test/fixtures/fidelity/legacy-sheet-edge.ods',
    'packages/quds_office_engine/CHANGELOG.md',
    'pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
]

def snapshot():
    result = {}
    for relative in FILES:
        path = ROOT / relative
        if path.is_file():
            data = path.read_bytes()
            result[relative] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        else:
            result[relative] = None
    return result

label, mode = sys.argv[1:]
if mode == 'ods':
    cwd = ROOT / 'packages/quds_office_engine'
    command = ['dart', 'test', '--reporter=json', 'test/ods_sheet_reader_test.dart']
elif mode == 'combined':
    cwd = ROOT / 'packages/quds_office_engine'
    command = ['dart', 'test', '--reporter=json', 'test/ods_sheet_reader_test.dart',
               'test/sheet_time_number_format_test.dart', 'test/sheet_formula_test.dart',
               'test/sheet_authored_number_format_test.dart']
elif mode == 'analysis':
    cwd = ROOT
    command = ['dart', 'analyze', '--fatal-infos', '--fatal-warnings',
               *FILES[:4]]
else:
    raise SystemExit('mode must be ods, combined or analysis')
receipt_path = OUT / f'{label}.summary.json'
if receipt_path.exists():
    raise SystemExit(f'Refusing to overwrite {receipt_path}')
before = snapshot()
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
start = time.monotonic()
result = subprocess.run(command, cwd=cwd, capture_output=True)
suffix = 'stdout.log' if mode == 'analysis' else 'jsonl'
(OUT / f'{label}.{suffix}').write_bytes(result.stdout)
(OUT / f'{label}.stderr.log').write_bytes(result.stderr)
after = snapshot()
receipt = {
    'scope': 'canonical uncommitted ddaca merge development, not final clean host qualification',
    'started_utc': started, 'duration_seconds': time.monotonic() - start,
    'cwd': str(cwd), 'command': command, 'exit_code': result.returncode,
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'merge_head': subprocess.check_output(['git', 'rev-parse', 'MERGE_HEAD'], cwd=ROOT, text=True).strip(),
    'source_and_resolution_before': before, 'source_and_resolution_after': after,
    'source_and_resolution_unchanged': before == after,
}
if mode != 'analysis':
    events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith(b'{')]
    done = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
    receipt['test_counts'] = {
        key: sum(e.get('result') == key for e in done)
        for key in ('success', 'failure', 'error')
    }
    receipt['test_counts']['skipped'] = sum(bool(e.get('skipped')) for e in done)
    receipt['done_events'] = [e for e in events if e.get('type') == 'done']
receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: v for k, v in receipt.items() if not k.startswith('source_and_resolution_')}, indent=2))
raise SystemExit(result.returncode)

#!/usr/bin/env python3
"""Record a bounded local acceptance command on the current source checkout."""
import argparse
import datetime
import gzip
import importlib.util
import json
import pathlib
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--phase', required=True)
parser.add_argument('--evidence', type=pathlib.Path, required=True)
parser.add_argument('--scope', choices=['all', 'packages'], default='all')
parser.add_argument('--cwd', type=pathlib.Path, default=pathlib.Path.cwd())
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
if not command:
    parser.error('a command is required')
spec = importlib.util.spec_from_file_location('terminal_acceptance', 'tool/run_terminal_validation.py')
acceptance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acceptance)


def sources():
    result = acceptance.source_hashes()
    if args.scope == 'packages':
        result = {path: digest for path, digest in result.items()
                  if path.startswith('packages/') or path in
                  {'.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}}
    return result


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


args.evidence.mkdir(parents=True, exist_ok=True)
before = sources()
record = {'phase': args.phase, 'command': command,
          'cwd': str(args.cwd.resolve()),
          'head_at_start': acceptance.git('rev-parse', 'HEAD'),
          'started_utc': stamp(), 'source_scope': args.scope,
          'watched_source_count': len(before),
          'github_actions_queried_or_awaited': False}
inventory = args.evidence / f'{args.phase}-source-sha256.json.gz'
inventory.write_bytes(gzip.compress((json.dumps(before, indent=2) + '\n').encode(), mtime=0))
started = time.monotonic()
log_path = args.evidence / f'{args.phase}.log'
with log_path.open('w') as log:
    result = subprocess.run(command, cwd=args.cwd, stdout=log,
                            stderr=subprocess.STDOUT)
after = sources()
record.update(finished_utc=stamp(), seconds=round(time.monotonic() - started, 3),
              exit_code=result.returncode,
              changed_sources=[path for path in sorted(before.keys() | after.keys())
                               if before.get(path) != after.get(path)])
lines = log_path.read_text().splitlines()
final = next((line for line in reversed(lines)
              if 'All tests passed!' in line or 'Some tests failed.' in line), '')
counts = re.search(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?:', final)
if counts:
    record['counts'] = dict(zip(['passed', 'skipped', 'failed'],
                               (int(value or 0) for value in counts.groups())))
record['final_test_line'] = final
(args.evidence / f'{args.phase}.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2), flush=True)
raise SystemExit(result.returncode or bool(record['changed_sources']))

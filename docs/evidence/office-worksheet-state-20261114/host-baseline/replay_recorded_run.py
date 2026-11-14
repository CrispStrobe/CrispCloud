#!/usr/bin/env python3
"""Replay a recorded host command only after its exact inputs match."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys

if len(sys.argv) != 4:
    raise SystemExit('Usage: replay_recorded_run.py INPUTS_JSON CHECKOUT FRESH_BUILD_DIRECTORY')
inputs_path = Path(sys.argv[1]).resolve()
root = Path(sys.argv[2]).resolve()
destination = (root / sys.argv[3]).resolve()
if not destination.is_relative_to(root / 'build') or destination.exists():
    raise SystemExit('Choose a fresh destination inside the checkout build directory.')
inputs = json.loads(inputs_path.read_text())
snapshot = json.loads(gzip.decompress(
    (inputs_path.parent / 'source-snapshot-before.json.gz').read_bytes()))
helper = runpy.run_path(str(root / 'tool/collect_office_host_coverage.py'))
current = helper['source_snapshot'](root)
changed = helper['_changes'](snapshot, current)
if changed:
    raise SystemExit('Recorded inputs do not match: ' + ', '.join(changed[:20]))
if helper['snapshot_digest'](current) != inputs['input_tree_sha256_before']:
    raise SystemExit('Input-tree digest does not match the recorded receipt.')
if hashlib.sha256((root / 'pubspec.yaml').read_bytes()).hexdigest() != inputs['pubspec_committed_sha256']:
    raise SystemExit('The checkout pubspec does not match its committed view.')
command = list(inputs['command'])
command[command.index('--') - 1] = str(destination.relative_to(root))
environment = os.environ.copy()
environment.update(inputs['environment_overrides'])
print('Executing:', command, flush=True)
raise SystemExit(subprocess.run(command, cwd=root, env=environment).returncode)

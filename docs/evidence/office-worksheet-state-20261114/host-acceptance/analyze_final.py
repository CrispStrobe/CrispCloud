#!/usr/bin/env python3
"""Run the agreed three-file Flutter analysis against the tested input set."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess

root = Path(__file__).resolve().parents[2]
out = root / 'build/office-sheet-state-provenance/final-analysis'
out.mkdir(exist_ok=False)
run = root / 'build/office-sheet-state-provenance/native-fill-positive-1'
inputs = json.loads((run / 'inputs.json').read_text())
expected = json.loads(gzip.decompress((run / 'source-snapshot-before.json.gz').read_bytes()))
helper = runpy.run_path(str(root / 'tool/collect_office_host_coverage.py'))
before = helper['source_snapshot'](root)
assert before == expected
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
assert head == 'ccba883b3a042582d3fd80f75772c20bff9e2c4b'
files = ['lib/widgets/office_editor_ribbon.dart',
         'test/widget/office_sheet_state_workflow_test.dart',
         'test/widget/office_native_workflow_test.dart']
command = ['/workspace/scratch/f035141943c7/toolchain/flutter/bin/flutter',
           'analyze', '--no-pub', *files]
environment = os.environ.copy()
environment.update(inputs['environment_overrides'])
started = datetime.now(timezone.utc).isoformat()
with (out / 'analysis.log').open('w') as log:
    result = subprocess.run(command, cwd=root, env=environment,
                            stdout=log, stderr=subprocess.STDOUT)
after = helper['source_snapshot'](root)
receipt = {'head': head, 'started_at': started,
           'completed_at': datetime.now(timezone.utc).isoformat(),
           'command': command, 'returncode': result.returncode,
           'input_files': len(before), 'input_tree_sha256': helper['snapshot_digest'](before),
           'changed_inputs': helper['_changes'](before, after),
           'analyzed_file_sha256': {name: before[name] for name in files},
           'pubspec_restored': hashlib.sha256((root / 'pubspec.yaml').read_bytes()).hexdigest()
                                == inputs['pubspec_committed_sha256'],
           'log_sha256': hashlib.sha256((out / 'analysis.log').read_bytes()).hexdigest()}
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print((out / 'analysis.log').read_text(), flush=True)
print(json.dumps(receipt, indent=2), flush=True)
raise SystemExit(result.returncode or bool(receipt['changed_inputs']))

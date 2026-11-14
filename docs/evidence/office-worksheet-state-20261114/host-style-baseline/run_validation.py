#!/usr/bin/env python3
"""Capture the worksheet, ribbon-style, or native-fill focused host cases."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ATTEMPT = sys.argv[1]
MODE = sys.argv[2] if len(sys.argv) > 2 else 'sheet'
if MODE not in ('sheet', 'style', 'fill'):
    raise SystemExit('Expected mode sheet, style or fill')
OUT = ROOT / 'build/office-sheet-state-provenance' / ATTEMPT
OUT.mkdir(parents=True, exist_ok=False)
COVERAGE = Path('build') / ({
    'sheet': 'office-sheet-state-coverage-',
    'style': 'office-style-history-coverage-',
    'fill': 'office-native-fill-coverage-',
}[MODE] + ATTEMPT)
HELPER = runpy.run_path(str(ROOT / 'tool/collect_office_host_coverage.py'))
PREVIOUS = json.loads((ROOT / 'build/office-fill-host-provenance/attempt-3/inputs.json').read_text())
OVERRIDES = PREVIOUS['environment_overrides']
ENV = os.environ.copy()
ENV.update(OVERRIDES)


def stamp():
    return datetime.now(timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


before = HELPER['source_snapshot'](ROOT)
raw_snapshot = (json.dumps(before, indent=2) + '\n').encode()
(OUT / 'source-snapshot-before.json.gz').write_bytes(gzip.compress(raw_snapshot, mtime=0))
committed = (ROOT / 'pubspec.yaml').read_bytes()
HOOK = runpy.run_path(str(ROOT / 'tool/with_ci_system_sqlite.py'))['HOOK']
collected = committed.rstrip(b'\r\n') + b'\n' + HOOK
(OUT / 'pubspec-committed.yaml').write_bytes(committed)
(OUT / 'pubspec-expected-collected.yaml').write_bytes(collected)

generated = {}
for name in ['pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
    path = ROOT / name
    if path.is_file():
        content = path.read_bytes()
        relative = 'generated-inputs/' + name + '.gz'
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(gzip.compress(content, mtime=0))
        generated[name] = {'sha256': sha(content), 'snapshot': relative, 'bytes': len(content)}
write('generated-inputs.json', generated)

changed = set(git('diff', '--name-only', 'HEAD').splitlines())
changed.update(git('ls-files', '--others', '--exclude-standard').splitlines())
snapshots = {}
for name in sorted(changed):
    if name in before or name == '.github/workflows/office-fidelity.yml':
        content = (ROOT / name).read_bytes()
        target = OUT / 'changed-inputs' / (name + '.gz')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(gzip.compress(content, mtime=0))
        snapshots[name] = {'sha256': sha(content), 'snapshot': str(target.relative_to(OUT)),
                           'collector_input': name in before}

test_file = ('test/widget/office_sheet_state_workflow_test.dart' if MODE == 'sheet'
             else 'test/widget/office_native_workflow_test.dart')
test_filter = ([] if MODE == 'sheet' else [
    '--plain-name', ('ribbon style history' if MODE == 'style' else
                     'native fills survive unrelated formatting through three host uploads')])
command = ['python3', 'tool/with_ci_system_sqlite.py', 'python3',
           'tool/collect_office_host_coverage.py', '--flutter',
           '/workspace/scratch/f035141943c7/toolchain/flutter/bin/flutter',
           str(COVERAGE), '--', '--concurrency=1', '--reporter=expanded',
           *test_filter, test_file]
inputs = {'attempt': ATTEMPT, 'captured_at': stamp(), 'head': git('rev-parse', 'HEAD'),
          'git_status': git('status', '--short'), 'input_files': len(before),
          'input_tree_sha256_before': HELPER['snapshot_digest'](before),
          'source_snapshot_sha256': sha(raw_snapshot),
          'pubspec_committed_sha256': sha(committed),
          'pubspec_expected_collected_sha256': sha(collected),
          'command': command, 'environment_overrides': OVERRIDES,
          'changed_input_snapshots': snapshots,
          'mode': MODE, 'test_sha256': {test_file: before[test_file]},
          'scope': ('Only five worksheet state/history host cases; independent ZIP/XML assertions and actual toolbar uploads. Worksheet navigation alone uses public setActiveSheet because this host has no sheet selector.'
                    if MODE == 'sheet' else
                    'Only two actual-ribbon style history cases with independent native fill/font/style provenance and worksheet ownership assertions.'
                    if MODE == 'style' else
                    'Only the existing native-fill overlap regression, comparing three actual host uploads against independently authored native fill definitions.')}
write('inputs.json', inputs)
print(f'Captured {len(before)} input hashes at {OUT}', flush=True)
print('Running: ' + ' '.join(command), flush=True)
started = stamp()
with (OUT / 'test.log').open('w') as log:
    result = subprocess.run(command, cwd=ROOT, env=ENV, stdout=log, stderr=subprocess.STDOUT)
after = HELPER['source_snapshot'](ROOT)
status = {'started_at': started, 'completed_at': stamp(), 'returncode': result.returncode,
          'pubspec_restored': (ROOT / 'pubspec.yaml').read_bytes() == committed,
          'changed_inputs': HELPER['_changes'](before, after),
          'input_tree_sha256_after': HELPER['snapshot_digest'](after)}
artifact_root = ROOT / {
    'sheet': 'build/office-sheet-state-acceptance',
    'style': 'build/office-style-history-acceptance',
    'fill': 'build/office-fill-host-acceptance',
}[MODE]
if artifact_root.is_dir():
    artifacts = {}
    for artifact in sorted(artifact_root.glob('*.xlsx')):
        target = OUT / 'artifacts' / artifact.name
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(artifact, target)
        artifacts[artifact.name] = {'sha256': sha(artifact.read_bytes()), 'bytes': artifact.stat().st_size}
    write('artifact-manifest.json', artifacts)
    status['artifacts'] = len(artifacts)
write('run-status.json', status)
print(json.dumps(status, indent=2), flush=True)
print((OUT / 'test.log').read_text()[-14000:], flush=True)

if result.returncode == 0:
    verification = ['python3', 'tool/with_ci_system_sqlite.py', 'python3',
                    'tool/office_host_coverage.py', str(COVERAGE / 'lcov.info'),
                    '--output', str(COVERAGE / 'coverage-report.json'), '--require-receipt']
    with (OUT / 'coverage-verification.log').open('w') as log:
        verified = subprocess.run(verification, cwd=ROOT, env=ENV, stdout=log, stderr=subprocess.STDOUT)
    final = HELPER['source_snapshot'](ROOT)
    verified_status = {'command': verification, 'returncode': verified.returncode,
                       'pubspec_restored': (ROOT / 'pubspec.yaml').read_bytes() == committed,
                       'changed_inputs': HELPER['_changes'](before, final)}
    write('coverage-verification-status.json', verified_status)
    print(json.dumps(verified_status, indent=2), flush=True)
    if verified.returncode:
        raise SystemExit(verified.returncode)
raise SystemExit(result.returncode)

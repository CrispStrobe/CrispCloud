#!/usr/bin/env python3
"""Run one proven acceptance gate against an exact clean frozen Git checkpoint."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--repo', type=Path, required=True)
p.add_argument('--commit', required=True)
p.add_argument('--gate', choices=('portable', 'schema', 'native'), required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--receipts', type=Path, required=True)
a = p.parse_args()
workspace = Path('/workspace/scratch/c1ca2a1344e9')
dart = str(workspace / 'toolchains/dart-3.13.7/dart-sdk/bin/dart')
dotnet = str(workspace / 'toolchains/dotnet-8.0.428/dotnet')
office = '/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/override/soffice'
repo = a.repo.resolve()


def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args]).decode().strip()


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source():
    paths = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z']).decode().strip('\0').split('\0')
    paths += ['pubspec.lock', '.dart_tool/package_config.json']
    return {'commit': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}'),
            'status': git('status', '--porcelain', '--untracked-files=all'),
            'files': {name: sha(repo / name) for name in sorted(set(paths))}}


before = source()
if before['commit'] != a.commit or before['status']:
    raise ValueError('Acceptance requires the requested exact clean checkpoint')
if a.out.exists():
    raise ValueError('Acceptance output must be new')
a.receipts.mkdir(parents=True, exist_ok=True)
receipt_path = a.receipts / (a.gate + '.launch.json')
log_path = a.receipts / (a.gate + '.console.log')
if receipt_path.exists() or log_path.exists():
    raise ValueError('Refusing to overwrite prior launch evidence')
commands = {
    'portable': [sys.executable, 'doc/evidence/continuation-0c3e596/run_parser_gate.py',
                 '--repo', str(repo), '--out', str(a.out), '--dart', dart],
    'schema': [sys.executable, 'tool/fidelity/schema.py', '--dart', dart, '--dotnet', dotnet,
               '--cached-nuget', str(workspace / 'toolchains/nuget'), '--out', str(a.out)],
    'native': [sys.executable, 'tool/fidelity/run.py', '--office', office, '--dart', dart,
               '--output', str(a.out), '--dpi', '72', '--raster-storage', 'gzip', '--roundtrip-cycles', '3'],
}
command = commands[a.gate]
overrides = {'TMPDIR': str(workspace / 'tmp'), 'DART_SUPPRESS_ANALYTICS': 'true',
             'PUB_CACHE': str(workspace / 'toolchains/pub-cache')}
Path(overrides['TMPDIR']).mkdir(exist_ok=True)
record = {'gate': a.gate, 'status': 'running', 'command': command, 'cwd': str(repo),
          'environmentOverrides': overrides, 'startedAtUnix': time.time(), 'sourceBefore': before,
          'launcherSha256': sha(Path(__file__)), 'driverSourceSha256': sha(repo / command[1]),
          'consoleLog': log_path.name}


def save():
    temporary = receipt_path.with_suffix('.tmp')
    temporary.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    temporary.replace(receipt_path)


save()
print(json.dumps({'gate': a.gate, 'commit': a.commit, 'started': True, 'output': str(a.out)}), flush=True)
with log_path.open('xb') as log:
    completed = subprocess.run(command, cwd=repo, env=os.environ | overrides,
                               stdout=log, stderr=subprocess.STDOUT)
after = source()
record.update(status='complete', exitCode=completed.returncode, completedAtUnix=time.time(),
              sourceAfter=after, inputsUnchanged=before == after, consoleSha256=sha(log_path))
record['success'] = completed.returncode == 0 and before == after
save()
print(json.dumps({'gate': a.gate, 'commit': a.commit, 'exitCode': completed.returncode,
                  'inputsUnchanged': record['inputsUnchanged'], 'success': record['success']}), flush=True)
sys.exit(0 if record['success'] else 1)

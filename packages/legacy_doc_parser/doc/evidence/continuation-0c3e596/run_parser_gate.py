#!/usr/bin/env python3
"""Retain a fresh portable gate and before/after input identities."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

p = argparse.ArgumentParser()
p.add_argument('--repo', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--dart', required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=False)


def git(*args):
    return subprocess.check_output(['git', '-C', str(a.repo), *args], text=True).strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    paths = git('ls-files').splitlines()
    paths += ['pubspec.lock', '.dart_tool/package_config.json']
    return {f: sha(a.repo / f) for f in sorted(set(paths)) if (a.repo / f).is_file()}


receipt = {'commit': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}'),
           'dirtyBefore': git('status', '--porcelain', '--untracked-files=all'),
           'python': sys.version, 'startedAtUnix': time.time(), 'stages': [],
           'inputsBefore': inputs()}
if receipt['dirtyBefore']:
    raise ValueError('Portable gate requires a clean source checkpoint')
commands = [
    ('dart-version', [a.dart, '--version']),
    ('format', [a.dart, 'format', '--output=none', '--set-exit-if-changed', '.']),
    ('analyze', [a.dart, 'analyze', '--fatal-infos']),
    ('dart-tests', [a.dart, 'test', '--reporter=expanded']),
    ('corpus-integrity', ['python3', 'tool/fidelity/oracle.py']),
    ('python-tests', ['python3', '-m', 'unittest', 'discover', '-s', 'tool/fidelity', '-p', 'test_*.py']),
    ('javascript', ['python3', 'tool/verify_web.py', '--dart', a.dart]),
    ('publish-dry-run', [a.dart, 'pub', 'publish', '--dry-run']),
]


def save():
    (a.out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


save()
for name, command in commands:
    started = time.time()
    log = a.out / (name + '.log')
    with log.open('wb') as stream:
        result = subprocess.run(command, cwd=a.repo, env=os.environ,
                                stdout=stream, stderr=subprocess.STDOUT)
    stage = {'name': name, 'command': command, 'exitCode': result.returncode,
             'elapsedSeconds': time.time() - started, 'log': log.name,
             'logSha256': sha(log)}
    receipt['stages'].append(stage)
    save()
    print(json.dumps(stage), flush=True)
    if result.returncode:
        break
receipt['inputsAfter'] = inputs()
receipt['inputsUnchanged'] = receipt['inputsAfter'] == receipt['inputsBefore']
receipt['dirtyAfter'] = git('status', '--porcelain', '--untracked-files=all')
receipt['completedAtUnix'] = time.time()
receipt['success'] = (len(receipt['stages']) == len(commands) and
                      all(s['exitCode'] == 0 for s in receipt['stages']) and
                      receipt['inputsUnchanged'] and not receipt['dirtyAfter'])
save()
sys.exit(0 if receipt['success'] else 1)

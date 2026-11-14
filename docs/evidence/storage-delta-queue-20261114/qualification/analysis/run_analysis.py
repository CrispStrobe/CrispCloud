#!/usr/bin/env python3
"""Read-only strict analysis receipt for the frozen queued-delta increment."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone

REPO = Path('/workspace/scratch/209f165653d7/CrispCloud')
OUT = Path(__file__).resolve().parent
BASE = '781458d765100ae3556906ff8ca923e70c956afa'
HEAD = '832d3a26e004cf5268928d093841d3df61a3c5ea'
TREE = '5b185bf4c52650cb64c0895f0c7c349f800c8808'
LAUNCHER = REPO.parent / 'toolchain/run'
DART = REPO.parent / 'toolchain/flutter/bin/cache/dart-sdk/bin/dart'


def now():
    return datetime.now(timezone.utc).isoformat()


def encode(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def write(name, value):
    (OUT / name).write_bytes(encode(value))


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def state():
    return {
        'head': git('rev-parse', 'HEAD').decode().strip(),
        'tree': git('rev-parse', 'HEAD^{tree}').decode().strip(),
        'status': git('status', '--porcelain=v1', '--untracked-files=all').decode(),
    }


def snapshot():
    names = {os.fsdecode(p) for p in git('ls-files', '-z').split(b'\0') if p}
    names = {p for p in names if not p.startswith('docs/evidence/')}
    names.update(['.dart_tool/package_config.json', '.dart_tool/package_graph.json'])
    entries = {}
    for name in sorted(names):
        path = REPO / name
        if path.is_symlink():
            data = os.fsencode(os.readlink(path))
            entries[name] = {'kind': 'symlink', 'size': len(data),
                             'sha256': hashlib.sha256(data).hexdigest()}
        elif path.is_file():
            entries[name] = {'kind': 'file', 'size': path.stat().st_size,
                             'sha256': digest(path)}
        else:
            entries[name] = {'kind': 'missing_or_nonfile'}
    return {'at': now(), 'count': len(entries), 'entries': entries,
            'entries_sha256': hashlib.sha256(encode(entries)).hexdigest(),
            'selector': 'all tracked except docs/evidence/**, plus root package_config.json and package_graph.json'}


before_git = state()
assert before_git == {'head': HEAD, 'tree': TREE, 'status': ''}, before_git
changed = git('diff', '--name-only', '--diff-filter=ACMRT', '-z', BASE, HEAD)
files = sorted(os.fsdecode(p) for p in changed.split(b'\0')
               if p and os.fsdecode(p).endswith('.dart')
               and set(Path(os.fsdecode(p)).parts) & {'lib', 'test'})
assert files and all((REPO / name).is_file() for name in files)
(OUT / 'files.txt').write_text('\n'.join(files) + '\n')
command = [str(LAUNCHER), str(DART), 'analyze', '--fatal-infos', '--fatal-warnings', *files]
write('command.json', {'argv': command, 'cwd': str(REPO), 'shell_display': shlex.join(command)})
version = subprocess.run([str(LAUNCHER), str(DART), '--version'], cwd=REPO,
                         capture_output=True, text=True, check=True)
flutter_version_file = DART.parents[2] / 'flutter.version.json'
versions = {'dart': (version.stdout + version.stderr).strip(),
            'dart_version_command': [str(LAUNCHER), str(DART), '--version'],
            'python': sys.version, 'platform': platform.platform(),
            'flutter_cache_version_file': str(flutter_version_file),
            'flutter_cache_version': json.loads(flutter_version_file.read_text())}
write('versions.json', versions)
tools = {'launcher': LAUNCHER, 'dart_binary': DART, 'runner': Path(__file__).resolve()}
before_tools = {name: {'path': str(path), 'sha256': digest(path)} for name, path in tools.items()}
before = snapshot()
(OUT / 'inputs-before.json.gz').write_bytes(gzip.compress(encode(before), mtime=0))
metadata = {'repo': str(REPO), 'base_commit': BASE, 'files': files, 'file_count': len(files),
            'command': command, 'before_git': before_git, 'before_tools': before_tools,
            'started_at': now(), 'versions': versions}
write('metadata.json', metadata)
started = time.monotonic()
with (OUT / 'stdout.log').open('wb') as stdout, (OUT / 'stderr.log').open('wb') as stderr:
    result = subprocess.run(command, cwd=REPO, stdout=stdout, stderr=stderr, check=False)
metadata.update({'finished_at': now(), 'elapsed_seconds': time.monotonic() - started,
                 'returncode': result.returncode})
after_git, after = state(), snapshot()
(OUT / 'inputs-after.json.gz').write_bytes(gzip.compress(encode(after), mtime=0))
after_tools = {name: {'path': str(path), 'sha256': digest(path)} for name, path in tools.items()}
old, new = before['entries'], after['entries']
changes = {'added': sorted(new.keys() - old.keys()), 'removed': sorted(old.keys() - new.keys()),
           'changed': sorted(p for p in old.keys() & new.keys() if old[p] != new[p])}
stable = not any(changes.values()) and before_git == after_git and before_tools == after_tools
metadata.update({'after_git': after_git, 'after_tools': after_tools, 'input_changes': changes,
                 'inputs_and_commit_stable': stable, 'input_count': before['count'],
                 'before_entries_sha256': before['entries_sha256'],
                 'after_entries_sha256': after['entries_sha256'],
                 'qualification_success': result.returncode == 0 and stable,
                 'input_stability_note': 'Before/after equality does not prove absence of transient writes.',
                 'scope': 'Strict static analysis of every changed Dart file under lib/test since base; no tests, package resolution, formatting edits, or runtime qualification.'})
write('metadata.json', metadata)
write('artifacts-sha256.json', {p.name: {'sha256': digest(p), 'size': p.stat().st_size}
                               for p in sorted(OUT.iterdir())
                               if p.is_file() and p.name != 'artifacts-sha256.json'})
print(json.dumps({k: metadata[k] for k in ('qualification_success', 'returncode', 'file_count',
                                         'input_count', 'inputs_and_commit_stable')}, indent=2))
sys.exit(0 if metadata['qualification_success'] else 1)

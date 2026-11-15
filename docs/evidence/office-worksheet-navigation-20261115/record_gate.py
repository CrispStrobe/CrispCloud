#!/usr/bin/env python3
"""Record one non-overwriting source-bound continuation validation command."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def stamp():
    return datetime.now(timezone.utc).isoformat()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def snapshot(root):
    tracked = git(root, 'ls-files', '-z').decode().rstrip('\0').split('\0')
    others = git(root, 'ls-files', '--others', '--exclude-standard', '-z').decode().rstrip('\0').split('\0')
    selected = set()
    for name in [*tracked, *others]:
        if not name or name.startswith(('docs/', 'tmp/', 'build/', 'coverage/')):
            continue
        if '/doc/evidence/' in name or '/build/' in name:
            continue
        if (root / name).is_file():
            selected.add(name)
    for folder in ['', 'packages/quds_office_engine/', 'packages/quds_office_editor/']:
        for name in ['pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
            if (root / (folder + name)).is_file():
                selected.add(folder + name)
    return {name: digest((root / name).read_bytes()) for name in sorted(selected)}


def write_json(path, data):
    path.write_text(json.dumps(data, sort_keys=True, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--cwd', default='.')
    parser.add_argument('--artifacts', action='append', default=[])
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('a command is required')
    root = args.repo.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = git(root, 'rev-parse', 'HEAD').decode().strip()
    before = snapshot(root)
    raw = (json.dumps(before, sort_keys=True, indent=2) + '\n').encode()
    (output / 'input-sha256.json.gz').write_bytes(gzip.compress(raw, mtime=0))
    changed = set(git(root, 'diff', '--name-only', 'HEAD').decode().splitlines())
    changed.update(git(root, 'ls-files', '--others', '--exclude-standard').decode().splitlines())
    payloads = {}
    for name in before:
        if name in changed or name.endswith(('pubspec.lock', 'package_config.json', 'package_graph.json')):
            content = (root / name).read_bytes()
            target = output / 'input-payloads' / (name + '.gz')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(gzip.compress(content, mtime=0))
            payloads[name] = {'sha256': digest(content), 'snapshot': str(target.relative_to(output))}
    runtime = {}
    flutter = os.environ.get('FLUTTER_ROOT')
    if flutter:
        sdk = Path(flutter)
        for name in ['bin/cache/dart-sdk/bin/dart', 'bin/cache/flutter_tools.snapshot',
                     'bin/cache/artifacts/engine/linux-x64/flutter_tester', 'bin/internal/engine.version']:
            path = sdk / name
            if path.is_file():
                runtime[name] = digest(path.read_bytes())
        runtime['flutter_revision'] = git(sdk, 'rev-parse', 'HEAD').decode().strip()
    receipt = {
        'version': 1, 'label': args.label, 'source_commit': source,
        'source_tree': git(root, 'rev-parse', 'HEAD^{tree}').decode().strip(),
        'git_status_before': git(root, 'status', '--porcelain').decode(),
        'working_directory': args.cwd, 'command': command, 'started_at': stamp(),
        'inputs': len(before), 'input_manifest_sha256': digest(raw),
        'input_payloads': payloads, 'runtime': runtime,
        'environment_overrides': {name: os.environ[name] for name in (
            'FLUTTER_ROOT', 'PUB_CACHE', 'TMPDIR', 'CI', 'BOT',
            'FLUTTER_SUPPRESS_ANALYTICS', 'DART_SUPPRESS_ANALYTICS',
            'LD_LIBRARY_PATH', 'CARGO_HOME', 'RUSTUP_HOME') if name in os.environ},
        'limits': 'External dependency-cache payloads are identified by resolution, not archived; this is not a hermetic execution claim.',
        'completed': False,
    }
    write_json(output / 'receipt.json', receipt)
    log_path = output / 'command.log'
    with log_path.open('wb') as log:
        result = subprocess.run(command, cwd=root / args.cwd, stdout=log, stderr=subprocess.STDOUT)
    after = snapshot(root)
    changed_inputs = [name for name in sorted(set(before) | set(after)) if before.get(name) != after.get(name)]
    log = log_path.read_bytes()
    (output / 'command.log.gz').write_bytes(gzip.compress(log, mtime=0))
    log_path.unlink()
    artifacts = {}
    for folder in args.artifacts:
        for path in sorted((root / folder).glob('*.xlsx')):
            content = path.read_bytes()
            target = output / 'artifacts' / path.name
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(content)
            artifacts[path.name] = {'source_path': str(path.relative_to(root)),
                                    'sha256': digest(content), 'bytes': len(content)}
    if artifacts:
        write_json(output / 'artifact-sha256.json', artifacts)
    receipt.update({'completed': True, 'completed_at': stamp(), 'exit_code': result.returncode,
                    'changed_inputs': changed_inputs, 'log_sha256': digest(log), 'artifacts': artifacts})
    write_json(output / 'receipt.json', receipt)
    print(json.dumps({'output': str(output), 'exit_code': result.returncode, 'inputs': len(before),
                      'changed_inputs': changed_inputs, 'artifacts': len(artifacts)}, indent=2))
    print(log.decode(errors='replace')[-6000:])
    return result.returncode or (2 if changed_inputs else 0)


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Collect host Flutter LCOV with an exact-input, successful-run receipt.

Resolve dependencies first and choose a NEW destination, then run:

    python3 tool/collect_office_host_coverage.py build/host-run-1 -- test/office_footnote_test.dart
    python3 tool/office_host_coverage.py build/host-run-1/lcov.info --require-receipt

The collector owns --no-pub, --coverage and --coverage-path. It never clears or
reuses a directory and writes a receipt only after successful, stable collection.
This binds coverage to the recorded sources, tests, assets, config, vendor files and
runtime. It does not prove branch correctness, fidelity, or a hermetic build.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LCOV = 'lcov.info'
RECEIPT = 'collection-receipt.json'
SCHEMA_VERSION = 1
IGNORED = {'__pycache__', '.dart_tool', 'build', 'failures'}
CONFIG = ('pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml', '.fvmrc',
          'dart_test.yaml', 'analysis_options.yaml', 'l10n.yaml',
          '.dart_tool/package_config.json', '.dart_tool/package_graph.json')
VENDORS = ('quds_office_engine', 'quds_office_editor', 'legacy_doc_parser', 'quds_reports')


class CollectionError(ValueError):
    """Collection provenance is incomplete or no longer matches its inputs."""


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def _no_symlinks(path, boundary=None):
    for current in (path, *path.parents):
        if current.is_symlink() and not (os.name != 'nt' and current.parent == Path(current.anchor)):
            raise CollectionError(f'Symlink in coverage path: {current}')
        if current == boundary:
            break


def _files(directory, ignored=IGNORED):
    _no_symlinks(directory)
    if not directory.exists():
        return
    for parent, directories, names in os.walk(directory, followlinks=False):
        directories[:] = sorted(name for name in directories if name not in ignored)
        for name in directories + sorted(names):
            path = Path(parent) / name
            if path.is_symlink():
                raise CollectionError(f'Symlink in collection inputs: {path}')
        for name in sorted(names):
            path = Path(parent) / name
            if not path.is_file():
                raise CollectionError(f'Not a regular collection input: {path}')
            yield path


def snapshot_digest(snapshot):
    return hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()


def _safe_vendor_path(name):
    if not isinstance(name, str):
        raise CollectionError('Non-string vendor path')
    path = PurePosixPath(name)
    if (path.is_absolute() or '..' in path.parts or '\\' in name
            or str(path) != name or len(path.parts) < 3
            or path.parts[0] not in ('packages', 'tool')):
        raise CollectionError(f'Invalid vendor path: {name}')
    return path


def source_snapshot(root=ROOT):
    """Snapshot conservative host inputs and verify the actual pinned vendor.

    All host lib/test/asset files cover imports, fixtures and fonts used by Office.
    The Office tool/config inputs and Quds lib/test/tool/font inputs are bound as
    well. Other installed dependency contents and system libraries are not claimed
    to be hermetic; dependency resolutions and the Flutter runtime are retained.
    """
    root = root.resolve()
    files = {}

    def add(path):
        _no_symlinks(path, root)
        if path.is_file():
            files[path.relative_to(root).as_posix()] = digest(path)

    for required in ('pubspec.yaml', 'pubspec.lock', 'tool/office_fidelity_manifest.json'):
        _no_symlinks(root / required, root)
        if not (root / required).is_file():
            raise CollectionError(f'Missing resolved collection input: {required}')
    for folder in ('lib', 'test', 'assets'):
        for path in _files(root / folder, ignored=set() if folder == 'assets' else IGNORED):
            add(path)
    for path in sorted((root / 'tool').glob('*office*')):
        _no_symlinks(path, root)
        if path.is_dir():
            ignored = IGNORED | {'bin', 'obj'} if path.name == 'office-validation' else IGNORED
            for child in _files(path, ignored):
                add(child)
        else:
            add(path)
    for name in ('with_ci_system_sqlite.py', 'test_with_ci_system_sqlite.py',
                 'sync_legacy_doc_parser.py', 'test_sync_legacy_doc_parser.py'):
        add(root / 'tool' / name)
    for name in CONFIG:
        add(root / name)
    for vendor in VENDORS:
        base = root / 'packages' / vendor
        for folder in ('lib', 'test', 'tool', 'fonts', 'example/fonts'):
            for path in _files(base / folder):
                add(path)
        for path in _files(base / 'example'):
            if path.suffix == '.dart':
                add(path)
        for name in CONFIG:
            add(base / name)
    manifest = json.loads((root / 'tool/office_fidelity_manifest.json').read_text())
    expected = manifest.get('files') if isinstance(manifest, dict) else None
    if not isinstance(expected, dict) or not expected:
        raise CollectionError('Missing pinned vendor file inventory')
    for name, expected_hash in sorted(expected.items()):
        _safe_vendor_path(name)
        path = root / name
        add(path)
        if (not isinstance(expected_hash, str)
                or not re.fullmatch(r'[0-9a-f]{64}', expected_hash)
                or files.get(name) != expected_hash):
            raise CollectionError(f'Vendor drift: {name}')
    if not any(re.fullmatch(r'lib/(services|widgets)/office_[^/]+\.dart', name)
               for name in files):
        raise CollectionError('No Office host Dart sources found')
    return dict(sorted(files.items()))


def _changes(before, after):
    return sorted(name for name in set(before) | set(after)
                  if before.get(name) != after.get(name))


def _timestamp():
    return datetime.now(timezone.utc).isoformat()


def _destination(directory, root):
    directory = Path(directory).absolute()
    if '..' in directory.parts:
        raise CollectionError('Coverage destination must not contain parent traversals')
    _no_symlinks(directory)
    directory = directory.resolve()
    for folder in ('lib', 'test', 'tool', 'packages', 'assets', '.dart_tool'):
        if directory.is_relative_to(root / folder):
            raise CollectionError('Coverage destination must be outside source/input directories')
    return directory


def collect(directory, root=ROOT, flutter='flutter', test_arguments=(), *, runner=subprocess.run):
    root = root.resolve()
    directory = _destination(directory, root)
    if directory.exists():
        raise CollectionError(f'Coverage directory already exists; choose a fresh destination: {directory}')
    arguments = list(test_arguments)
    reserved = {'--coverage', '--no-coverage', '--coverage-path', '--merge-coverage',
                '--no-merge-coverage', '--pub'}
    if any(argument.split('=', 1)[0] in reserved for argument in arguments):
        raise CollectionError('The collector owns coverage output and disables pub resolution')
    executable = shutil.which(flutter)
    if executable is None:
        raise CollectionError(f'Flutter executable not found: {flutter}')
    executable = Path(executable).resolve()
    version = subprocess.run([str(executable), '--version', '--machine'],
                             check=True, capture_output=True, text=True)
    runtime = {'executable': str(executable), 'sha256': digest(executable),
               'version': (version.stdout + version.stderr).strip()}
    if not runtime['version']:
        raise CollectionError('Flutter reported no runtime version')
    before = source_snapshot(root)
    command = [str(executable), 'test', '--no-pub', '--coverage',
               '--coverage-path=' + str(directory / LCOV), *arguments]
    directory.parent.mkdir(parents=True, exist_ok=True)
    try:
        directory.mkdir()  # Exclusive ownership excludes concurrent collectors.
    except FileExistsError as error:
        raise CollectionError(f'Coverage directory already exists: {directory}') from error
    started = _timestamp()
    result = runner(command, cwd=root, check=False)
    if result.returncode:
        raise CollectionError(f'Flutter test failed with exit code {result.returncode}; no receipt issued')
    changed = _changes(before, source_snapshot(root))
    if changed:
        raise CollectionError('Collection inputs changed during tests: ' + ', '.join(changed[:10]))
    if digest(executable) != runtime['sha256']:
        raise CollectionError('Flutter executable changed during collection')
    lcov = directory / LCOV
    _no_symlinks(lcov)
    if not lcov.is_file():
        raise CollectionError('No Flutter LCOV output was produced')
    # Validate genuine scoped coverage before sealing a successful receipt.
    from office_host_coverage import report_coverage
    lcov_bytes = lcov.read_bytes()
    coverage_sha256 = hashlib.sha256(lcov_bytes).hexdigest()
    report_coverage(lcov_bytes.decode('utf-8'), root)
    changed = _changes(before, source_snapshot(root))
    if changed:
        raise CollectionError('Collection inputs changed during validation: ' + ', '.join(changed[:10]))
    _no_symlinks(lcov)
    if not lcov.is_file() or digest(lcov) != coverage_sha256:
        raise CollectionError('LCOV changed during collection validation')
    if digest(executable) != runtime['sha256']:
        raise CollectionError('Flutter executable changed during collection validation')
    receipt = {'schema_version': SCHEMA_VERSION, 'status': 'complete',
               'returncode': result.returncode, 'started_at': started,
               'completed_at': _timestamp(), 'host_root': str(root),
               'coverage_directory': str(directory), 'command': command,
               'runtime': runtime, 'input_sha256': before,
               'input_tree_sha256': snapshot_digest(before),
               'coverage_sha256': {LCOV: coverage_sha256}}
    temporary = directory / (RECEIPT + '.tmp')
    with temporary.open('x', encoding='utf-8') as output:
        output.write(json.dumps(receipt, indent=2) + '\n')
    temporary.replace(directory / RECEIPT)
    return receipt


def verify_receipt(lcov, root=ROOT):
    lcov = Path(lcov).absolute()
    _no_symlinks(lcov)
    path = lcov.parent / RECEIPT
    _no_symlinks(path)
    if not path.is_file():
        raise CollectionError('Missing collection receipt; run collect_office_host_coverage.py into a fresh directory')
    data = json.loads(path.read_text(encoding='utf-8'))
    if (not isinstance(data, dict) or type(data.get('schema_version')) is not int
            or data.get('schema_version') != SCHEMA_VERSION
            or data.get('status') != 'complete' or type(data.get('returncode')) is not int
            or data.get('returncode') != 0):
        raise CollectionError('Host coverage collection did not complete successfully')
    recorded = data.get('input_sha256')
    if (not isinstance(recorded, dict) or not recorded
            or any(not isinstance(name, str) or not isinstance(value, str)
                   or not re.fullmatch(r'[0-9a-f]{64}', value)
                   for name, value in recorded.items())
            or data.get('input_tree_sha256') != snapshot_digest(recorded)):
        raise CollectionError('Invalid input snapshot in collection receipt')
    changed = _changes(recorded, source_snapshot(root))
    if changed:
        raise CollectionError('Coverage inputs no longer match collected sources: ' + ', '.join(changed[:10]))
    if (lcov.name != LCOV or not lcov.is_file()
            or data.get('coverage_sha256') != {LCOV: digest(lcov)}):
        raise CollectionError('LCOV no longer matches successful collection')
    runtime, command = data.get('runtime'), data.get('command')
    destination = data.get('coverage_directory')
    if (not isinstance(runtime, dict) or not isinstance(runtime.get('version'), str)
            or not runtime['version'] or not isinstance(runtime.get('sha256'), str)
            or not re.fullmatch(r'[0-9a-f]{64}', runtime['sha256'])
            or not isinstance(command, list) or len(command) < 5
            or any(not isinstance(argument, str) for argument in command)
            or not isinstance(destination, str)
            or command[:5] != [runtime.get('executable'), 'test', '--no-pub', '--coverage',
                              '--coverage-path=' + str(Path(destination) / LCOV)]
            or any(argument.split('=', 1)[0] in
                   {'--coverage', '--no-coverage', '--coverage-path', '--merge-coverage',
                    '--no-merge-coverage', '--pub'} for argument in command[5:])):
        raise CollectionError('Invalid Flutter command/runtime provenance in collection receipt')
    return {'verified': True, 'receipt_sha256': digest(path),
            'input_tree_sha256': data['input_tree_sha256'],
            'input_files': len(recorded), 'coverage_sha256': data['coverage_sha256'],
            'command': command, 'runtime': runtime,
            'started_at': data.get('started_at'), 'completed_at': data.get('completed_at'),
            'scope': 'Host lib/tests/assets, Office tools/config/resolutions and actual Quds inputs; successful source/output identity, not branch correctness or a hermetic environment.'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('directory', type=Path)
    parser.add_argument('test_arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    extra = args.test_arguments[1:] if args.test_arguments[:1] == ['--'] else args.test_arguments
    try:
        receipt = collect(args.directory, flutter=args.flutter, test_arguments=extra)
        print(f"Sealed host LCOV against {len(receipt['input_sha256'])} inputs: {args.directory / RECEIPT}")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Host coverage collection failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

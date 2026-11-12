#!/usr/bin/env python3
"""Collect Dart VM coverage with a source-bound, successful-run receipt.

Run dependency resolution first, then use a NEW output directory:

    python3 tool/fidelity/collect_coverage.py coverage/vm
    python3 tool/fidelity/coverage_report.py coverage/vm --require-receipt

Arguments after ``--`` are passed to ``dart test``. The collector owns the
coverage destination; overriding it is an error. An existing directory is never
cleared or reused. A failed/interrupted command, changed source, or absent VM
output cannot produce a complete receipt. This proves collection provenance,
not branch correctness, hermetic execution, or semantic Office fidelity.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ENGINE = Path(__file__).resolve().parents[2]
RECEIPT = 'collection-receipt.json'
SCHEMA_VERSION = 1
IGNORED_DIRECTORIES = {'__pycache__', '.dart_tool', 'build', 'failures'}


class CollectionError(ValueError):
    """Coverage evidence is incomplete or no longer matches its inputs."""


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def _regular_files(directory):
    if directory.is_symlink():
        raise CollectionError(f'Symlink in collection inputs: {directory}')
    if not directory.exists():
        return
    for parent, directories, files in os.walk(directory, followlinks=False):
        directories[:] = sorted(name for name in directories if name not in IGNORED_DIRECTORIES)
        for name in directories + sorted(files):
            path = Path(parent) / name
            if path.is_symlink():
                raise CollectionError(f'Symlink in collection inputs: {path}')
        for name in sorted(files):
            path = Path(parent) / name
            if not path.is_file():
                raise CollectionError(f'Not a regular collection input: {path}')
            yield path


def source_snapshot(root):
    """Hash engine code, test inputs, scenario tools and available resolutions.

    Fonts in the sibling editor package are read by several engine tests. Root
    workspace resolution files are included as well as standalone engine files.
    External system files and mutable hosted dependency contents are not claimed
    to be hermetic inputs; the Dart executable, version and lockfiles are retained.
    """
    root = root.resolve()
    files = {}
    for folder in ('lib', 'test', 'tool'):
        for path in _regular_files(root / folder):
            files['engine/' + path.relative_to(root).as_posix()] = digest(path)
    # Engine tests import examples, but their generated output is not an input.
    for path in _regular_files(root / 'example'):
        if path.suffix == '.dart':
            files['engine/' + path.relative_to(root).as_posix()] = digest(path)
    for folder in ('fonts', 'example/fonts'):
        editor = root.parent / 'quds_office_editor'
        for path in _regular_files(editor / folder):
            files['quds_office_editor/' + path.relative_to(editor).as_posix()] = digest(path)
    workspace = root.parent.parent
    for label, directory in (('engine', root), ('workspace', workspace)):
        for name in ('pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml',
                     'dart_test.yaml', 'analysis_options.yaml',
                     '.dart_tool/package_config.json', '.dart_tool/package_graph.json'):
            path = directory / name
            if path.is_symlink():
                raise CollectionError(f'Symlink in collection configuration: {path}')
            if path.is_file():
                files[label + '/' + name] = digest(path)
    if not any(name.startswith('engine/lib/') and name.endswith('.dart') for name in files):
        raise CollectionError('No engine Dart sources found')
    return dict(sorted(files.items()))


def snapshot_digest(snapshot):
    return hashlib.sha256(json.dumps(snapshot, sort_keys=True).encode()).hexdigest()


def coverage_snapshot(directory):
    files = {}
    # Do not ignore any child directories: extra or symlinked evidence fails.
    for parent, directories, names in os.walk(directory, followlinks=False):
        for name in sorted(directories + names):
            path = Path(parent) / name
            if path.is_symlink():
                raise CollectionError(f'Symlink in coverage evidence: {path}')
        for name in sorted(names):
            path = Path(parent) / name
            relative = path.relative_to(directory).as_posix()
            if relative == RECEIPT:
                continue
            if not path.is_file():
                raise CollectionError(f'Not a regular coverage file: {path}')
            files[relative] = digest(path)
    return dict(sorted(files.items()))


def _timestamp():
    return datetime.now(timezone.utc).isoformat()


def _write_receipt(directory, data):
    temporary = directory / (RECEIPT + '.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    temporary.replace(directory / RECEIPT)


def _changes(expected, observed):
    return sorted(name for name in set(expected) | set(observed)
                  if expected.get(name) != observed.get(name))


def collect(directory, root=ENGINE, dart='dart', test_arguments=(), *, runner=subprocess.run):
    root = root.resolve()
    directory = directory.absolute()
    for parent in (directory, *directory.parents):
        if parent.is_symlink() and not (os.name != 'nt' and parent.parent == Path(parent.anchor)):
            raise CollectionError(f'Symlink in coverage destination: {parent}')
    directory = directory.resolve()
    for folder in ('lib', 'test', 'tool', 'example'):
        if directory.is_relative_to(root / folder):
            raise CollectionError('Coverage destination must be outside source/input directories')
    arguments = list(test_arguments)
    if any(argument == '--coverage' or argument.startswith('--coverage=') for argument in arguments):
        raise CollectionError('The collector owns --coverage; do not override it')
    executable = shutil.which(dart)
    if executable is None:
        raise CollectionError(f'Dart executable not found: {dart}')
    executable = Path(executable).resolve()
    version = subprocess.run([str(executable), '--version'], check=True,
                             capture_output=True, text=True)
    runtime = {'executable': str(executable), 'sha256': digest(executable),
               'version': (version.stdout + version.stderr).strip()}
    before = source_snapshot(root)
    command = [str(executable), 'test', *arguments, '--coverage=' + str(directory)]
    directory.parent.mkdir(parents=True, exist_ok=True)
    try:
        directory.mkdir()  # Exclusive ownership also excludes concurrent collectors.
    except FileExistsError as error:
        raise CollectionError(f'Coverage directory already exists; choose a fresh destination: {directory}') from error
    receipt = {'schema_version': SCHEMA_VERSION, 'status': 'running',
               'started_at': _timestamp(), 'package_root': str(root),
               'coverage_directory': str(directory), 'command': command,
               'runtime': runtime, 'input_sha256': before,
               'input_tree_sha256': snapshot_digest(before)}
    _write_receipt(directory, receipt)
    try:
        result = runner(command, cwd=root, check=False)
        receipt['returncode'] = result.returncode
        if result.returncode:
            raise CollectionError(f'Dart test failed with exit code {result.returncode}')
        after = source_snapshot(root)
        changed = _changes(before, after)
        if changed:
            raise CollectionError('Collection inputs changed during tests: ' + ', '.join(changed[:10]))
        if digest(executable) != runtime['sha256']:
            raise CollectionError('Dart executable changed during collection')
        outputs = coverage_snapshot(directory)
        if not any(name.endswith('.json') for name in outputs):
            raise CollectionError('No Dart VM coverage JSON was produced')
        # Validate coverage now, before a successful receipt can be issued.
        from coverage_report import report_coverage
        report_coverage(directory, root, verify_collection=False)
        receipt.update(status='complete', completed_at=_timestamp(),
                       coverage_sha256=outputs)
        _write_receipt(directory, receipt)
        return receipt
    except BaseException as error:
        receipt.update(status='failed', completed_at=_timestamp(),
                       error=f'{type(error).__name__}: {error}')
        _write_receipt(directory, receipt)
        raise


def verify_receipt(directory, root=ENGINE):
    directory = directory.absolute()
    path = directory / RECEIPT
    if directory.is_symlink() or path.is_symlink():
        raise CollectionError('Coverage directory and receipt must not be symlinks')
    if not path.is_file():
        raise CollectionError('Missing collection receipt; run collect_coverage.py into a fresh directory')
    data = json.loads(path.read_text(encoding='utf-8'))
    if (not isinstance(data, dict) or data.get('schema_version') != SCHEMA_VERSION
            or data.get('status') != 'complete' or type(data.get('returncode')) is not int
            or data.get('returncode') != 0):
        raise CollectionError('Coverage collection did not complete successfully')
    recorded = data.get('input_sha256')
    if (not isinstance(recorded, dict) or not recorded
            or data.get('input_tree_sha256') != snapshot_digest(recorded)):
        raise CollectionError('Invalid source snapshot in collection receipt')
    changed = _changes(recorded, source_snapshot(root))
    if changed:
        raise CollectionError('Coverage inputs no longer match collected sources: ' + ', '.join(changed[:10]))
    expected = data.get('coverage_sha256')
    if not isinstance(expected, dict) or not expected:
        raise CollectionError('Missing coverage inventory in collection receipt')
    changed = _changes(expected, coverage_snapshot(directory))
    if changed:
        raise CollectionError('Coverage files no longer match successful collection: ' + ', '.join(changed[:10]))
    runtime = data.get('runtime')
    command = data.get('command')
    original_directory = data.get('coverage_directory')
    if (not isinstance(runtime, dict) or not runtime.get('version')
            or not runtime.get('sha256') or not isinstance(command, list)
            or len(command) < 3 or command[:2] != [runtime.get('executable'), 'test']
            or not isinstance(original_directory, str)
            or command[-1] != '--coverage=' + original_directory
            or any(not isinstance(arg, str) for arg in command)
            or any(arg == '--coverage' or arg.startswith('--coverage=') for arg in command[2:-1])):
        raise CollectionError('Invalid Dart command/runtime provenance in collection receipt')
    return {'verified': True, 'receipt_sha256': digest(path),
            'input_tree_sha256': data['input_tree_sha256'],
            'input_files': len(recorded), 'coverage_files': len(expected),
            'command': command, 'runtime': runtime,
            'started_at': data.get('started_at'), 'completed_at': data.get('completed_at'),
            'scope': 'Engine lib, tests/fixtures, tools, imported examples, sibling fonts and resolution files; source/output identity, not branch correctness or a hermetic environment.'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', default='dart', help='Dart executable; defaults to PATH')
    parser.add_argument('directory', nargs='?', type=Path, default=ENGINE / 'coverage/vm')
    parser.add_argument('test_arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    extra = args.test_arguments[1:] if args.test_arguments[:1] == ['--'] else args.test_arguments
    try:
        receipt = collect(args.directory, dart=args.dart, test_arguments=extra)
        print(f"Sealed {len(receipt['coverage_sha256'])} coverage files against "
              f"{len(receipt['input_sha256'])} inputs: {args.directory / RECEIPT}")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Coverage collection failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

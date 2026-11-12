#!/usr/bin/env python3
"""List, plan or run bounded Office feature scenarios and independent oracles.

Examples (from the engine package):
  python3 tool/fidelity/feature_matrix.py list
  python3 tool/fidelity/feature_matrix.py plan footnotes headings tables
  python3 tool/fidelity/feature_matrix.py run styles references

Every run removes only its selected manifest outputs before production. Reviewed
editor goldens are listed separately and are never updated or run implicitly.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
from zipfile import BadZipFile, ZipFile

from collect_coverage import source_snapshot, snapshot_digest
from inventory import load_manifest, package_root, _safe_file

ROOT = Path(__file__).resolve().parents[2]
MATRIX = Path(__file__).with_suffix('.json')
REQUIRED_FEATURES = {'footnotes', 'endnotes', 'headings', 'styles', 'paragraphs',
                     'images', 'tables', 'tocs', 'textflow', 'placement', 'drawings',
                     'references', 'comments', 'spreadsheets', 'slides'}
SCOPE = 'Selected producer scenarios and independent package oracles; not full-suite, branch-coverage or Microsoft Office visual-equivalence certification.'


class MatrixError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise MatrixError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f'Duplicate matrix JSON key: {key}')
        result[key] = value
    return result


def names(value, label, *, nonempty=True):
    require(isinstance(value, list) and (value or not nonempty)
            and all(isinstance(item, str) and item for item in value), f'Invalid {label}')
    require(len(set(value)) == len(value), f'Duplicate {label}')
    return value


def relative(value):
    require(isinstance(value, str) and value and '\\' not in value, 'Invalid reference path')
    path = PurePosixPath(value)
    require(not path.is_absolute() and '..' not in path.parts and str(path) == value,
            f'Unsafe reference path: {value}')
    return path


def reference(root, value, prefix, suffix):
    path = relative(value)
    require(value.startswith(prefix) and value.endswith(suffix), f'Invalid reference: {value}')
    target = root.joinpath(*path.parts)
    require(target.is_file() and not target.is_symlink() and
            target.resolve().is_relative_to(root.resolve()), f'Missing/escaping reference: {value}')


def load_matrix(root=ROOT, matrix_path=MATRIX):
    data = json.loads(matrix_path.read_text(), object_pairs_hook=unique_object)
    require(isinstance(data, dict) and set(data) == {'version', 'features', 'bundles', 'goldens'}
            and type(data['version']) is int and data['version'] == 1, 'Invalid matrix schema')
    for kind in ('features', 'bundles', 'goldens'):
        require(isinstance(data[kind], dict) and data[kind], f'Empty/malformed {kind}')
        require(all(re.fullmatch(r'[a-z][a-z0-9-]*', key) for key in data[kind]), f'Invalid {kind} name')
    require(REQUIRED_FEATURES <= set(data['features']),
            f'Missing required features: {sorted(REQUIRED_FEATURES - set(data["features"]))}')
    manifest = load_manifest(root / 'tool/fidelity/output_manifest.json')
    for name, bundle in data['bundles'].items():
        require(isinstance(bundle, dict) and set(bundle) == {'tests', 'scripts', 'oracles', 'controls'},
                f'Invalid bundle: {name}')
        for kind, prefix, suffix in (('tests', 'test/', '_test.dart'),
                                     ('scripts', 'tool/fidelity/', '.dart'),
                                     ('controls', 'tool/fidelity/test_', '.py')):
            for path in names(bundle[kind], f'{name}/{kind}', nonempty=False):
                reference(root, path, prefix, suffix)
        producers = bundle['tests'] + bundle['scripts']
        require(producers and any(p in manifest.producers.values() for p in producers),
                f'Bundle has no manifest outputs: {name}')
        require(all(p in manifest.producers.values() for p in bundle['scripts']),
                f'Unregistered producer script: {name}')
        require(isinstance(bundle['oracles'], list) and bundle['oracles'], f'Missing oracles: {name}')
        for command in bundle['oracles']:
            require(isinstance(command, list) and command and
                    all(isinstance(arg, str) and arg for arg in command), f'Invalid oracle: {name}')
            reference(root, command[0], 'tool/fidelity/', '.py')
            require(command[0].endswith('_oracle.py') or command[0] == 'tool/fidelity/corpus.py',
                    f'Not a verification oracle: {command[0]}')
            if command[0].endswith('/corpus.py'):
                require(command[1:] == ['verify'], 'Corpus oracle must verify; fixture seeding is forbidden')
            else:
                require(all(str(relative(arg)).startswith('build/fidelity') for arg in command[1:]),
                        f'Invalid oracle arguments: {name}')
    for name, golden in data['goldens'].items():
        require(isinstance(golden, dict) and set(golden) == {'tests', 'files'}, f'Invalid golden: {name}')
        for kind, prefix, suffix in (('tests', 'test/', '_test.dart'), ('files', 'test/goldens/', '.png')):
            for path in names(golden[kind], f'{name}/{kind}'):
                reference(root.parent / 'quds_office_editor', path, prefix, suffix)
    for name, feature in data['features'].items():
        require(isinstance(feature, dict) and set(feature) == {'description', 'bundles', 'goldens'}
                and isinstance(feature['description'], str) and feature['description'].strip(),
                f'Invalid feature: {name}')
        for kind in ('bundles', 'goldens'):
            refs = names(feature[kind], f'{name}/{kind}', nonempty=kind == 'bundles')
            require(set(refs) <= set(data[kind]), f'Unknown {kind} reference: {name}')
    return data, manifest


def plan(features, root=ROOT, matrix_path=MATRIX):
    data, manifest = load_matrix(root, matrix_path)
    names(features, 'feature selection')
    require(set(features) <= set(data['features']), f'Unknown features: {sorted(set(features) - set(data["features"]))}')
    bundles = sorted({name for feature in features for name in data['features'][feature]['bundles']})
    tests = sorted({path for name in bundles for path in data['bundles'][name]['tests']})
    scripts = sorted({path for name in bundles for path in data['bundles'][name]['scripts']})
    oracles = sorted({tuple(args) for name in bundles for args in data['bundles'][name]['oracles']})
    controls = sorted({path for name in bundles for path in data['bundles'][name]['controls']})
    outputs = sorted(path for path, producer in manifest.producers.items() if producer in tests + scripts)
    commands = ([{'stage': 'tests', 'argv': ['dart', 'test', *tests]}] if tests else [])
    commands += [{'stage': 'producer', 'argv': ['dart', 'run', path]} for path in scripts]
    commands += [{'stage': 'oracle', 'argv': ['python3', *args]} for args in oracles]
    commands += [{'stage': 'controls', 'argv': ['python3', '-m', 'unittest', 'discover',
                  '-s', 'tool/fidelity', '-p', Path(path).name]} for path in controls]
    goldens = sorted({name for feature in features for name in data['features'][feature]['goldens']})
    golden_tests = sorted({path for name in goldens for path in data['goldens'][name]['tests']})
    return {'version': 1, 'scope': SCOPE, 'features': sorted(features), 'bundles': bundles,
            'matrix_sha256': hashlib.sha256(matrix_path.read_bytes()).hexdigest(),
            'output_manifest_sha256': manifest.sha256, 'expected_outputs': outputs,
            'commands': commands,
            'editor_goldens': {'executed': False, 'required_runtime': 'Flutter 3.44.0 on Linux',
                'cwd': '../quds_office_editor',
                'command': ['flutter', 'test', '--no-pub', *golden_tests] if golden_tests else [],
                'files': sorted({path for name in goldens for path in data['goldens'][name]['files']})}}


def inspect_outputs(root, paths):
    files = []
    for name in paths:
        path = _safe_file(root / 'build', name)
        require(path.is_file() and path.stat().st_size > 0, f'Missing/empty selected output: {name}')
        with ZipFile(path) as archive:
            members = archive.namelist()
            require(len(members) == len(set(members)) and archive.testzip() is None,
                    f'Corrupt/duplicate ZIP members: {name}')
            require({'[Content_Types].xml', '_rels/.rels'} <= set(members), f'Invalid OPC package: {name}')
        files.append({'path': name, 'bytes': path.stat().st_size,
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return files


def run(features, root=ROOT, matrix_path=MATRIX, *, dart='dart', runner=subprocess.run):
    root = package_root(root)
    selected = plan(features, root, matrix_path)  # Validate every reference before any deletion.
    executable = shutil.which(dart)
    require(executable is not None, f'Dart executable not found: {dart}')
    before = source_snapshot(root)
    targets = [_safe_file(root / 'build', path) for path in selected['expected_outputs']]
    receipt_path = _safe_file(root / 'build', 'fidelity-features/' + '-'.join(selected['features']) + '.json')
    lock = _safe_file(root / 'build', 'fidelity-feature-run.lock')
    root.joinpath('build').mkdir(parents=True, exist_ok=True)
    try:
        owner = lock.open('x')
    except FileExistsError as error:
        raise MatrixError('Another feature run owns the output lock') from error
    report = dict(selected, status='running', completed_commands=[], files=[],
                  input_sha256=before, input_tree_sha256=snapshot_digest(before))
    try:
        with owner:
            # Invalidate an earlier success before removing any output, including
            # if this process is killed before its finally block can run.
            receipt_path.parent.mkdir(parents=True, exist_ok=True)
            receipt_path.write_text(json.dumps(report, indent=2) + '\n')
            for path in targets:
                path.unlink(missing_ok=True)
            for command in selected['commands']:
                argv = [executable if command['argv'][0] == 'dart' else sys.executable, *command['argv'][1:]]
                result = runner(argv, cwd=root, check=False)
                report['completed_commands'].append(dict(command, argv=argv, returncode=result.returncode))
                require(result.returncode == 0, f'{command["stage"]} failed ({result.returncode}): {argv}')
            report['files'] = inspect_outputs(root, selected['expected_outputs'])
            require(source_snapshot(root) == before, 'Scenario inputs changed during the feature run')
            report['status'] = 'passed'
    except BaseException as error:
        report.update(status='failed', error=f'{type(error).__name__}: {error}')
        raise
    finally:
        try:
            receipt_path.parent.mkdir(parents=True, exist_ok=True)
            receipt_path.write_text(json.dumps(report, indent=2) + '\n')
        finally:
            lock.unlink()
    return report, receipt_path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', default='dart', help='Dart executable for run')
    parser.add_argument('action', choices=('list', 'plan', 'run'))
    parser.add_argument('features', nargs='*')
    args = parser.parse_args(argv)
    try:
        if args.action == 'list':
            require(not args.features, 'list does not take feature names')
            data, _ = load_matrix()
            print(json.dumps(data['features'], indent=2))
        elif args.action == 'plan':
            print(json.dumps(plan(args.features), indent=2))
        else:
            report, receipt = run(args.features, dart=args.dart)
            print(f"Selected features {', '.join(report['features'])}: "
                  f"{len(report['files'])} regenerated outputs verified; receipt {receipt}")
        return 0
    except (OSError, ValueError, BadZipFile) as error:
        print(f'Feature matrix failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

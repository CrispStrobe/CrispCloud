#!/usr/bin/env python3
"""Freeze and independently validate an explicitly counted final app corpus.

Run collect-schema only after the final host gate and commit pins are supplied.
The native phase is separate so the shared LibreOfficeKit runtime stays serial.
All evidence is written outside the application checkout.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True

RUNTIME = Path(__file__).resolve().parent
VALIDATOR = RUNTIME / 'validator/OfficeValidation.dll'
VALIDATOR_RECEIPT = RUNTIME / 'validator/build-receipt.json'
RENDERER_RECEIPT = RUNTIME / 'renderer-provenance.json'
PROBE = RUNTIME / 'probe_host_native_gap.py'
OFFICE = {'.docx', '.docm', '.dotx', '.dotm', '.xlsx', '.pptx'}
ENGINE_PREFIX = 'packages/quds_office_engine/build/'
ENGINE_INVENTORY = 'packages/quds_office_engine/build/fidelity-inventory.json'
ENGINE_MANIFEST = 'packages/quds_office_engine/tool/fidelity/output_manifest.json'
HOST_INVENTORY = 'build/fidelity-host/inventory.json'
HOST_MANIFEST = 'tool/office_host_evidence.json'
SYNC_MANIFEST = 'tool/office_fidelity_manifest.json'
FROZEN_METADATA = {
    ENGINE_INVENTORY: 'engine-inventory.json',
    HOST_INVENTORY: 'host-inventory.json',
    ENGINE_MANIFEST: 'engine-output-manifest.json',
    HOST_MANIFEST: 'host-output-manifest.json',
    SYNC_MANIFEST: 'managed-source-manifest.json',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def checked_relative(name):
    require(isinstance(name, str) and bool(name) and '\\' not in name,
            f'Invalid relative evidence path: {name!r}')
    path = PurePosixPath(name)
    require(not path.is_absolute() and bool(path.parts) and '..' not in path.parts and str(path) == name,
            f'Invalid relative evidence path: {name}')
    return path


def require_file(root, name):
    checked_relative(name)
    path = root / name
    require(path.is_file() and path.resolve().is_relative_to(root),
            f'Missing or escaping evidence file: {name}')
    current = path
    while current != root:
        require(not current.is_symlink(), f'Symlink in evidence path: {name}')
        current = current.parent
    return path


def runtime_receipt(repository):
    validator = read_json(VALIDATOR_RECEIPT)
    require(sha(VALIDATOR) == validator['assembly_sha256'], 'Validator assembly changed')
    require(sha(repository / 'tool/office-validation/Program.cs') == validator['source_sha256'],
            'Pinned app validator source differs from the frozen assembly receipt')
    for name, digest in validator['dependencies_sha256'].items():
        if name.endswith('.dll'):
            require(sha(VALIDATOR.parent / name) == digest, f'Validator dependency changed: {name}')
    renderer = read_json(RENDERER_RECEIPT)
    for entry in renderer['adapter']['artifacts']:
        require(sha(entry['path']) == entry['sha256'], f'Frozen native adapter changed: {entry["path"]}')
    return {
        'validator_source_sha256': validator['source_sha256'],
        'validator_assembly_sha256': sha(VALIDATOR),
        'validator_build_receipt_sha256': sha(VALIDATOR_RECEIPT),
        'renderer_provenance_sha256': sha(RENDERER_RECEIPT),
        'native_conversion_script_sha256': sha(repository / 'tool/office-validation/render.py'),
        'collection_script_sha256': sha(__file__),
        'host_native_probe_sha256': sha(PROBE),
    }


def require_runtime_environment():
    require(shutil.which('libreoffice') == str(RUNTIME / 'lok242-bin/libreoffice'),
            f'Prepend {RUNTIME / "lok242-bin"} to PATH for the frozen native adapter')
    require(shutil.which('dotnet') == str(RUNTIME / 'dotnet/dotnet'),
            f'Prepend {RUNTIME / "dotnet"} to PATH for the frozen validator runtime')


def count_options(parser):
    for name in ('engine', 'host', 'managed'):
        parser.add_argument(f'--{name}-count', type=positive_count, required=True,
                            help=f'Explicit final {name} file count; no historical default')


def positive_count(value):
    try:
        count = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError('Count must be a positive integer') from error
    if count <= 0:
        raise argparse.ArgumentTypeError('Count must be a positive integer')
    return count


def verify_pins(repository, app_commit, source_commit, managed_count):
    require(re.fullmatch('[0-9a-f]{40}', app_commit) is not None and
            re.fullmatch('[0-9a-f]{40}', source_commit) is not None,
            'App and source pins must be literal full commit IDs')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip()
    require(head == app_commit, 'App HEAD does not match the supplied final pin')
    status = subprocess.check_output(['git', 'status', '--porcelain=v1', '--untracked-files=normal'],
                                     cwd=repository, text=True)
    require(not status.strip(), 'Final app capture requires a clean worktree')
    sync = read_json(repository / SYNC_MANIFEST)
    require(sync['source_commit'] == source_commit, 'Managed source pin differs from final source pin')
    require(len(sync['files']) == managed_count,
            f'Final managed source inventory must contain exactly {managed_count} files')
    for name, digest in sync['files'].items():
        require(sha(require_file(repository, name)) == digest, f'Managed source mismatch: {name}')
    return sync


def inventory_entries(engine, host, declared_engine, declared_host, counts):
    require(engine.get('ok') is True and not engine['errors'] and
            engine['expected_files'] == engine['observed_files'] == engine['verified_files'] == counts.engine_count,
            f'Engine inventory is not a clean {counts.engine_count}-file final capture')
    require(host['expected'] == host['verified'] == counts.host_count and not host['failures'],
            f'Host inventory is not a clean {counts.host_count}-file final capture')
    require(declared_engine['version'] == declared_host['version'] == 1 and
            declared_engine['package'] == 'quds_office_engine', 'Unexpected manifest version or package')
    engine_names = []
    for item in declared_engine['series']:
        require(isinstance(item['pattern'], str) and item['pattern'].count('{cycle}') == 1 and
                item['cycles'] in ([0, 1, 2], [1, 2, 3]) and
                all(type(cycle) is int for cycle in item['cycles']),
                'Engine series must declare exactly three integer save cycles')
        engine_names.extend(item['pattern'].format(cycle=cycle) for cycle in item['cycles'])
    engine_names += [item['path'] for item in declared_engine['standalone']]
    require(len(engine_names) == len(set(engine_names)) == declared_engine['expected_file_count'] == counts.engine_count,
            f'Declared engine inventory is not exactly {counts.engine_count} unique paths')
    host_names = declared_host['outputs']
    require(len(host_names) == len(set(host_names)) == counts.host_count,
            f'Declared host inventory is not exactly {counts.host_count} unique paths')
    for name in engine_names + host_names:
        checked_relative(name)
        require(PurePosixPath(name).suffix.lower() in OFFICE, f'Unexpected Office extension: {name}')
    require({item['path'] for item in engine['files']} == set(engine_names) and
            len(engine['files']) == counts.engine_count,
            'Engine receipt paths differ from declared inventory')
    require({item['path'] for item in host['files']} == set(host_names) and
            len(host['files']) == counts.host_count,
            'Host receipt paths differ from declared inventory')
    files = []
    for group, rows, prefix in [('engine', engine['files'], ENGINE_PREFIX), ('host', host['files'], '')]:
        for row in rows:
            require(type(row['bytes']) is int and row['bytes'] > 0 and
                    re.fullmatch('[0-9a-f]{64}', row['sha256']) is not None,
                    f'Invalid byte/hash receipt: {row["path"]}')
            files.append({'path': prefix + row['path'], 'bytes': row['bytes'],
                          'sha256': row['sha256'], 'producer_group': group})
    require(len(files) == len({item['path'] for item in files}) == counts.engine_count + counts.host_count,
            'Merged inventory has missing or duplicate entries')
    return sorted(files, key=lambda item: item['path'])


def verify_snapshot(output, counts):
    manifest = read_json(output / 'input-manifest.json')
    inputs = Path(manifest['input_root']).resolve()
    require(inputs == (output / 'inputs').resolve(), 'Snapshot root mismatch')
    entries = {item['path']: item for item in manifest['files']}
    total = counts.engine_count + counts.host_count
    require(len(entries) == len(manifest['files']) == manifest['total'] == total,
            f'Snapshot must contain {total} unique entries')
    require(manifest['engine_files'] == counts.engine_count and manifest['host_files'] == counts.host_count and
            manifest['managed_source_files_verified'] == counts.managed_count,
            'Snapshot source counts changed')
    require(set(manifest['metadata_sha256']) == set(FROZEN_METADATA.values()),
            'Frozen manifest/inventory metadata set changed')
    for name, digest in manifest['metadata_sha256'].items():
        require(sha(require_file(output, name)) == digest, f'Frozen metadata bytes changed: {name}')
    engine = read_json(output / 'engine-inventory.json')
    host = read_json(output / 'host-inventory.json')
    require(engine['manifest_sha256'] == sha(output / 'engine-output-manifest.json') and
            host['manifest_sha256'] == sha(output / 'host-output-manifest.json'),
            'Frozen inventory manifest hashes differ from the declared manifests')
    declared = inventory_entries(engine, host, read_json(output / 'engine-output-manifest.json'),
                                 read_json(output / 'host-output-manifest.json'), counts)
    require(sorted(manifest['files'], key=lambda item: item['path']) == declared,
            'Snapshot entries differ from exact declared inventory/hash sets')
    sync = read_json(output / 'managed-source-manifest.json')
    require(sync['source_commit'] == manifest['managed_source_commit'] and
            len(sync['files']) == counts.managed_count, 'Frozen managed source pin/count changed')
    observed = {p.relative_to(inputs).as_posix() for p in inputs.rglob('*') if p.is_file()}
    require(observed == set(entries), 'Snapshot file set differs from manifest')
    for name, item in entries.items():
        path = require_file(inputs, name)
        require(path.stat().st_size == item['bytes'] and sha(path) == item['sha256'],
                f'Snapshot bytes changed: {name}')
    return manifest, entries


def verify_schema(output, counts):
    manifest, entries = verify_snapshot(output, counts)
    total = counts.engine_count + counts.host_count
    schema = read_json(output / 'schema-report.json')
    require(schema['Files'] == total and schema['Failures'] == 0, 'SDK validation failed')
    for item in schema['Reports']:
        require(item['File'] == str(Path(item['File']).resolve()),
                f'SDK receipt must name the exact canonical input path: {item["File"]}')
    reports = {Path(item['File']): item for item in schema['Reports']}
    require(len(reports) == len(schema['Reports']) == total, 'SDK receipt set is incomplete or duplicated')
    inputs = Path(manifest['input_root'])
    require(set(reports) == {inputs / name for name in entries}, 'SDK input set mismatch')
    for name, item in entries.items():
        report = reports[inputs / name]
        require(report.get('Errors') == [] and 'Exception' not in report,
                f'SDK error for {name}')
        require(report['Sha256'] == item['sha256'], f'SDK hash mismatch for {name}')
    return manifest


def collect_schema(args):
    require_runtime_environment()
    repository = args.repository.resolve()
    output = args.output_root.resolve()
    require(not output.is_relative_to(repository), 'Evidence must be outside the app checkout')
    sync = verify_pins(repository, args.app_commit, args.source_commit, args.managed_count)
    total = args.engine_count + args.host_count
    runtime = runtime_receipt(repository)
    engine = read_json(repository / ENGINE_INVENTORY)
    host = read_json(repository / HOST_INVENTORY)
    declared_engine = read_json(repository / ENGINE_MANIFEST)
    declared_host = read_json(repository / HOST_MANIFEST)
    require(engine['manifest_sha256'] == sha(repository / ENGINE_MANIFEST), 'Engine manifest hash mismatch')
    require(host['manifest_sha256'] == sha(repository / HOST_MANIFEST), 'Host manifest hash mismatch')
    files = inventory_entries(engine, host, declared_engine, declared_host, args)
    for item in files:
        path = require_file(repository, item['path'])
        require(sha(path) == item['sha256'] and path.stat().st_size == item['bytes'],
                f'Capture differs from inventory receipt: {item["path"]}')
    require(not output.exists(), 'External acceptance must start in a fresh output directory')
    output.mkdir(parents=True)
    inputs = output / 'inputs'
    inputs.mkdir()
    for item in files:
        target = inputs / item['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repository / item['path'], target)
    for source, destination in FROZEN_METADATA.items():
        shutil.copyfile(repository / source, output / destination)
    shutil.copyfile(VALIDATOR_RECEIPT, output / 'validator-build-receipt.json')
    shutil.copyfile(RENDERER_RECEIPT, output / 'native-renderer-provenance.json')
    manifest = {
        'format_version': 1, 'source_commit': args.app_commit,
        'managed_source_commit': args.source_commit, 'repository': str(repository),
        'collected_utc': datetime.now(timezone.utc).isoformat(),
        'input_root': str(inputs), 'total': total,
        'engine_files': args.engine_count, 'host_files': args.host_count,
        'managed_source_files_verified': len(sync['files']),
        'engine_inventory_sha256': sha(output / 'engine-inventory.json'),
        'host_inventory_sha256': sha(output / 'host-inventory.json'),
        'metadata_sha256': {name: sha(output / name) for name in FROZEN_METADATA.values()},
        **runtime,
        'collection': 'Exact declared engine and actual host captures, frozen outside the application checkout.',
        'files': sorted(files, key=lambda item: item['path']),
    }
    write_json(output / 'input-manifest.json', manifest)
    verify_snapshot(output, args)
    verify_pins(repository, args.app_commit, args.source_commit, args.managed_count)
    started = time.monotonic()
    with (output / 'schema.log').open('w') as log:
        result = subprocess.run(['dotnet', str(VALIDATOR), str(inputs), str(output / 'schema-report.json')],
                                stdout=log, stderr=subprocess.STDOUT, check=False)
    summary = {
        'source_commit': args.app_commit, 'managed_source_commit': args.source_commit,
        'status': 'schema_receipt_verification_pending' if result.returncode == 0 else 'failed',
        'sdk_files': total, 'engine_files': args.engine_count, 'host_files': args.host_count,
        'managed_source_files_verified': args.managed_count,
        'validator_exit_code': result.returncode,
        'schema_elapsed_seconds': time.monotonic() - started,
        'input_manifest_sha256': sha(output / 'input-manifest.json'),
        'native_status': 'pending',
    }
    write_json(output / 'external-summary.json', summary)
    require(result.returncode == 0, 'SDK process failed; preserved schema report and log')
    try:
        verify_schema(output, args)
        verify_pins(repository, args.app_commit, args.source_commit, args.managed_count)
    except (OSError, ValueError, KeyError) as error:
        summary.update({'status': 'failed', 'receipt_verification_error': str(error)})
        write_json(output / 'external-summary.json', summary)
        raise
    summary.update({'status': 'schema_passed_native_pending',
                    'sdk_passing_files': total, 'sdk_failures': 0,
                    'all_schema_receipt_hashes_match': True,
                    'schema_report_sha256': sha(output / 'schema-report.json')})
    write_json(output / 'external-summary.json', summary)
    print(json.dumps(summary, indent=2))


def native(args):
    require_runtime_environment()
    output = args.output_root.resolve()
    manifest = verify_schema(output, args)
    repository = Path(manifest['repository'])
    verify_pins(repository, manifest['source_commit'], manifest['managed_source_commit'], args.managed_count)
    for name, digest in runtime_receipt(repository).items():
        require(digest == manifest[name], f'Frozen runtime or validation script changed: {name}')
    for original, captured in FROZEN_METADATA.items():
        require(sha(require_file(repository, original)) == manifest['metadata_sha256'][captured],
                f'App manifest/inventory changed after snapshot: {original}')
    previous_summary = read_json(output / 'external-summary.json')
    require(previous_summary['input_manifest_sha256'] == sha(output / 'input-manifest.json') and
            previous_summary['schema_report_sha256'] == sha(output / 'schema-report.json'),
            'Accepted input or SDK receipt changed after collection')
    with (output / 'host-native.log').open('w') as log:
        result = subprocess.run([sys.executable, str(PROBE), str(repository), manifest['input_root'],
                                 str(output / 'host-native'), '--manifest', str(output / 'input-manifest.json'),
                                 '--schema-report', str(output / 'schema-report.json'),
                                 '--engine-count', str(args.engine_count), '--host-count', str(args.host_count),
                                 '--managed-count', str(args.managed_count)],
                                stdout=log, stderr=subprocess.STDOUT, check=False)
    summary = read_json(output / 'external-summary.json')
    try:
        verify_schema(output, args)
        verify_pins(repository, manifest['source_commit'], manifest['managed_source_commit'], args.managed_count)
    except (OSError, ValueError, KeyError) as error:
        summary.update({'status': 'failed', 'receipt_verification_error': str(error),
                        'all_input_hashes_unchanged': False})
        write_json(output / 'external-summary.json', summary)
        raise
    report_path = output / 'host-native/render-report.json'
    report = read_json(report_path) if report_path.exists() else {}
    passed = result.returncode == 0 and report.get('status') == 'passed' and report.get('rendered_files') == 11
    summary.update({'status': 'passed' if passed else 'failed',
                    'native_status': report.get('status', 'failed'),
                    'native_exit_code': result.returncode,
                    'native_files': report.get('rendered_files', 0),
                    'native_pages': report.get('rendered_pages', 0),
                    'native_scope': 'Eleven actual host XLSX/PPTX/DOCM/DOTX/DOTM uploads; source engine full rendering is independently reported.',
                    'native_failures': report.get('failures', ['Native report missing']),
                    'all_input_hashes_unchanged': True})
    if report_path.exists():
        summary['host_native_report_sha256'] = sha(report_path)
    write_json(output / 'external-summary.json', summary)
    artifacts = {}
    for path in sorted(output.rglob('*')):
        if path.is_file() and not path.is_relative_to(output / 'inputs') and path.name != 'artifact-hashes.json':
            artifacts[path.relative_to(output).as_posix()] = {'sha256': sha(path), 'bytes': path.stat().st_size}
    write_json(output / 'artifact-hashes.json', artifacts)
    print(json.dumps(summary, indent=2))
    require(passed, 'Host native acceptance failed; preserved all artifacts')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    collect = commands.add_parser('collect-schema')
    collect.add_argument('--repository', type=Path, required=True)
    collect.add_argument('--app-commit', required=True)
    collect.add_argument('--source-commit', required=True)
    collect.add_argument('--output-root', type=Path, required=True)
    count_options(collect)
    render = commands.add_parser('native')
    render.add_argument('--output-root', type=Path, required=True)
    count_options(render)
    args = parser.parse_args()
    (collect_schema if args.command == 'collect-schema' else native)(args)


if __name__ == '__main__':
    main()

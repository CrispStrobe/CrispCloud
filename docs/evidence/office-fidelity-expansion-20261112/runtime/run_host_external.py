#!/usr/bin/env python3
"""Freeze and independently validate the complete declared app corpus.

Run collect-schema only after the final host gate and commit pins are supplied.
The native phase is separate so the shared LibreOfficeKit runtime stays serial.
All evidence is written outside the application checkout.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import time


RUNTIME = Path(__file__).resolve().parent
VALIDATOR = RUNTIME / 'validator/OfficeValidation.dll'
VALIDATOR_RECEIPT = RUNTIME / 'validator/build-receipt.json'
RENDERER_RECEIPT = RUNTIME / 'renderer-provenance.json'
OFFICE = {'.docx', '.docm', '.dotx', '.dotm', '.xlsx', '.pptx'}
ENGINE_PREFIX = 'packages/quds_office_engine/build/'
ENGINE_INVENTORY = 'packages/quds_office_engine/build/fidelity-inventory.json'
ENGINE_MANIFEST = 'packages/quds_office_engine/tool/fidelity/output_manifest.json'
HOST_INVENTORY = 'build/fidelity-host/inventory.json'
HOST_MANIFEST = 'tool/office_host_evidence.json'
SYNC_MANIFEST = 'tool/office_fidelity_manifest.json'


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
    path = PurePosixPath(name)
    require(not path.is_absolute() and '..' not in path.parts and str(path) == name,
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
    }


def require_runtime_environment():
    require(shutil.which('libreoffice') == str(RUNTIME / 'lok242-bin/libreoffice'),
            'Source env-external.sh to select the frozen native adapter')
    require(shutil.which('dotnet') == str(RUNTIME / 'dotnet/dotnet'),
            'Source env-external.sh to select the frozen validator runtime')


def verify_snapshot(output):
    manifest = read_json(output / 'input-manifest.json')
    inputs = Path(manifest['input_root']).resolve()
    require(inputs == (output / 'inputs').resolve(), 'Snapshot root mismatch')
    entries = {item['path']: item for item in manifest['files']}
    expected_engine = read_json(output / 'engine-output-manifest.json')['expected_file_count']
    expected_host = len(read_json(output / 'host-output-manifest.json')['outputs'])
    expected_total = expected_engine + expected_host
    require(len(entries) == len(manifest['files']) == manifest['total'] == expected_total,
            'Snapshot must contain every declared unique entry')
    require(manifest['engine_files'] == expected_engine and manifest['host_files'] == expected_host,
            'Snapshot source counts changed')
    observed = {p.relative_to(inputs).as_posix() for p in inputs.rglob('*') if p.is_file()}
    require(observed == set(entries), 'Snapshot file set differs from manifest')
    for name, item in entries.items():
        path = require_file(inputs, name)
        require(path.stat().st_size == item['bytes'] and sha(path) == item['sha256'] and
                sha(Path(manifest['repository']) / name) == item['sha256'],
                f'Snapshot bytes changed: {name}')
    return manifest, entries


def verify_schema(output):
    manifest, entries = verify_snapshot(output)
    schema = read_json(output / 'schema-report.json')
    require(schema['Files'] == manifest['total'] and schema['Failures'] == 0, 'SDK validation failed')
    reports = {Path(item['File']).resolve(): item for item in schema['Reports']}
    require(len(reports) == len(schema['Reports']) == manifest['total'], 'SDK receipt set is incomplete or duplicated')
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
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip()
    require(head == args.app_commit, 'App HEAD does not match the supplied final pin')
    status = subprocess.check_output(['git', 'status', '--porcelain=v1', '--untracked-files=normal'],
                                     cwd=repository, text=True)
    require(not status.strip(), 'Final app capture requires a clean worktree')
    sync = read_json(repository / SYNC_MANIFEST)
    require(sync['source_commit'] == args.source_commit, 'Managed source pin differs from final source pin')
    require(bool(sync['files']), 'Managed source inventory must not be empty')
    for name, digest in sync['files'].items():
        require(sha(require_file(repository, name)) == digest, f'Managed source mismatch: {name}')
    runtime = runtime_receipt(repository)
    engine = read_json(repository / ENGINE_INVENTORY)
    host = read_json(repository / HOST_INVENTORY)
    declared_engine = read_json(repository / ENGINE_MANIFEST)
    declared_host = read_json(repository / HOST_MANIFEST)
    expected_engine = declared_engine['expected_file_count']
    expected_host = len(declared_host['outputs'])
    expected_total = expected_engine + expected_host
    producer = read_json(args.producer_receipt)
    require(producer.get('status') == 'passed' and producer['app_commit'] == args.app_commit
            and producer['source_commit'] == args.source_commit,
            'External capture requires a passed complete host gate at these exact pins')
    require(producer['artifacts']['engine-inventory.json'] == sha(repository / ENGINE_INVENTORY)
            and producer['artifacts']['host-inventory.json'] == sha(repository / HOST_INVENTORY),
            'Capture inventories differ from the successful host gate')
    require(engine.get('ok') is True and not engine['errors'] and
            engine['expected_files'] == engine['observed_files'] == engine['verified_files'] == expected_engine,
            'Engine inventory differs from the committed output manifest')
    require(host['expected'] == host['verified'] == expected_host and not host['failures'],
            'Host inventory differs from the committed output manifest')
    require(engine['manifest_sha256'] == sha(repository / ENGINE_MANIFEST), 'Engine manifest hash mismatch')
    require(host['manifest_sha256'] == sha(repository / HOST_MANIFEST), 'Host manifest hash mismatch')
    engine_names = [item['pattern'].format(cycle=cycle)
                    for item in declared_engine['series'] for cycle in item['cycles']]
    engine_names += [item['path'] for item in declared_engine['standalone']]
    require(len(engine_names) == len(set(engine_names)) == declared_engine['expected_file_count'] == expected_engine,
            'Declared engine inventory is not a complete unique path set')
    host_names = declared_host['outputs']
    require(len(host_names) == len(set(host_names)) == expected_host, 'Declared host inventory is not a complete unique path set')
    require({item['path'] for item in engine['files']} == set(engine_names) and len(engine['files']) == expected_engine,
            'Engine receipt paths differ from declared inventory')
    require({item['path'] for item in host['files']} == set(host_names) and len(host['files']) == expected_host,
            'Host receipt paths differ from declared inventory')
    files = []
    for group, rows, prefix in [('engine', engine['files'], ENGINE_PREFIX), ('host', host['files'], '')]:
        for row in rows:
            name = prefix + row['path']
            path = require_file(repository, name)
            require(path.suffix.lower() in OFFICE, f'Unexpected Office extension: {name}')
            require(sha(path) == row['sha256'] and path.stat().st_size == row['bytes'],
                    f'Capture differs from inventory receipt: {name}')
            files.append({'path': name, 'bytes': row['bytes'], 'sha256': row['sha256'], 'producer_group': group})
    require(len(files) == len({item['path'] for item in files}) == expected_total, 'Merged inventory must include every declared unique path')
    require(not output.exists(), 'External acceptance must start in a fresh output directory')
    output.mkdir(parents=True)
    inputs = output / 'inputs'
    inputs.mkdir()
    for item in files:
        target = inputs / item['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repository / item['path'], target)
    for source, destination in [(ENGINE_INVENTORY, 'engine-inventory.json'),
                                (HOST_INVENTORY, 'host-inventory.json'),
                                (ENGINE_MANIFEST, 'engine-output-manifest.json'),
                                (HOST_MANIFEST, 'host-output-manifest.json'),
                                (SYNC_MANIFEST, 'managed-source-manifest.json')]:
        shutil.copyfile(repository / source, output / destination)
    shutil.copyfile(args.producer_receipt, output / 'producer-acceptance.json')
    shutil.copyfile(VALIDATOR_RECEIPT, output / 'validator-build-receipt.json')
    shutil.copyfile(RENDERER_RECEIPT, output / 'native-renderer-provenance.json')
    manifest = {
        'format_version': 1, 'source_commit': args.app_commit,
        'managed_source_commit': args.source_commit, 'repository': str(repository),
        'collected_utc': datetime.now(timezone.utc).isoformat(),
        'input_root': str(inputs), 'total': expected_total, 'engine_files': expected_engine, 'host_files': expected_host,
        'managed_source_files_verified': len(sync['files']),
        'producer_receipt_sha256': sha(output / 'producer-acceptance.json'),
        'engine_inventory_sha256': sha(output / 'engine-inventory.json'),
        'host_inventory_sha256': sha(output / 'host-inventory.json'),
        **runtime,
        'collection': 'Exact declared engine and actual host captures, frozen outside the application checkout.',
        'files': sorted(files, key=lambda item: item['path']),
    }
    write_json(output / 'input-manifest.json', manifest)
    verify_snapshot(output)
    started = time.monotonic()
    with (output / 'schema.log').open('w') as log:
        result = subprocess.run(['dotnet', str(VALIDATOR), str(inputs), str(output / 'schema-report.json')],
                                stdout=log, stderr=subprocess.STDOUT, check=False)
    summary = {
        'source_commit': args.app_commit, 'managed_source_commit': args.source_commit,
        'status': 'schema_receipt_verification_pending' if result.returncode == 0 else 'failed',
        'sdk_files': expected_total, 'engine_files': expected_engine, 'host_files': expected_host,
        'validator_exit_code': result.returncode,
        'schema_elapsed_seconds': time.monotonic() - started,
        'input_manifest_sha256': sha(output / 'input-manifest.json'),
        'native_status': 'pending',
    }
    write_json(output / 'external-summary.json', summary)
    require(result.returncode == 0, 'SDK process failed; preserved schema report and log')
    try:
        verify_schema(output)
    except (OSError, ValueError, KeyError) as error:
        summary.update({'status': 'failed', 'receipt_verification_error': str(error)})
        write_json(output / 'external-summary.json', summary)
        raise
    summary.update({'status': 'schema_passed_native_pending',
                    'sdk_passing_files': expected_total, 'sdk_failures': 0,
                    'all_schema_receipt_hashes_match': True,
                    'schema_report_sha256': sha(output / 'schema-report.json')})
    write_json(output / 'external-summary.json', summary)
    print(json.dumps(summary, indent=2))


def native(args):
    require_runtime_environment()
    output = args.output_root.resolve()
    manifest = verify_schema(output)
    repository = Path(manifest['repository'])
    require(runtime_receipt(repository)['native_conversion_script_sha256'] ==
            manifest['native_conversion_script_sha256'], 'Native gate changed after snapshot')
    host_inputs = output / 'host-inputs'
    host_inputs.mkdir(exist_ok=False)
    files = [item for item in manifest['files'] if item['producer_group'] == 'host']
    require(len(files) == manifest['host_files'], 'Missing actual-host captures')
    for item in files:
        original = Path(manifest['input_root']) / item['path']
        target = host_inputs / item['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
        require(sha(target) == item['sha256'], 'Native host staging changed bytes')
    command = [sys.executable, str(repository / 'tool/office-validation/render.py'),
               str(host_inputs), str(output / 'host-native')]
    with (output / 'host-native.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                check=False, timeout=1800)
    summary = read_json(output / 'external-summary.json')
    verify_schema(output)
    for item in files:
        require(sha(host_inputs / item['path']) == item['sha256'], 'Native input changed')
    report_path = output / 'host-native/render-report.json'
    report = read_json(report_path) if report_path.exists() else {}
    expected = {item['path'] for item in files}
    observed = {item['file'] for item in report.get('reports', [])}
    passed = (result.returncode == 0 and not report.get('failures', ['Missing report'])
              and report.get('files') == report.get('rendered_files') == len(files)
              and report.get('native_schema_only_files') == 0
              and len(report.get('reports', [])) == len(files) and observed == expected)
    summary.update({'status': 'passed' if passed else 'failed',
                    'native_status': 'passed' if passed else 'failed',
                    'native_command': command, 'native_exit_code': result.returncode,
                    'native_files': report.get('rendered_files', 0),
                    'native_pages': sum(row['pages'] for row in report.get('reports', [])),
                    'native_scope': 'Every actual-host capture, including DOCM/DOTX/DOTM, custom tabs and picture-only slides; full shared-engine rendering is separately required by source acceptance.',
                    'native_cycle_groups': report.get('cycle_groups', 0),
                    'native_failures': report.get('failures', ['Native report missing']),
                    'all_input_hashes_unchanged': True})
    if report_path.exists():
        summary['host_native_report_sha256'] = sha(report_path)
    write_json(output / 'external-summary.json', summary)
    print(json.dumps(summary, indent=2))
    require(passed, 'Host native acceptance failed; preserved all artifacts')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    commands = parser.add_subparsers(dest='command', required=True)
    collect = commands.add_parser('collect-schema')
    collect.add_argument('--producer-receipt', type=Path, required=True)
    collect.add_argument('--repository', type=Path, required=True)
    collect.add_argument('--app-commit', required=True)
    collect.add_argument('--source-commit', required=True)
    collect.add_argument('--output-root', type=Path, required=True)
    render = commands.add_parser('native')
    render.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    global RUNTIME, VALIDATOR, VALIDATOR_RECEIPT, RENDERER_RECEIPT
    RUNTIME = args.runtime.resolve()
    VALIDATOR = RUNTIME / 'validator/OfficeValidation.dll'
    VALIDATOR_RECEIPT = RUNTIME / 'validator/build-receipt.json'
    RENDERER_RECEIPT = RUNTIME / 'renderer-provenance.json'
    (collect_schema if args.command == 'collect-schema' else native)(args)


if __name__ == '__main__':
    main()

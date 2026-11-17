#!/usr/bin/env python3
"""Package compact, lossless setup evidence without modifying active inputs."""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess

QUDS = 'b87f9d6c3a2532c9695024adf48ca9fbd3c0927a'
HOST = '07083d1983db87a9868c3e8ba0cda1efd283b445'
FRAMEWORK = '737ba8f885dc774b53b442759999a312c9461e4e'
EXAMPLES = ['packages/quds_office_engine/example/' + name for name in
            ['pdf_widgets_invoice.dart', 'pdf_widgets_proposal.dart', 'pdf_widgets_report.dart']]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(data):
    return (json.dumps(data, indent=2, sort_keys=True) + '\n').encode()


def git(repo, *args):
    return subprocess.check_output(['git', '--no-replace-objects', '-C', str(repo), *args],
                                   env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'})


def selected(path):
    parts = Path(path).parts
    return bool(parts and parts[0] != 'docs' and (
        Path(path).name in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'} or
        (len(parts) >= 4 and parts[0] == 'packages' and parts[2] in {'lib', 'test', 'fonts', 'assets', 'third_party'}) or
        path.startswith('packages/quds_office_editor/example/lib/') or
        path.startswith('packages/quds_office_editor/example/test/')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workspace, output = args.workspace.resolve(), args.output.resolve()
    toolchain, audit = workspace / 'zotero-toolchain', workspace / 'recovery-audit'
    quds, host = workspace / 'quds-validation', workspace / 'crisp-validation'
    for protected in [toolchain, workspace / 'quds', workspace / 'crispcloud', quds, host]:
        assert not output.is_relative_to(protected), 'Publication must not write active inputs'
    output.mkdir(parents=True, exist_ok=True)
    source_references = []

    def write(name, data, compressed=False):
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(gzip.compress(data, mtime=0) if compressed else data)

    def snapshot(source, name, compressed=False):
        data = source.read_bytes()
        write(name, data, compressed)
        assert source.read_bytes() == data, f'Input changed while packaging: {source}'
        source_references.append({'artifact': name, 'source_workspace_path': str(source.relative_to(workspace)),
                                  'uncompressed_bytes': len(data), 'uncompressed_sha256': sha(data)})

    def git_snapshot(repo, repo_name, commit, source, name, compressed=False):
        data = git(repo, 'cat-file', 'blob', commit + ':' + source)
        oid = git(repo, 'rev-parse', commit + ':' + source).decode().strip()
        write(name, data, compressed)
        source_references.append({'artifact': name, 'repository': repo_name, 'commit': commit,
                                  'source_path': source, 'git_blob': oid,
                                  'uncompressed_bytes': len(data), 'uncompressed_sha256': sha(data)})

    for script in ['bootstrap-local-tests.sh', 'reconstruct-harnesses.py', 'record-setup.py']:
        git_snapshot(workspace / 'quds', 'CrispStrobe/quds_office_suite', QUDS,
                     'docs/validation/zotero-continuation-20261116/setup/' + script, 'scripts/' + script)
    git_snapshot(workspace / 'quds', 'CrispStrobe/quds_office_suite', QUDS,
                 'docs/validation/zotero-citing-20261115/setup-receipt.json', 'recorded-quds-setup-receipt.json.gz', True)
    git_snapshot(workspace / 'crispcloud', 'CrispStrobe/CrispCloud', HOST,
                 'docs/validation/zotero-citing-20261115/host-dependency-inputs.json', 'recorded-host-dependency-inputs.json.gz', True)
    for script in ['create-isolated-harnesses.py', 'link-pdf-widget-examples.py', 'build-setup-publication.py']:
        snapshot(audit / script, 'scripts/' + script)
    snapshot(toolchain / 'env.sh', 'recorded-environment.sh')
    snapshot(toolchain / 'setup-receipt-20261116.json', 'setup-receipt-20261116.json.gz', True)
    snapshot(toolchain / 'reconstruction-inputs.json', 'reconstruction-inputs.json')
    snapshot(toolchain / 'recovery-prestage/runtime-download.json', 'runtime-download.json')
    snapshot(toolchain / 'recovery-prestage/harness-assets.json', 'harness-assets.json')
    snapshot(audit / 'retry-harness-setup.json', 'retry-harness-setup.json.gz', True)
    snapshot(audit / 'pdf-widget-example-links.json', 'pdf-widget-example-links.json')
    snapshot(audit / 'quds/sparse-setup-missing.json', 'sparse-manifest-correction.json')
    adjustment = toolchain / 'expanded-canonical-qualification/attempt-2-executor-interruption/harness-metadata-adjustment.json'
    snapshot(adjustment, 'harness-metadata-adjustment.json')
    adjustment_data = json.loads(adjustment.read_text())
    engine_graph = toolchain / 'harness/quds_office_engine/.dart_tool/package_config.json'
    warmed = engine_graph.read_bytes()
    restored = b''.join(line for line in warmed.splitlines(keepends=True)
                        if not line.lstrip().startswith((b'"flutterRoot":', b'"flutterVersion":')))
    assert sha(warmed) == adjustment_data['current_sha256']
    assert sha(restored) == adjustment_data['expected_original_sha256']

    isolation = json.loads((audit / 'retry-harness-setup.json').read_text())
    inputs = {}
    for item in isolation['copied_files']:
        for key, hash_key in [('source', 'source_sha256'), ('destination', 'destination_sha256')]:
            name = item[key]
            data = (workspace / name).read_bytes()
            assert sha(data) == item[hash_key], f'Prepared wrapper input changed: {name}'
            inputs[name] = {'sha256': sha(data), 'bytes': len(data), 'text': data.decode()}
    write('harness-inputs.json.gz', json_bytes({'schema_version': 1, 'inputs': inputs,
          'scope': 'Exact warmed original and isolated wrapper manifests, locks and package graphs. No compiled caches.'}), True)

    baseline = json.loads((toolchain / 'setup-receipt-20261116.json').read_text())
    sdk = toolchain / 'flutter-sdk'
    assert git(sdk, 'rev-parse', 'HEAD').decode().strip() == FRAMEWORK
    sdk_status = git(sdk, 'status', '--porcelain', '--untracked-files=no').decode().strip()
    assert not sdk_status
    runtime = {}
    for name, expected in baseline['sdk_artifacts'].items():
        data = (sdk / name).read_bytes()
        assert sha(data) == expected['sha256'], f'Runtime changed from setup: {name}'
        runtime[name] = {'bytes': len(data), 'sha256': sha(data), 'matches_setup_receipt': True}
    write('runtime-verification.json', json_bytes({
        'recorded_utc': datetime.now(timezone.utc).isoformat(), 'framework_commit': FRAMEWORK,
        'sdk_tracked_status': sdk_status, 'runtime': json.loads((sdk / 'bin/cache/flutter.version.json').read_text()),
        'sdk_artifacts': runtime, 'platform': {'system': platform.system(), 'machine': platform.machine()},
        'checked_without_runtime_mutation': True,
    }))
    sdk_inputs = {}
    for name in ['packages/flutter_tools/pubspec.yaml', 'packages/flutter_tools/pubspec.lock',
                 'packages/flutter_tools/.dart_tool/package_config.json', 'packages/flutter_tools/.dart_tool/package_graph.json']:
        path = sdk / name
        if path.is_file():
            data = path.read_bytes()
            sdk_inputs[name] = {'sha256': sha(data), 'bytes': len(data), 'text': data.decode()}
    write('sdk-tool-inputs.json.gz', json_bytes({'framework_commit': FRAMEWORK, 'inputs': sdk_inputs}), True)

    tree = {}
    for row in git(quds, 'ls-tree', '-r', '-z', QUDS).split(b'\0'):
        if row:
            metadata, path = row.split(b'\t', 1)
            tree[path.decode()] = metadata.split()[2].decode()
    initial = sorted(path for path in tree if selected(path))
    assert len(initial) == 1565
    full_selection = sorted(set(initial) | set(EXAMPLES))
    assert len(full_selection) == 1568
    hashes = {}
    for name in full_selection:
        data = (quds / name).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        assert blob == tree[name], name
        hashes[name] = sha(data)
    initial_hashes = {name: hashes[name] for name in initial}
    initial_aggregate = sha(json.dumps(initial_hashes, sort_keys=True).encode())
    assert initial_aggregate == isolation['canonical_source']['selected_input_sha256_aggregate']
    host_manifest_bytes = git(host, 'cat-file', 'blob', HOST + ':tool/office_fidelity_manifest.json')
    host_manifest = json.loads(host_manifest_bytes)
    assert len(host_manifest['files']) == 2509 and host_manifest['source_commit'] == QUDS
    write('source-maps.json.gz', json_bytes({
        'canonical_commit': QUDS, 'host_commit': HOST,
        'initial_isolation_count': len(initial), 'initial_isolation_aggregate_sha256': initial_aggregate,
        'complete_run_canonical_count': len(full_selection), 'complete_run_canonical_sha256_by_path': hashes,
        'complete_run_canonical_git_blob_by_path': {path: tree[path] for path in full_selection},
        'complete_run_additional_source_files': EXAMPLES,
        'host_manifest_git_blob': git(host, 'rev-parse', HOST + ':tool/office_fidelity_manifest.json').decode().strip(),
        'host_managed_sha256_by_path': host_manifest['files'],
        'host_manifest_sha256': sha(host_manifest_bytes),
        'scope': 'Source/setup inputs only; test execution and complete before/after qualification receipts are separate.',
    }), True)

    statuses = {'dart-sdk-download.log': 0, 'flutter-version.log': 0, 'engine-pub-get.log': 0,
                'quds_office_editor-pub-get.log': 0, 'quds_office_studio-pub-get.log': 0, 'host-pub-get.log': 0,
                'initial-prestage-engine-pub-get.log': 127, 'initial-example-link-engine-pub-get.log': 66,
                'initial-prestage-flutter-version.log': 130}
    logs = {}
    for path in sorted((toolchain / 'logs').glob('*.log')):
        data = path.read_bytes()
        logs[path.name] = {'bytes': len(data), 'sha256': sha(data), 'text': data.decode(),
                           'observed_process_exit_code': statuses.get(path.name),
                           'scope': 'Setup only; not a qualification-test result.'}
    write('setup-logs.json.gz', json_bytes({'logs': logs,
          'missing_raw_console_events': ['The initial HTTP/2 framework clone error and the initial conservative zip-path assertion were observed in the tool transcript but have no separate raw log file.']}), True)
    write('source-references.json', json_bytes({'sources': source_references,
          'implementation_pins_are_explicit': True,
          'original_checkout_documentation_heads_not_used_as_implementation_pins': True,
          'github_actions_queried_awaited_or_rerun': False}))

    for path in (output / 'scripts').glob('*.py'):
        ast.parse(path.read_text(), filename=str(path))
    for path in (output / 'scripts').glob('*.sh'):
        subprocess.run(['bash', '-n', str(path)], check=True)
    inventory = {}
    for path in sorted(output.rglob('*')):
        if path.is_file() and path.name != 'artifact-index.json':
            data = path.read_bytes()
            if path.suffix == '.gz':
                json.loads(gzip.decompress(data))
            inventory[str(path.relative_to(output))] = {'bytes': len(data), 'sha256': sha(data)}
    write('artifact-index.json', json_bytes({'schema_version': 1,
          'recorded_utc': datetime.now(timezone.utc).isoformat(), 'algorithm': 'sha256',
          'self_excluded': 'artifact-index.json', 'files': inventory,
          'file_count_excluding_index': len(inventory), 'total_bytes_excluding_index': sum(v['bytes'] for v in inventory.values()),
          'python_scripts_parse': True, 'shell_scripts_syntax_check': True, 'gzip_json_roundtrip': True,
          'active_source_runtime_harness_and_cache_writes': False}))
    print(json.dumps({'output': str(output), 'files_excluding_index': len(inventory),
                      'bytes_excluding_index': sum(v['bytes'] for v in inventory.values()),
                      'harness_input_files': len(inputs), 'source_inputs': len(full_selection),
                      'host_managed_files': len(host_manifest['files']), 'source_runtime_or_harness_writes': False}, indent=2))


if __name__ == '__main__':
    main()

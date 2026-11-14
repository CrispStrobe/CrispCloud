#!/usr/bin/env python3
"""Audit preserved Office evidence; does not rerun Flutter, Office or Chrome."""
import argparse
import ast
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import struct
import subprocess
from zipfile import ZipFile

from PIL import Image

SUITE_EVIDENCE_COMMIT = '41072ce7fac74eb54cdbc5e3803a45e605533b06'
APP_MEASURED_COMMIT = '05905b86ca3a7fc8db3df131620842da3e134061'
APP_INTEGRATED_COMMIT = '2316efe611663e08ebdde8786e9bb3fef280bf40'
EVIDENCE = 'docs/evidence/office-recovery-20261114'
GENERATED_INPUTS = {
    '.dart_tool/package_config.json', '.dart_tool/package_graph.json',
    'packages/quds_office_engine/.dart_tool/package_config.json',
    'packages/quds_office_engine/.dart_tool/package_graph.json',
    'packages/quds_office_engine/pubspec.lock',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def blob(root, commit, path):
    return git(root, 'cat-file', 'blob', f'{commit}:{path}')


def verify_zip(raw, manifest):
    archive = ZipFile(io.BytesIO(raw))
    names = archive.namelist()
    require(len(names) == len(set(names)), 'Duplicate archive entries')
    require(set(names) == set(manifest) | {'archive-manifest.json'},
            'Archive entry inventory differs from manifest')
    require(archive.testzip() is None, 'ZIP CRC failed')
    for name, item in manifest.items():
        data = archive.read(name)
        require(len(data) == item['bytes'] and digest(data) == item['sha256'],
                f'Archive content mismatch: {name}')
    return archive


def pixel_fingerprint(data):
    with Image.open(io.BytesIO(data)) as source:
        image = source.convert('RGB')
        return digest(struct.pack('>II', *image.size) + image.tobytes())


def verify_render(archive):
    report = json.loads(archive.read('render/render-report.json'))
    require(report['files'] == report['rendered_files'] == 16,
            'Expected all sixteen rendered inputs')
    require(not report['failures'], 'Saved renderer reported failures')
    records = {item['file']: item for item in report['reports']}
    require(len(records) == 16, 'Duplicate/missing render records')
    for item in records.values():
        require(digest(archive.read('render-inputs/' + item['file'])) ==
                item['input_sha256'], 'Render input mismatch')
        require(item['pages'] == len(item['page_artifacts']), 'Page inventory mismatch')
        computed = []
        for page in item['page_artifacts']:
            value = pixel_fingerprint(archive.read('render/' + page['png']))
            require(value == page['pixel_sha256'], 'Decoded PNG fingerprint mismatch')
            computed.append(value)
        require(computed == item['pixel_sha256'], 'Page fingerprints differ')
        text_path = 'render/' + str(PurePosixPath(item['pdf']).parent / 'text.txt')
        require(archive.read(text_path).decode() == item['text'], 'Saved text mismatch')
    groups = [
        [f'fidelity-host/native-{kind}-{cycle}{ext}' for cycle in (1, 2, 3)] +
        [f'fidelity-host/reference/native-{kind}-expected{ext}']
        for kind, ext in [('word', '.docx'), ('sheet', '.xlsx'), ('slide', '.pptx')]]
    groups.append([f'fidelity-schema/namespace-style-{cycle}.xlsx'
                   for cycle in (1, 2, 3)] +
                  ['fidelity-schema/namespace-style-reference.xlsx'])
    for names in groups:
        values = [(records[name]['pages'], records[name]['text'],
                   records[name]['pixel_sha256']) for name in names]
        require(all(value == values[0] for value in values),
                f'Saved first-save/cycle comparison differs: {names[0]}')
    return {'render_inputs': len(records), 'equal_cycle_and_reference_groups': len(groups)}


def verify_source(app, restored, collected, source):
    require(len(restored) == len(collected) == 4732, 'Input count differs')
    require(set(restored) == set(collected), 'Collected/restored inputs differ')
    require([key for key in restored if restored[key] != collected[key]] ==
            ['pubspec.yaml'], 'Unexpected test-view source modifications')
    for snapshot, key in [(restored, 'restored_input_tree_sha256'),
                          (collected, 'collected_input_tree_sha256')]:
        require(digest(json.dumps(snapshot, sort_keys=True).encode()) == source[key],
                f'Input tree digest differs: {key}')
    tree = {}
    for row in git(app, 'ls-tree', '-r', '-z', APP_MEASURED_COMMIT).split(b'\0'):
        if row:
            metadata, path = row.split(b'\t', 1)
            mode, kind, oid = metadata.split()
            if kind == b'blob':
                tree[path.decode()] = oid.decode()
    generated, verified = set(), 0
    for name, expected in restored.items():
        path = PurePosixPath(name)
        require(not path.is_absolute() and '..' not in path.parts, 'Invalid source path')
        if name not in tree:
            generated.add(name)
            continue
        local = app / name
        data = local.read_bytes() if local.is_file() else b''
        oid = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if oid != tree[name]:
            data = git(app, 'cat-file', 'blob', tree[name])
        require(digest(data) == expected, f'Measured source mismatch: {name}')
        verified += 1
    require(generated == GENERATED_INPUTS, 'Unexpected untracked source inputs')
    wrapper = blob(app, APP_MEASURED_COMMIT, 'tool/with_ci_system_sqlite.py')
    hook = next(ast.literal_eval(node.value) for node in ast.parse(wrapper).body
                if isinstance(node, ast.Assign) and any(
                    isinstance(target, ast.Name) and target.id == 'HOOK'
                    for target in node.targets))
    pubspec = blob(app, APP_MEASURED_COMMIT, 'pubspec.yaml')
    require(digest(pubspec.rstrip(b'\r\n') + b'\n' + hook) == collected['pubspec.yaml'],
            'SQLite test-view transformation differs')
    return {'snapshot_inputs': len(restored), 'verified_tracked_inputs': verified,
            'untracked_inputs_with_hash_only': sorted(generated),
            'sqlite_test_view_reconstructed': True}


def audit(suite, app):
    read = lambda path: blob(suite, SUITE_EVIDENCE_COMMIT, EVIDENCE + '/' + path)
    suite_receipt = json.loads(read('suite-validation.json'))
    for name, expected in suite_receipt['evidence_sha256'].items():
        require(digest(read(name)) == expected, f'Suite evidence hash differs: {name}')
    external = json.loads(read('external/external-validation.json'))
    require(external['source']['app_commit'] == APP_MEASURED_COMMIT,
            'Unexpected measured app identity')
    for name, expected in external['reports_sha256'].items():
        require(digest(read('external/' + name)) == expected, f'Report hash differs: {name}')
    archive_bytes = read('external/external-artifacts.zip')
    require(digest(archive_bytes) == external['archive']['sha256'], 'Archive hash differs')
    manifest_bytes = read('external/archive-manifest.json')
    manifest = json.loads(manifest_bytes)
    with verify_zip(archive_bytes, manifest) as archive:
        require(archive.read('archive-manifest.json') == manifest_bytes,
                'Embedded archive manifest differs')
        inventory = json.loads(archive.read('host-inventory.json'))
        require(inventory['expected'] == inventory['verified'] == 149 and
                not inventory['failures'], 'Incomplete saved host inventory')
        require(len(inventory['files']) == 149, 'Host inventory count differs')
        for item in inventory['files']:
            require(digest(archive.read('schema-inputs/host/' + item['path'])) ==
                    item['sha256'], 'Saved host package differs from inventory')
        for name, prefix, count in [('host-schema-report.json', 'schema-inputs/host/', 149),
                                    ('namespace-schema-report.json', 'schema-inputs/namespace/', 4)]:
            report = json.loads(archive.read(name))
            require(report['Files'] == count and len(report['Reports']) == count and
                    not report['Failures'], 'Incomplete schema report')
            seen = set()
            for item in report['Reports']:
                path = prefix + item['File'].split('/' + prefix, 1)[1]
                require(path not in seen and not item['Errors'] and
                        digest(archive.read(path)) == item['Sha256'], 'Schema input binding differs')
                seen.add(path)
        rendering = verify_render(archive)
        collection = json.loads(archive.read('host-collection-receipt.json'))
        require(collection['status'] == 'complete' and collection['returncode'] == 0,
                'Historical collection did not finish')
        source = verify_source(app, json.loads(archive.read('restored-source-snapshot.json')),
                               collection['input_sha256'], external['source'])
        require(digest(archive.read('host-collection-receipt.json')) ==
                external['source']['collection_receipt_sha256'], 'Collection receipt differs')
        require(not any(name.endswith('/lcov.info') or name == 'lcov.info'
                        for name in archive.namelist()), 'Update audit: raw LCOV is now present')
    integrated_path = EVIDENCE + '/integrated-macos/'
    acceptance = json.loads(blob(app, APP_INTEGRATED_COMMIT, integrated_path + 'acceptance.json'))
    for name, expected in acceptance['reports'].items():
        require(digest(blob(app, APP_INTEGRATED_COMMIT, integrated_path + name)) == expected,
                f'Integrated receipt hash differs: {name}')
    browser = json.loads(blob(app, APP_INTEGRATED_COMMIT, integrated_path + 'browser-copy-receipt.json'))
    for key, path in [('entrypoint_sha256', browser['entrypoint']),
                      ('wrapper_sha256', 'lib/services/office_device_export.dart'),
                      ('adapter_sha256', 'lib/services/office_device_export_web.dart')]:
        require(digest(blob(app, acceptance['host_checkpoint'], path)) == browser[key],
                f'Browser source binding differs: {path}')
    return {
        'schema_version': 1, 'status': 'passed',
        'scope': 'Historical archive integrity, source binding and saved pixel/text replay only',
        'suite_evidence_commit': SUITE_EVIDENCE_COMMIT,
        'measured_app_commit': APP_MEASURED_COMMIT,
        'integrated_evidence_commit': APP_INTEGRATED_COMMIT,
        'suite_supporting_hashes_verified': len(suite_receipt['evidence_sha256']),
        'external_report_hashes_verified': len(external['reports_sha256']),
        'external_archive_sha256': digest(archive_bytes),
        'external_archive_entries_verified': len(manifest),
        'host_inventory_bindings_verified': 149,
        'historical_schema_report_bindings': {'host': 149, 'namespace': 4},
        'saved_render_replay': rendering,
        'historical_source_binding': source,
        'integrated_report_hashes_verified': len(acceptance['reports']),
        'integrated_browser_source_hashes_verified': 3,
        'limits': [
            'No Flutter tests, schema validator, LibreOffice conversion or browser were rerun.',
            'Historical LCOV and full host test log were not preserved in this archive.',
            'Historical test totals and coverage percentages were not recalculated.',
            'Results do not certify the current branch or physical-device/live-provider behavior.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite-root', type=Path, required=True)
    parser.add_argument('--app-root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = json.dumps(audit(args.suite_root.resolve(), args.app_root.resolve()), indent=2) + '\n'
    if args.output:
        args.output.write_text(result)
    print(result, end='')


if __name__ == '__main__':
    main()

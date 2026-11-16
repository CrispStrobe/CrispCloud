#!/usr/bin/env python3
"""Copy genuine resolved wrappers to fresh source worktrees without running pub.

Only manifests, locks, package graphs and source symlinks are copied. Compiled
test/build caches are excluded. Existing wrappers, the SDK and cache are read
only. The copied engine graph retains its already warmed Flutter metadata.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
from urllib.parse import unquote, urljoin, urlparse


QUDS = 'b87f9d6c3a2532c9695024adf48ca9fbd3c0927a'
HOST = '07083d1983db87a9868c3e8ba0cda1efd283b445'
GRAPHS = {'package_config.json', 'package_graph.json'}
MANIFESTS = {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(repo, *args):
    return subprocess.check_output(['git', '--no-replace-objects', '-C', str(repo), *args],
                                   env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'})


def resolve_uri(config, uri):
    parsed = urlparse(urljoin(config.as_uri(), uri))
    if parsed.scheme != 'file' or parsed.netloc not in {'', 'localhost'}:
        raise ValueError(f'Expected local package root: {uri}')
    return Path(unquote(parsed.path)).resolve()


def source_input(path):
    parts = Path(path).parts
    if not parts or parts[0] == 'docs':
        return False
    return (Path(path).name in MANIFESTS or
            (len(parts) >= 4 and parts[0] == 'packages' and
             parts[2] in {'lib', 'test', 'fonts', 'assets', 'third_party'}) or
            path.startswith('packages/quds_office_editor/example/lib/') or
            path.startswith('packages/quds_office_editor/example/test/'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    toolchain = workspace / 'zotero-toolchain'
    quds, host = workspace / 'quds-validation', workspace / 'crisp-validation'
    for repo, commit in [(quds, QUDS), (host, HOST)]:
        assert git(repo, 'rev-parse', 'HEAD').decode().strip() == commit
        assert not git(repo, 'status', '--porcelain', '--untracked-files=no').strip()
    pairs = [
        (toolchain / 'harness', toolchain / 'retry-harness'),
        (toolchain / 'crisp-host-harness', toolchain / 'crisp-host-retry'),
    ]
    for _, new in pairs:
        assert not new.exists(), f'Refusing to replace an existing wrapper: {new}'
    mapping = [*pairs,
               (workspace / 'quds_office_suite', quds), (workspace / 'quds', quds),
               (workspace / 'CrispCloud', host), (workspace / 'crispcloud', host)]
    mapping.sort(key=lambda pair: len(str(pair[0])), reverse=True)
    replacements = {str(before): str(after) for before, after in mapping}
    replacement_pattern = re.compile('|'.join(re.escape(path) for path in replacements))

    def mapped(path):
        for before, after in mapping:
            if path == before or path.is_relative_to(before):
                return after / path.relative_to(before)
        return path

    def rebase(value):
        return replacement_pattern.sub(lambda match: replacements[match[0]], value)

    files, links, skipped, graph_checks, original_bytes = [], [], [], [], {}

    def copy_file(old, new):
        data = old.read_bytes()
        original_bytes[str(old)] = data
        new.parent.mkdir(parents=True, exist_ok=True)
        payload = rebase(data.decode()).encode()
        if old.name == 'package_config.json':
            original_graph = json.loads(data)
            copied_graph = json.loads(payload)
            changed_uris = []
            assert len(original_graph['packages']) == len(copied_graph['packages'])
            for original, copied in zip(original_graph['packages'], copied_graph['packages']):
                assert original['name'] == copied['name']
                expected = mapped(resolve_uri(old, original['rootUri']))
                if resolve_uri(new, copied['rootUri']) != expected:
                    copied['rootUri'] = expected.as_uri() + '/'
                assert resolve_uri(new, copied['rootUri']) == expected
                assert {k: v for k, v in original.items() if k != 'rootUri'} == {k: v for k, v in copied.items() if k != 'rootUri'}
                assert expected.is_dir(), (original['name'], expected)
                if original['rootUri'] != copied['rootUri']:
                    changed_uris.append({'package': original['name'], 'before': original['rootUri'], 'after': copied['rootUri']})
            # Retain all top-level metadata; only the wrappers' local roots move.
            assert {k: v for k, v in original_graph.items() if k != 'packages'} == {k: v for k, v in copied_graph.items() if k != 'packages'}
            assert copied_graph.get('flutterRoot') == (toolchain / 'flutter-sdk').as_uri()
            assert copied_graph.get('flutterVersion') == '3.47.8'
            # Keep byte identity if no normalization was needed beyond rebasing.
            if json.loads(payload) != copied_graph:
                payload = (json.dumps(copied_graph, indent=2) + '\n').encode()
            graph_checks.append({'path': str(new.relative_to(workspace)),
                                 'package_count': len(copied_graph['packages']),
                                 'only_local_roots_rebased': True, 'metadata_preserved': True,
                                 'flutter_metadata_already_present': True,
                                 'changed_package_root_uris': changed_uris})
        new.write_bytes(payload)
        before_stat = old.stat()
        os.chmod(new, stat.S_IMODE(before_stat.st_mode))
        os.utime(new, ns=(before_stat.st_atime_ns, before_stat.st_mtime_ns))
        if old.name != 'package_config.json':
            assert payload == rebase(data.decode()).encode()
        files.append({'source': str(old.relative_to(workspace)), 'destination': str(new.relative_to(workspace)),
                      'source_sha256': digest(data), 'destination_sha256': digest(payload),
                      'byte_identical': payload == data, 'path_rebase_only': True})

    def copy_tree(old, new, graph_directory=False):
        new.mkdir(parents=True, exist_ok=True)
        # Make directory roots before graphs are validated against them.
        for item in sorted(old.iterdir()):
            if item.is_dir() and not item.is_symlink() and item.name not in {'build', '.dart_tool'}:
                (new / item.name).mkdir(exist_ok=True)
        for item in sorted(old.iterdir()):
            destination = new / item.name
            if item.is_symlink():
                target = mapped(item.resolve())
                destination.symlink_to(target, target_is_directory=item.is_dir())
                links.append({'source': str(item.relative_to(workspace)), 'destination': str(destination.relative_to(workspace)),
                              'old_target': str(item.resolve()), 'new_target': str(target)})
            elif item.is_dir():
                if item.name == 'build':
                    skipped.append(str(item.relative_to(workspace)))
                elif item.name == '.dart_tool':
                    destination.mkdir(exist_ok=True)
                    for graph in sorted(item.iterdir()):
                        if graph.is_file() and graph.name in GRAPHS:
                            copy_file(graph, destination / graph.name)
                        else:
                            skipped.append(str(graph.relative_to(workspace)))
                else:
                    copy_tree(item, destination)
            elif item.name in MANIFESTS:
                copy_file(item, destination)
            else:
                skipped.append(str(item.relative_to(workspace)))

    def prepare_directories(before, after):
        after.mkdir(parents=True, exist_ok=True)
        for item in before.iterdir():
            if item.is_dir() and not item.is_symlink() and item.name not in {'build', '.dart_tool'}:
                prepare_directories(item, after / item.name)

    # All local package wrapper roots must exist before a graph references them.
    for before, after in pairs:
        prepare_directories(before, after)
    for before, after in pairs:
        copy_tree(before, after)

    for original, data in original_bytes.items():
        assert Path(original).read_bytes() == data, f'Original input changed during copy: {original}'
    for before, after in pairs:
        for path in after.rglob('*'):
            if path.is_symlink():
                continue
            assert path.name not in {'build', '.test_cache'}, path
        for config in after.rglob('package_config.json'):
            if config.is_symlink():
                continue
            graph = json.loads(config.read_text())
            for entry in graph['packages']:
                root = resolve_uri(config, entry['rootUri'])
                assert not root.is_relative_to(before), (entry['name'], root)

    expected = {}
    for row in git(quds, 'ls-tree', '-r', '-z', QUDS).split(b'\0'):
        if row:
            meta, name = row.split(b'\t', 1)
            expected[name.decode()] = meta.split()[2].decode()
    selected = sorted(path for path in expected if source_input(path))
    assert len(selected) == 1565, len(selected)
    hashes = {}
    for path in selected:
        data = (quds / path).read_bytes()
        actual_blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        assert actual_blob == expected[path], path
        hashes[path] = digest(data)
    host_manifest = json.loads((host / 'tool/office_fidelity_manifest.json').read_text())
    for path, expected_hash in host_manifest['files'].items():
        assert digest((host / path).read_bytes()) == expected_hash, path

    # Required library/fixture links must resolve to the fresh source worktrees.
    for name in ['legacy_doc_parser', 'quds_office_engine', 'quds_reports', 'quds_office_editor']:
        for kind in ['lib', 'test']:
            assert (toolchain / 'retry-harness' / name / kind).resolve() == (quds / 'packages' / name / kind)
        assert (toolchain / 'crisp-host-retry/packages' / name / 'lib').resolve() == (host / 'packages' / name / 'lib')
    assert (toolchain / 'retry-harness/quds_office_editor/fonts').resolve() == quds / 'packages/quds_office_editor/fonts'
    assert (toolchain / 'retry-harness/quds_office_engine/third_party').resolve() == quds / 'packages/quds_office_engine/third_party'
    for name in ['office_zotero_test.dart', 'office_zotero_citing_transport_test.dart', 'office_zotero_ribbon_test.dart', 'office_proofing_licenses_test.dart']:
        assert (toolchain / 'crisp-host-retry/test' / name).resolve() == host / 'test' / name
    assert (toolchain / 'crisp-host-retry/packages/quds_office_engine/third_party').resolve() == host / 'packages/quds_office_engine/third_party'

    receipt = {
        'recorded_utc': datetime.now(timezone.utc).isoformat(),
        'canonical_source': {'directory': str(quds), 'commit': QUDS, 'selected_inputs': len(selected),
                             'selected_input_sha256_aggregate': digest(json.dumps(hashes, sort_keys=True).encode()),
                             'all_selected_inputs_present_and_match_git_blobs': True,
                             'studio_app_manifests_present': all((quds / 'apps/quds_report_studio' / name).is_file() for name in ['pubspec.yaml', 'analysis_options.yaml'])},
        'host_source': {'directory': str(host), 'commit': HOST, 'managed_files_verified': len(host_manifest['files'])},
        'wrappers': {'canonical': str(toolchain / 'retry-harness'), 'host': str(toolchain / 'crisp-host-retry')},
        'copied_files': files, 'source_links': links, 'package_graph_checks': graph_checks,
        'excluded_old_cache_or_other_paths': sorted(skipped),
        'original_copied_inputs_unchanged_during_setup': True,
        'dependency_versions_and_nonpath_graph_metadata_unchanged': True,
        'compiled_test_and_build_caches_copied': False,
        'pub_get_or_tests_run': False,
        'sdk_cache_and_old_harness_writes': False,
        'runner_environment': str(toolchain / 'env.sh'),
        'script_sha256': digest(Path(__file__).read_bytes()),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps({k: receipt[k] for k in ['canonical_source', 'host_source', 'wrappers', 'package_graph_checks',
                                            'compiled_test_and_build_caches_copied', 'pub_get_or_tests_run',
                                            'sdk_cache_and_old_harness_writes']}, indent=2))


if __name__ == '__main__':
    main()

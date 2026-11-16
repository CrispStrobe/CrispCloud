#!/usr/bin/env python3
"""Qualify the real vendored Zotero host with an already locked local harness.

No dependencies, production manifests or tracked source are rewritten. The
temporary host analyzer graph resolves genuine dependencies from the harness.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse

PACKAGES = ('quds_office_engine', 'quds_office_editor', 'quds_reports', 'legacy_doc_parser')
TESTS = (
    'test/office_zotero_test.dart',
    'test/office_zotero_citing_transport_test.dart',
    'test/office_zotero_ribbon_test.dart',
    'test/office_proofing_licenses_test.dart',
)
HOST_TARGETS = (
    'lib/services/office_zotero.dart',
    'lib/services/office_zotero_transport.dart',
    'lib/services/office_proofing_licenses.dart',
    'lib/l10n/office_zotero_strings.dart',
    *TESTS,
)
VENDORED_TARGETS = (
    'packages/quds_office_engine/lib/src/word/model/word_zotero.dart',
    'packages/quds_office_engine/lib/src/zotero/zotero_client.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_format.dart',
)
TOOL_INPUTS = (
    'tool/sync_office_fidelity.py', 'tool/verify_office_fidelity.py',
    'tool/sync_legacy_doc_parser.py', 'tool/test_sync_office_fidelity.py',
    'tool/test_sync_legacy_doc_parser.py',
)


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def aggregate(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()


def resolve(config, uri):
    parsed = urlparse(urljoin(config.as_uri(), uri))
    if parsed.scheme != 'file' or parsed.netloc:
        raise ValueError(f'Expected an existing local dependency: {uri}')
    return Path(unquote(parsed.path)).resolve()


def source_snapshot(repo):
    manifest = json.loads((repo / 'tool/office_fidelity_manifest.json').read_text())
    names = set(manifest['files']) | set(TESTS) | set(TOOL_INPUTS)
    names.add('tool/office_fidelity_manifest.json')
    for path in (repo / 'lib').rglob('*'):
        if path.is_file():
            names.add(str(path.relative_to(repo)))
    for base in (repo, *(repo / 'packages' / name for name in PACKAGES)):
        for filename in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'):
            path = base / filename
            if path.is_file():
                names.add(str(path.relative_to(repo)))
    return {name: digest((repo / name).read_bytes()) for name in sorted(names)}


def dependency_snapshot(harness, flutter, repo):
    config = harness / '.dart_tool/package_config.json'
    graph = json.loads(config.read_text())
    files = {'.dart_tool/package_config.json': digest(config.read_bytes())}
    roots = {}
    declarations = {}
    for base_name, base in [('harness', harness), *[(f'harness/packages/{name}', harness / 'packages' / name) for name in PACKAGES]]:
        for filename in ('pubspec.yaml', 'pubspec.lock'):
            path = base / filename
            if path.is_file():
                declarations[f'{base_name}/{filename}'] = {'sha256': digest(path.read_bytes()), 'text': path.read_text()}
    for entry in graph['packages']:
        name = entry['name']
        root = resolve(config, entry['rootUri'])
        library = (root / entry.get('packageUri', 'lib/')).resolve()
        if not root.is_dir():
            raise ValueError(f'Missing resolved dependency root for {name}: {root}')
        expected = repo / 'lib' if name == 'crisp_cloud' else (repo / 'packages' / name / 'lib' if name in PACKAGES else None)
        if expected is not None and not library.samefile(expected):
            raise ValueError(f'{name} does not resolve to the actual host source')
        # Native-only plugin metadata packages legitimately have no Dart lib/.
        roots[name] = {'root': str(root), 'library': str(library), 'has_dart_library': library.is_dir(),
                       'language_version': entry.get('languageVersion')}
        for path in sorted(library.rglob('*')):
            if path.is_file():
                files[f'{name}/lib/{path.relative_to(library)}'] = digest(path.read_bytes())
        for filename in ('pubspec.yaml', 'analysis_options.yaml', 'LICENSE'):
            path = root / filename
            if path.is_file():
                files[f'{name}/{filename}'] = digest(path.read_bytes())
    runtime = {}
    for name in ('bin/cache/dart-sdk/bin/dart', 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                 'bin/cache/flutter_tools.snapshot', 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
                 'bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill',
                 'bin/cache/flutter.version.json'):
        path = flutter / name
        if path.is_file():
            runtime[name] = digest(path.read_bytes())
    return {'package_count': len(roots), 'package_roots': roots, 'declarations': declarations,
            'dependency_files': files, 'runtime_files': runtime}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--harness', required=True, type=Path)
    parser.add_argument('--quds-source', required=True, type=Path)
    parser.add_argument('--expected-quds', required=True)
    parser.add_argument('--published-source', required=True)
    parser.add_argument('--expected-tree', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    repo, harness, quds, output = (path.resolve() for path in (args.repo, args.harness, args.quds_source, args.output))
    flutter = Path(os.environ['FLUTTER_ROOT']).resolve()
    dart = flutter / 'bin/cache/dart-sdk/bin/dart'
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((repo / 'tool/office_fidelity_manifest.json').read_text())
    if manifest['source_commit'] != args.expected_quds:
        raise ValueError('Host manifest does not match the requested canonical source')
    initial_tree = git(repo, 'rev-parse', 'HEAD^{tree}')
    if initial_tree != args.expected_tree:
        raise ValueError('Actual starting source tree differs from the published implementation tree')
    source_before = source_snapshot(repo)
    deps_before = dependency_snapshot(harness, flutter, repo)
    save(output / 'source-before.json', source_before)
    save(output / 'dependencies-before.json', deps_before)
    receipt = {
        'schema_version': 1, 'repository': 'CrispStrobe/CrispCloud', 'started_utc': now(),
        'head_at_start': git(repo, 'rev-parse', 'HEAD'), 'published_source': args.published_source,
        'implementation_tree': initial_tree, 'expected_canonical_source': args.expected_quds,
        'managed_office_files': len(manifest['files']), 'tests': list(TESTS), 'expected_test_count': 41,
        'host_analysis_targets': list(HOST_TARGETS), 'vendored_analysis_targets': list(VENDORED_TARGETS),
        'source_file_count': len(source_before), 'dependency_file_count': len(deps_before['dependency_files']),
        'dependency_package_count': deps_before['package_count'], 'pub_get_rerun': False,
        'source_before_aggregate_sha256': aggregate(source_before), 'dependencies_before_aggregate_sha256': aggregate(deps_before),
        'reproduction_script_sha256': digest(Path(__file__).read_bytes()), 'commands': [],
        'runtime': json.loads((flutter / 'bin/cache/flutter.version.json').read_text()),
        'limitations': ['Focused genuine locked dependency graph; no full application compile or full production dependency resolution.',
                       'Network, credentials and protocol interactions use test doubles; no live Zotero account, desktop picker, Word/LibreOffice or keychain acceptance.',
                       'Canonical tests are qualified separately; these counts are distinct host tests.',
                       'No GitHub Actions, status, workflow or job queries, waits or reruns.'],
    }
    config = harness / '.dart_tool/package_config.json'
    analyzer_graph = json.loads(config.read_text())
    for entry in analyzer_graph['packages']:
        name = entry['name']
        root = repo if name == 'crisp_cloud' else (repo / 'packages' / name if name in PACKAGES else resolve(config, entry['rootUri']))
        entry['rootUri'] = root.as_uri() + '/'
    target = repo / '.dart_tool/package_config.json'
    previous = target.read_bytes() if target.exists() else None
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(analyzer_graph, indent=2) + '\n')
    save(output / 'analysis-package-config.json', analyzer_graph)
    receipt['analysis_config_sha256'] = digest(target.read_bytes())

    def run(name, command, cwd):
        started = now()
        start = time.monotonic()
        log = output / f'{name}.log'
        with log.open('w') as stream:
            result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
        row = {'name': name, 'command': command, 'cwd': str(cwd), 'started_utc': started,
               'finished_utc': now(), 'duration_seconds': round(time.monotonic()-start, 3),
               'exit_code': result.returncode, 'log': log.name, 'log_sha256': digest(log.read_bytes())}
        receipt['commands'].append(row)
        print(f'{name}: exit {result.returncode}', flush=True)
        if result.returncode:
            print(log.read_text()[-6500:], flush=True)
            raise RuntimeError(f'{name} failed; see {log.name}')
        return log.read_text()

    failure = None
    try:
        run('vendor-source', [sys.executable, 'tool/verify_office_fidelity.py', '--source', str(quds)], repo)
        run('vendor-tracked', [sys.executable, 'tool/verify_office_fidelity.py', '--source', str(quds), '--require-tracked'], repo)
        log = run('host-tests', [str(dart), str(flutter / 'bin/cache/flutter_tools.snapshot'), 'test', '--no-pub',
                                '--concurrency=1', '--reporter', 'expanded', *TESTS], harness)
        match = re.search(r'\+(\d+): All tests passed!', log)
        receipt['passed_host_tests'] = int(match[1]) if match else None
        if receipt['passed_host_tests'] != 41:
            raise RuntimeError('Executed test count differs from the final 41-test cohort')
        run('host-analysis', [str(dart), 'analyze', '--fatal-infos', *HOST_TARGETS], repo)
        run('vendor-analysis', [str(dart), 'analyze', '--fatal-infos', *VENDORED_TARGETS], repo)
        run('host-format', [str(dart), 'format', '--output=none', '--set-exit-if-changed', *HOST_TARGETS], repo)
        run('vendor-format', [str(dart), 'format', '--output=none', '--set-exit-if-changed', *VENDORED_TARGETS], repo)
        log = run('python-sync-verifier-tests', [sys.executable, '-m', 'unittest', 'test_sync_office_fidelity', 'test_sync_legacy_doc_parser', '-v'], repo / 'tool')
        count = re.search(r'Ran (\d+) tests? in', log)
        receipt['passed_python_tests'] = int(count[1]) if count else None
        run('whitespace', ['git', 'diff', '--check'], repo)
        run('vendor-tracked-final', [sys.executable, 'tool/verify_office_fidelity.py', '--source', str(quds), '--require-tracked'], repo)
    except Exception as error:
        failure = str(error)
    finally:
        if previous is None:
            target.unlink(missing_ok=True)
            try:
                target.parent.rmdir()
            except OSError:
                pass
        else:
            target.write_bytes(previous)
        restored = (target.read_bytes() if target.exists() else None) == previous
        source_after = source_snapshot(repo)
        deps_after = dependency_snapshot(harness, flutter, repo)
        save(output / 'source-after.json', source_after)
        save(output / 'dependencies-after.json', deps_after)
        receipt.update({'finished_utc': now(), 'head_at_completion': git(repo, 'rev-parse', 'HEAD'),
                        'source_unchanged': source_before == source_after, 'dependencies_unchanged': deps_before == deps_after,
                        'source_after_aggregate_sha256': aggregate(source_after), 'dependencies_after_aggregate_sha256': aggregate(deps_after),
                        'analysis_config_restored': restored,
                        'changed_source_paths': [name for name in sorted(source_before.keys() | source_after.keys()) if source_before.get(name) != source_after.get(name)]})
        if not (receipt['source_unchanged'] and receipt['dependencies_unchanged'] and restored):
            failure = (failure + '; ' if failure else '') + 'Input stability or analyzer restoration failed'
        receipt['status'] = 'passed' if failure is None else 'failed'
        receipt['error'] = failure
        save(output / 'receipt.json', receipt)
    print(json.dumps({k: receipt.get(k) for k in ('status', 'passed_host_tests', 'passed_python_tests', 'source_file_count', 'dependency_file_count', 'source_unchanged', 'dependencies_unchanged', 'analysis_config_restored', 'error')}, indent=2))
    return 0 if failure is None else 1


if __name__ == '__main__':
    raise SystemExit(main())

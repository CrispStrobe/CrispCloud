#!/usr/bin/env python3
"""Validate a frozen Office improvement commit using its locked local graph.

No network, CI or workflow endpoints are queried. Each run requires a fresh
output directory. Raw test events, source/dependency/runtime maps, and commands
are retained; historical runs are never added to the measured totals.
"""
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def now():
    return datetime.now(timezone.utc).isoformat()


def source_snapshot(repo):
    prefixes = ('lib/', 'test/', 'tool/', 'assets/', 'fonts/',
                'packages/quds_office_engine/lib/', 'packages/quds_office_engine/test/',
                'packages/quds_office_engine/third_party/',
                'packages/quds_office_editor/lib/', 'packages/quds_office_editor/test/',
                'packages/quds_office_editor/example/lib/', 'packages/quds_office_editor/example/test/',
                'packages/quds_office_editor/example/assets/',
                'packages/quds_office_editor/example/fonts/', 'packages/quds_proofing_harper/lib/',
                'packages/quds_proofing_aot/lib/', 'packages/quds_proofing_aot/test/',
                'packages/quds_proofing_aot/tool/', 'tools/proofing/german_model/',
                'packages/quds_office_editor/fonts/', 'packages/quds_reports/lib/',
                'packages/legacy_doc_parser/')
    entries = {}
    for row in git(repo, 'ls-tree', '-r', '-z', 'HEAD').split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        name = name.decode()
        mode, kind, oid = meta.decode().split()
        parts = Path(name).parts
        # The export widget imports six more local packages. Their library and
        # resource/build-hook inputs must remain bound when graph_snapshot skips
        # repository-local package libraries. This does not run native backends.
        local_package_input = (len(parts) > 3 and parts[0] == 'packages' and
                               parts[2] in ('lib', 'assets', 'fonts', 'hook',
                                            'native', 'rust', 'rust_cloud'))
        if kind != 'blob' or not (name.startswith(prefixes) or local_package_input or
                                 Path(name).name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')):
            continue
        # A sparse checkout may omit unrelated examples and tool families.
        # Every materialized program input in the above scopes is bound.
        path = repo / name
        if not path.exists():
            continue
        data = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
        actual_mode = '120000' if path.is_symlink() else ('100755' if path.stat().st_mode & 0o111 else '100644')
        actual_oid = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        assert (actual_mode, actual_oid) == (mode, oid), 'Source differs from frozen Git object: ' + name
        entries[name] = {'sha256': sha(data), 'git_blob': oid, 'mode': mode}
    return entries


def graph_snapshot(config, repo):
    graph = json.loads(config.read_text())
    files = {}
    for package in graph['packages']:
        root = Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path)).resolve()
        for name in ('pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml', 'analysis_options.yaml'):
            path = root / name
            files[str(path)] = sha(path.read_bytes()) if path.is_file() else None
        paths = set()
        for directory in ('lib', 'bin', 'assets', 'fonts', 'hook', 'native', 'rust', 'rust_cloud'):
            resource = root / directory
            if resource.resolve().is_relative_to(repo):
                continue
            paths.update(resource.rglob('*'))
        for path in sorted(paths):
            if path.is_file():
                files[str(path)] = sha(path.read_bytes())
    return files


def package_routes(config):
    """Bind wrapper symlink destinations as well as package-config bytes."""
    routes = {}
    for package in json.loads(config.read_text())['packages']:
        root = Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path)).resolve()
        routes[package['name']] = {
            'root': str(root),
            'library': str((root / package.get('packageUri', 'lib/')).resolve()),
            'resources': {name: str((root / name).resolve()) for name in
                          ('assets', 'fonts', 'hook', 'native', 'rust', 'rust_cloud')
                          if (root / name).exists()},
        }
    return routes


def authenticated_schema_whitespace_exceptions(repo):
    """Preserve exact incoming third-party schemas, including their notices."""
    source_ref = 'f9cc1c003892944881bab3699ba6b76620dc2f07'
    paths = (
        'docs/validation/office-reconcile-20261117/consumer/schemas/OpenDocument-v1.3-manifest-schema.rng',
        'docs/validation/office-reconcile-20261117/consumer/schemas/OpenDocument-v1.3-schema.rng',
    )
    exceptions = {}
    for name in paths:
        trusted_blob = git(repo, 'rev-parse', source_ref + ':' + name).decode().strip()
        head_blob = git(repo, 'rev-parse', 'HEAD:' + name).decode().strip()
        trusted = git(repo, 'cat-file', 'blob', trusted_blob)
        path = repo / name
        assert trusted_blob == head_blob and not path.is_symlink(), name
        # git diff --check below compares committed blobs; a sparse checkout may
        # intentionally omit these documentation files. Verify local bytes too
        # when present, without materializing or rewriting third-party notices.
        if path.exists():
            assert path.is_file() and path.read_bytes() == trusted, 'Third-party schema differs from captured source: ' + name
        exceptions[name] = {'source_ref': source_ref, 'git_blob': trusted_blob,
                            'sha256': sha(trusted), 'bytes': len(trusted),
                            'working_tree_materialized': path.exists()}
    return exceptions


def test_results(path, expected, cwd):
    starts, suites, ends, done, errors = {}, {}, [], [], []
    start_ids = []
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get('type')
        if kind == 'testStart':
            starts[event['test']['id']] = event['test']
            start_ids.append(event['test']['id'])
        elif kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif kind == 'testDone':
            ends.append(event)
        elif kind == 'done':
            done.append(event)
        elif kind == 'error':
            errors.append(event)
    records = []
    for end in ends:
        start = starts.get(end['testID'], {})
        name = start.get('name', '')
        if end.get('hidden') or name.startswith('loading ') or name.endswith(('(setUpAll)', '(tearDownAll)')):
            continue
        records.append({'name': name, 'suite': suites.get(start.get('suiteID')),
                        'result': end.get('result'), 'skipped': end.get('skipped', False)})
    terminal_ids = [event['testID'] for event in ends]
    def resolve(path):
        value = Path(unquote(urlparse(path).path)) if path.startswith('file:') else Path(path)
        return str((value if value.is_absolute() else cwd / value).resolve())
    counts = {'passed': sum(r['result'] == 'success' and not r['skipped'] for r in records),
              'failed': sum(r['result'] != 'success' and not r['skipped'] for r in records),
              'skipped': sum(r['skipped'] for r in records)}
    complete = (len(done) == 1 and done[0].get('success') is True and not errors and
                set(start_ids) == set(terminal_ids) and len(start_ids) == len(set(start_ids)) and
                len(terminal_ids) == len(set(terminal_ids)) and
                {resolve(p) for p in suites.values()} == {resolve(p) for p in expected} and
                len(suites) == len(expected) and counts['failed'] == counts['skipped'] == 0)
    return {**counts, 'complete': complete, 'suites': suites, 'records': records,
            'errors': errors, 'completion_events': done}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=('canonical', 'host', 'workflow'), required=True)
    for name in ('repo', 'harness', 'sdk', 'cache', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--canonical-source', type=Path)
    args = parser.parse_args()
    repo, harness, sdk, cache, out = [p.resolve() for p in (args.repo, args.harness, args.sdk, args.cache, args.output)]
    assert not out.exists(), 'Use a fresh output directory'
    out.mkdir(parents=True)
    for name in ('tmp', 'config'):
        (out / name).mkdir()
    assert git(repo, 'rev-parse', 'HEAD').decode().strip() == args.expected_head
    dirty = git(repo, 'status', '--porcelain', '--untracked-files=all').decode().splitlines()
    assert all(line[3:].startswith('docs/') for line in dirty), dirty
    config = harness / '.dart_tool/package_config.json'
    dart = str(sdk / 'bin/cache/dart-sdk/bin/dart')
    flutter = [dart, str(sdk / 'bin/cache/flutter_tools.snapshot')]
    env = dict(os.environ, FLUTTER_ROOT=str(sdk), PUB_CACHE=str(cache), CI='true',
               FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true',
               TMPDIR=str(out / 'tmp'), XDG_CONFIG_HOME=str(out / 'config'))
    runtime_names = ('bin/cache/dart-sdk/bin/dart', 'bin/cache/dart-sdk/bin/dartaotruntime',
                     'bin/cache/flutter_tools.snapshot', 'bin/cache/flutter.version.json',
                     'bin/cache/artifacts/engine/linux-x64/flutter_tester',
                     'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                     'bin/cache/dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot',
                     'bin/cache/dart-sdk/bin/snapshots/dart2js_aot.dart.snapshot',
                     'bin/cache/dart-sdk/bin/snapshots/dartdev_aot.dart.snapshot')
    runtime_paths = {sdk / name for name in runtime_names}
    for directory in ('bin/cache/dart-sdk/lib',
                      'bin/cache/artifacts/engine/common/flutter_patched_sdk',
                      'bin/cache/artifacts/engine/common/flutter_patched_sdk_product'):
        runtime_paths.update(path for path in (sdk / directory).rglob('*') if path.is_file())
    icu = sdk / 'bin/cache/artifacts/engine/linux-x64/icudtl.dat'
    if icu.is_file():
        runtime_paths.add(icu)
    node = Path(shutil.which('node')).resolve() if args.kind == 'canonical' else None
    node_runtime = ({'node/executable': sha(node.read_bytes())} if node else {})
    python = Path(sys.executable).resolve()
    workspace_paths = {harness / name for name in ('pubspec.yaml', 'pubspec.lock',
                       'pubspec_overrides.yaml', 'analysis_options.yaml',
                       '.dart_tool/package_config.json', '.dart_tool/package_graph.json')}
    for pattern in ('packages/*/pubspec*.yaml', 'packages/*/example/pubspec*.yaml',
                    'apps/*/pubspec*.yaml', 'packages/*/analysis_options.yaml'):
        workspace_paths.update(harness.glob(pattern))
    def inputs():
        return {'source': source_snapshot(repo), 'dependencies': graph_snapshot(config, repo),
                'package_routes': package_routes(config),
                'runtime': {**{str(path.relative_to(sdk)): sha(path.read_bytes()) for path in sorted(runtime_paths)},
                            **({'node/executable': sha(node.read_bytes())} if node else {}),
                            'python/executable': sha(python.read_bytes())},
                'workspace': {str(path): sha(path.read_bytes()) if path.is_file() else None for path in sorted(workspace_paths)},
                'graph_sha256': sha(config.read_bytes()),
                'lock_sha256': sha((harness / 'pubspec.lock').read_bytes()),
                'runner_sha256': sha(Path(__file__).read_bytes()),
                **({'authenticated_schema_whitespace_exceptions':
                    authenticated_schema_whitespace_exceptions(repo)} if args.kind == 'canonical' else {})}
    before = inputs()
    save(out / 'inputs-before.json', before)
    receipt = {'status': 'running', 'kind': args.kind, 'source_commit': args.expected_head,
               'source_tree': git(repo, 'rev-parse', 'HEAD^{tree}').decode().strip(),
               'baseline': args.baseline, 'started_utc': now(), 'commands': [],
               'scope': 'Local source-specific Office, proofing, AOT and Studio unit/widget qualification; no full application/export-dialog, live interoperability, native/model or Wasm acceptance.'}
    if args.kind == 'workflow':
        receipt['scope'] = ('Local production Office menu/export widget qualification using authored fixtures '
                            'and deterministic cloud/copy-destination test doubles; no live operating-system '
                            'export dialog, cloud transport, Word/LibreOffice/Zotero interoperability, '
                            'native/model or Wasm acceptance.')
    if args.kind == 'canonical':
        receipt['whitespace_exceptions'] = before['authenticated_schema_whitespace_exceptions']
    if node:
        receipt['node_runtime'] = {'path': str(node), 'sha256': node_runtime['node/executable'],
                                   'version': subprocess.check_output([str(node), '--version'], text=True).strip()}
    receipt['python_runtime'] = {'path': str(python), 'sha256': sha(python.read_bytes()),
                                 'version': subprocess.check_output([str(python), '--version'], text=True).strip()}
    def run(name, command, cwd, selected=None, expected_count=None):
        assert expected_count is None or selected
        row = {'name': name, 'command': command, 'cwd': str(cwd), 'started_utc': now()}
        if selected:
            routing = []
            for path in selected:
                actual = (cwd / path).resolve(strict=True)
                expected = repo / path if args.kind in ('host', 'workflow') else cwd / path
                assert actual == expected.resolve(strict=True) and actual.is_relative_to(repo), path
                relative = str(actual.relative_to(repo))
                assert sha(actual.read_bytes()) == before['source'][relative]['sha256'], path
                routing.append({'selected': path, 'resolved': str(actual),
                                'source_path': relative, 'sha256': sha(actual.read_bytes())})
            row['test_routing'] = routing
        receipt['commands'].append(row)
        save(out / 'receipt.json', receipt)
        stdout, stderr = out / (name + '.stdout.log'), out / (name + '.stderr.log')
        started = time.monotonic()
        with stdout.open('w') as so, stderr.open('w') as se:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=so, stderr=se)
            while process.poll() is None:
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    print(name, 'running', round(time.monotonic() - started), 'seconds', flush=True)
                    if time.monotonic() - started > 600:
                        process.terminate()
                        process.wait(timeout=10)
                        raise RuntimeError(name + ' exceeded 600 seconds')
        row.update(exit_code=process.returncode, finished_utc=now(),
                   stdout_sha256=sha(stdout.read_bytes()), stderr_sha256=sha(stderr.read_bytes()))
        if selected:
            result = test_results(stdout, selected, cwd)
            save(out / (name + '-events.json'), result)
            row['tests'] = {key: result[key] for key in ('passed', 'failed', 'skipped', 'complete')}
            row['selected_files'] = selected
        row['passed'] = process.returncode == 0 and (not selected or row['tests']['complete'])
        if expected_count is not None:
            row['expected_substantive_count'] = expected_count
            row['passed'] = row['passed'] and row['tests']['passed'] == expected_count
        save(out / 'receipt.json', receipt)
        print(name, 'passed' if row['passed'] else 'FAILED', row.get('tests', ''), flush=True)
        return row
    def run_candidate_controls():
        module = (repo / 'tools/proofing/german_model/test_candidate_admission.py').resolve(strict=True)
        relative = str(module.relative_to(repo))
        assert sha(module.read_bytes()) == before['source'][relative]['sha256']
        result_path = out / 'candidate-python-controls-result.json'
        code = '''import hashlib, importlib.util, json, pathlib, sys, unittest
module_path = pathlib.Path(sys.argv[1]).resolve(strict=True)
destination = pathlib.Path(sys.argv[2])
expected = int(sys.argv[3])
source_hash = hashlib.sha256(module_path.read_bytes()).hexdigest()
sys.path.insert(0, str(module_path.parent))
spec = importlib.util.spec_from_file_location("test_candidate_admission", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
assert pathlib.Path(module.__file__).resolve() == module_path
suite = unittest.defaultTestLoader.loadTestsFromModule(module)
def ids(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from ids(item)
        else:
            yield item.id()
identities = list(ids(suite))
assert len(identities) == len(set(identities)) == expected
result = unittest.TextTestRunner(verbosity=2).run(suite)
after_hash = hashlib.sha256(module_path.read_bytes()).hexdigest()
passed = result.wasSuccessful() and not result.skipped and result.testsRun == expected and source_hash == after_hash
destination.write_text(json.dumps({"passed": passed, "source": str(module_path), "sha256": source_hash, "sha256_after": after_hash, "case_ids": identities, "tests_run": result.testsRun, "expected_count": expected, "failures": len(result.failures), "errors": len(result.errors), "skips": len(result.skipped)}, indent=2) + "\\n")
sys.exit(0 if passed else 1)
'''
        row = run('candidate-python-controls', [str(python), '-c', code, str(module), str(result_path), '5'], module.parent)
        result = json.loads(result_path.read_text())
        assert result['source'] == str(module) and result['sha256'] == before['source'][relative]['sha256']
        row['python_controls'] = result
        row['passed'] = row['passed'] and result['passed']
        save(out / 'receipt.json', receipt)
    target = repo / '.dart_tool/package_config.json'
    previous = target.read_bytes() if target.exists() else None
    installed = False
    installed_graph_sha256 = None
    try:
        if args.kind == 'canonical':
            assert config == target, 'Canonical runner must use its own frozen graph'
            engine = repo / 'packages/quds_office_engine'
            names = sorted(p.name for p in (engine / 'test').glob('*_test.dart') if
                           p.name.startswith(('odt_', 'odf_', 'ods_', 'odp_', 'word_bookmark_', 'word_section_')) or
                           p.name in ('office_search_fidelity_test.dart', 'office_isolate_open_test.dart', 'office_isolate_save_test.dart', 'story_media_fidelity_test.dart'))
            selected = ['test/' + name for name in names]
            selected += [str(path.relative_to(engine)) for path in sorted((engine / 'test/proofing').glob('*_test.dart'))]
            run('engine-tests', [dart, 'test', '--concurrency=4', '--reporter=json', *selected], engine, selected)
            editor_tests = ['test/' + name + '_test.dart' for name in (
                'word_bookmark_fidelity', 'word_bookmark_copy', 'word_bookmark_history',
                'word_generated_bookmark_paste', 'word_note_numbering', 'word_notes_editing',
                'word_german_grammar_integration', 'word_manual_proofing', 'word_proofing_session',
                'word_proofing_correction', 'word_proofing_dialog')]
            run('editor-tests', [*flutter, 'test', '--no-pub', '--concurrency=2', '--reporter=json', *editor_tests],
                repo / 'packages/quds_office_editor', editor_tests)
            aot = repo / 'packages/quds_proofing_aot'
            aot_tests = [str(path.relative_to(aot)) for path in sorted((aot / 'test').glob('*_test.dart'))]
            run('aot-vm-tests', [dart, 'test', '--concurrency=2', '--reporter=json', *aot_tests], aot, aot_tests)
            node_row = run('aot-node-tests', [dart, 'test', '--platform=node', '--concurrency=2', '--reporter=json', *aot_tests], aot, aot_tests)
            node_row['repeat_of'] = 'aot-vm-tests'
            save(out / 'receipt.json', receipt)
            studio = repo / 'packages/quds_office_editor/example'
            studio_tests = ['test/studio_aot_test.dart', 'test/widget_test.dart']
            run('studio-tests', [*flutter, 'test', '--no-pub', '--concurrency=2', '--reporter=json',
                                '--dart-define=QUDS_AOT_ENDPOINT=http://127.0.0.1:17018/', *studio_tests], studio, studio_tests)
            run_candidate_controls()
            run('engine-analysis', [dart, 'analyze', '--fatal-infos', 'packages/quds_office_engine'], repo)
            run('aot-analysis', [dart, 'analyze', '--fatal-infos', 'packages/quds_proofing_aot'], repo)
            run('editor-proofing-analysis', [dart, 'analyze', '--fatal-infos',
                'lib/src/embed/word_proofing_dialog.dart', *editor_tests], repo / 'packages/quds_office_editor')
            run('studio-analysis', [dart, 'analyze', '--fatal-infos', 'lib/studio_aot.dart',
                                    'lib/suite_workspace.dart', *studio_tests], studio)
        else:
            assert args.canonical_source
            graph = json.loads(config.read_text())
            for package in graph['packages']:
                name = package['name']
                original_root = Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path)).resolve()
                library = (original_root / package.get('packageUri', 'lib/')).resolve()
                root = original_root
                if library.is_relative_to(repo):
                    root = repo if name == 'crisp_cloud' else repo / 'packages' / name
                    assert (root / package.get('packageUri', 'lib/')).resolve() == library, name
                package['rootUri'] = root.as_uri() + '/'
            target.parent.mkdir(exist_ok=True)
            save(target, graph)
            installed = True
            installed_graph_sha256 = sha(target.read_bytes())
            save(out / 'analysis-package-config.json', graph)
            guard = [sys.executable, 'tool/verify_office_fidelity.py', '--source', str(args.canonical_source), '--require-tracked']
            run('vendor-before', guard, repo)
            if args.kind == 'workflow':
                selected = ['test/widget/office_odf_export_workflow_test.dart']
                support = ['test/support/office_test_harness.dart', 'test/support/workflow_fake_client.dart',
                           'test/support/workspace_fixture.dart']
                libraries = ['lib/widgets/office_editor_dialog.dart', 'lib/widgets/office_editor_ribbon.dart',
                             'lib/services/office_editor_menu.dart', 'lib/services/office_device_export.dart',
                             'lib/services/office_device_export_native.dart', 'lib/services/office_device_export_types.dart',
                             'lib/services/office_document_service.dart']
                routed = []
                for path in [*selected, *support, *libraries,
                             'test/fixtures/office_native_workflows/native-slide-source.pptx']:
                    actual = (harness / path).resolve(strict=True)
                    assert actual == (repo / path).resolve(strict=True) and actual.is_relative_to(repo), path
                    relative = str(actual.relative_to(repo))
                    assert sha(actual.read_bytes()) == before['source'][relative]['sha256'], path
                    routed.append({'selected': path, 'resolved': str(actual), 'source_path': relative,
                                   'sha256': sha(actual.read_bytes())})
                receipt['workflow_input_routing'] = routed
                save(out / 'receipt.json', receipt)
                run('workflow-tests', [*flutter, 'test', '--no-pub', '--concurrency=1', '--reporter=json', *selected],
                    harness, selected, expected_count=10)
                run('workflow-analysis', [dart, 'analyze', '--fatal-infos', *selected, *support, *libraries], repo)
                run('workflow-format', [dart, 'format', '--language-version=3.13', '--output=none',
                                        '--set-exit-if-changed', *selected], repo)
            else:
                selected = ['test/' + name + '_test.dart' for name in (
                    'office_annotation_preview', 'office_document_service', 'office_proofing_licenses',
                    'office_zotero', 'office_zotero_citing_transport', 'office_zotero_ribbon',
                    'office_odf_visibility', 'office_odf_cell_story', 'office_odf_cell_limits', 'office_odt_export_acceptance')]
                run('host-tests', [*flutter, 'test', '--no-pub', '--concurrency=1', '--reporter=json', *selected], harness, selected)
                targets = ['lib/services/office_document_service.dart', *selected]
                run('host-analysis', [dart, 'analyze', '--fatal-infos', *targets], repo)
                run('host-format', [dart, 'format', '--language-version=3.13', '--output=none', '--set-exit-if-changed',
                                   'lib/services/office_document_service.dart',
                                   'test/office_odf_visibility_test.dart', 'test/office_odf_cell_story_test.dart', 'test/office_odf_cell_limits_test.dart',
                                   'test/office_odt_export_acceptance_test.dart'], repo)
                run('vendor-python-controls', [sys.executable, '-m', 'unittest', 'test_sync_office_fidelity', 'test_sync_legacy_doc_parser', '-v'], repo / 'tool')
            run('vendor-after', guard, repo)
        changed = git(repo, 'diff', '--name-only', args.baseline, 'HEAD').decode().splitlines()
        dart_changes = [p for p in changed if p.endswith('.dart') and p.startswith('packages/')]
        if args.kind == 'host':
            production_changes = [p for p in dart_changes if '/lib/' in p]
            if production_changes:
                run('vendor-analysis', [dart, 'analyze', '--fatal-infos', *production_changes], repo)
        if dart_changes and args.kind != 'workflow':
            run('changed-dart-format', [dart, 'format', '--language-version=3.12', '--output=none', '--set-exit-if-changed', *dart_changes], repo)
        whitespace = ['git', 'diff', '--check', args.baseline, 'HEAD']
        if args.kind == 'canonical':
            authenticated = authenticated_schema_whitespace_exceptions(repo)
            assert authenticated == before['authenticated_schema_whitespace_exceptions']
            whitespace.extend(['--', '.', *(':(exclude,literal)' + path for path in authenticated)])
        run('whitespace', whitespace, repo)
    except BaseException as error:
        receipt['exception'] = repr(error)
        raise
    finally:
        receipt['analysis_config_unchanged_during_run'] = (
            not installed or (target.is_file() and sha(target.read_bytes()) == installed_graph_sha256))
        if installed:
            if previous is None:
                target.unlink()
            else:
                target.write_bytes(previous)
        try:
            after = inputs()
            save(out / 'inputs-after.json', after)
            receipt['inputs_unchanged'] = before == after
            receipt['source_head_unchanged'] = git(repo, 'rev-parse', 'HEAD').decode().strip() == args.expected_head
        except BaseException as error:
            receipt['final_snapshot_error'] = repr(error)
            receipt['inputs_unchanged'] = False
            receipt['source_head_unchanged'] = False
        receipt['analysis_config_restored'] = (target.read_bytes() if target.exists() else None) == previous
        receipt['finished_utc'] = now()
        receipt['status'] = 'passed' if not receipt.get('exception') and receipt['commands'] and all(r.get('passed') for r in receipt['commands']) and receipt['inputs_unchanged'] and receipt['source_head_unchanged'] and receipt['analysis_config_restored'] and receipt['analysis_config_unchanged_during_run'] else 'failed'
        save(out / 'receipt.json', receipt)
    return 0 if receipt['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

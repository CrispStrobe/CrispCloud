#!/usr/bin/env python3
"""Qualify final Zotero plus concurrent ODS/proofing/layout integration at an explicit source pin."""
from datetime import datetime, timezone
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
import traceback
from urllib.parse import unquote, urljoin, urlparse

OUTPUT = Path(__file__).resolve().parent
TOOLCHAIN = OUTPUT.parent
WORKSPACE = TOOLCHAIN.parent
SOURCE = (WORKSPACE / 'quds_office_suite').resolve()
HARNESSES = TOOLCHAIN / 'harness'
PUBLISHED_SOURCE = None
EXPECTED_TREE = None
COMMAND_TIMEOUT_SECONDS = 600
HEARTBEAT_SECONDS = 15
PACKAGE_PATHS = {
    'legacy_doc_parser': 'packages/legacy_doc_parser',
    'quds_office_engine': 'packages/quds_office_engine',
    'quds_reports': 'packages/quds_reports',
    'quds_office_editor': 'packages/quds_office_editor',
    'quds_office_studio': 'packages/quds_office_editor/example',
}
TARGETS = {
    'engine': [
        'packages/quds_office_engine/lib/src/word/model/word_zotero.dart',
        'packages/quds_office_engine/lib/src/zotero/zotero_client.dart',
        'packages/quds_office_engine/test/word_zotero_source_identity_test.dart',
        'packages/quds_office_engine/test/zotero_backoff_state_test.dart',
    ],
    'editor': [
        'packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart',
        'packages/quds_office_editor/lib/src/embed/word_zotero_format.dart',
        'packages/quds_office_editor/test/word_zotero_source_identity_test.dart',
        'packages/quds_office_editor/test/word_zotero_dialog_scaling_test.dart',
        'packages/quds_office_editor/test/word_zotero_backoff_session_test.dart',
    ],
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    return digest(path.read_bytes())


def save(name, value):
    temporary = OUTPUT / (name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.replace(OUTPUT / name)


def git(*args):
    return subprocess.check_output(['git', '-C', str(SOURCE), *args])


def git_text(*args):
    return git(*args).decode().strip()


def source_input(path):
    parts = Path(path).parts
    if not parts or parts[0] == 'docs':
        return False
    return (
        Path(path).name in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}
        or (len(parts) >= 4 and parts[0] == 'packages' and parts[2] in {'lib', 'test', 'fonts', 'assets', 'third_party'})
        or path.startswith('packages/quds_office_editor/example/lib/')
        or path.startswith('packages/quds_office_editor/example/test/')
    )


def source_fingerprint():
    tracked = [p.decode() for p in git('ls-files', '-z').split(b'\0') if p and source_input(p.decode())]
    untracked = [p.decode() for p in git('ls-files', '--others', '--exclude-standard', '-z').split(b'\0') if p and source_input(p.decode())]
    paths = sorted(set(tracked + untracked))
    hashes = {p: sha(SOURCE / p) for p in paths}
    return {
        'files': len(hashes),
        'sha256_by_path': hashes,
        'aggregate_sha256': digest(json.dumps(hashes, sort_keys=True).encode()),
        'untracked_paths': untracked,
    }


def published_matches(paths):
    expected = {}
    for row in git('ls-tree', '-r', '-z', PUBLISHED_SOURCE).split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        expected[name.decode()] = meta.split()[2].decode()
    mismatches = []
    for path in paths:
        data = (SOURCE / path).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if expected.get(path) != blob:
            mismatches.append(path)
    return mismatches


def normalize_graph(config_path):
    graph = json.loads(config_path.read_text())
    assert graph['configVersion'] == 2
    for package in graph['packages']:
        name = package['name']
        if name in PACKAGE_PATHS:
            root = SOURCE / PACKAGE_PATHS[name]
        else:
            uri = urlparse(urljoin(config_path.as_uri(), package['rootUri']))
            assert uri.scheme == 'file' and uri.netloc in {'', 'localhost'}, uri
            root = Path(unquote(uri.path)).resolve()
        assert root.is_dir(), root
        package['rootUri'] = root.as_uri() + '/'
    return graph


def dependencies_fingerprint(graphs):
    files = {}
    for graph in graphs.values():
        for package in graph['packages']:
            if package['name'] in PACKAGE_PATHS:
                continue
            root = Path(unquote(urlparse(package['rootUri']).path))
            for relative in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']:
                path = root / relative
                if path.is_file():
                    files[str(path.relative_to(TOOLCHAIN))] = sha(path)
            for folder in ['lib', 'bin']:
                for path in sorted((root / folder).rglob('*')):
                    if path.is_file():
                        files[str(path.relative_to(TOOLCHAIN))] = sha(path)
    runtime = TOOLCHAIN / 'flutter-sdk'
    for relative in [
        'bin/cache/dart-sdk/bin/dart',
        'bin/cache/flutter_tools.snapshot',
        'bin/cache/artifacts/engine/linux-x64/flutter_tester',
        'bin/cache/flutter.version.json',
        'bin/internal/engine.version',
    ]:
        path = runtime / relative
        files[str(path.relative_to(TOOLCHAIN))] = sha(path)
    return {
        'files': len(files),
        'sha256_by_path': files,
        'aggregate_sha256': digest(json.dumps(files, sort_keys=True).encode()),
    }


def harness_inputs():
    inputs = {}
    for name in ['quds_office_engine', 'quds_office_editor', 'quds_reports', 'legacy_doc_parser']:
        for relative in ['pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json', '.dart_tool/package_graph.json']:
            path = HARNESSES / name / relative
            if path.exists():
                inputs[str(path.relative_to(TOOLCHAIN))] = sha(path)
    return inputs


def main():
    global PUBLISHED_SOURCE, EXPECTED_TREE, SOURCE, HARNESSES
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-commit', required=True, help='Exact final published Git commit; do not use a moving branch name.')
    parser.add_argument('--source-dir', type=Path, help='Optional isolated canonical checkout; exact published tree is still required.')
    parser.add_argument('--harness-root', type=Path, help='Optional isolated harness root; SDK and pub cache remain in the original toolchain.')
    parser.add_argument('--extra-analysis-target', action='append', default=[], help='Additional directly ported Dart source/test path; may be repeated.')
    parser.add_argument('--extra-test', action='append', default=[], help='Extra disjoint integration test as engine:test/file.dart or editor:test/file.dart.')
    args = parser.parse_args()
    SOURCE = (args.source_dir or SOURCE).resolve()
    HARNESSES = (args.harness_root or HARNESSES).resolve()
    assert SOURCE.is_dir() and HARNESSES.is_dir(), (SOURCE, HARNESSES)
    assert not (OUTPUT / 'receipt.json').exists(), 'Use a new output directory or preserve the previous receipt before a retry.'
    assert re.fullmatch(r'[a-f0-9]{40}', args.source_commit), 'Use a complete published commit SHA.'
    PUBLISHED_SOURCE = args.source_commit
    EXPECTED_TREE = git_text('rev-parse', PUBLISHED_SOURCE + '^{tree}')
    for target in args.extra_analysis_target:
        assert '..' not in Path(target).parts and target.endswith('.dart'), target
        package = next((name for name in TARGETS if target.startswith('packages/quds_office_' + name + '/')), None)
        assert package is not None and (SOURCE / target).is_file(), target
        if target not in TARGETS[package]:
            TARGETS[package].append(target)
    assert git_text('rev-parse', PUBLISHED_SOURCE + '^{tree}') == EXPECTED_TREE
    assert git_text('rev-parse', 'HEAD^{tree}') == EXPECTED_TREE
    dart = str(TOOLCHAIN / 'flutter-sdk/bin/cache/dart-sdk/bin/dart')
    snapshot = str(TOOLCHAIN / 'flutter-sdk/bin/cache/flutter_tools.snapshot')
    runtime = json.loads((TOOLCHAIN / 'flutter-sdk/bin/cache/flutter.version.json').read_text())
    assert runtime['frameworkRevision'] == '737ba8f885dc774b53b442759999a312c9461e4e'
    assert runtime['engineRevision'] == 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
    assert runtime['dartSdkVersion'] == '3.13.7'

    graphs = {}
    for name in ['engine', 'editor']:
        harness = HARNESSES / ('quds_office_' + name)
        for relative in ['lib', 'test']:
            assert (harness / relative).resolve() == SOURCE / 'packages' / ('quds_office_' + name) / relative
        graphs[name] = normalize_graph(harness / '.dart_tool/package_config.json')
        save(name + '-analysis-package-config.json', graphs[name])
    before = source_fingerprint()
    assert not before['untracked_paths'], before['untracked_paths']
    mismatches = published_matches(before['sha256_by_path'])
    assert not mismatches, mismatches
    dependencies_before = dependencies_fingerprint(graphs)
    inputs_before = harness_inputs()
    save('source-before.json', before)
    save('dependencies-before.json', dependencies_before)

    engine = SOURCE / 'packages/quds_office_engine'
    editor = SOURCE / 'packages/quds_office_editor'
    cohorts = {
        'engine-zotero': ('engine', sorted(str(p.relative_to(engine)) for p in (engine / 'test').rglob('*zotero*test.dart'))),
        'editor-zotero': ('editor', sorted(str(p.relative_to(editor)) for p in (editor / 'test').rglob('*zotero*test.dart'))),
        'engine-proofing-integration': ('engine', sorted([str(p.relative_to(engine)) for p in (engine / 'test/proofing').glob('*.dart')] + ['test/proofing_hyphenation_test.dart'])),
        'engine-ods-integration': ('engine', ['test/ods_sheet_reader_test.dart']),
        'engine-word-layout-integration': ('engine', ['test/word_layout_test.dart', 'test/word_styles_layout_test.dart']),
        'editor-proofing-integration': ('editor', sorted([str(p.relative_to(editor)) for p in (editor / 'test').glob('word_proofing*test.dart')] + ['test/platform_spelling_provider_test.dart'])),
        'editor-hyphenation-integration': ('editor', sorted(str(p.relative_to(editor)) for p in (editor / 'test').glob('word_hyphenation*test.dart'))),
    }
    for spec in args.extra_test:
        package, test = spec.split(':', 1)
        assert package in ('engine', 'editor'), spec
        path = Path(test)
        assert not path.is_absolute() and '..' not in path.parts and path.parts[0] == 'test' and test.endswith('_test.dart'), spec
        assert (SOURCE / ('packages/quds_office_' + package) / test).is_file(), spec
        if not any((package == owner and test in tests) for owner, tests in cohorts.values()):
            key = package + '-recovery-integration'
            if key not in cohorts:
                cohorts[key] = (package, [])
            cohorts[key][1].append(test)
    for name, (package, tests) in cohorts.items():
        assert tests, 'Empty cohort: ' + name
        for test in tests:
            assert (SOURCE / ('packages/quds_office_' + package) / test).is_file(), test
    for target in args.extra_analysis_target:
        if '/test/' not in target or not target.endswith('_test.dart'):
            continue
        package = 'engine' if target.startswith('packages/quds_office_engine/') else 'editor'
        test = str(Path(target).relative_to('packages/quds_office_' + package))
        if not any((package == owner and test in tests) for owner, tests in cohorts.values()):
            key = package + '-ported-fix-integration'
            if key not in cohorts:
                cohorts[key] = (package, [])
            cohorts[key][1].append(test)
    selected = [(package, test) for package, tests in cohorts.values() for test in tests]
    assert len(selected) == len(set(selected)), 'Cohorts must be disjoint.'
    receipt = {
        'recorded_utc': datetime.now(timezone.utc).isoformat(),
        'reproduction_script_sha256': sha(Path(__file__)),
        'runner_changes': ['Resolve canonical checkout symlink for portable path identity', 'Allow explicit disjoint additional integration tests without changing existing cohorts', 'Bind runner bytes and require selected tests to exist', 'Fingerprint bundled fonts, assets, and third-party inputs used by incoming rendering tests', 'Analyze support fixtures without enrolling them as standalone test suites', 'Allow isolated source and harness roots with the original shared runtime', 'Journal command start, heartbeat, and completion atomically', 'Stop command process groups after 600 seconds and fail closed', 'Require successful command status in addition to zero exit codes'],
        'repository': 'CrispStrobe/quds_office_suite',
        'status': 'running',
        'source_checkout': str(SOURCE),
        'harness_root': str(HARNESSES),
        'external_toolchain_root': str(TOOLCHAIN),
        'per_command_timeout_seconds': COMMAND_TIMEOUT_SECONDS,
        'heartbeat_seconds': HEARTBEAT_SECONDS,
        'qualified_published_source_commit': PUBLISHED_SOURCE,
        'qualified_source_tree': EXPECTED_TREE,
        'working_head_at_start': git_text('rev-parse', 'HEAD'),
        'fresh_full_retry': {
            'original_interrupted_attempt': '../expanded-canonical-qualification/attempt-2-executor-interruption',
            'previous_completed_engine_tests_excluded': 390,
            'partial_editor_progress_excluded': True,
            'previous_attempt_counts_are_not_added': True,
        },
        'initial_pre_concurrent_qualification': {
            'directory': '../final-canonical-qualification',
            'source_commit': '039c1e293052f548367f9ea3b0fa5ff56949ccaa',
            'counts_are_not_added_to_this_run': True,
        },
        'canonical_source_files_verified_against_published_git_blobs': before['files'],
        'runtime': runtime,
        'cohorts': {name: {'package': package, 'tests': tests} for name, (package, tests) in cohorts.items()},
        'cohorts_are_disjoint': True,
        'analysis_and_format_targets': TARGETS,
        'harness_input_sha256_before': inputs_before,
        'source_scope': 'Tracked canonical package lib/test/fonts/assets/third_party trees, Studio lib/test and dependency/analysis manifests outside docs. Untracked compiled inputs are rejected.',
        'dependency_scope': 'Source lib/bin trees and manifests of all resolved external engine/editor graph packages, plus the genuine runtime artifacts. Exact package resolution is preserved by the unchanged locked harness inputs.',
        'counts_exclude_setup_smokes_overlapping_runs_and_expected_failure_controls': True,
        'production_dependency_manifests_changed': False,
        'github_actions_queried_awaited_or_rerun': False,
        'commands': [],
    }
    save('receipt.json', receipt)

    def command(name, parts, cwd, test=False):
        log = OUTPUT / (name + '-execution.log')
        started = time.monotonic()
        item = {
            'name': name,
            'command': parts,
            'cwd': str(cwd),
            'status': 'running',
            'started_utc': datetime.now(timezone.utc).isoformat(),
            'timeout_seconds': COMMAND_TIMEOUT_SECONDS,
            'exit_code': None,
            'elapsed_seconds': 0.0,
            'log': log.name,
            'log_sha256': None,
        }
        if test:
            item['passed_tests'] = None
            item['skipped_tests'] = None
        receipt['commands'].append(item)
        save('receipt.json', receipt)
        print(json.dumps({'event': 'command-start', 'name': name, 'timeout_seconds': COMMAND_TIMEOUT_SECONDS}), flush=True)
        process = None
        timed_out = False

        def stop_group():
            if process is None or process.poll() is not None:
                return
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)

        try:
            with log.open('w') as stream:
                process = subprocess.Popen(parts, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
                item['pid'] = process.pid
                save('receipt.json', receipt)
                deadline = started + COMMAND_TIMEOUT_SECONDS
                next_heartbeat = started + HEARTBEAT_SECONDS
                while process.poll() is None:
                    now = time.monotonic()
                    if now >= deadline:
                        timed_out = True
                        item['timed_out'] = True
                        item['status'] = 'timed_out'
                        save('receipt.json', receipt)
                        print(json.dumps({'event': 'command-timeout', 'name': name, 'timeout_seconds': COMMAND_TIMEOUT_SECONDS}), flush=True)
                        stop_group()
                        break
                    if now >= next_heartbeat:
                        item['elapsed_seconds'] = round(now - started, 3)
                        item['last_heartbeat_utc'] = datetime.now(timezone.utc).isoformat()
                        item['observed_log_bytes'] = log.stat().st_size
                        save('receipt.json', receipt)
                        print(json.dumps({'event': 'heartbeat', 'name': name, 'elapsed_seconds': item['elapsed_seconds'], 'log_bytes': item['observed_log_bytes']}), flush=True)
                        next_heartbeat = now + HEARTBEAT_SECONDS
                    time.sleep(min(1.0, max(0.0, deadline - now), max(0.0, next_heartbeat - now)))
                process_returncode = process.wait(timeout=5)
            item['process_returncode'] = process_returncode
            item['exit_code'] = 124 if timed_out else process_returncode
            content = log.read_text()
            if test:
                match = re.search(r'\+(\d+)(?:\s+~(\d+))?: All tests passed!', content)
                if match:
                    item['observed_success_marker_count'] = int(match.group(1))
                if item['exit_code'] == 0 and match:
                    item['passed_tests'] = int(match.group(1))
                    item['skipped_tests'] = int(match.group(2) or 0)
            item['status'] = 'passed' if item['exit_code'] == 0 and (not test or item['passed_tests'] is not None) else ('timed_out' if timed_out else 'failed')
        except BaseException as error:
            item['status'] = 'interrupted' if isinstance(error, (KeyboardInterrupt, SystemExit)) else 'error'
            item['error'] = type(error).__name__ + ': ' + str(error)
            stop_group()
            if process is not None:
                item['process_returncode'] = process.poll()
                item['exit_code'] = process.poll()
            raise
        finally:
            item['elapsed_seconds'] = round(time.monotonic() - started, 3)
            item['finished_utc'] = datetime.now(timezone.utc).isoformat()
            item['log_sha256'] = sha(log) if log.exists() else None
            save('receipt.json', receipt)
            print(json.dumps({'event': 'command-finish', **item}), flush=True)
        if item['status'] != 'passed':
            raise RuntimeError(name + ' failed, timed out, or had no successful test count')

    config = SOURCE / '.dart_tool/package_config.json'
    original = config.read_bytes() if config.exists() else None
    original_parent = config.parent.exists()
    try:
        for name, (package, tests) in cohorts.items():
            prefix = [dart, 'test'] if package == 'engine' else [dart, snapshot, 'test', '--no-pub']
            command(name, [*prefix, '--concurrency=2', '--reporter', 'expanded', *tests], HARNESSES / ('quds_office_' + package), test=True)
        for package in ['engine', 'editor']:
            config.parent.mkdir(exist_ok=True)
            config.write_text(json.dumps(graphs[package], indent=2) + '\n')
            command(package + '-strict-analysis', [dart, 'analyze', '--fatal-infos', *TARGETS[package]], SOURCE)
        command('dart-3.12-format-check', [dart, 'format', '--language-version=3.12', '--output=none', '--set-exit-if-changed', *TARGETS['engine'], *TARGETS['editor']], SOURCE)
    finally:
        if original is None:
            config.unlink(missing_ok=True)
            if not original_parent and config.parent.exists() and not any(config.parent.iterdir()):
                config.parent.rmdir()
        else:
            config.write_bytes(original)
        after = source_fingerprint()
        dependencies_after = dependencies_fingerprint(graphs)
        inputs_after = harness_inputs()
        save('source-after.json', after)
        save('dependencies-after.json', dependencies_after)
        receipt['analysis_config_restored'] = (config.read_bytes() if config.exists() else None) == original
        receipt['source_inputs_unchanged'] = before == after
        receipt['external_dependency_and_runtime_inputs_unchanged'] = dependencies_before == dependencies_after
        receipt['harness_input_sha256_after'] = inputs_after
        receipt['harness_inputs_unchanged'] = inputs_before == inputs_after
        receipt['working_head_at_end'] = git_text('rev-parse', 'HEAD')
        receipt['published_source_still_matches'] = not published_matches(after['sha256_by_path'])
        receipt['passed_tests_by_cohort'] = {row['name']: row['passed_tests'] for row in receipt['commands'] if 'passed_tests' in row}
        receipt['zotero_passed_tests'] = sum(n or 0 for name, n in receipt['passed_tests_by_cohort'].items() if 'zotero' in name)
        receipt['integration_passed_tests'] = sum(n or 0 for name, n in receipt['passed_tests_by_cohort'].items() if 'integration' in name)
        receipt['total_disjoint_tests_passed'] = receipt['zotero_passed_tests'] + receipt['integration_passed_tests']
        receipt['all_passed'] = (
            len(receipt['commands']) == len(cohorts) + 3
            and all(row['exit_code'] == 0 and row['status'] == 'passed' for row in receipt['commands'])
            and all(receipt[key] for key in ['analysis_config_restored', 'source_inputs_unchanged', 'external_dependency_and_runtime_inputs_unchanged', 'harness_inputs_unchanged', 'published_source_still_matches'])
        )
        receipt['status'] = 'passed' if receipt['all_passed'] else 'failed'
        receipt['finished_utc'] = datetime.now(timezone.utc).isoformat()
        save('receipt.json', receipt)
        print(json.dumps({key: receipt[key] for key in ['all_passed', 'passed_tests_by_cohort', 'zotero_passed_tests', 'integration_passed_tests', 'total_disjoint_tests_passed', 'source_inputs_unchanged', 'external_dependency_and_runtime_inputs_unchanged', 'analysis_config_restored']}), flush=True)
    if not receipt['all_passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    with (OUTPUT / 'qualification.lock').open('a+') as run_lock:
        try:
            fcntl.flock(run_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('Another qualification is already active in this output directory.')
        try:
            main()
        except BaseException as error:
            if not isinstance(error, SystemExit) or error.code not in (None, 0):
                save('runner-error.json', {
                    'recorded_utc': datetime.now(timezone.utc).isoformat(),
                    'error': type(error).__name__ + ': ' + str(error),
                    'traceback': traceback.format_exc(),
                    'test_commands_and_success_gates_weakened': False,
                })
            raise

#!/usr/bin/env python3
"""Qualify the combined published Zotero host with an already locked local harness.

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
import signal
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urljoin, urlparse

COMMAND_TIMEOUT_SECONDS = 600
HEARTBEAT_SECONDS = 15
TERMINATION_GRACE_SECONDS = 10
EXPECTED_COMMANDS = (
    'vendor-source', 'vendor-tracked', 'host-tests', 'host-analysis',
    'vendor-analysis', 'host-format', 'vendor-format',
    'python-sync-verifier-tests', 'whitespace', 'vendor-tracked-final',
)

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
    'packages/quds_office_engine/lib/src/fonts/font_subsetter.dart',
    'packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart',
    'packages/quds_office_engine/lib/src/pdf/pdf_canvas.dart',
    'packages/quds_office_engine/lib/src/pdf/pdf_document.dart',
    'packages/quds_office_engine/lib/src/pdf/pdf_font.dart',
    'packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_reader.dart',
    'packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_writer.dart',
    'packages/quds_office_engine/lib/src/sheet/model/sml_workbook.dart',
    'packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart',
    'packages/quds_office_engine/lib/src/word/model/word_zotero.dart',
    'packages/quds_office_engine/lib/src/zotero/zotero_client.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_format.dart',
    'packages/quds_office_editor/lib/src/editor_word/caret_engine.dart',
    'packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart',
    'packages/quds_office_editor/test/word_hyphenation_caret_test.dart',
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


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_name = None
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
            os.fchmod(temporary.fileno(), mode)
            temporary_name = temporary.name
            temporary.write(data)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
    finally:
        if temporary_name is not None and os.path.exists(temporary_name):
            os.unlink(temporary_name)


def save(path, value):
    write_atomic(path, (json.dumps(value, indent=2, sort_keys=True) + '\n').encode())


def stop_owned_process_group(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=TERMINATION_GRACE_SECONDS)


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
    parser.add_argument('--quds-commit', required=True, help='Full published canonical commit SHA')
    parser.add_argument('--source-commit', required=True, help='Full published CrispCloud implementation commit SHA')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    repo, harness, quds, output = (path.resolve() for path in (args.repo, args.harness, args.quds_source, args.output))
    flutter = Path(os.environ['FLUTTER_ROOT']).resolve()
    dart = flutter / 'bin/cache/dart-sdk/bin/dart'
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in ('receipt.json', 'source-before.json', 'dependencies-before.json')):
        raise ValueError('Use a fresh output directory; prior qualification evidence cannot be overwritten')
    started_utc = now()
    receipt = {
        'schema_version': 3, 'status': 'initializing', 'phase': 'validating-source-and-harness',
        'repository': 'CrispStrobe/CrispCloud', 'started_utc': started_utc,
        'published_source': args.source_commit, 'expected_canonical_source': args.quds_commit,
        'repo': str(repo), 'harness': str(harness), 'quds_source': str(quds),
        'commands': [], 'expected_commands': list(EXPECTED_COMMANDS),
        'command_timeout_seconds': COMMAND_TIMEOUT_SECONDS,
        'heartbeat_seconds': HEARTBEAT_SECONDS,
        'termination_grace_seconds': TERMINATION_GRACE_SECONDS,
        'reproduction_script_sha256': digest(Path(__file__).read_bytes()),
    }
    save(output / 'receipt.json', receipt)
    print(f'qualification started: {args.source_commit}', flush=True)

    def interrupted(signum, frame):
        raise InterruptedError(f'Received signal {signum}')

    signal.signal(signal.SIGTERM, interrupted)
    for name, commit, checkout in (('source', args.source_commit, repo), ('canonical', args.quds_commit, quds)):
        if re.fullmatch(r'[0-9a-f]{40}', commit) is None or git(checkout, 'rev-parse', '--verify', commit + '^{commit}') != commit:
            raise ValueError(f'The {name} identity must be an available full immutable commit SHA')
    manifest = json.loads((repo / 'tool/office_fidelity_manifest.json').read_text())
    if manifest['source_commit'] != args.quds_commit:
        raise ValueError('Host manifest does not match the requested canonical source')
    published_tree = git(repo, 'rev-parse', args.source_commit + '^{tree}')
    initial_tree = git(repo, 'rev-parse', 'HEAD^{tree}')
    if initial_tree != published_tree:
        raise ValueError('Actual starting source tree differs from the published implementation tree')
    input_roots = ['lib', 'packages', 'tool', 'test', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']
    if subprocess.run(['git', 'diff', '--quiet', args.source_commit, '--', *input_roots], cwd=repo).returncode:
        raise ValueError('Tracked qualification inputs differ from the published source commit')
    source_before = source_snapshot(repo)
    deps_before = dependency_snapshot(harness, flutter, repo)
    save(output / 'source-before.json', source_before)
    save(output / 'dependencies-before.json', deps_before)
    receipt.update({
        'status': 'running', 'phase': 'preparing-analyzer',
        'repository': 'CrispStrobe/CrispCloud', 'started_utc': started_utc,
        'tracked_inputs_match_published_source': True,
        'head_at_start': git(repo, 'rev-parse', 'HEAD'), 'published_source': args.source_commit, 'source_commit': args.source_commit,
        'implementation_tree': initial_tree, 'expected_canonical_source': args.quds_commit, 'quds_commit': args.quds_commit,
        'canonical_tree': git(quds, 'rev-parse', args.quds_commit + '^{tree}'),
        'managed_office_files': len(manifest['files']), 'tests': list(TESTS), 'expected_test_count': 41,
        'host_analysis_targets': list(HOST_TARGETS), 'vendored_analysis_targets': list(VENDORED_TARGETS),
        'source_file_count': len(source_before), 'dependency_file_count': len(deps_before['dependency_files']),
        'dependency_package_count': deps_before['package_count'], 'pub_get_rerun': False, 'expected_python_test_count': 28,
        'source_before_aggregate_sha256': aggregate(source_before), 'dependencies_before_aggregate_sha256': aggregate(deps_before),
        'reproduction_script_sha256': digest(Path(__file__).read_bytes()), 'commands': [],
        'runtime': json.loads((flutter / 'bin/cache/flutter.version.json').read_text()),
        'limitations': ['Focused genuine locked dependency graph; no full application compile or full production dependency resolution.',
                       'Network, credentials and protocol interactions use test doubles; no live Zotero account, desktop picker, Word/LibreOffice or keychain acceptance.',
                       'Canonical tests are qualified separately; these counts are distinct host tests.',
                       'No GitHub Actions, status, workflow or job queries, waits or reruns.'],
    })
    save(output / 'receipt.json', receipt)
    config = harness / '.dart_tool/package_config.json'
    analyzer_graph = json.loads(config.read_text())
    for entry in analyzer_graph['packages']:
        name = entry['name']
        root = repo if name == 'crisp_cloud' else (repo / 'packages' / name if name in PACKAGES else resolve(config, entry['rootUri']))
        entry['rootUri'] = root.as_uri() + '/'
    target = repo / '.dart_tool/package_config.json'
    previous = target.read_bytes() if target.exists() else None
    receipt['analysis_config_preexisting'] = previous is not None
    receipt['analysis_config_before_sha256'] = digest(previous) if previous is not None else None
    if previous is not None:
        write_atomic(output / 'analysis-config-before.bin', previous)
        receipt['analysis_config_before_backup'] = 'analysis-config-before.bin'
    save(output / 'receipt.json', receipt)
    target.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(target, (json.dumps(analyzer_graph, indent=2) + '\n').encode())
    save(output / 'analysis-package-config.json', analyzer_graph)
    receipt['analysis_config_sha256'] = digest(target.read_bytes())
    receipt['phase'] = 'ready-to-run'
    save(output / 'receipt.json', receipt)

    def run(name, command, cwd):
        started = now()
        start = time.monotonic()
        log = output / f'{name}.log'
        row = {
            'name': name, 'command': command, 'cwd': str(cwd),
            'started_utc': started, 'status': 'running', 'log': log.name,
            'timeout_seconds': COMMAND_TIMEOUT_SECONDS,
        }
        receipt['commands'].append(row)
        receipt.update(status='running', phase=name, active_command=name)
        save(output / 'receipt.json', receipt)
        print(f'{name}: started; deadline {COMMAND_TIMEOUT_SECONDS}s', flush=True)
        process = None
        timed_out = False
        execution_error = None
        try:
            with log.open('w') as stream:
                process = subprocess.Popen(
                    command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                row['process_id'] = process.pid
                row['process_group_id'] = process.pid
                save(output / 'receipt.json', receipt)
                while True:
                    elapsed = time.monotonic() - start
                    remaining = COMMAND_TIMEOUT_SECONDS - elapsed
                    if remaining <= 0:
                        timed_out = True
                        row['timeout_observed_utc'] = now()
                        row['timed_out'] = True
                        receipt['phase'] = f'{name}:terminating-timeout'
                        save(output / 'receipt.json', receipt)
                        print(f'{name}: deadline exceeded; terminating owned process group', flush=True)
                        stop_owned_process_group(process)
                        break
                    try:
                        process.wait(timeout=min(HEARTBEAT_SECONDS, remaining))
                        break
                    except subprocess.TimeoutExpired:
                        row['elapsed_seconds'] = round(time.monotonic() - start, 3)
                        row['last_heartbeat_utc'] = now()
                        row['log_bytes'] = log.stat().st_size
                        save(output / 'receipt.json', receipt)
                        print(f'{name}: running {row["elapsed_seconds"]:.1f}s; log {row["log_bytes"]} bytes', flush=True)
                stream.flush()
                os.fsync(stream.fileno())
        except BaseException as error:
            execution_error = f'{type(error).__name__}: {error}'
            if process is not None and process.poll() is None:
                try:
                    stop_owned_process_group(process)
                except BaseException as cleanup_error:
                    execution_error += f'; cleanup {type(cleanup_error).__name__}: {cleanup_error}'
        finally:
            payload = log.read_bytes() if log.exists() else b''
            row.update(
                finished_utc=now(), duration_seconds=round(time.monotonic() - start, 3),
                exit_code=process.returncode if process is not None else None,
                log_sha256=digest(payload), timed_out=timed_out,
                execution_error=execution_error,
            )
            row['status'] = ('timed_out' if timed_out else
                             'failed' if execution_error or row['exit_code'] != 0 else 'passed')
            receipt['active_command'] = None
            receipt['phase'] = f'{name}:completed'
            save(output / 'receipt.json', receipt)
        print(f'{name}: exit {row["exit_code"]}; {row["status"]}', flush=True)
        if row['status'] != 'passed':
            print(payload.decode(errors='replace')[-6500:], flush=True)
            raise RuntimeError(f'{name} {row["status"]}; see {log.name}; {execution_error or ""}')
        return payload.decode()

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
        if receipt['passed_python_tests'] != 28:
            raise RuntimeError('Executed Python test count differs from the 28-test sync/verifier cohort')
        run('whitespace', ['git', 'diff', '--check'], repo)
        run('vendor-tracked-final', [sys.executable, 'tool/verify_office_fidelity.py', '--source', str(quds), '--require-tracked'], repo)
    except BaseException as error:
        failure = f'{type(error).__name__}: {error}'
    finally:
        receipt.update(status='finalizing', phase='restoring-config-and-verifying-inputs', error=failure)
        save(output / 'receipt.json', receipt)
        if previous is None:
            target.unlink(missing_ok=True)
            try:
                target.parent.rmdir()
            except OSError:
                pass
        else:
            write_atomic(target, previous)
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
        completed = [row['name'] for row in receipt['commands'] if row.get('status') == 'passed']
        receipt['all_required_commands_completed'] = completed == list(EXPECTED_COMMANDS)
        if not receipt['all_required_commands_completed']:
            failure = (failure + '; ' if failure else '') + 'Not all required commands completed'
        receipt['phase'] = 'completed'
        receipt['status'] = 'passed' if failure is None else 'failed'
        receipt['error'] = failure
        save(output / 'receipt.json', receipt)
    print(json.dumps({k: receipt.get(k) for k in ('status', 'passed_host_tests', 'passed_python_tests', 'source_file_count', 'dependency_file_count', 'source_unchanged', 'dependencies_unchanged', 'analysis_config_restored', 'error')}, indent=2))
    return 0 if failure is None else 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Compare final local qualification with the frozen, committed app source."""
import ast
import datetime
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

EVIDENCE = Path(__file__).resolve().parent
ROOT = EVIDENCE.parents[2]
SOURCE_COMMIT = '047adfb944ad9f46acc65e0c8c38376b3949f3da'
PHASES = ['native', 'engine-final', 'live', 'visual', 'analysis', 'format', 'web']
EXPECTED_SDK = {
    'bin/dart': '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',
    'bin/dartaotruntime': '3599c987228070f342c80d29353f496c8efc72c620c75fc4d59e5671666b2f72',
    'bin/snapshots/dart2js_aot.dart.snapshot': '29314b1f8e994436c5639a59df0243692cd83625fc587619a9c99e9a3804b1d6',
}
EXPECTED_MODES = {name: 0o100755 if name != 'bin/snapshots/dart2js_aot.dart.snapshot'
                  else 0o100644 for name in EXPECTED_SDK}
EXPECTED_COUNTS = {
    'native': {'passed': 1075, 'skipped': 2, 'failed': 0},
    'engine-final': {'passed': 209, 'skipped': 0, 'failed': 0},
    'live': {'passed': 22, 'skipped': 3, 'failed': 0},
    'visual': {'passed': 2, 'skipped': 0, 'failed': 0},
}
spec = importlib.util.spec_from_file_location(
    'terminal_validation', ROOT / 'tool/run_terminal_validation.py')
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode().strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree(commit):
    result = {}
    raw = subprocess.check_output(['git', 'ls-tree', '-r', '-z', commit], cwd=ROOT)
    for entry in raw.split(b'\0'):
        if entry:
            metadata, path = entry.split(b'\t', 1)
            mode, kind, oid = metadata.decode().split()
            result[path.decode()] = (mode, kind, oid)
    return result


head = git('rev-parse', 'HEAD')
sources = validation.source_hashes()
committed = tree(SOURCE_COMMIT)
current = tree(head)
extensions = {'.dart', '.rs', '.c', '.cpp', '.h', '.yaml', '.lock', '.toml'}
root_inputs = {'.fvmrc', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}
frozen_paths = {path for path in committed
                if (path.startswith(('lib/', 'test/', 'packages/'))
                    and Path(path).suffix in extensions) or path in root_inputs}
source_errors = list(frozen_paths.symmetric_difference(sources))
for path in frozen_paths:
    file = ROOT / path
    if not file.is_file():
        source_errors.append(path)
        continue
    content = file.read_bytes()
    oid = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
    mode = '100755' if file.stat().st_mode & 0o111 else '100644'
    expected = (mode, 'blob', oid)
    if committed.get(path) != expected or current.get(path) != expected:
        source_errors.append(path)
source_errors = sorted(set(source_errors))

frozen_runner = ast.parse(git('show', f'{SOURCE_COMMIT}:tool/run_terminal_validation.py'))
new_suites = next(ast.literal_eval(node.value) for node in frozen_runner.body
                  if isinstance(node, ast.Assign)
                  and any(isinstance(target, ast.Name) and target.id == 'NEW_TESTS'
                          for target in node.targets))
baseline_suites = json.loads(git('show', f'{SOURCE_COMMIT}:docs/validation/terminal-parity-continuation/native-summary.json'))['suite_files']
native_suites = sorted(set(baseline_suites + new_suites))
static_files = json.loads(git('show', f'{SOURCE_COMMIT}:docs/validation/terminal-session-optimization-20261116/analysis.json'))['files']
engine_suites = ['test/ods_sheet_reader_test.dart', 'test/zotero_metadata_batch_test.dart',
                 'test/zotero_client_test.dart', 'test/word_zotero_scaling_test.dart',
                 'test/word_zotero_citing_test.dart']
live_suites = ['test/ssh_terminal_live_test.dart', 'test/ssh_port_forwarding_live_test.dart',
               'test/ssh_agent_live_test.dart', 'test/ssh_connection_sharing_live_test.dart']
visual_suites = ['test/terminal_workspace_recovery_visual_test.dart', 'test/tmux_control_visual_test.dart']
visual_defines = ['--dart-define=TERMINAL_RECOVERY_VISUALS=true',
                  f'--dart-define=TERMINAL_RECOVERY_VISUAL_DIR={EVIDENCE.relative_to(ROOT)}/visuals/recovery',
                  '--dart-define=TMUX_CONTROL_VISUALS=true',
                  f'--dart-define=TMUX_CONTROL_VISUAL_DIR={EVIDENCE.relative_to(ROOT)}/visuals/tmux']
version = next(line.split(':', 1)[1].strip()
               for line in git('show', f'{SOURCE_COMMIT}:pubspec.yaml').splitlines()
               if line.startswith('version:'))

record = {
    'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_commit': SOURCE_COMMIT,
    'recorded_at_commit': head,
    'scope': 'The source/test/dependency file set selected by tool/run_terminal_validation.py.',
    'watched_source_count': len(sources),
    'frozen_watched_source_count': len(frozen_paths),
    'watched_path_sets_equal': set(sources) == frozen_paths,
    'watched_files_match_frozen_and_current_committed_blobs_and_modes': not source_errors,
    'source_errors': source_errors,
    'github_actions_queried_or_awaited': False,
    'phases': {},
}

for phase in PHASES:
    receipt_path = EVIDENCE / f'{phase}.json'
    receipt = json.loads(receipt_path.read_text())
    inventory_path = EVIDENCE / f'{phase}-source-sha256.json.gz'
    if inventory_path.exists():
        inventory = json.loads(gzip.decompress(inventory_path.read_bytes()))
    else:
        inventory_path = EVIDENCE / f'{phase}-source-sha256.json'
        inventory = json.loads(inventory_path.read_text())
    phase_head = receipt['head_at_start']
    changed_at_head = set(git('diff', '--name-only', SOURCE_COMMIT, phase_head).splitlines())
    changed_watched = sorted(changed_at_head.intersection(sources))
    ancestor = subprocess.run(
        ['git', 'merge-base', '--is-ancestor', phase_head, head], cwd=ROOT).returncode == 0
    command = receipt['command']
    coverage = True
    if phase == 'native':
        coverage = (command == ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', *native_suites]
                    and receipt['suite_files'] == native_suites and receipt['suite_count'] == 85)
    elif phase == 'engine-final':
        coverage = command == ['dart', 'test', '--concurrency=1', '--reporter=expanded', *engine_suites]
    elif phase == 'live':
        coverage = (command[1:] == ['tool/run_terminal_live_smoke.py', '--flutter', 'flutter', '--with-unix-agent']
                    and receipt['suite_files'] == live_suites and receipt['suite_count'] == 4)
    elif phase == 'visual':
        coverage = command == ['flutter', 'test', '--no-pub', '--concurrency=1', '--reporter=expanded', *visual_defines, *visual_suites]
    elif phase in {'analysis', 'format'}:
        options = ['analyze'] if phase == 'analysis' else ['format', '--output=none', '--set-exit-if-changed']
        coverage = (command[1:] == [*options, *static_files]
                    and receipt['files'] == static_files and receipt['file_count'] == 164)
    elif phase == 'web':
        coverage = command == ['flutter', 'build', 'web', '--release', '--no-pub',
                               '--no-wasm-dry-run', f'--dart-define=APP_VERSION={version}',
                               f'--dart-define=GIT_HASH={phase_head[:8]}']
    if phase in EXPECTED_COUNTS:
        coverage = coverage and receipt.get('counts') == EXPECTED_COUNTS[phase]
    record['phases'][phase] = {
        'head_at_start': phase_head,
        'phase_head_is_ancestor': ancestor,
        'watched_paths_changed_between_frozen_source_and_phase_head': changed_watched,
        'receipt': receipt_path.name,
        'receipt_sha256': sha(receipt_path),
        'inventory': inventory_path.name,
        'inventory_sha256': sha(inventory_path),
        'source_inventory_matches_current': inventory == sources,
        'watched_source_count_matches': receipt['watched_source_count'] == len(sources),
        'changed_sources_during_phase': receipt['changed_sources'],
        'exit_code': receipt['exit_code'],
        'seconds': receipt['seconds'],
        'counts': receipt.get('counts'),
        'required_command_suite_and_count_coverage': coverage,
    }

web = json.loads((EVIDENCE / 'web.json').read_text())
resource = json.loads((EVIDENCE / 'web-resource-run.json').read_text())
observations_path = EVIDENCE / 'web-resource-observations.json'
observations = json.loads(observations_path.read_text())
commands = sorted({process['command']
                   for sample in observations['samples'] for process in sample['processes']
                   if 'dart2js_aot.dart.snapshot' in process['command']})
sdk = ROOT.parent / 'toolchain/flutter/bin/cache/dart-sdk'
sdk_hashes = {name: sha(sdk / name) for name in EXPECTED_SDK}
sdk_modes = {name: (sdk / name).stat().st_mode for name in EXPECTED_MODES}
binding_keys = ['started_utc', 'finished_utc', 'heap_mb', 'exit_code', 'sdk',
                'sdk_before', 'sdk_after', 'sdk_modes_before', 'sdk_modes_after',
                'sdk_restored_exactly', 'command']
times = [datetime.datetime.fromisoformat(value) for value in [
    resource['started_utc'], web['started_utc'], web['finished_utc'], resource['finished_utc']]]
same_attempt = (resource['complete_record'] == observations_path.name
                and resource['complete_record_sha256'] == sha(observations_path)
                and resource['sample_count'] == len(observations['samples'])
                and all(resource[key] == observations.get(key) for key in binding_keys)
                and times == sorted(times)
                and resource['exit_code'] == web['exit_code'] == 0)
record['web'] = {
    'heap_mb': resource['heap_mb'],
    'observed_compiler_commands': commands,
    'standard_o4_and_minify_observed': bool(commands) and all(
        ' -O4 ' in command and ' --minify ' in command for command in commands),
    'sdk_restored_exactly': resource['sdk_restored_exactly'],
    'same_successful_build_attempt': same_attempt,
    'compiler_git_hash_matches_receipt': bool(commands) and all(
        f" -DGIT_HASH={web['head_at_start'][:8]} " in command for command in commands),
    'sdk_path_matches_prepared_toolchain': Path(resource['sdk']).resolve() == sdk.resolve(),
    'sdk_receipt_matches_pinned_sdk': resource['sdk_before'] == resource['sdk_after'] == EXPECTED_SDK,
    'sdk_receipt_modes_match_pinned_sdk': resource['sdk_modes_before'] == resource['sdk_modes_after'] == EXPECTED_MODES,
    'current_sdk_hashes_match_original': sdk_hashes == EXPECTED_SDK,
    'current_sdk_modes_match_original': sdk_modes == EXPECTED_MODES,
}
if web['exit_code'] == 0:
    output = ROOT / 'build/web/main.dart.js'
    artifact = {'bytes': output.stat().st_size, 'sha256': sha(output)}
    record['web']['main_dart_js'] = artifact
    record['web']['artifact_matches_receipt'] = artifact == web['main_dart_js']

record['all_source_inventories_identical_and_unchanged'] = not source_errors and all(
    phase['source_inventory_matches_current'] and phase['watched_source_count_matches']
    and not phase['changed_sources_during_phase'] and phase['phase_head_is_ancestor']
    and not phase['watched_paths_changed_between_frozen_source_and_phase_head']
    for phase in record['phases'].values())
record['all_selected_phases_passed'] = all(
    phase['exit_code'] == 0 and phase['required_command_suite_and_count_coverage']
    for phase in record['phases'].values())
record['sdk_integrity_passed'] = all(record['web'][key] for key in [
    'sdk_restored_exactly', 'current_sdk_hashes_match_original',
    'current_sdk_modes_match_original', 'sdk_path_matches_prepared_toolchain',
    'sdk_receipt_matches_pinned_sdk', 'sdk_receipt_modes_match_pinned_sdk'])
record['complete_acceptance'] = (
    record['all_source_inventories_identical_and_unchanged']
    and record['all_selected_phases_passed'] and record['sdk_integrity_passed']
    and record['web']['standard_o4_and_minify_observed']
    and record['web']['same_successful_build_attempt']
    and record['web']['compiler_git_hash_matches_receipt']
    and record['web'].get('artifact_matches_receipt', False))
output = EVIDENCE / 'acceptance-source-verification.json'
output.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({key: value for key, value in record.items()
                  if key not in {'phases', 'web'}}, indent=2))
raise SystemExit(0 if record['complete_acceptance'] else 1)

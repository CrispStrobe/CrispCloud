#!/usr/bin/env python3
"""Run local terminal acceptance and preserve commands, logs and source identity.

Uses the normal application graph; run flutter pub get --enforce-lockfile first.
No GitHub Actions or network-hosted test runner is used.
"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE = ROOT / 'docs/validation/terminal-parity-continuation'
NEW_TESTS = [
    'test/terminal_workspace_recovery_test.dart',
    'test/terminal_workspace_recovery_dialog_test.dart',
    'test/terminal_workspace_recovery_widget_test.dart',
    'test/terminal_panel_recovery_idle_test.dart',
    'test/ssh_connection_sharing_test.dart',
    'test/terminal_connection_sharing_test.dart',
    'test/ssh_shared_terminal_adapters_test.dart',
    'test/ssh_connection_sharing_widget_test.dart',
    'test/ssh_shared_forwarding_profiles_test.dart',
    'test/ssh_shared_channel_cleanup_test.dart',
    'test/tmux_control_protocol_test.dart',
    'test/tmux_control_client_test.dart',
    'test/tmux_control_workspace_test.dart',
    'test/ssh_native_tmux_persistence_test.dart',
    'test/terminal_input_budget_test.dart',
    'test/ssh_tmux_panel_lifecycle_test.dart',
    'test/ssh_agent_channel_test.dart',
    'test/ssh_agent_profiles_test.dart',
    'test/ssh_agent_route_test.dart',
    'test/ssh_agent_test.dart',
    'test/ssh_agent_widget_test.dart',
    'test/ssh_public_key_auth_test.dart',
    'test/ssh_forwarding_panel_test.dart',
    'test/ssh_forwarding_profiles_test.dart',
    'test/ssh_forwarding_profiles_widget_test.dart',
    'test/ssh_port_forwarding_model_test.dart',
    'test/ssh_port_forwarding_test.dart',
    'test/ssh_port_forwarding_widget_test.dart',
    'test/terminal_trigger_session_test.dart',
    'test/terminal_triggers_test.dart',
    'test/terminal_triggers_widget_test.dart',
]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def source_hashes():
    paths = git('ls-files', '--cached', '--others', '--exclude-standard').splitlines()
    extensions = {'.dart', '.rs', '.c', '.cpp', '.h', '.yaml', '.lock', '.toml'}
    selected = sorted(set(path for path in paths
                          if (path.startswith(('lib/', 'test/', 'packages/'))
                              and pathlib.Path(path).suffix in extensions)
                          or path in {'.fvmrc', 'pubspec.yaml', 'pubspec.lock',
                                      'analysis_options.yaml'}))
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in selected if (ROOT / path).is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['native', 'live', 'analysis', 'format', 'web'])
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--concurrency', type=int, default=2,
                        help='Parallel native test workers (use 1 on constrained hosts).')
    parser.add_argument('--evidence', type=pathlib.Path,
                        default=ROOT / 'docs/validation/terminal-forwarding-triggers')
    args = parser.parse_args()
    if args.concurrency < 1:
        parser.error('--concurrency must be positive')
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    suites = sorted(set(json.loads((BASELINE / 'native-summary.json').read_text())['suite_files'] + NEW_TESTS))
    prior_analysis = json.loads((BASELINE / 'analysis.json').read_text())
    analysis_files = set(path for path in prior_analysis['command'] if path.endswith('.dart'))
    changed = git('diff', '--name-only', 'origin/main').splitlines()
    changed += git('ls-files', '--others', '--exclude-standard').splitlines()
    analysis_files.update(path for path in changed
                          if path.startswith(('lib/', 'test/')) and path.endswith('.dart'))
    analysis_files.add('packages/crisp_storage/lib/src/host_keys.dart')
    analysis_files = sorted(analysis_files)
    head = git('rev-parse', 'HEAD')
    if args.phase == 'live':
        suites = ['test/ssh_terminal_live_test.dart', 'test/ssh_port_forwarding_live_test.dart',
                  'test/ssh_agent_live_test.dart', 'test/ssh_connection_sharing_live_test.dart']
    if args.phase == 'native':
        command = [args.flutter, 'test', '--no-pub', f'--concurrency={args.concurrency}',
                   '--reporter=expanded', *suites]
    elif args.phase == 'live':
        command = [sys.executable, 'tool/run_terminal_live_smoke.py', '--flutter', args.flutter,
                   '--with-unix-agent']
    elif args.phase == 'analysis':
        command = [args.dart, 'analyze', *analysis_files]
    elif args.phase == 'format':
        command = [args.dart, 'format', '--output=none', '--set-exit-if-changed', *analysis_files]
    else:
        version = re.search(r'^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(), re.M).group(1)
        command = [args.flutter, 'build', 'web', '--release', '--no-pub', '--no-wasm-dry-run',
                   f'--dart-define=APP_VERSION={version}', f'--dart-define=GIT_HASH={head[:8]}']
    before = source_hashes()
    record = {'phase': args.phase, 'command': command, 'head_at_start': head,
              'started_utc': stamp(), 'watched_source_count': len(before),
              'github_actions_queried_or_awaited': False}
    if args.phase in {'native', 'live'}:
        record.update(suite_count=len(suites), suite_files=suites)
    if args.phase in {'analysis', 'format'}:
        record.update(file_count=len(analysis_files), files=analysis_files)
    (evidence / f'{args.phase}-source-sha256.json').write_text(json.dumps(before, indent=2) + '\n')
    print(f'Running {args.phase}: {len(suites) if args.phase == "native" else len(analysis_files)} files; source {head[:8]}', flush=True)
    start = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='crisp-terminal-zsh-') as shell_config:
        environment = dict(os.environ)
        if args.phase == 'native':
            # Real PTY tests must not execute the developer's startup scripts.
            environment['ZDOTDIR'] = shell_config
            record['isolated_zsh_startup'] = True
        with (evidence / f'{args.phase}.log').open('w') as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log,
                                    stderr=subprocess.STDOUT, env=environment)
    after = source_hashes()
    record.update(finished_utc=stamp(), seconds=round(time.monotonic() - start, 3),
                  exit_code=result.returncode,
                  changed_sources=[path for path in sorted(before.keys() | after.keys())
                                   if before.get(path) != after.get(path)])
    if args.phase in {'native', 'live'}:
        lines = (evidence / f'{args.phase}.log').read_text().splitlines()
        final = next((line for line in reversed(lines) if 'All tests passed!' in line or 'Some tests failed.' in line), '')
        counts = re.search(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?:', final)
        if counts:
            record['counts'] = dict(zip(['passed', 'skipped', 'failed'],
                                       (int(value or 0) for value in counts.groups())))
        record['final_test_line'] = final
    if args.phase == 'web' and result.returncode == 0:
        output = ROOT / 'build/web/main.dart.js'
        record['main_dart_js'] = {'bytes': output.stat().st_size,
                                 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
    (evidence / f'{args.phase}.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({key: value for key, value in record.items()
                      if key not in {'command', 'files', 'suite_files'}}, indent=2), flush=True)
    return result.returncode or (1 if record['changed_sources'] else 0)


if __name__ == '__main__':
    raise SystemExit(main())

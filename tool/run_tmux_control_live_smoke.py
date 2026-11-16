#!/usr/bin/env python3
"""Run the native control client against an unmodified disposable tmux server.

The prerequisite probe reports an explicit skip when Unix sockets are denied.
Only this runner's unique scratch socket is ever passed to kill-server.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--tmux', default='tmux')
    parser.add_argument('--evidence', type=Path,
                        default=ROOT / 'docs/validation/terminal-tmux-control/live-tmux')
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    binary = shutil.which(args.tmux)
    record = {'recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'github_actions_queried_or_awaited': False, 'actual_feature_tests_completed': 0}
    result_code = 1
    try:
        if not binary:
            raise RuntimeError('Install tmux 3.2 or later to run actual tmux acceptance.')
        record['binary'] = binary
        version = subprocess.run([binary, '-V'], capture_output=True, text=True, timeout=10)
        record['version'] = version.stdout.strip()
        version.check_returncode()
        with tempfile.TemporaryDirectory(prefix='tmux-probe-', dir=os.environ.get('TMPDIR')) as path:
            socket = str(Path(path) / 'server')
            # Keep interactive zsh panes independent of user startup scripts.
            environment = dict(os.environ, ZDOTDIR=path)
            command = [binary, '-S', socket, '-f', '/dev/null', 'new-session',
                       '-d', '-s', 'crispcloud-probe']
            record['probe_command'] = command
            probe = None
            try:
                probe = subprocess.run(command, capture_output=True, text=True, timeout=10, env=environment)
                record.update(probe_exit_code=probe.returncode,
                              probe_stdout=probe.stdout, probe_stderr=probe.stderr)
                if probe.returncode:
                    if 'Operation not permitted' in probe.stderr or 'Permission denied' in probe.stderr:
                        record.update(status='skipped', reason='Host policy prevents an unmodified tmux Unix-socket server.')
                        result_code = 0
                    else:
                        raise RuntimeError('tmux prerequisite probe failed; see recorded stderr.')
                else:
                    command = [args.flutter, 'test', '--no-pub', '--concurrency=1',
                               '--reporter=expanded', '--dart-define=TMUX_CONTROL_LIVE=true',
                               f'--dart-define=TMUX_CONTROL_BINARY={binary}',
                               'test/tmux_control_live_test.dart']
                    record['command'] = command
                    with (args.evidence / 'live-tmux.log').open('w') as log:
                        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=environment)
                    result_code = result.returncode
                    record.update(status='passed' if result_code == 0 else 'failed', exit_code=result_code)
                    if result_code == 0:
                        record['actual_feature_tests_completed'] = 1
            finally:
                # A timed-out client may already have started the detached
                # server. Always attempt cleanup on this unique socket.
                cleanup = subprocess.run([binary, '-S', socket, 'kill-server'],
                                         capture_output=True, text=True, timeout=10)
                record.update(cleanup_exit_code=cleanup.returncode,
                              cleanup_stdout=cleanup.stdout,
                              cleanup_stderr=cleanup.stderr)
                if probe is not None and probe.returncode == 0:
                    cleanup.check_returncode()
    except Exception as error:
        record.update(status='failed', error=str(error))
        result_code = 1
    (args.evidence / 'live-tmux.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2))
    return result_code


if __name__ == '__main__':
    raise SystemExit(main())

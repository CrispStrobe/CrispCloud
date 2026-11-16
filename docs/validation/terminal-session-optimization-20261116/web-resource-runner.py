#!/usr/bin/env python3
"""Reproduce the production web build with a bounded compiler-only heap cap.

From this repository, using the prepared pinned toolchain:
  ../toolchain/run python3 docs/validation/terminal-session-optimization-20261116/web-resource-runner.py --preflight
  ../toolchain/run python3 docs/validation/terminal-session-optimization-20261116/web-resource-runner.py --run

Preflight never replaces an SDK file. Run the full build only after other users
of this shared SDK have finished. The runner restores the exact Dart executable
on normal completion, exceptions, SIGINT, and SIGTERM. If it is forcibly killed,
--restore-only verifies the retained original before restoring it. No source,
dependency, release optimization, or SDK snapshot is changed by this runner.
"""

import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


HERE = Path(__file__).resolve().parent
EXPECTED = {
    'bin/dart': '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',
    'bin/dartaotruntime': '3599c987228070f342c80d29353f496c8efc72c620c75fc4d59e5671666b2f72',
    'bin/snapshots/dart2js_aot.dart.snapshot': '29314b1f8e994436c5639a59df0243692cd83625fc587619a9c99e9a3804b1d6',
}


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identities(sdk):
    return {name: sha(sdk / name) for name in EXPECTED}


def write_json(path, value):
    staged = path.with_suffix(path.suffix + '.tmp')
    staged.write_text(json.dumps(value, indent=2) + '\n')
    staged.replace(path)


def resources(child_pid):
    memory = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        if key in {'MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree', 'AnonPages'}:
            memory[key] = int(value.strip().split()[0])
    visible = {}
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            status = dict(line.split(':', 1)
                          for line in (proc / 'status').read_text().splitlines())
            visible[int(proc.name)] = {
                'pid': int(proc.name), 'ppid': int(status['PPid']),
                'name': status['Name'].strip(),
                'rss_kb': int(status.get('VmRSS', '0 kB').strip().split()[0]),
                'command': (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace').strip(),
            }
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    owned = {child_pid}
    while True:
        descendants = {pid for pid, item in visible.items() if item['ppid'] in owned}
        if descendants.issubset(owned):
            break
        owned.update(descendants)
    return {'utc': stamp(), 'memory_kb': memory,
            'processes': [visible[pid] for pid in sorted(owned) if pid in visible]}


def stop_child(child):
    if child is None or child.poll() is not None:
        return
    os.killpg(child.pid, signal.SIGTERM)
    try:
        child.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()


def preflight(args, sdk, launcher):
    before = identities(sdk)
    if before != EXPECTED:
        raise RuntimeError('Pinned SDK identities differ from Flutter 3.47.8 / Dart 3.13.7')
    if (sdk / 'bin/dart.resource-original').exists():
        raise RuntimeError('SDK backup exists; inspect the previous run or use --restore-only')
    env = os.environ.copy()
    env.update(CRISP_DART_SDK_ROOT=str(sdk), CRISP_DART_ORIGINAL=str(sdk / 'bin/dart'),
               CRISP_DART_HEAP_MB=str(args.heap_mb))
    record = {'started_utc': stamp(), 'sdk': str(sdk), 'heap_mb': args.heap_mb,
              'sdk_before': before, 'launcher_sha256': sha(launcher),
              'sdk_files_replaced': False, 'full_web_build_started': False,
              'github_actions_queried_or_awaited': False}
    args.evidence.mkdir(parents=True, exist_ok=True)
    log_path = args.evidence / 'web-resource-preflight.log'
    with log_path.open('w') as log:
        subprocess.run(['bash', '-n', str(launcher)], stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(['bash', str(launcher), '--version'], env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        flags = subprocess.run([
            str(sdk / 'bin/dartaotruntime'), f'--old_gen_heap_size={args.heap_mb}', '--print_flags',
            str(sdk / 'bin/snapshots/dart2js_aot.dart.snapshot'), '--version',
        ], text=True, capture_output=True, check=True)
        flag_output = flags.stdout + flags.stderr
        log.write(flag_output)
        record['old_gen_heap_flag'] = next(
            line.strip() for line in flag_output.splitlines()
            if 'old_gen_heap_size:' in line and str(args.heap_mb) in line)
        scratch = args.toolchain / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='web-resource-preflight-', dir=scratch) as temporary:
            probe = Path(temporary) / 'probe.dart'
            output = Path(temporary) / 'probe.js'
            probe.write_text("void main() { print('compiler resource probe'); }\n")
            command = ['bash', str(launcher), 'compile', 'js', '-O4', '--minify',
                       '--no-source-maps', str(probe), '-o', str(output)]
            log.flush()
            subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            record['tiny_release_probe'] = {
                'command': command, 'exit_code': 0, 'source_sha256': sha(probe),
                'javascript_sha256': sha(output), 'javascript_bytes': output.stat().st_size,
            }
            node = shutil.which('node')
            if node:
                result = subprocess.run([node, str(output)], capture_output=True, text=True, check=True)
                if result.stdout.strip() != 'compiler resource probe':
                    raise RuntimeError('Unexpected compiled probe output')
                record['tiny_release_probe']['node_stdout'] = result.stdout.strip()
    record.update(finished_utc=stamp(), sdk_after=identities(sdk))
    record['sdk_unchanged'] = record['sdk_after'] == before
    write_json(args.evidence / 'web-resource-preflight.json', record)
    if not record['sdk_unchanged']:
        raise RuntimeError('SDK changed during preflight')
    print(json.dumps(record, indent=2), flush=True)
    return 0


def run(args, sdk, launcher):
    dart = sdk / 'bin/dart'
    original = sdk / 'bin/dart.resource-original'
    staged = sdk / 'bin/dart.resource-launcher-temp'
    before = identities(sdk)
    modes = {name: (sdk / name).stat().st_mode for name in EXPECTED}
    if before != EXPECTED or original.exists() or staged.exists():
        raise RuntimeError('Pinned SDK identity/backup precondition failed')
    command = [sys.executable, 'tool/run_terminal_validation.py', 'web',
               '--evidence', str(args.evidence)]
    record = {'started_utc': stamp(), 'command': command, 'heap_mb': args.heap_mb,
              'sdk': str(sdk), 'sdk_before': before, 'sdk_modes_before': modes,
              'launcher_sha256': sha(launcher), 'application_or_dependency_changes': False,
              'compiler_args': 'Unchanged Flutter compile-js arguments; SDK implicit arguments preserved.',
              'process_scope': 'Only the launched validation process and visible descendants.',
              'github_actions_queried_or_awaited': False, 'samples': []}
    child = None
    installed = False
    started = time.monotonic()
    args.evidence.mkdir(parents=True, exist_ok=True)
    full_record = args.evidence / 'web-resource-observations.json'
    try:
        shutil.copy2(launcher, staged)
        staged.chmod(modes['bin/dart'])
        os.replace(dart, original)
        installed = True
        os.replace(staged, dart)
        env = os.environ.copy()
        env.update(CRISP_DART_SDK_ROOT=str(sdk), CRISP_DART_ORIGINAL=str(original),
                   CRISP_DART_HEAP_MB=str(args.heap_mb))
        with (args.evidence / 'web-resource-runner.log').open('w') as log:
            child = subprocess.Popen(command, cwd=args.repo, env=env, stdout=log,
                                     stderr=subprocess.STDOUT, start_new_session=True)
            while child.poll() is None:
                record['samples'].append(resources(child.pid))
                write_json(full_record, record)
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    pass
        record['exit_code'] = child.returncode
    except BaseException as error:
        record['runner_error'] = f'{type(error).__name__}: {error}'
        raise
    finally:
        try:
            stop_child(child)
        finally:
            if installed:
                if sha(original) != EXPECTED['bin/dart']:
                    raise RuntimeError('Retained original Dart executable failed its identity check')
                os.replace(original, dart)
            staged.unlink(missing_ok=True)
            record['sdk_after'] = identities(sdk)
            record['sdk_modes_after'] = {name: (sdk / name).stat().st_mode for name in EXPECTED}
            record['sdk_restored_exactly'] = (record['sdk_after'] == before
                                            and record['sdk_modes_after'] == modes)
            record.update(finished_utc=stamp(), seconds=round(time.monotonic() - started, 3))
            record['peak_visible_rss_kb'] = max(
                (sum(proc['rss_kb'] for proc in item['processes']) for item in record['samples']), default=0)
            record['minimum_available_memory_kb'] = min(
                (item['memory_kb']['MemAvailable'] for item in record['samples']), default=0)
            write_json(full_record, record)
            summary = {key: value for key, value in record.items() if key != 'samples'}
            summary.update(sample_count=len(record['samples']), complete_record=full_record.name,
                           complete_record_sha256=sha(full_record))
            write_json(args.evidence / 'web-resource-run.json', summary)
            print(json.dumps(summary, indent=2), flush=True)
    if not record['sdk_restored_exactly']:
        raise RuntimeError('SDK binary or mode restoration failed')
    return record.get('exit_code', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--preflight', action='store_true', help='Verify compiler without replacing SDK files (default).')
    actions.add_argument('--run', action='store_true', help='Run the full release build after all other SDK users finish.')
    actions.add_argument('--restore-only', action='store_true', help='Recover the verified original after a forcibly interrupted run.')
    parser.add_argument('--heap-mb', type=int, choices=[2048, 3072, 4096], default=4096,
                        help='Compiler-only old-generation heap cap; release flags stay unchanged.')
    parser.add_argument('--repo', type=Path, default=HERE.parents[2])
    parser.add_argument('--toolchain', type=Path)
    parser.add_argument('--evidence', type=Path, default=HERE)
    args = parser.parse_args()
    args.repo = args.repo.resolve()
    args.toolchain = (args.toolchain or args.repo.parent / 'toolchain').resolve()
    args.evidence = args.evidence.resolve()
    sdk = args.toolchain / 'flutter/bin/cache/dart-sdk'
    launcher = HERE / 'web-resource-launcher.sh'
    if not args.run and not args.restore_only:
        return preflight(args, sdk, launcher)
    with (args.toolchain / 'web-resource-runner.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.restore_only:
            original = sdk / 'bin/dart.resource-original'
            if sha(original) != EXPECTED['bin/dart']:
                raise RuntimeError('Retained original Dart executable failed its identity check')
            os.replace(original, sdk / 'bin/dart')
            (sdk / 'bin/dart.resource-launcher-temp').unlink(missing_ok=True)
            restored = identities(sdk)
            if restored != EXPECTED:
                raise RuntimeError('SDK restoration identity check failed')
            print(json.dumps({'sdk_restored_exactly': True, 'sdk_after': restored}, indent=2), flush=True)
            return 0
        def interrupted(signum, _frame):
            raise InterruptedError(f'Received signal {signum}')
        signal.signal(signal.SIGTERM, interrupted)
        return run(args, sdk, launcher)


if __name__ == '__main__':
    raise SystemExit(main())

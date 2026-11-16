#!/usr/bin/env python3
"""Run the existing web acceptance command with a compiler-only VM heap cap."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

WORK = Path(__file__).resolve().parent
REPO = WORK / 'CrispCloud'
SDK = WORK / 'toolchain/flutter/bin/cache/dart-sdk'
EVIDENCE = REPO / 'docs/validation/terminal-forwarding-triggers'
LAUNCHER = WORK / 'toolchain/dart-compiler-resource-launcher'
ORIGINAL = SDK / 'bin/dart.resource-original'
DART = SDK / 'bin/dart'
EXPECTED = '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb'
WATCH = ['bin/dart', 'bin/dartaotruntime',
         'bin/snapshots/dart2js_aot.dart.snapshot']


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resources():
    memory = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        if key in {'MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree', 'AnonPages'}:
            memory[key] = int(value.strip().split()[0])
    processes = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines())
            command = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace').strip()
            processes.append({'pid': int(proc.name), 'ppid': int(status['PPid']),
                              'name': status['Name'].strip(),
                              'rss_kb': int(status.get('VmRSS', '0 kB').strip().split()[0]),
                              'command': command})
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return {'utc': stamp(), 'memory_kb': memory, 'processes': processes}


def main():
    if ORIGINAL.exists() or sha(DART) != EXPECTED:
        raise RuntimeError('Pinned SDK Dart identity/backup precondition failed')
    before = {path: sha(SDK / path) for path in WATCH}
    command = [sys.executable, 'tool/run_terminal_validation.py', 'web']
    record = {'started_utc': stamp(), 'command': command, 'heap_mb': 3072,
              'sdk_before': before, 'launcher_sha256': sha(LAUNCHER),
              'application_or_dependency_changes': False,
              'compiler_args': 'Unchanged Flutter compile-js arguments; SDK implicit arguments preserved.',
              'github_actions_queried_or_awaited': False, 'samples': []}
    child = None
    installed = False
    started = time.monotonic()
    try:
        os.replace(DART, ORIGINAL)
        installed = True
        shutil.copy2(LAUNCHER, DART)
        DART.chmod(0o755)
        env = os.environ.copy()
        env['CRISP_COMPILER_HEAP_MB'] = '3072'
        child = subprocess.Popen(command, cwd=REPO, env=env)
        while child.poll() is None:
            record['samples'].append(resources())
            time.sleep(3)
        record['exit_code'] = child.returncode
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        if installed:
            DART.unlink(missing_ok=True)
            os.replace(ORIGINAL, DART)
        record['sdk_after'] = {path: sha(SDK / path) for path in WATCH}
        record['sdk_restored_exactly'] = record['sdk_after'] == before
        record['finished_utc'] = stamp()
        record['seconds'] = round(time.monotonic() - started, 3)
        record['peak_visible_rss_kb'] = max(
            (sum(p['rss_kb'] for p in sample['processes']) for sample in record['samples']),
            default=0)
        (EVIDENCE / 'web-resource-retry.json').write_text(json.dumps(record, indent=2) + '\n')
        print(json.dumps({key: value for key, value in record.items() if key != 'samples'}, indent=2), flush=True)
    if not record['sdk_restored_exactly']:
        raise RuntimeError('SDK binary restoration failed')
    return record.get('exit_code', 1)


if __name__ == '__main__':
    raise SystemExit(main())

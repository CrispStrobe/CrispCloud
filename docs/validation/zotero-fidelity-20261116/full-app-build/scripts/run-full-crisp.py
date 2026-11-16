import datetime
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import time

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / 'full-crisp-app'
DART = ROOT / 'flutter-sdk/bin/cache/dart-sdk/bin/dart'
FLUTTER = ROOT / 'flutter-sdk/bin/cache/flutter_tools.snapshot'
RECEIPT = ROOT / 'full-crisp-build-receipt.json'
receipt = json.loads(RECEIPT.read_text())
receipt['commands'] = []
deadline = time.monotonic() + 150
env = {**os.environ, 'PUB_CACHE': str(ROOT / 'pub-cache'), 'CI': 'true',
       'DART_SUPPRESS_ANALYTICS': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
       'FLUTTER_ROOT': str(ROOT / 'flutter-sdk'),
       'TMPDIR': str(ROOT / 'tmp'), 'XDG_CONFIG_HOME': str(ROOT / 'config')}

def run(name, arguments, limit):
    command = [str(DART), str(FLUTTER), *arguments]
    logfile = ROOT / f'full-crisp-{name}.log'
    started = time.monotonic()
    result = {'name': name, 'command': command, 'cwd': str(TARGET)}
    print('Starting', name, flush=True)
    with logfile.open('w') as output:
        try:
            completed = subprocess.run(command, cwd=TARGET, env=env,
                stdout=output, stderr=subprocess.STDOUT,
                timeout=max(1, min(limit, deadline - started)))
            result['exit_code'] = completed.returncode
            result['status'] = 'passed' if completed.returncode == 0 else 'failed'
        except subprocess.TimeoutExpired:
            result['status'] = 'timeout'
    result['seconds'] = round(time.monotonic() - started, 3)
    result['log'] = str(logfile.relative_to(ROOT))
    result['log_sha256'] = hashlib.sha256(logfile.read_bytes()).hexdigest()
    receipt['commands'].append(result)
    RECEIPT.write_text(json.dumps(receipt, indent=2) + '\n')
    print(name, result['status'], result['seconds'], flush=True)
    return result['status'] == 'passed'

try:
    if run('locked-restore', ['pub', 'get', '--offline', '--enforce-lockfile'], 45):
        run('bundle', ['build', 'bundle', '--debug', '--target-platform',
                      'linux-x64', '--no-pub'], 110)
finally:
    snapshot = runpy.run_path(str(ROOT / 'prepare-full-crisp.py'))['snapshot']
    after = snapshot()
    before = json.loads((ROOT / 'full-crisp-source-before.json').read_text())
    (ROOT / 'full-crisp-source-after.json').write_text(json.dumps(after, indent=2) + '\n')
    receipt['source_unchanged'] = before == after
    receipt['changed_source_paths'] = [p for p in sorted(set(before) | set(after))
                                       if before.get(p) != after.get(p)]
    receipt['isolated_lock_unchanged'] = hashlib.sha256(
        (TARGET / 'pubspec.lock').read_bytes()).hexdigest() == before['pubspec.lock']
    receipt['isolated_manifest_unchanged'] = hashlib.sha256(
        (TARGET / 'pubspec.yaml').read_bytes()).hexdigest() == before['pubspec.yaml']
    receipt['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    receipt['bundle_passed'] = any(c['name'] == 'bundle' and c['status'] == 'passed'
                                   for c in receipt['commands'])
    receipt['bundle_files'] = {
        str(p.relative_to(TARGET)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((TARGET / 'build/flutter_assets').rglob('*')) if p.is_file()
    }
    RECEIPT.write_text(json.dumps(receipt, indent=2) + '\n')
    print('source_unchanged', receipt['source_unchanged'], flush=True)

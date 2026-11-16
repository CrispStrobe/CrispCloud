import concurrent.futures
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parent
LOCK = ROOT / 'full-crisp-app/pubspec.lock'
CACHE = ROOT / 'pub-cache'
DART = ROOT / 'flutter-sdk/bin/cache/dart-sdk/bin/dart'
LOGS = ROOT / 'full-crisp-cache-logs'
LOGS.mkdir(exist_ok=True)
RECEIPT = ROOT / 'full-crisp-cache-receipt.json'

import yaml

lock_bytes = LOCK.read_bytes()
packages = yaml.safe_load(lock_bytes)['packages']
missing = [
    (name, package['version'])
    for name, package in packages.items()
    if package['source'] == 'hosted'
    and not (CACHE / 'hosted/pub.dev' / f"{name}-{package['version']}").is_dir()
]
deadline = time.monotonic() + 210
mutex = threading.Lock()
receipt = {
    'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'lock_sha256_before': hashlib.sha256(lock_bytes).hexdigest(),
    'method': 'Official dart pub cache add at exact locked versions',
    'hosted_count': sum(p['source'] == 'hosted' for p in packages.values()),
    'missing_at_start': len(missing),
    'deadline_seconds': 210,
    'workers': 10,
    'results': [],
}
env = {**os.environ, 'PUB_CACHE': str(CACHE), 'CI': 'true',
       'DART_SUPPRESS_ANALYTICS': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
       'FLUTTER_ROOT': str(ROOT / 'flutter-sdk'),
       'TMPDIR': str(ROOT / 'tmp'), 'XDG_CONFIG_HOME': str(ROOT / 'config')}

def warm(item):
    name, version = item
    command = [str(DART), 'pub', 'cache', 'add', name, '--version', version]
    result = {'name': name, 'version': version, 'command': command}
    started = time.monotonic()
    remaining = deadline - started
    logfile = LOGS / f'{name}-{version}.log'
    if remaining <= 0:
        result['status'] = 'not_started_at_deadline'
    else:
        with logfile.open('w') as log:
            try:
                completed = subprocess.run(command, env=env, cwd=ROOT,
                    stdout=log, stderr=subprocess.STDOUT,
                    timeout=min(50, remaining))
                result['exit_code'] = completed.returncode
                result['status'] = 'passed' if completed.returncode == 0 else 'failed'
            except subprocess.TimeoutExpired:
                result['status'] = 'timeout'
        result['log'] = str(logfile.relative_to(ROOT))
        result['log_sha256'] = hashlib.sha256(logfile.read_bytes()).hexdigest()
    result['seconds'] = round(time.monotonic() - started, 3)
    result['cached_after'] = (CACHE / 'hosted/pub.dev' / f'{name}-{version}').is_dir()
    with mutex:
        receipt['results'].append(result)
        RECEIPT.write_text(json.dumps(receipt, indent=2) + '\n')
        print(name, version, result['status'], flush=True)
    return result

with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
    list(pool.map(warm, missing))

receipt['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
receipt['lock_sha256_after'] = hashlib.sha256(LOCK.read_bytes()).hexdigest()
receipt['remaining_missing'] = [
    [name, p['version']] for name, p in packages.items()
    if p['source'] == 'hosted'
    and not (CACHE / 'hosted/pub.dev' / f"{name}-{p['version']}").is_dir()
]
RECEIPT.write_text(json.dumps(receipt, indent=2) + '\n')
print('Remaining missing:', len(receipt['remaining_missing']), flush=True)

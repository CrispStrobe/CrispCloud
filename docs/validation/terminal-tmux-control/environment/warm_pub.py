import concurrent.futures
import hashlib
import json
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import yaml

ROOT = pathlib.Path(__file__).resolve().parent
locks = [ROOT / 'flutter/pubspec.lock', ROOT.parent / 'CrispCloud/pubspec.lock']
cache = ROOT / 'pub-cache'
archives = ROOT / 'downloads/pub'
archives.mkdir(parents=True, exist_ok=True)
hosted = cache / 'hosted/pub.dev'
hosted.mkdir(parents=True, exist_ok=True)
hashes = cache / 'hosted-hashes/pub.dev'
hashes.mkdir(parents=True, exist_ok=True)
packages = {}
for lock in locks:
    for name, package in yaml.safe_load(lock.read_text())['packages'].items():
        if package['source'] != 'hosted':
            continue
        desc = package['description']
        assert desc['url'] == 'https://pub.dev', desc
        key = f'{name}-{package["version"]}'
        item = {'name': name, 'version': package['version'], 'key': key, 'sha256': desc['sha256']}
        if key in packages:
            assert packages[key] == item
        packages[key] = item

def warm(item):
    key = item['key']
    archive = archives / f'{key}.tar.gz'
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
        subprocess.run(['curl', '-fsSL', '--retry', '2', '--max-time', '120',
                        f'https://pub.dev/api/archives/{key}.tar.gz', '-o', str(archive)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual != item['sha256']:
        raise RuntimeError(f'{key}: checksum mismatch {actual}')
    destination = hosted / key
    if not destination.exists():
        stage = pathlib.Path(tempfile.mkdtemp(prefix=key + '-', dir=ROOT))
        try:
            with tarfile.open(archive, 'r:gz') as tar:
                tar.extractall(stage, filter='data')
            try:
                stage.rename(destination)
            except FileExistsError:
                pass
        finally:
            if stage.exists():
                shutil.rmtree(stage)
    (hashes / f'{key}.sha256').write_text(actual)
    print('Verified ' + key, flush=True)
    return {**item, 'bytes': archive.stat().st_size}

with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
    receipts = list(pool.map(warm, packages.values()))
(ROOT / 'pub-downloads.json').write_text(json.dumps(receipts, indent=2) + '\n')
print(f'Verified {len(receipts)} exact hosted archives.', flush=True)

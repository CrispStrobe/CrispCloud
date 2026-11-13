"""Install the three official hash-verified Rust components in scratch only."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib, json, subprocess, tarfile, urllib.request

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent
SELECTION = json.loads((BASE / 'rust-toolchain-selection.json').read_text())
PREFIX = ROOT / 'toolchains' / 'rust-1.100.0'
DOWNLOADS = BASE / 'rust-downloads'
DOWNLOADS.mkdir(exist_ok=True)

def download(item):
    name, metadata = item
    target = DOWNLOADS / metadata['xz_url'].rsplit('/', 1)[1]
    if not target.exists():
        with urllib.request.urlopen(metadata['xz_url'], timeout=60) as response:
            target.write_bytes(response.read())
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest != metadata['xz_hash']:
        raise RuntimeError(f'{name} archive hash mismatch')
    return {'component': name, 'url': metadata['xz_url'], 'sha256': digest,
            'bytes': target.stat().st_size, 'path': str(target)}

with ThreadPoolExecutor(max_workers=3) as pool:
    records = list(pool.map(download, SELECTION['components'].items()))
for record in records:
    archive = Path(record['path'])
    with tarfile.open(archive) as package:
        package.extractall(DOWNLOADS, filter='data')
    installer = DOWNLOADS / archive.name.removesuffix('.tar.xz') / 'install.sh'
    command = ['sh', str(installer), '--prefix=' + str(PREFIX), '--disable-ldconfig']
    result = subprocess.run(command, capture_output=True, text=True)
    record.update(command=command, exitCode=result.returncode,
                  stdout=result.stdout, stderr=result.stderr)
    if result.returncode:
        raise RuntimeError(record)
    print(record['component'], record['bytes'], record['sha256'], flush=True)
(BASE / 'rust-setup-receipt.json').write_text(json.dumps(records, indent=2) + '\n')
print(subprocess.check_output([str(PREFIX / 'bin/cargo'), '--version'], text=True))
print(subprocess.check_output([str(PREFIX / 'bin/rustc'), '-vV'], text=True))

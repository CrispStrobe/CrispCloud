import concurrent.futures
import hashlib
import json
import pathlib
import shutil
import subprocess
import tarfile
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent
DOWNLOADS = ROOT / 'downloads'
entries = json.loads((DOWNLOADS / 'debian-packages.json').read_text())
rust = tomllib.loads((DOWNLOADS / 'rust-channel.toml').read_text())
packages = ['clang-19', 'libclang-cpp19', 'libllvm19', 'libclang-common-19-dev',
            'llvm-19-linker-tools', 'llvm-19', 'llvm-19-runtime', 'libclang1-19',
            'cmake', 'cmake-data', 'ninja-build', 'libz3-4', 'libpfm4',
            'libjsoncpp26', 'librhash1', 'libuv1t64', 'libarchive13t64']
jobs = []
for name in packages:
    entry = entries[name]
    jobs.append({'name': name, 'kind': 'deb', 'version': entry['Version'],
                 'url': 'https://deb.debian.org/debian/' + entry['Filename'],
                 'sha256': entry['SHA256'], 'file': DOWNLOADS / pathlib.Path(entry['Filename']).name})
for name in ['rustc', 'rust-std', 'cargo']:
    entry = rust['pkg'][name]['target']['x86_64-unknown-linux-gnu']
    jobs.append({'name': name, 'kind': 'rust', 'version': rust['pkg'][name]['version'],
                 'url': entry['xz_url'], 'sha256': entry['xz_hash'],
                 'file': DOWNLOADS / pathlib.Path(entry['xz_url']).name})

def download(job):
    path = job['file']
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != job['sha256']:
        subprocess.run(['curl', '-fSL', '--retry', '2', '--max-time', '300', job['url'], '-o', str(path)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != job['sha256']:
        raise RuntimeError(f'Hash mismatch for {path}')
    print(f'Verified {job["name"]}: {path.stat().st_size} bytes', flush=True)
    return job

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    list(pool.map(download, jobs))

native = ROOT / 'native'
native.mkdir(exist_ok=True)
rustroot = ROOT / 'rust'
rustroot.mkdir(exist_ok=True)
stage = ROOT / 'rust-stage'
stage.mkdir(exist_ok=True)
for job in jobs:
    if job['kind'] == 'deb':
        subprocess.run(['dpkg-deb', '-x', str(job['file']), str(native)], check=True)
    else:
        with tarfile.open(job['file'], 'r:xz') as archive:
            archive.extractall(stage, filter='data')
        package_root = stage / job['file'].name.removesuffix('.tar.xz')
        subprocess.run(['sh', str(package_root / 'install.sh'), '--prefix=' + str(rustroot),
                        '--disable-ldconfig'], check=True)
        shutil.rmtree(package_root)
receipt = [{'name': j['name'], 'kind': j['kind'], 'version': j['version'], 'url': j['url'],
            'sha256': j['sha256'], 'bytes': j['file'].stat().st_size} for j in jobs]
(ROOT / 'native-downloads.json').write_text(json.dumps(receipt, indent=2) + '\n')
print('Native toolchain extracted and Rust installed.', flush=True)

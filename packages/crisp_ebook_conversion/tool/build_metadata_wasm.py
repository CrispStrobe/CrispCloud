"""Build the reviewed offline metadata-only Wasm asset from the pinned lockfile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from check_wasm import manifest

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cargo', default='cargo')
    parser.add_argument('--wasm-bindgen', default='wasm-bindgen')
    parser.add_argument('--rustc', default='rustc')
    args = parser.parse_args()
    env = os.environ.copy()
    # This is scoped to the Wasm build. The called metadata path uses no RNG;
    # getrandom's Wasm option permits compiling unused upstream export code.
    env['RUSTFLAGS'] = '--cfg getrandom_backend="wasm_js" -C link-arg=--max-memory=402653184 -C link-arg=-zstack-size=1048576'
    subprocess.run([args.cargo, 'build', '--manifest-path', 'wasm/Cargo.toml',
                    '--target', 'wasm32-unknown-unknown', '--release', '--locked'],
                   cwd=ROOT, env=env, check=True)
    source = ROOT / 'wasm/target/wasm32-unknown-unknown/release/crisp_kindling_metadata_wasm.wasm'
    version = subprocess.check_output([args.wasm_bindgen, '--version'], text=True).strip()
    if version != 'wasm-bindgen 0.2.121':
        raise RuntimeError('Install the pinned wasm-bindgen-cli 0.2.121 with --locked')
    # Remove unused bindgen descriptor/table exports from transitive upstream
    # dependencies. The final raw byte ABI has no JavaScript/WASI imports and
    # needs no generated JS shim; metadata_runtime.js checks this at load time.
    output = ROOT / 'build/metadata-wasm'
    subprocess.run([args.wasm_bindgen, '--target', 'web', '--out-dir', str(output),
                    '--out-name', 'kindling_metadata', '--no-typescript', str(source)],
                   cwd=ROOT, check=True)
    source = output / 'kindling_metadata_bg.wasm'
    target = ROOT / 'assets/kindling_metadata.wasm'
    shutil.copyfile(source, target)
    target.chmod(0o644)
    rustc = subprocess.check_output([args.rustc, '--version'], text=True).strip()
    (ROOT / 'WASM.json').write_text(json.dumps(manifest(rustc), indent=2) + '\n')
    print(json.dumps({'asset': str(target.relative_to(ROOT)), 'bytes': target.stat().st_size,
                      'sha256': hashlib.sha256(target.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()

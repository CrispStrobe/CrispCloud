"""Build the shared bounded Kindle converter for a memory-only WASI worker."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cargo', default='cargo')
    args = parser.parse_args()
    env = os.environ.copy()
    env['RUSTFLAGS'] = '-C link-arg=--max-memory=536870912 -C link-arg=-zstack-size=1048576'
    subprocess.run([args.cargo, 'build', '--manifest-path', 'native/Cargo.toml',
                    '--bin', 'crisp-kindling', '--target', 'wasm32-wasip1',
                    '--release', '--locked'], cwd=ROOT, env=env, check=True)
    source = ROOT / 'native/target/wasm32-wasip1/release/crisp-kindling.wasm'
    target = ROOT / 'assets/kindling_conversion.wasm'
    shutil.copyfile(source, target)
    target.chmod(0o644)
    print(f'Built {target.relative_to(ROOT)} ({target.stat().st_size} bytes)')


if __name__ == '__main__':
    main()

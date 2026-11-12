#!/usr/bin/env python3
"""Check the exact, documented CrisperBooks consumer snapshot."""
import hashlib
import json
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]

def main():
    metadata = json.loads((ROOT / 'packages/crisperbooks/UPSTREAM.json').read_text())
    if metadata['repository'] != 'CrispStrobe/crisperbooks' or len(metadata['commit']) != 40:
        raise SystemExit('Invalid CrisperBooks source pin')
    paths = set(metadata['paths'].values())
    if paths != set(metadata['sha256']):
        raise SystemExit('Incomplete CrisperBooks source inventory')
    for name in sorted(paths):
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or str(relative) != name:
            raise SystemExit(f'Unsafe source path: {name}')
        if not any(name.startswith('packages/' + package + '/') for package in
                   ('crisperbooks', 'crisp_ebook', 'crisp_ebook_reader', 'crisp_ebook_conversion')):
            raise SystemExit(f'Unexpected source path: {name}')
        path = ROOT / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(ROOT):
            raise SystemExit(f'Missing regular source file: {name}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != metadata['sha256'][name]:
            raise SystemExit(f'CrisperBooks source drift: {name}')
    print(f"Verified {len(paths)} CrisperBooks files at {metadata['commit']}")

if __name__ == '__main__':
    main()

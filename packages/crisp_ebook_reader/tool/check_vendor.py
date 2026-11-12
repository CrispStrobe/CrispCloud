#!/usr/bin/env python3
"""Check pinned runtime bytes; optionally verify an exact upstream checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path,
                        help='foliate-js checkout at the recorded revision')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / 'UPSTREAM.json').read_text())
    foliate = manifest['foliate_js']
    entries = [*foliate['files'], manifest['fflate'],
               *manifest['license_files']]
    failures = []
    for entry in entries:
        path = root / entry['path']
        actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
        if actual != entry['sha256']:
            failures.append(f"Changed or missing pinned file: {entry['path']}")
    expected = {entry['path'] for entry in foliate['files']} | {manifest['fflate']['path']}
    actual = {str(path.relative_to(root)) for path in (root / 'assets/foliate').rglob('*.js')}
    if expected != actual:
        failures.append(f'Runtime inventory differs: {sorted(expected ^ actual)}')
    if args.upstream:
        revision = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=args.upstream, text=True).strip()
        if revision != foliate['revision']:
            failures.append(f'Upstream checkout revision differs: {revision}')
        for entry in foliate['files']:
            path = args.upstream / entry['source_path']
            actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
            if actual != entry['upstream_sha256']:
                failures.append(f"Upstream source differs: {entry['source_path']}")
    if failures:
        raise SystemExit('\n'.join(failures))
    print(f"PASS {len(expected)} pinned JavaScript runtime files and {len(manifest['license_files'])} license notices")


if __name__ == '__main__':
    main()

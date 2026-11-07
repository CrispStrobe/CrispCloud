#!/usr/bin/env python3
"""Fetch two exact upstream benchmark reference files, or verify a local copy.

This creates ignored build inputs, not app source or dependencies. A mismatched
download or local checkout is rejected before either reference file is written.
"""

import argparse
import hashlib
from pathlib import Path
from urllib.request import urlopen

COMMIT = 'a36afdffac7092de69a6120b6b3ec2edee35ecbe'
REPOSITORY = 'CrispStrobe/CrispSorter'
FILES = {
    'index.rs': '1886c3e00b060ff8fc502be3f8ae9f79de089b6201e5a2d5c751b0e9b8063cb5',
    'scan.rs': '13ac4d0421d33f4aab320150bdadfe08abe89b279b873b4779c5bf6d77db211f',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-checkout', type=Path,
        help='Use these files from an existing CrispSorter checkout; hashes still must match.')
    args = parser.parse_args()
    checked = {}
    for name, expected in FILES.items():
        relative = f'crates/crispcat/src/{name}'
        if args.source_checkout:
            data = (args.source_checkout / relative).read_bytes()
        else:
            url = f'https://raw.githubusercontent.com/{REPOSITORY}/{COMMIT}/{relative}'
            with urlopen(url, timeout=30) as response:
                data = response.read(1024 * 1024 + 1)
        if len(data) > 1024 * 1024 or hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit(f'Refused reference file with unexpected contents: {relative}')
        checked[name] = data
    destination = Path(__file__).resolve().parent / 'reference'
    destination.mkdir(exist_ok=True)
    for name, data in checked.items():
        target = destination / name
        temporary = destination / (name + '.tmp')
        temporary.write_bytes(data)
        temporary.replace(target)
    print(f'Prepared {len(checked)} hash-verified files from {REPOSITORY}@{COMMIT}.')


if __name__ == '__main__':
    main()

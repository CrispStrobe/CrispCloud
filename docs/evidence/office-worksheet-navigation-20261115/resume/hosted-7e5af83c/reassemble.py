#!/usr/bin/env python3
"""Reconstruct exact GitHub artifact ZIPs from the retained parts."""

import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    args.destination.mkdir(parents=True, exist_ok=True)
    for item in json.loads((root / 'archives.json').read_text()):
        chunks = []
        for part in item['parts']:
            source = (root / part['path']).resolve()
            if not source.is_relative_to(root):
                raise ValueError('Archive part escapes evidence directory')
            data = source.read_bytes()
            if (len(data) != part['bytes'] or
                    hashlib.sha256(data).hexdigest() != part['sha256']):
                raise ValueError(f'Archive part integrity mismatch: {part["path"]}')
            chunks.append(data)
        archive = b''.join(chunks)
        digest = hashlib.sha256(archive).hexdigest()
        if (len(archive) != item['bytes'] or digest != item['sha256'] or
                f'sha256:{digest}' != item['digest']):
            raise ValueError(f'Archive integrity mismatch: {item["id"]}')
        target = args.destination / f'{int(item["id"])}.zip'
        if target.exists() and target.read_bytes() != archive:
            raise ValueError(f'Refusing to replace a different archive: {target}')
        target.write_bytes(archive)
        print(f'{target.name}: {len(archive)} bytes, SHA-256 {digest}')


if __name__ == '__main__':
    main()

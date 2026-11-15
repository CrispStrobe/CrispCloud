#!/usr/bin/env python3
"""Reconstruct exact GitHub artifact ZIPs from the retained parts."""

import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--extract', action='store_true',
                        help='Prepare the input layout for the saved integrity verifier')
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
        filename = item['file_name'] if args.extract else f'{int(item["id"])}.zip'
        if Path(filename).name != filename:
            raise ValueError('Archive filename must be a single path component')
        target = args.destination / filename
        if target.exists() and target.read_bytes() != archive:
            raise ValueError(f'Refusing to replace a different archive: {target}')
        target.write_bytes(archive)
        if args.extract:
            extracted = args.destination / str(int(item['id']))
            if extracted.exists():
                raise ValueError(f'Extraction destination already exists: {extracted}')
            with ZipFile(target) as zipped:
                if len(zipped.namelist()) != len(set(zipped.namelist())):
                    raise ValueError('Duplicate archive member')
                for member in zipped.namelist():
                    if not (extracted / member).resolve().is_relative_to(extracted.resolve()):
                        raise ValueError('Archive member escapes destination')
                zipped.extractall(extracted)
        print(f'{target.name}: {len(archive)} bytes, SHA-256 {digest}')
    if args.extract:
        (args.destination / 'download-receipts.json').write_bytes(
            (root / 'integrity/download-receipts.json').read_bytes())


if __name__ == '__main__':
    main()

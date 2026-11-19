"""Bind the already-built CLI SMB library to the declared Linux SMB fixture.

This does not build or publish a library. The actual native/network test must
still initialize the bridge and pass its existing reconnect/resume assertions.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path


def bridge_receipt(bundle):
    bundle = Path(bundle).resolve(strict=True)
    candidates = sorted(bundle.rglob('*crisp_smb_bridge*.so'))
    if len(candidates) != 1:
        raise ValueError('Expected one built CLI SMB bridge; found ' + str(len(candidates)))
    library = candidates[0]
    if (library.is_symlink() or not library.is_file()
            or not library.resolve().is_relative_to(bundle)
            or '\n' in str(library) or '\r' in str(library)):
        raise ValueError('SMB bridge must be a regular file inside the CLI bundle')
    with library.open('rb') as stream:
        header = stream.read(64)
    if (len(header) != 64 or header[:6] != b'\x7fELF\x02\x01'
            or int.from_bytes(header[16:18], 'little') != 3
            or int.from_bytes(header[18:20], 'little') != 62):
        raise ValueError('Expected the Linux x86-64 ELF shared SMB bridge')
    digest = hashlib.sha256()
    with library.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return {'library': str(library), 'bytes': library.stat().st_size,
            'sha256': digest.hexdigest(),
            'scope': 'Existing CI-built CLI asset; header/digest only, not native test acceptance',
            'new_build_performed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    receipt = bridge_receipt(args.bundle)
    environment_file = os.environ.get('GITHUB_ENV')
    if not environment_file:
        raise ValueError('This binding is restricted to a hosted CI environment')
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
    with open(environment_file, 'a', encoding='utf-8') as environment:
        environment.write('CRISP_SMB_LIBRARY=' + receipt['library'] + '\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()

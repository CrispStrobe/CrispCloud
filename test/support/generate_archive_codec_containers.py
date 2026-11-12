#!/usr/bin/env python3
"""Original TAR trees in read-only Lzip/UNIX compress wrappers.

Python produces the USTAR tree; native libarchive produces the two compression
wrappers. liblzma/zlib and GNU gzip independently verify the complete TAR bytes.
"""
import argparse
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/archives'


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w', format=tarfile.USTAR_FORMAT) as tar:
        for name, directory, body in [
            ('empty/', True, b''),
            ('docs/hello.txt', False, b'Independent wrapped TAR\n'),
        ]:
            entry = tarfile.TarInfo(name)
            entry.type = tarfile.DIRTYPE if directory else tarfile.REGTYPE
            entry.mode = 0o755 if directory else 0o640
            entry.uid, entry.gid, entry.mtime = 123, 456, 1700000000
            entry.size = len(body)
            tar.addfile(entry, None if directory else io.BytesIO(body))
    plain = buffer.getvalue()
    lzip = module('lzip_reference', ROOT / 'test/support/generate_lzip_reference.py')
    compress = module('compress_reference', FIXTURES / 'generate_unix_compress_reference.py')
    for suffix, encoded in [('lz', lzip.compress(plain)), ('Z', compress.encode(plain))]:
        if suffix == 'lz':
            lzip.verify(encoded, plain)
        else:
            result = subprocess.run(['gzip', '-dc'], input=encoded, capture_output=True, check=True)
            assert result.stdout == plain
        path = FIXTURES / f'codec-container.tar.{suffix}'
        if args.check_only:
            assert path.read_bytes() == encoded
        else:
            path.write_bytes(encoded)
        print(f'{path.name}: SHA-256 {hashlib.sha256(encoded).hexdigest()}, exact {len(plain)}-byte independent readback passed')


if __name__ == '__main__':
    main()

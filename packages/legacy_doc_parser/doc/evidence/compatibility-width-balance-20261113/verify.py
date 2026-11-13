#!/usr/bin/env python3
"""Verify the retained compatibility archive in place, without extraction."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def safe_path(value):
    if not isinstance(value, str) or not value or any(c in value for c in '\\\x00:'):
        raise ValueError('Invalid archive path')
    path = PurePosixPath(value)
    if (path.is_absolute() or path.as_posix() != value or
            any(part in {'.', '..'} for part in path.parts)):
        raise ValueError('Unsafe archive path')
    return value


def digest(stream):
    return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if (manifest.get('schema') != 'legacy-doc-parser/compatibility-width-balance-evidence'
            or manifest.get('version') != 1):
        raise ValueError('Unexpected evidence format')
    record = manifest['archive']
    name = safe_path(record['path'])
    if len(PurePosixPath(name).parts) != 1:
        raise ValueError('Archive must be in the manifest directory')
    path = directory / name
    if path.is_symlink() or not path.is_file() or path.stat().st_size != record['bytes']:
        raise ValueError('Archive file or size differs')
    with path.open('rb') as stream:
        if digest(stream) != record['sha256']:
            raise ValueError('Archive hash differs')
    expected = {}
    for item in manifest['files']:
        name = safe_path(item['path'])
        if name in expected or type(item['bytes']) is not int or item['bytes'] < 0:
            raise ValueError('Duplicate or invalid manifest member')
        expected[name] = item
    if len(expected) != manifest['fileCount']:
        raise ValueError('Manifest file count differs')
    seen = set()
    with tarfile.open(path, 'r:xz') as archive:
        for member in archive:
            name = safe_path(member.name)
            if (member.type not in {tarfile.REGTYPE, tarfile.AREGTYPE} or
                    name in seen or name not in expected):
                raise ValueError('Unsafe, duplicate, or unexpected archive member')
            seen.add(name)
            item = expected[name]
            if member.size != item['bytes']:
                raise ValueError('Member size differs: ' + name)
            with archive.extractfile(member) as stream:
                if digest(stream) != item['sha256']:
                    raise ValueError('Member hash differs: ' + name)
    if seen != set(expected):
        raise ValueError('Archive coverage differs')
    return {'verified': True, 'fileCount': len(seen), 'archiveSha256': record['sha256']}


if __name__ == '__main__':
    print(json.dumps(verify(Path(__file__).resolve().parent)))

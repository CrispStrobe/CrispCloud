#!/usr/bin/env python3
"""Repair four deprecated literal declarations in one authenticated CI input.

No warning suppression, dependency upgrade, storage logic or crypto change.
The original archive is pinned by pubspec.lock; unknown header bytes fail closed.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'flutter_secure_storage_linux'
VERSION = '1.2.3'
ARCHIVE_SHA = 'be76c1d24a97d0b98f8b54bce6b481a380a6590df992d0098f868ad54dc8f688'
ORIGINAL_SHA = '0d8d3e680a119c7c4e5ab45a95bc4dbd47474f69d57c7f89eab75c7d3ad3403a'
PATCHED_SHA = 'd99a246165e67ac370a6393095ae10c8170e1a62f181a4c17d1c1e22d6245877'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def patched_header(data):
    if digest(data) == PATCHED_SHA:
        return data
    if digest(data) != ORIGINAL_SHA or data.count(b'operator "" _json') != 4:
        raise ValueError('Unreviewed secure-storage JSON header; refuse to patch')
    result = data.replace(b'operator "" _json', b'operator ""_json')
    if digest(result) != PATCHED_SHA:
        raise ValueError('Unexpected literal-operator repair result')
    return result


def main():
    if (sys.platform != 'linux' or os.environ.get('GITHUB_ACTIONS') != 'true'
            or os.environ.get('GITHUB_REPOSITORY') != 'CrispStrobe/CrispCloud'):
        raise ValueError('This cache mutation is restricted to the owned Linux CI job')
    lock = (ROOT / 'pubspec.lock').read_text()
    blocks = re.findall(r'^  flutter_secure_storage_linux:\n(.*?)(?=^  \S|\Z)',
                        lock, re.M | re.S)
    if (len(blocks) != 1 or ARCHIVE_SHA not in blocks[0]
            or re.search(r'^    version: "1\.2\.3"$', blocks[0], re.M) is None):
        raise ValueError('Secure-storage dependency differs from the reviewed lock')
    config_path = ROOT / '.dart_tool/package_config.json'
    packages = json.loads(config_path.read_text())['packages']
    entries = [p for p in packages if p['name'] == PACKAGE]
    if len(entries) != 1:
        raise ValueError('Expected one resolved secure-storage package')
    uri = urlparse(entries[0]['rootUri'])
    if uri.scheme not in ('', 'file') or uri.netloc:
        raise ValueError('Expected a local resolved package URI')
    package = Path(unquote(uri.path))
    if not package.is_absolute():
        package = config_path.parent / package
    package = package.resolve()
    cache = Path(os.environ['PUB_CACHE']).resolve()
    if not package.is_relative_to(cache) or package.name != PACKAGE + '-' + VERSION:
        raise ValueError('Resolved secure-storage package lies outside the owned pub cache')
    target = package / 'linux/include/json.hpp'
    if target.is_symlink() or not target.is_file() or not target.resolve().is_relative_to(package):
        raise ValueError('Expected a regular package-owned JSON header')
    original = target.read_bytes()
    repaired = patched_header(original)
    if repaired != original:
        mode = stat.S_IMODE(target.stat().st_mode)
        fd, name = tempfile.mkstemp(prefix='.crisp-json-compat-', dir=target.parent)
        temporary = Path(name)
        try:
            with os.fdopen(fd, 'wb') as output:
                output.write(repaired)
                output.flush()
                os.fchmod(output.fileno(), mode)
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
    if digest(target.read_bytes()) != PATCHED_SHA:
        raise ValueError('Post-write header verification failed')
    print(json.dumps({'package': PACKAGE, 'version': VERSION,
        'archive_sha256': ARCHIVE_SHA, 'before_sha256': digest(original),
        'after_sha256': PATCHED_SHA, 'literal_spacing_only': True,
        'warning_suppression': False, 'already_repaired': repaired == original}))


if __name__ == '__main__':
    main()

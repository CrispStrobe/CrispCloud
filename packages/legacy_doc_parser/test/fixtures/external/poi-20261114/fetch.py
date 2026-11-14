#!/usr/bin/env python3
"""Fetch or verify the exact externally authored files pinned in manifest.json.

No document content is executed. External document relationships are not fetched.
Existing mismatched files cause failure; the script never silently replaces them.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path, PurePosixPath
import urllib.parse
import urllib.request


def checked_path(root: Path, value: str) -> Path:
    relative = PurePosixPath(value)
    if relative.is_absolute() or any(p in ('.', '..', '') for p in relative.parts):
        raise ValueError(f'Unsafe manifest path: {value!r}')
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'Manifest path escapes output directory: {value!r}')
    return path


def verify(data: bytes, item: dict) -> None:
    if len(data) != item['bytes']:
        raise ValueError(f"Wrong length: {item['path']}")
    if hashlib.sha256(data).hexdigest() != item['sha256']:
        raise ValueError(f"Wrong SHA-256: {item['path']}")
    if 'gitBlobSha1' in item:
        blob = b'blob ' + str(len(data)).encode() + b'\0' + data
        if hashlib.sha1(blob).hexdigest() != item['gitBlobSha1']:
            raise ValueError(f"Wrong upstream Git blob: {item['path']}")


def obtain(root: Path, item: dict, verify_only: bool) -> str:
    target = checked_path(root, item['path'])
    if target.exists():
        verify(target.read_bytes(), item)
        return 'verified'
    if verify_only:
        raise FileNotFoundError(target)
    url = item['downloadUrl']
    expected = ('https://raw.githubusercontent.com/' + item['sourceRepository'] + '/'
                + item['sourceCommit'] + '/' + urllib.parse.quote(item['sourcePath'], safe='/'))
    if url != expected:
        raise ValueError(f"Download URL does not match pinned source: {item['path']}")
    if not isinstance(item['bytes'], int) or not 0 <= item['bytes'] <= 400_000:
        raise ValueError(f"Invalid download budget: {item['path']}")
    request = urllib.request.Request(url, headers={'User-Agent': 'parser-external-corpus/1'})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(item['bytes'] + 1)
    verify(data, item)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.download')
    temporary.write_bytes(data)
    temporary.replace(target)
    return 'downloaded'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).with_name('manifest.json'))
    parser.add_argument('--out', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error('--jobs must be between 1 and 8')
    manifest = json.loads(args.manifest.read_text())
    if manifest['version'] != 1:
        raise ValueError('Unsupported manifest version')
    items = manifest['files'] + manifest['licenseFiles']
    paths = [item['path'] for item in items]
    if len(paths) != len(set(paths)):
        raise ValueError('Duplicate manifest paths')
    root = args.out or args.manifest.parent
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: obtain(root, item, args.verify_only), items))
    print(json.dumps({'files':len(items), 'documents':len(manifest['files']),
                      'verified':results.count('verified'), 'downloaded':results.count('downloaded')}))


if __name__ == '__main__':
    main()

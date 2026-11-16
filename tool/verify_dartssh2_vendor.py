#!/usr/bin/env python3
"""Verify the exact pinned SSH runtime and its reviewed agent-channel patch."""
import argparse
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'packages/dartssh2'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-tracked', action='store_true')
    args = parser.parse_args()
    upstream = json.loads((VENDOR / 'UPSTREAM.json').read_text())
    patched = json.loads((VENDOR / 'PATCHED.json').read_text())
    expected = dict(upstream['upstream_files'])
    changed = set(upstream['patched_files'])
    if changed != set(patched['files']) or not changed <= expected.keys():
        raise SystemExit('SSH vendor patch inventory mismatch')
    expected.update(patched['files'])
    expected['agent-channel.patch'] = patched['patch_sha256']
    runtime = {str(path.relative_to(VENDOR)) for path in (VENDOR / 'lib').rglob('*')
               if path.is_file()}
    if runtime != {name for name in expected if name.startswith('lib/')}:
        raise SystemExit('SSH runtime source inventory mismatch')
    for name, sha in expected.items():
        path = VENDOR / name
        if (path.is_symlink() or not path.is_file()
                or not path.resolve().is_relative_to(VENDOR.resolve())
                or digest(path) != sha):
            raise SystemExit(f'SSH vendor drift: {name}')
    if args.require_tracked:
        tracked = {}
        for row in subprocess.check_output(
                ['git', 'ls-files', '--stage', '-z', 'packages/dartssh2'], cwd=ROOT).split(b'\0'):
            if not row:
                continue
            metadata, path = row.split(b'\t', 1)
            mode, sha, stage = metadata.decode().split()
            tracked[path.decode()] = (mode, sha, stage)
        for name in [*expected, 'UPSTREAM.json', 'UPSTREAM.md', 'PATCHED.json']:
            data = (VENDOR / name).read_bytes()
            sha = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            if tracked.get('packages/dartssh2/' + name) != ('100644', sha, '0'):
                raise SystemExit(f'SSH vendor differs from tracked source: {name}')
    print(f"Verified {len(upstream['upstream_files'])} dartssh2 {upstream['version']} upstream files; "
          f'{len(changed)} reviewed agent-channel patches.')


if __name__ == '__main__':
    main()

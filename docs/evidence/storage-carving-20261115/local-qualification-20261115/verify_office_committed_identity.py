#!/usr/bin/env python3
"""Verify every declared Office mirror blob/mode and working SHA-256 at a saved app ref."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import subprocess


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def tree(repo, ref):
    result = {}
    for row in git(repo, 'ls-tree', '-rz', ref).split(b'\0'):
        if not row:
            continue
        meta, path = row.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        result[path.decode()] = {'mode': mode, 'kind': kind, 'oid': oid}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--ref', required=True)
    parser.add_argument('--quds', type=Path, required=True)
    parser.add_argument('--parser', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.app.resolve()
    app_head = git(root, 'rev-parse', args.ref+'^{commit}').decode().strip()
    manifest_path = 'tool/office_fidelity_manifest.json'
    manifest_bytes = git(root, 'show', app_head+':'+manifest_path)
    manifest = json.loads(manifest_bytes)
    legacy = manifest['standalone_sources']['packages/legacy_doc_parser']
    if legacy['repository'] != 'CrispStrobe/legacy-doc-parser':
        raise SystemExit('Unexpected parser source')
    app_tree = tree(root, app_head)
    quds_tree = tree(args.quds, manifest['source_commit'])
    legacy_tree = tree(args.parser, legacy['commit'])
    counts = {'quds': 0, 'parser': 0}
    failures = []
    inspected = {}
    if (root/manifest_path).read_bytes() != manifest_bytes:
        failures.append({'path': manifest_path, 'reason': 'working manifest differs from saved app ref'})
    for path, sha256 in manifest['files'].items():
        pure = PurePosixPath(path)
        local = root/path
        if pure.is_absolute() or '..' in pure.parts or not local.resolve().is_relative_to(root):
            raise SystemExit('Unsafe manifest path')
        if path.startswith('packages/legacy_doc_parser/'):
            source = legacy_tree.get(path.removeprefix('packages/legacy_doc_parser/'))
            counts['parser'] += 1
        else:
            source = quds_tree.get(path)
            counts['quds'] += 1
        actual = app_tree.get(path)
        if actual != source or source is None:
            failures.append({'path': path, 'reason': 'canonical Git identity/mode mismatch',
                             'app': actual, 'canonical': source})
        if local.is_symlink() or not local.is_file():
            failures.append({'path': path, 'reason': 'nonregular working path'})
            continue
        data = local.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        blob = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        mode = '100755' if stat.S_IMODE(local.stat().st_mode) & 0o111 else '100644'
        if digest != sha256 or actual != {'kind': 'blob', 'oid': blob, 'mode': mode}:
            failures.append({'path': path, 'reason': 'working bytes/mode mismatch with manifest or Git ref'})
        inspected[path] = {'git_blob': blob, 'mode': mode, 'sha256': digest, 'size': len(data)}
    result = {'verified_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'app_commit': app_head, 'app_tree': git(root, 'rev-parse', app_head+'^{tree}').decode().strip(),
              'quds_pin': manifest['source_commit'], 'parser_pin': legacy['commit'],
              'declared_file_count': len(manifest['files']), 'counts': counts,
              'verified_file_count': len(inspected), 'failures': failures,
              'success': not failures, 'files': inspected,
              'scope': 'Saved Git blob identities and modes against exact canonical pins, plus complete declared working-file SHA-256 and Git identity; no runtime qualification claim.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'files'}, indent=2))
    return 0 if result['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

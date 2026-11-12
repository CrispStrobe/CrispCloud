#!/usr/bin/env python3
"""Dry-run or apply an exact standalone legacy-doc-parser mirror update.

Requires both pinned commits in a local parser checkout. Every existing source
byte and the complete mirror inventory are checked before writes. No network,
release evidence, distribution policy or Quds source is changed by this tool.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

import sync_office_fidelity as office

ROOT = Path(__file__).resolve().parents[1]
PREFIX = office.LEGACY_PREFIX
REPOSITORY = office.LEGACY_REPOSITORY
GENERATED_DIRECTORIES = {'.dart_tool', 'build', '__pycache__', 'coverage'}


def source_tree(source, ref):
    commit = office.git(source, 'rev-parse', '--verify', '--end-of-options', ref + '^{commit}').decode().strip()
    records = office.git(source, 'ls-tree', '-rzl', '--full-tree', commit).split(b'\0')
    if len(records) > 5001:
        raise office.SyncError('Standalone parser source exceeds the file-count limit')
    files, total = {}, 0
    for record in records:
        if not record:
            continue
        metadata, raw_name = record.split(b'\t', 1)
        mode, kind, _, size = metadata.decode().split()
        name = raw_name.decode('utf-8')
        path = office.safe_path(name)
        if (mode not in ('100644', '100755') or kind != 'blob'
                or path.parts[0] in GENERATED_DIRECTORIES or name == 'UPSTREAM.json'):
            raise office.SyncError(f'Unsupported standalone source entry: {name}')
        length = int(size)
        total += length
        if length > 64 * 1024 * 1024 or total > 128 * 1024 * 1024:
            raise office.SyncError('Standalone parser source exceeds its byte limit')
        data = office.git(source, 'show', f'{commit}:{name}')
        if len(data) != length:
            raise office.SyncError('Standalone parser source extent changed')
        files[name] = data
    if not re.search(rb'^name:\s*legacy_doc_parser\s*$', files.get('pubspec.yaml', b''), re.MULTILINE):
        raise office.SyncError('Source commit is not the legacy_doc_parser package')
    for required in ('LICENSE', 'lib/legacy_doc_parser.dart'):
        if required not in files:
            raise office.SyncError(f'Standalone package lacks required source: {required}')
    return commit, files


def mirror_files(directory, tracked):
    """Reject unexplained source additions; allow only local tool outputs."""
    import os
    files = set()
    for parent, directories, names in os.walk(directory, followlinks=False):
        for name in directories + names:
            if (Path(parent) / name).is_symlink():
                raise office.SyncError('Symlink in standalone parser mirror')
        directories[:] = [name for name in directories if name not in GENERATED_DIRECTORIES]
        for name in names:
            relative = (Path(parent) / name).relative_to(directory).as_posix()
            if relative == 'UPSTREAM.json' or (relative == 'pubspec.lock' and relative not in tracked):
                continue
            if relative.endswith('.pyc') and '__pycache__' in Path(relative).parts:
                continue
            files.add(relative)
    return files


def plan(source, target_root, ref):
    manifest_path = target_root / 'tool/office_fidelity_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    office.standalone_sources(manifest, target_root)
    metadata_path = target_root / PREFIX / 'UPSTREAM.json'
    upstream = json.loads(metadata_path.read_text())
    if (upstream.get('repository') != REPOSITORY or upstream.get('patches') != []
            or not re.fullmatch(r'[0-9a-f]{40}', upstream.get('commit', ''))):
        raise office.SyncError('Legacy mirror needs an exact unpatched upstream pin')
    before, old = source_tree(source, upstream['commit'])
    after, new = source_tree(source, ref)
    mirror = target_root / PREFIX
    if mirror.is_symlink() or not mirror.resolve().is_relative_to(target_root.resolve()):
        raise office.SyncError('Standalone parser mirror escapes the host checkout')
    if mirror_files(mirror, old) != set(old):
        raise office.SyncError('Standalone parser mirror has missing or unreviewed files')
    for name, data in old.items():
        path = mirror / name
        if not path.is_file() or path.read_bytes() != data:
            raise office.SyncError(f'Standalone parser vendor drift: {name}')
    # Validate the entire existing inventory before deriving a new one. Quds
    # files and their historical source identity remain byte-for-byte intact.
    for name, expected in manifest['files'].items():
        office.safe_path(name)
        path = target_root / name
        if (path.is_symlink() or not path.resolve().is_relative_to(target_root.resolve())
                or not path.is_file() or office.digest(path.read_bytes()) != expected):
            raise office.SyncError(f'Vendor drift: {name}')
    pubspec_path = target_root / 'pubspec.yaml'
    pubspec = pubspec_path.read_bytes()
    pattern = (rb'(?m)(^  legacy_doc_parser:\n    git:\n'
               rb'      url: https://github.com/CrispStrobe/legacy-doc-parser.git\n'
               rb'      ref: )([0-9a-f]{40})(\s*$)')
    matches = list(re.finditer(pattern, pubspec))
    override = re.search(rb'^dependency_overrides:\n  legacy_doc_parser:\n'
                         rb'    path: packages/legacy_doc_parser\s*$', pubspec, re.MULTILINE)
    if len(matches) != 1 or matches[0][2].decode() != before or override is None:
        raise office.SyncError('App Git dependency does not match the current parser mirror')
    updated_pubspec = re.sub(pattern, lambda match: match[1] + after.encode() + match[3], pubspec)
    new_upstream = {'repository': REPOSITORY, 'commit': after, 'patches': []}
    writes = {f'{PREFIX}/{name}': data for name, data in new.items() if old.get(name) != data}
    writes[f'{PREFIX}/UPSTREAM.json'] = (json.dumps(new_upstream, indent=2) + '\n').encode()
    writes['pubspec.yaml'] = updated_pubspec
    deletes = [f'{PREFIX}/{name}' for name in sorted(set(old) - set(new))]
    hashes = {name: sha for name, sha in manifest['files'].items() if not name.startswith(PREFIX + '/')}
    hashes.update({f'{PREFIX}/{name}': office.digest(data) for name, data in new.items()})
    sources = {**manifest.get('standalone_sources', {}), PREFIX: {'repository': REPOSITORY, 'commit': after}}
    result = dict(manifest, standalone_sources=sources, files=hashes)
    return {'before': before, 'after': after, 'writes': writes, 'deletes': deletes,
            'manifest': result, 'manifest_path': manifest_path}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--ref', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    change = plan(args.source, ROOT, args.ref)
    print(json.dumps({'from': change['before'], 'to': change['after'],
                      'write': list(change['writes']), 'delete': change['deletes'],
                      'applied': args.apply}, indent=2))
    if args.apply:
        office.apply(ROOT, change)


if __name__ == '__main__':
    main()

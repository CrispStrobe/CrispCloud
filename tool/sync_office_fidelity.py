#!/usr/bin/env python3
"""Review or apply a guarded sync from an exact quds_office_suite commit.

The default is a dry run. Existing pinned hashes and every changed unpinned
file are checked before any write. Host customizations are never overwritten.
The manifest is written last, so an interrupted sync fails the normal gate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import tempfile
import os
import re

ROOT = Path(__file__).resolve().parents[1]
LEGACY_PREFIX = 'packages/legacy_doc_parser'
LEGACY_REPOSITORY = 'CrispStrobe/legacy-doc-parser'


class SyncError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(source, *args, optional=False):
    result = subprocess.run(['git', '-C', str(source), *args], capture_output=True)
    if result.returncode:
        if optional:
            return None
        raise SyncError(result.stderr.decode(errors='replace').strip())
    return result.stdout


def safe_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or str(path) != name:
        raise SyncError(f'Unsafe source path: {name}')
    return path


def standalone_sources(manifest, target_root=None):
    """Keep separately maintained parser bytes out of a Quds sync.

    Only the explicitly supported package can use this source boundary. It is
    not a general mechanism for excluding arbitrary vendor files from checks.
    """
    sources = manifest.get('standalone_sources', {})
    if not isinstance(sources, dict) or set(sources) - {LEGACY_PREFIX}:
        raise SyncError('Unsupported standalone Office source boundary')
    for prefix, source in sources.items():
        if (not isinstance(source, dict) or set(source) != {'repository', 'commit'}
                or source['repository'] != LEGACY_REPOSITORY
                or not isinstance(source['commit'], str)
                or not re.fullmatch(r'[0-9a-f]{40}', source['commit'])):
            raise SyncError('Invalid standalone legacy parser source pin')
        if target_root is not None:
            metadata = target_root / prefix / 'UPSTREAM.json'
            if (metadata.is_symlink() or not metadata.is_file()
                    or not metadata.resolve().is_relative_to(target_root.resolve())):
                raise SyncError('Missing or unsafe legacy parser upstream metadata')
            upstream = json.loads(metadata.read_text())
            if upstream != {**source, 'patches': []}:
                raise SyncError('Standalone parser metadata disagrees with Office manifest')
            pubspec = (target_root / 'pubspec.yaml').read_text()
            pin = re.search(r'^  legacy_doc_parser:\n    git:\n'
                            r'      url: https://github.com/CrispStrobe/legacy-doc-parser.git\n'
                            r'      ref: ([0-9a-f]{40})\s*$', pubspec, re.MULTILINE)
            override = re.search(r'^dependency_overrides:\n  legacy_doc_parser:\n'
                                 r'    path: packages/legacy_doc_parser\s*$', pubspec,
                                 re.MULTILINE)
            if pin is None or pin[1] != source['commit'] or override is None:
                raise SyncError('Standalone parser dependency, mirror, and source pin disagree')
    return sources


def standalone_path(name, sources):
    return any(name.startswith(prefix + '/') for prefix in sources)


def shared(name):
    path = safe_path(name)
    parts = path.parts
    if parts[:2] == ('tool', 'office-validation'):
        return True
    if len(parts) < 3 or parts[0] != 'packages' or parts[1] not in ('quds_office_engine', 'quds_office_editor', 'legacy_doc_parser', 'quds_reports'):
        return False
    return parts[2] in ('lib', 'test', 'tool', 'CHANGELOG.md')


def plan(source, target_root, ref, branch=None):
    manifest_path = target_root/'tool/office_fidelity_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    independent = standalone_sources(manifest, target_root)
    base = manifest['source_commit']
    target = git(source, 'rev-parse', '--verify', '--end-of-options', ref+'^{commit}').decode().strip()
    git(source, 'cat-file', '-e', base+'^{commit}')
    expected = manifest['files']
    for name, sha in expected.items():
        safe_path(name)
        path = target_root/name
        if path.is_symlink() or not path.is_file() or digest(path.read_bytes()) != sha:
            raise SyncError(f'Vendor drift: {name}; reconcile the host change first')
        if not standalone_path(name, independent):
            original = git(source, 'show', f'{base}:{name}')
            if digest(original) != sha:
                raise SyncError(f'Manifest does not match its source commit: {name}')
    changed = git(source, 'diff', '--name-only', '--no-renames', base, target).decode().splitlines()
    names = sorted({name for name in expected if not standalone_path(name, independent)} |
                   {name for name in changed if shared(name) and not standalone_path(name, independent)})
    writes, deletes = {}, []
    hashes = {name: sha for name, sha in expected.items() if standalone_path(name, independent)}
    for name in names:
        safe_path(name)
        path = target_root/name
        # Check ancestors as well: a symlinked directory could escape the repo.
        if not path.resolve().is_relative_to(target_root.resolve()):
            raise SyncError(f'Path escapes the host checkout: {name}')
        before = git(source, 'show', f'{base}:{name}', optional=True)
        after = git(source, 'show', f'{target}:{name}', optional=True)
        current = path.read_bytes() if path.is_file() else None
        if path.is_symlink() or current not in (before, after):
            raise SyncError(f'Unsynced host customization: {name}')
        if after is None:
            if current is not None:
                deletes.append(name)
            continue
        hashes[name] = digest(after)
        if current != after:
            writes[name] = after
    result = dict(manifest, source_commit=target, files=hashes)
    if branch:
        result['source_branch'] = branch
    return {'before': base, 'after': target, 'writes': writes, 'deletes': deletes,
            'manifest': result, 'manifest_path': manifest_path}


def apply(target_root, change):
    # Validate the whole plan before reaching this function. Each replacement
    # uses a sibling temporary file; never truncate a live vendored source.
    for name, data in change['writes'].items():
        path = target_root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
            temporary.write(data)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_name = temporary.name
        try:
            os.chmod(temporary_name, mode)
            os.replace(temporary_name, path)
        finally:
            if os.path.exists(temporary_name):
                os.unlink(temporary_name)
    for name in change['deletes']:
        (target_root/name).unlink()
    data = json.dumps(change['manifest'], indent=2)+'\n'
    path = change['manifest_path']
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as temporary:
        temporary.write(data)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_name = temporary.name
    os.replace(temporary_name, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='local suite checkout with both commits fetched')
    parser.add_argument('--ref', required=True, help='source commit or feature branch to sync')
    parser.add_argument('--branch', help='human-readable source branch stored with the exact commit')
    parser.add_argument('--apply', action='store_true', help='apply a validated plan; default only prints it')
    args = parser.parse_args()
    change = plan(args.source, ROOT, args.ref, args.branch)
    print(json.dumps({'from': change['before'], 'to': change['after'],
                      'write': list(change['writes']), 'delete': change['deletes'],
                      'pinned_files': len(change['manifest']['files']), 'applied': args.apply}, indent=2))
    if args.apply:
        apply(ROOT, change)


if __name__ == '__main__':
    main()

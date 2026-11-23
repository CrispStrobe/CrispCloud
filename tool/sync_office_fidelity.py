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
MACRO_EXAMPLES = 'packages/quds_office_engine/example/macros'


class SyncError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(source, *args, optional=False, input_data=None):
    result = subprocess.run(['git', '-C', str(source), *args], capture_output=True, input=input_data)
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


def local_patch_bases(manifest, independent):
    """Check explicit host overlays without relaxing the hash checks."""
    patches = manifest.get('local_patch_bases', {})
    if not isinstance(patches, dict):
        raise SyncError('Invalid Office local patch bases')
    for name, upstream_hash in patches.items():
        if (not shared(name) or standalone_path(name, independent)
                or name not in manifest['files']
                or not isinstance(upstream_hash, str)
                or not re.fullmatch(r'[0-9a-f]{64}', upstream_hash)
                or manifest['files'][name] == upstream_hash):
            raise SyncError(f'Invalid Office local patch base: {name}')
    return patches


def shared(name):
    path = safe_path(name)
    parts = path.parts
    if name.startswith(MACRO_EXAMPLES + '/'):
        return True
    if parts[:2] == ('tool', 'office-validation'):
        return True
    # Embedded German data and font metadata use these exact source notices.
    # Keep their provenance and licenses under the same runtime pin.
    if (parts[:3] == ('packages', 'quds_office_engine', 'third_party')
            and len(parts) >= 5 and parts[3] in ('hyphenation', 'proofing', 'fonttools')):
        return True
    if len(parts) < 3 or parts[0] != 'packages' or parts[1] not in ('quds_office_engine', 'quds_office_editor', 'legacy_doc_parser', 'quds_reports', 'quds_proofing_spacy'):
        return False
    return parts[2] in ('lib', 'test', 'tool', 'CHANGELOG.md')


def source_files(source, ref, names):
    """Read a frozen source inventory in one Git process, including missing files."""
    names = sorted(names)
    for name in names:
        safe_path(name)
    requests = [f'{ref}:{name}' for name in names]
    result = git(source, 'cat-file', '--batch', input_data=('\n'.join(requests) + '\n').encode())
    output, offset = {}, 0
    for name in names:
        end = result.index(b'\n', offset)
        header = result[offset:end].split()
        offset = end + 1
        if header[-1] == b'missing':
            output[name] = None
            continue
        if len(header) != 3 or header[1] != b'blob':
            raise SyncError(f'Expected a regular source blob: {name}')
        size = int(header[2])
        output[name] = result[offset:offset + size]
        offset += size
        if result[offset:offset + 1] != b'\n':
            raise SyncError('Malformed Git blob stream')
        offset += 1
    if offset != len(result):
        raise SyncError('Unexpected trailing Git blob data')
    return output


def plan(source, target_root, ref, branch=None):
    manifest_path = target_root/'tool/office_fidelity_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    independent = standalone_sources(manifest, target_root)
    base = manifest['source_commit']
    target = git(source, 'rev-parse', '--verify', '--end-of-options', ref+'^{commit}').decode().strip()
    git(source, 'cat-file', '-e', base+'^{commit}')
    expected = manifest['files']
    patches = local_patch_bases(manifest, independent)
    tree = git(source, 'diff', '--name-only', '--no-renames', base, target).decode().splitlines()
    tree += git(source, 'ls-tree', '-r', '--name-only', target, '--',
                'packages/quds_proofing_spacy', MACRO_EXAMPLES).decode().splitlines()
    names = sorted({name for name in expected if not standalone_path(name, independent)} |
                   {name for name in tree if shared(name) and not standalone_path(name, independent)})
    originals = source_files(source, base, names)
    incoming = source_files(source, target, names)
    for name, sha in expected.items():
        safe_path(name)
        path = target_root/name
        if path.is_symlink() or not path.is_file() or digest(path.read_bytes()) != sha:
            raise SyncError(f'Vendor drift: {name}; reconcile the host change first')
        if not standalone_path(name, independent):
            original = originals[name]
            if original is None or digest(original) != patches.get(name, sha):
                raise SyncError(f'Manifest does not match its source commit: {name}')
    writes, deletes = {}, []
    retained_patches = {}
    hashes = {name: sha for name, sha in expected.items() if standalone_path(name, independent)}
    for name in names:
        safe_path(name)
        path = target_root/name
        # Check ancestors as well: a symlinked directory could escape the repo.
        if not path.resolve().is_relative_to(target_root.resolve()):
            raise SyncError(f'Path escapes the host checkout: {name}')
        before = originals[name]
        after = incoming[name]
        current = path.read_bytes() if path.is_file() else None
        if name in patches and current != after:
            if after != before:
                raise SyncError(f'Upstream changed a locally patched file: {name}; reconcile it first')
            retained_patches[name] = patches[name]
            hashes[name] = expected[name]
            continue
        if path.is_symlink() or (current not in (before, after)
                                 and not (current is None and name not in expected)):
            raise SyncError(f'Unsynced host customization: {name}')
        if after is None:
            if current is not None:
                deletes.append(name)
            continue
        hashes[name] = digest(after)
        if current != after:
            writes[name] = after
    result = dict(manifest, source_commit=target, files=hashes)
    if retained_patches:
        result['local_patch_bases'] = retained_patches
    else:
        result.pop('local_patch_bases', None)
    if branch:
        result['source_branch'] = branch
    return {'before': base, 'after': target, 'writes': writes, 'deletes': deletes,
            'manifest': result, 'manifest_path': manifest_path}


def apply(target_root, change):
    # Validate the whole plan before reaching this function. Each replacement
    # uses a sibling temporary file; never truncate a live vendored source.
    modes = change.get('modes', {})
    if (set(modes) - set(change['writes'])
            or any(mode not in (0o644, 0o755) for mode in modes.values())):
        raise SyncError('Invalid source modes in sync plan')
    for name, data in change['writes'].items():
        path = target_root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = modes.get(name)
        if mode is None:
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

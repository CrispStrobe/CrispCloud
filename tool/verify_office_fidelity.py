#!/usr/bin/env python3
"""Verify Office inventory and pinned parser bytes and Git executable bits."""
import argparse
import hashlib
import json
from pathlib import Path

import sync_office_fidelity as office
import sync_legacy_doc_parser as legacy

ROOT = Path(__file__).resolve().parents[1]


def verify_git_index(root, paths):
    """Check that the next commit contains the inspected source, including logs."""
    object_format = office.git(root, 'rev-parse', '--show-object-format').decode().strip()
    if object_format not in ('sha1', 'sha256'):
        raise office.SyncError('Unsupported Git object format')
    entries = {}
    for record in office.git(root, 'ls-files', '--stage', '-z').split(b'\0'):
        if not record:
            continue
        metadata, raw_name = record.split(b'\t', 1)
        mode, oid, stage = metadata.decode().split()
        name = raw_name.decode('utf-8')
        entries.setdefault(name, []).append((mode, oid, stage))
    failures = []
    for name in sorted(paths):
        office.safe_path(name)
        staged = entries.get(name)
        if staged is None:
            failures.append(f'Office source missing from Git index: {name}')
            continue
        if len(staged) != 1 or staged[0][2] != '0':
            failures.append(f'Office source has unresolved Git index stages: {name}')
            continue
        local = root / name
        if (local.is_symlink() or not local.resolve().is_relative_to(root.resolve())
                or not local.is_file()):
            failures.append(f'Office source is not a regular local file: {name}')
            continue
        data = local.read_bytes()
        oid = hashlib.new(object_format, b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        mode = '100755' if legacy.file_mode(local) == 0o755 else '100644'
        if staged[0][:2] != (mode, oid):
            failures.append(f'Office source differs from Git index: {name}')
    return failures


def verify(root, source=None, legacy_source=None, *, require_tracked=False):
    manifest = json.loads((root / 'tool/office_fidelity_manifest.json').read_text())
    independent = office.standalone_sources(manifest, root)
    failures = []
    for name, expected in manifest['files'].items():
        office.safe_path(name)
        local = root / name
        if (local.is_symlink() or not local.resolve().is_relative_to(root.resolve())
                or not local.is_file() or office.digest(local.read_bytes()) != expected):
            failures.append(f'vendor drift: {name}')
            continue
        if source and not office.standalone_path(name, independent):
            upstream = source / name
            if not upstream.is_file() or upstream.read_bytes() != local.read_bytes():
                failures.append(f'fork mismatch: {name}')
    if independent:
        pinned = {name[len(legacy.PREFIX) + 1:]: sha
                  for name, sha in manifest['files'].items()
                  if name.startswith(legacy.PREFIX + '/')}
        if not pinned or legacy.mirror_files(root / legacy.PREFIX, pinned) != set(pinned):
            failures.append('standalone parser mirror inventory mismatch')
        if legacy_source:
            pin = independent[legacy.PREFIX]['commit']
            _, files, modes = legacy.source_snapshot(legacy_source, pin)
            actual = {name: office.digest(data) for name, data in files.items()}
            if actual != pinned:
                failures.append(f'standalone parser source mismatch at {pin}')
            for name, mode in modes.items():
                local = root / legacy.PREFIX / name
                if (local.is_symlink() or not local.resolve().is_relative_to(root.resolve())
                        or not local.is_file() or legacy.file_mode(local) != mode):
                    failures.append(f'standalone parser mode mismatch: {name}')
    elif legacy_source:
        failures.append('standalone parser source entry is missing')
    if require_tracked:
        declarations = {'tool/office_fidelity_manifest.json', 'pubspec.yaml'}
        declarations.update(f'{prefix}/UPSTREAM.json' for prefix in independent)
        failures.extend(verify_git_index(root, set(manifest['files']) | declarations))
    return manifest, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='local Quds checkout for Quds-managed files')
    parser.add_argument('--legacy-source', type=Path,
                        help='local standalone parser Git checkout containing the exact pin')
    parser.add_argument('--require-tracked', action='store_true',
                        help='require managed source and pin declarations to match the Git index')
    args = parser.parse_args()
    try:
        manifest, failures = verify(ROOT, args.source, args.legacy_source,
                                    require_tracked=args.require_tracked)
    except (office.SyncError, ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
    if failures:
        raise SystemExit('\n'.join(failures))
    print(f"Verified {len(manifest['files'])} Office files; Quds source {manifest['source_commit']}.")
    for prefix, source in manifest.get('standalone_sources', {}).items():
        print(f"Standalone source {prefix}: {source['repository']} at {source['commit']}.")


if __name__ == '__main__':
    main()

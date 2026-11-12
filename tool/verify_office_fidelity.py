#!/usr/bin/env python3
"""Verify Office inventory and pinned parser bytes and Git executable bits."""
import argparse
import json
from pathlib import Path

import sync_office_fidelity as office
import sync_legacy_doc_parser as legacy

ROOT = Path(__file__).resolve().parents[1]


def verify(root, source=None, legacy_source=None):
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
    return manifest, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='local Quds checkout for Quds-managed files')
    parser.add_argument('--legacy-source', type=Path,
                        help='local standalone parser Git checkout containing the exact pin')
    args = parser.parse_args()
    try:
        manifest, failures = verify(ROOT, args.source, args.legacy_source)
    except (office.SyncError, ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
    if failures:
        raise SystemExit('\n'.join(failures))
    print(f"Verified {len(manifest['files'])} Office files; Quds source {manifest['source_commit']}.")
    for prefix, source in manifest.get('standalone_sources', {}).items():
        print(f"Standalone source {prefix}: {source['repository']} at {source['commit']}.")


if __name__ == '__main__':
    main()

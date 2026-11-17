#!/usr/bin/env python3
"""Declare the four genuine host notices and required fixture links in wrappers.

Run after reconstruct-harnesses.py and before the final enforced-lockfile get.
This setup helper never changes either production repository.
"""
from datetime import datetime, timezone
import argparse
import hashlib
import json
from pathlib import Path

ASSETS = [
    'packages/quds_office_engine/third_party/hyphenation/LICENSE',
    'packages/quds_office_engine/third_party/proofing/WORTLISTE_LICENSE',
    'packages/quds_office_engine/third_party/proofing/QUDS_WORDS_LICENSE',
    'packages/quds_office_engine/third_party/fonttools/LICENSE',
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    toolchain = workspace / 'zotero-toolchain'
    canonical = (workspace / 'quds_office_suite').resolve()
    source = (workspace / 'CrispCloud').resolve()
    harness = toolchain / 'crisp-host-harness'
    pubspec = harness / 'pubspec.yaml'
    before = digest(pubspec)
    lock_before = digest(harness / 'pubspec.lock')
    links = []

    def link(destination, target):
        assert target.exists(), target
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.is_symlink():
            assert destination.resolve() == target.resolve(), destination
        elif destination.exists():
            raise ValueError(f'Refusing to replace existing path {destination}')
        else:
            destination.symlink_to(target, target_is_directory=target.is_dir())
        links.append({'path': str(destination), 'target': str(target)})

    link(toolchain / 'harness/quds_office_engine/third_party',
         canonical / 'packages/quds_office_engine/third_party')
    link(toolchain / 'harness/quds_office_editor/fonts',
         canonical / 'packages/quds_office_editor/fonts')
    link(harness / 'packages/quds_office_engine/third_party',
         source / 'packages/quds_office_engine/third_party')
    for name in ['office_zotero_test.dart', 'office_zotero_citing_transport_test.dart',
                 'office_zotero_ribbon_test.dart', 'office_proofing_licenses_test.dart']:
        link(harness / 'test' / name, source / 'test' / name)
    contents = pubspec.read_text()
    assert '\nflutter:\n' in contents
    if '\n  assets:\n' not in contents:
        contents = contents.rstrip() + '\n  assets:\n'
    else:
        tail = contents.rsplit('\n  assets:\n', 1)[1]
        assert all(not line.strip() or line.startswith('    - ') for line in tail.splitlines()), 'Expected the recorded trailing asset list'
    for asset in ASSETS:
        assert (harness / asset).resolve() == (source / asset).resolve()
        assert (harness / asset).is_file()
        if f'    - {asset}\n' not in contents:
            contents += f'    - {asset}\n'
    if contents != pubspec.read_text():
        pubspec.write_text(contents)
    assert digest(harness / 'pubspec.lock') == lock_before
    receipt = {'recorded_utc': datetime.now(timezone.utc).isoformat(), 'assets': ASSETS,
               'assets_sha256': {path: digest(harness / path) for path in ASSETS},
               'source_links': links, 'pubspec_sha256_before': before,
               'pubspec_sha256_after': digest(pubspec), 'dependency_lock_sha256_unchanged': lock_before,
               'pub_get_or_tests_run': False, 'production_repository_writes': False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps(receipt, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()

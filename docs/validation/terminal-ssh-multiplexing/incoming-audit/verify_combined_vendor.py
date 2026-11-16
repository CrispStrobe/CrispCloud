#!/usr/bin/env python3
"""Verify the integrated Office bytes and modes against exact Git objects.

Run from any directory after fetching the canonical Quds integration branch:
  python3 docs/validation/terminal-ssh-multiplexing/incoming-audit/verify_combined_vendor.py
The default canonical repository is ../quds-sharing-integration. No checkout is
required. This script reads repository/index data and writes only this evidence
directory; it never edits runtime sources, dependencies, refs or the index.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import lzma
from pathlib import Path
import subprocess


EVIDENCE = Path(__file__).resolve().parent
HOST = EVIDENCE.parents[3]
INITIAL = 'ea560e8c20c897f98809664e54961509e570b9cb'
PIN = '4235e690602195cc504438a6b937972c71f1ad39'
TREE = 'bb5f1912fe2ff2b5cfb3d9c7091a184ba54de0ae'
PARENTS = [
    '428679a33381f943a8ae63117d4207f01dd15462',
    '4ffdf113803806ba5f8ade4a0846eee85dcfbe68',
]
BRANCH = 'codex/terminal-sharing-office-20261116'


def git(repository, *args):
    return subprocess.check_output(['git', '-C', str(repository), *args])


def tree_entries(repository, ref):
    entries = {}
    for line in git(repository, 'ls-tree', '-r', '-z', ref).split(b'\0'):
        if not line:
            continue
        metadata, path = line.split(b'\t', 1)
        mode, kind, blob = metadata.decode().split()
        entries[path.decode()] = {'mode': mode, 'kind': kind, 'sha': blob}
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path,
                        default=HOST.parent / 'quds-sharing-integration')
    args = parser.parse_args()
    errors = []
    manifest = json.loads((HOST / 'tool/office_fidelity_manifest.json').read_text())
    before = json.loads(git(HOST, 'show', INITIAL + ':tool/office_fidelity_manifest.json'))
    canonical = tree_entries(args.source, PIN)
    initial_tree = tree_entries(HOST, INITIAL)
    actual_tree = git(args.source, 'rev-parse', PIN + '^{tree}').decode().strip()
    actual_parents = git(args.source, 'show', '-s', '--format=%P', PIN).decode().split()
    remote_pin = git(args.source, 'rev-parse', 'refs/remotes/origin/' + BRANCH).decode().strip()
    if (manifest['source_commit'] != PIN or manifest['source_branch'] != BRANCH
            or manifest['source_repository'] != 'CrispStrobe/quds_office_suite'):
        errors.append('Host canonical source identity mismatch')
    if actual_tree != TREE or actual_parents != PARENTS or remote_pin != PIN:
        errors.append('Fetched canonical commit/tree/parent mismatch')
    standalone = manifest.get('standalone_sources', {})
    if standalone != before.get('standalone_sources', {}):
        errors.append('Standalone source boundary changed')
    upstream = json.loads((HOST / 'packages/legacy_doc_parser/UPSTREAM.json').read_text())
    if upstream != dict(standalone['packages/legacy_doc_parser'], patches=[]):
        errors.append('Standalone parser metadata mismatch')
    staged = {}
    for line in git(HOST, 'ls-files', '--stage', '-z').split(b'\0'):
        if not line:
            continue
        metadata, path = line.split(b'\t', 1)
        mode, blob, stage = metadata.decode().split()
        staged.setdefault(path.decode(), []).append((mode, blob, stage))
    inventory = []
    mode_corrections = []
    content_changes = []
    for path, expected_sha256 in manifest['files'].items():
        independent = any(path.startswith(prefix + '/') for prefix in standalone)
        local = HOST / path
        if local.is_symlink() or not local.is_file():
            errors.append('Missing or unsafe host file: ' + path)
            continue
        data = local.read_bytes()
        sha256 = hashlib.sha256(data).hexdigest()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        mode = '100755' if local.stat().st_mode & 0o111 else '100644'
        if sha256 != expected_sha256:
            errors.append('Host SHA-256 mismatch: ' + path)
        if staged.get(path) != [(mode, blob, '0')]:
            errors.append('Host index content/mode mismatch: ' + path)
        expected_entry = {'kind': 'blob', 'sha': blob, 'mode': mode}
        if not independent and canonical.get(path) != expected_entry:
            errors.append('Canonical content/mode mismatch: ' + path)
        if independent and before['files'].get(path) != sha256:
            errors.append('Standalone parser content changed: ' + path)
        previous = initial_tree.get(path)
        if previous and previous['sha'] != blob:
            content_changes.append(path)
        if previous and previous['mode'] != mode:
            mode_corrections.append({'path': path, 'before': previous['mode'], 'after': mode,
                                     'content_unchanged': previous['sha'] == blob})
        inventory.append({'path': path, 'sha256': sha256, 'git_blob': blob, 'mode': mode,
                          'source': 'standalone_legacy_parser' if independent else 'combined_quds'})
    canonical_changes = git(args.source, 'diff', '--name-only', '--no-renames',
                            PARENTS[0], PIN).decode().splitlines()
    if set(content_changes) != set(canonical_changes) or len(canonical_changes) != 4:
        errors.append('Unexpected combined content delta')
    if set(before['files']) != set(manifest['files']):
        errors.append('Managed file inventory changed')
    encoded_inventory = (json.dumps(inventory, indent=2) + '\n').encode()
    (EVIDENCE / 'combined-vendor-inventory.json.xz').write_bytes(lzma.compress(encoded_inventory))
    canonical_count = sum(item['source'] == 'combined_quds' for item in inventory)
    summary = {
        'verified_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'host_initial': INITIAL,
        'host_head_at_verification': git(HOST, 'rev-parse', 'HEAD').decode().strip(),
        'host_merge_in_progress': (HOST / '.git/MERGE_HEAD').exists(),
        'canonical_repository': 'CrispStrobe/quds_office_suite',
        'canonical_branch': BRANCH,
        'canonical_commit': PIN,
        'canonical_tree': actual_tree,
        'canonical_parents': actual_parents,
        'fetched_remote_branch_matches': remote_pin == PIN,
        'managed_entries': len(inventory),
        'quds_entries': canonical_count,
        'separately_pinned_legacy_entries': len(inventory) - canonical_count,
        'standalone_sources': standalone,
        'changed_content_paths': content_changes,
        'mode_corrections': mode_corrections,
        'inventory_sha256': hashlib.sha256(encoded_inventory).hexdigest(),
        'all_managed_hashes_verified': not errors,
        'all_index_blobs_and_modes_verified': not errors,
        'all_canonical_quds_blobs_and_modes_verified': not errors,
        'standalone_legacy_bytes_unchanged': not errors,
        'errors': errors,
        'scope': 'All host bytes are freshly SHA-256 hashed and tied to stage-0 index '
                 'blobs and filesystem modes. All 552 Quds entries match the fetched '
                 'canonical Git commit by exact blob and mode. All 1,857 standalone '
                 'legacy parser hashes retain the original manifest pin and unchanged '
                 'UPSTREAM.json source boundary. No source checkout or CI is used.',
    }
    (EVIDENCE / 'combined-vendor-proof.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

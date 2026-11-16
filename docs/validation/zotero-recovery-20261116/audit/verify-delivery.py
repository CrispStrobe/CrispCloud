#!/usr/bin/env python3
"""Verify immutable Quds/CrispCloud delivery objects and describe copy coverage.

Reads Git objects and supplemental working-tree names. Writes only the requested
JSON summary and a lossless gzip inventory; does not edit source or harnesses.
Unmanaged lib/test differences are reported separately and are not failures.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import subprocess
import sys


QUDS_COMMIT = 'b87f9d6c3a2532c9695024adf48ca9fbd3c0927a'
HOST_BASELINE = '553f3be64da9ad3c35730f1b6a67d79f1ac54b72'
ZOTERO_BASELINE = '9de43669088c3719d541c9fe1c7dcb3ffbf86df3'
PARSER_PREFIX = 'packages/legacy_doc_parser/'
PARSER_PIN = {
    'repository': 'CrispStrobe/legacy-doc-parser',
    'commit': '4895712158127b2fc930d796e17035c3ca0dac62',
}
MANIFEST = 'tool/office_fidelity_manifest.json'
ZOTERO_PATHS = [
    'packages/quds_office_engine/lib/src/word/model/word_zotero.dart',
    'packages/quds_office_engine/lib/src/zotero/zotero_client.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_dialog.dart',
    'packages/quds_office_editor/lib/src/embed/word_zotero_format.dart',
]
SCOPES = [
    f'packages/{package}/{kind}/'
    for package in ['quds_office_engine', 'quds_office_editor', 'quds_reports']
    for kind in ['lib', 'test']
]


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def aggregate(value):
    return hashlib.sha256(canonical_json(value)).hexdigest()


def safe_path(name):
    if not isinstance(name, str):
        raise ValueError('Manifest paths must be strings')
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or '\0' in name or str(path) != name:
        raise ValueError(f'Unsafe repository path: {name!r}')
    return name


def git_args(repo, *arguments):
    return ['git', '--no-replace-objects', '-C', str(repo), *arguments]


def git_env():
    return {**os.environ, 'GIT_OPTIONAL_LOCKS': '0'}


def git(repo, *arguments):
    return subprocess.check_output(git_args(repo, *arguments), env=git_env())


def text(repo, *arguments):
    return git(repo, *arguments).decode('utf-8', 'surrogateescape').strip()


def commit(repo, value):
    if not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', value):
        raise ValueError('Use complete immutable commit IDs, not branch names or abbreviations')
    resolved = text(repo, 'rev-parse', '--verify', value + '^{commit}')
    if resolved != value:
        raise ValueError(f'Commit identity changed: {value} -> {resolved}')
    return value


def tree(repo, value):
    entries = {}
    for row in git(repo, 'ls-tree', '-r', '-z', '--full-tree', value).split(b'\0'):
        if not row:
            continue
        metadata, raw_path = row.split(b'\t', 1)
        mode, kind, oid = metadata.decode().split()
        path = raw_path.decode('utf-8', 'surrogateescape')
        if path in entries:
            raise ValueError(f'Duplicate Git tree path: {path}')
        entries[path] = {'mode': mode, 'type': kind, 'oid': oid}
    return entries


def blob_json(repo, value, path):
    return json.loads(git(repo, 'cat-file', 'blob', value + ':' + path))


def manifest(repo, value):
    data = blob_json(repo, value, MANIFEST)
    if not isinstance(data.get('files'), dict):
        raise ValueError('Missing manifest file inventory')
    for path, digest in data['files'].items():
        safe_path(path)
        if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ValueError(f'Invalid manifest SHA-256: {path}')
    return data


class BlobDigests:
    """Hash each unique blob once without retaining its content in memory."""

    def __init__(self, repo):
        self.process = subprocess.Popen(
            git_args(repo, 'cat-file', '--batch'), env=git_env(),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        )
        self.cache = {}
        self.bytes_hashed = 0

    def digest(self, oid):
        if oid in self.cache:
            return self.cache[oid]
        process = self.process
        process.stdin.write((oid + '\n').encode())
        process.stdin.flush()
        header = process.stdout.readline().decode().rstrip('\n').split()
        if len(header) != 3 or header[0] != oid or header[1] != 'blob':
            raise ValueError(f'Cannot read required blob: {header!r}')
        remaining = int(header[2])
        size = remaining
        digest = hashlib.sha256()
        while remaining:
            chunk = process.stdout.read(min(1024 * 1024, remaining))
            if not chunk:
                raise ValueError(f'Truncated Git blob {oid}')
            digest.update(chunk)
            remaining -= len(chunk)
        if process.stdout.read(1) != b'\n':
            raise ValueError(f'Invalid Git batch framing for {oid}')
        self.cache[oid] = digest.hexdigest()
        self.bytes_hashed += size
        return self.cache[oid]

    def close(self):
        self.process.stdin.close()
        self.process.stdout.close()
        returncode = self.process.wait()
        if returncode:
            raise RuntimeError(f'git cat-file exited {returncode}')


def parser_pin(repo, value, data):
    upstream = blob_json(repo, value, PARSER_PREFIX + 'UPSTREAM.json')
    pubspec = git(repo, 'cat-file', 'blob', value + ':pubspec.yaml').decode()
    dependency = re.search(
        r'^  legacy_doc_parser:\n    git:\n'
        r'      url: https://github.com/CrispStrobe/legacy-doc-parser.git\n'
        r'      ref: ([0-9a-f]{40})\s*$', pubspec, re.MULTILINE,
    )
    override = re.search(
        r'^dependency_overrides:\n  legacy_doc_parser:\n'
        r'    path: packages/legacy_doc_parser\s*$', pubspec, re.MULTILINE,
    )
    return {
        'standalone_sources': data.get('standalone_sources'),
        'upstream_metadata': upstream,
        'dependency_git_commit': dependency[1] if dependency else None,
        'local_override_present': override is not None,
    }


def observed_worktree(repo):
    paths = [scope.rstrip('/') for scope in SCOPES]
    untracked = sorted(p.decode('utf-8', 'surrogateescape') for p in
                       git(repo, 'ls-files', '--others', '--exclude-standard', '-z', '--', *paths).split(b'\0') if p)
    changed = sorted(p.decode('utf-8', 'surrogateescape') for p in
                     git(repo, 'diff', '--name-only', '-z', '--no-ext-diff', '--no-textconv', 'HEAD', '--', *paths).split(b'\0') if p)
    return {
        'observed_head': text(repo, 'rev-parse', 'HEAD'),
        'git_untracked_paths_in_lib_test_scope': untracked,
        'tracked_paths_differing_from_observed_head_in_lib_test_scope': changed,
        'scope': 'Supplemental working-tree observations; immutable delivery verification uses the named commits.',
    }


def verify(args):
    q, h = args.quds.resolve(), args.host.resolve()
    source = commit(q, args.quds_commit)
    host = commit(h, args.host_commit)
    baseline = commit(h, args.host_baseline)
    historic = commit(q, args.zotero_baseline)
    qtree, htree = tree(q, source), tree(h, host)
    baseline_tree, historic_tree = tree(h, baseline), tree(q, historic)
    current, previous = manifest(h, host), manifest(h, baseline)
    managed = current['files']
    parser = sorted(p for p in managed if p.startswith(PARSER_PREFIX))
    previous_parser = {p: s for p, s in previous['files'].items() if p.startswith(PARSER_PREFIX)}
    shared = sorted(set(managed) - set(parser))
    checks = {
        'same_git_object_format': text(q, 'rev-parse', '--show-object-format') == text(h, 'rev-parse', '--show-object-format'),
        'manifest_pins_requested_canonical_commit': current.get('source_commit') == source,
        'manifest_names_canonical_repository': current.get('source_repository') == 'CrispStrobe/quds_office_suite',
    }

    shared_records, parser_records, digest_mismatches = [], [], []
    blobs = BlobDigests(h)
    try:
        for path in sorted(managed):
            host_entry = htree.get(path)
            actual_digest = blobs.digest(host_entry['oid']) if host_entry and host_entry['type'] == 'blob' else None
            if actual_digest != managed[path]:
                digest_mismatches.append({'path': path, 'declared': managed[path], 'actual': actual_digest})
            reference = baseline_tree.get(path) if path.startswith(PARSER_PREFIX) else qtree.get(path)
            record = {
                'path': path, 'reference_git_entry': reference, 'host_git_entry': host_entry,
                'git_blob_type_and_mode_equal': reference is not None and reference == host_entry,
                'manifest_sha256': managed[path], 'actual_host_blob_sha256': actual_digest,
            }
            (parser_records if path.startswith(PARSER_PREFIX) else shared_records).append(record)
    finally:
        blobs.close()

    shared_mismatches = [row for row in shared_records if not row['git_blob_type_and_mode_equal']]
    parser_mismatches = [row for row in parser_records if not row['git_blob_type_and_mode_equal']]
    all_parser_names = sorted({p for p in htree if p.startswith(PARSER_PREFIX)} |
                              {p for p in baseline_tree if p.startswith(PARSER_PREFIX)})
    all_parser_records = [
        {'path': p, 'baseline': baseline_tree.get(p), 'host': htree.get(p)}
        for p in all_parser_names
    ]
    parser_all_mismatches = [row for row in all_parser_records if row['baseline'] != row['host']]
    pin_before, pin_after = parser_pin(h, baseline, previous), parser_pin(h, host, current)
    expected_pin = {
        'standalone_sources': {PARSER_PREFIX.rstrip('/'): PARSER_PIN},
        'upstream_metadata': {**PARSER_PIN, 'patches': []},
        'dependency_git_commit': PARSER_PIN['commit'],
        'local_override_present': True,
    }
    zotero = [
        {'path': path, 'historical': historic_tree.get(path), 'canonical': qtree.get(path),
         'host': htree.get(path), 'managed': path in managed}
        for path in ZOTERO_PATHS
    ]
    zotero_mismatches = [row for row in zotero if not row['historical'] or
                        row['historical'] != row['canonical'] or row['historical'] != row['host'] or not row['managed']]
    checks.update({
        'managed_non_parser_git_blobs_and_modes_identical': not shared_mismatches,
        'all_managed_manifest_sha256_values_match_host_blobs': not digest_mismatches,
        'managed_parser_has_expected_1857_entries': len(parser) == 1857,
        'managed_parser_inventory_and_manifest_hashes_unchanged': {p: managed[p] for p in parser} == previous_parser,
        'managed_parser_git_blobs_and_modes_unchanged': not parser_mismatches,
        'all_tracked_parser_paths_blobs_and_modes_unchanged': not parser_all_mismatches,
        'parser_source_pins_metadata_and_dependency_unchanged': pin_before == pin_after == expected_pin,
        'four_historical_zotero_production_blobs_and_modes_identical': not zotero_mismatches,
    })

    in_scope = lambda name: any(name.startswith(prefix) for prefix in SCOPES)
    qscope = {p: e for p, e in qtree.items() if in_scope(p)}
    hscope = {p: e for p, e in htree.items() if in_scope(p)}
    scope_records = []
    for path in sorted(set(qscope) | set(hscope)):
        canonical, host_entry = qscope.get(path), hscope.get(path)
        if path in managed:
            category = 'managed_equal' if canonical and canonical == host_entry else 'managed_different_or_missing'
        elif canonical and host_entry:
            category = 'unmanaged_equal' if canonical == host_entry else 'unmanaged_different'
        elif canonical:
            category = 'canonical_only_unmanaged'
        else:
            category = 'host_only_unmanaged'
        scope_records.append({'path': path, 'category': category, 'canonical': canonical, 'host': host_entry})
    counts = Counter(row['category'] for row in scope_records)
    differences = [row for row in scope_records if row['category'] not in ['managed_equal', 'unmanaged_equal']]
    sources = {
        'canonical_repository': 'CrispStrobe/quds_office_suite', 'canonical_commit': source,
        'canonical_tree': text(q, 'rev-parse', source + '^{tree}'),
        'host_repository': 'CrispStrobe/CrispCloud', 'host_commit': host,
        'host_tree': text(h, 'rev-parse', host + '^{tree}'),
        'host_parser_baseline_commit': baseline, 'historical_zotero_canonical_commit': historic,
        'manifest_path': MANIFEST, 'manifest_git_entry': htree.get(MANIFEST),
        'manifest_source_branch': current.get('source_branch'),
    }
    details = {
        'schema_version': 1, 'sources': sources,
        'managed_non_parser': shared_records, 'managed_parser': parser_records,
        'all_tracked_parser': all_parser_records, 'zotero_production': zotero,
        'complete_engine_editor_reports_lib_test_union': scope_records,
        'manifest_sha256_mismatches': digest_mismatches,
    }
    payload = canonical_json(details) + b'\n'
    compressed = gzip.compress(payload, mtime=0)
    args.details.parent.mkdir(parents=True, exist_ok=True)
    args.details.write_bytes(compressed)
    command = [sys.executable, str(Path(__file__).resolve()), '--quds', str(q), '--host', str(h),
               '--quds-commit', source, '--host-commit', host, '--host-baseline', baseline,
               '--zotero-baseline', historic, '--output', str(args.output.resolve()),
               '--details', str(args.details.resolve())]
    summary = {
        'schema_version': 1, 'recorded_utc': datetime.now(timezone.utc).isoformat(),
        'verified': all(checks.values()), 'checks': checks, 'sources': sources,
        'managed_copy': {
            'total_manifest_entries': len(managed), 'non_parser_entries': len(shared),
            'parser_entries': len(parser), 'host_unique_blobs_hashed': len(blobs.cache),
            'host_unique_blob_bytes_hashed': blobs.bytes_hashed,
            'non_parser_blob_mode_mismatch_count': len(shared_mismatches),
            'manifest_sha256_mismatch_count': len(digest_mismatches),
            'non_parser_records_aggregate_sha256': aggregate(shared_records),
            'manifest_map_aggregate_sha256': aggregate(managed),
            'mismatch_preview': (shared_mismatches + digest_mismatches)[:20],
        },
        'parser_preservation': {
            'managed_entries': len(parser), 'all_tracked_entries_in_baseline_or_host': len(all_parser_records),
            'managed_blob_mode_mismatch_count': len(parser_mismatches),
            'all_tracked_blob_mode_mismatch_count': len(parser_all_mismatches),
            'baseline_pin': pin_before, 'host_pin': pin_after,
            'records_aggregate_sha256': aggregate(parser_records),
            'all_tracked_records_aggregate_sha256': aggregate(all_parser_records),
            'mismatch_preview': (parser_mismatches + parser_all_mismatches)[:20],
        },
        'zotero_production': {'files': zotero, 'mismatch_count': len(zotero_mismatches),
                              'records_aggregate_sha256': aggregate(zotero)},
        'complete_lib_test_comparison': {
            'scope_prefixes': SCOPES, 'canonical_entries': len(qscope), 'host_entries': len(hscope),
            'union_entries': len(scope_records), 'categories': dict(sorted(counts.items())),
            'difference_count': len(differences), 'difference_preview': differences[:20],
            'difference_preview_truncated': len(differences) > 20,
            'records_aggregate_sha256': aggregate(scope_records),
            'canonical_inventory_aggregate_sha256': aggregate(qscope),
            'host_inventory_aggregate_sha256': aggregate(hscope),
            'interpretation': 'This covers every tracked canonical and host engine/editor/reports lib/test path. Unmanaged differences are observations outside the declared vendor inventory, not automatically errors. They do not affect the managed-copy verification result.',
        },
        'working_tree_observations': {'canonical': observed_worktree(q), 'host': observed_worktree(h)},
        'details_archive': {
            'filename': args.details.name, 'bytes': len(compressed),
            'sha256': hashlib.sha256(compressed).hexdigest(),
            'uncompressed_bytes': len(payload), 'uncompressed_sha256': hashlib.sha256(payload).hexdigest(),
            'format': 'UTF-8 JSON, gzip with mtime=0; contains all per-path records losslessly.',
        },
        'reproduction': {'argv': command, 'shell_command': shlex.join(command),
                         'dependencies': 'Python 3 standard library and Git; all four immutable commits must be available in the indicated checkouts.'},
        'verifier_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'github_actions_queried_awaited_or_rerun': False,
        'source_runtime_and_harness_writes': False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quds', type=Path, required=True, help='Canonical Git checkout')
    parser.add_argument('--host', type=Path, required=True, help='CrispCloud Git checkout')
    parser.add_argument('--quds-commit', default=QUDS_COMMIT)
    parser.add_argument('--host-commit', required=True)
    parser.add_argument('--host-baseline', default=HOST_BASELINE)
    parser.add_argument('--zotero-baseline', default=ZOTERO_BASELINE)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--details', type=Path, help='Lossless .json.gz inventory; defaults beside output')
    args = parser.parse_args()
    if args.details is None:
        args.details = args.output.with_suffix('.details.json.gz')
    result = verify(args)
    print(json.dumps({
        'verified': result['verified'], 'checks': result['checks'],
        'managed_entries': result['managed_copy']['total_manifest_entries'],
        'canonical_managed_entries': result['managed_copy']['non_parser_entries'],
        'parser_managed_entries': result['parser_preservation']['managed_entries'],
        'complete_lib_test_counts': result['complete_lib_test_comparison']['categories'],
        'complete_lib_test_difference_count': result['complete_lib_test_comparison']['difference_count'],
        'summary': str(args.output), 'compressed_details': str(args.details),
    }, indent=2))
    return 0 if result['verified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

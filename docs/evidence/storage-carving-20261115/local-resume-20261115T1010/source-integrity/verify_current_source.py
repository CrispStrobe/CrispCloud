#!/usr/bin/env python3
"""Verify this checkout against committed objects and both canonical Office pins.

This is source integrity evidence, not runtime, rendering, or schema acceptance.
It never changes managed source, resolves dependencies, or generates fixtures.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args])


def tree(root, ref):
    rows = {}
    for item in git(root, 'ls-tree', '-rz', '--full-tree', ref).split(b'\0'):
        if not item:
            continue
        meta, raw_path = item.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        rows[raw_path.decode()] = {'mode': mode, 'kind': kind, 'oid': oid}
    return rows


def inspect(path):
    if path.is_symlink():
        import os
        data = os.fsencode(os.readlink(path))
        mode = '120000'
    elif path.is_file():
        data = path.read_bytes()
        mode = '100755' if path.stat().st_mode & 0o100 else '100644'
    else:
        return {'missing': True}
    return {'mode': mode, 'kind': 'blob', 'oid': hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest(),
            'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}


def write_json(path, value):
    raw = (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
    if path.name.endswith('.gz'):
        raw = gzip.compress(raw, mtime=0)
    path.write_bytes(raw)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--quds', type=Path, required=True)
    ap.add_argument('--parser', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    repo, quds, parser, output = (p.resolve() for p in (args.repo, args.quds, args.parser, args.output))
    output.mkdir(parents=True, exist_ok=True)
    before = git(repo, 'rev-parse', 'HEAD').decode().strip()
    committed = tree(repo, before)
    manifest_path = repo / 'tool/office_fidelity_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    quds_pin = manifest['source_commit']
    parser_pin = manifest['standalone_sources']['packages/legacy_doc_parser']['commit']
    sys.path.insert(0, str(repo / 'tool'))
    import sync_office_fidelity as sync
    sync.standalone_sources(manifest, repo)
    canonical = {'quds': tree(quds, quds_pin), 'parser': tree(parser, parser_pin)}
    failures, full_records, managed_records = [], {}, {}
    for name, expected in committed.items():
        observed = inspect(repo / name)
        full_records[name] = observed
        if any(observed.get(k) != v for k, v in expected.items()):
            failures.append({'path': name, 'check': 'checkout_matches_HEAD', 'expected': expected, 'observed': observed})
    counts = Counter()
    for name, expected_sha256 in manifest['files'].items():
        source = 'parser' if name.startswith('packages/legacy_doc_parser/') else 'quds'
        source_name = name.removeprefix('packages/legacy_doc_parser/') if source == 'parser' else name
        expected = canonical[source].get(source_name)
        observed = full_records.get(name, inspect(repo / name))
        counts[source] += 1
        record = {'source': source, 'expected': expected, 'observed': observed, 'manifest_sha256': expected_sha256}
        managed_records[name] = record
        if expected is None or any(observed.get(k) != v for k, v in expected.items()):
            failures.append({'path': name, 'check': 'canonical_git_blob_and_mode', **record})
        if observed.get('sha256') != expected_sha256:
            failures.append({'path': name, 'check': 'manifest_SHA256', **record})
    pinned_parser_names = {p.removeprefix('packages/legacy_doc_parser/') for p in manifest['files'] if p.startswith('packages/legacy_doc_parser/')}
    if pinned_parser_names != set(canonical['parser']):
        failures.append({'check': 'complete_parser_inventory', 'missing': sorted(set(canonical['parser']) - pinned_parser_names),
                         'extra': sorted(pinned_parser_names - set(canonical['parser']))})
    for name, expected_pin, root in [('quds', quds_pin, quds), ('parser', parser_pin, parser)]:
        actual = git(root, 'rev-parse', 'HEAD').decode().strip()
        if actual != expected_pin:
            failures.append({'check': 'canonical_checkout_pin', 'source': name, 'expected': expected_pin, 'observed': actual})
    after = git(repo, 'rev-parse', 'HEAD').decode().strip()
    if before != after:
        failures.append({'check': 'source_HEAD_unchanged', 'before': before, 'after': after})
    write_json(output / 'full-checkout-sha256.json.gz', full_records)
    write_json(output / 'managed-source-comparison.json.gz', managed_records)
    summary = {'schema': 1, 'at': datetime.now(timezone.utc).isoformat(), 'source_commit': before,
               'source_tree': git(repo, 'rev-parse', before + '^{tree}').decode().strip(), 'source_head_after': after,
               'tracked_files_verified': len(full_records), 'managed_files_verified': len(managed_records),
               'canonical_managed_counts': dict(counts), 'canonical_pins': {'quds': quds_pin, 'parser': parser_pin},
               'manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
               'failure_count': len(failures), 'failures': failures, 'success': not failures,
               'scope': 'Full committed checkout Git blob/mode integrity; every managed SHA-256, canonical Git blob/mode, exact parser inventory and pin declaration. Does not qualify runtime, rendering, native outputs or schemas.'}
    write_json(output / 'source-verification.json', summary)
    print(json.dumps(summary, indent=2))
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())

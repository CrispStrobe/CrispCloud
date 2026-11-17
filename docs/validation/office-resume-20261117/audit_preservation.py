#!/usr/bin/env python3
"""Verify immutable canonical/host source and the previously audited boundaries."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--host', type=Path, required=True)
parser.add_argument('--canonical', type=Path, required=True)
parser.add_argument('--host-ref', default='HEAD')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()


def git(repo, *argv):
    return subprocess.check_output(['git', '-C', str(repo), *argv])


def read(repo, ref, path):
    return git(repo, 'show', ref + ':' + path)


def snapshot(repo, ref):
    result = {}
    for row in git(repo, 'ls-tree', '-r', '-z', ref).split(b'\0'):
        if not row:
            continue
        metadata, path = row.split(b'\t', 1)
        mode, kind, oid = metadata.decode().split()
        result[path.decode()] = {'mode': mode, 'type': kind, 'blob': oid}
    return result


host_ref = git(args.host, 'rev-parse', args.host_ref).decode().strip()
manifest = json.loads(read(args.host, host_ref, 'tool/office_fidelity_manifest.json'))
canonical_ref = manifest['source_commit']
host_tree = snapshot(args.host, host_ref)
canonical_tree = snapshot(args.canonical, canonical_ref)
old_host_ref = '6bc4de43867db4ef2f85da0479ab62c894d604c9'
old_host_tree = snapshot(args.host, old_host_ref)
prior_review = json.loads(read(args.host, old_host_ref,
    'docs/validation/office-continuation-20261117/independent-host-review-1d1411c5.json'))
zotero = json.loads(read(args.canonical, '555eb728ce3ea872cb5ceb3e5fd2104b21f932aa',
    'docs/validation/office-continuation-20261117/pre-section-main-canonical-source-audit.json'))['zotero']
failures = []
managed = []
mode_differences = []
parser_prefix = 'packages/legacy_doc_parser/'
for path, expected_hash in sorted(manifest['files'].items()):
    actual = host_tree.get(path)
    if actual is None:
        failures.append('missing managed file: ' + path)
        continue
    data = read(args.host, host_ref, path)
    digest = hashlib.sha256(data).hexdigest()
    standalone = path.startswith(parser_prefix)
    expected = old_host_tree.get(path) if standalone else canonical_tree.get(path)
    matched = expected is not None and actual['blob'] == expected['blob']
    if not matched or digest != expected_hash:
        failures.append('managed source/hash mismatch: ' + path)
    if standalone and actual != expected:
        failures.append('standalone parser changed: ' + path)
    if not standalone and expected and actual['mode'] != expected['mode']:
        mode_differences.append({'path': path, 'host': actual['mode'], 'canonical': expected['mode']})
    managed.append({'path': path, **actual, 'sha256': digest,
                    'bytes': len(data), 'source_matches': matched,
                    'manifest_matches': digest == expected_hash,
                    'standalone_parser': standalone})

prior_modes = prior_review['manifest']['canonical_mode_differences']
if sorted(mode_differences, key=lambda row: row['path']) != sorted(prior_modes, key=lambda row: row['path']):
    failures.append('managed executable-mode difference set changed')

protected = {}
for label, rows in [
    ('host_customizations', prior_review['host_preservation']['customizations']),
    ('original_notices', prior_review['host_preservation']['original_six_notices']),
    ('engine_license', [prior_review['host_preservation']['engine_license']]),
]:
    protected[label] = []
    for row in rows:
        path = row['path']
        expected = {'mode': row['mode'], 'type': 'blob', 'blob': row['blob']}
        actual = host_tree.get(path)
        equal = actual == expected
        protected[label].append({'path': path, 'expected': expected, 'actual': actual, 'unchanged': equal})
        if not equal:
            failures.append(label + ' changed: ' + path)

canonical_zotero = []
host_zotero = []
for row in zotero['entries']:
    path = row['path']
    expected = {'mode': row['expected_mode'], 'type': 'blob', 'blob': row['expected_blob']}
    actual = canonical_tree.get(path)
    equal = actual == expected
    canonical_zotero.append({'path': path, 'expected': expected, 'actual': actual, 'unchanged': equal})
    if not equal:
        failures.append('canonical Zotero changed: ' + path)
    if path in old_host_tree:
        equal_host = host_tree.get(path) == old_host_tree[path]
        host_zotero.append({'path': path, 'expected': old_host_tree[path],
                           'actual': host_tree.get(path), 'unchanged': equal_host})
        if not equal_host:
            failures.append('host Zotero changed: ' + path)

expected_parser_paths = {path for path in old_host_tree if path.startswith(parser_prefix)}
actual_parser_paths = {path for path in host_tree if path.startswith(parser_prefix)}
if expected_parser_paths != actual_parser_paths:
    failures.append('standalone parser path inventory changed')
for path in sorted(expected_parser_paths & actual_parser_paths):
    if host_tree[path] != old_host_tree[path]:
        failures.append('standalone parser blob/mode changed: ' + path)

result = {
    'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'host_ref': host_ref, 'canonical_ref': canonical_ref,
    'host_tree': git(args.host, 'rev-parse', host_ref + '^{tree}').decode().strip(),
    'canonical_tree': git(args.canonical, 'rev-parse', canonical_ref + '^{tree}').decode().strip(),
    'baseline_host_ref': old_host_ref,
    'standalone_source': manifest['standalone_sources'],
    'counts': {'managed': len(managed),
               'canonical': sum(not row['standalone_parser'] for row in managed),
               'parser': sum(row['standalone_parser'] for row in managed),
               'canonical_zotero': len(canonical_zotero), 'host_zotero': len(host_zotero),
               'host_customizations': len(protected['host_customizations']),
               'original_notices': len(protected['original_notices']),
               'inherited_mode_differences': len(mode_differences)},
    'managed_files': managed, 'mode_differences': mode_differences,
    'protected': protected, 'canonical_zotero': canonical_zotero, 'host_zotero': host_zotero,
    'failures': failures, 'passed': not failures,
    'scope': 'Git blobs, modes, path inventories and SHA-256 identities; runtime results are separate.',
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'host_ref': host_ref, 'canonical_ref': canonical_ref,
                  'counts': result['counts'], 'passed': not failures, 'failures': failures}, indent=2))
raise SystemExit(1 if failures else 0)

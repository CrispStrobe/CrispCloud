#!/usr/bin/env python3
"""Account for a frozen read-only Git ref snapshot using local Git objects."""
import argparse
import hashlib
import json
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parent.parent
REPO = WORKSPACE / 'crispcloud'
OUT = Path(__file__).resolve().parent
MAIN = 'bf0255a168576b0d9993d8b668f2a7d0d943fd4f'

def git(*args, check=True, text=True, input=None):
    return subprocess.run(['git', *args], cwd=REPO, check=check,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=text, input=input)

def exists(sha):
    return git('cat-file', '-e', sha + '^{commit}', check=False).returncode == 0

def ancestor(sha, target=MAIN):
    return git('merge-base', '--is-ancestor', sha, target, check=False).returncode == 0

def diff(a, b):
    return git('diff', '--binary', '--full-index', '--no-renames', a, b, text=False).stdout

def stable_patch(raw):
    value = git('patch-id', '--stable', text=False, input=raw).stdout.decode().strip()
    return value.split()[0] if value else None

def main():
    global REPO, OUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=REPO)
    parser.add_argument('--evidence-dir', type=Path, default=OUT)
    args = parser.parse_args()
    REPO, OUT = args.repo.resolve(), args.evidence_dir.resolve()
    snapshot = OUT / 'crisp-remote-refs.txt'
    meta = json.loads((OUT / 'crisp-pr-metadata.json').read_text())
    proofs = json.loads((OUT / 'crisp-remote-squash-equivalence.json').read_text())
    proof_by_sha = {row['head']: row for row in proofs}
    by_sha = {}
    for pr in meta:
        by_sha.setdefault(pr['head_sha'], []).append(pr)
    rows = []
    missing = []
    for line in snapshot.read_text().splitlines():
        sha, ref = line.split()
        row = {'ref': ref, 'sha': sha, 'prs': [p['number'] for p in by_sha.get(sha, [])]}
        if not exists(sha):
            proof = proof_by_sha.get(sha)
            if (proof and proof['tree_equal'] and proof['head_tree'] == proof['merge_tree']
                    and exists(proof['merge']) and ancestor(proof['merge'])):
                row.update(disposition='exact_squash_tree_equivalent',
                           local_head_object_available=False,
                           proof_source='GitHub Git commits API', equivalence=proof,
                           merged_counterpart_ancestor_of_integration=True)
            else:
                row['disposition'] = 'missing_local_object'
                missing.append(ref)
        elif ancestor(sha):
            row['disposition'] = 'ancestor'
        else:
            row['disposition'] = 'needs_review'
            candidates = []
            for pr in by_sha.get(sha, []):
                merge = pr['merge_sha']
                if not pr['merged_at'] or not merge or not exists(merge) or not ancestor(merge):
                    continue
                parent = git('rev-parse', merge + '^').stdout.strip()
                base = git('merge-base', sha, parent).stdout.strip()
                same_tree = git('rev-parse', sha + '^{tree}').stdout == git('rev-parse', merge + '^{tree}').stdout
                if same_tree:
                    row['disposition'] = 'exact_squash_tree_equivalent'
                    candidates.append({'pr': pr['number'], 'merge_sha': merge, 'merge_parent': parent,
                                       'head_base': base, 'same_whole_tree': True,
                                       'tree': git('rev-parse', sha + '^{tree}').stdout.strip()})
                    break
                before = diff(base, sha)
                after = diff(parent, merge)
                probe = {'pr': pr['number'], 'merge_sha': merge, 'merge_parent': parent,
                         'head_base': base, 'head_delta_sha256': hashlib.sha256(before).hexdigest(),
                         'squash_delta_sha256': hashlib.sha256(after).hexdigest(),
                         'head_patch_id': stable_patch(before), 'squash_patch_id': stable_patch(after)}
                probe['same_whole_tree'] = same_tree
                if before == after:
                    row['disposition'] = 'exact_squash_diff_equivalent'
                elif probe['same_whole_tree']:
                    row['disposition'] = 'exact_squash_tree_equivalent'
                elif probe['head_patch_id'] and probe['head_patch_id'] == probe['squash_patch_id']:
                    row['disposition'] = 'stable_patch_equivalent'
                candidates.append(probe)
                if row['disposition'] != 'needs_review':
                    break
            row['equivalence_candidates'] = candidates
        rows.append(row)
    report = {'schema_version': 1, 'repository': 'CrispStrobe/CrispCloud',
              'created_utc': datetime.now(timezone.utc).isoformat(),
              'snapshot_file_mtime_utc': datetime.fromtimestamp(snapshot.stat().st_mtime, timezone.utc).isoformat(),
              'snapshot_sha256': hashlib.sha256(snapshot.read_bytes()).hexdigest(),
              'integration_commit': MAIN, 'count': len(rows),
              'counts': dict(Counter(r['disposition'] for r in rows)),
              'branch_heads': sum(r['ref'].startswith('refs/heads/') for r in rows),
              'pr_heads': sum(r['ref'].startswith('refs/pull/') for r in rows),
              'outgoing_excluded': ['refs/heads/codex/zotero-recovery-20261116'],
              'ci_queries': False, 'refs': rows,
              'all_incoming_refs_have_recorded_disposition': all(
                  r['disposition'] in ('ancestor', 'exact_squash_tree_equivalent',
                                       'exact_squash_diff_equivalent', 'stable_patch_equivalent')
                  for r in rows)}
    (OUT / 'crisp-incoming-audit.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k:v for k,v in report.items() if k != 'refs'}, indent=2))
    print(json.dumps([r for r in rows if r['disposition'] in ('missing_local_object','needs_review')], indent=2))
    return 0 if report['all_incoming_refs_have_recorded_disposition'] else 1

if __name__ == '__main__':
    raise SystemExit(main())

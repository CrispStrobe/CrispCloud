#!/usr/bin/env python3
"""Read-only ancestry inventory for a frozen list of repository refs."""
import argparse
import collections
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--head', required=True)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--patch-equivalence', action='store_true', help='May fetch promisor blobs; leave off for metadata-only audit')
    args = parser.parse_args()
    def run(*parts, check=True):
        result = subprocess.run(['git', '-C', str(args.repo), *parts], text=True,
                                capture_output=True, check=check)
        return result
    frozen = json.loads(args.inventory.read_text())
    head = run('rev-parse', args.head).stdout.strip()
    groups = collections.defaultdict(list)
    for ref in frozen['refs']:
        groups[ref['sha']].append(ref)
    result = {'observed_utc': frozen['observed_utc'], 'head': head,
              'source_inventory': str(args.inventory), 'groups': []}
    for sha, refs in sorted(groups.items()):
        record = {'sha': sha, 'refs': refs}
        exists = run('cat-file', '-e', sha + '^{commit}', check=False)
        if exists.returncode:
            record['disposition'] = 'missing_object'
        elif run('merge-base', '--is-ancestor', sha, head, check=False).returncode == 0:
            record['disposition'] = 'ancestor'
        else:
            record['disposition'] = 'non_ancestor'
            base = run('merge-base', head, sha, check=False)
            record['merge_base'] = base.stdout.strip() or None
            record['left_right_count'] = run('rev-list', '--left-right', '--count', head + '...' + sha).stdout.strip()
            record['unique_commits'] = run('log', '--format=%H %s', head + '..' + sha).stdout.splitlines()
            record['tree_equal_to_head'] = run('rev-parse', sha + '^{tree}').stdout == run('rev-parse', head + '^{tree}').stdout
            if args.patch_equivalence:
                record['unique_patches'] = run('log', '--no-merges', '--right-only', '--cherry-pick', '--format=%H %s', head + '...' + sha).stdout.splitlines()
            if record['merge_base']:
                record['changed_paths_from_merge_base'] = run('diff', '--name-only', record['merge_base'], sha).stdout.splitlines()
        result['groups'].append(record)
    counts = collections.Counter()
    for group in result['groups']:
        counts[group['disposition']] += len(group['refs'])
    result['counts'] = dict(counts)
    result['ref_count'] = sum(counts.values())
    result['unique_head_count'] = len(groups)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'head': head, 'counts': result['counts'], 'unique_head_count': len(groups),
                      'non_ancestors': [dict(sha=x['sha'], refs=[r['ref'] for r in x['refs']], patch_equivalence_evaluated='unique_patches' in x, unique_patches=x.get('unique_patches')) for x in result['groups'] if x['disposition'] != 'ancestor']}, indent=2))


if __name__ == '__main__':
    main()

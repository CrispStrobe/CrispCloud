#!/usr/bin/env python3
"""Record fork refs and verify ancestry or exact complete-tree inclusion."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot', type=Path)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    head = git('rev-parse', args.head)
    ancestors = dict(line.split() for line in git('log', '--format=%H %T', head).splitlines())
    trees = {}
    for commit, tree in ancestors.items():
        trees.setdefault(tree, commit)
    if args.snapshot:
        refs = json.loads(args.snapshot.read_text())['refs']
    else:
        refs = []
        for line in git('for-each-ref', '--format=%(refname) %(objectname) %(symref)',
                        'refs/remotes/origin', 'refs/remotes/pull').splitlines():
            parts = line.split()
            if len(parts) == 2:
                ref, commit = parts
                refs.append({'ref': ref, 'commit': commit})
    summary = {'ancestor': 0, 'exact_tree': 0, 'outstanding': 0}
    records = []
    for ref in refs:
        commit = ref['commit']
        tree = git('rev-parse', commit + '^{tree}')
        status = 'ancestor' if commit in ancestors else 'exact_tree' if tree in trees else 'outstanding'
        summary[status] += 1
        records.append({'ref': ref['ref'], 'commit': commit, 'tree': tree,
                        'status': status, 'integrated_commit': commit if status == 'ancestor'
                        else trees.get(tree)})
    result = {'observed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'repository': 'CrispStrobe/CrispCloud', 'head': head,
              'snapshot_input': str(args.snapshot) if args.snapshot else None,
              'criterion': 'commit ancestry or exact complete Git tree equality with an ancestor',
              'counts': summary, 'refs': records}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'head': head, 'counts': summary,
                      'outstanding': [r for r in records if r['status'] == 'outstanding']}, indent=2))


if __name__ == '__main__':
    main()

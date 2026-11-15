#!/usr/bin/env python3
"""Reverify a finite connector-observed branch/PR inventory against a saved head."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

BASE = 'docs/evidence/storage-carving-20261115/local-resume-20261115T1150/incoming'
PIN = 'cc92423bb98789239380864d5e8343c19c25e815'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--head', required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    notes = Path(__file__).parent
    branches = json.loads((notes/'crispcloud-incoming-audit.json').read_text())['branches']
    prs = json.loads((notes/'crispcloud-recent-pr-metadata.json').read_text())
    def git(*argv):
        return subprocess.check_output(['git', '-C', str(args.repo), *argv])
    def ancestor(ref):
        return subprocess.run(['git', '-C', str(args.repo), 'merge-base', '--is-ancestor', ref, args.head], capture_output=True).returncode == 0
    def file(ref, path):
        return git('show', ref+':'+path)
    def oid(ref, path):
        return git('rev-parse', ref+':'+path).decode().strip()
    def changed(a,b):
        return git('diff','--name-only',a,b).decode().splitlines()
    heads = {}
    for branch in branches:
        heads.setdefault(branch['sha'], []).append('branch '+branch['name'])
    for pr in prs:
        assert pr['repository'] == 'CrispStrobe/CrispCloud', ('external fork head needs retrieval', pr)
        heads.setdefault(pr['sha'], []).append('PR#'+str(pr['number'])+' '+pr['head'])
    closure = json.loads(file(PIN, BASE+'/incoming-closure.json'))['repositories']['app']
    historical = {x['head']: x for x in closure['heads']}
    lineage = {x['head']: x for x in json.loads(file(PIN, BASE+'/superseded-path-lineage.json'))}
    rows = []
    c8 = 'c8fd8d76a5367e2712600451de3a2811b085a6c5'
    for head, labels in heads.items():
        row = {'head': head, 'labels': labels}
        if head == args.head:
            row['disposition'] = 'same_head'
        elif ancestor(head):
            row['disposition'] = 'ancestor'
        elif head in ['443db52220f25b6fa982dfa6afd18c17ed09179e','686318626e209220011f7da194cfe4e41ca4adeb']:
            assert ancestor(c8), ('missing imported source', c8)
            paths = changed(c8,head)
            assert paths == ['tool/office_fidelity_manifest.json'], paths
            previous = json.loads(file(c8,paths[0]))
            incoming = json.loads(file(head,paths[0]))
            differing = [k for k in set(previous)|set(incoming) if previous.get(k)!=incoming.get(k)]
            assert differing == ['source_commit'], differing
            row.update(disposition='source_equivalent_except_superseded_canonical_pin', proof={'already_imported_ancestor':c8,'complete_tree_difference':paths,'manifest_only_field_changed':differing,'previous_pin':previous['source_commit'],'incoming_pin':incoming['source_commit'],'current_pin':json.loads(file(args.head,paths[0]))['source_commit']})
        elif head in lineage:
            prior = historical[head]
            assert prior['disposition']=='superseded'
            proof = lineage[head]
            paths = changed(proof['merge_base'],head)
            assert set(paths)=={x['path'] for x in proof['files']}
            matched, semantic = [], []
            for item in proof['files']:
                path = item['path']
                assert oid(head,path)==item['branch_blob'], (head,path,'branch blob changed')
                match = item['matching_integration_revision']
                if match:
                    assert ancestor(match) and oid(match,path)==item['branch_blob'], (head,path,'lineage proof')
                    matched.append({'path':path,'blob':item['branch_blob'],'matching_ancestor':match})
                else:
                    semantic.append(path)
            assert len(matched)==proof['historically_imported']
            row.update(disposition='historically_imported_and_semantically_superseded', proof={'exact_blobs_reverified':len(matched),'changed_paths':len(paths),'matching_blobs':matched,'remaining_semantic_paths':semantic,'retained_semantic_finding':prior['proof']['remaining_finding'],'reviewed_current_features':['ODS file routing imports with OdsSheetReader, writes a new XLSX copy and preserves source bytes.','Quds typed XLS/ODS read-only grid retains the Legacy fallback toggle and sheet controller lifecycle.','Office service retains typed repeated/merged ODS extraction, ODT styled text/lists/notes and ODP positioned slide rendering.','Current source pins supersede older QUDS_FORKS and manifest values.']})
        else:
            raise AssertionError(('Unaccounted incoming head',row))
        rows.append(row)
    result = {'schema':1,'at':datetime.now(timezone.utc).isoformat(),'repository':'CrispStrobe/CrispCloud','review_head':args.head,'inventory':{'branches':len(branches),'recent_prs_updated_on_or_after':'2026-11-15','recent_prs':len(prs),'distinct_heads':len(heads),'external_fork_heads':0},'heads':rows,'all_observed_heads_accounted_for':True,'scope':'Finite connector-observed inventory, independently reverified against immutable local Git ancestry and blob/tree identities. Source-equivalent pins and historical supersession are explicit; this does not assert every historical head is an ancestor or that future pushes were observed.'}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    counts={d:sum(x['disposition']==d for x in rows) for d in sorted({x['disposition'] for x in rows})}
    print(json.dumps({'success':True,'distinct_heads':len(rows),'dispositions':counts,'output':str(args.output)},indent=2))


if __name__=='__main__':
    main()

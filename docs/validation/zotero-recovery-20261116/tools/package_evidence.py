#!/usr/bin/env python3
"""Publish completed qualification artifacts with lossless, deterministic archives."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('kind',choices=['canonical','host'])
p.add_argument('source',type=Path)
p.add_argument('destination',type=Path)
a=p.parse_args()
src,dst=a.source.resolve(),a.destination.resolve()
receipt=json.loads((src/'receipt.json').read_text())
assert receipt.get('all_passed') is True if a.kind=='canonical' else receipt.get('status')=='passed'
assert not dst.exists(), 'Use a new publication directory'
for command in receipt['commands']:
    path=src/command['log']
    assert path.is_file() and path.parent==src
    assert hashlib.sha256(path.read_bytes()).hexdigest()==command['log_sha256'], path

def digest(data):
    return hashlib.sha256(data).hexdigest()

dst.mkdir(parents=True)
rows=[]
for source in sorted(src.rglob('*')):
    if not source.is_file():
        continue
    assert not source.is_symlink(), source
    name=source.relative_to(src)
    data=source.read_bytes()
    compress=(source.suffix=='.log' or (source.suffix=='.json' and len(data)>20000 and source.name!='receipt.json'))
    target_name=Path(str(name)+'.gz') if compress else name
    target=dst/target_name
    target.parent.mkdir(parents=True,exist_ok=True)
    stored=gzip.compress(data,compresslevel=9,mtime=0) if compress else data
    target.write_bytes(stored)
    if compress:
        assert gzip.decompress(stored)==data
    rows.append({'original_path':str(name),'published_path':str(target_name),'compression':'gzip' if compress else None,
                 'original_bytes':len(data),'published_bytes':len(stored),'original_sha256':digest(data),'published_sha256':digest(stored)})
summary={'schema_version':1,'kind':a.kind,'source_commit':receipt.get('qualified_published_source_commit',receipt.get('source_commit')),
         'source_receipt_sha256':digest((src/'receipt.json').read_bytes()),'artifacts':rows,
         'restore':'Run gzip -dk on each .gz file to restore the exact original paths and bytes used by receipt.json.',
         'counts_include_overlapping_or_setup_runs':False}
(dst/'artifact-inventory.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
print(json.dumps({'kind':a.kind,'artifacts':len(rows),'original_bytes':sum(r['original_bytes'] for r in rows),
                  'published_bytes':sum(r['published_bytes'] for r in rows),'destination':str(dst)}))

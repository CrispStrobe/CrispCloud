#!/usr/bin/env python3
"""Independently audit selected completed recorder gates against current source.

This is a receipt recheck, not a test rerun. Gate and artifact directory arguments
are explicit so rejected attempts and predecessor evidence cannot count silently.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(value):
    return (json.dumps(value,sort_keys=True,indent=2)+'\n').encode()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo',type=Path,required=True)
    ap.add_argument('--base',type=Path,required=True)
    ap.add_argument('--gate',action='append',default=[])
    ap.add_argument('--artifact-dir',action='append',default=[])
    ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args()
    repo,base=args.repo.resolve(),args.base.resolve()
    if not args.gate:
        ap.error('at least one explicitly selected completed gate is required')
    git=lambda *p:subprocess.check_output(['git','-C',str(repo),*p])
    head=git('rev-parse','HEAD').decode().strip()

    def source_tree(ref):
        result={}
        for row in git('ls-tree','-rz',ref).split(b'\0'):
            if not row:
                continue
            identity,name=row.split(b'\t',1)
            path=os.fsdecode(name)
            if not path.startswith('docs/evidence/'):
                result[path]=identity.decode()
        return result

    def fingerprints(names):
        result={}
        for name in names:
            path=repo/name
            if path.is_symlink():
                data,kind=os.fsencode(os.readlink(path)),'symlink'
            else:
                assert path.is_file(),name
                data,kind=path.read_bytes(),'file'
            result[name]={'kind':kind,'size':len(data),'sha256':sha(data)}
        return result

    current_tree=source_tree(head)
    current=fingerprints(current_tree)
    assert not git('diff','--name-only','HEAD','--','.',':(exclude)docs/evidence/**'),'working source changes'
    assert not git('ls-files','--others','--exclude-standard','--','.',':(exclude)docs/evidence/**'),'untracked source'

    def directory(relative):
        path=(base/relative).resolve()
        assert path.is_relative_to(base) and path.is_dir(),relative
        return path

    def artifacts(path):
        manifest=json.loads((path/'artifacts-sha256.json').read_text())
        inventory={str(p.relative_to(path)) for p in path.rglob('*') if p.is_file() and p != path/'artifacts-sha256.json'}
        assert inventory==set(manifest),(path,'artifact inventory')
        for name,expected in manifest.items():
            file=path/name
            assert file.resolve().is_relative_to(path) and file.is_file() and not file.is_symlink(),name
            assert {'sha256':sha(file.read_bytes()),'size':file.stat().st_size}==expected,(path,name)
        return {'files':len(manifest),'manifest_sha256':sha((path/'artifacts-sha256.json').read_bytes()),'exact_inventory':True}

    reviews=[]
    for gate in args.gate:
        path=directory(gate)
        manifest=artifacts(path)
        meta=json.loads((path/'metadata.json').read_text())
        before,after=[json.loads(gzip.decompress((path/name).read_bytes())) for name in ['inputs-before.json.gz','inputs-after.json.gz']]
        digest=sha(encode(before['entries']))
        assert before['entries']==after['entries']
        assert digest==before['entries_sha256']==after['entries_sha256']==meta['before_entries_sha256']==meta['after_entries_sha256']
        assert before['count']==after['count']==meta['input_count']==len(before['entries'])
        assert all(before['entries'].get(name)==value for name,value in current.items()),(gate,'current source bytes differ')
        assert meta['before_tools']==meta['after_tools']
        current_tool_count=0
        for name,expected in meta['before_tools'].items():
            tool=Path(name)
            assert tool.is_file() and sha(tool.read_bytes())==expected,(gate,'current recorded tool differs',name)
            current_tool_count+=1
        assert meta['input_changes']=={'added':[],'changed':[],'removed':[]}
        assert meta['returncode']==0 and meta['qualification_success'] and meta['inputs_and_commit_stable']
        for key in ['head','tree','source_changes','untracked_source']:
            assert meta['before_git'][key]==meta['after_git'][key],(gate,key)
        assert meta['before_git']['source_changes']==meta['before_git']['untracked_source']==[]
        assert source_tree(meta['before_git']['head'])==current_tree,(gate,'source Git identity/mode differs')
        assert git('rev-parse',meta['before_git']['head']+'^{tree}').decode().strip()==meta['before_git']['tree']
        command=json.loads((path/'command.json').read_text())
        assert command['argv']==meta['command'] and command['cwd']==meta['cwd']
        review={'gate':gate,'tested_head':meta['before_git']['head'],'artifacts':manifest,
                'source_paths_compared':len(current),'source_resolution_digest':digest,
                'recorded_inputs_tools_and_head_stable':True,'current_tools_verified':current_tool_count,
                'current_source_bytes_blobs_and_modes_equal':True,'success':True}
        if (path/'suites.txt').exists():
            suites=(path/'suites.txt').read_text().splitlines()
            assert len(suites)==len(set(suites))==meta['suite_count']
            assert all((repo/s).is_file() for s in suites)
            command_suites=[arg.removeprefix(meta['repo']+'/') for arg in meta['command'] if arg.endswith('.dart')]
            assert command_suites==suites,(gate,'command suites differ')
            events=[json.loads(line) for line in (path/'stdout.jsonl').read_text().splitlines()]
            starts=[e['test']['id'] for e in events if e['type']=='testStart']
            dones=[e for e in events if e['type']=='testDone']
            ends=[e['testID'] for e in dones]
            assert len(starts)==len(set(starts))==len(ends)==len(set(ends)) and set(starts)==set(ends)
            assert all(e.get('result')=='success' and not e.get('skipped') for e in dones)
            assert not any(e['type']=='error' for e in events)
            completed=[e for e in events if e['type']=='done'];assert len(completed)==1 and completed[0]['success']
            observed={e['suite']['path'].removeprefix(meta['repo']+'/') for e in events if e['type']=='suite'}
            assert observed==set(suites)
            passed=sum(not e.get('hidden') for e in dones)
            saved=json.loads((path/'summary.json').read_text())
            assert saved['qualification_success'] and saved['done_success']
            assert saved['totals']=={'tests':passed,'passed':passed,'failed':0,'errors':0,'skipped':0,'other_results':0}
            assert not saved['missing_suites'] and not saved['unexpected_suites'] and not saved['nonpassing_requested_suites']
            review.update({'tests':passed,'suites':len(suites),'hidden_success_events':len(dones)-passed,'complete_unique_machine_events':True})
        elif 'analyze' in meta['command']:
            assert '--fatal-infos' in meta['command'] and '--fatal-warnings' in meta['command']
            assert 'No issues found!' in (path/'stdout.log').read_text()
            review['analyzed_files']=sum(arg.endswith('.dart') for arg in meta['command'])
        reviews.append(review)
    other_artifacts={name:artifacts(directory(name)) for name in args.artifact_dir}
    assert git('rev-parse','HEAD').decode().strip()==head
    assert fingerprints(current_tree)==current
    result={'schema':1,'at':datetime.now(timezone.utc).isoformat(),'review_head':head,
            'reviewer_sha256':sha(Path(__file__).read_bytes()),'gates':reviews,
            'additional_artifacts':other_artifacts,'success':True,
            'scope':'Independent raw receipt hash, source/commit/mode, tool, invocation and machine-event verification. Explicit selected gates only. Runtime totals are per gate; repeated preview executions must not be added again to primary cohort totals.'}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(encode(result));print(json.dumps(result,indent=2))


if __name__=='__main__':
    main()

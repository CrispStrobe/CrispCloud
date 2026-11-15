#!/usr/bin/env python3
"""Read saved Git objects and independently validate recovered qualification receipts."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--evidence-ref', default='59466d8b48f329362ab88e9da5e195c849557069')
    ap.add_argument('--portable-ref', default='0c574677be7749969d5c9230a5c036fde95cd87e')
    args = ap.parse_args()
    git = lambda *p: subprocess.check_output(['git', '-C', str(args.repo), *p])
    blob = lambda ref, path: git('show', f'{ref}:{path}')
    load = lambda ref, path: json.loads(blob(ref, path))
    base = 'docs/evidence/storage-carving-20261115/local-resume-20261115T1010/'
    continuation = 'docs/evidence/storage-carving-20261115/continuation-review-20261115/'

    def tree(ref, exclude_evidence=False):
        rows = {}
        for row in git('ls-tree', '-rz', ref).split(b'\0'):
            if not row:
                continue
            identity, name = row.split(b'\t', 1)
            name = name.decode()
            if exclude_evidence and name.startswith('docs/evidence/'):
                continue
            mode, kind, identity = identity.decode().split()
            rows[name] = {'mode': mode, 'kind': kind, 'blob': identity}
        return rows

    source_tree = tree(args.evidence_ref, True)
    all_tree = tree(args.evidence_ref)
    original = load(args.evidence_ref, base+'app-final/metadata.json')
    snapshot = json.loads(gzip.decompress(blob(args.evidence_ref, base+'app-final/inputs-before.json.gz')))
    proc = subprocess.Popen(['git', '-C', str(args.repo), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    source_mismatches = []
    source_fingerprints = {}
    for name, identity in source_tree.items():
        assert identity['kind'] == 'blob'
        proc.stdin.write((identity['blob']+'\n').encode()); proc.stdin.flush()
        got, kind, size = proc.stdout.readline().decode().split()
        assert got == identity['blob'] and kind == 'blob'
        data = proc.stdout.read(int(size)); assert proc.stdout.read(1) == b'\n'
        value = {'kind': 'symlink' if identity['mode']=='120000' else 'file', 'size':len(data), 'sha256':sha(data)}
        source_fingerprints[name] = value
        if snapshot['entries'].get(name) != value:
            source_mismatches.append(name)
    proc.stdin.close(); assert proc.wait() == 0
    assert not source_mismatches, source_mismatches

    def audit_manifest(directory):
        manifest = load(args.evidence_ref, directory+'/artifacts-sha256.json')
        actual = {name[len(directory)+1:] for name in all_tree if name.startswith(directory+'/')}
        actual.remove('artifacts-sha256.json')
        assert set(manifest) == actual, (directory, 'inventory')
        for name, expected in manifest.items():
            data = blob(args.evidence_ref, directory+'/'+name)
            assert {'size':len(data),'sha256':sha(data)} == expected, (directory,name)
        return len(manifest)

    gates = []
    for name in ['analysis-app-final-2','analysis-engine-final-2','analysis-cli-final','app-final','editor-final','engine-final-2','scripted-oracle-final','source-integrity-final']:
        directory = base+name
        artifacts = audit_manifest(directory)
        meta = load(args.evidence_ref, directory+'/metadata.json')
        before, after = [json.loads(gzip.decompress(blob(args.evidence_ref, directory+'/'+n))) for n in ['inputs-before.json.gz','inputs-after.json.gz']]
        expected_digest = sha(encode(before['entries']))
        assert before['entries'] == after['entries'] == snapshot['entries']
        assert expected_digest == before['entries_sha256'] == after['entries_sha256'] == meta['before_entries_sha256'] == meta['after_entries_sha256']
        assert before['count'] == after['count'] == meta['input_count'] == len(before['entries'])
        assert meta['before_tools'] == meta['after_tools']
        assert meta['input_changes'] == {'added': [], 'changed': [], 'removed': []}
        assert meta['returncode'] == 0 and meta['qualification_success'] and meta['inputs_and_commit_stable']
        for key in ['head','tree','source_changes','untracked_source']:
            assert meta['before_git'][key] == meta['after_git'][key]
        assert not meta['before_git']['source_changes'] and not meta['before_git']['untracked_source']
        assert git('rev-parse', meta['before_git']['head']+'^{tree}').decode().strip() == meta['before_git']['tree']
        assert tree(meta['before_git']['head'], True) == source_tree
        command = load(args.evidence_ref, directory+'/command.json')
        assert command['argv'] == meta['command'] and command['cwd'] == meta['cwd']
        for name_tool, expected_tool in meta['before_tools'].items():
            prefix=meta['repo']+'/'
            if name_tool.startswith(prefix) and name_tool[len(prefix):] in all_tree:
                assert sha(blob(args.evidence_ref,name_tool[len(prefix):])) == expected_tool
        row={'gate':name,'tested_head':meta['before_git']['head'],'artifacts_verified':artifacts,'source_inputs_verified':len(source_tree),'snapshot_inputs':before['count'],'source_resolution_digest':expected_digest,'original_run_stability_verified':True,'passing_commit_object_verified':True}
        if name.startswith('analysis'):
            assert '--fatal-infos' in meta['command'] and '--fatal-warnings' in meta['command']
            assert 'No issues found!' in blob(args.evidence_ref,directory+'/stdout.log').decode()
            row['analyzed_files']=len([x for x in meta['command'] if x.endswith('.dart')])
        if name in ['app-final','editor-final','engine-final-2']:
            events=[json.loads(s) for s in blob(args.evidence_ref,directory+'/stdout.jsonl').splitlines()]
            starts=[e['test']['id'] for e in events if e['type']=='testStart']
            dones=[e for e in events if e['type']=='testDone']
            ends=[e['testID'] for e in dones]
            assert len(starts)==len(set(starts))==len(ends)==len(set(ends)) and set(starts)==set(ends)
            assert all(e.get('result')=='success' and not e.get('skipped') for e in dones)
            done=[e for e in events if e['type']=='done']; assert len(done)==1 and done[0]['success']
            assert not any(e['type']=='error' for e in events)
            suite_events=[e['suite'] for e in events if e['type']=='suite']
            suite_paths={e['path'].removeprefix(meta['repo']+'/') for e in suite_events}
            suites=blob(args.evidence_ref,directory+'/suites.txt').decode().splitlines()
            assert suite_paths == set(suites) and len(suites)==len(set(suites))==meta['suite_count']
            arguments=[s.removeprefix(meta['repo']+'/') for s in meta['command'] if s.endswith('.dart')]
            assert arguments==suites
            count=sum(not e.get('hidden') for e in dones)
            summary=load(args.evidence_ref,directory+'/summary.json')
            assert summary['totals']=={'errors':0,'failed':0,'other_results':0,'passed':count,'skipped':0,'tests':count}
            assert summary['qualification_success'] and not summary['missing_suites'] and not summary['unexpected_suites'] and not summary['nonpassing_requested_suites']
            row.update({'tests':count,'suites':len(suites),'hidden_success_events':len(dones)-count,'complete_unique_events':True,'zero_failures_errors_skips':True})
        gates.append(row)

    oracle_dir=base+'scripted-artifacts-final'
    oracle_artifacts=audit_manifest(oracle_dir)
    oracle=load(args.evidence_ref,oracle_dir+'/summary.json')
    expected_names={f'{kind}/{filename}.{ext}' for kind,ext in [('word','docx'),('sheet','xlsx'),('slide','pptx')] for filename in ['edited','roundtrip-1','roundtrip-2','roundtrip-3']}
    assert oracle['success'] and oracle['before']==oracle['after'] and set(oracle['before'])==expected_names
    for path,expected in oracle['before'].items():
        data=blob(args.evidence_ref,oracle_dir+'/produced/'+path)
        assert {'size':len(data),'sha256':sha(data)}==expected
    assert oracle['oracle']=={'exports':12,'failures':[]} and oracle['commands'][1]['tests']==17
    assert all(row['returncode']==0 for row in oracle['commands'])
    assert 'Ran 17 tests' in blob(args.evidence_ref,oracle_dir+'/controls.stderr.log').decode()
    assert blob(args.evidence_ref,oracle_dir+'/oracle.stdout.log').decode().splitlines()==[n+': PASS' for n in sorted(expected_names)]
    source_summary=load(args.evidence_ref,base+'source-integrity-final-details/summary.json')
    source_verification=load(args.evidence_ref,base+'source-integrity-final-details/comparison/source-verification.json')
    assert source_summary['success'] and sum(row['unittest_count'] or 0 for row in source_summary['commands'])==82
    assert all(row['returncode']==0 for row in source_summary['commands'])
    assert source_verification['success'] and not source_verification['failures'] and source_verification['managed_files_verified']==2225

    portable=load(args.portable_ref,continuation+'portable-qualification.json')
    bundle=blob(args.portable_ref,continuation+'portable-qualification.tar.gz')
    assert len(bundle)==portable['raw_bundle']['size'] and sha(bundle)==portable['raw_bundle']['sha256']
    with tarfile.open(fileobj=io.BytesIO(bundle),mode='r:gz') as tar:
        members=[m for m in tar.getmembers() if m.isfile()]
        assert len(members)==portable['raw_bundle']['files']==len(portable['artifacts'])
        names={m.name for m in members}; assert names==set(portable['artifacts'])
        files={m.name:tar.extractfile(m).read() for m in members}
    for name,expected in portable['artifacts'].items():
        assert {'size':len(files[name]),'sha256':sha(files[name])}==expected
    before,after=[json.loads(gzip.decompress(files['png-portable-record/'+x])) for x in ['inputs-before.json.gz','inputs-after.json.gz']]
    meta=json.loads(files['png-portable-record/metadata.json'])
    assert before['entries']==after['entries']
    assert sha(encode(before['entries']))==portable['before_entries_sha256']==portable['after_entries_sha256']==meta['before_entries_sha256']==meta['after_entries_sha256']
    assert meta['before_tools']==meta['after_tools']
    assert meta['before_git']['head']==meta['after_git']['head']==portable['tested_head']
    assert tree(portable['tested_head'],True)==source_tree
    assert all(before['entries'].get(name)==value for name,value in source_fingerprints.items())
    assert meta['qualification_success'] and meta['inputs_and_commit_stable'] and meta['returncode']==0
    commands=json.loads(files['png-portable/commands.json']);assert all(x['returncode']==0 for x in commands)
    assert {x['name'] for x in commands}=={'fixture-reference','vm-candidates','javascript-compile','javascript-candidates','vm-python','javascript-python'}
    assert json.loads(files['png-portable/summary.json'])==portable['results']
    assert files['png-portable/vm-candidates.json']==files['png-portable/javascript-candidates.json']
    assert sha(files['png-portable/png-carving.js'])==portable['results']['compiled_javascript_sha256']
    args.output.parent.mkdir(parents=True,exist_ok=True)
    extraction=args.output.parent/'portable-extracted'; extraction.mkdir(exist_ok=True)
    for name in ['png-portable/vm-candidates.json','png-portable/javascript-candidates.json']:
        target=extraction/Path(name).name;target.write_bytes(files[name])
    result={'schema':1,'at':datetime.now(timezone.utc).isoformat(),'review_script_sha256':sha(Path(__file__).read_bytes()),'reviewed_integration_head':args.evidence_ref,'reviewed_portable_head':args.portable_ref,'tracked_source_files_verified':len(source_tree),'gates':gates,'runtime_total':sum(x.get('tests',0) for x in gates),'runtime_suites':sum(x.get('suites',0) for x in gates),'office_oracle':{'exports':12,'controls':17,'artifacts_verified':oracle_artifacts},'source_audit':{'managed_files':2225,'tracked_files':source_verification['tracked_files_verified'],'controls':82},'portable':{'tested_head':portable['tested_head'],'archive_files_verified':len(files),'archive_sha256':sha(bundle),'results':portable['results'],'tracked_source_equal_to_integration':True},'original_missing_gate':'navigation-capture-final','success':True,'scope':'Independent recovered raw artifact/source object/hash/machine-event audit. This is not a new Dart/Flutter execution; original passing results are bound to their tested source. Later incoming source requires newly scoped qualification.'}
    args.output.write_bytes(encode(result));print(json.dumps(result,indent=2))


if __name__=='__main__':
    main()

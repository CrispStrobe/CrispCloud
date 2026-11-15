#!/usr/bin/env python3
"""Read-only receipt/immutable-Git audit; no runtime tests or repository writes."""
from pathlib import Path
from datetime import datetime, timezone
import base64
import gzip
import hashlib
import json
import os
import struct
import subprocess

W = Path('/workspace/scratch/1e19fe1d39ae')
APP = W/'CrispCloud'
PARSER = W/'ParserCanonical'
QUDS = W/'QudsCanonical'
BASE = APP/'docs/evidence/storage-carving-20261115/local-resume-20261115T1150'
OUT = W/'evidence-review/final-acceptance'
REVIEW_HEAD = 'cc92423bb98789239380864d5e8343c19c25e815'
SOURCE_HEAD = '20ee83ff965d5433aeb528ae84debdb304edcf4a'
PARSER_PIN = '9bdcc7eba3f1ce80b7d834d7740895774eeca615'
PARSER_EVIDENCE = '57442c79239fb4d483e274e0ebb04f34686beb6c'
ENV = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_OPTIONAL_LOCKS='0')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(data):
    return (json.dumps(data, sort_keys=True, indent=2)+'\n').encode()


def read(path):
    return json.loads(path.read_bytes())


def git(repo, *args):
    return subprocess.check_output(['git','-C',str(repo),*args], env=ENV)


def obj(repo, ref, name):
    return git(repo, 'show', ref+':'+name)


def tree(repo, ref, exclude_evidence=False):
    result={}
    for row in git(repo,'ls-tree','-rz',ref).split(b'\0'):
        if not row:
            continue
        identity,name=row.split(b'\t',1)
        name=os.fsdecode(name)
        if exclude_evidence and (name.startswith('docs/evidence/') or name.startswith('doc/evidence/')):
            continue
        mode,kind,oid=identity.decode().split()
        result[name]={'mode':mode,'kind':kind,'oid':oid}
    return result


def fp(path):
    if path.is_symlink():
        data=os.fsencode(os.readlink(path));kind='symlink'
    elif path.is_file():
        data=path.read_bytes();kind='file'
    else:
        return {'kind':'missing_or_nonfile'}
    return {'kind':kind,'size':len(data),'sha256':sha(data)}


def files_match(path, mapping):
    for rel, expected in mapping.items():
        item=path/rel
        assert item.is_file() and not item.is_symlink(), str(item)
        assert {'sha256':sha(item.read_bytes()),'size':item.stat().st_size}==expected, str(item)


def unique_machine_events(data, suites, repo):
    events=[json.loads(line) for line in data.decode().splitlines()]
    starts=[x['test']['id'] for x in events if x['type']=='testStart']
    ends=[x for x in events if x['type']=='testDone']
    ids=[x['testID'] for x in ends]
    assert len(starts)==len(set(starts))==len(ids)==len(set(ids))
    assert set(starts)==set(ids)
    assert all(x['result']=='success' and not x.get('skipped') for x in ends)
    assert not [x for x in events if x['type']=='error']
    dones=[x for x in events if x['type']=='done']
    assert len(dones)==1 and dones[0]['success']
    seen=[x['suite']['path'].removeprefix(str(repo)+'/') for x in events if x['type']=='suite']
    assert len(seen)==len(set(seen))==len(suites) and set(seen)==set(suites)
    return {'tests':sum(not x.get('hidden') for x in ends),'suites':len(suites),
            'hidden_success_events':sum(bool(x.get('hidden')) for x in ends),
            'all_starts_have_one_successful_end':True,'errors':0,'skipped':0}


assert git(APP,'rev-parse','HEAD').decode().strip()==REVIEW_HEAD
assert git(PARSER,'rev-parse','HEAD').decode().strip()==PARSER_PIN
assert not git(APP,'status','--porcelain=v1','--untracked-files=all')
recorded=read(OUT/'recorded-gates.json')
assert recorded['success'] and recorded['review_head']==REVIEW_HEAD
digests={g['source_resolution_digest'] for g in recorded['gates']}
assert len(digests)==1
DIGEST=next(iter(digests))
assert tree(APP,REVIEW_HEAD,True)==tree(APP,SOURCE_HEAD,True)
changes=git(APP,'diff','--name-only',SOURCE_HEAD,REVIEW_HEAD).decode().splitlines()
assert changes and all(x.startswith('docs/evidence/') for x in changes)
report={'schema':1,'at':datetime.now(timezone.utc).isoformat(),
        'review_head':REVIEW_HEAD,'production_source':SOURCE_HEAD,
        'source_resolution_sha256':DIGEST,'reviewer_sha256':sha(Path(__file__).read_bytes()),
        'evidence_only_paths_since_production_checkpoint':len(changes),
        'recorded_gates_report_sha256':sha((OUT/'recorded-gates.json').read_bytes())}

# Generated Office files must be exactly those fingerprinted by the passed engine gate.
binding=read(BASE/'engine-final/produced-files.json')
engine_meta=read(BASE/'engine-final/metadata.json')
summary=read(BASE/'scripted-oracle-final-artifacts/summary.json')
binding_hash=sha((BASE/'engine-final/produced-files.json').read_bytes())
assert binding['tested_head']==engine_meta['before_git']['head']==summary['generation_tested_head']
assert binding['source_resolution_sha256']==DIGEST==summary['generation_source_resolution_sha256']
assert summary['generation_receipt_sha256']==binding_hash
assert engine_meta['postprocessing']=={'success':True,'produced_files_sha256':binding_hash}
assert summary['success'] and summary['produced_outputs_unchanged']
assert summary['before']==summary['after']==binding['files'] and len(binding['files'])==12
files_match(BASE/'scripted-oracle-final-artifacts/produced',binding['files'])
files_match(APP/'packages/quds_office_engine/build/fidelity-scripted',binding['files'])
assert summary['oracle']==read(BASE/'scripted-oracle-final-artifacts/produced/oracle-report.json')=={'exports':12,'failures':[]}
assert len(summary['commands'])==2 and all(c['returncode']==0 for c in summary['commands'])
assert summary['commands'][1]['tests']==17
control_log=(BASE/'scripted-oracle-final-artifacts/controls.stderr.log').read_text()
assert 'Ran 17 tests' in control_log and control_log.rstrip().endswith('OK')
report['scripted_office']={'exports':12,'oracle_controls':17,'generation_binding_sha256':binding_hash,
                          'retained_and_live_output_hashes_match':True,'semantic_report':summary['oracle']}

# Navigation capture binds six real workbooks and two images with their font/source receipts.
binding=read(BASE/'navigation-capture-final/produced-files.json')
binding_hash=sha((BASE/'navigation-capture-final/produced-files.json').read_bytes())
meta=read(BASE/'navigation-capture-final/metadata.json')
review=read(BASE/'navigation-independent-review-final-artifacts/verification.json')
assert meta['postprocessing']=={'success':True,'produced_files_sha256':binding_hash}
assert review['success'] and review['capture_machine_tests']==12
assert review['capture_tested_head']==binding['tested_head']==meta['before_git']['head']
assert review['capture_source_resolution_sha256']==binding['source_resolution_sha256']==DIGEST
assert review['capture_produced_files_receipt_sha256']==binding_hash
assert review['verifier_sha256']==sha((BASE/'plans/verify_navigation_capture.py').read_bytes())
assert len(binding['files'])==10
files_match(APP/'build',binding['files'])
retained={n.replace('office-sheet-navigation-acceptance/','workbooks/').replace('office-sheet-navigation-preview/','previews/'):v for n,v in binding['files'].items()}
files_match(BASE/'navigation-independent-review-final-artifacts',retained)
assert len(review['navigation_workbooks'])==6 and all(x['passed'] for x in review['navigation_workbooks'])
captures=[]
for name,size,locale in [('rename-validation.png',(1600,1000),'en'),('worksheet-arabic-narrow.png',(390,1000),'ar')]:
    p=BASE/'navigation-independent-review-final-artifacts/previews'/name
    png=p.read_bytes();r=read(p.with_name(name+'.json'))
    assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==size
    assert r['sha256']==sha(png) and (r['width'],r['height'])==size and r['locale']==locale
    assert r['device_pixel_ratio']==1.0 and r['capture']=='complete host render view including modal overlays'
    fonts=r['preview_only_typography']['fonts'];sources=r['capture_sources']
    assert len(fonts)==6 and len(sources)==2
    for f in fonts:
        raw=(APP/f['asset']).read_bytes();assert sha(raw)==f['sha256'] and len(raw)==f['bytes']
    for s in sources:
        assert sha((APP/s['path']).read_bytes())==s['sha256']
    captures.append({'file':name,'sha256':sha(png),'dimensions':list(size),'locale':locale,'fonts':len(fonts),'source_files':len(sources)})
report['navigation']={'generator_binding_sha256':binding_hash,'workbooks':6,'captures':captures,
                      'capture_tests_separate_from_host_total':12,'retained_and_live_output_hashes_match':True,
                      'visual_review':'Separate root-agent visual inspection; this script makes only hash/receipt/dimension checks.'}

# Portable VM / real JS outputs and independent Python report must refer to identical payloads.
p=BASE/'png-portable-final-artifacts'
summary=read(p/'summary.json');commands=read(p/'commands.json')
assert summary['qualification_success'] and summary['runtime_outputs_match']
assert len(commands)==6 and all(c['returncode']==0 for c in commands)
assert summary['compiled_javascript_sha256']==sha((p/'png-carving.js').read_bytes())
runtime_results={}
payloads=[]
for runtime in ['vm','javascript']:
    candidate=p/(runtime+'-candidates.json');d=read(candidate);check=read(p/(runtime+'-python.json'))
    assert check['candidateReceiptSha256']==sha(candidate.read_bytes())
    assert check['passed']==d['groups']==len(d['candidates'])==len(check['cases'])==8
    assert d['checks']==248 and check['verifiedPngs']==10 and check['wrongExpectedHashRejected']
    assert summary['runtimes'][runtime]=={'cases':8,'assertions':248,'verified_zips':8,'verified_pngs':10,'wrong_expected_hash_rejected':True}
    assert check['fixtureManifestSha256']==sha((APP/'test/fixtures/archives/png-carving-reference-manifest.json').read_bytes())
    cases={x['name']:x for x in check['cases']}
    for name,encoded in d['candidates'].items():
        raw=base64.b64decode(encoded,validate=True)
        assert sha(raw)==cases[name]['archiveSha256']==d['referenceCases'][name]['outputSha256']
        assert len(raw)==cases[name]['archiveBytes']
        assert cases[name]['verifiedPngs']==d['referenceCases'][name]['recovered']
    assert sum(x['verifiedPngs'] for x in cases.values())==10
    payloads.append(d)
    runtime_results[runtime]={'cases':8,'assertions':248,'zips':8,'pngs':10,'wrong_hash_control':True,
                              'candidate_receipt_sha256':sha(candidate.read_bytes())}
assert payloads[0]==payloads[1]
node=next(c for c in commands if c['name']=='javascript-candidates')['argv'][0]
assert Path(node).is_absolute() and Path(node).is_file()
portable_meta=read(BASE/'png-portable-final/metadata.json')
assert portable_meta['before_tools'][node]==sha(Path(node).read_bytes())
report['portable_png']={'runtimes':runtime_results,'actual_node':node,'node_sha256':sha(Path(node).read_bytes()),
                        'compiled_js_sha256':summary['compiled_javascript_sha256'],'vm_js_payload_identity':True}

# Managed source canonical Git identities, current bytes and file modes are independently rechecked.
manifest=read(APP/'tool/office_fidelity_manifest.json')
pins={'parser':PARSER_PIN,'quds':manifest['source_commit']}
assert manifest['standalone_sources']['packages/legacy_doc_parser']['commit']==PARSER_PIN
trees={'parser':tree(PARSER,PARSER_PIN),'quds':tree(QUDS,pins['quds'])}
app_tree=tree(APP,REVIEW_HEAD)
managed=json.loads(gzip.decompress((BASE/'source-integrity-final-details/source/comparison/managed-source-comparison.json.gz').read_bytes()))
assert set(managed)==set(manifest['files']) and len(managed)==2303
counts={'parser':0,'quds':0}
for name,expected_sha in manifest['files'].items():
    source='parser' if name.startswith('packages/legacy_doc_parser/') else 'quds'
    canonical_name=name.removeprefix('packages/legacy_doc_parser/') if source=='parser' else name
    identity=trees[source][canonical_name]
    assert app_tree[name]==identity==managed[name]['expected']
    p=APP/name;data=os.fsencode(os.readlink(p)) if p.is_symlink() else p.read_bytes()
    mode='120000' if p.is_symlink() else ('100755' if p.stat().st_mode & 0o111 else '100644')
    assert mode==identity['mode'] and sha(data)==expected_sha==managed[name]['manifest_sha256']
    assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==identity['oid']
    assert managed[name]['observed']==dict(identity,sha256=sha(data),bytes=len(data))
    counts[source]+=1
source_summary=read(BASE/'source-integrity-final-details/summary.json')
assert source_summary['success'] and source_summary['canonical_pins']==pins
assert source_summary['total_python_controls']==85 and source_summary['managed_files']==2303
report['managed_source']={'files':2303,'by_canonical':counts,'canonical_pins':pins,
                          'all_bytes_git_blobs_modes_match':True,'source_controls':85,
                          'manifest_sha256':sha((APP/'tool/office_fidelity_manifest.json').read_bytes()),
                          'full_checkout_gate_tracked_files':source_summary['tracked_files']}

# Canonical parser acceptance reads immutable Git objects, leaving pinned checkout untouched.
link=read(BASE/'canonical-parser-current-qualification.json')
assert link['source_pin']==PARSER_PIN and link['final_evidence_head']==PARSER_EVIDENCE
parser_paths=git(PARSER,'diff','--name-only',PARSER_PIN,PARSER_EVIDENCE).decode().splitlines()
assert sorted(parser_paths)==sorted(link['evidence_only_changed_paths'])
assert all(n.startswith('doc/evidence/') for n in parser_paths)
parser_source=tree(PARSER,PARSER_PIN,True)
assert parser_source==tree(PARSER,PARSER_EVIDENCE,True)
parser_reviews=[];common_parser_inputs=[]
root='doc/evidence/storage-carving-reconcile-20261115/'
for label in ['directory-focused-fixed','directory-strict-analysis','directory-all-parser-final']:
    prefix=root+label+'/'
    all_tree=tree(PARSER,PARSER_EVIDENCE)
    inventory={n[len(prefix):] for n in all_tree if n.startswith(prefix) and n!=prefix+'artifacts-sha256.json'}
    index=json.loads(obj(PARSER,PARSER_EVIDENCE,prefix+'artifacts-sha256.json'))
    assert inventory==set(index)
    data={n:obj(PARSER,PARSER_EVIDENCE,prefix+n) for n in index}
    for n,expected in index.items():
        assert {'sha256':sha(data[n]),'size':len(data[n])}==expected
    meta=json.loads(data['metadata.json']);command=json.loads(data['command.json'])
    assert link['reports'][prefix+'metadata.json']==meta
    assert meta['qualification_success'] and meta['returncode']==0 and meta['inputs_and_commit_stable']
    assert meta['before_git']==meta['after_git'] and meta['before_git']['status']==''
    assert meta['before_git']['source_changes']==meta['before_git']['untracked_source']==[]
    tested=meta['before_git']['head'];assert tree(PARSER,tested,True)==parser_source
    assert git(PARSER,'rev-parse',tested+'^{tree}').decode().strip()==meta['before_git']['tree']
    before=json.loads(gzip.decompress(data['inputs-before.json.gz']))
    after=json.loads(gzip.decompress(data['inputs-after.json.gz']))
    assert before['entries']==after['entries'] and before['count']==after['count']==len(before['entries'])==meta['input_count']
    digest=sha(canonical(before['entries']))
    assert digest==before['entries_sha256']==after['entries_sha256']==meta['before_entries_sha256']==meta['after_entries_sha256']
    assert meta['input_changes']=={'added':[],'changed':[],'removed':[]}
    normalized={n:v for n,v in before['entries'].items() if not n.startswith('doc/evidence/')}
    assert all(fp(PARSER/n)==v for n,v in normalized.items()),label
    common_parser_inputs.append(normalized)
    assert meta['before_tools']==meta['after_tools']
    for n,expected in meta['before_tools'].items():
        assert sha(Path(n).read_bytes())==expected,(label,n)
    assert command['argv']==meta['command'] and command['cwd']==meta['cwd']
    r={'label':label,'tested_head':tested,'artifact_files':len(index),'artifact_index_sha256':sha(obj(PARSER,PARSER_EVIDENCE,prefix+'artifacts-sha256.json')),
       'recorded_input_count':len(before['entries']),'recorded_input_digest':digest,
       'current_source_and_declaration_inputs':len(normalized),'current_tools_verified':len(meta['before_tools']),
       'source_identity_equal_to_app_pin':True,'success':True}
    if 'suites.txt' in data:
        suites=data['suites.txt'].decode().splitlines();assert len(suites)==len(set(suites))==meta['suite_count']
        assert [x for x in meta['command'] if x.endswith('.dart')]==suites
        r.update(unique_machine_events(data['stdout.jsonl'],suites,PARSER))
        saved=json.loads(data['summary.json']);assert link['reports'][prefix+'summary.json']==saved
        assert saved['qualification_success'] and saved['totals']=={'tests':r['tests'],'passed':r['tests'],'failed':0,'errors':0,'skipped':0,'other_results':0}
    else:
        assert '--fatal-infos' in meta['command'] and '--no-fatal-warnings' not in meta['command']
        assert 'No issues found!' in data['stdout.log'].decode() and not data['stderr.log']
        r['analyzed_files']=sum(x.endswith('.dart') for x in meta['command'])
        r['fatal_infos_explicit']=True
        r['no_analyzer_issues_reported']=True
    parser_reviews.append(r)
assert all(x==common_parser_inputs[0] for x in common_parser_inputs)
assert parser_reviews[0]['tests']==9 and parser_reviews[1]['analyzed_files']==18
assert parser_reviews[2]['tests']==4131 and parser_reviews[2]['suites']==144
report['canonical_parser']={'source_pin':PARSER_PIN,'final_evidence_head':PARSER_EVIDENCE,
                            'app_link_report_sha256':sha((BASE/'canonical-parser-current-qualification.json').read_bytes()),
                            'source_git_entries':len(parser_source),'gates':parser_reviews,
                            'normalized_source_resolution_sha256':sha(canonical(common_parser_inputs[0])),
                            'only_evidence_diffs_after_pin':True,
                            'scope':'Standalone parser development graph; host graph qualification remains the separate app/engine/editor gates.'}

# Final incoming closure is bounded to its saved observation inventory.
closure=read(W/'incoming-audit/final-closure-supplement.json')
assert closure['result']=='pass' and closure['totals']=={'observed_heads':53,'ancestors':49,'superseded':4,'unaccounted':0}
assert closure['cross_repository_binding']['source_commit']==pins['quds']
assert closure['cross_repository_binding']['standalone_parser_commit']==PARSER_PIN
assert closure['cross_repository_binding']['manifest_sha256']==report['managed_source']['manifest_sha256']
ancestry=0
for name,repository in [('app',APP),('quds',QUDS),('parser',PARSER)]:
    r=closure['repositories'][name]
    assert git(repository,'rev-parse',r['final_commit']+'^{tree}').decode().strip()==r['final_tree']
    for h in r['heads']:
        if h['disposition']=='ancestor':
            assert subprocess.run(['git','-C',str(repository),'merge-base','--is-ancestor',h['head'],r['final_commit']],env=ENV).returncode==0
            ancestry+=1
assert ancestry==49
report['incoming_closure']={'supplement_sha256':sha((W/'incoming-audit/final-closure-supplement.json').read_bytes()),
                            'observed_heads':53,'ancestors_independently_rechecked':ancestry,
                            'superseded_with_separate_reviewed_equivalence_proofs':4,'unaccounted':0,
                            'scope':closure['scope']}

assert git(APP,'rev-parse','HEAD').decode().strip()==REVIEW_HEAD
assert not git(APP,'status','--porcelain=v1','--untracked-files=all')
assert git(PARSER,'rev-parse','HEAD').decode().strip()==PARSER_PIN
report['success']=True
report['runtime_tests_rerun']=0
report['repository_writes']=0
report['ci_polls_or_waits']=0
(OUT/'cross-bindings.json').write_bytes(canonical(report))
print(json.dumps({'success':True,'output':str(OUT/'cross-bindings.json'),
                  'sha256':sha((OUT/'cross-bindings.json').read_bytes()),
                  'parser_tests':4131,'parser_suites':144,'managed_files':2303,
                  'oracle_outputs':12,'navigation_workbooks':6},indent=2))

#!/usr/bin/env python3
"""Read-only receipt/immutable-Git audit; no runtime tests or repository writes."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import base64
from collections import Counter
import gzip
import hashlib
import io
import json
import os
import re
import sys
import struct
import subprocess
import tarfile
from urllib.parse import unquote, urlsplit
from zipfile import ZipFile

ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--review-head',required=True,help='Root-announced fixed final review HEAD; run only after every selected gate is saved.')
ap.add_argument('--repo',type=Path,default=Path('/workspace/scratch/1e19fe1d39ae/CrispCloud'))
ap.add_argument('--output',type=Path,default=Path(__file__).resolve().parent)
ap.add_argument('--config',type=Path,required=True,help='Explicit final source/pin/label configuration, completed only after final freeze.')
args=ap.parse_args()
config=json.loads(args.config.read_bytes())
for field in ['source_head','quds_pin','parser_pin']:
    if not isinstance(config.get(field),str) or not re.fullmatch(r'[0-9a-f]{40}',config[field]):
        ap.error('Configuration needs a final immutable '+field)
if not re.fullmatch(r'[0-9a-f]{40}',args.review_head):
    ap.error('Review head must be a full immutable commit hash.')
if not isinstance(config.get('input_digest'),str) or not re.fullmatch(r'[0-9a-f]{64}',config['input_digest']):
    ap.error('Configuration needs the final source/resolution digest.')
if not isinstance(config.get('input_count'),int) or not isinstance(config.get('canonical_counts'),dict) or not isinstance(config.get('manifest_counts'),dict):
    ap.error('Configuration needs final input, canonical and manifest counts.')
if not isinstance(config.get('checkpoint_file'),str) or not isinstance(config.get('additional_intake_reports'),list):
    ap.error('Configuration needs the final checkpoint path and explicit additional-intake report paths.')
if set(config['canonical_counts'])!={'quds','parser'} or not all(isinstance(n,int) and n>0 for n in config['canonical_counts'].values()):
    ap.error('Canonical counts must explicitly name positive quds and parser inventories.')
suffix=config.get('gate_suffix','')
if suffix and not re.fullmatch(r'-[A-Za-z0-9._-]+',suffix):
    ap.error('Gate suffix must be empty or a simple hyphen-prefixed suffix.')
APP=args.repo.resolve()
W=APP.parent
PARSER=W/'ParserCanonical'
QUDS=W/'QudsCanonical'
BASE=(APP/config['evidence_base']).resolve()
if not BASE.is_relative_to(APP/'docs/evidence/'):
    ap.error('Evidence base must be an existing app evidence directory.')
OUT=args.output.resolve()
if any(OUT.is_relative_to(root) for root in (APP,PARSER,QUDS)):
    ap.error('Audit output must remain outside all repositories.')
OUT.mkdir(parents=True,exist_ok=True)
REVIEW_HEAD=args.review_head
SOURCE_HEAD=config['source_head']
PARSER_PIN=config['parser_pin']
QUDS_PIN=config['quds_pin']
RESTORED_QUDS_PIN='9bb71983a4ae6bc7bb3372fd931e724ddd102fc8'
MANAGED_COUNTS=config['canonical_counts']
MANAGED_TOTAL=sum(MANAGED_COUNTS.values())
PARSER_PREVIOUS_EVIDENCE='57442c79239fb4d483e274e0ebb04f34686beb6c'
PARSER_FRESH_EVIDENCE='84264525417b924476af3a9c8cfa9bbe19b6437b'
PARSER_FULL_EVIDENCE='09a4a531a4aa210a638a220de45c9d53d44c84e1'
ENV=dict(os.environ,GIT_NO_LAZY_FETCH='1',GIT_OPTIONAL_LOCKS='0')
LOGICAL_LABELS=['analysis-app','analysis-engine','analysis-editor','analysis-cli',
        'app','engine','editor','scripted-oracle','comments-oracle','source-integrity','png-portable',
        'navigation-capture','navigation-independent-review']
GATE_LABELS={name:name+suffix for name in LOGICAL_LABELS}
overrides=config.get('gate_labels') or {}
if not isinstance(overrides,dict) or not set(overrides).issubset(LOGICAL_LABELS):
    ap.error('Gate label overrides must name known logical gates.')
GATE_LABELS.update(overrides)
if len(set(GATE_LABELS.values()))!=len(LOGICAL_LABELS) or not all(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*',label) for label in GATE_LABELS.values()):
    ap.error('Every selected receipt needs a unique simple label.')
LABELS=list(GATE_LABELS.values())
ARTIFACT_DIRS=[GATE_LABELS[name]+tail for name,tail in
               [('scripted-oracle','-artifacts'),('comments-oracle','-artifacts'),('source-integrity','-details'),
                ('png-portable','-artifacts'),('navigation-independent-review','-artifacts')]]


def gate_path(logical,relative=''):
    return BASE/GATE_LABELS[logical]/relative


def artifact_path(logical,tail,relative=''):
    return BASE/(GATE_LABELS[logical]+tail)/relative




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
    def suite_path(value):
        parsed=urlsplit(value)
        assert parsed.scheme in ('','file') and parsed.netloc in ('','localhost')
        return unquote(parsed.path).removeprefix(str(repo)+'/')
    suite_records=[x['suite'] for x in events if x['type']=='suite']
    assert len(suite_records)==len({record['id'] for record in suite_records})
    seen=[suite_path(record['path']) for record in suite_records]
    assert len(seen)==len(set(seen))==len(suites) and set(seen)==set(suites)
    suite_ids={record['id']:suite_path(record['path']) for record in suite_records}
    start_records={x['test']['id']:x['test'] for x in events if x['type']=='testStart'}
    names={name:[] for name in suites}
    for end in ends:
        if end.get('hidden'):
            continue
        test=start_records[end['testID']]
        names[suite_ids[test['suiteID']]].append(test['name'])
    return {'tests':sum(not x.get('hidden') for x in ends),'suites':len(suites),
            'hidden_success_events':sum(bool(x.get('hidden')) for x in ends),
            'all_starts_have_one_successful_end':True,'errors':0,'skipped':0,
            '_visible_test_names_by_suite':names}


assert git(APP,'rev-parse','HEAD').decode().strip()==REVIEW_HEAD
assert git(PARSER,'rev-parse','HEAD').decode().strip()==PARSER_PIN
assert not git(APP,'status','--porcelain=v1','--untracked-files=all')
# This saved verifier only reads receipts/Git and writes its report to scratch.
audit_command=[sys.executable,str(BASE/'plans/audit_recorded_gates.py'),'--repo',str(APP),'--base',str(BASE)]
for label in LABELS:
    audit_command.extend(['--gate',label])
for name in ARTIFACT_DIRS:
    audit_command.extend(['--artifact-dir',name])
audit_command.extend(['--output',str(OUT/'recorded-gates.json')])
with (OUT/'recorded-gates.stdout.log').open('w') as log:
    subprocess.run(audit_command,env=ENV,stdout=log,stderr=subprocess.STDOUT,check=True)
recorded=read(OUT/'recorded-gates.json')
assert recorded['success'] and recorded['review_head']==REVIEW_HEAD
digests={g['source_resolution_digest'] for g in recorded['gates']}
assert len(digests)==1
DIGEST=next(iter(digests))
assert DIGEST==config['input_digest']
assert {g['current_source_and_resolution_paths_compared'] for g in recorded['gates']}=={config['input_count']}
raw_gate_map={g['gate']:g for g in recorded['gates']}
assert set(raw_gate_map)==set(LABELS) and len(recorded['gates'])==len(LABELS)
gate_map={logical:raw_gate_map[label] for logical,label in GATE_LABELS.items()}
for logical,required in config.get('required_runtime_suites',{}).items():
    selected=(gate_path(logical,'suites.txt')).read_text().splitlines()
    assert set(required).issubset(selected),(logical,'missing newly required suites')
for label in ['app','engine','editor','navigation-capture']:
    count=config['manifest_counts'][label]
    assert gate_map[label]['suites']==count and gate_map[label]['tests']>0
for label in ['analysis-app','analysis-engine','analysis-editor','analysis-cli']:
    count=config['manifest_counts'][label]
    assert gate_map[label]['analyzed_files']==count
assert tree(APP,REVIEW_HEAD,True)==tree(APP,SOURCE_HEAD,True)
changes=git(APP,'diff','--name-only',SOURCE_HEAD,REVIEW_HEAD).decode().splitlines()
assert changes and all(x.startswith('docs/evidence/') for x in changes)
report={'schema':1,'at':datetime.now(timezone.utc).isoformat(),
        'review_head':REVIEW_HEAD,'production_source':SOURCE_HEAD,
        'source_resolution_sha256':DIGEST,'reviewer_sha256':sha(Path(__file__).read_bytes()),
        'evidence_only_paths_since_production_checkpoint':len(changes),
        'recorded_gates_report_sha256':sha((OUT/'recorded-gates.json').read_bytes()),
        'audit_config_sha256':sha(args.config.read_bytes()),'selected_gate_labels':GATE_LABELS,
        'host_runtime':{name:{'tests':gate_map[name]['tests'],'suites':gate_map[name]['suites']} for name in ('app','engine','editor')},
        'host_total_tests':sum(gate_map[name]['tests'] for name in ('app','engine','editor')),
        'host_total_suites':sum(gate_map[name]['suites'] for name in ('app','engine','editor')),
        'navigation_tests_separate':gate_map['navigation-capture']['tests']}

# Generated Office files must be exactly those fingerprinted by the passed engine gate.
binding=read(gate_path('engine','produced-files.json'))
assert binding['gate']==GATE_LABELS['engine']
engine_meta=read(gate_path('engine','metadata.json'))
summary=read(artifact_path('scripted-oracle','-artifacts','summary.json'))
binding_hash=sha((gate_path('engine','produced-files.json')).read_bytes())
assert binding['tested_head']==engine_meta['before_git']['head']==summary['generation_tested_head']
assert binding['source_resolution_sha256']==DIGEST==summary['generation_source_resolution_sha256']
assert summary['generation_receipt_sha256']==binding_hash
assert engine_meta['postprocessing']=={'success':True,'produced_files_sha256':binding_hash}
assert summary['success'] and summary['produced_outputs_unchanged']
assert summary['before']==summary['after']==binding['files'] and len(binding['files'])==12
files_match(artifact_path('scripted-oracle','-artifacts','produced'),binding['files'])
files_match(APP/'packages/quds_office_engine/build/fidelity-scripted',binding['files'])
assert summary['oracle']==read(artifact_path('scripted-oracle','-artifacts','produced/oracle-report.json'))=={'exports':12,'failures':[]}
assert len(summary['commands'])==2 and all(c['returncode']==0 for c in summary['commands'])
assert summary['commands'][1]['tests']==17
control_log=(artifact_path('scripted-oracle','-artifacts','controls.stderr.log')).read_text()
assert 'Ran 17 tests' in control_log and control_log.rstrip().endswith('OK')
report['scripted_office']={'exports':12,'oracle_controls':17,'generation_binding_sha256':binding_hash,
                          'retained_and_live_output_hashes_match':True,'semantic_report':summary['oracle']}

# Comments generation and independent readback run inside one recorded gate.
# Bind the actual Dart invocation, immediate output hashes and independent Python tools.
comments_artifacts=artifact_path('comments-oracle','-artifacts')
comments_meta=read(gate_path('comments-oracle','metadata.json'))
comments_summary=read(comments_artifacts/'summary.json')
comments_generation=read(comments_artifacts/'generation.json')
comments_reader=read(comments_artifacts/'reader-report.json')
comments_commands=read(comments_artifacts/'commands.json')
fixture=APP/'packages/quds_office_engine/tool/fidelity/comment_schema_fixture.dart'
comments_driver=BASE/'plans/run_comments_oracle.py'
comments_verifier=BASE/'plans/verify_comments.py'
expected_comment_files=({f'comments-cycle-{cycle}.xlsx' for cycle in range(1,4)}
    | {f'collision-{kind}-{phase}.xlsx' for kind in ('valid','malformed') for phase in ('empty','added','cleared')}
    | {'expected-comments.json','collision-cases.json'})
assert comments_summary['success'] and comments_summary['reader_success'] and not comments_summary['failures']
assert comments_summary['tools_unchanged'] and comments_summary['tools_before']==comments_summary['tools_after']
assert comments_summary['tested_head']==comments_generation['tested_head']==comments_meta['before_git']['head']
assert comments_summary['source_resolution_sha256']==comments_generation['source_resolution_sha256']==DIGEST
assert comments_summary['generation_sha256']==sha((comments_artifacts/'generation.json').read_bytes())
assert comments_summary['reader_report_sha256']==sha((comments_artifacts/'reader-report.json').read_bytes())
assert set(comments_summary['expected_outputs'])==set(comments_generation['files'])==expected_comment_files
assert {p.name for p in (comments_artifacts/'workbooks').iterdir()}==expected_comment_files
files_match(comments_artifacts/'workbooks',comments_generation['files'])
reader_inputs={name:{'bytes':item['size'],'sha256':item['sha256']} for name,item in comments_generation['files'].items()}
assert comments_reader['success'] and comments_reader['inputs_unchanged']
assert comments_reader['inputs_before']==comments_reader['inputs_after']==reader_inputs
assert not comments_reader['setup_failures'] and not comments_reader['failure_counts']
assert comments_reader['oracle_script_sha256']==sha(comments_verifier.read_bytes())
for item in (comments_generation['dart'],comments_generation['generator']):
    path=Path(item['path'])
    assert fp(path)=={'kind':'file','size':item['size'],'sha256':item['sha256']}
    assert comments_meta['before_tools'][str(path)]==item['sha256']
assert comments_generation['generator']['path']==str(fixture)
assert comments_generation['dart']['path'].endswith('/bin/cache/dart-sdk/bin/dart')
for path,item in comments_summary['tools_before'].items():
    assert fp(Path(path))=={'kind':'file',**item}
for path in (fixture,comments_driver,comments_verifier):
    assert comments_meta['before_tools'][str(path)]==sha(path.read_bytes())
assert comments_commands==comments_summary['commands'] and len(comments_commands)==2
assert [command['name'] for command in comments_commands]==['generate','independent-reader']
assert all(command['returncode']==0 and command['cwd']==str(APP/'packages/quds_office_engine') for command in comments_commands)
assert comments_commands[0]['argv']==[comments_generation['dart']['path'],'run',str(fixture),str(comments_artifacts/'workbooks')]
python_path=Path(comments_reader['tools']['python_executable'])
assert sha(python_path.read_bytes())==comments_reader['tools']['python_executable_sha256']
assert comments_commands[1]['argv']==[comments_commands[1]['argv'][0],str(comments_verifier),'--input-dir',
    str(comments_artifacts/'workbooks'),'--report',str(comments_artifacts/'reader-report.json')]
assert Path(comments_commands[1]['argv'][0]).resolve()==python_path.resolve()
assert comments_summary['tools_before'][str(python_path.resolve())]['sha256']==comments_reader['tools']['python_executable_sha256']
assert len(comments_reader['tool_module_hashes'])==5
for path,item in comments_reader['tool_module_hashes'].items():
    assert fp(Path(path))=={'kind':'file','size':item['bytes'],'sha256':item['sha256']}
classic_expected=read(comments_artifacts/'workbooks/expected-comments.json')
assert comments_reader['expected_comments']==classic_expected and len(classic_expected)==6
cycles=comments_reader['cycles']
collisions=comments_reader['collisions']
assert len(cycles)==3 and {case['file'] for case in cycles}=={f'comments-cycle-{n}.xlsx' for n in range(1,4)}
assert len(collisions)==6 and {case['file'] for case in collisions}=={f'collision-{kind}-{phase}.xlsx' for kind in ('valid','malformed') for phase in ('empty','added','cleared')}
assert comments_reader['checks']==sum(case['checks'] for case in cycles+collisions)
assert all(case['success'] and not case['failures'] and case['checks']>0 for case in cycles+collisions)
def expected_notes(rows):
    return {row['cell']:{'text':row['text'],'author':row['author']} for row in rows}
for case in cycles:
    assert case['input']==reader_inputs[case['file']]
    assert case['worksheet_name']=='Notes'
    assert case['external_reader']['comments']==expected_notes(classic_expected)
collision_manifest=read(comments_artifacts/'workbooks/collision-cases.json')
assert collision_manifest['schema_version']==1 and len(collision_manifest['cases'])==6
collision_by_file={case['file']:case for case in collision_manifest['cases']}
assert set(collision_by_file)=={case['file'] for case in collisions}
for case in collisions:
    expected=collision_by_file[case['file']]
    assert case['phase']==expected['phase']
    assert [sheet['worksheet_name'] for sheet in case['worksheets']]==['Original','Added']
    assert len({sheet['comments_part'] for sheet in case['worksheets']})==2
    assert all(sheet['comments_part']!=expected['orphan_part'] and sheet['success'] and not sheet['failures']
               and sheet['input']==reader_inputs[case['file']] for sheet in case['worksheets'])
    for sheet,notes in zip(case['worksheets'],[expected['original_comments'],expected['comments']]):
        assert sheet['external_reader']['comments']==expected_notes(notes)
    assert len(expected['comments'])==(1 if expected['phase']=='added' else 0)
    with ZipFile(comments_artifacts/'workbooks'/case['file']) as package:
        for key,part_key,bytes_key in [('orphan','orphan_part','orphan_base64'),
                                     ('orphan_relationships','orphan_relationships_part','orphan_relationships_base64')]:
            original=base64.b64decode(expected[bytes_key],validate=True)
            assert package.read(expected[part_key])==original
            assert case[key]['part']==expected[part_key]
            assert case[key]['bytes']==len(original) and case[key]['sha256']==sha(original)
report['independent_comments']={'xlsx_outputs':9,'classic_repeated_saves':3,'authored_classic_comments_per_save':6,
    'orphan_collision_lifecycle_outputs':6,'checks':comments_reader['checks'],
    'generation_binding_sha256':comments_summary['generation_sha256'],
    'reader_report_sha256':comments_summary['reader_report_sha256'],
    'actual_pinned_dart_generator_and_source_bound':True,'unchanged_output_inputs':11,
    'exact_original_notes_orphan_xml_relationships_and_empty_authority_checked':True,
    'independent_reader_modules_verified':5,
    'scope':'Bounded plain-comment packages and two orphan kinds through empty/add/clear. No external Excel, VML geometry or full Open XML schema certification.'}

# Navigation capture binds six real workbooks and two images with their font/source receipts.
binding=read(gate_path('navigation-capture','produced-files.json'))
assert binding['gate']==GATE_LABELS['navigation-capture']
binding_hash=sha((gate_path('navigation-capture','produced-files.json')).read_bytes())
meta=read(gate_path('navigation-capture','metadata.json'))
review=read(artifact_path('navigation-independent-review','-artifacts','verification.json'))
assert meta['postprocessing']=={'success':True,'produced_files_sha256':binding_hash}
assert review['success'] and review['capture_machine_tests']==gate_map['navigation-capture']['tests']
assert review['capture_tested_head']==binding['tested_head']==meta['before_git']['head']
assert review['capture_source_resolution_sha256']==binding['source_resolution_sha256']==DIGEST
assert review['capture_produced_files_receipt_sha256']==binding_hash
assert review['verifier_sha256']==sha((BASE/'plans/verify_navigation_capture.py').read_bytes())
assert len(binding['files'])==10
files_match(APP/'build',binding['files'])
retained={n.replace('office-sheet-navigation-acceptance/','workbooks/').replace('office-sheet-navigation-preview/','previews/'):v for n,v in binding['files'].items()}
files_match(artifact_path('navigation-independent-review','-artifacts',''),retained)
assert len(review['navigation_workbooks'])==6 and all(x['passed'] for x in review['navigation_workbooks'])
captures=[]
for name,size,locale in [('rename-validation.png',(1600,1000),'en'),('worksheet-arabic-narrow.png',(390,1000),'ar')]:
    p=artifact_path('navigation-independent-review','-artifacts','previews')/name
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
                      'capture_tests_separate_from_host_total':gate_map['navigation-capture']['tests'],'retained_and_live_output_hashes_match':True,
                      'visual_review':'Separate root-agent visual inspection; this script makes only hash/receipt/dimension checks.'}

# Portable VM / real JS outputs and independent Python report must refer to identical payloads.
p=artifact_path('png-portable','-artifacts','')
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
portable_meta=read(gate_path('png-portable','metadata.json'))
assert portable_meta['before_tools'][node]==sha(Path(node).read_bytes())
report['portable_png']={'runtimes':runtime_results,'actual_node':node,'node_sha256':sha(Path(node).read_bytes()),
                        'compiled_js_sha256':summary['compiled_javascript_sha256'],'vm_js_payload_identity':True}

# Managed source canonical Git identities, current bytes and file modes are independently rechecked.
manifest=read(APP/'tool/office_fidelity_manifest.json')
pins={'parser':PARSER_PIN,'quds':QUDS_PIN}
assert manifest['source_commit']==QUDS_PIN
assert manifest['standalone_sources']['packages/legacy_doc_parser']['commit']==PARSER_PIN
trees={'parser':tree(PARSER,PARSER_PIN),'quds':tree(QUDS,pins['quds'])}
app_tree=tree(APP,REVIEW_HEAD)
managed=json.loads(gzip.decompress((artifact_path('source-integrity','-details','source/comparison/managed-source-comparison.json.gz')).read_bytes()))
assert set(managed)==set(manifest['files']) and len(managed)==MANAGED_TOTAL
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
assert counts==MANAGED_COUNTS
source_summary=read(artifact_path('source-integrity','-details','summary.json'))
assert source_summary['success'] and source_summary['canonical_pins']==pins
assert source_summary['total_python_controls']==85 and source_summary['managed_files']==MANAGED_TOTAL
report['managed_source']={'files':MANAGED_TOTAL,'by_canonical':counts,'canonical_pins':pins,
                          'all_bytes_git_blobs_modes_match':True,'source_controls':85,
                          'manifest_sha256':sha((APP/'tool/office_fidelity_manifest.json').read_bytes()),
                          'full_checkout_gate_tracked_files':source_summary['tracked_files']}

# Exact Linux golden comparison scope in the fresh editor raw event stream.
editor=gate_path('editor','')
editor_meta=read(editor/'metadata.json')
editor_suites=(editor/'suites.txt').read_text().splitlines()
editor_events=unique_machine_events((editor/'stdout.jsonl').read_bytes(),editor_suites,APP)
golden_cases={
    'packages/quds_office_editor/test/office_fidelity_golden_test.dart':[
        'DOCX import and exported reopen match reviewed page golden'],
    'packages/quds_office_editor/test/office_structure_goldens_test.dart':[
        'create structure matches reviewed pages through three saves',
        'edit structure matches reviewed pages through three saves',
        'remove structure matches reviewed pages through three saves'],
}
assert editor_meta['cwd']==str(APP/'packages/quds_office_editor')
assert editor_meta['platform'].startswith('Linux-')
assert any(p.endswith('/linux-x64/flutter_tester') for p in editor_meta['before_tools'])
for arg in editor_meta['command']:
    assert not any(arg==flag or arg.startswith(flag+'=') for flag in
                   ['--update-goldens','--name','--plain-name','--tags','--exclude-tags'])
for suite,names in golden_cases.items():
    assert Counter(editor_events['_visible_test_names_by_suite'][suite])==Counter(names)
    source=(APP/suite).read_text()
    assert 'setUpAll(OfficeHostFonts.ensureRegistered)' in source
    assert 'matchesGoldenFile(' in source and 'Platform.isLinux' in source
    assert 'tester.view.devicePixelRatio = 1;' in source and 'Size(800, 1120)' in source
    assert not any(token in source for token in ['goldenFileComparator =','autoUpdateGoldenFiles =','skip:'])
assert not any(name.endswith('flutter_test_config.dart') for name in app_tree), 'Review custom test configuration before relying on standard comparator.'
provenance_path=APP/'packages/quds_office_editor/test/goldens/linux/word-pages-provenance.json'
provenance=read(provenance_path)
expected_golden_names={'office_fidelity_word.png','structure_create_1.png','structure_edit_1.png','structure_edit_2.png','structure_remove_1.png'}
assert {x['file'] for x in provenance['references']}==expected_golden_names
editor_inputs=json.loads(gzip.decompress((editor/'inputs-before.json.gz').read_bytes()))['entries']
goldens=[]
for expected in provenance['references']:
    relative='packages/quds_office_editor/test/goldens/linux/'+expected['file']
    data=(APP/relative).read_bytes()
    assert data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',data[16:24])==(800,1120)
    assert sha(data)==expected['sha256']==editor_inputs[relative]['sha256']
    assert len(data)==editor_inputs[relative]['size']
    goldens.append({'path':relative,'sha256':sha(data),'size':len(data),'dimensions':[800,1120]})
font_loader_path=APP/'packages/quds_office_editor/lib/src/embed/office_host_fonts.dart'
font_names=re.findall(r"_asset\('([^']+)'\)",font_loader_path.read_text())
assert len(font_names)==len(set(font_names))==14
font_assets=[]
for name in font_names:
    path='packages/quds_office_editor/fonts/'+name
    actual=fp(APP/path)
    assert editor_inputs[path]==actual
    font_assets.append({'path':path,**actual})
report['linux_word_goldens']={
    'editor_tested_head':editor_meta['before_git']['head'],
    'passing_case_names':golden_cases,'reference_files':goldens,
    'source_bound_font_assets':font_assets,
    'font_loader_sha256':sha(font_loader_path.read_bytes()),
    'reference_provenance_sha256':sha(provenance_path.read_bytes()),
    'source_defined_exact_comparison_scope':{'import_and_reopen':2,'structure_save_cycles':16,'total':18},
    'standard_comparator_and_no_update_or_filter_flags':True,
    'scope':'Fresh successful Linux cases against five exact tracked references. Comparison-loop count is from frozen test source; no new golden capture or external Word/macOS rendering claim.',
}

# Parser combines historical complete qualification with one fresh changed suite.
# Immutable Git reads preserve the pinned canonical checkout and distinguish scope.
link_root=BASE/'canonical-parser-observed-pin'
link=read(link_root/'canonical-parser-observed-pin-qualification.json')
equivalence=read(link_root/'source-equivalence.json')
assert link['source_pin']==PARSER_PIN and link['evidence_commit']==PARSER_FRESH_EVIDENCE
assert link['retained_prior_full_run']['fresh_full_run_at_current_pin'] is False
assert link['retained_prior_full_run']['evidence_commit']==PARSER_PREVIOUS_EVIDENCE
fresh_base=link['evidence_base'].rstrip('/')+'/'
for name,expected in link['copied_linkage_files'].items():
    data=(link_root/name).read_bytes()
    assert {'sha256':sha(data),'size':len(data)}==expected
remote_index=read(link_root/'canonical-receipt-artifacts.json')
assert len(remote_index)==len(link['remote_receipt_artifacts'])
assert {r['path']: {'sha256':r['sha256'],'size':r['size']} for r in link['remote_receipt_artifacts']}=={
    fresh_base+name:value for name,value in remote_index.items()}
for name,expected in remote_index.items():
    data=obj(PARSER,PARSER_FRESH_EVIDENCE,fresh_base+name)
    assert {'sha256':sha(data),'size':len(data)}==expected
assert json.loads(obj(PARSER,PARSER_FRESH_EVIDENCE,fresh_base+'source-equivalence.json'))==equivalence
assert (link_root/'README.md').read_bytes()==obj(PARSER,PARSER_FRESH_EVIDENCE,fresh_base+'README.md')
changed_test='test/recovery_reconciliation_bounds_test.dart'
previous_tree=tree(PARSER,PARSER_PREVIOUS_EVIDENCE)
current_tree=tree(PARSER,PARSER_PIN)
assert set(previous_tree)==set(current_tree)
delta={name for name in current_tree if previous_tree[name]!=current_tree[name]}
assert delta=={changed_test}
assert len(current_tree)==equivalence['tracked_path_count']==1832
assert equivalence['unchanged_tracked_paths']==len(current_tree)-1
assert equivalence['production_dependencies_and_other_tests_equal']
delta_record=equivalence['only_tracked_delta'][changed_test]
for key,identity in [('before',previous_tree[changed_test]),('after',current_tree[changed_test])]:
    assert delta_record[key]=={'mode':identity['mode'],'type':identity['kind'],'git_blob':identity['oid']}
numstat=git(PARSER,'diff','--numstat',PARSER_PREVIOUS_EVIDENCE,PARSER_PIN,'--',changed_test).decode().strip().split('\t')
assert numstat==['29','0',changed_test]
assert tree(PARSER,PARSER_PIN,True)==tree(PARSER,PARSER_FRESH_EVIDENCE,True)
parser_source=tree(PARSER,PARSER_PIN,True)
parser_gates=[]
parser_details={}


def parser_gate(label,evidence,prefix,historical):
    index=json.loads(obj(PARSER,evidence,prefix+'artifacts-sha256.json'))
    evidence_tree=tree(PARSER,evidence)
    inventory={name[len(prefix):] for name in evidence_tree if name.startswith(prefix) and name!=prefix+'artifacts-sha256.json'}
    assert inventory==set(index)
    data={name:obj(PARSER,evidence,prefix+name) for name in index}
    for name,expected in index.items():
        assert {'sha256':sha(data[name]),'size':len(data[name])}==expected
    meta=json.loads(data['metadata.json']);command=json.loads(data['command.json'])
    assert meta['qualification_success'] and meta['returncode']==0 and meta['inputs_and_commit_stable']
    assert meta['before_git']==meta['after_git'] and meta['before_git']['status']==''
    assert meta['before_git']['source_changes']==meta['before_git']['untracked_source']==[]
    tested=meta['before_git']['head']
    tested_source=tree(PARSER,tested,True)
    differences={name for name in tested_source.keys() | parser_source.keys() if tested_source.get(name)!=parser_source.get(name)}
    assert differences==({changed_test} if historical else set())
    assert git(PARSER,'rev-parse',tested+'^{tree}').decode().strip()==meta['before_git']['tree']
    before=json.loads(gzip.decompress(data['inputs-before.json.gz']))
    after=json.loads(gzip.decompress(data['inputs-after.json.gz']))
    assert before['entries']==after['entries'] and before['count']==after['count']==len(before['entries'])==meta['input_count']
    digest=sha(canonical(before['entries']))
    assert digest==before['entries_sha256']==after['entries_sha256']==meta['before_entries_sha256']==meta['after_entries_sha256']
    assert meta['input_changes']=={'added':[],'changed':[],'removed':[]}
    normalized={name:value for name,value in before['entries'].items() if not name.startswith('doc/evidence/')}
    assert all(fp(PARSER/name)==value for name,value in normalized.items() if not historical or name!=changed_test)
    if historical:
        prior_test=obj(PARSER,tested,changed_test)
        assert normalized[changed_test]=={'kind':'file','sha256':sha(prior_test),'size':len(prior_test)}
    assert meta['before_tools']==meta['after_tools']
    for name,expected in meta['before_tools'].items():
        assert sha(Path(name).read_bytes())==expected,(label,name)
    assert command['argv']==meta['command'] and command['cwd']==meta['cwd']
    result={'label':label,'evidence_commit':evidence,'tested_head':tested,'historical_full_graph_scope':historical,
            'artifact_files':len(index),'artifact_index_sha256':sha(obj(PARSER,evidence,prefix+'artifacts-sha256.json')),
            'recorded_input_count':len(before['entries']),'recorded_input_digest':digest,
            'normalized_source_resolution_inputs':len(normalized),'current_tools_verified':len(meta['before_tools']),
            'production_dependencies_and_unchanged_tests_equal_to_app_pin':True,'success':True}
    case_names={}
    if 'suites.txt' in data:
        suites=data['suites.txt'].decode().splitlines()
        assert len(suites)==len(set(suites))==meta['suite_count']
        assert [arg for arg in meta['command'] if arg.endswith('.dart')]==suites
        machine=unique_machine_events(data['stdout.jsonl'],suites,PARSER)
        case_names=machine.pop('_visible_test_names_by_suite')
        result.update(machine)
        saved=json.loads(data['summary.json'])
        assert saved['qualification_success'] and saved['done_success']
        assert saved['totals']=={'tests':result['tests'],'passed':result['tests'],'failed':0,'errors':0,'skipped':0,'other_results':0}
        assert not saved['missing_suites'] and not saved['unexpected_suites'] and not saved['nonpassing_requested_suites']
    else:
        assert '--fatal-infos' in meta['command'] and '--no-fatal-warnings' not in meta['command']
        assert 'No issues found!' in data['stdout.log'].decode() and not data['stderr.log']
        result['analyzed_files']=sum(arg.endswith('.dart') for arg in meta['command'])
        result['fatal_infos_explicit']=True
        result['no_analyzer_issues_reported']=True
    parser_details[label]={'meta':meta,'normalized':normalized,'names':case_names}
    parser_gates.append(result)
    return result


prior_base='doc/evidence/storage-carving-reconcile-20261115/'
old_focused=parser_gate('prior-directory-focused-fixed',PARSER_PREVIOUS_EVIDENCE,prior_base+'directory-focused-fixed/',True)
old_strict=parser_gate('prior-directory-strict-analysis',PARSER_PREVIOUS_EVIDENCE,prior_base+'directory-strict-analysis/',True)
old_full=parser_gate('retained-prior-full-run',PARSER_PREVIOUS_EVIDENCE,prior_base+'directory-all-parser-final/',True)
fresh=parser_gate('fresh-changed-suite',PARSER_FRESH_EVIDENCE,fresh_base+'changed-suite/',False)
fresh_strict=parser_gate('fresh-changed-file-analysis',PARSER_FRESH_EVIDENCE,fresh_base+'strict-analysis/',False)
assert old_focused['tests']==9 and old_strict['analyzed_files']==18
assert old_full['tests']==4131 and old_full['suites']==144
assert fresh['tests']==18 and fresh['suites']==1 and fresh_strict['analyzed_files']==1
old_details=parser_details['retained-prior-full-run']
fresh_details=parser_details['fresh-changed-suite']
for label,details in parser_details.items():
    if label.startswith('fresh-'):
        assert details['normalized']==fresh_details['normalized']
    else:
        assert {n:v for n,v in details['normalized'].items() if n!=changed_test}=={
            n:v for n,v in fresh_details['normalized'].items() if n!=changed_test}
    assert all(equivalence['tool_sha256'][n]==value for n,value in details['meta']['before_tools'].items())
old_names=Counter(old_details['names'][changed_test])
fresh_names=Counter(fresh_details['names'][changed_test])
assert sum(old_names.values())==17 and sum(fresh_names.values())==18
assert not old_names-fresh_names and sum((fresh_names-old_names).values())==1
for name,comparison in equivalence['resolved_inputs'].items():
    assert comparison['identical']
    assert comparison['previous']==comparison['current']==old_details['normalized'][name]==fresh_details['normalized'][name]==fp(PARSER/name)
assert old_details['meta']['before_tools']==fresh_details['meta']['before_tools']
assert equivalence['retained_full_gate']['totals']['tests']==old_full['tests']
assert link['fresh_gates']['changed_suite']['tests']==fresh['tests']
assert link['fresh_gates']['strict_analysis']['files']==[changed_test]
report['historical_parser_reuse_proof']={
    'source_pin':PARSER_PIN,'fresh_evidence_head':PARSER_FRESH_EVIDENCE,
    'retained_evidence_head':PARSER_PREVIOUS_EVIDENCE,'tracked_paths_at_pin':len(current_tree),
    'sole_additive_test_delta':changed_test,'added_lines':29,'removed_lines':0,
    'added_case_names':list((fresh_names-old_names).elements()),
    'gates':parser_gates,'remote_link_artifacts_verified':len(remote_index),
    'link_report_sha256':sha((link_root/'canonical-parser-observed-pin-qualification.json').read_bytes()),
    'source_equivalence_sha256':sha((link_root/'source-equivalence.json').read_bytes()),
    'unchanged_production_dependencies_other_tests_and_tools_verified':True,
    'prior_17_case_names_retained_in_fresh_18_case_suite':True,
    'fresh_full_run_at_current_pin':False,
    'scope':'Retain the historical 4131-test/144-suite run through exact unchanged production/dependency/test/tool identity, and replace the changed 17-test suite with its fresh 18-test receipt. This is not a fresh full 4132-test run and is separate from the app host graph.',
}

# A later explicitly observed immutable receipt supplies a complete 4132-test run
# on the exact current parser pin. It is the primary parser acceptance result;
# the preceding historical proof stays separate and contributes no extra tests.
full_root=BASE/'integration-return-audit/parser-09a4'
full_link=read(full_root/'canonical-parser-full-qualification.json')
full_summary=read(full_root/'summary.json')
full_index=read(full_root/'artifacts-manifest.json')
bundle_index=read(full_root/'bundle-artifacts-sha256.json')
assert {p.name for p in full_root.iterdir() if p.is_file() and p.name!='bundle-artifacts-sha256.json'}==set(bundle_index)
files_match(full_root,bundle_index)
assert full_link['canonical_source_pin']==PARSER_PIN and full_link['qualification_commit']==PARSER_FULL_EVIDENCE
assert full_link['observed_through_app_commit']=='3e9560c9b4bd617b5346bacd8b5039493f0f2dc1'
full_base=full_link['remote_evidence_base'].rstrip('/')+'/'
for name in ['artifacts.tar.xz','artifacts-manifest.json','summary.json']:
    assert (full_root/name).read_bytes()==obj(PARSER,PARSER_FULL_EVIDENCE,full_base+name)
archive=(full_root/'artifacts.tar.xz').read_bytes()
assert len(archive)==full_link['remote_archive']['size']==full_summary['archive']['size']==206644
assert sha(archive)==full_link['remote_archive']['sha256']==full_summary['archive']['sha256']
archive_files={}
with tarfile.open(fileobj=io.BytesIO(archive),mode='r:xz') as stream:
    for member in stream.getmembers():
        member_path=Path(member.name)
        assert member.isfile() and not member_path.is_absolute() and '..' not in member_path.parts
        assert member.name not in archive_files
        archive_files[member.name]=stream.extractfile(member).read()
assert len(archive_files)==32 and set(archive_files)==set(full_index)
for name,data in archive_files.items():
    assert full_index[name]=={'sha256':sha(data),'size':len(data)}
inner_indexes=[]
for name,data in archive_files.items():
    if not name.endswith('/artifacts-sha256.json'):
        continue
    index=json.loads(data)
    prefix=str(Path(name).parent)+'/'
    actual={path[len(prefix):] for path in archive_files if path.startswith(prefix) and path!=name}
    assert actual==set(index)
    for relative,expected in index.items():
        raw=archive_files[prefix+relative]
        assert expected=={'sha256':sha(raw),'size':len(raw)}
    inner_indexes.append({'path':name,'entries':len(index)})
assert sum(item['entries'] for item in inner_indexes)==23
parser_full_tree=tree(PARSER,PARSER_PIN)
parser_full_source=tree(PARSER,PARSER_PIN,True)
assert len(parser_full_tree)==1832 and len(parser_full_source)==937
assert parser_full_source==tree(PARSER,PARSER_FULL_EVIDENCE,True)
full_metadata={}
full_snapshots={}
full_gates=[]
for label in ['full-parser','strict-analysis']:
    meta=json.loads(archive_files[label+'/metadata.json'])
    before=json.loads(gzip.decompress(archive_files[label+'/inputs-before.json.gz']))
    after=json.loads(gzip.decompress(archive_files[label+'/inputs-after.json.gz']))
    command=json.loads(archive_files[label+'/command.json'])
    assert meta['before_git']==meta['after_git']
    assert meta['before_git']['head']==PARSER_PIN
    assert meta['before_git']['tree']==git(PARSER,'rev-parse',PARSER_PIN+'^{tree}').decode().strip()
    assert meta['before_git']['status']=='' and not meta['before_git']['source_changes'] and not meta['before_git']['untracked_source']
    assert meta['before_tools']==meta['after_tools']
    assert meta['returncode']==0 and meta['qualification_success'] and meta['inputs_and_commit_stable']
    assert meta['input_changes']=={'added':[],'changed':[],'removed':[]}
    assert before['entries']==after['entries']
    assert before['count']==after['count']==meta['input_count']==len(before['entries'])==949
    digest=sha(canonical(before['entries']))
    assert digest==before['entries_sha256']==after['entries_sha256']==meta['before_entries_sha256']==meta['after_entries_sha256']
    assert command['argv']==meta['command'] and command['cwd']==meta['cwd']
    full_metadata[label]=meta
    full_snapshots[label]=before
    full_gates.append({'gate':label,'source_head':PARSER_PIN,'input_count':949,'input_digest':digest,
                       'source_commit_resolution_and_tools_stable':True,'returncode':0,
                       'source_selector':before['selector']})
assert full_snapshots['full-parser']['entries']==full_snapshots['strict-analysis']['entries']
full_entries=full_snapshots['full-parser']['entries']
resolution_paths={prefix+name for prefix in ('','packages/legacy_doc_parser/','packages/quds_office_engine/','packages/quds_office_editor/')
                  for name in ('pubspec.lock','.dart_tool/package_config.json','.dart_tool/package_graph.json')}
assert set(full_entries)==set(parser_full_source)|resolution_paths
for name in resolution_paths:
    if name.startswith('packages/'):
        assert full_entries[name]=={'kind':'missing_or_nonfile'}
# Batch immutable object reads bind all source snapshots without consulting the
# original workspace or changing the current parser checkout.
by_blob={}
for name,identity in parser_full_source.items():
    assert identity['kind']=='blob'
    by_blob.setdefault(identity['oid'],[]).append(name)
blob_ids=list(by_blob)
blob_data=subprocess.check_output(['git','-C',str(PARSER),'cat-file','--batch'],
    input=('\n'.join(blob_ids)+'\n').encode(),env=ENV)
offset=0
for oid in blob_ids:
    end=blob_data.index(b'\n',offset)
    header=blob_data[offset:end].decode().split()
    assert header[0]==oid and header[1]=='blob'
    size=int(header[2]);start=end+1;raw=blob_data[start:start+size]
    assert blob_data[start+size:start+size+1]==b'\n'
    offset=start+size+1
    for name in by_blob[oid]:
        assert full_entries[name]=={'kind':'file','size':len(raw),'sha256':sha(raw)}
assert offset==len(blob_data)
requested=archive_files['full-parser/suites.txt'].decode().splitlines()
assert requested==archive_files['all-suites.txt'].decode().splitlines()
assert len(requested)==len(set(requested))==144==full_metadata['full-parser']['suite_count']
assert set(requested)=={name for name in parser_full_source if name.startswith('test/') and name.endswith('_test.dart')}
assert [arg for arg in full_metadata['full-parser']['command'] if arg.endswith('.dart')]==requested
assert full_metadata['full-parser']['command'][1:4]==['test','--reporter=json','--concurrency=2']
full_machine=unique_machine_events(archive_files['full-parser/stdout.jsonl'],requested,Path(full_metadata['full-parser']['cwd']))
full_names=full_machine.pop('_visible_test_names_by_suite')
assert full_machine['tests']==4132 and full_machine['suites']==144 and full_machine['hidden_success_events']==144
saved_full=json.loads(archive_files['full-parser/summary.json'])
assert saved_full['qualification_success'] and saved_full['done_success']
assert saved_full['totals']=={'tests':4132,'passed':4132,'failed':0,'errors':0,'skipped':0,'other_results':0}
assert not saved_full['missing_suites'] and not saved_full['unexpected_suites'] and not saved_full['nonpassing_requested_suites']
assert len(saved_full['suites'])==144 and {row['path'] for row in saved_full['suites']}==set(requested)
for row in saved_full['suites']:
    assert row['result']=='passed' and row['passed']==len(full_names[row['path']])
analysis=archive_files['analysis-files.txt'].decode().splitlines()
assert len(analysis)==len(set(analysis))==18
assert full_metadata['strict-analysis']['command'][1:4]==['analyze','--fatal-infos','--fatal-warnings']
assert full_metadata['strict-analysis']['command'][4:]==analysis
assert set(analysis).issubset(parser_full_source)
assert b'No issues found!' in archive_files['strict-analysis/stdout.log'] and not archive_files['strict-analysis/stderr.log']
assert full_summary['source_commit']==PARSER_PIN and full_summary['runtime']['totals']==saved_full['totals']
assert full_link['verified_runtime']['tests']==4132 and full_link['verified_runtime']['suites']==144
assert full_link['verified_strict_analysis']['files']==18
full_tools={}
for meta in full_metadata.values():
    for name,expected in meta['before_tools'].items():
        assert full_tools.setdefault(name,expected)==expected
tool_checks=[]
for name,expected in full_tools.items():
    sdk_marker='/toolchains/flutter/bin/cache/dart-sdk/'
    if sdk_marker in name:
        relative=name.split(sdk_marker,1)[1]
        assert '..' not in Path(relative).parts
        local=W/'toolchains/flutter/bin/cache/dart-sdk'/relative
        assert sha(local.read_bytes())==expected
        tool_checks.append({'recorded_path':name,'sha256':expected,'verification':'current SDK bytes','current_path':str(local)})
    elif name.endswith('/record_gate.py'):
        assert sha(archive_files['record_gate.py'])==expected
        tool_checks.append({'recorded_path':name,'sha256':expected,'verification':'retained archive bytes','member':'record_gate.py'})
    elif name.endswith('/run_delta_qualification.py'):
        relative='doc/evidence/storage-carving-reconcile-20261115/run_delta_qualification.py'
        assert sha(obj(PARSER,PARSER_PIN,relative))==expected
        tool_checks.append({'recorded_path':name,'sha256':expected,'verification':'immutable pinned Git bytes','path':relative})
    elif name.endswith('/toolchains/env.sh'):
        # The foreign environment script was hashed before/after but its bytes
        # were not retained. Do not imply independent byte verification of it.
        tool_checks.append({'recorded_path':name,'sha256':expected,'verification':'stable recorded hash only; environment script bytes not retained'})
    else:
        raise AssertionError('Unexpected parser receipt tool without an explicit identity mapping: '+name)
assert len(tool_checks)==9 and sum(item['verification']=='current SDK bytes' for item in tool_checks)==6
resolution={}
for name,archive_name in [('pubspec.lock','pubspec.lock.gz'),('.dart_tool/package_config.json','dart_tool-package_config.json.gz'),('.dart_tool/package_graph.json','dart_tool-package_graph.json.gz')]:
    raw=gzip.decompress(archive_files['dependency-setup/after/'+archive_name])
    assert full_entries[name]=={'kind':'file','size':len(raw),'sha256':sha(raw)}
    local=(PARSER/name).read_bytes()
    resolution[name]={'recorded_sha256':sha(raw),'current_sha256':sha(local),'byte_equal_to_current':raw==local}
assert resolution['pubspec.lock']['byte_equal_to_current']
assert gzip.decompress(archive_files['dependency-setup/before/pubspec.lock.gz'])==gzip.decompress(archive_files['dependency-setup/after/pubspec.lock.gz'])
assert gzip.decompress(archive_files['dependency-setup/before/pubspec.yaml.gz'])==gzip.decompress(archive_files['dependency-setup/after/pubspec.yaml.gz'])==obj(PARSER,PARSER_PIN,'pubspec.yaml')
def normalize_graph(value):
    if isinstance(value,dict):
        return {key:normalize_graph(item) for key,item in sorted(value.items())}
    if isinstance(value,list):
        return sorted([normalize_graph(item) for item in value],key=lambda item:json.dumps(item,sort_keys=True))
    return value
recorded_graph=json.loads(gzip.decompress(archive_files['dependency-setup/after/dart_tool-package_graph.json.gz']))
assert normalize_graph(recorded_graph)==normalize_graph(read(PARSER/'.dart_tool/package_graph.json'))
assert sha((full_root/'independent-verification.json').read_bytes())==full_link['independent_audit']['sha256']
report['canonical_parser']={'source_pin':PARSER_PIN,'complete_evidence_head':PARSER_FULL_EVIDENCE,
    'source_tree':git(PARSER,'rev-parse',PARSER_PIN+'^{tree}').decode().strip(),
    'runtime':full_machine,'strict_analysis_files':18,'fatal_infos_and_warnings':True,
    'fresh_complete_run_at_current_pin':True,'gates':full_gates,
    'archive_sha256':sha(archive),'archive_members_verified':32,'inner_indexes':inner_indexes,
    'tracked_non_evidence_source_files_verified':937,'excluded_historical_evidence_paths':895,
    'recorded_input_count':949,'recorded_input_digest':full_snapshots['full-parser']['entries_sha256'],
    'tool_identity_checks':tool_checks,'resolution':resolution,'normalized_package_graph_equal':True,
    'linkage_sha256':sha((full_root/'canonical-parser-full-qualification.json').read_bytes()),
    'previous_overlapping_results_added_to_total':False,
    'scope':'Complete native standalone parser run on exact08296ed, independently checked from retained raw receipts. Original workspace graphs remain source-bound; only lock bytes and normalized package graph/SDK identities are compared across workspaces. The environment script has a stable recorded hash but no retained bytes. Historical4131 and changed-suite18 results remain separate; host app graph qualification is independent.'}

# Bind this finite observed intake, its three restored tests and the frozen source.
checkpoint_path=BASE/config['checkpoint_file']
checkpoint=read(checkpoint_path)
integration=read(BASE/'source-integration.json')
assert checkpoint['production_source']==SOURCE_HEAD
assert checkpoint['source_tree']==git(APP,'rev-parse',SOURCE_HEAD+'^{tree}').decode().strip()
assert checkpoint['canonical_pins']==pins and checkpoint['source_resolution_sha256']==DIGEST
assert checkpoint['input_count']==config['input_count']
assert integration['intended_office_pin']==RESTORED_QUDS_PIN and integration['intended_parser_pin']==PARSER_PIN
assert integration['managed_files']==2334  # Historical source966 integration receipt.
observed=integration['observed_app_source']
assert observed=='41885d7d1d67348f5abe3579b99d9d2951fc909f'
for ancestor in [observed,integration['parent_checkpoint'],'20ee83ff965d5433aeb528ae84debdb304edcf4a']:
    assert subprocess.run(['git','-C',str(APP),'merge-base','--is-ancestor',ancestor,SOURCE_HEAD],env=ENV).returncode==0
intake=read(BASE/'incoming/remote-41885-delta-audit.json')
assert intake['app_commit']==observed
assert intake['app_tree']==git(APP,'rev-parse',observed+'^{tree}').decode().strip()
restored=read(BASE/'incoming/ods-regressions-restored.stdout.json')
assert restored['applied'] and restored['to']==RESTORED_QUDS_PIN and restored['delete']==[]
assert restored['write']==['packages/quds_office_engine/test/ods_sheet_reader_test.dart']
restored_paths=git(QUDS,'diff','--name-only',restored['from'],RESTORED_QUDS_PIN).decode().splitlines()
assert restored_paths==restored['write']
restore_numstat=git(QUDS,'diff','--numstat',restored['from'],RESTORED_QUDS_PIN).decode().strip().split('\t')
assert restore_numstat==['93','0',restored_paths[0]]
required_ancestry=[]
for name,repository,final_pin in [('quds',QUDS,QUDS_PIN),('parser',PARSER,PARSER_PIN)]:
    for ancestor in config.get('required_canonical_ancestors',{}).get(name,[]):
        assert re.fullmatch(r'[0-9a-f]{40}',ancestor)
        assert subprocess.run(['git','-C',str(repository),'merge-base','--is-ancestor',ancestor,final_pin],env=ENV).returncode==0
        required_ancestry.append({'repository':name,'ancestor':ancestor,'final_pin':final_pin})
for ancestor in config.get('required_app_ancestors',[]):
    assert re.fullmatch(r'[0-9a-f]{40}',ancestor)
    assert subprocess.run(['git','-C',str(APP),'merge-base','--is-ancestor',ancestor,SOURCE_HEAD],env=ENV).returncode==0
    required_ancestry.append({'repository':'app','ancestor':ancestor,'final_pin':SOURCE_HEAD})
additional_intake=[]
for relative in config['additional_intake_reports']:
    path=(BASE/relative).resolve()
    assert path.is_relative_to(BASE) and path.is_file()
    raw=path.read_bytes()
    assert obj(APP,REVIEW_HEAD,str(path.relative_to(APP)))==raw
    additional_intake.append({'path':relative,'sha256':sha(raw),'size':len(raw)})
resolution_path=BASE/config.get('resolution_file','resolution/receipt.json')
resolution=read(resolution_path)
assert resolution['success'] and resolution['declarations_and_committed_locks_unchanged']
assert resolution['before']==resolution['after']
for name,expected in resolution['after'].items():
    assert sha((APP/name).read_bytes())==expected
assert len(resolution['commands'])==4 and all(command['returncode']==0 for command in resolution['commands'])
for name,prefix in [('app',''),('cli','cli/'),('engine','packages/quds_office_engine/'),('editor','packages/quds_office_editor/')]:
    graph=read(APP/(prefix+'.dart_tool/package_graph.json'))
    versions=[p['version'] for p in graph['packages'] if p['name']=='archive']
    assert versions==resolution['archive_graph_versions'][name]
report['observed_incoming_and_source_freeze']={
    'observed_app_commit':observed,'restored_quds_test_pin':RESTORED_QUDS_PIN,'final_quds_pin':QUDS_PIN,
    'source_checkpoint_sha256':sha(checkpoint_path.read_bytes()),
    'source_integration_sha256':sha((BASE/'source-integration.json').read_bytes()),
    'intake_report_sha256':sha((BASE/'incoming/remote-41885-delta-audit.json').read_bytes()),
    'restored_ods_test_lines':93,'deleted_lines':0,'archive_graph_versions':resolution['archive_graph_versions'],
    'required_ancestry_rechecked':required_ancestry,'additional_intake_reports_bound_to_review_head':additional_intake,
    'scope':'Finite observed41885 intake, retained three-case canonical restoration and explicitly selected later intake reports. No new remote observation; prior source20ee and966 evidence remain historical.',
}

assert git(APP,'rev-parse','HEAD').decode().strip()==REVIEW_HEAD
assert not git(APP,'status','--porcelain=v1','--untracked-files=all')
assert git(PARSER,'rev-parse','HEAD').decode().strip()==PARSER_PIN
final_inputs=json.loads(gzip.decompress((gate_path('analysis-app','inputs-before.json.gz')).read_bytes()))['entries']
assert all(fp(APP/name)==expected for name,expected in final_inputs.items()), 'Source/resolution changed during cross-binding audit.'
current_tools={}
for label in LABELS:
    for name,expected in read(BASE/label/'metadata.json')['before_tools'].items():
        assert current_tools.setdefault(name,expected)==expected
for name,expected in current_tools.items():
    assert sha(Path(name).read_bytes())==expected, 'Recorded tool changed during cross-binding audit: '+name
report['final_source_resolution_and_tool_recheck']={'entries':len(final_inputs),'unique_recorded_tool_inputs':len(current_tools),'passed':True}
report['success']=True
report['runtime_tests_rerun']=0
report['repository_writes']=0
report['ci_polls_or_waits']=0
(OUT/'cross-bindings.json').write_bytes(canonical(report))
print(json.dumps({'success':True,'output':str(OUT/'cross-bindings.json'),
                  'sha256':sha((OUT/'cross-bindings.json').read_bytes()),
                  'canonical_parser_full_tests':4132,'canonical_parser_full_suites':144,'managed_files':MANAGED_TOTAL,
                  'oracle_outputs':12,'comments_oracle_outputs':9,'navigation_workbooks':6},indent=2))

#!/usr/bin/env python3
"""Final frozen-source validation; historical replacement-worker receipts stay unchanged."""
import argparse,datetime,gzip,hashlib,json,os,re,subprocess,time
from pathlib import Path
TC=Path(__file__).resolve().parent
REPO=TC.parent/'CrispCloud'
BASE=TC/'evidence/final-acceptance'
FROZEN='fdc262e112aa29dd1e60a76cff9a2dfb5f2d7b4f'
STARTING='74fbdd5a9a17399237b54512877dc6700c0d76b2'
STEMS=['terminal_workspace_recovery','terminal_workspace_recovery_dialog','terminal_workspace_recovery_widget','terminal_panel_recovery_idle','terminal_arrangements','terminal_arrangements_dialog','terminal_arrangements_widget','terminal_tabs','terminal_pane_layout','terminal_session','terminal_panel','terminal_widget','terminal_user_input','terminal_broadcast','terminal_broadcast_dialog','terminal_key_bindings','terminal_key_bindings_widget','terminal_triggers','terminal_triggers_widget','terminal_trigger_session','terminal_shell_integration','terminal_shell_directory_labels','terminal_search','terminal_search_bar','terminal_input_budget','terminal_connection_sharing','ssh_connection_sharing_widget','ssh_tmux_panel_lifecycle','tmux_control_workspace','ssh_native_tmux_persistence','ssh_terminal_reconnect','terminal_mount_localization','tmux_control_client','screen_session_command']
TERMINAL=[f'test/{stem}_test.dart' for stem in STEMS]
ODS=['build/final-incoming-tests/ods_sheet_reader_test.dart','build/final-incoming-tests/sheet_formula_test.dart','test/widget/ods_editor_workflow_test.dart']
ZOTERO=['build/final-incoming-tests/'+name+'_test.dart' for name in ['zotero_client','zotero_identity_client','zotero_metadata_batch','word_zotero_scaling','word_zotero_citing']]+['packages/quds_office_editor/test/word_zotero_dialog_test.dart']
VISUAL=['test/terminal_workspace_recovery_visual_test.dart']
SUITES=[*TERMINAL,*ODS,*ZOTERO,*VISUAL]
assert len(SUITES)==44
FIXTURES=['packages/quds_office_engine/test/fixtures/fidelity/legacy-sheet.ods','packages/quds_office_engine/test/fixtures/fidelity/legacy-sheet-edge.ods','packages/quds_office_engine/test/fixtures/zotero/citing/processor-output.json']
EXTRA=['.dart_tool/package_config.json','.dart_tool/package_graph.json',*ODS,*ZOTERO,*FIXTURES,'tool/office_fidelity_manifest.json']
SUBTREES={'lib':'8efc7ea40f30399c9a65ea1e9c82056b413d3c94','test':'f57fa42a3c99acee60afb1a7007f7cba827edf72','packages':'cd2bbbd7d574f7c3f16184c75206ff6ea47a55fe','tool':'f8879d4ede3e4417c19d3f56df515dc69d5195ef'}

def git(*args):
 return subprocess.check_output(['git',*args],cwd=REPO).decode().strip()
def stamp():
 return datetime.datetime.now(datetime.timezone.utc).isoformat()
def identity(p):
 raw=p.read_bytes()
 return {'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'mode':oct(p.stat().st_mode&0o777)}
def snapshot():
 paths=subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=REPO).decode().split('\0')
 ext={'.dart','.rs','.c','.cpp','.h','.yaml','.lock','.toml'}
 chosen={p for p in paths if (p.startswith(('lib/','test/','packages/')) and Path(p).suffix in ext) or (p.startswith('tool/') and Path(p).suffix in {'.dart','.py'}) or p in {'.fvmrc','pubspec.yaml','pubspec.lock','analysis_options.yaml'}}
 chosen.update(EXTRA)
 absent=[p for p in EXTRA if not (REPO/p).is_file()]
 assert not absent,absent
 return {p:identity(REPO/p) for p in sorted(chosen) if (REPO/p).is_file()}
def save(path,value):
 with path.open('wb') as out:
  with gzip.GzipFile(filename='',mode='wb',fileobj=out,mtime=0) as z:
   z.write(json.dumps(value,sort_keys=True,indent=2).encode())
def frozen_proof(sources):
 entries={}
 for item in subprocess.check_output(['git','ls-tree','-r','-z',FROZEN],cwd=REPO).decode().split('\0'):
  if not item:continue
  meta,path=item.split('\t',1);mode,kind,oid=meta.split(' ')
  if kind=='blob':entries[path]=(mode,oid)
 mismatch=[]
 for path in sources:
  if path not in entries:continue
  raw=(REPO/path).read_bytes();oid=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
  mode='100755' if ((REPO/path).stat().st_mode&0o111) else '100644'
  if (mode,oid)!=entries[path]:mismatch.append(path)
 return {'accepted_commit':FROZEN,'tracked_inputs_checked':sum(p in entries for p in sources),'mismatches':mismatch,'reviewed_subtrees':{p:{'expected':oid,'actual':git('rev-parse',FROZEN+':'+p)} for p,oid in SUBTREES.items()}}
def targets():
 t=json.loads((BASE/'static-targets.json').read_text())
 assert t['original_target_count']==175
 return t
def main():
 parser=argparse.ArgumentParser();parser.add_argument('phase',choices=['analysis','format','vendor','web','combined']);args=parser.parse_args()
 evidence=BASE/args.phase;evidence.mkdir(exist_ok=False)
 before=snapshot();save(evidence/'sources-before.json.gz',before)
 proof=frozen_proof(before);assert not proof['mismatches'],proof
 assert all(v['expected']==v['actual'] for v in proof['reviewed_subtrees'].values())
 environment=os.environ.copy()
 for key in ['FLUTTER_NATIVE_ASSETS','FLUTTER_DART_DATA_ASSETS']:environment.pop(key,None)
 overrides={}
 command=[str(TC/'run')]
 commands=None
 if args.phase=='analysis':command+=['dart','analyze',*targets()['analysis_targets']]
 elif args.phase=='format':command+=['dart','format','--output=none','--set-exit-if-changed',*targets()['format_targets']]
 elif args.phase=='vendor':
  commands=[['python3','tool/verify_office_fidelity.py','--require-tracked'],['python3','tool/verify_dartssh2_vendor.py']]
  command=commands[0]
 elif args.phase=='web':command+=['python3',str(TC/'web-resource-runner.py'),'--run','--repo',str(REPO),'--toolchain',str(TC),'--evidence',str(evidence)]
 else:
  command+=['flutter','test','--no-pub','--concurrency=1','--reporter=expanded','--dart-define=TERMINAL_RECOVERY_VISUALS=true',*SUITES]
  overrides={'FLUTTER_NATIVE_ASSETS':'false','FLUTTER_DART_DATA_ASSETS':'true'};environment.update(overrides)
 record={'phase':args.phase,'source_head':git('rev-parse','HEAD'),'accepted_source':FROZEN,'started_utc':stamp(),'command':command,'environment_overrides':overrides,'isolated_feature_environment':{key:environment.get(key) for key in ['FLUTTER_NATIVE_ASSETS','FLUTTER_DART_DATA_ASSETS']},'watched_files':len(before),'frozen_commit_proof':proof,'github_actions_queried_or_awaited':False,'runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'toolchain_wrapper':identity(TC/'run')}
 if commands:record['commands']=commands
 (evidence/'started.json').write_text(json.dumps(record,indent=2)+'\n')
 start=time.monotonic();exitcode=0
 with (evidence/'run.log').open('w') as log:
  for cmd in commands or [command]:
   try:result=subprocess.run(cmd,cwd=REPO,env=environment,stdout=log,stderr=subprocess.STDOUT)
   except KeyboardInterrupt:result=subprocess.CompletedProcess(cmd,130)
   if commands:record.setdefault('individual_exit_codes',[]).append({'command':cmd,'exit_code':result.returncode})
   if result.returncode:exitcode=result.returncode
 after=snapshot();save(evidence/'sources-after.json.gz',after)
 record.update(finished_utc=stamp(),seconds=time.monotonic()-start,exit_code=exitcode,head_at_end=git('rev-parse','HEAD'),source_changes=[p for p in sorted(before.keys()|after.keys()) if before.get(p)!=after.get(p)],log_sha256=hashlib.sha256((evidence/'run.log').read_bytes()).hexdigest())
 record['source_inventory_artifacts']={name:identity(evidence/name) for name in ['sources-before.json.gz','sources-after.json.gz']}
 text=(evidence/'run.log').read_text()
 if args.phase in {'analysis','format'}:
  record.update(file_count=175,qualification='Pinned Dart CLI static verification with the exact production graph and no feature overrides. Analysis uses three declared immutable host adapters; formatting reads all 175 original source files without writes.',analysis_adapter_mappings=targets()['analysis_adapter_mappings'])
 if args.phase=='analysis':
  diagnostics=[line.strip() for line in text.splitlines() if re.match(r'^\s*(error|warning|info)\s+-',line)]
  record['diagnostics']={'errors':sum(s.startswith('error') for s in diagnostics),'warnings':sum(s.startswith('warning') for s in diagnostics),'infos':sum(s.startswith('info') for s in diagnostics),'lines':diagnostics}
  record['pre_existing_diagnostic_files']={}
  for p in ['test/ssh_shared_channel_cleanup_test.dart','test/terminal_mount_localization_test.dart']:
   old=git('rev-parse',STARTING+':'+p);new=git('rev-parse',FROZEN+':'+p)
   record['pre_existing_diagnostic_files'][p]={'starting_commit':STARTING,'starting_blob':old,'accepted_blob':new,'identical':old==new}
 if args.phase=='vendor':
  record.update(qualification='Read-only local provenance checks of the tracked Office fidelity manifest and dartssh2 upstream files/patches.')
 if args.phase=='web':
  resource=json.loads((evidence/'web-resource-run.json').read_text()) if (evidence/'web-resource-run.json').exists() else {}
  web=json.loads((evidence/'web.json').read_text()) if (evidence/'web.json').exists() else {}
  record.update(qualification='Normal complete application release web build, standard O4/minification and normal web hooks; no browser/native-platform runtime qualification.',sdk_restored_exactly=resource.get('sdk_restored_exactly',False),main_dart_js=web.get('main_dart_js'),compiler_heap_mb=4096)
 if args.phase=='combined':
  lines=text.splitlines()
  final=next((line for line in reversed(lines) if 'All tests passed!' in line or 'Some tests failed.' in line),'')
  pat=re.compile(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?:')
  def counts(line):
   m=pat.search(line);assert m,line
   return dict(zip(['passed','skipped','failed'],(int(v or 0) for v in m.groups())))
  record.update(qualification='Isolated Dart/widget validation with unmodified production graph and supported per-command feature configuration. Native CodeAssets intentionally omitted, DataAssets enabled; not full native/application acceptance.',test_files=SUITES,test_file_count=44,final_test_line=final)
  if final:
   try:
    record['counts']=counts(final)
    def before_suite(name):
     return counts(next(line for line in lines if 'loading '+str(REPO/name) in line))
    initial=before_suite(TERMINAL[0]);related=before_suite(TERMINAL[4]);ods=before_suite(ODS[0]);zotero=before_suite(ZOTERO[0]);visual=before_suite(VISUAL[0]);total=record['counts']
    def delta(end,start):return {key:end[key]-start[key] for key in end}
    record['cohorts']={'new_recovery_idle':{'files':TERMINAL[:4],'counts':delta(related,initial)},'related_terminal':{'files':TERMINAL[4:],'counts':delta(ods,related)},'incoming_ods':{'files':ODS,'counts':delta(zotero,ods)},'incoming_zotero':{'files':ZOTERO,'counts':delta(visual,zotero)},'final_visual':{'files':VISUAL,'counts':delta(total,visual)}}
    (evidence/'cohort-summary.json').write_text(json.dumps({'counts':record['counts'],'file_count':44,'cohorts':record['cohorts']},indent=2)+'\n')
   except Exception as e:record['counter_parse_error']=repr(e)
  prep=json.loads((BASE/'incoming-office/preparation.json').read_text())
  record['changed_office_protected_inputs']=[n for n,item in prep['protected_inputs_before'].items() if identity(REPO/n)!=item]
  record['changed_office_adapters']=[a['adapted_path'] for a in prep['adapters'] if identity(REPO/a['adapted_path'])!=a['adapted']]
  visuals=REPO/'build/recovery-visuals'
  record['visual_artifacts']={p.name:identity(p) for p in sorted(visuals.glob('*.png'))}
 record['accepted']=exitcode==0 and not record['source_changes']
 if args.phase=='web':record['accepted']=record['accepted'] and record['sdk_restored_exactly'] and bool(record['main_dart_js'])
 if args.phase=='combined':record['accepted']=record['accepted'] and not record['changed_office_protected_inputs'] and not record['changed_office_adapters'] and not record.get('counter_parse_error') and 'All tests passed!' in record['final_test_line']
 (evidence/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
 print(json.dumps({k:v for k,v in record.items() if k not in {'command','test_files','cohorts'}},indent=2),flush=True)
 return 0 if record['accepted'] else 1
if __name__=='__main__':raise SystemExit(main())

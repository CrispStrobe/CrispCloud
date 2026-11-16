#!/usr/bin/env python3
import argparse,datetime,gzip,hashlib,json,os,re,subprocess,time
from pathlib import Path
TC=Path(__file__).resolve().parent
REPO=TC.parent/'CrispCloud'
BASE=TC/'evidence/recovered-acceptance'
FROZEN='3cd501798794dcb74de5dca912b498a4c0a7e39b'
MAIN='5d3a020d4d3c5e1a89c0209378df0fce3f78efe3'
STEMS=['terminal_workspace_recovery','terminal_workspace_recovery_dialog','terminal_workspace_recovery_widget','terminal_panel_recovery_idle','terminal_arrangements','terminal_arrangements_dialog','terminal_arrangements_widget','terminal_tabs','terminal_pane_layout','terminal_session','terminal_panel','terminal_widget','terminal_user_input','terminal_broadcast','terminal_broadcast_dialog','terminal_key_bindings','terminal_key_bindings_widget','terminal_triggers','terminal_triggers_widget','terminal_trigger_session','terminal_shell_integration','terminal_shell_directory_labels','terminal_search','terminal_search_bar','terminal_input_budget','terminal_connection_sharing','ssh_connection_sharing_widget','ssh_tmux_panel_lifecycle','tmux_control_workspace','ssh_native_tmux_persistence','ssh_terminal_reconnect','terminal_mount_localization']
TERMINAL=[f'test/{stem}_test.dart' for stem in STEMS]
OFFICE=['build/office-incoming-tests/ods_sheet_reader_test.dart','build/office-incoming-tests/sheet_formula_test.dart','test/widget/ods_editor_workflow_test.dart']
VISUAL=['test/terminal_workspace_recovery_visual_test.dart']
EXTRA=['.dart_tool/package_config.json','.dart_tool/package_graph.json',*OFFICE,'packages/quds_office_engine/test/fixtures/fidelity/legacy-sheet.ods','packages/quds_office_engine/test/fixtures/fidelity/legacy-sheet-edge.ods','tool/office_fidelity_manifest.json']
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
 return {'accepted_commit':FROZEN,'tracked_inputs_checked':sum(p in entries for p in sources),'mismatches':mismatch}
def static_files():
 baseline=json.loads((REPO/'docs/validation/terminal-parity-continuation/analysis.json').read_text())
 files={p for p in baseline['command'] if p.endswith('.dart')}
 files.update(p for p in git('diff','--name-only',MAIN,FROZEN).splitlines() if p.startswith(('lib/','test/')) and p.endswith('.dart'))
 files.update(['packages/crisp_storage/lib/src/host_keys.dart','tool/terminal_recovery_web_test.dart'])
 assert len(files)==164,len(files)
 return sorted(files)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('phase',choices=['analysis','format','web','combined']);args=parser.parse_args()
 evidence=BASE/args.phase;evidence.mkdir(exist_ok=False)
 before=snapshot();save(evidence/'sources-before.json.gz',before)
 proof=frozen_proof(before);assert not proof['mismatches'],proof
 environment=os.environ.copy()
 for key in ['FLUTTER_NATIVE_ASSETS','FLUTTER_DART_DATA_ASSETS']:environment.pop(key,None)
 overrides={}
 command=[str(TC/'run')]
 if args.phase=='analysis':command+=['dart','analyze',*static_files()]
 elif args.phase=='format':command+=['dart','format','--output=none','--set-exit-if-changed',*static_files()]
 elif args.phase=='web':command+=['python3',str(TC/'web-resource-runner.py'),'--run','--repo',str(REPO),'--toolchain',str(TC),'--evidence',str(evidence)]
 else:
  command+=['flutter','test','--no-pub','--concurrency=1','--reporter=expanded','--dart-define=TERMINAL_RECOVERY_VISUALS=true',*TERMINAL,*OFFICE,*VISUAL]
  overrides={'FLUTTER_NATIVE_ASSETS':'false','FLUTTER_DART_DATA_ASSETS':'true'};environment.update(overrides)
 record={'phase':args.phase,'source_head':git('rev-parse','HEAD'),'accepted_source':FROZEN,'started_utc':stamp(),'command':command,'environment_overrides':overrides,'watched_files':len(before),'frozen_commit_proof':proof,'github_actions_queried_or_awaited':False,'runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
 (evidence/'started.json').write_text(json.dumps(record,indent=2)+'\n')
 start=time.monotonic()
 with (evidence/'run.log').open('w') as log:
  try:result=subprocess.run(command,cwd=REPO,env=environment,stdout=log,stderr=subprocess.STDOUT)
  except KeyboardInterrupt:result=subprocess.CompletedProcess(command,130)
 after=snapshot();save(evidence/'sources-after.json.gz',after)
 record.update(finished_utc=stamp(),seconds=time.monotonic()-start,exit_code=result.returncode,head_at_end=git('rev-parse','HEAD'),source_changes=[p for p in sorted(before.keys()|after.keys()) if before.get(p)!=after.get(p)],log_sha256=hashlib.sha256((evidence/'run.log').read_bytes()).hexdigest())
 record['source_inventory_artifacts']={name:identity(evidence/name) for name in ['sources-before.json.gz','sources-after.json.gz']}
 if args.phase in {'analysis','format'}:
  record.update(file_count=164,qualification='Normal pinned Dart CLI static verification, exact production package graph, no feature overrides.')
 if args.phase=='web':
  resource=json.loads((evidence/'web-resource-run.json').read_text()) if (evidence/'web-resource-run.json').exists() else {}
  web=json.loads((evidence/'web.json').read_text()) if (evidence/'web.json').exists() else {}
  record.update(qualification='Normal complete application release web build, standard O4/minification and normal web hooks; no browser/native-platform runtime qualification.',sdk_restored_exactly=resource.get('sdk_restored_exactly',False),main_dart_js=web.get('main_dart_js'),compiler_heap_mb=4096)
 if args.phase=='combined':
  lines=(evidence/'run.log').read_text().splitlines()
  final=next((line for line in reversed(lines) if 'All tests passed!' in line or 'Some tests failed.' in line),'')
  pat=re.compile(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?:')
  def counts(line):
   m=pat.search(line);assert m,line
   return dict(zip(['passed','skipped','failed'],(int(v or 0) for v in m.groups())))
  record.update(qualification='Isolated Dart/widget validation with unmodified production graph and supported per-command feature configuration. Native CodeAssets intentionally omitted; not full native/application acceptance.',test_files=[*TERMINAL,*OFFICE,*VISUAL],final_test_line=final)
  if final:
   record['counts']=counts(final)
   def before_suite(name):
    return counts(next(line for line in lines if 'loading '+str(REPO/name) in line))
   start_counts=before_suite(TERMINAL[0]);related=before_suite(TERMINAL[4]);office=before_suite(OFFICE[0]);visual=before_suite(VISUAL[0]);total=record['counts']
   def delta(end,start):return {key:end[key]-start[key] for key in end}
   record['cohorts']={'new_recovery_idle':{'files':TERMINAL[:4],'counts':delta(related,start_counts)},'related_terminal':{'files':TERMINAL[4:],'counts':delta(office,related)},'incoming_office':{'files':OFFICE,'counts':delta(visual,office)},'final_visual':{'files':VISUAL,'counts':delta(total,visual)}}
  office_prep=json.loads((BASE/'incoming-office/preparation.json').read_text())
  record['changed_office_protected_inputs']=[n for n,item in office_prep['protected_inputs_before'].items() if identity(REPO/n)!=item]
  record['changed_office_adapters']=[a['adapted_path'] for a in office_prep['adapters'] if identity(REPO/a['adapted_path'])!=a['adapted']]
 record['accepted']=result.returncode==0 and not record['source_changes']
 if args.phase=='web':record['accepted']=record['accepted'] and record['sdk_restored_exactly'] and bool(record['main_dart_js'])
 if args.phase=='combined':record['accepted']=record['accepted'] and not record['changed_office_protected_inputs'] and not record['changed_office_adapters'] and 'All tests passed!' in record['final_test_line']
 (evidence/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
 print(json.dumps({k:v for k,v in record.items() if k not in {'command','test_files','cohorts'}},indent=2),flush=True)
 return 0 if record['accepted'] else 1
if __name__=='__main__':raise SystemExit(main())

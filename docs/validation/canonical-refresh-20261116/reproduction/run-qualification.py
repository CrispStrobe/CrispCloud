from pathlib import Path
import subprocess,json,hashlib,importlib.util,datetime,time,re
root=Path.cwd();e=root/'docs/validation/canonical-refresh-20261116';flutter='/tmp/crispcloud-flutter-20261116';dart='/Users/christianstrobele/flutter-3.47.8/bin/cache/dart-sdk/bin/dart'
spec=importlib.util.spec_from_file_location('qualification',root/'tool/run_terminal_validation.py');q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip();records=[]
engine=root/'packages/quds_office_engine';sheet_files=sorted(str(p.relative_to(engine)) for p in (engine/'test').glob('sheet_*_test.dart'))+['test/legacy_sheet_reader_test.dart','test/ods_sheet_reader_test.dart','test/sml_styles_date_test.dart']
commands=[('unit',root,['python3','tool/run_terminal_validation.py','native','--flutter',flutter,'--dart',dart,'--evidence',str(e/'unit')]),('ssh-live',root,['python3','tool/run_terminal_live_smoke.py','--flutter',flutter,'--with-pty','--with-unix-agent']),('tmux-live',root,['python3','tool/run_tmux_control_live_smoke.py','--flutter',flutter,'--tmux','/opt/homebrew/bin/tmux','--evidence',str(e/'live-tmux')]),('ods-host',root,[flutter,'test','--no-pub','--concurrency=2','--reporter=expanded','test/office_document_service_test.dart','test/widget/ods_viewer_grid_test.dart','test/widget/ods_viewer_workflow_test.dart','test/widget/ods_editor_workflow_test.dart','test/widget/office_editor_dialog_test.dart','test/local_odf_corpus_test.dart']),('ods-engine',engine,[dart,'test','--concurrency=2','--reporter=expanded',*sheet_files]),('ods-local',engine,[dart,'test','test/local_spreadsheet_corpus_test.dart','--name','local ODS corpus','--reporter=expanded'])]
commands=[v for v in commands if v[0]!='ods-engine']
for name,cwd,command in commands:
 if name=='ods-host':command += ['test/office_zotero_citing_transport_test.dart','test/office_zotero_test.dart','test/office_zotero_ribbon_test.dart','packages/madedit2_hex/test','packages/quds_office_editor/test/word_zotero_dialog_test.dart','packages/quds_office_editor/test/word_zotero_collection_pagination_test.dart']
 before=q.source_hashes();start=time.monotonic();stamp=datetime.datetime.now(datetime.timezone.utc).isoformat();log=e/(name+'-runner.log' if name=='unit' else name+'.log')
 with log.open('w') as out:result=subprocess.run(command,cwd=cwd,stdout=out,stderr=subprocess.STDOUT)
 after=q.source_hashes();changed=[p for p in sorted(before.keys()|after.keys()) if before.get(p)!=after.get(p)]
 v={'phase':name,'head':head,'command':command,'cwd':str(cwd),'started_utc':stamp,'seconds':round(time.monotonic()-start,3),'exit_code':result.returncode,'changed_sources':changed,'log':str(log.relative_to(e)),'source_sha256':hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest()}
 content=log.read_text()
 if name=='tmux-live':content=(e/'live-tmux/live-tmux.log').read_text()
 if name=='unit':content=(e/'unit/native.log').read_text()
 final=next((line for line in reversed(content.splitlines()) if 'All tests passed!' in line or 'Some tests failed.' in line),'');v['final_line']=final;m=re.search(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?:',final)
 if m:v['counts']=dict(zip(['passed','skipped','failed'],(int(x or 0) for x in m.groups())))
 records.append(v);(e/'final-integrated-execution.json').write_text(json.dumps(records,indent=2)+'\n');print(name,result.returncode,v.get('counts'),flush=True)
 if result.returncode or changed:raise SystemExit(result.returncode or 1)

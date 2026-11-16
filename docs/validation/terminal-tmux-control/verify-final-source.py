from pathlib import Path
import datetime,gzip,hashlib,importlib.util,json,subprocess
root=Path(__file__).resolve().parents[3]
out=root/'docs/validation/terminal-tmux-control'
accepted='60bc3a4155c3c1e1b7107cc087647ac79938b0d6'
def sha(data):return hashlib.sha256(data).hexdigest()
def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
spec=importlib.util.spec_from_file_location('validation',root/'tool/run_terminal_validation.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
base=json.loads(gzip.decompress((out/'native-source-sha256.json.gz').read_bytes()))
phases={}
for phase in ['native','analysis','format','live','web']:
 record=json.loads((out/f'{phase}.json').read_text())
 assert record['exit_code']==0 and record['changed_sources']==[],phase
 p=out/f'{phase}-source-sha256.json'
 if p.exists():
  raw=p.read_bytes();p.with_suffix('.json.gz').write_bytes(gzip.compress(raw,mtime=0));p.unlink()
 else:raw=gzip.decompress(p.with_suffix('.json.gz').read_bytes())
 assert json.loads(raw)==base,phase
 log=out/f'{phase}.log'
 log_bytes=log.read_bytes() if log.exists() else gzip.decompress(log.with_suffix('.log.gz').read_bytes())
 phases[phase]={'head_at_start':record['head_at_start'],'exit_code':record['exit_code'],'source_count':record['watched_source_count'],'source_inventory_uncompressed_sha256':sha(raw),'record_sha256':sha((out/f'{phase}.json').read_bytes()),'log_uncompressed_sha256':sha(log_bytes)}
assert module.source_hashes()==base
runtime_scopes=['lib','test','packages','assets','android','ios','macos','windows','linux','web','.fvmrc','pubspec.yaml','pubspec.lock','analysis_options.yaml','dart_test.yaml']
changed=git('diff','--name-only',accepted,'HEAD','--',*runtime_scopes).splitlines()
assert not changed,changed
resource=json.loads((out/'web-resource-run.json').read_text())
assert resource['exit_code']==0 and resource['sdk_restored_exactly']
sdk=Path(resource['sdk']);sdk_actual={name:sha((sdk/name).read_bytes()) for name in resource['sdk_before']}
modes={name:(sdk/name).stat().st_mode for name in resource['sdk_modes_before']}
assert sdk_actual==resource['sdk_before']==resource['sdk_after']
assert modes==resource['sdk_modes_before']==resource['sdk_modes_after']
web=json.loads((out/'web.json').read_text());bundle=root/'build/web/main.dart.js'
assert sha(bundle.read_bytes())==web['main_dart_js']['sha256']
visual=json.loads((out/'focused/visual-receipt.json').read_text())
for path,digest in visual['source_sha256'].items():assert sha((root/path).read_bytes())==digest
for shot in visual['captures']:assert sha((root/shot['path']).read_bytes())==shot['sha256']
record={'recorded_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'accepted_application_source':accepted,'verified_head':git('rev-parse','HEAD'),'watched_source_count':len(base),'all_five_phase_inventories_identical':True,'current_worktree_source_matches':True,'runtime_paths_changed_since_accepted_source':changed,'phases':phases,'sdk_sha256':sdk_actual,'sdk_modes':modes,'sdk_restored_exactly':True,'web_bundle':web['main_dart_js'],'visual_source_and_images_match':True,'github_actions_queried_or_awaited':False}
(out/'final-source-verification.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))

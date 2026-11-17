#!/usr/bin/env python3
"""Correct two local lock paths, then enforce the unchanged package identities."""
from pathlib import Path
import hashlib,json,os,subprocess,time
import yaml

OUT=Path(__file__).resolve().parent/'service-setup'
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'crisp-host-harness'
HARNESS=OUT/'service-harness'
SDK=ROOT/'flutter-sdk'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
 receipt=json.loads((OUT/'service-setup-receipt.json').read_text())
 assert receipt['setup_commands'][-1]['exit_code']!=0
 (OUT/'setup-attempt-1.json').write_text(json.dumps(receipt,indent=2)+'\n')
 old=(HARNESS/'pubspec.lock').read_bytes();before=yaml.safe_load(old)
 corrected=old.decode().replace(str(BASE),str(HARNESS)).encode();after=yaml.safe_load(corrected)
 changes=[]
 for name,entry in before['packages'].items():
  if entry!=after['packages'][name]:
   assert entry['source']=='path' and name in {'quds_office_engine','quds_office_editor'}
   assert entry['version']==after['packages'][name]['version']
   changes.append({'package':name,'before':entry,'after':after['packages'][name]})
 assert len(changes)==2
 (OUT/'seed-lock-before-path-rebase.yaml').write_bytes(old)
 (HARNESS/'pubspec.lock').write_bytes(corrected)
 receipt['path_rebase_correction']={'original_failure':'Two local engine/editor paths still named the old harness; enforced resolution correctly rejected them.',
  'changes':changes,'hosted_versions_or_hashes_changed':False,'failed_attempt_preserved':'setup-attempt-1.json'}
 env=os.environ.copy();env.update(FLUTTER_ROOT=str(SDK),PUB_CACHE=str(OUT/'pub-cache'),TMPDIR=str(OUT/'tmp'),
  XDG_CONFIG_HOME=str(OUT/'config'),CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true')
 command=[str(SDK/'bin/cache/dart-sdk/bin/dart'),str(SDK/'bin/cache/flutter_tools.snapshot'),'pub','get','--offline','--enforce-lockfile']
 def save():(OUT/'service-setup-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 for n in [1,2]:
  log=OUT/'logs'/f'service-rebased-locked-resolution-{n}.log';start=time.monotonic()
  with log.open('w') as stream:run=subprocess.run(command,cwd=HARNESS,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=600)
  receipt['setup_commands'].append({'name':f'service-rebased-locked-resolution-{n}','command':command,'cwd':str(HARNESS),
   'log':str(log),'status':'passed' if run.returncode==0 else 'failed','exit_code':run.returncode,'elapsed_seconds':round(time.monotonic()-start,3),'log_sha256':sha(log)})
  save();assert run.returncode==0,log
  assert yaml.safe_load((HARNESS/'pubspec.lock').read_text())==after
  if n==1:frozen=sha(HARNESS/'pubspec.lock')
  else:assert sha(HARNESS/'pubspec.lock')==frozen
 graph=json.loads((HARNESS/'.dart_tool/package_config.json').read_text())
 assert graph['flutterRoot']==SDK.as_uri() and graph['flutterVersion']=='3.47.8'
 for name,value in receipt['base_inputs_before'].items():assert sha(BASE/name)==value,name
 for name,value in receipt['runtime_before'].items():assert sha(SDK/name)==value,name
 receipt.update(status='passed',harness=str(HARNESS),pub_cache=str(OUT/'pub-cache'),
  final_package_count=len(graph['packages']),final_lock_sha256=frozen,additional_package_names=sorted(x['name'] for x in receipt['downloaded_packages']),
  original_package_identities_preserved=True,new_packages_match_production_lock=True,base_inputs_unchanged=True,runtime_inputs_unchanged=True,
  package_config_sha256=sha(HARNESS/'.dart_tool/package_config.json'))
 save();print(json.dumps({'status':'passed','packages':len(graph['packages']),'additional':receipt['additional_package_names']}),flush=True)

if __name__=='__main__':main()

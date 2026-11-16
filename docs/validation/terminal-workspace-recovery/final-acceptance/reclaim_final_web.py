#!/usr/bin/env python3
"""Reclaim only reproducible caches and sparse materializations before final web."""
import datetime,hashlib,importlib.util,json,os,shutil,subprocess,time
from pathlib import Path
TC=Path(__file__).resolve().parent
REPO=TC.parent/'CrispCloud'
BASE=TC/'evidence/final-acceptance/resource-cleanup'
BASE.mkdir(exist_ok=False)
spec=importlib.util.spec_from_file_location('accept_final',TC/'accept_final_recovery.py')
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
def run(args,cwd=REPO,**kw):
 p=subprocess.run(args,cwd=cwd,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,**kw)
 record['commands'].append({'argv':args,'cwd':str(cwd),'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
 if p.returncode:raise RuntimeError(str(args)+' failed: '+p.stderr)
 return p.stdout
def size(path):
 return sum(p.stat().st_size for p in path.rglob('*') if p.is_file()) if path.is_dir() else path.stat().st_size
def resources():
 disk=shutil.disk_usage(REPO)
 memory={k:int(v.split()[0])*1024 for k,v in (line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines()) if k in ['MemTotal','MemAvailable','Shmem','Cached','SwapTotal','SwapFree']}
 return {'disk':dict(zip(['total','used','free'],disk)),'memory':memory}
record={'accepted_source':a.FROZEN,'started_utc':a.stamp(),'commands':[],'before_resources':resources(),'removed_generated_caches':[],'sdk_binaries_modified':False,'source_or_optimization_changed':False}
before=a.snapshot();a.save(BASE/'sources-before.json.gz',before)
assert not a.frozen_proof(before)['mismatches']
assert json.loads((TC/'evidence/final-acceptance/combined/receipt.json').read_text())['accepted']
active_sdk=['bin/dart','bin/dartaotruntime','bin/snapshots/dart2js_aot.dart.snapshot']
sdk=TC/'flutter/bin/cache/dart-sdk'
record['active_sdk_before']={p:a.identity(sdk/p) for p in active_sdk}
try:
 for p in [REPO/'build/test_cache',REPO/'build/unit_test_assets',REPO/'.dart_tool/flutter_build',REPO/'build/web']:
  if p.exists():
   record['removed_generated_caches'].append({'path':str(p),'bytes':size(p),'reason':'Completed test/generated web output; reproducible from unchanged accepted source and exact graph.'})
   shutil.rmtree(p)
 # Only ended temp entries owned by this toolchain; no Flutter process remains.
 for p in list((TC/'tmp').iterdir()):
  if p.name.startswith(('flutter_tools.','flutter_test_fonts.')):
   record['removed_generated_caches'].append({'path':str(p),'bytes':size(p),'reason':'Ended Flutter temporary output.'})
   shutil.rmtree(p) if p.is_dir() else p.unlink()
 # Sparse materialization changes index skip-worktree flags, not tracked bytes/history.
 docs=[]
 tree={}
 for item in subprocess.check_output(['git','ls-tree','-r','-z','HEAD','--','docs'],cwd=REPO).decode().split('\0'):
  if item:
   meta,p=item.split('\t',1);mode,kind,oid=meta.split(' ')
   if kind=='blob':tree[p]=(mode,oid)
 for p in sorted((REPO/'docs').rglob('*')):
  if not p.is_file() or p.suffix not in {'.png','.gz'}:continue
  rel=p.relative_to(REPO).as_posix()
  if rel not in tree:continue
  data=p.read_bytes();oid=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
  mode='100755' if p.stat().st_mode&0o111 else '100644'
  assert (mode,oid)==tree[rel],rel
  docs.append({'path':rel,'bytes':len(data),'git_blob':oid,'mode':mode,'sha256':hashlib.sha256(data).hexdigest()})
 record['sparse_materialization']={'patterns':['/*','!/docs/**/*.png','!/docs/**/*.gz'],'tracked_count':len(docs),'tracked_bytes':sum(x['bytes'] for x in docs),'identity_source_commit':a.FROZEN,'history_preserved':True}
 a.save(BASE/'sparse-excluded-identities.json.gz',docs)
 run(['git','sparse-checkout','set','--no-cone','--stdin'],input='/*\n!/docs/**/*.png\n!/docs/**/*.gz\n')
 assert all(not (REPO/d['path']).exists() for d in docs)
 # Replace downloaded blob cache with a fresh promisor commit/tree store.
 # Every retained local ref and HEAD must exist before and after replacement.
 refs=run(['git','for-each-ref','--format=%(objectname)']).splitlines()
 refs=sorted(set(refs+[run(['git','rev-parse','HEAD']).strip()]))
 fresh=TC/'final-filtered.git'
 run(['git','clone','--filter=blob:none','--bare','--no-single-branch','https://github.com/CrispStrobe/CrispCloud',str(fresh)],cwd=TC)
 for oid in refs:
  run(['git','--git-dir='+str(fresh),'cat-file','-e',oid+'^{commit}'],cwd=TC)
  run(['git','--git-dir='+str(fresh),'cat-file','-e',oid+'^{tree}'],cwd=TC)
 original=REPO/'.git/objects';backup=TC/'final-previous-git-objects'
 prior_size=size(original);new_size=size(fresh/'objects')
 original.rename(backup);(fresh/'objects').rename(original)
 try:
  for oid in refs:
   run(['git','cat-file','-e',oid+'^{commit}'])
   run(['git','cat-file','-e',oid+'^{tree}'])
  assert run(['git','rev-parse','HEAD']).strip()==a.FROZEN
 except BaseException:
  failed=TC/'final-failed-new-git-objects';original.rename(failed);backup.rename(original)
  raise
 shutil.rmtree(backup);shutil.rmtree(fresh)
 record['git_object_cache']={'old_bytes':prior_size,'new_bytes':new_size,'retained_ref_targets_verified':refs,'full_commit_and_tree_objects_verified':True,'missing_blob_resolution':'Existing origin promisor configuration fetches missing remote blobs on demand.','source_worktree_unchanged':True}
 record['active_sdk_after']={p:a.identity(sdk/p) for p in active_sdk}
 assert record['active_sdk_before']==record['active_sdk_after']
 after=a.snapshot();a.save(BASE/'sources-after.json.gz',after)
 record['source_changes']=[p for p in sorted(before.keys()|after.keys()) if before.get(p)!=after.get(p)]
 record['watched_files']=len(after);record['frozen_commit_proof']=a.frozen_proof(after)
 assert not record['source_changes']
 assert not record['frozen_commit_proof']['mismatches']
 status=run(['git','status','--short'])
 record['git_status']=status
 assert not status.strip()
 record['accepted']=True
except BaseException as e:
 record['accepted']=False;record['error']=repr(e)
 raise
finally:
 record['finished_utc']=a.stamp();record['after_resources']=resources()
 record['runner_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
 (BASE/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
 print(json.dumps({k:v for k,v in record.items() if k not in {'commands','git_object_cache','frozen_commit_proof'}},indent=2),flush=True)

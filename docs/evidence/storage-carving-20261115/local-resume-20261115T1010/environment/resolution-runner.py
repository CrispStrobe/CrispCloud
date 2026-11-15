#!/usr/bin/env python3
"""Preserve dependency resolution attempts; these are setup receipts, not test gates."""
import argparse,datetime,gzip,hashlib,json,os,platform,subprocess,sys,time
from pathlib import Path

def stamp(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(b): return hashlib.sha256(b).hexdigest()
def encode(x): return (json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def git(repo,*args): return subprocess.check_output(['git','-C',str(repo),*args],text=True).strip()

def main():
 p=argparse.ArgumentParser(); p.add_argument('--repo',type=Path,required=True); p.add_argument('--cwd',default='.'); p.add_argument('--output',type=Path,required=True); p.add_argument('--enforce-lock',action='store_true'); p.add_argument('command',nargs=argparse.REMAINDER); a=p.parse_args()
 repo=a.repo.resolve(); cwd=(repo/a.cwd).resolve(); out=a.output.resolve(); out.mkdir(parents=True,exist_ok=False)
 cmd=a.command[1:] if a.command[:1]==['--'] else a.command
 def snapshot(phase):
  result={}
  for name in ['pubspec.yaml','pubspec.lock','.dart_tool/package_config.json','.dart_tool/package_graph.json']:
   path=cwd/name; dst=out/phase/(name+'.gz'); dst.parent.mkdir(parents=True,exist_ok=True)
   if path.exists():
    b=path.read_bytes(); dst.write_bytes(gzip.compress(b,mtime=0)); result[name]={'size':len(b),'sha256':sha(b)}
   else: result[name]={'missing':True}
  return result
 before=snapshot('before'); started=time.monotonic()
 metadata={'schema':1,'scope':'Dependency setup only; application source may change concurrently. Not runtime qualification.','started_at':stamp(),'source_head_at_start':git(repo,'rev-parse','HEAD'),'source_tree_at_start':git(repo,'rev-parse','HEAD^{tree}'),'cwd':str(cwd),'command':cmd,'lock_enforcement':a.enforce_lock,'environment':{n:os.environ[n] for n in ['PATH','FLUTTER_ROOT','PUB_CACHE','CARGO_HOME','TMPDIR','XDG_CONFIG_HOME','XDG_CACHE_HOME','LD_LIBRARY_PATH','CI','FLUTTER_SUPPRESS_ANALYTICS','DART_SUPPRESS_ANALYTICS'] if n in os.environ},'platform':platform.platform(),'before_inputs':before,'status':'running'}
 (out/'receipt.json').write_bytes(encode(metadata))
 with (out/'stdout.log').open('wb') as stdout,(out/'stderr.log').open('wb') as stderr:
  try: result=subprocess.run(cmd,cwd=cwd,stdout=stdout,stderr=stderr,timeout=900); code=result.returncode
  except subprocess.TimeoutExpired: code=124; metadata['execution_error']='900-second setup timeout'
  except OSError as e: code=127; metadata['execution_error']=repr(e)
 after=snapshot('after'); unchanged=before['pubspec.yaml']==after['pubspec.yaml']; lock_unchanged=before['pubspec.lock']==after['pubspec.lock']
 success=code==0 and unchanged and (lock_unchanged or not a.enforce_lock)
 metadata.update({'finished_at':stamp(),'elapsed_seconds':time.monotonic()-started,'source_head_at_end':git(repo,'rev-parse','HEAD'),'returncode':code,'after_inputs':after,'pubspec_unchanged':unchanged,'lock_unchanged':lock_unchanged,'resolution_success':success,'status':'completed'})
 (out/'receipt.json').write_bytes(encode(metadata))
 (out/'artifacts-sha256.json').write_bytes(encode({str(x.relative_to(out)):{'size':x.stat().st_size,'sha256':sha(x.read_bytes())} for x in sorted(out.rglob('*')) if x.is_file() and x.name!='artifacts-sha256.json'}))
 print(json.dumps({'output':str(out),'returncode':code,'resolution_success':success,'pubspec_unchanged':unchanged,'lock_unchanged':lock_unchanged},indent=2))
 return 0 if success else 1
if __name__=='__main__':sys.exit(main())

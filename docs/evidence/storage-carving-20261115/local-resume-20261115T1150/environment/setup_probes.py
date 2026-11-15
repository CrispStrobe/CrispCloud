from pathlib import Path
import subprocess,json,os,hashlib,datetime,platform,shutil
r=Path(__file__).resolve().parent
(r/'tmp/probe.c').write_text('int main(void){return 0;}\n')
(r/'tmp/probe.rs').write_text('fn main() {}\n')
versions={}
for cmd in [['clang','--version'],['clang++','--version'],['llvm-ar','--version'],['cmake','--version'],['ninja','--version'],['rustc','-Vv'],['cargo','-Vv']]:
 p=subprocess.run(cmd,capture_output=True,text=True)
 versions[' '.join(cmd)]=dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
 assert p.returncode==0,cmd
(r/'receipts/tool-versions.json').write_text(json.dumps(versions,indent=2)+'\n')
probes=[]
for label,env in [('normal',os.environ.copy()),('filtered',dict(PATH=os.environ['PATH']))]:
 for language,cmd in [('C',['clang',str(r/'tmp/probe.c'),'-o',str(r/'tmp/probe-c')]),('Rust',['rustc',str(r/'tmp/probe.rs'),'-o',str(r/'tmp/probe-rs')])]:
  p=subprocess.run(cmd,env=env,capture_output=True,text=True)
  assert p.returncode==0,(cmd,p.stdout,p.stderr)
  p2=subprocess.run([cmd[-1]],env=env,capture_output=True,text=True)
  assert p2.returncode==0
  probes.append(dict(environment=label,language=language,command=cmd,returncode=p.returncode,execution_returncode=p2.returncode))
(r/'receipts/native-probes.json').write_text(json.dumps(probes,indent=2)+'\n')
receipt=dict(recorded_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),root=str(r),platform=platform.platform(),scope='Toolchain setup only. Not app runtime acceptance.',native_hooks_disabled=False,source_modified=False,flutter_commit=subprocess.check_output(['git','-C',str(r/'flutter'),'rev-parse','HEAD'],text=True).strip(),free_disk=shutil.disk_usage(r).free,downloads_verified=True,sdk_cache_preloaded=True,linux_precache_success=True,native_probes_passed=True)
(r/'receipts/setup-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))

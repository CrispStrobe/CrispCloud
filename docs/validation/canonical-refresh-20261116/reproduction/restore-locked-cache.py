import concurrent.futures,hashlib,json,subprocess,tarfile,tempfile
from pathlib import Path
import yaml
root=Path('/tmp/crispcloud-terminal-ods-isolated'); cache=Path('/tmp/crispcloud-pub-cache-20261116');pkgs={}
locks=[root/'pubspec.lock',root/'packages/quds_office_engine/pubspec.lock',Path('/Users/christianstrobele/flutter-3.47.8/packages/flutter_tools/pubspec.lock')]
for lock in locks:
 if not lock.exists():continue
 for n,p in yaml.safe_load(lock.read_text())['packages'].items():
  if p['source']=='hosted':pkgs[(n,p['version'])]=p['description']['sha256']
def get(item):
 (n,v),sha=item; dest=cache/'hosted/pub.dev'/f'{n}-{v}';archive=cache/'downloads'/f'{n}-{v}.tar.gz';archive.parent.mkdir(parents=True,exist_ok=True)
 if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=sha:
  subprocess.run(['curl','-fsSL','--retry','3','--connect-timeout','10','--max-time','120',f'https://pub.dev/api/archives/{n}-{v}.tar.gz','-o',str(archive)],check=True)
 assert hashlib.sha256(archive.read_bytes()).hexdigest()==sha,(n,v)
 dest.mkdir(parents=True,exist_ok=True)
 with tarfile.open(archive) as t:
  for member in t.getmembers():
   assert (dest/member.name).resolve().is_relative_to(dest.resolve()),member.name
   if member.issym():assert (dest/member.name).parent.joinpath(member.linkname).resolve().is_relative_to(dest.resolve()),member.name
   if member.islnk():assert (dest/member.linkname).resolve().is_relative_to(dest.resolve()),member.name
  t.extractall(dest)
 h=cache/'hosted-hashes/pub.dev'/f'{n}-{v}.sha256';h.parent.mkdir(parents=True,exist_ok=True);h.write_text(sha)
 return n,v
results=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
 for r in pool.map(get,pkgs.items()):
  results.append(r)
  if len(results)%30==0:print('restored',len(results),'/',len(pkgs),flush=True)
(root/'docs/validation/canonical-refresh-20261116/cache-restoration.json').write_text(json.dumps({'packages':results,'verification':'Archive SHA-256 matches existing lockfiles; no production constraints or lockfile edits.'},indent=2)+'\n')
print('restored',len(results),flush=True)

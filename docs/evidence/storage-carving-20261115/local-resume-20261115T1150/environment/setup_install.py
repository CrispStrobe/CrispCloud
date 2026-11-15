from pathlib import Path
import json, subprocess, datetime, os, shutil
r=Path(__file__).resolve().parent
assert (r/'receipts/downloads.json').exists(), 'Finish verified downloads first'
env=os.environ.copy()
env['TMPDIR']=str(r/'tmp')
print('extract flutter',flush=True)
subprocess.run(['tar','-xJf',str(r/'downloads/flutter_linux_3.47.8-stable.tar.xz'),'-C',str(r)],check=True,env=env)
(r/'native').mkdir(exist_ok=True)
for p in sorted((r/'downloads').glob('*.deb')):
 subprocess.run(['dpkg-deb','-x',str(p),str(r/'native')],check=True,env=env)
 print('extract',p.name,flush=True)
(r/'rust-sources').mkdir(exist_ok=True)
for n in ['rustc','cargo','rust-std']:
 p=r/'downloads'/f'{n}-1.100.0-x86_64-unknown-linux-gnu.tar.xz'
 subprocess.run(['tar','-xJf',str(p),'-C',str(r/'rust-sources')],check=True,env=env)
 source=r/'rust-sources'/f'{n}-1.100.0-x86_64-unknown-linux-gnu'
 subprocess.run(['sh','install.sh','--prefix='+str(r/'rust'),'--disable-ldconfig'],cwd=source,check=True,env=env,stdout=(r/'receipts'/f'install-{n}.log').open('w'))
 print('install',n,flush=True)
 shutil.rmtree(source)
link=r/'lib/libsqlite3.so'
if not link.exists(): link.symlink_to('/lib/x86_64-linux-gnu/libsqlite3.so.0')
(r/'receipts/install.json').write_text(json.dumps(dict(installed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),root=str(r),removed_extracted_rust_sources=True),indent=2)+'\n')
print('installation complete',flush=True)

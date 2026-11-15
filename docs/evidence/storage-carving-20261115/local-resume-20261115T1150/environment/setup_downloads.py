from pathlib import Path
import concurrent.futures, hashlib, json, subprocess, time, datetime
root=Path(__file__).resolve().parent
prior=json.loads((root/'receipts/prior-setup-receipt.json').read_text())
release=json.loads((root/'receipts/prior-flutter-release.json').read_text())
metadata=json.loads((root/'receipts/releases_linux.json').read_text())
assert any(r['version']==release['version'] and r['sha256']==release['sha256'] and r['hash']==release['hash'] for r in metadata['releases'])
rust=json.loads((root/'receipts/prior-rust-packages.json').read_text())
assert hashlib.sha256((root/'receipts/channel-rust-1.100.0.toml').read_bytes()).hexdigest()==rust['manifest_sha256']
native=json.loads((root/'receipts/prior-native-packages.json').read_text())
items=[prior['flutter_archive']]+[dict(url=p['url'],sha256=p['sha256']) for p in rust['packages']]+[dict(url='https://deb.debian.org/debian/'+p['Filename'],sha256=p['SHA256'],size=int(p['Size'])) for p in native['packages']]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for part in iter(lambda:f.read(1024*1024),''): 
   if not part: break
   h.update(part)
 return h.hexdigest()
def one(item):
 p=root/'downloads'/item['url'].split('/')[-1]
 start=time.time()
 if not p.exists():
  subprocess.run(['curl','-fSL','--max-time','900','--connect-timeout','30',item['url'],'-o',str(p)],check=True,stdout=subprocess.DEVNULL,stderr=(root/'receipts'/('download-'+p.name+'.log')).open('w'))
 assert sha(p)==item['sha256'],p
 if 'size' in item: assert p.stat().st_size==item['size'],p
 out=dict(item,path=str(p),verified=True,elapsed_seconds=round(time.time()-start,2),size=p.stat().st_size)
 print('verified',p.name,out['size'],flush=True)
 return out
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
 results=list(pool.map(one,items))
(root/'receipts/downloads.json').write_text(json.dumps(dict(recorded_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),downloads=results),indent=2)+'\n')
print('all_downloads_verified',flush=True)

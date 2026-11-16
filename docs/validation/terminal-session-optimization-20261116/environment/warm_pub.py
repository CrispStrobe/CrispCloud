import concurrent.futures,hashlib,json,pathlib,subprocess,tarfile,tempfile,shutil,os
root=pathlib.Path(__file__).resolve().parent
source=root.parent/"crispcloud/docs/validation/terminal-ssh-multiplexing/environment/pub-downloads.json"
items={x["key"]:x for x in json.loads(source.read_text())}
import yaml
for lock in [root/"flutter/packages/flutter_tools/pubspec.lock",root.parent/"crispcloud/pubspec.lock"]:
 if not lock.exists():continue
 for name,spec in yaml.safe_load(lock.read_text())["packages"].items():
  if spec["source"]!="hosted":continue
  desc=spec["description"];key=name+"-"+spec["version"]
  entry={"name":name,"version":spec["version"],"key":key,"sha256":desc["sha256"]}
  if key in items and items[key]["sha256"]!=entry["sha256"]:raise RuntimeError("Lock conflict "+key)
  items[key]=entry
cache=root/"pub-cache"
for d in [cache/"hosted/pub.dev",cache/"hosted-hashes/pub.dev",root/"downloads/pub"]:d.mkdir(parents=True,exist_ok=True)
receipts=[]
def install(item):
 key=item["key"];dest=cache/"hosted/pub.dev"/key;digest=cache/"hosted-hashes/pub.dev"/(key+".sha256")
 if dest.exists() and digest.exists() and digest.read_text().strip()==item["sha256"]:return {**item,"cached":True}
 archive=root/"downloads/pub"/(key+".tar.gz")
 if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=item["sha256"]:
  subprocess.run(["curl","-fsSL","--retry","2","--connect-timeout","15","--max-time","300","https://pub.dev/api/archives/"+key+".tar.gz","-o",str(archive)],check=True)
 actual=hashlib.sha256(archive.read_bytes()).hexdigest()
 if actual!=item["sha256"]:raise RuntimeError("Digest mismatch "+key)
 stage=pathlib.Path(tempfile.mkdtemp(prefix=key+"-",dir=root/"tmp"))
 with tarfile.open(archive) as t:t.extractall(stage,filter="data")
 if not dest.exists():stage.rename(dest)
 else:shutil.rmtree(stage)
 digest.write_text(item["sha256"])
 print("verified",key,archive.stat().st_size,flush=True)
 return {**item,"bytes":archive.stat().st_size,"verified":True}
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
 for receipt in pool.map(install,items.values()):
  receipts.append(receipt)
  (root/"logs/pub-installation.json").write_text(json.dumps(receipts,indent=2)+"\n")
print("hosted packages complete",len(receipts),flush=True)

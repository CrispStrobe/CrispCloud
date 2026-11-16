import concurrent.futures,hashlib,json,pathlib,subprocess,tarfile,time
root=pathlib.Path(__file__).resolve().parent
source=root.parent/"crispcloud/docs/validation/terminal-ssh-multiplexing/environment"
items=json.loads((source/"native-downloads.json").read_text())+json.loads((source/"tmux-downloads.json").read_text())
receipts=[]
def download(item):
 path=root/"downloads"/item["url"].split("/")[-1]
 if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=item["sha256"]:
  subprocess.run(["curl","-fsSL","--retry","2","--connect-timeout","20","--max-time","300",item["url"],"-o",str(path)],check=True)
 actual=hashlib.sha256(path.read_bytes()).hexdigest()
 if actual!=item["sha256"]:raise RuntimeError("SHA256 mismatch: "+item["name"])
 print("verified",item["name"],path.stat().st_size,flush=True)
 return item,path
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
 for item,path in pool.map(download,items):
  if item.get("kind","deb")=="deb":
   subprocess.run(["dpkg-deb","-x",str(path),str(root/"native")],check=True)
  else:
   dest=root/"downloads"/("unpack-"+item["name"])
   dest.mkdir(exist_ok=True)
   with tarfile.open(path) as archive:archive.extractall(dest,filter="data")
   install=next(dest.glob("*/install.sh"))
   subprocess.run(["sh",str(install),"--prefix="+str(root/"rust"),"--disable-ldconfig"],cwd=install.parent,check=True)
  receipts.append({**item,"installed":True})
  (root/"logs/native-installation.json").write_text(json.dumps(receipts,indent=2)+"\n")
print("all native artifacts installed",flush=True)

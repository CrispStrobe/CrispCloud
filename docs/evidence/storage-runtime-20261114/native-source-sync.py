from pathlib import Path
import argparse,hashlib,json,shutil,subprocess
p=argparse.ArgumentParser();p.add_argument('--include-manifests',action='store_true');args=p.parse_args()
root=Path(__file__).resolve().parent
src=root.parent/'CrispCloud';dst=root/'app-validation'
base=subprocess.check_output(['git','-C',str(dst),'rev-parse','HEAD'],text=True).strip()
head=subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()
def names(command):
    return [s.decode() for s in subprocess.check_output(command).split(b'\0') if s]
files=set(names(['git','-C',str(src),'diff','--name-only','-z',base]))
files.update(names(['git','-C',str(src),'ls-files','--others','--exclude-standard','-z']))
if not args.include_manifests:files.difference_update({'pubspec.yaml','pubspec.lock'})
receipt={'source_head':head,'validation_base':base,'includes_manifests':args.include_manifests,'files':{}}
for name in sorted(files):
    source=src/name;target=dst/name
    if source.is_file():
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        receipt['files'][name]=hashlib.sha256(target.read_bytes()).hexdigest()
    elif not source.exists() and target.exists():
        target.unlink();receipt['files'][name]=None
(root/'validation-source-sync.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'copied_paths':len(receipt['files']),'source_head':head,'includes_manifests':args.include_manifests}))

"""Seal only the small reproducible audit, excluding downloaded/build binaries."""
from pathlib import Path
import hashlib, io, json, shutil, tarfile

base=Path(__file__).resolve().parent
output=base/'sealed'
output.mkdir(exist_ok=True)
helpers=['README.md','LICENSE-crisp-docx.txt','verify.py','oracle_adapter.rs','ooxml_projection.py','make_controls.py','run_probes.py','run_retained_pairs.py','run_command.py','prepare_rust.py','seal_audit.py']
for name in helpers: shutil.copyfile(base/name,output/name)
records={}
for p in sorted(base.iterdir()):
    if p.is_file() and p.name not in helpers and p.suffix in ['.json','.log','.toml','.sha256','.lock','.md','.docx']:
        records[p.name]=p.read_bytes()
for folder in ['controls','results','retained-pairs','note-schema']:
    for p in sorted((base/folder).rglob('*')):
        if p.is_file(): records[str(p.relative_to(base))]=p.read_bytes()
def sha(data): return hashlib.sha256(data).hexdigest()
manifest={name:{'bytes':len(data),'sha256':sha(data)} for name,data in sorted(records.items())}
with tarfile.open(output/'records.tar.xz','w:xz',preset=6,format=tarfile.PAX_FORMAT) as tar:
    for name,data in sorted(records.items()):
        info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o644;info.mtime=0
        tar.addfile(info,io.BytesIO(data))
(output/'record-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
receipt={'schema':'crisp-docx-independent-audit-v1','sourceCommit':'ddf7830d8d92e6b59b10874d144a59f163a256e1','recordCount':len(records),'rawRecordBytes':sum(len(x) for x in records.values()),'files':{}}
for p in sorted(output.iterdir()):
    if p.is_file() and p.name!='receipt.json':
        receipt['files'][p.name]={'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
(output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'output':str(output),'records':len(records),'rawBytes':receipt['rawRecordBytes'],'archive':receipt['files']['records.tar.xz']},indent=2))

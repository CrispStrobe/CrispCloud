#!/usr/bin/env python3
"""Build a second immutable source copy of an exact saved Git revision."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tarfile
import time

p=argparse.ArgumentParser();p.add_argument('--revision',required=True)
p.add_argument('--label',default='ext-final-web');a=p.parse_args()
root=Path(__file__).resolve().parent;repo=root.parent/'crispcloud'
revision=subprocess.check_output(['git','rev-parse',a.revision+'^{commit}'],cwd=repo,text=True).strip()
app=root/('app-release-'+revision[:12]);app.mkdir()
archive=subprocess.Popen(['git','archive','--format=tar',revision],cwd=repo,stdout=subprocess.PIPE)
with tarfile.open(fileobj=archive.stdout,mode='r|') as tar:tar.extractall(app,filter='data')
if archive.wait():raise SystemExit('git archive failed')
sha=lambda data:hashlib.sha256(data).hexdigest()
original={name:(app/name).read_bytes() for name in ['pubspec.yaml','pubspec.lock']}
version=re.search(rb'^version:\s*(\S+)',original['pubspec.yaml'],re.M).group(1).decode()
tree={}
for entry in subprocess.check_output(['git','ls-tree','-r','-z',revision],cwd=repo).split(b'\0'):
    if not entry:continue
    metadata,name=entry.split(b'\t',1);name=name.decode()
    if name.startswith('docs/'):continue
    kind=metadata.decode().split()[1]
    if kind!='blob':continue
    data=(app/name).read_bytes()
    blob=hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
    if blob!=metadata.decode().split()[2]:raise SystemExit('Archive differs from saved source: '+name)
    tree[name]=sha(data)
binding=root/'logs'/f'{a.label}-source-binding.json'
binding.write_text(json.dumps({'revision':revision,'files':tree},indent=2)+'\n')
env=dict(os.environ)
env.update({'PUB_CACHE':str(root/'pub-cache'),'TMPDIR':str(root/'tmp'),
            'XDG_CACHE_HOME':str(root/'xdg-cache'),'XDG_CONFIG_HOME':str(root/'xdg-config'),
            'FLUTTER_ROOT':str(root/'flutter'),'CI':'true',
            'CARGO_HOME':str(root/'cargo'),'RUSTUP_HOME':str(root/'rustup')})
env['PATH']=str(root/'toolchain-bin')+os.pathsep+str(root/'flutter/bin')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/bin')+os.pathsep+env['PATH']
env['LD_LIBRARY_PATH']=str(root/'llvm19/usr/lib/x86_64-linux-gnu')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/lib')+(os.pathsep+env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
commands=[['flutter','pub','get','--offline','--enforce-lockfile'],
 ['flutter','build','web','--release','--no-pub','--no-wasm-dry-run','--dart-define=APP_VERSION='+version,'--dart-define=GIT_HASH='+revision]]
receipt={'source_revision':revision,'cwd':str(app),'app_version':version,
 'source_paths':len(tree),'source_binding_sha256':sha(binding.read_bytes()),
 'profile':'Original production manifests; production JavaScript release; no native-test hook override.',
 'production_manifest_sha256':{name:sha(data) for name,data in original.items()},
 'started_at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'commands':[]}
code=1
try:
    for index,command in enumerate(commands):
        logfile=root/'logs'/f'{a.label}-{index}.log'
        with logfile.open('w') as log:code=subprocess.run(command,cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT).returncode
        receipt['commands'].append({'command':command,'exit_code':code,'log':logfile.name,'log_sha256':sha(logfile.read_bytes())})
        if code:break
    if code==0:
        build=app/'build/web';main=(build/'main.dart.js').read_bytes()
        targets=['main.dart.js','flutter_bootstrap.js','index.html','assets/packages/apple_lzfse/LICENSE']
        receipt['outputs']={name:{'bytes':(build/name).stat().st_size,'sha256':sha((build/name).read_bytes())} for name in targets if (build/name).is_file()}
        receipt['revision_stamp_present']=revision.encode() in main
        receipt['app_version_present']=version.encode() in main
        receipt['apple_lzfse_license_present']=(build/targets[-1]).is_file()
        if not all(receipt[key] for key in ['revision_stamp_present','app_version_present','apple_lzfse_license_present']):code=1
finally:
    receipt['exit_code']=code
    receipt['manifests_unchanged']=all((app/name).read_bytes()==data for name,data in original.items())
    receipt['source_drift_after']=[name for name,digest in tree.items() if not (app/name).is_file() or sha((app/name).read_bytes())!=digest]
    receipt['finished_at_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    (root/'logs'/f'{a.label}-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
raise SystemExit(code if receipt['manifests_unchanged'] and not receipt['source_drift_after'] else 1)

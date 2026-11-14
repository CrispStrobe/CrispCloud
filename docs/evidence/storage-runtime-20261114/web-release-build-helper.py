from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--label',required=True);p.add_argument('--source-revision',required=True);args=p.parse_args()
root=Path(__file__).resolve().parent;app=root/'app-validation';primary=root.parent/'CrispCloud'
def sha(data):return hashlib.sha256(data).hexdigest()
original={name:(app/name).read_bytes() for name in ('pubspec.yaml','pubspec.lock')}
for name,data in original.items():
    if data!=(primary/name).read_bytes():raise SystemExit('Validation '+name+' differs from primary production manifest')
if b'\nhooks:' in original['pubspec.yaml']:raise SystemExit('Unexpected host test hooks in production manifest')
version=re.search(rb'^version:\s*(\S+)',original['pubspec.yaml'],re.M).group(1).decode()
env=dict(os.environ)
env.update({'PUB_CACHE':str(root/'pub-cache'),'TMPDIR':str(root/'tmp'),'XDG_CACHE_HOME':str(root/'xdg-cache'),'XDG_CONFIG_HOME':str(root/'xdg-config'),'FLUTTER_ROOT':str(root/'flutter'),'CI':'true'})
env['PATH']=str(root/'flutter/bin')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/bin')+os.pathsep+env['PATH']
env['LD_LIBRARY_PATH']=str(root/'llvm19/usr/lib/x86_64-linux-gnu')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/lib')+(os.pathsep+env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
command=[str(root/'flutter/bin/flutter'),'build','web','--release','--no-pub','--no-wasm-dry-run','--dart-define=APP_VERSION='+version,'--dart-define=GIT_HASH='+args.source_revision]
receipt={'command':command,'cwd':str(app),'profile':'Original production manifest; standard JavaScript release; optional WebAssembly dry run disabled.','source_revision_stamp':args.source_revision,'app_version':version,'production_hashes':{n:sha(d) for n,d in original.items()},'input_sources':json.loads((root/'validation-source-sync.json').read_text()),'started_at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
code=1
try:
    code=subprocess.run(command,cwd=app,env=env).returncode
finally:
    receipt['exit_code']=code
    receipt['manifests_unchanged']=all((app/n).read_bytes()==d for n,d in original.items())
    receipt['finished_at_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    if code==0:
        targets=['main.dart.js','flutter_bootstrap.js','index.html','assets/packages/apple_lzfse/LICENSE']
        receipt['outputs']={name:{'bytes':(app/'build/web'/name).stat().st_size,'sha256':sha((app/'build/web'/name).read_bytes())} for name in targets if (app/'build/web'/name).is_file()}
        main=(app/'build/web/main.dart.js').read_text()
        receipt['revision_stamp_present']=args.source_revision in main
        receipt['app_version_present']=version in main
        receipt['apple_lzfse_license_asset_present']=(app/'build/web/assets/packages/apple_lzfse/LICENSE').is_file()
    (root/(args.label+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n')
raise SystemExit(code)

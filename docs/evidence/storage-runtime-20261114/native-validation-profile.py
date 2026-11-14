from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--label',required=True);p.add_argument('command',nargs=argparse.REMAINDER);args=p.parse_args()
root=Path(__file__).resolve().parent;app=root/'app-validation'
command=args.command
if command and command[0]=='--':command=command[1:]
if not command:raise SystemExit('Missing flutter command')
manifest=app/'pubspec.yaml';lock=app/'pubspec.lock'
original={manifest:manifest.read_bytes(),lock:lock.read_bytes()}
if b'\nhooks:' in original[manifest]:raise SystemExit('Unexpected existing hooks configuration')
profile=original[manifest]+b'\n# Isolated archive-test host profile: native ebook conversion is not under test.\nhooks:\n  user_defines:\n    crisp_ebook_conversion:\n      enabled: false\n'
def sha(data):return hashlib.sha256(data).hexdigest()
env=dict(os.environ)
env.update({'PUB_CACHE':str(root/'pub-cache'),'TMPDIR':str(root/'tmp'),'XDG_CACHE_HOME':str(root/'xdg-cache'),'XDG_CONFIG_HOME':str(root/'xdg-config'),'FLUTTER_ROOT':str(root/'flutter'),'CI':'true'})
env['PATH']=str(root/'flutter/bin')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/bin')+os.pathsep+env['PATH']
env['LD_LIBRARY_PATH']=str(root/'llvm19/usr/lib/x86_64-linux-gnu')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/lib')+(os.pathsep+env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
receipt={'command':[str(root/'flutter/bin/flutter'),*command],'cwd':str(app),'profile':'Only optional native ebook conversion build disabled; no app source or dependency version substitutions.','production_hashes':{path.name:sha(data) for path,data in original.items()},'test_manifest_sha256':sha(profile),'input_sources':json.loads((root/'validation-source-sync.json').read_text()),'started_at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
code=1
try:
    manifest.write_bytes(profile)
    code=subprocess.run(receipt['command'],cwd=app,env=env).returncode
finally:
    receipt['lock_unchanged_during_test']=lock.read_bytes()==original[lock]
    for path,data in original.items():path.write_bytes(data)
    receipt['exit_code']=code
    receipt['restored_hashes']={path.name:sha(path.read_bytes()) for path in original}
    receipt['manifests_restored']=all(path.read_bytes()==data for path,data in original.items())
    receipt['finished_at_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    (root/(args.label+'-receipt.json')).write_text(json.dumps(receipt,indent=2)+'\n')
raise SystemExit(code)

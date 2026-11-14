#!/usr/bin/env python3
"""Execute a source-bound validation command, temporarily disabling ebook hook."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--label', required=True)
p.add_argument('--native', action='store_true')
p.add_argument('--revision')
p.add_argument('command', nargs=argparse.REMAINDER)
a = p.parse_args()
command = a.command[1:] if a.command[:1] == ['--'] else a.command
if not command:
    raise SystemExit('No command supplied')
root = Path(__file__).resolve().parent
app = root / 'app-validation'
marker = root / 'validation-running'
marker.open('x').write(a.label)
env = dict(os.environ)
env.update({'PUB_CACHE': str(root/'pub-cache'), 'TMPDIR': str(root/'tmp'),
            'XDG_CACHE_HOME': str(root/'xdg-cache'), 'XDG_CONFIG_HOME': str(root/'xdg-config'),
            'FLUTTER_ROOT': str(root/'flutter'), 'CI': 'true',
            'CARGO_HOME': str(root/'cargo'), 'RUSTUP_HOME': str(root/'rustup')})
env['PATH'] = str(root/'toolchain-bin')+os.pathsep+str(root/'flutter/bin')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/bin')+os.pathsep+str(root/'cargo/bin')+os.pathsep+env['PATH']
env['LD_LIBRARY_PATH'] = str(root/'llvm19/usr/lib/x86_64-linux-gnu')+os.pathsep+str(root/'llvm19/usr/lib/llvm-19/lib')+(os.pathsep+env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
manifest, lock = app/'pubspec.yaml', app/'pubspec.lock'
original = {manifest: manifest.read_bytes(), lock: lock.read_bytes()}
sha = lambda data: hashlib.sha256(data).hexdigest()
binding = json.loads((root/'validation-source-sync.json').read_text())
mismatch = [name for name,digest in binding['files'].items() if sha((app/name).read_bytes()) != digest]
if mismatch:
    marker.unlink()
    raise SystemExit('Source drift before validation: '+repr(mismatch))
if a.revision:
    entries = subprocess.check_output(['git', 'ls-tree', '-r', '-z', a.revision], cwd=root.parent/'crispcloud').split(b'\0')
    expected = {}
    for entry in entries:
        if not entry:
            continue
        metadata, name = entry.split(b'\t', 1)
        expected[name.decode()] = metadata.decode().split()[2]
    unbound = []
    for name in binding['files']:
        data = (app/name).read_bytes()
        object_hash = hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
        if expected.get(name) != object_hash:
            unbound.append(name)
    if unbound:
        marker.unlink()
        raise SystemExit('Sources differ from requested revision: '+repr(unbound))
profile = original[manifest]
if a.native:
    if b'\nhooks:' in profile:
        marker.unlink()
        raise SystemExit('Unexpected existing hooks configuration')
    profile += b'\n# Isolated storage-test host profile; ebook conversion is outside this test.\nhooks:\n  user_defines:\n    crisp_ebook_conversion:\n      enabled: false\n'
receipt = {'command': command, 'cwd': str(app), 'native_ebook_hook_disabled': a.native,
           'production_hashes': {path.name: sha(data) for path,data in original.items()},
           'test_manifest_sha256': sha(profile), 'source_head': binding['source_head'],
           'verified_revision': a.revision,
           'source_paths': len(binding['files']), 'source_binding_sha256': sha((root/'validation-source-sync.json').read_bytes()),
           'started_at_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
(root/'logs'/f'{a.label}-source-binding.json').write_text(json.dumps(binding,indent=2)+'\n')
code=1
try:
    manifest.write_bytes(profile)
    with (root/'logs'/f'{a.label}.log').open('w') as log:
        code=subprocess.run(command,cwd=app,env=env,stdout=log,stderr=subprocess.STDOUT).returncode
finally:
    receipt['lock_unchanged_during_test'] = lock.read_bytes() == original[lock]
    for path,data in original.items():
        path.write_bytes(data)
    receipt['exit_code'] = code
    receipt['manifests_restored'] = all(path.read_bytes() == data for path,data in original.items())
    receipt['source_drift_after'] = [name for name,digest in binding['files'].items() if sha((app/name).read_bytes()) != digest]
    receipt['finished_at_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    receipt['log_sha256'] = sha((root/'logs'/f'{a.label}.log').read_bytes())
    (root/'logs'/f'{a.label}-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    marker.unlink()
print(json.dumps(receipt, indent=2))
raise SystemExit(code)

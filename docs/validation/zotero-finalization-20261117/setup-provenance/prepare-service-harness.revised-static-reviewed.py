#!/usr/bin/env python3
"""Extend an isolated copy of the qualified host graph with production locks.

No source repository, previous harness, SDK, or previous pub cache is written.
Only setup and dependency resolution run; no application tests are launched.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import time
from urllib.parse import urljoin, urlparse, unquote
import yaml

DIRECT = ('html', 'koni_archive', 'koni_codecs')
PINNED = {'html': '0.15.6', 'koni_archive': '0.9.0', 'koni_codecs': '0.9.0'}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--base-harness',type=Path,required=True)
    parser.add_argument('--flutter',type=Path,required=True)
    parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args()
    repo,base,sdk,out=[p.resolve() for p in (args.repo,args.base_harness,args.flutter,args.output_root)]
    out.mkdir(parents=True,exist_ok=True)
    harness=out/'service-harness';cache=out/'pub-cache'
    assert not harness.exists() and not cache.exists(),'Use fresh isolated harness and cache paths'
    for name in ['logs','downloads','tmp','config']:(out/name).mkdir(exist_ok=True)
    production=yaml.safe_load((repo/'pubspec.lock').read_text())['packages']
    original=yaml.safe_load((base/'pubspec.lock').read_text())
    graph_file=base/'.dart_tool/package_config.json'
    graph=json.loads(graph_file.read_text())
    runtime_names=['bin/cache/dart-sdk/bin/dart','bin/cache/flutter_tools.snapshot',
                   'bin/cache/artifacts/engine/linux-x64/flutter_tester','bin/cache/flutter.version.json']
    runtime_before={name:sha(sdk/name) for name in runtime_names}
    base_before={name:sha(base/name) for name in ['pubspec.yaml','pubspec.lock','.dart_tool/package_config.json','.dart_tool/package_graph.json']}
    receipt={'status':'running','production_lock_sha256':sha(repo/'pubspec.lock'),
             'base_harness':str(base),'base_inputs_before':base_before,'runtime_before':runtime_before,
             'added_direct_packages':list(DIRECT),'setup_commands':[],'downloaded_packages':[],
             'application_tests_run':False,'old_harness_cache_sdk_or_source_writes':False}
    def save():
        (out/'service-setup-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    def run(name,command,cwd,env=None):
        log=out/'logs'/(name+'.log');start=time.monotonic()
        row={'name':name,'command':command,'cwd':str(cwd),'log':str(log),'status':'running'}
        receipt['setup_commands'].append(row);save();print(json.dumps({'start':name}),flush=True)
        with log.open('w') as stream:
            process=subprocess.Popen(command,cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT)
            while process.poll() is None:
                try:process.wait(timeout=15)
                except subprocess.TimeoutExpired:print(json.dumps({'active':name,'seconds':round(time.monotonic()-start)}),flush=True)
                if time.monotonic()-start>600:
                    process.terminate();process.wait(timeout=10);raise RuntimeError(name+' timed out')
        row.update(status='passed' if process.returncode==0 else 'failed',exit_code=process.returncode,
                   elapsed_seconds=round(time.monotonic()-start,3),log_sha256=sha(log));save()
        assert process.returncode==0,name
    save()
    shutil.copytree(base,harness,symlinks=True,ignore=shutil.ignore_patterns('.dart_tool','build'))
    for path in harness.rglob('pubspec.yaml'):
        assert not path.is_symlink(),path
        path.write_text(path.read_text().replace(str(base),str(harness)))
    lock=yaml.safe_load((base/'pubspec.lock').read_text().replace(str(base),str(harness)))
    for entry in graph['packages']:
        name=entry['name'];record=original['packages'].get(name)
        if not record or record['source']!='hosted':continue
        uri=urlparse(urljoin(graph_file.as_uri(),entry['rootUri']))
        assert uri.scheme=='file'
        source=Path(unquote(uri.path)).resolve()
        dest=cache/'hosted/pub.dev'/source.name
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copytree(source,dest)
        expected=record['description']['sha256']
        hashes=cache/'hosted-hashes/pub.dev';hashes.mkdir(parents=True,exist_ok=True)
        (hashes/(source.name+'.sha256')).write_text(expected)
    pending=list(DIRECT);added={}
    while pending:
        name=pending.pop()
        if name in lock['packages']:continue
        record=copy.deepcopy(production[name])
        assert record['source']=='hosted',(name,record['source'])
        if name in PINNED:assert record['version']==PINNED[name]
        version=record['version'];expected=record['description']['sha256']
        archive=out/'downloads'/f'{name}-{version}.tar.gz'
        run('download-'+name,['curl','--fail','--location','--retry','3','--max-time','300',
             '--output',str(archive),f'https://pub.dev/api/archives/{name}-{version}.tar.gz'],out)
        assert sha(archive)==expected,(name,sha(archive),expected)
        dest=cache/'hosted/pub.dev'/f'{name}-{version}';dest.mkdir()
        with tarfile.open(archive,'r:gz') as bundle:
            for member in bundle.getmembers():
                path=Path(member.name)
                assert not path.is_absolute() and '..' not in path.parts,member.name
                assert member.isfile() or member.isdir(),member.name
            bundle.extractall(dest,filter='data')
        hashes=cache/'hosted-hashes/pub.dev';hashes.mkdir(parents=True,exist_ok=True)
        (hashes/f'{name}-{version}.sha256').write_text(expected)
        record['dependency']='direct main' if name in DIRECT else 'transitive'
        lock['packages'][name]=record;added[name]=record
        package=yaml.safe_load((dest/'pubspec.yaml').read_text())
        pending.extend(dep for dep in package.get('dependencies',{}) if dep not in lock['packages'])
        receipt['downloaded_packages'].append({'name':name,'version':version,'archive_sha256':expected,
            'production_lock_entry':production[name]});save()
    manifest=yaml.safe_load((harness/'pubspec.yaml').read_text())
    for name in DIRECT:manifest['dependencies'][name]=production[name]['version']
    (harness/'pubspec.yaml').write_text(yaml.safe_dump(manifest,sort_keys=False))
    lock['packages']=dict(sorted(lock['packages'].items()))
    (harness/'pubspec.lock').write_text(yaml.safe_dump(lock,sort_keys=False))
    receipt['seed_lock_sha256']=sha(harness/'pubspec.lock');save()
    env=os.environ.copy();env.update(FLUTTER_ROOT=str(sdk),PUB_CACHE=str(cache),TMPDIR=str(out/'tmp'),
        XDG_CONFIG_HOME=str(out/'config'),CI='true',DART_SUPPRESS_ANALYTICS='true',FLUTTER_SUPPRESS_ANALYTICS='true')
    command=[str(sdk/'bin/cache/dart-sdk/bin/dart'),str(sdk/'bin/cache/flutter_tools.snapshot'),
             'pub','get','--offline','--enforce-lockfile']
    run('service-locked-resolution',command,harness,env)
    resolved=yaml.safe_load((harness/'pubspec.lock').read_text())
    assert resolved==lock,'Package identities or classifications changed from seeded locked graph'
    frozen=sha(harness/'pubspec.lock')
    run('service-locked-resolution-repeat',command,harness,env)
    assert sha(harness/'pubspec.lock')==frozen
    newgraph=json.loads((harness/'.dart_tool/package_config.json').read_text())
    assert newgraph['flutterRoot']==sdk.as_uri() and newgraph['flutterVersion']=='3.47.8'
    assert (harness/'test/office_document_service_test.dart').resolve()==repo/'test/office_document_service_test.dart'
    for name,value in base_before.items():assert sha(base/name)==value,name
    for name,value in runtime_before.items():assert sha(sdk/name)==value,name
    receipt.update(status='passed',harness=str(harness),pub_cache=str(cache),
        final_package_count=len(newgraph['packages']),final_lock_sha256=frozen,
        additional_package_names=sorted(added),original_package_identities_preserved=True,
        new_packages_match_production_lock=True,base_inputs_unchanged=True,runtime_inputs_unchanged=True,
        package_config_sha256=sha(harness/'.dart_tool/package_config.json'))
    save();print(json.dumps({'status':'passed','packages':len(newgraph['packages']),'added':sorted(added)}),flush=True)

if __name__=='__main__':main()

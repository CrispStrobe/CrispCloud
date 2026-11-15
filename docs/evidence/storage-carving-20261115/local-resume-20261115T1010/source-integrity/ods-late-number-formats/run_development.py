#!/usr/bin/env python3
"""Record focused development checks while reconciling the canonical merge."""
from pathlib import Path
import concurrent.futures,datetime,gzip,hashlib,importlib.util,json,os,subprocess,time
repo=Path('/workspace/scratch/aed049b7e8bd/canonical/quds_office_suite')
cwd=repo/'packages/quds_office_engine'
out=Path(__file__).resolve().parent
owned=['packages/quds_office_engine/lib/src/sheet/styles/sml_styles.dart','packages/quds_office_engine/test/sheet_time_number_format_test.dart']
inputs=[*owned,'pubspec.lock','.dart_tool/package_config.json','.dart_tool/package_graph.json']
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def encode(x): return (json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def sha(b): return hashlib.sha256(b).hexdigest()
def snapshot(dest):
 result={}
 for name in inputs:
  p=repo/name
  if p.is_file():
   b=p.read_bytes(); q=dest/(name+'.gz'); q.parent.mkdir(parents=True,exist_ok=True); q.write_bytes(gzip.compress(b,mtime=0));result[name]={'size':len(b),'sha256':sha(b)}
  else: result[name]={'missing':True}
 return result
before=snapshot(out/'inputs-before')
base={'scope':'Focused development checks on the canonical merge working tree; not a clean-commit app qualification gate.','started_at':now(),'head':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),'merge_head':subprocess.check_output(['git','-C',str(repo),'rev-parse','MERGE_HEAD'],text=True).strip(),'cwd':str(cwd),'before_inputs':before,'environment':{k:os.environ[k] for k in ['PATH','FLUTTER_ROOT','PUB_CACHE','TMPDIR','CARGO_HOME'] if k in os.environ}}
suites=['test/sheet_time_number_format_test.dart','test/sheet_formula_test.dart','test/sheet_authored_number_format_test.dart']
commands={'tests':['dart','test','--reporter','json',*suites],'analysis':['dart','analyze','--fatal-infos','--fatal-warnings','lib/src/sheet/styles/sml_styles.dart','test/sheet_time_number_format_test.dart']}
def run(item):
 name,cmd=item; start=time.monotonic()
 with (out/(name+'.stdout.log')).open('wb') as stdout,(out/(name+'.stderr.log')).open('wb') as stderr:
  r=subprocess.run(cmd,cwd=cwd,stdout=stdout,stderr=stderr)
 return name,{'command':cmd,'returncode':r.returncode,'elapsed_seconds':time.monotonic()-start}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: results=dict(pool.map(run,commands.items()))
after=snapshot(out/'inputs-after')
helper=Path('/workspace/scratch/aed049b7e8bd/CrispCloud/docs/evidence/storage-delta-queue-20261114/run_delta_qualification.py')
spec=importlib.util.spec_from_file_location('machine_receipts',helper);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
summary=module.parse_machine(out/'tests.stdout.log',repo,['packages/quds_office_engine/'+p for p in suites]);(out/'test-summary.json').write_bytes(encode(summary))
base.update({'finished_at':now(),'after_inputs':after,'owned_source_and_resolution_inputs_unchanged':before==after,'commands':results,'test_totals':summary['totals'],'done_success':summary['done_success']})
(out/'receipt.json').write_bytes(encode(base))
(out/'artifacts-sha256.json').write_bytes(encode({str(p.relative_to(out)):{'size':p.stat().st_size,'sha256':sha(p.read_bytes())} for p in sorted(out.rglob('*')) if p.is_file() and p.name!='artifacts-sha256.json'}))
print(json.dumps({'results':results,'test_totals':summary['totals'],'inputs_unchanged':before==after,'done_success':summary['done_success']},indent=2))
raise SystemExit(0 if all(r['returncode']==0 for r in results.values()) and before==after and summary['done_success'] else 1)

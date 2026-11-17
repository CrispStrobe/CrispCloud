#!/usr/bin/env python3
"""Execute the prepared source-bound canonical run after runtime readiness."""
import datetime,hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
plan=json.loads((ROOT/'canonical-invocation.json').read_text())
runner=Path(plan['command'][1])
output=runner.parent
actual=hashlib.sha256(runner.read_bytes()).hexdigest()
assert actual==plan['expected_runner_sha256'],(actual,plan['expected_runner_sha256'])
assert not (output/'receipt.json').exists(),'Preserve prior receipts before retrying.'
env=os.environ.copy()
env.update(plan['environment'])
Path(env['QUDS_ALIAS_RENDER_OUTPUT']).mkdir(exist_ok=True)
plan['started_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
plan['status']='running'
(output/'invocation.json').write_text(json.dumps(plan,indent=2)+'\n')
with (output/'execution.log').open('w') as log:
 result=subprocess.run(plan['command'],env=env,stdout=log,stderr=subprocess.STDOUT)
plan['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
plan['exit_code']=result.returncode
plan['status']='completed' if result.returncode==0 else 'failed'
(output/'invocation.json').write_text(json.dumps(plan,indent=2)+'\n')
print(json.dumps({'exit_code':result.returncode,'output':str(output),'status':plan['status']}),flush=True)
sys.exit(result.returncode)

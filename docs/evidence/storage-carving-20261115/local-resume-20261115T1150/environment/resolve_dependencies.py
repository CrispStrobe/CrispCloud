from pathlib import Path
import json,subprocess,sys,datetime
r=Path(__file__).resolve().parent
repo=r.parent/'CrispCloud'
steps=[('01-app-locked','.',True,['flutter','--no-version-check','--suppress-analytics','pub','get','--enforce-lockfile']),('02-engine-dev','packages/quds_office_engine',False,['dart','pub','get']),('03-editor-dev','packages/quds_office_editor',False,['flutter','--no-version-check','--suppress-analytics','pub','get']),('04-parser-dev','packages/legacy_doc_parser',False,['dart','pub','get']),('05-cli-locked','cli',True,['dart','pub','get','--enforce-lockfile'])]
summary=[]
for name,cwd,locked,cmd in steps:
 out=r/'receipts/resolution'/name
 print('starting '+name,flush=True)
 args=[sys.executable,str(r/'resolution-runner.py'),'--repo',str(repo),'--cwd',cwd,'--output',str(out)]
 if locked:args+=['--enforce-lock']
 p=subprocess.run(args+['--']+cmd)
 summary.append(dict(name=name,returncode=p.returncode,receipt=json.loads((out/'receipt.json').read_text())))
 (r/'receipts/resolution-summary.json').write_text(json.dumps(dict(recorded_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),steps=summary),indent=2)+'\n')
 if p.returncode:sys.exit(p.returncode)
print('all dependency graphs resolved',flush=True)

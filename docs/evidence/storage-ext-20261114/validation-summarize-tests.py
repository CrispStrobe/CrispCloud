#!/usr/bin/env python3
from pathlib import Path
import argparse
import collections
import hashlib
import json

p=argparse.ArgumentParser(); p.add_argument('label'); a=p.parse_args()
root=Path(__file__).resolve().parent/'logs'
path=root/(a.label+'-events.json')
events=[json.loads(line) for line in path.read_text().splitlines()]
tests={e['test']['id']:e['test'] for e in events if e['type']=='testStart'}
done=[e for e in events if e['type']=='testDone' and not e['hidden']]
results=collections.Counter('skipped' if e['skipped'] else e['result'] for e in done)
summary={
 'label':a.label,
 'passed':results['success'],'failed':results['failure']+results['error'],
 'skipped':results['skipped'], 'total':len(done),
 'files':[e['suite']['path'] for e in events if e['type']=='suite'],
 'failures':[{'test':tests[e['testID']]['name'],'result':e['result']} for e in done if e['result']!='success' and not e['skipped']],
 'skips':[{'test':tests[e['testID']]['name'],'reason':tests[e['testID']].get('metadata',{}).get('skipReason')} for e in done if e['skipped']],
 'run_success':next((e['success'] for e in reversed(events) if e['type']=='done'),None),
 'events_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
}
(root/(a.label+'-summary.json')).write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))

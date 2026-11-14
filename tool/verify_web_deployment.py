#!/usr/bin/env python3
"""Require a published web receipt to identify the exact reviewed commit."""
import argparse
import json
import re
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--url', required=True)
parser.add_argument('--commit', required=True)
parser.add_argument('--attempts', type=int, default=15)
args = parser.parse_args()
if not re.fullmatch(r'[0-9a-f]{40}', args.commit) or not 1 <= args.attempts <= 30:
    parser.error('Expected a full commit SHA and 1–30 attempts.')
url = args.url.rstrip('/') + '/deployment.json?commit=' + args.commit
last = 'No deployment response'
for attempt in range(args.attempts):
    result = subprocess.run(
        ['curl', '--fail', '--silent', '--show-error', '--location',
         '--max-time', '20', '--max-filesize', '65536', url],
        capture_output=True, text=True, timeout=25,
    )
    try:
        receipt = json.loads(result.stdout) if result.returncode == 0 else {}
        if isinstance(receipt, dict) and receipt.get('commit') == args.commit:
            print(json.dumps({'url': args.url, 'commit': args.commit,
                              'version': receipt.get('version'), 'verified': True}))
            break
        last = 'Deployment receipt does not identify the requested commit.'
    except ValueError:
        last = 'Deployment has not published a valid JSON receipt.'
    if result.returncode:
        last = result.stderr.strip()[:300]
    print(f'Attempt {attempt + 1}/{args.attempts}: {last}', flush=True)
    if attempt + 1 < args.attempts:
        time.sleep(5)
else:
    raise SystemExit(last)

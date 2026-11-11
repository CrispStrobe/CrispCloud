#!/usr/bin/env python3
"""Check the pinned office patch set for drift, optionally against a fork checkout."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, help='local quds_office_suite checkout')
args = p.parse_args()
manifest = json.loads((ROOT/'tool/office_fidelity_manifest.json').read_text())
failures = []
for name, expected in manifest['files'].items():
    local = ROOT/name
    if not local.is_file() or hashlib.sha256(local.read_bytes()).hexdigest() != expected:
        failures.append(f'vendor drift: {name}')
    if args.source:
        upstream = args.source/name
        if not upstream.is_file() or upstream.read_bytes() != local.read_bytes():
            failures.append(f'fork mismatch: {name}')
if failures:
    raise SystemExit('\n'.join(failures))
print(f"Verified {len(manifest['files'])} office files at {manifest['source_commit']}.")

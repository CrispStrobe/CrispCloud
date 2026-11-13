#!/usr/bin/env python3
"""Reseal altered outer hashes and require internal evidence checks to fail."""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

import verify


HERE = Path(__file__).resolve().parent


def update_json(records, name, change):
    value = json.loads(records[name])
    change(value)
    records[name] = (json.dumps(value, indent=2) + '\n').encode()


def main():
    with contextlib.redirect_stdout(io.StringIO()):
        verify.verify(HERE)
    with tarfile.open(HERE / 'records.tar.xz') as archive:
        original = {member.name: archive.extractfile(member).read() for member in archive}
    rejected = []

    def control(name, change):
        records = dict(original)
        change(records)
        with tempfile.TemporaryDirectory(prefix='app-evidence-control-', dir=os.environ.get('TMPDIR')) as temp:
            target = Path(temp)
            for filename in ('README.md', 'verify.py', 'test_verifier.py'):
                shutil.copyfile(HERE / filename, target / filename)
            manifest = {'schemaVersion': 1, 'files': {
                key: {'sha256': verify.sha(data), 'bytes': len(data)} for key, data in records.items()}}
            manifest_bytes = (json.dumps(manifest, indent=2) + '\n').encode()
            (target / 'manifest.json').write_bytes(manifest_bytes)
            with tarfile.open(target / 'records.tar.xz', 'w:xz', preset=0) as archive:
                for key, data in records.items():
                    member = tarfile.TarInfo(key)
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
            raw = (target / 'records.tar.xz').read_bytes()
            receipt = json.loads((HERE / 'receipt.json').read_bytes())
            receipt.update(archiveBytes=len(raw), archiveSha256=verify.sha(raw),
                           manifestSha256=verify.sha(manifest_bytes), recordCount=len(records),
                           uncompressedRecordBytes=sum(map(len, records.values())))
            (target / 'receipt.json').write_text(json.dumps(receipt))
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    verify.verify(target)
            except (AssertionError, KeyError):
                rejected.append(name)
            else:
                raise RuntimeError('Accepted resealed corruption: ' + name)

    summary = json.loads(original['final/summary.json'])
    for command in summary['commands']:
        def unrelated(records, name=command['name']):
            update_json(records, 'final/' + name + '.command.json', lambda c: c.update(argv=['true']))
            update_json(records, 'final/summary.json', lambda s: next(c for c in s['commands']
                        if c['name'] == name).update(argv=['true']))
        control('unrelated actual command: ' + command['name'], unrelated)
    control('stale cohort events hash', lambda r: update_json(r, 'cohort/results/summary.json',
            lambda c: c['files']['events.jsonl'].update(sha256='0' * 64)))
    control('changed post-run source', lambda r: update_json(r, 'final/source-after.json',
            lambda s: s.update(status=' M pubspec.yaml')))
    control('failed actual native assertion', lambda r: update_json(r, 'final/native.stdout',
            lambda n: n['checks'].update(sourceUnchanged=False)))
    control('extra policy decision change', lambda r: update_json(r, 'integration/final-policy.json',
            lambda p: p.update(uses_non_exempt_encryption=not p['uses_non_exempt_encryption'])))
    control('new unreviewed policy key', lambda r: update_json(r, 'integration/final-policy.json',
            lambda p: p.update(new_policy_decision='changed')))
    control('stale retained policy copy', lambda r: update_json(r, 'integration/final-policy.json',
            lambda p: p.update(reviewed_source_sha256='0' * 64)))
    optimized = subprocess.run([sys.executable, '-O', str(HERE / 'verify.py')], capture_output=True, text=True)
    if optimized.returncode != 1 or 'requires assertions' not in optimized.stderr:
        raise RuntimeError('Optimized Python did not fail explicitly')
    print(json.dumps({'validEvidenceAccepted': True, 'resealedCorruptionsRejected': len(rejected),
                      'optimizationRejected': True, 'controls': rejected}, indent=2))


if __name__ == '__main__':
    main()

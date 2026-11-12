#!/usr/bin/env python3
"""Verify the retained, lossless app Word continuation evidence."""
from __future__ import annotations

import gzip
import hashlib
import json
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    root = Path(__file__).resolve().parent
    receipt = json.loads((root / 'receipt.json').read_text())
    assert digest(Path(__file__).read_bytes()) == receipt['verificationHelperSha256']
    records = {}
    for name, expected in receipt['artifacts'].items():
        assert Path(name).name == name and name.endswith('.gz'), name
        packed = (root / name).read_bytes()
        assert len(packed) == expected['compressedBytes'], name
        assert digest(packed) == expected['compressedSha256'], name
        raw = gzip.decompress(packed)
        assert len(raw) == expected['bytes'], name
        assert digest(raw) == expected['sha256'], name
        assert expected['originalName'] not in records, name
        records[expected['originalName']] = raw
    summary = json.loads(records['cohort-summary.json'])
    before = json.loads(records['cohort-inputs-before.json'])
    after = json.loads(records['cohort-inputs-after.json'])
    assert summary['success'] and summary['cohortCompleteWithoutSkips']
    assert summary['sourceAndDependenciesUnchanged']
    assert before['files'] == after['files']
    assert before['fileCount'] == len(before['files']) == receipt['capturedInputCount']
    assert before['appCommit'] == receipt['measuredLocalAppCommit']
    assert before['appWorktreeStatus'] == receipt['measuredWorktreeStatus'] == ''
    assert summary['testCount'] == receipt['cohort']['testCount']
    assert summary['suites'] == receipt['cohort']['suites']
    for suite in summary['suites'].values():
        assert suite['passed'] > 0 and suite['failed'] == suite['skipped'] == 0
    events = [json.loads(line) for line in records['cohort-events.jsonl'].splitlines()]
    done = [event for event in events if event['type'] == 'done']
    assert len(done) == 1 and done[0]['success']
    completed = [event for event in events if event['type'] == 'testDone'
                 and not event.get('hidden', False)]
    assert len(completed) == summary['testCount']
    assert all(event['result'] == 'success' and not event.get('skipped')
               for event in completed)
    for name, expected in summary['files'].items():
        raw = records['cohort-' + name]
        assert digest(raw) == expected['sha256'] and len(raw) == expected['bytes'], name
    native = json.loads(records['native.json'])
    assert native == receipt['nativeChecks']
    assert len(native['checks']) == 13 and all(native['checks'].values())
    assert before['parserUpstream']['commit'] == receipt['parser']['commit']
    assert before['parserUpstream']['patches'] == []
    remote = receipt['remoteEquivalentCheckpoint']
    assert remote and remote['tree'] == receipt['measuredAppTree']
    print(f"Verified {len(records)} lossless records; {summary['testCount']} app tests, "
          f"{len(native['checks'])} native checks, {before['fileCount']} unchanged inputs.")


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Verify lossless final app acceptance and the bounded source-identity audit."""
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
    for state in (before, after):
        assert state['appCommit'] == receipt['measuredRemoteAppCommit']
        assert state['appWorktreeStatus'] == receipt['measuredWorktreeStatus'] == ''
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
    assert before['parserUpstream']['commit'] == receipt['parser']['commit']
    assert before['parserUpstream']['patches'] == []

    native = json.loads(records['native.json'])
    assert native == receipt['nativeChecks']
    assert len(native['checks']) == 13 and all(native['checks'].values())
    assert native['limitations'] == ['partialFormatting']
    assert 'Portable Office JavaScript smoke passed:' in records['portable-web.log'].decode()
    production = json.loads(records['production-package_config.json'])
    assert len(production['packages']) == receipt['productionPackageCount']

    acceptance_before = json.loads(records['acceptance-inputs-before.json'])
    acceptance_after = json.loads(records['acceptance-inputs-after.json'])
    assert acceptance_before == acceptance_after
    assert acceptance_before['commit'] == receipt['measuredRemoteAppCommit']
    assert acceptance_before['tree'] == receipt['measuredAppTree']
    assert acceptance_before['status'] == ''
    assert acceptance_before['files'] == receipt['extraInputHashes']
    assert digest(records['production-package_config.json']) == (
        acceptance_before['productionPackageConfiguration']['sha256'])
    commands = json.loads(records['acceptance-commands.json'])
    assert commands == receipt['acceptanceCommands']
    assert commands and all(item['exitCode'] == 0 for item in commands)
    attempt = json.loads(records['portable-web-initial-attempt.json'])
    assert receipt['initialAttempts'] == [attempt]
    assert attempt['exitCode'] == 1
    assert "No such file or directory: '/usr/bin/node'" in (
        records['portable-web-initial-attempt.log'].decode())
    for key, name in [('guardedSync', 'sync-controls-exact.log'),
                      ('appleExportPreflight', 'apple-preflight-controls-exact.log'),
                      ('cryptoReleaseEvidence', 'crypto-evidence-controls-exact.log'),
                      ('ebookSources', 'ebook-source-controls-exact.log')]:
        control = receipt['sourceControls'][key]
        log = records[name].decode()
        count = control['passed'] + control['skipped']
        assert f'Ran {count} tests in ' in log
        expected = f"OK (skipped={control['skipped']})" if control['skipped'] else 'OK'
        assert log.rstrip().endswith(expected)
    ebook = json.loads(records['ebook-source-verification-exact.log'])
    assert ebook['files_verified'] == receipt['ebookSourceCheck']['fileCount']
    assert ebook['revision'] == receipt['ebookSourceCheck']['commit']
    assert ebook['resolved_bytes_verified']
    assert f"Verified {receipt['officeFileCount']} Office files" in (
        records['source-verification-exact.log'].decode())
    assert receipt['parser']['commit'] in records['source-verification-exact.log'].decode()
    assert records['release-input-check-exact.log'].decode().startswith('Crypto release inputs checked;')

    audit_bytes = (root / 'source-audit.json').read_bytes()
    assert digest(audit_bytes) == receipt['sourceAuditSha256']
    audit = json.loads(audit_bytes)
    assert audit['parserCommit'] == receipt['parser']['commit']
    assert audit['parserTree'] == receipt['parser']['tree']
    assert audit['officeFileCount'] == receipt['officeFileCount']
    assert audit['parserFileCount'] == receipt['parserFileCount']
    assert audit['qudsCommit'] == receipt['qudsCommit']
    assert audit['unchangedNonParserOfficeFileCount'] == receipt['unchangedNonParserFileCount']
    policy_before = json.loads(records['policy-before.json'])
    policy_after = json.loads(records['policy-after.json'])
    permitted = {'inventory_sha256', 'reviewed_source_sha256'}
    assert {key for key in policy_before if policy_before[key] != policy_after[key]} == permitted
    assert set(policy_before) == set(policy_after)
    assert sorted(set(policy_before) - permitted) == audit['preservedPolicyFields']
    inventory_before = json.loads(records['inventory-before.json'])
    inventory_after = json.loads(records['inventory-after.json'])
    assert set(inventory_before) == set(inventory_after)
    assert all(inventory_before[key] == inventory_after[key]
               for key in inventory_before if key != 'reviewed_files')
    added = set(inventory_after['reviewed_files']) - set(inventory_before['reviewed_files'])
    assert added == set(audit['addedReviewedRuntimePaths'])
    assert set(inventory_before['reviewed_files']) <= set(inventory_after['reviewed_files'])
    for direction, policy in [('before', policy_before), ('after', policy_after)]:
        assert digest(records[f'policy-{direction}.json']) == audit[direction]['policySha256']
        assert digest(records[f'inventory-{direction}.json']) == audit[direction]['inventorySha256']
        assert policy['inventory_sha256'] == audit[direction]['inventorySha256']
        assert policy['reviewed_source_sha256'] == audit[direction]['reviewedSourceSha256']
        assert policy['pubspec_lock_sha256'] == audit[direction]['pubspecLockSha256']
    assert audit['before']['pubspecLockSha256'] == audit['after']['pubspecLockSha256']
    for changed in audit['reviewedSourceChanges']:
        assert changed['afterSha256'] == receipt['extraInputHashes'][changed['path']]['sha256']
    for path, expected in audit['unchangedSourcePlists'].items():
        assert expected == receipt['extraInputHashes'][path]['sha256']
    print(f"Verified {len(records)} lossless records on exact remote app commit "
          f"{receipt['measuredRemoteAppCommit']}; {summary['testCount']} app tests, "
          f"{len(native['checks'])} native checks, {before['fileCount']} unchanged cohort inputs, "
          f"{len(audit['reviewedSourceChanges'])} reviewed source changes.")


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Verify bounded current-main evidence without replaying acceptance commands."""
import gzip
import hashlib
import json
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    root = Path(__file__).resolve().parent
    receipt = json.loads((root / 'receipt.json').read_text())
    assert sha(Path(__file__).read_bytes()) == receipt['verifierSha256']
    records = {}
    for name, record in receipt['records'].items():
        assert Path(name).name == name and name.endswith('.gz')
        compressed = (root / name).read_bytes()
        assert len(compressed) == record['compressedBytes']
        assert sha(compressed) == record['compressedSha256']
        raw = gzip.decompress(compressed)
        assert len(raw) == record['bytes'] and sha(raw) == record['sha256']
        records[record['originalName']] = raw
    load = lambda name: json.loads(records[name])
    before, after = load('baseline-source-before.json'), load('baseline-source-after.json')
    assert before == after
    assert before['appCommit'] == receipt['measuredAppCommit']
    assert before['appTree'] == receipt['measuredAppTree']
    assert before['status'] == '' and before['parserUpstream']['patches'] == []
    assert before['parserUpstream']['commit'] == receipt['parserCommit']
    summary = load('cohort-summary.json')
    inputs_before, inputs_after = load('cohort-inputs-before.json'), load('cohort-inputs-after.json')
    assert summary['success'] and summary['cohortCompleteWithoutSkips']
    assert summary['sourceAndDependenciesUnchanged']
    assert summary['testCount'] == receipt['cohortTestCount']
    assert inputs_before['files'] == inputs_after['files']
    assert inputs_before['fileCount'] == len(inputs_before['files']) == receipt['cohortInputCount']
    assert inputs_before['appCommit'] == inputs_after['appCommit'] == receipt['measuredAppCommit']
    assert inputs_before['appWorktreeStatus'] == inputs_after['appWorktreeStatus'] == ''
    events = [json.loads(line) for line in records['cohort-events.jsonl'].splitlines()]
    done = [x for x in events if x['type'] == 'done']
    tests = [x for x in events if x['type'] == 'testDone' and not x.get('hidden')]
    assert len(done) == 1 and done[0]['success']
    assert len(tests) == summary['testCount']
    assert all(x['result'] == 'success' and not x.get('skipped') for x in tests)
    for name, expected in summary['files'].items():
        raw = records['cohort-' + name]
        assert len(raw) == expected['bytes'] and sha(raw) == expected['sha256']
    for name, counts in receipt['controls'].items():
        raw = records[name].decode()
        assert f"Ran {counts['passed'] + counts['skipped']} tests in " in raw
        ending = f"OK (skipped={counts['skipped']})" if counts['skipped'] else 'OK'
        assert raw.rstrip().endswith(ending)
    native = load('native.json')
    assert native == receipt['native']
    assert len(native['checks']) == 13 and all(native['checks'].values())
    assert 'partialFormatting' in native['limitations']
    assert 'Portable Office JavaScript smoke passed:' in records['portable-web.log'].decode()
    production = load('production-pub-get.json')
    assert production['exitCode'] == 0 and production['inputsUnchanged']
    assert production['inputHashesBefore'] == production['inputHashesAfter']
    assert production['appCommit'] == receipt['measuredAppCommit'] and production['appStatus'] == ''
    config = load('production-package_config.json')
    assert len(config['packages']) == receipt['productionPackageCount']
    dependencies = load('production-dependencies-verified.json')
    assert sha(records['production-package_config.json']) == dependencies['packageConfigSha256']
    assert len(dependencies['hostedHashesVerified']) == receipt['productionHostedPackagesVerified']
    assert sha(records['production-pubspec.lock']) == dependencies['lockfileSha256']
    policy, inventory = load('policy-before.json'), load('inventory-before.json')
    reviewed = load('reviewed-source-before.json')
    assert sha(records['policy-before.json']) == before['files']['docs/apple-export-policy.json']['sha256']
    assert sha(records['inventory-before.json']) == policy['inventory_sha256']
    assert reviewed['fileCount'] == len(reviewed['files']) == len(inventory['reviewed_files'])
    assert set(reviewed['files']) == set(inventory['reviewed_files'])
    assert sha(json.dumps(reviewed['files'], sort_keys=True, separators=(',', ':')).encode()) == (
        policy['reviewed_source_sha256'])
    assert policy['pubspec_lock_sha256'] == production['inputHashesAfter']['pubspec.lock']
    assert records['release-input-check.log'].decode().startswith('Crypto release inputs checked;')
    assert 'Missing or redirected source file: .dart_tool/package_config.json' in (
        records['release-input-check-preresolution.log'].decode())
    source_log = records['source-verification.log'].decode()
    assert f"Verified {receipt['officeFileCount']} Office files" in source_log
    assert receipt['parserCommit'] in source_log and receipt['qudsCommit'] in source_log
    ebook = load('ebook-source-verification.log')
    assert ebook['files_verified'] == receipt['ebookSource']['fileCount']
    assert ebook['revision'] == receipt['ebookSource']['commit'] and ebook['resolved_bytes_verified']
    flutter = load('flutter-source-recovery.json')
    index = load('flutter-release-index.json')
    assert flutter['officialRelease'] in index['releases']
    assert sha(records['flutter-release-index.json']) == (
        load('setup-flutter-release-metadata-corrected.json')['sha256'])
    assert flutter['frameworkCommit'] == flutter['officialRelease']['hash']
    assert flutter['archiveSha256'] == flutter['officialRelease']['sha256']
    assert flutter['archiveSha256'] == load('setup-flutter-sdk-archive-corrected.json')['sha256']
    assert flutter['flutterVersionMetadata']['flutterVersion'] == '3.47.8'
    assert flutter['flutterLauncherInvoked'] is False
    for name in receipt['recordedAcceptanceCommands']:
        command = load(name)
        assert command['exitCode'] == 0 and command['appCommit'] == receipt['measuredAppCommit']
    print(f"Verified {len(records)} lossless baseline records: {summary['testCount']} tests, "
          f"13 native assertions, {inputs_before['fileCount']} unchanged cohort inputs; "
          f"clean app {receipt['measuredAppCommit']}.")


if __name__ == '__main__':
    main()

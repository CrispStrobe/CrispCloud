#!/usr/bin/env python3
"""Verify this immutable app acceptance archive without running application code."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify(directory):
    if not __debug__:
        raise SystemExit('Evidence verification requires assertions; disable Python optimization and PYTHONOPTIMIZE.')
    receipt = json.loads((directory / 'receipt.json').read_text())
    assert receipt['schemaVersion'] == 1
    assert receipt['measuredAppCommit'] == 'e3eaaa32bafa869548b30c0938aec776e99ea44e'
    assert receipt['measuredAppTree'] == 'f7a9943e1790de253930fec3e12375277132fa3a'
    assert receipt['parserCommit'] == '74420eb2e0ec14401a0db5bcbb30ab6d202a2340'
    assert receipt['trackedSourceFileCount'] == 7257 and receipt['cohortInputCount'] == 1180
    assert receipt['managedOfficeFiles'] == 1369 and receipt['parserSourceFiles'] == 948
    manifest_bytes = (directory / 'manifest.json').read_bytes()
    assert sha(manifest_bytes) == receipt['manifestSha256'], 'Manifest changed'
    manifest = json.loads(manifest_bytes)
    assert manifest['schemaVersion'] == 1
    archive = directory / 'records.tar.xz'
    assert archive.stat().st_size == receipt['archiveBytes']
    assert sha(archive.read_bytes()) == receipt['archiveSha256'], 'Archive changed'
    assert sha((directory / 'verify.py').read_bytes()) == receipt['verifierSha256'], 'Verifier changed'
    assert sha((directory / 'test_verifier.py').read_bytes()) == receipt['selfTestSha256'], 'Verifier controls changed'
    assert sha((directory / 'README.md').read_bytes()) == receipt['readmeSha256'], 'README changed'
    records = {}
    with tarfile.open(archive, 'r:xz') as bundle:
        for member in bundle:
            path = PurePosixPath(member.name)
            assert member.isfile() and not path.is_absolute() and '..' not in path.parts
            assert member.name not in records, 'Duplicate archive member'
            assert member.name in manifest['files'], 'Unlisted archive member'
            expected = manifest['files'][member.name]
            assert member.size == expected['bytes'] and member.size < 32 * 1024 * 1024
            data = bundle.extractfile(member).read()
            assert sha(data) == expected['sha256'], member.name
            records[member.name] = data
    assert set(records) == set(manifest['files']), 'Missing archive member'
    assert len(records) == receipt['recordCount']
    assert sum(len(data) for data in records.values()) == receipt['uncompressedRecordBytes']
    load = lambda name: json.loads(records[name])
    summary = load('final/summary.json')
    before = load('final/source-before.json')
    after = load('final/source-after.json')
    assert before == after and before['status'] == ''
    assert before['commit'] == summary['sourceCommit'] == receipt['measuredAppCommit']
    assert before['tree'] == summary['sourceTree'] == receipt['measuredAppTree']
    assert len(before['files']) == summary['sourceFileCount'] == receipt['trackedSourceFileCount']
    assert summary['success'] and summary['trackedInputsUnchanged']
    expected_commands = {'cohort', 'portable-web', 'native', 'sync-controls',
                         'apple-preflight-controls', 'crypto-evidence-controls',
                         'ebook-source-controls', 'office-source-verification',
                         'ebook-source-verification', 'release-input-check'}
    command_names = [command['name'] for command in summary['commands']]
    assert len(command_names) == len(expected_commands) and set(command_names) == expected_commands
    recorded_commands = {name.removeprefix('final/').removesuffix('.command.json')
                         for name in records if name.startswith('final/') and name.endswith('.command.json')}
    assert recorded_commands == expected_commands | {'production-offline-resolution'}
    for command in summary['commands']:
        assert command == load('final/' + command['name'] + '.command.json')
        assert command['exitCode'] == 0 and command['sourceCommit'] == receipt['measuredAppCommit']
    root = '/workspace/scratch/c1ca2a1344e9'
    app = root + '/CrispCloud-layout-next'
    dart = root + '/toolchains/dart-3.13.7/dart-sdk/bin/dart'
    expected_argv = {
        'cohort': ['python', 'docs/evidence/word-continuation-7308125/run_word_cohort.py',
                   '--app', app, '--workspace', root + '/app-word-cohort-e3eaaa32',
                   '--dart', dart, '--pub-cache', root + '/toolchains/pub-cache'],
        'portable-web': ['python', 'tool/verify_portable_office_web.py', '--dart', dart],
        'native': [dart, '--packages=' + app + '/.dart_tool/package_config.json',
                   'tool/verify_legacy_word_structured.dart',
                   '/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/override/soffice'],
        'office-source-verification': ['python', 'tool/verify_office_fidelity.py',
                                      '--legacy-source', root + '/legacy-doc-parser', '--require-tracked'],
        'ebook-source-verification': ['python', 'tool/verify_ebook_sources.py'],
        'release-input-check': ['python', 'tool/crypto_release_evidence.py', '--check'],
    }
    for name, pattern in [('sync-controls', 'test_sync_*.py'),
                          ('apple-preflight-controls', 'test_apple_export_preflight.py'),
                          ('crypto-evidence-controls', 'test_crypto_release_evidence.py'),
                          ('ebook-source-controls', 'test_verify_ebook_sources.py')]:
        expected_argv[name] = ['python', '-m', 'unittest', 'discover', '-s', 'tool', '-p', pattern, '-v']
    for command in summary['commands']:
        assert command['argv'] == expected_argv[command['name']] and command['cwd'] == app, command['name']
    resolution = load('final/production-offline-resolution.command.json')
    assert resolution['name'] == 'production-offline-resolution' and resolution['exitCode'] == 0
    assert resolution['sourceCommit'] == receipt['measuredAppCommit']
    assert resolution['argv'] == [dart, 'pub', 'get', '--offline', '--enforce-lockfile'] and resolution['cwd'] == app
    assert sha(records['final/production-package_config.json']) == before['productionPackageConfigSha256']
    resolution_inputs = load('final/resolution-inputs.json')
    assert set(resolution_inputs) == {'pubspec.yaml', 'pubspec.lock', '.fvmrc'}
    assert all(digest == before['files'][name]['sha256'] for name, digest in resolution_inputs.items())
    for name in ('pubspec.yaml', 'pubspec.lock'):
        assert sha(records['final/production-' + name]) == before['files'][name]['sha256']
    cohort_before = load('cohort/results/inputs-before.json')
    cohort_after = load('cohort/results/inputs-after.json')
    cohort = load('cohort/results/summary.json')
    assert cohort_before == cohort_after and cohort_before['appWorktreeStatus'] == ''
    assert cohort_before['appCommit'] == receipt['measuredAppCommit']
    assert cohort_before['parserUpstream']['commit'] == receipt['parserCommit']
    assert len(cohort_before['files']) == receipt['cohortInputCount']
    assert cohort['success'] and cohort['testCount'] == receipt['cohortTests'] == 107
    assert cohort['cohortCompleteWithoutSkips'] and cohort['sourceAndDependenciesUnchanged']
    assert len(cohort['suites']) == 8
    assert all(item['failed'] == item['skipped'] == 0 for item in cohort['suites'].values())
    cohort_files = {name.removeprefix('cohort/results/') for name in records
                    if name.startswith('cohort/results/') and name != 'cohort/results/summary.json'}
    assert set(cohort['files']) == cohort_files
    for name, expected in cohort['files'].items():
        data = records['cohort/results/' + name]
        assert len(data) == expected['bytes'] and sha(data) == expected['sha256'], name
    events = [json.loads(line) for line in records['cohort/results/events.jsonl'].splitlines()]
    assert [event for event in events if event['type'] == 'done'][-1]['success'] is True
    completions = [event for event in events if event['type'] == 'testDone' and not event.get('hidden', False)]
    assert len(completions) == cohort['testCount'] == 107
    assert len({event['testID'] for event in completions}) == 107
    assert all(event['result'] == 'success' and not event.get('skipped', False) for event in completions)
    native = load('final/native.stdout')
    assert len(native['checks']) == 13 and all(native['checks'].values())
    assert set(native['checks']) == {'tableAndCells', 'bold', 'fontSize', 'fontColor', 'pageDimensions',
                                    'headersAndFootersPreserved', 'notesPreserved', 'imagesPreserved',
                                    'independentPdfInfo', 'independentPdfText', 'independentPdfImage',
                                    'sourceUnchanged', 'preparedPackageUnchanged'}
    assert native['limitations'] == ['partialFormatting']
    assert b'Portable Office JavaScript smoke passed:' in records['final/portable-web.stdout']
    for name, (count, skipped) in receipt['controlCounts'].items():
        log = records['final/' + name + '.stderr'].decode()
        assert f'Ran {count} tests' in log and ('OK' in log)
        assert (f'OK (skipped={skipped})' in log) if skipped else ('OK (skipped=' not in log)
    remote = load('integration/remote-source-verification.json')
    assert remote['commit'] == receipt['measuredAppCommit'] and remote['status'] == ''
    assert remote['tree'] == receipt['measuredAppTree']
    assert remote['exitCode'] == 0 and remote['argv'] == ['python', 'tool/verify_office_fidelity.py',
            '--legacy-source', root + '/parser-layout-next', '--require-tracked']
    assert f"Verified {receipt['managedOfficeFiles']} Office files".encode() in records['integration/remote-source-verification.stdout']
    policy_before = load('integration/base-policy.json')
    policy_after = load('integration/final-policy.json')
    assert set(policy_before) == set(policy_after), 'Policy fields added or removed'
    assert [key for key in policy_before if policy_before[key] != policy_after[key]] == ['reviewed_source_sha256']
    assert records['integration/base-crypto-inventory.json'] == records['integration/final-crypto-inventory.json']
    assert sha(records['integration/base-pubspec.lock']) == sha(records['final/production-pubspec.lock'])
    main_office = load('integration/base-office-manifest.json')
    final_office = load('integration/final-office-manifest.json')
    assert main_office['source_commit'] == final_office['source_commit'] == receipt['qudsCommit']
    non_parser = lambda manifest: {name: digest for name, digest in manifest['files'].items()
                                  if not name.startswith('packages/legacy_doc_parser/')}
    assert non_parser(main_office) == non_parser(final_office)
    assert len(final_office['files']) == receipt['managedOfficeFiles']
    assert final_office['standalone_sources']['packages/legacy_doc_parser']['commit'] == receipt['parserCommit']
    assert len(non_parser(final_office)) == 421
    for name, digest in final_office['files'].items():
        assert before['files'][name]['sha256'] == digest, name
    baseline = load('integration/base-source.json')
    assert baseline['commit'] == 'ec354cc3e6c11243bb66cbe9eb0763f15b72f7c1'
    for relative, base_record, final_record in [
        ('docs/apple-export-policy.json', 'base-policy.json', 'final-policy.json'),
        ('docs/crypto-inventory.json', 'base-crypto-inventory.json', 'final-crypto-inventory.json'),
        ('tool/office_fidelity_manifest.json', 'base-office-manifest.json', 'final-office-manifest.json'),
    ]:
        assert sha(records['integration/' + base_record]) == baseline['files'][relative]['sha256'], base_record
        assert sha(records['integration/' + final_record]) == before['files'][relative]['sha256'], final_record
    all_names = set(baseline['files']) | set(before['files'])
    changes = {name for name in all_names if baseline['files'].get(name) != before['files'].get(name)}
    assert {name for name in changes if not name.startswith('packages/legacy_doc_parser/')} == {
        'pubspec.yaml', 'tool/office_fidelity_manifest.json', 'docs/apple-export-policy.json'}
    assert len(changes) == 166
    assert load('integration/runtime-review.json')['adoptedParser'] == receipt['parserCommit']
    assert load('integration/runtime-review.json')['runtimeUnchangedFromReview'] is True
    flutter = load('recovery/flutter-minimal-recovery.json')
    assert flutter['archiveSha256'] == 'baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2'
    assert flutter['version']['frameworkVersion'] == '3.47.8'
    assert flutter['version']['frameworkRevision'] == '737ba8f885dc774b53b442759999a312c9461e4e'
    dart = load('recovery/dart-recovery.json')
    assert dart['binarySha256'] == cohort_before['dartExecutableSha256']
    print(f"Verified {len(records)} records: 107 app tests, 13 native assertions, "
          f"{receipt['managedOfficeFiles']} Office sources and {receipt['trackedSourceFileCount']} unchanged tracked inputs; "
          f"clean app {receipt['measuredAppCommit']}.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path, default=Path(__file__).resolve().parent)
    verify(parser.parse_args().directory.resolve())

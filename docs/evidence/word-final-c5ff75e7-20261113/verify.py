#!/usr/bin/env python3
"""Verify this immutable app acceptance archive without running application code."""
import argparse
from collections import Counter
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
    assert receipt['measuredAppCommit'] == '86d5a218853d8441afe8bc28f19cfe0adf4cd71e'
    assert receipt['measuredAppTree'] == '765bf752b0095233192d38e678941e7ca92a76b8'
    assert receipt['parserCommit'] == 'c5ff75e76163d9abbdd44a9f2a7c5ad210929289'
    assert receipt['parserTree'] == '25bd05c12fa2272a32ec2aaba2cc0117be5bed96'
    assert receipt['trackedSourceFileCount'] == 7573 and receipt['cohortInputCount'] == 1182
    assert receipt['managedOfficeFiles'] == 1679 and receipt['parserSourceFiles'] == 1258
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
    app = root + '/CrispCloud-final-next'
    dart = root + '/toolchains/dart-3.13.7/dart-sdk/bin/dart'
    expected_argv = {
        'cohort': ['python', 'docs/evidence/word-continuation-7308125/run_word_cohort.py',
                   '--app', app, '--workspace', root + '/app-word-cohort-86d5a218',
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
    expected_suite_counts = {
        'word_conversion_inspection_test.dart': 43,
        'legacy_word_structured_conversion_test.dart': 9,
        'legacy_word_structured_document_test.dart': 16,
        'legacy_word_structured_render_test.dart': 7,
        'legacy_word_structured_bounds_test.dart': 4,
        'legacy_word_sprm_regression_test.dart': 6,
        'legacy_word_document_test.dart': 9,
        'installed_office_converter_test.dart': 13,
    }
    expected_suite_paths = ['test/' + name for name in expected_suite_counts]
    cohort_workspace = root + '/app-word-cohort-86d5a218'
    assert cohort['version'] == 1 and cohort['exitCode'] == 0
    assert cohort['cwd'] == cohort_workspace
    assert cohort['command'] == [dart, 'test', *expected_suite_paths,
            '--concurrency=2', '--reporter=expanded',
            '--file-reporter=json:' + cohort_workspace + '/results/events.jsonl'], 'Cohort test command changed'
    assert cohort['expectedSuiteCount'] == cohort['executedSuiteCount'] == 8
    assert set(cohort['suites']) == set(expected_suite_counts), 'Cohort suite inventory changed'
    for name, passed in expected_suite_counts.items():
        assert cohort['suites'][name] == {'passed': passed, 'failed': 0, 'skipped': 0}, name
    cohort_files = {name.removeprefix('cohort/results/') for name in records
                    if name.startswith('cohort/results/') and name != 'cohort/results/summary.json'}
    assert set(cohort['files']) == cohort_files
    for name, expected in cohort['files'].items():
        data = records['cohort/results/' + name]
        assert len(data) == expected['bytes'] and sha(data) == expected['sha256'], name
    events = [json.loads(line) for line in records['cohort/results/events.jsonl'].splitlines()]
    done = [event for event in events if event['type'] == 'done']
    assert len(done) == 1 and done[0]['success'] is True
    suites = [event['suite'] for event in events if event['type'] == 'suite']
    assert len(suites) == 8 and len({suite['id'] for suite in suites}) == 8
    assert {suite['path'] for suite in suites} == set(expected_suite_paths), 'Cohort suite event paths changed'
    assert all(suite['platform'] == 'vm' for suite in suites)
    suite_by_id = {suite['id']: suite['path'].removeprefix('test/') for suite in suites}
    starts = [event['test'] for event in events if event['type'] == 'testStart']
    tests = {test['id']: test for test in starts}
    assert len(tests) == len(starts) == 115
    assert all(test['suiteID'] in suite_by_id and test['metadata']['skip'] is False for test in starts)
    all_completions = [event for event in events if event['type'] == 'testDone']
    assert len(all_completions) == len(tests)
    assert {event['testID'] for event in all_completions} == set(tests)
    assert all(event['result'] == 'success' and not event.get('skipped', False) for event in all_completions)
    completions = [event for event in events if event['type'] == 'testDone' and not event.get('hidden', False)]
    assert len(completions) == cohort['testCount'] == 107
    assert len({event['testID'] for event in completions}) == 107
    assert all(event['result'] == 'success' and not event.get('skipped', False) for event in completions)
    counts = Counter(suite_by_id[tests[event['testID']]['suiteID']] for event in completions)
    assert dict(counts) == expected_suite_counts, 'Cohort event suite totals changed'
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
    assert remote['cwd'] == root + '/CrispCloud-final-remote-check'
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
    assert baseline['commit'] == '6f2e3245b7971d620410a65e75bf54b04132319a'
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
    assert len(changes) == 340
    assert load('integration/runtime-review.json')['adoptedParser'] == receipt['parserCommit']
    assert load('integration/runtime-review.json')['runtimeUnchangedFromReview'] is True
    projection = load('integration/independent-projection-review.json')
    assert projection['commit'] == '907d3be3506cb8332bc556854a819d4d0c934a67'
    assert projection['tree'] == receipt['measuredAppTree']
    assert projection['parserPin'] == receipt['parserCommit'] and projection['parserTree'] == receipt['parserTree']
    assert projection['exactParserProjectionFiles'] == receipt['parserSourceFiles']
    assert projection['managedOfficeFiles'] == receipt['managedOfficeFiles']
    assert projection['retainedDiagnosticFiles'] == 9 and projection['unchangedNonParserOfficeFiles'] == 421
    assert projection['changedFiles'] == len(changes) and projection['worktreeStatus'] == ''
    assert set(projection['changedOutsideParser']) == {name for name in changes if not name.startswith('packages/legacy_doc_parser/')}
    assert projection['lockCryptoFvmrcUnchanged'] and projection['onlyPolicyChange'] == 'reviewed_source_sha256'
    previous_ci = load('integration/previous-hosted-ci.json')
    assert previous_ci['appCommit'] == baseline['commit']
    for name, run_id, workflow, job_names in [
        ('provider', 43383828311, 'provider-conformance.yml', {'conformance'}),
        ('office', 43383828350, 'office-fidelity.yml', {'host-roundtrip', 'external-schema'}),
    ]:
        run = previous_ci[name]['run']
        assert run['id'] == run_id and run['run_attempt'] == 1
        assert run['head_sha'] == baseline['commit'] and run['head_commit']['tree_id'] == baseline['tree']
        assert run['path'] == '.github/workflows/' + workflow
        assert run['status'] == 'completed' and run['conclusion'] == 'success'
        jobs = previous_ci[name]['jobs']['jobs']
        assert {job['name'] for job in jobs} == job_names and len(jobs) == len(job_names)
        assert all(job['run_id'] == run_id and job['status'] == 'completed' and job['conclusion'] == 'success' for job in jobs)
        assert all(step['status'] == 'completed' and step['conclusion'] == 'success' for job in jobs for step in job['steps'])
    runtime_ci = load('integration/runtime-provider-ci.json')
    run = runtime_ci['run']
    assert runtime_ci['appCommit'] == run['head_sha'] == receipt['measuredAppCommit']
    assert run['head_commit']['tree_id'] == receipt['measuredAppTree']
    assert run['id'] == 43388810612 and run['run_attempt'] == 1
    assert run['path'] == '.github/workflows/provider-conformance.yml'
    assert run['head_branch'] == 'checkpoint/app-final-next-20261113'
    assert run['status'] == 'completed' and run['conclusion'] == 'success'
    jobs = runtime_ci['jobs']['jobs']
    assert len(jobs) == 1 and jobs[0]['id'] == 131763541117 and jobs[0]['name'] == 'conformance'
    assert jobs[0]['run_id'] == run['id'] and jobs[0]['status'] == 'completed' and jobs[0]['conclusion'] == 'success'
    assert len(jobs[0]['steps']) == 15
    assert all(step['status'] == 'completed' and step['conclusion'] == 'success' for step in jobs[0]['steps'])
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

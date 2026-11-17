#!/usr/bin/env python3
"""Independently recount the final locked host qualification evidence."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import re
from urllib.parse import unquote, urlparse


BASE = Path(__file__).resolve().parent.parent
RUN = BASE / 'runtime-work/host/final-qualification-002'
HOST = '511361a4623e6ddf787b5cccfaed4ba14ae1899f'
CANONICAL = 'def52d84f3c3c5ce22c44d2620ecfa08d77780a7'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_text())


def aggregate(value):
    return sha(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def recount(command, expected_paths):
    parsed = []
    ignored = []
    for line in (RUN / command['log']).read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            ignored.append(line)
            continue
        if isinstance(event, dict) and 'type' in event:
            parsed.append(event)
    starts_list = [event['test'] for event in parsed if event['type'] == 'testStart']
    starts = {test['id']: test for test in starts_list}
    suites = {event['suite']['id']: event['suite'] for event in parsed if event['type'] == 'suite'}
    ends = [event for event in parsed if event['type'] == 'testDone']
    assert len(starts) == len(starts_list)
    assert len(ends) == len({event['testID'] for event in ends})
    assert set(starts) == {event['testID'] for event in ends}
    assert not [event for event in parsed if event['type'] == 'error']
    done = [event for event in parsed if event['type'] == 'done']
    assert len(done) == 1 and done[0]['success']
    def resolved(raw):
        parsed_uri = urlparse(raw)
        path = Path(unquote(parsed_uri.path) if parsed_uri.scheme == 'file' else raw)
        return (path if path.is_absolute() else Path(command['cwd']) / path).resolve()
    assert {resolved(suite['path']) for suite in suites.values()} == {resolved(path) for path in expected_paths}
    tests = []
    administrative = 0
    for event in ends:
        test = starts[event['testID']]
        name = test['name']
        if event.get('hidden') or name.startswith('loading ') or name.endswith('(setUpAll)') or name.endswith('(tearDownAll)'):
            administrative += 1
            continue
        assert event['result'] == 'success' and not event.get('skipped')
        tests.append({'name': name, 'suite': suites[test['suiteID']]['path']})
    assert tests
    return {'passed': len(tests), 'failed': 0, 'skipped': 0, 'administrative_events': administrative, 'all_started_tests_terminated': True, 'counts_by_file': dict(Counter(Path(row['suite']).name for row in tests)), 'tests': tests, 'unparsed_log_lines': ignored}


def main():
    receipt = load(RUN / 'receipt.json')
    assert receipt['status'] == 'passed'
    assert receipt['source_commit'] == receipt['head_at_completion'] == HOST
    assert receipt['canonical_source_commit'] == CANONICAL
    assert not receipt['historical_counts_reused']
    assert not receipt['github_actions_or_status_queried'] and not receipt['github_actions_awaited']
    for flag in ['all_commands_passed', 'test_stream_complete', 'analysis_config_restored', 'source_unchanged', 'dependencies_unchanged', 'tracked_inputs_unchanged', 'retained_cohorts_complete', 'python_cohort_complete', 'supplemental_stream_complete', 'supplemental_inputs_unchanged']:
        assert receipt[flag] is True, flag
    commands = receipt['commands']
    assert [row['name'] for row in commands] == receipt['expected_commands']
    assert len(commands) == len({row['name'] for row in commands}) == 11
    for row in commands:
        assert row['status'] == 'passed' and row['exit_code'] == 0 and not row.get('timed_out')
        assert sha((RUN / row['log']).read_bytes()) == row['log_sha256']
    by_name = {row['name']: row for row in commands}
    source_before = load(RUN / 'source-before.json')
    source_after = load(RUN / 'source-after.json')
    deps_before = load(RUN / 'dependencies-before.json')
    deps_after = load(RUN / 'dependencies-after.json')
    assert source_before == source_after
    assert deps_before == deps_after
    assert aggregate(source_before) == receipt['source_before_aggregate_sha256'] == receipt['source_after_aggregate_sha256']
    assert aggregate(deps_before) == receipt['dependencies_before_aggregate_sha256'] == receipt['dependencies_after_aggregate_sha256']
    assert len(source_before) == receipt['source_file_count']
    assert len(deps_before['dependency_files']) == receipt['dependency_file_count']
    assert deps_before['runtime_files']['bin/cache/dart-sdk/bin/dart'] == '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb'
    assert deps_before['runtime_files']['bin/cache/artifacts/engine/linux-x64/flutter_tester'] == '800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f'
    for path, expected in receipt['supplemental_probe_sha256'].items():
        assert sha(Path(path).read_bytes()) == expected
    host = recount(by_name['host-tests'], receipt['tests'])
    probes = recount(by_name['writer-host-probes'], receipt['supplemental_probe_paths'])
    expected = {'office_annotation_preview_test.dart': 8, 'office_document_service_test.dart': 41, 'office_proofing_licenses_test.dart': 2, 'office_zotero_test.dart': 21, 'office_zotero_citing_transport_test.dart': 16, 'office_zotero_ribbon_test.dart': 2}
    assert host['counts_by_file'] == expected == receipt['test_counts_by_file']
    assert host['passed'] == receipt['test_counts']['passed'] == 90
    assert probes['passed'] == receipt['supplemental_test_counts']['passed'] == 6
    python_log = (RUN / by_name['python-vendor-tests']['log']).read_text()
    python_ids = re.findall(r'^test_\S+ \(([^\n]+)\) \.\.\. ok$', python_log, re.M)
    assert len(python_ids) == len(set(python_ids)) == 28
    assert re.search(r'^Ran 28 tests in ', python_log, re.M)
    assert re.search(r'^OK\s*$', python_log, re.M)
    assert not re.search(r'\.\.\. (?:skipped|FAIL|ERROR)|^OK \(', python_log, re.M)
    assert receipt['passed_python_tests'] == 28
    generated = receipt['generated_format_exclusions']
    assert len(receipt['vendored_analysis_targets']) == 61
    assert len(receipt['vendored_format_targets']) == 43
    assert set(receipt['vendored_analysis_targets']) - set(receipt['vendored_format_targets']) == set(generated)
    repo = Path(receipt['source_repo'])
    for path, row in generated.items():
        assert sha((repo / path).read_bytes()) == row['sha256']
        assert (repo / path).read_text().startswith('// GENERATED by tool/proofing/')
        assert sha((repo / row['manifest']).read_bytes()) == row['manifest_sha256']
        manifest = load(repo / row['manifest'])
        assert manifest['generated_files'][str(Path(path).relative_to('packages/quds_office_engine'))] == row['sha256']
    assert len(generated) == 18
    correction = load(BASE / 'runtime-work/host/probe-contract-correction-independent-review.json')
    assert receipt['runner_sha256'] == correction['reviewed_runner_sha256']
    note = next(path for path in receipt['supplemental_probe_paths'] if path.endswith('/odt_note_host_test.dart'))
    assert receipt['supplemental_probe_sha256'][note] == correction['reviewed_note_probe_sha256']
    result = {'accepted': True, 'host_source': HOST, 'canonical_source': CANONICAL, 'host_tree': receipt['host_tree'], 'canonical_tree': receipt['canonical_tree'], 'receipt_sha256': sha((RUN / 'receipt.json').read_bytes()), 'reviewer_script_sha256': sha(Path(__file__).read_bytes()), 'all_11_command_logs_readback_verified': True, 'host_cohort': host, 'writer_probes': probes, 'python_passes': 28, 'python_test_ids': python_ids, 'total_substantive_test_passes': 124, 'skipped_or_failed_tests': 0, 'prior_cohort_preservation': 'All 80 prior Dart cases and 28 prior Python cases remain. Current document service has 41 cases (39 prior plus2), annotation adds8, and six separate writer probes pass.', 'source_input_count': len(source_before), 'dependency_input_count': len(deps_before['dependency_files']), 'runtime_input_count': len(deps_before['runtime_files']), 'source_dependencies_runtime_and_probe_inputs_unchanged': True, 'temporary_analysis_graph_restored': True, 'generated_format_exclusions_authenticated': 18, 'vendor_analysis_targets': 61, 'vendor_format_targets': 43, 'limitations': receipt['limitations'], 'test_execution_performed_by_reviewer': False}
    output = BASE / 'host-final-review/final-host-qualification-review.json'
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: result[key] for key in ['accepted', 'host_source', 'canonical_source', 'total_substantive_test_passes', 'skipped_or_failed_tests', 'source_input_count', 'dependency_input_count', 'runtime_input_count', 'all_11_command_logs_readback_verified']}, indent=2))


if __name__ == '__main__':
    main()

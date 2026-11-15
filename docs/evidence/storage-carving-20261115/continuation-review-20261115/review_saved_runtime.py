#!/usr/bin/env python3
"""Audit retained runtime receipts without relabeling them as a new execution.

Rehash all artifacts, compare every tracked non-evidence input and Git identity,
reparse original machine streams, and verify retained Office output identities.
Original package graphs/tool binaries are checked for recorded within-run
stability; this does not claim they are this workspace's dependency resolution.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def load(path):
    return json.loads(path.read_text())


def fingerprint(path):
    if path.is_symlink():
        data, kind = os.fsencode(os.readlink(path)), 'symlink'
    elif path.is_file():
        data, kind = path.read_bytes(), 'file'
    else:
        return {'kind': 'missing_or_nonfile'}
    return {'kind': kind, 'size': len(data), 'sha256': sha(data)}


def audit_artifacts(directory):
    manifest = load(directory / 'artifacts-sha256.json')
    actual = {str(p.relative_to(directory)) for p in directory.rglob('*')
              if p.is_file() and p != directory / 'artifacts-sha256.json'}
    invalid = []
    for name, expected in manifest.items():
        path = directory / name
        if (not path.resolve().is_relative_to(directory.resolve())
                or not path.is_file() or path.is_symlink()
                or {'sha256': sha(path.read_bytes()), 'size': path.stat().st_size} != expected):
            invalid.append(name)
    assert not invalid, (directory.name, 'invalid artifacts', invalid)
    assert actual == set(manifest), (directory.name, 'artifact inventory mismatch')
    return {'artifacts_verified': len(manifest),
            'manifest_sha256': sha((directory / 'artifacts-sha256.json').read_bytes()),
            'exact_manifest_inventory': True}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    repo = args.repo.resolve()
    git = lambda *argv: subprocess.check_output(['git', '-C', str(repo), *argv])
    review_head = git('rev-parse', 'HEAD').decode().strip()
    base = repo / 'docs/evidence/storage-carving-20261115/local-resume-20261115T1010'

    def source_tree(ref):
        result = {}
        for row in git('ls-tree', '-r', '-z', ref).split(b'\0'):
            if not row:
                continue
            identity, raw_path = row.split(b'\t', 1)
            name = os.fsdecode(raw_path)
            if not name.startswith('docs/evidence/'):
                result[name] = identity.decode()
        return result

    current_tree = source_tree(review_head)
    current = {name: fingerprint(repo / name) for name in sorted(current_tree)}
    assert not git('diff', '--name-only', 'HEAD', '--', '.', ':(exclude)docs/evidence/**')
    assert not git('ls-files', '--others', '--exclude-standard', '--', '.', ':(exclude)docs/evidence/**')

    def receipt(name, expected_success=True):
        directory = base / name
        artifacts = audit_artifacts(directory)
        meta = load(directory / 'metadata.json')
        before, after = [json.loads(gzip.decompress((directory / filename).read_bytes()))
                         for filename in ['inputs-before.json.gz', 'inputs-after.json.gz']]
        digest = sha(encode(before['entries']))
        assert before['entries'] == after['entries']
        assert digest == before['entries_sha256'] == after['entries_sha256']
        assert digest == meta['before_entries_sha256'] == meta['after_entries_sha256']
        assert before['count'] == after['count'] == meta['input_count'] == len(before['entries'])
        assert meta['before_tools'] == meta['after_tools']
        assert meta['input_changes'] == {'added': [], 'changed': [], 'removed': []}
        for phase in ['before_git', 'after_git']:
            assert meta[phase]['source_changes'] == meta[phase]['untracked_source'] == []
            assert source_tree(meta[phase]['tree']) == current_tree
            if expected_success:
                assert git('rev-parse', meta[phase]['head'] + '^{tree}').decode().strip() == meta[phase]['tree']
        assert all(before['entries'].get(name) == value for name, value in current.items())
        internal_tools = 0
        for path, expected in meta['before_tools'].items():
            if path.startswith(meta['repo'] + '/'):
                relative = path[len(meta['repo']) + 1:]
                if not relative.startswith(('cli/.dart_tool/', '.dart_tool/')):
                    assert sha((repo / relative).read_bytes()) == expected, relative
                    internal_tools += 1
        stable_git = all(meta['before_git'][key] == meta['after_git'][key]
                         for key in ['head', 'tree', 'source_changes', 'untracked_source'])
        assert meta['inputs_and_commit_stable'] is stable_git
        assert meta['returncode'] == 0
        assert meta['qualification_success'] is expected_success
        assert stable_git is expected_success
        command = load(directory / 'command.json')
        assert command['argv'] == meta['command'] and command['cwd'] == meta['cwd']
        return meta, {'gate': name, 'tested_head': meta['before_git']['head'],
                      **artifacts, 'source_resolution_digest': digest,
                      'recorded_inputs_and_tools_unchanged': True,
                      'recorded_head_and_tree_stable': stable_git,
                      'passing_head_commit_objects_verified': expected_success,
                      'current_tracked_source_paths_compared': len(current),
                      'source_git_blobs_and_modes_equal': True,
                      'source_bytes_equal': True,
                      'current_repository_tools_verified': internal_tools}

    parser_path = repo / 'docs/evidence/storage-delta-queue-20261114/run_delta_qualification.py'
    spec = importlib.util.spec_from_file_location('machine_parser', parser_path)
    parser = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(parser)
    rows = []
    for gate, cohort, suites_expected, tests_expected in [
        ('app-final', 'app', 49, 741),
        ('editor-final', 'editor', 7, 73),
        ('engine-final-2', 'engine', 17, 182),
    ]:
        meta, row = receipt(gate)
        directory = base / gate
        manifest = repo / f'docs/evidence/storage-carving-20261115/{cohort}-suites.txt'
        assert (directory / 'suites.txt').read_bytes() == manifest.read_bytes()
        suites = [line.strip() for line in manifest.read_text().splitlines() if line.strip()]
        assert len(suites) == len(set(suites)) == suites_expected == meta['suite_count']
        prefix = meta['repo'] + '/'
        arguments = [arg[len(prefix):] if arg.startswith(prefix) else arg
                     for arg in meta['command'] if arg.endswith('.dart')]
        assert arguments == suites
        assert meta['command'][0] == ('dart' if cohort == 'engine' else 'flutter')
        assert 'test' in meta['command'] and '--reporter' in meta['command'] and 'json' in meta['command']
        if cohort != 'engine':
            assert '--no-pub' in meta['command']
        parsed = parser.parse_machine(directory / 'stdout.jsonl', Path(meta['repo']), suites)
        saved = load(directory / 'summary.json')
        assert all(saved[key] == value for key, value in parsed.items())
        assert parsed['totals'] == {'tests': tests_expected, 'passed': tests_expected,
                                    'skipped': 0, 'failed': 0, 'other_results': 0, 'errors': 0}
        assert len(parsed['done_events']) == 1 and parsed['done_success']
        assert parsed['missing_suites'] == parsed['errors'] == []
        assert parsed['non_json_lines'] == parsed['non_object_json_lines'] == 0
        assert {item['path'] for item in parsed['suites']} == set(suites)
        assert all(item['observed'] and item['result'] == 'passed' for item in parsed['suites'])
        assert saved['unexpected_suites'] == saved['nonpassing_requested_suites'] == []
        assert saved['qualification_success'] is True
        events = [json.loads(line) for line in (directory / 'stdout.jsonl').read_text().splitlines()]
        starts = [event['test']['id'] for event in events if event['type'] == 'testStart']
        ends = [event['testID'] for event in events if event['type'] == 'testDone']
        assert len(starts) == len(set(starts)) == len(ends) == len(set(ends))
        assert set(starts) == set(ends)
        assert all(event.get('result') == 'success' and not event.get('skipped', False)
                   for event in events if event['type'] == 'testDone')
        row.update({'suites': suites_expected, 'tests': tests_expected,
                    'raw_machine_reparse_matches_saved_summary': True,
                    'exact_suite_manifest_and_command': True,
                    'no_skips_errors_or_unexpected_suites': True,
                    'no_duplicate_or_incomplete_test_events': True,
                    'hidden_completed_events': parsed['hidden_test_done'], 'success': True})
        rows.append(row)

    failed_meta, failed = receipt('engine-final', expected_success=False)
    assert failed_meta['before_git']['head'] != failed_meta['after_git']['head']
    assert failed_meta['before_git']['tree'] == failed_meta['after_git']['tree']
    assert load(base / 'engine-final/summary.json')['qualification_success'] is False
    failed.update({'included_in_acceptance': False,
                   'after_head': failed_meta['after_git']['head'],
                   'reason': 'HEAD changed during the recorded gate; retained as a rejected attempt. '
                             'Its before-head ac3b196f is not available remotely; its recorded tree '
                             'and source snapshot are verified, but its commit object is not claimed.'})

    oracle_meta, oracle = receipt('scripted-oracle-final')
    produced_dir = base / 'scripted-artifacts-final'
    oracle['produced_artifacts'] = audit_artifacts(produced_dir)
    summary = load(produced_dir / 'summary.json')
    expected = {f'{kind}/{name}.{ext}'
                for kind, ext in [('word', 'docx'), ('sheet', 'xlsx'), ('slide', 'pptx')]
                for name in ['edited', 'roundtrip-1', 'roundtrip-2', 'roundtrip-3']}
    output_hashes = {str(path.relative_to(produced_dir / 'produced')):
                    {'sha256': sha(path.read_bytes()), 'size': path.stat().st_size}
                    for path in (produced_dir / 'produced').rglob('*')
                    if path.suffix in ['.docx', '.xlsx', '.pptx']}
    assert set(output_hashes) == expected
    assert output_hashes == summary['before'] == summary['after']
    assert summary['success'] is summary['produced_outputs_unchanged'] is True
    report = load(produced_dir / 'produced/oracle-report.json')
    assert report == summary['oracle'] == {'exports': 12, 'failures': []}
    assert len(summary['commands']) == 2 and all(row['returncode'] == 0 for row in summary['commands'])
    assert summary['commands'][1]['tests'] == 17
    control_text = (produced_dir / 'controls.stderr.log').read_text()
    assert re.search(r'\nRan 17 tests in [0-9.]+s\n\nOK\n?$', control_text)
    assert len(re.findall(r'^test_.* \.\.\. ok$', control_text, re.M)) == 17
    oracle_lines = (produced_dir / 'oracle.stdout.log').read_text().splitlines()
    assert oracle_lines == [name + ': PASS' for name in sorted(expected)]
    engine_meta = load(base / 'engine-final-2/metadata.json')
    assert datetime.fromisoformat(engine_meta['finished_at']) < datetime.fromisoformat(oracle_meta['started_at'])
    generator = 'packages/quds_office_engine/test/scripted_workflows_test.dart'
    assert generator in (base / 'engine-final-2/suites.txt').read_text().splitlines()
    oracle.update({'exports': 12, 'controls': 17, 'retained_outputs_match_before_and_after': True,
                   'raw_oracle_pass_inventory_matches': True, 'raw_controls_all_pass': True,
                   'engine_generator_pass_precedes_oracle': True, 'success': True})

    after_head = git('rev-parse', 'HEAD').decode().strip()
    assert source_tree(after_head) == current_tree
    assert {name: fingerprint(repo / name) for name in sorted(current_tree)} == current
    result = {'schema': 1, 'at': datetime.now(timezone.utc).isoformat(),
              'review_head': review_head, 'after_review_head': after_head,
              'review_script_sha256': sha(Path(__file__).read_bytes()),
              'source_sha256': sha(encode(current)), 'source_stable_during_review': True,
              'runtime_gates': rows, 'total_tests': sum(row['tests'] for row in rows),
              'total_suites': sum(row['suites'] for row in rows), 'scripted_oracle': oracle,
              'excluded_attempt': failed, 'success': True,
              'scope': 'Independent receipt audit and raw-log reparse, not a new native test run. '
                       'All current tracked non-evidence bytes, Git blobs and modes equal the tested sources. '
                       'Original package resolutions and external tool hashes are checked within each recorded run, '
                       'not relabeled as current workspace execution. Office output generation is supported by '
                       'the preceding passed engine generator suite and retained output hashes; this review '
                       'does not establish external Office rendering or broad schema acceptance.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

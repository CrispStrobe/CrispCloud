#!/usr/bin/env python3
"""Audit immutable saved receipts without claiming recreated historical tools.

Reads all source/receipt bytes from an explicit Git commit. The old tool binaries
and dependency graphs are not recreated. Their saved before/after identities are
checked for consistency; independently available bytes are verified separately.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, required=True)
    ap.add_argument('--head', required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    repo = args.repo.resolve()
    def git(*argv):
        return subprocess.check_output(['git', '-C', str(repo), *argv])
    def tree(ref):
        result = {}
        for row in git('ls-tree', '-rz', ref).split(b'\0'):
            if row:
                identity, path = row.split(b'\t', 1)
                result[path.decode()] = identity.decode()
        return result
    pinned_tree = tree(args.head)
    source_tree = {k: v for k, v in pinned_tree.items() if not k.startswith('docs/evidence/')}
    batch = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    cache = {}
    def blob(oid):
        if oid in cache:
            return cache[oid]
        batch.stdin.write((oid + '\n').encode())
        batch.stdin.flush()
        header = batch.stdout.readline().decode().split()
        assert len(header) == 3 and header[1] == 'blob', header
        data = batch.stdout.read(int(header[2]))
        assert batch.stdout.read(1) == b'\n'
        if len(data) < 2_000_000:
            cache[oid] = data
        return data
    def read(path):
        return blob(pinned_tree[path].split()[2])
    def obj(path):
        return json.loads(read(path))
    fingerprints = {}
    for path, identity in source_tree.items():
        mode, kind, oid = identity.split()
        assert kind == 'blob', (path, kind)
        data = blob(oid)
        fingerprints[path] = {'kind': 'symlink' if mode == '120000' else 'file', 'size': len(data), 'sha256': digest(data)}
    base = 'docs/evidence/storage-carving-20261115/local-resume-20261115T1150'
    gates = ['analysis-app-final', 'analysis-engine-final', 'analysis-editor-final', 'analysis-cli-final', 'app-retry-1', 'engine-final', 'editor-final', 'scripted-oracle-final', 'source-integrity-final', 'png-portable-final', 'navigation-capture-final', 'navigation-independent-review-final']
    def artifacts(relative):
        prefix = base + '/' + relative + '/'
        manifest = obj(prefix + 'artifacts-sha256.json')
        actual = {p.removeprefix(prefix) for p in pinned_tree if p.startswith(prefix) and p != prefix + 'artifacts-sha256.json'}
        assert actual == set(manifest), (relative, 'inventory', actual ^ set(manifest))
        for name, expected in manifest.items():
            assert '..' not in Path(name).parts and not name.startswith('/')
            data = read(prefix + name)
            assert {'sha256': digest(data), 'size': len(data)} == expected, (relative, name)
        return {'file_count': len(manifest), 'manifest_sha256': digest(read(prefix + 'artifacts-sha256.json')), 'exact_inventory_and_hashes': True}
    results, tools, snapshot_digests = [], {}, set()
    for gate in gates:
        prefix = base + '/' + gate + '/'
        inventory = artifacts(gate)
        meta = obj(prefix + 'metadata.json')
        before = json.loads(gzip.decompress(read(prefix + 'inputs-before.json.gz')))
        after = json.loads(gzip.decompress(read(prefix + 'inputs-after.json.gz')))
        assert before['entries'] == after['entries'], gate
        sha = digest(encoded(before['entries']))
        assert sha == before['entries_sha256'] == after['entries_sha256'] == meta['before_entries_sha256'] == meta['after_entries_sha256'], gate
        assert before['count'] == after['count'] == len(before['entries']) == meta['input_count'], gate
        assert all(before['entries'].get(k) == v for k, v in fingerprints.items()), (gate, 'source bytes')
        snapshot_digests.add(sha)
        assert meta['before_tools'] == meta['after_tools'], gate
        for path, expected in meta['before_tools'].items():
            assert path not in tools or tools[path] == expected, ('tool changed across gates', path)
            tools[path] = expected
        assert meta['input_changes'] == {'added': [], 'changed': [], 'removed': []}, gate
        assert meta['returncode'] == 0 and meta['qualification_success'] and meta['inputs_and_commit_stable'], gate
        for key in ['head', 'tree', 'source_changes', 'untracked_source']:
            assert meta['before_git'][key] == meta['after_git'][key], (gate, key)
        assert meta['before_git']['source_changes'] == meta['before_git']['untracked_source'] == [], gate
        tested = meta['before_git']['head']
        tested_source = {k: v for k, v in tree(tested).items() if not k.startswith('docs/evidence/')}
        assert tested_source == source_tree, (gate, 'source git identities')
        assert git('rev-parse', tested + '^{tree}').decode().strip() == meta['before_git']['tree'], gate
        command = obj(prefix + 'command.json')
        assert command['argv'] == meta['command'] and command['cwd'] == meta['cwd'], gate
        result = {'gate': gate, 'tested_head': tested, 'artifact_inventory': inventory, 'source_files_verified': len(fingerprints), 'recorded_input_count': len(before['entries']), 'recorded_inputs_sha256': sha, 'immutable_source_bytes_blobs_modes_equal': True, 'recorded_inputs_tools_head_stable': True, 'success': True}
        if prefix + 'suites.txt' in pinned_tree:
            suites = read(prefix + 'suites.txt').decode().splitlines()
            assert len(suites) == len(set(suites)) == meta['suite_count']
            assert all(s in source_tree for s in suites)
            command_suites = [x.removeprefix(meta['repo'] + '/') for x in meta['command'] if x.endswith('.dart')]
            assert command_suites == suites, (gate, 'command suites')
            events = [json.loads(row) for row in read(prefix + 'stdout.jsonl').splitlines()]
            starts = [e['test']['id'] for e in events if e['type'] == 'testStart']
            dones = [e for e in events if e['type'] == 'testDone']
            ends = [e['testID'] for e in dones]
            assert len(starts) == len(set(starts)) == len(ends) == len(set(ends)) and set(starts) == set(ends), gate
            assert all(e.get('result') == 'success' and not e.get('skipped') for e in dones), gate
            assert not any(e['type'] == 'error' for e in events), gate
            done = [e for e in events if e['type'] == 'done']
            assert len(done) == 1 and done[0]['success'], gate
            observed = {e['suite']['path'].removeprefix(meta['repo'] + '/') for e in events if e['type'] == 'suite'}
            assert observed == set(suites), gate
            passed = sum(not e.get('hidden') for e in dones)
            summary = obj(prefix + 'summary.json')
            assert summary['qualification_success'] and summary['done_success'], gate
            assert summary['totals'] == {'tests': passed, 'passed': passed, 'failed': 0, 'errors': 0, 'skipped': 0, 'other_results': 0}, gate
            assert not summary['missing_suites'] and not summary['unexpected_suites'] and not summary['nonpassing_requested_suites'], gate
            result.update(tests=passed, suites=len(suites), hidden_success_events=len(dones) - passed, complete_unique_machine_events=True)
        elif 'analyze' in meta['command']:
            assert '--fatal-infos' in meta['command'] and '--fatal-warnings' in meta['command'], gate
            assert 'No issues found!' in read(prefix + 'stdout.log').decode(), gate
            result['analyzed_files'] = sum(x.endswith('.dart') for x in meta['command'])
        if gate in ['engine-final', 'navigation-capture-final']:
            generation = obj(prefix + 'produced-files.json')
            assert generation['tested_head'] == tested and generation['source_resolution_sha256'] == sha
            assert meta['postprocessing'] == {'success': True, 'produced_files_sha256': digest(read(prefix + 'produced-files.json'))}
            result['produced_files'] = len(generation['files'])
        results.append(result)
    assert len(snapshot_digests) == 1
    artifact_dirs = ['scripted-oracle-final-artifacts', 'source-integrity-final-details', 'png-portable-final-artifacts', 'navigation-independent-review-final-artifacts']
    indexed = {name: artifacts(name) for name in artifact_dirs}
    assert obj(base + '/scripted-oracle-final-artifacts/summary.json')['success']
    assert obj(base + '/source-integrity-final-details/summary.json')['success']
    assert obj(base + '/png-portable-final-artifacts/summary.json')['qualification_success']
    assert obj(base + '/navigation-independent-review-final-artifacts/verification.json')['success']
    tool_audit = []
    for name, expected in tools.items():
        record = {'recorded_path': name, 'sha256': expected}
        if '/CrispCloud/' in name:
            relative = name.split('/CrispCloud/', 1)[1]
            if relative in pinned_tree:
                assert digest(read(relative)) == expected, ('retained tool', name)
                record.update(status='verified_against_pinned_repository_blob', retained_path=relative)
            else:
                record['status'] = 'recorded_before_after_hash_only_not_retained'
        elif name.endswith('/toolchains/env.sh'):
            assert digest(read(base + '/environment/env.sh')) == expected
            record.update(status='verified_against_retained_original_environment', retained_path=base + '/environment/env.sh')
        elif Path(name).is_file() and digest(Path(name).read_bytes()) == expected:
            record['status'] = 'verified_against_available_exact_binary'
        else:
            record['status'] = 'recorded_before_after_hash_only_binary_unavailable'
        tool_audit.append(record)
    generated_inputs = {k: v for k, v in before['entries'].items() if k not in fingerprints}
    result = {'schema': 1, 'at': datetime.now(timezone.utc).isoformat(), 'audited_commit': args.head, 'review_script_sha256': digest(Path(__file__).read_bytes()), 'gates': results, 'additional_artifacts': indexed, 'source_paths_verified': len(fingerprints), 'common_saved_input_digest': next(iter(snapshot_digests)), 'unretained_resolution_inputs': generated_inputs, 'recorded_tool_audit': tool_audit, 'counts': {'primary_app_tests': 903, 'primary_engine_tests': 249, 'primary_editor_tests': 101, 'primary_total': 1253, 'separate_navigation_repeat_tests': 12}, 'success': True, 'scope': 'Independent immutable Git source/mode and saved raw receipt, artifact index, command, input consistency and complete machine-event audit. No Dart/Flutter rerun. Current missing historical dependency graphs and binaries are not reconstructed or certified. Repeated navigation tests excluded from primary cohort total.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(encoded(result))
    batch.stdin.close()
    batch.wait()
    print(json.dumps({'success': True, 'gates': len(results), 'source_paths': len(fingerprints), 'primary_tests': result['counts']['primary_total'], 'separate_navigation': 12, 'output': str(args.output), 'historical_tools': dict(Counter(r['status'] for r in tool_audit))}, indent=2))


if __name__ == '__main__':
    main()

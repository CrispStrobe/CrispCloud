import collections
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1] / 'ParserCanonical'
REF = '09a4a531a4aa210a638a220de45c9d53d44c84e1'
PIN = '08296edbee08da013a8ff718798972552ccd03f7'

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()

summary = json.loads((ROOT / 'summary.json').read_text())
manifest = json.loads((ROOT / 'artifacts-manifest.json').read_text())
archive = (ROOT / 'artifacts.tar.xz').read_bytes()
assert sha(archive) == summary['archive']['sha256']
assert len(archive) == summary['archive']['size']
with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as stream:
    files = {}
    for member in stream.getmembers():
        path = Path(member.name)
        assert member.isfile() and not path.is_absolute() and '..' not in path.parts
        assert member.name not in files
        files[member.name] = stream.extractfile(member).read()
assert set(files) == set(manifest) and len(files) == 32
for path, raw in files.items():
    assert len(raw) == manifest[path]['size'] and sha(raw) == manifest[path]['sha256']
inner = []
for path, raw in files.items():
    if path.endswith('/artifacts-sha256.json'):
        index = json.loads(raw)
        for name, record in index.items():
            content = files[str(Path(path).parent / name)]
            assert len(content) == record['size'] and sha(content) == record['sha256']
        inner.append({'path': path, 'entries_verified': len(index)})
tracked = {}
for row in git('ls-tree', '-rz', PIN).split(b'\0'):
    if not row:
        continue
    header, path = row.split(b'\t', 1)
    mode, kind, blob = header.decode().split()
    tracked[path.decode()] = {'mode': mode, 'kind': kind, 'blob': blob}
snapshots = {}
metadata = {}
gates = []
for gate in ['full-parser', 'strict-analysis']:
    before = json.loads(gzip.decompress(files[gate + '/inputs-before.json.gz']))
    after = json.loads(gzip.decompress(files[gate + '/inputs-after.json.gz']))
    meta = json.loads(files[gate + '/metadata.json'])
    assert before['entries'] == after['entries']
    digest = sha(canonical(before['entries']))
    assert digest == meta['before_entries_sha256'] == meta['after_entries_sha256']
    assert meta['before_git'] == meta['after_git']
    assert meta['before_git']['head'] == PIN
    assert meta['before_git']['tree'] == git('rev-parse', PIN + '^{tree}').decode().strip()
    assert not meta['before_git']['source_changes'] and not meta['before_git']['untracked_source']
    assert meta['before_tools'] == meta['after_tools']
    assert meta['returncode'] == 0 and meta['qualification_success'] and meta['inputs_and_commit_stable']
    snapshots[gate] = before
    metadata[gate] = meta
    gates.append({'label': gate, 'head': PIN, 'tree': meta['before_git']['tree'],
                  'input_count': meta['input_count'], 'input_sha256': digest,
                  'selector': before['selector'], 'stable_inputs_and_commit': True,
                  'returncode': 0, 'tool_hashes': meta['before_tools']})
assert snapshots['full-parser']['entries'] == snapshots['strict-analysis']['entries']
entries = snapshots['full-parser']['entries']
# The retained recorder deliberately excludes historical evidence directories.
selected = {p: r for p, r in tracked.items()
            if not p.startswith(('doc/evidence/', 'docs/evidence/'))}
by_blob = {}
for path, record in selected.items():
    assert record['kind'] == 'blob' and entries[path]['kind'] == 'file', path
    by_blob.setdefault(record['blob'], []).append(path)
process = subprocess.Popen(['git', '-C', str(REPO), 'cat-file', '--batch'],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
for blob, paths in by_blob.items():
    process.stdin.write((blob + '\n').encode())
    process.stdin.flush()
    header = process.stdout.readline().decode().split()
    assert len(header) == 3 and header[1] == 'blob'
    raw = process.stdout.read(int(header[2]))
    assert process.stdout.read(1) == b'\n'
    for path in paths:
        assert entries[path]['size'] == len(raw) and entries[path]['sha256'] == sha(raw), path
process.stdin.close()
process.wait()
assert process.returncode == 0
requested = files['full-parser/suites.txt'].decode().splitlines()
assert len(requested) == len(set(requested)) == 144
assert set(requested) == {p for p in tracked if p.startswith('test/') and p.endswith('_test.dart')}
assert requested == files['all-suites.txt'].decode().splitlines()
starts, ends, suites, done, errors, non_json = {}, {}, {}, [], [], []
for line in files['full-parser/stdout.jsonl'].decode().splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        non_json.append(line)
        continue
    kind = event.get('type')
    if kind == 'testStart':
        assert event['test']['id'] not in starts
        starts[event['test']['id']] = event['test']
    elif kind == 'testDone':
        assert event['testID'] not in ends
        ends[event['testID']] = event
    elif kind == 'suite':
        assert event['suite']['id'] not in suites
        suites[event['suite']['id']] = event['suite']
    elif kind == 'done':
        done.append(event)
    elif kind == 'error':
        errors.append(event)
assert not non_json and not errors and len(done) == 1 and done[0]['success']
assert set(starts) == set(ends)
visible = {key: end for key, end in ends.items() if not end['hidden']}
assert len(visible) == 4132
assert all(end['result'] == 'success' and not end['skipped'] for end in ends.values())
suite_paths = {key: unquote(urlparse(value['path']).path).removeprefix(
    metadata['full-parser']['cwd'] + '/') for key, value in suites.items()}
assert set(suite_paths.values()) == set(requested)
counts = collections.Counter(suite_paths[starts[key]['suiteID']] for key in visible)
raw_summary = json.loads(files['full-parser/summary.json'])
assert raw_summary['totals']['passed'] == len(visible) and len(raw_summary['suites']) == 144
for row in raw_summary['suites']:
    assert row['passed'] == counts[row['path']] and row['result'] == 'passed'
analysis = files['analysis-files.txt'].decode().splitlines()
assert len(analysis) == 18 and metadata['strict-analysis']['command'][-18:] == analysis
assert b'No issues found!' in files['strict-analysis/stdout.log']
assert files['strict-analysis/stderr.log'] == b''
assert sha(files['record_gate.py']) in metadata['full-parser']['before_tools'].values()
resolution = {}
for key, filename in [('pubspec.lock', 'pubspec.lock.gz'),
                      ('.dart_tool/package_config.json', 'dart_tool-package_config.json.gz'),
                      ('.dart_tool/package_graph.json', 'dart_tool-package_graph.json.gz')]:
    raw = gzip.decompress(files['dependency-setup/after/' + filename])
    local = (REPO / key).read_bytes()
    assert entries[key]['size'] == len(raw) and entries[key]['sha256'] == sha(raw)
    resolution[key] = {'recorded_sha256': sha(raw), 'current_sha256': sha(local),
                       'byte_equal_to_current': raw == local, 'size': len(raw)}
assert gzip.decompress(files['dependency-setup/after/pubspec.lock.gz']) == gzip.decompress(
    files['dependency-setup/before/pubspec.lock.gz'])
foreign_graph = json.loads(gzip.decompress(files['dependency-setup/after/dart_tool-package_graph.json.gz']))
local_graph = json.loads((REPO / '.dart_tool/package_graph.json').read_text())
def normalize(value):
    if isinstance(value, dict):
        return {key: normalize(v) for key, v in sorted(value.items())}
    if isinstance(value, list):
        return sorted([normalize(v) for v in value], key=lambda v: json.dumps(v, sort_keys=True))
    return value
sdk_tools = []
for path, expected in metadata['strict-analysis']['before_tools'].items():
    marker = '/toolchains/flutter/bin/cache/dart-sdk/'
    if marker in path:
        current = REPO.parent / 'toolchains/flutter/bin/cache/dart-sdk' / path.split(marker, 1)[1]
        sdk_tools.append({'recorded_path': path, 'sha256': expected,
                          'current_path': str(current), 'current_bytes_equal': sha(current.read_bytes()) == expected})
assert all(row['current_bytes_equal'] for row in sdk_tools)
result = {
    'schema': 1, 'observed_app_reference': '3e9560c9b4bd617b5346bacd8b5039493f0f2dc1',
    'evidence_commit': REF, 'source_pin': PIN, 'archive_size': len(archive),
    'archive_sha256': sha(archive), 'outer_manifest_entries_verified': len(files),
    'inner_indexes': inner, 'tracked_non_evidence_files_verified_against_exact_git': len(selected),
    'historical_evidence_paths_excluded_by_recorded_selector': len(tracked) - len(selected),
    'gates': gates,
    'machine_events': {'suites': len(suites), 'visible_tests': len(visible),
        'hidden_loader_tests': len(ends) - len(visible), 'all_test_ids_unique_and_paired': True,
        'passed': len(visible), 'failed': 0, 'skipped': 0, 'errors': 0,
        'single_done_success': True, 'per_suite_counts_match_summary': True},
    'strict_analysis': {'files': 18, 'fatal_infos': True, 'fatal_warnings': True, 'no_issues': True},
    'resolution': resolution, 'normalized_package_graph_equal_to_current': normalize(foreign_graph) == normalize(local_graph),
    'sdk_tool_identity': sdk_tools,
    'full_suite_source_delta_to_app_pin': git('diff', '--name-only', PIN, REF, '--', 'lib', 'test', 'pubspec.yaml', 'analysis_options.yaml').decode().splitlines(),
    'current_checkout_head': git('rev-parse', 'HEAD').decode().strip(),
    'scope': 'Independently verified existing full 144-suite/4,132-test gate on exact 08296ed in its recorded standalone graph. No runtime rerun by this audit. Our distinct 18-test/one-file records remain retained separately; overlapping counts are not added.'
}
(ROOT / 'independent-verification.json').write_bytes(canonical(result))
print(json.dumps({key: value for key, value in result.items() if key not in ('gates', 'sdk_tool_identity')}, indent=2))

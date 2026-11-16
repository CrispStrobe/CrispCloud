#!/usr/bin/env python3
"""Verify published recovery evidence and its documentation-only source boundary."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('repo', type=Path)
p.add_argument('--source-commit', required=True)
p.add_argument('--tree', default='HEAD')
p.add_argument('--output', type=Path)
a = p.parse_args()
repo = a.repo.resolve()
evidence = repo / 'docs/validation/zotero-recovery-20261116'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args])

object_format = git('rev-parse', '--show-object-format').decode().strip()
assert object_format in ('sha1', 'sha256')
tree_entries = {}
for row in git('ls-tree', '-r', '-z', a.tree).split(bytes([0])):
    if not row:
        continue
    metadata, name = row.split(bytes([9]), 1)
    mode, kind, oid = metadata.decode().split()
    tree_entries[name.decode()] = (mode, kind, oid)

def bound_bytes(path):
    assert not path.is_symlink(), path
    rel = str(path.resolve().relative_to(repo))
    data = path.read_bytes()
    expected = tree_entries.get(rel)
    assert expected and expected[1] == 'blob', rel
    header = ('blob ' + str(len(data))).encode() + bytes([0])
    actual = hashlib.new(object_format, header + data).hexdigest()
    assert actual == expected[2], ('Working bytes differ from supplied tree', rel)
    return data

def read_json(path):
    return json.loads(bound_bytes(path))

def verify_inventory(folder):
    inventory = read_json(folder / 'artifact-inventory.json')
    restored = {}
    for entry in inventory['artifacts']:
        path = folder / entry['published_path']
        data = bound_bytes(path)
        assert len(data) == entry['published_bytes'] and sha(data) == entry['published_sha256'], path
        raw = gzip.decompress(data) if entry['compression'] == 'gzip' else data
        assert len(raw) == entry['original_bytes'] and sha(raw) == entry['original_sha256'], path
        assert entry['original_path'] not in restored
        restored[entry['original_path']] = raw
    receipt = json.loads(restored['receipt.json'])
    assert sha(restored['receipt.json']) == inventory['source_receipt_sha256']
    for command in receipt['commands']:
        assert command['status'] == 'passed' and command['exit_code'] == 0, command['name']
        assert sha(restored[command['log']]) == command['log_sha256'], command['name']
    return receipt, restored, len(inventory['artifacts'])

canonical, canonical_raw, canonical_artifacts = verify_inventory(evidence / 'canonical')
host, host_raw, host_artifacts = verify_inventory(evidence / 'host')
assert canonical['all_passed'] is True
assert host['status'] == 'passed' and host['all_required_commands_completed'] is True
assert canonical['qualified_published_source_commit'] == 'b87f9d6c3a2532c9695024adf48ca9fbd3c0927a'
assert host['source_commit'] == '07083d1983db87a9868c3e8ba0cda1efd283b445'
assert host['quds_commit'] == canonical['qualified_published_source_commit']
for key in ['source_inputs_unchanged', 'external_dependency_and_runtime_inputs_unchanged', 'harness_inputs_unchanged', 'fixture_inputs_unchanged', 'published_source_still_matches', 'analysis_config_restored']:
    assert canonical[key] is True, key
for key in ['source_unchanged', 'dependencies_unchanged', 'analysis_config_restored', 'tracked_inputs_match_published_source']:
    assert host[key] is True, key
for raw, names in [(canonical_raw, ['source', 'dependencies', 'fixtures']), (host_raw, ['source', 'dependencies'])]:
    for name in names:
        assert raw[name + '-before.json'] == raw[name + '-after.json'], name
assert sha(canonical_raw['run-qualification.py']) == canonical['reproduction_script_sha256']
assert sha(host_raw['run-expanded-host.py']) == host['reproduction_script_sha256']
selected = [(c['package'], path) for c in canonical['cohorts'].values() for path in c['tests']]
assert len(selected) == len(set(selected)) == 70
assert set(canonical['passed_tests_by_cohort']) == set(canonical['cohorts'])
canonical_total = sum(canonical['passed_tests_by_cohort'].values())
assert canonical_total == canonical['total_disjoint_tests_passed']
canonical_commands = {command['name']: command for command in canonical['commands']}
required_canonical = set(canonical['cohorts']) | {'engine-strict-analysis', 'editor-strict-analysis', 'dart-3.12-format-check'}
assert len(canonical_commands) == len(canonical['commands']) == len(required_canonical) == 12
assert set(canonical_commands) == required_canonical

def terminal_test_count(raw):
    text = raw.decode()
    matches = re.findall(r'^\d+(?::\d+){1,2} \+(\d+)(?: ~([0-9]+))?: All tests passed!\s*$', text, re.MULTILINE)
    assert len(matches) == 1, matches
    count, skips = matches[0]
    assert int(skips or '0') == 0
    return int(count)

for name, cohort in canonical['cohorts'].items():
    command = canonical_commands[name]
    assert command['passed_tests'] == canonical['passed_tests_by_cohort'][name]
    assert command['skipped_tests'] == 0
    assert terminal_test_count(canonical_raw[command['log']]) == command['passed_tests']
    assert [arg for arg in command['command'] if arg.startswith('test/') and arg.endswith('.dart')] == cohort['tests']
for name in ['engine-strict-analysis', 'editor-strict-analysis']:
    assert '--fatal-infos' in canonical_commands[name]['command']
    assert b'No issues found!' in canonical_raw[canonical_commands[name]['log']]
assert b'37 files (0 changed)' in canonical_raw[canonical_commands['dart-3.12-format-check']['log']]
host_commands = {command['name']: command for command in host['commands']}
required_host = {'vendor-source', 'vendor-tracked', 'host-tests', 'host-analysis', 'vendor-analysis', 'host-format', 'vendor-format', 'python-sync-verifier-tests', 'whitespace', 'vendor-tracked-final'}
assert len(host_commands) == len(host['commands']) == 10 and set(host_commands) == required_host
assert terminal_test_count(host_raw[host_commands['host-tests']['log']]) == host['passed_host_tests']
python_log = host_raw[host_commands['python-sync-verifier-tests']['log']].decode()
assert re.search(r'^Ran 28 tests in ', python_log, re.MULTILINE)
assert re.search(r'^OK\s*$', python_log, re.MULTILINE)
for name in ['host-analysis', 'vendor-analysis']:
    assert '--fatal-infos' in host_commands[name]['command']
    assert b'No issues found!' in host_raw[host_commands[name]['log']]

assert host['passed_host_tests'] == 41 and host['passed_python_tests'] == 28
assert len([x for values in canonical['analysis_and_format_targets'].values() for x in values]) == 37
assert len(host['host_analysis_targets']) + len(host['vendored_analysis_targets']) == 24
pdf = json.loads(canonical_raw['poppler/receipt.json'])
pdf_binding = json.loads(canonical_raw['poppler-binding.json'])
assert pdf['passed'] is True and pdf_binding['passed'] is True
assert pdf_binding['producer_receipt']['sha256'] == sha(canonical_raw['receipt.json'])
assert pdf_binding['verifier_receipt_sha256'] == sha(canonical_raw['poppler/receipt.json'])
assert len(pdf['commands']) == 7
for command in pdf['commands']:
    assert command['passed'] is True and command['exit_code'] == 0
    for stream in ['stdout', 'stderr']:
        assert sha(canonical_raw['poppler/' + command[stream]]) == command[stream + '_sha256']
assert pdf['checks']['raster']['passed'] is True and pdf['checks']['raster']['differing_pixels'] == 0
assert pdf['checks']['text']['passed'] is True

# This verifies faithful publication of the strict diagnostic, not a passing mode comparison.
original = evidence / 'audit/delivery-verification.json'
assert sha(bound_bytes(original)) == 'e410bd23b862ff88c407d1cc8db9c1b3cfee1879c2a9b5281139e15fd5865210'
strict = read_json(original)
assert strict['checks']['managed_non_parser_git_blobs_and_modes_identical'] is False
assert strict['checks']['all_managed_manifest_sha256_values_match_host_blobs'] is True
details = strict['details_archive']
details_bytes = bound_bytes(evidence / 'audit' / details['filename'])
assert len(details_bytes) == details['bytes'] and sha(details_bytes) == details['sha256']
details_raw = gzip.decompress(details_bytes)
assert len(details_raw) == details['uncompressed_bytes'] and sha(details_raw) == details['uncompressed_sha256']

changed = [item.decode() for item in git('diff', '--no-renames', '--name-only', '-z', a.source_commit, a.tree).split(bytes([0])) if item]
assert all(path.startswith('docs/validation/') for path in changed), changed
# Unified-diff context lines encode a blank source line as one space. Preserve
# those verbatim audit bytes; whitespace lint applies to the remaining files.
raw_diff_paths = sorted(name for name in tree_entries if
    (name.startswith('docs/validation/zotero-recovery-20261116/audit/unmanaged-diffs/') and name.endswith('.diff'))
    or name == 'docs/validation/zotero-recovery-20261116/audit/complete-runner-delta.patch')
for name in raw_diff_paths:
    raw_diff = bound_bytes(repo / name)
    assert raw_diff.startswith((b'--- ', b'diff --git ')), name
subprocess.run(['git', '-C', str(repo), 'diff', '--no-renames', '--check', a.source_commit, a.tree,
                '--', '.', *[':(exclude)' + name for name in raw_diff_paths]], check=True)
missing_links = []
reviewed_markdown = [evidence / 'README.md', evidence / 'host/README.md', evidence / 'setup/README.md']
reviewed_markdown.extend((evidence / 'audit').glob('*.md'))
if (evidence / 'canonical/README.md').exists():
    reviewed_markdown.append(evidence / 'canonical/README.md')
for doc in reviewed_markdown:
    text = bound_bytes(doc).decode()
    assert not re.search(r'\bPENDING[_A-Z]*\b|\{\{[A-Z_]+\}\}', text), doc
    for link in re.findall(r'\]\(([^)]+)\)', text):
        target = link.split('#', 1)[0]
        if not target or re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', target):
            continue
        target_path = doc.parent / target
        if not target_path.exists():
            missing_links.append({'document': str(doc.relative_to(evidence)), 'target': target})
        elif target_path.is_file():
            bound_bytes(target_path)
        else:
            prefix = str(target_path.resolve().relative_to(repo)) + '/'
            assert any(name.startswith(prefix) for name in tree_entries), target_path
assert not missing_links, missing_links
result = {
    'schema_version': 1,
    'publication_verified': True,
    'verification_scope': 'Archive bytes, receipt/log binding, disjoint complete test counts, input integrity and documentation-only source boundary. Does not replace the preserved strict Git-mode diagnostic.',
    'repo': str(repo), 'source_commit': a.source_commit,
    'publication_tree': git('rev-parse', a.tree + '^{tree}').decode().strip(),
    'all_read_artifact_and_linked_file_bytes_match_supplied_tree': True,
    'rename_detection_disabled_for_source_boundary': True,
    'whitespace_excluded_verbatim_diff_artifacts': raw_diff_paths,
    'documentation_paths_changed': len(changed),
    'canonical_artifacts_verified': canonical_artifacts, 'host_artifacts_verified': host_artifacts,
    'canonical_tests': canonical_total, 'host_tests': host['passed_host_tests'], 'python_tests': host['passed_python_tests'],
    'total_fresh_disjoint_tests': canonical_total + host['passed_host_tests'] + host['passed_python_tests'],
    'canonical_skips': 0, 'canonical_test_files': 70,
    'counts_bound_to_terminal_raw_log_markers': True,
    'required_command_sets_complete': True,
    'independent_pdf_checks_passed': True,
    'independent_pdf_commands_verified': 7,
    'canonical_analysis_format_targets': 37, 'host_analysis_format_targets': 24,
    'strict_mode_diagnostic_still_false': True,
    'markdown_links_checked': len(reviewed_markdown),
}
if a.output:
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
print(json.dumps(result, indent=2, sort_keys=True))

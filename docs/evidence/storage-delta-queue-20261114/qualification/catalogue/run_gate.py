import datetime
import hashlib
import json
import os
import pathlib
import platform
import re
import subprocess
import sys
import time

ROOT = pathlib.Path('/workspace/scratch/209f165653d7/CrispCloud')
OUT = pathlib.Path('/workspace/scratch/209f165653d7/validation/queue-catalogue-qualification')
LAUNCHER = ROOT.parent / 'toolchain/run'
FROZEN = '8b2ec1079ecaa340cf29bff0d04ae05e5368bf8f'
TREE = '74cafe6de213bcfca7d24362823106e3757a23f5'
NATIVE = 'packages/crisp_catalog/native'
COMMAND = ['../toolchain/run', 'cargo', 'test', '--locked', '--offline', '--manifest-path', NATIVE + '/Cargo.toml']
ENV = dict(os.environ)
ENV['CARGO_TARGET_DIR'] = str(ROOT.parent / 'toolchain/queue-catalogue-test-target')
ENV['CARGO_BUILD_JOBS'] = '2'
ENV['CARGO_TERM_COLOR'] = 'never'
WHITELIST = ['PATH', 'LD_LIBRARY_PATH', 'CARGO_HOME', 'RUSTUP_HOME', 'CARGO_TARGET_DIR', 'CARGO_BUILD_JOBS', 'CARGO_TERM_COLOR', 'RUSTUP_TOOLCHAIN', 'CARGO_BUILD_TARGET', 'RUSTFLAGS', 'RUSTDOCFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CC', 'CXX', 'AR', 'TMPDIR', 'CI']

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def run(argv):
    return subprocess.check_output(argv, cwd=ROOT, env=ENV, text=True).strip()

def digest(data):
    return hashlib.sha256(data).hexdigest()

def snapshot():
    paths = subprocess.check_output(['git', 'ls-files', '-z', '--', NATIVE], cwd=ROOT).decode().split('\0')
    entries = []
    for rel in sorted(p for p in paths if p):
        data = (ROOT / rel).read_bytes()
        pinned = subprocess.check_output(['git', 'show', FROZEN + ':' + rel], cwd=ROOT)
        entries.append({'path': rel, 'bytes': len(data), 'sha256': digest(data), 'frozen_sha256': digest(pinned), 'matches_frozen': data == pinned})
    return entries

def source_state():
    return {
        'head': run(['git', 'rev-parse', 'HEAD']),
        'tree': run(['git', 'rev-parse', 'HEAD^{tree}']),
        'branch': run(['git', 'branch', '--show-current']),
        'tracked_status': run(['git', 'status', '--porcelain=v1', '--untracked-files=no']),
    }

started = now()
before_state = source_state()
if before_state['head'] != FROZEN or before_state['tree'] != TREE or before_state['tracked_status']:
    write('blocked.json', {'started_utc': started, 'source': before_state, 'expected_head': FROZEN, 'expected_tree': TREE})
    raise SystemExit('Frozen clean source gate failed before testing.')
before = snapshot()
if not all(row['matches_frozen'] for row in before):
    raise SystemExit('A native input differs from the frozen commit.')
write('inputs-before.json', before)
write('source-before.json', before_state)
effective_env = json.loads(run([str(LAUNCHER), 'python3', '-c', 'import json,os; print(json.dumps({key:os.environ.get(key) for key in ' + repr(WHITELIST) + '}))']))
versions = {
    'rustc': run([str(LAUNCHER), 'rustc', '-vV']),
    'cargo': run([str(LAUNCHER), 'cargo', '--version']),
    'platform': platform.platform(),
    'uname': list(platform.uname()),
    'launcher': {'path': str(LAUNCHER), 'sha256': digest(LAUNCHER.read_bytes())},
}
for tool in ('rustc', 'cargo'):
    binary = pathlib.Path(run([str(LAUNCHER), 'rustup', 'which', tool]))
    versions[tool + '_binary'] = {'path': str(binary), 'sha256': digest(binary.read_bytes())}
write('runtime.json', versions)
write('environment.json', effective_env)
write('command.json', {'argv': COMMAND, 'cwd': str(ROOT), 'started_utc': started, 'expected_remote_head': FROZEN, 'expected_tree': TREE, 'network_mode': 'Cargo --offline', 'scope': 'native catalogue bridge unit tests and doc tests; existing ignored scale test is not requested'})
print('Starting frozen catalogue qualification; ' + str(len(before)) + ' native inputs captured.', flush=True)
t0 = time.monotonic()
with (OUT / 'stdout.log').open('w') as stdout, (OUT / 'stderr.log').open('w') as stderr:
    process = subprocess.run(COMMAND, cwd=ROOT, env=ENV, stdout=stdout, stderr=stderr)
elapsed = time.monotonic() - t0
(OUT / 'exit-code.txt').write_text(str(process.returncode) + '\n')
after = snapshot()
after_state = source_state()
write('inputs-after.json', after)
write('source-after.json', after_state)
stdout = (OUT / 'stdout.log').read_text()
results = []
pattern = re.compile(r'test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out; finished in ([^\n]+)')
for match in pattern.finditer(stdout):
    results.append({'result': match[1], 'passed': int(match[2]), 'failed': int(match[3]), 'ignored': int(match[4]), 'measured': int(match[5]), 'filtered_out': int(match[6]), 'duration': match[7]})
unit = results[0] if results else None
docs = results[1:] if len(results) > 1 else []
summary = {
    'started_utc': started,
    'ended_utc': now(),
    'elapsed_seconds': elapsed,
    'exit_code': process.returncode,
    'source_head': FROZEN,
    'source_tree': TREE,
    'input_count': len(before),
    'input_bytes': sum(row['bytes'] for row in before),
    'inputs_unchanged': before == after,
    'inputs_match_frozen': all(row['matches_frozen'] for row in before + after),
    'head_unchanged': before_state['head'] == after_state['head'] == FROZEN,
    'tree_unchanged': before_state['tree'] == after_state['tree'] == TREE,
    'tracked_tree_clean_before': not before_state['tracked_status'],
    'tracked_tree_clean_after': not after_state['tracked_status'],
    'unit_tests': unit,
    'doc_test_groups': docs,
    'alias_case_passed': bool(re.search(r'^test tests::self_index_under_an_alias_excludes_its_database_and_journal \.\.\. ok$', stdout, re.M)),
    'ignored_scope': 'Existing million-row SQLite stress test; not included as a pass.',
    'qualification_boundary': 'Linux x86_64 native Rust only. The Unix alias case is exercised; this does not reproduce or establish the Windows canonical-prefix fix.',
}
summary['accepted'] = bool(process.returncode == 0 and results and all(row['result'] == 'ok' for row in results) and summary['inputs_unchanged'] and summary['inputs_match_frozen'] and summary['head_unchanged'] and summary['tree_unchanged'] and summary['tracked_tree_clean_after'] and summary['alias_case_passed'])
write('summary.json', summary)
artifacts = []
for path in sorted(OUT.iterdir()):
    if path.is_file() and path.name != 'artifacts-sha256.json':
        data = path.read_bytes()
        artifacts.append({'path': path.name, 'bytes': len(data), 'sha256': digest(data)})
write('artifacts-sha256.json', artifacts)
print(json.dumps(summary, indent=2, sort_keys=True), flush=True)
sys.exit(0 if summary['accepted'] else 1)

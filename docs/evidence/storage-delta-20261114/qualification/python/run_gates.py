"""Run the four requested read-only Python qualification gates and retain receipts."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


ROOT = Path('/workspace/scratch/209f165653d7')
REPO = ROOT / 'CrispCloud'
QUDS = ROOT / 'quds_office_suite'
OUTPUT = ROOT / 'validation/delta-python-gates'
WRAPPER = ROOT / 'toolchain/run'
EXPECTED_HEAD = '9d4197f4cedc4279f3c7f1b83148c2a43bebc882'


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_state(repo):
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    def git(*args):
        return subprocess.check_output(
            ['git', *args], cwd=repo, text=True, env=environment,
        ).strip()
    return {
        'head': git('rev-parse', 'HEAD'),
        'tree': git('rev-parse', 'HEAD^{tree}'),
        'status_porcelain': git('status', '--porcelain=v1', '--untracked-files=all'),
    }


GATES = [
    ('verify-office-fidelity', ['python', 'tool/verify_office_fidelity.py', '--source', '../quds_office_suite']),
    ('sync-office-fidelity', ['python', '-m', 'unittest', 'discover', '-s', 'tool', '-p', 'test_sync_office_fidelity.py']),
    ('sync-legacy-doc-parser', ['python', '-m', 'unittest', 'discover', '-s', 'tool', '-p', 'test_sync_legacy_doc_parser.py']),
    ('office-host-evidence', ['python', '-m', 'unittest', 'discover', '-s', 'tool', '-p', 'test_office_host_evidence.py']),
]


def run_gate(gate):
    name, arguments = gate
    command = [str(WRAPPER), *arguments]
    log_path = OUTPUT / (name + '.log')
    before = git_state(REPO)
    started_at = utc_now()
    started = time.monotonic()
    with log_path.open('wb') as output:
        completed = subprocess.run(
            command, cwd=REPO, stdout=output, stderr=subprocess.STDOUT,
            env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1', GIT_OPTIONAL_LOCKS='0'),
        )
    seconds = time.monotonic() - started
    finished_at = utc_now()
    after = git_state(REPO)
    log = log_path.read_text(errors='replace')
    tests = re.search(r'Ran (\d+) tests? in ([0-9.]+)s', log)
    verified = re.search(r'Verified (\d+) Office files; Quds source ([0-9a-f]+)', log)
    return {
        'gate': name,
        'command': command,
        'cwd': str(REPO),
        'environment_overrides': {'PYTHONDONTWRITEBYTECODE': '1', 'GIT_OPTIONAL_LOCKS': '0'},
        'started_at': started_at,
        'finished_at': finished_at,
        'wall_seconds': seconds,
        'exit_code': completed.returncode,
        'log': log_path.name,
        'log_bytes': log_path.stat().st_size,
        'log_sha256': sha256(log_path),
        'unittest_count': int(tests.group(1)) if tests else None,
        'unittest_reported_seconds': float(tests.group(2)) if tests else None,
        'verified_office_files': int(verified.group(1)) if verified else None,
        'verified_quds_pin': verified.group(2) if verified else None,
        'git_before': before,
        'git_after': after,
        'git_state_unchanged': before == after,
    }


OUTPUT.mkdir(parents=True, exist_ok=True)
before = git_state(REPO)
quds_before = git_state(QUDS)
if before['head'] != EXPECTED_HEAD or before['status_porcelain']:
    raise SystemExit('The required frozen clean source checkpoint is not present.')
inputs = [
    'tool/verify_office_fidelity.py',
    'tool/sync_office_fidelity.py',
    'tool/sync_legacy_doc_parser.py',
    'tool/office_host_evidence.py',
    'tool/office_host_evidence.json',
    'tool/office_fidelity_manifest.json',
    'tool/test_sync_office_fidelity.py',
    'tool/test_sync_legacy_doc_parser.py',
    'tool/test_office_host_evidence.py',
]
input_hashes_before = {name: sha256(REPO / name) for name in inputs}
started_at = utc_now()
with ThreadPoolExecutor(max_workers=4) as executor:
    results = list(executor.map(run_gate, GATES))
after = git_state(REPO)
quds_after = git_state(QUDS)
input_hashes_after = {name: sha256(REPO / name) for name in inputs}
receipt = {
    'scope': 'Four requested Python reconciliation gates only; native Flutter qualification is separate.',
    'started_at': started_at,
    'finished_at': utc_now(),
    'python_version': sys.version,
    'python_executable': sys.executable,
    'wrapper_path': str(WRAPPER),
    'wrapper_sha256': sha256(WRAPPER),
    'tmpdir': os.environ.get('TMPDIR'),
    'git_before': before,
    'git_after': after,
    'git_state_unchanged': before == after,
    'quds_git_before': quds_before,
    'quds_git_after': quds_after,
    'quds_git_state_unchanged': quds_before == quds_after,
    'input_hashes_before': input_hashes_before,
    'input_hashes_after': input_hashes_after,
    'input_hashes_unchanged': input_hashes_before == input_hashes_after,
    'results': results,
    'all_exit_codes_zero': all(result['exit_code'] == 0 for result in results),
    'unit_tests_run': sum(result['unittest_count'] or 0 for result in results),
}
(OUTPUT / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key not in ('input_hashes_before', 'input_hashes_after')}, indent=2))
raise SystemExit(0 if receipt['all_exit_codes_zero'] and receipt['git_state_unchanged'] and receipt['input_hashes_unchanged'] else 1)

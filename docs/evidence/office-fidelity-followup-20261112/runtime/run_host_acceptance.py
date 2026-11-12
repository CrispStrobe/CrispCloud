#!/usr/bin/env python3
"""Record the complete host Office gate against explicit clean commit pins.

Source the pinned host runtime, then supply --repo, --commit, --source-commit
and a fresh --output directory outside the checkout. This runner never updates
dependencies, goldens, source files or Git refs itself. The existing CI SQLite
wrapper restores its temporary pubspec hook before the final fingerprint check.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def utc():
    return datetime.now(timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    require(not output.is_relative_to(repo), 'Write acceptance outside the checkout')
    require(os.environ.get('CI') == 'true', 'The pinned runtime must set CI=true')
    require(all(re.fullmatch('[0-9a-f]{40}', pin)
                for pin in (args.commit, args.source_commit)), 'Use full commit pins')

    def git(*arguments):
        return subprocess.check_output(['git', *arguments], cwd=repo, text=True)

    def snapshot():
        names = git('ls-files', '-z').split('\0')
        hashes = {name: sha(repo / name) for name in names if name}
        return {'head': git('rev-parse', 'HEAD').strip(),
                'tree': git('rev-parse', 'HEAD^{tree}').strip(),
                'dirty': git('status', '--porcelain', '--untracked-files=normal'),
                'tracked_files': len(hashes),
                'sha256': hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()}

    before = snapshot()
    require(before['head'] == args.commit and not before['dirty'], 'Expected clean pinned host')
    sync = json.loads((repo / 'tool/office_fidelity_manifest.json').read_text())
    require(sync['source_commit'] == args.source_commit, 'Shared source pin differs')
    for name, digest in sync['files'].items():
        require(sha(repo / name) == digest, f'Managed source drift: {name}')
    engine_manifest = json.loads((repo / 'packages/quds_office_engine/tool/fidelity/output_manifest.json').read_text())
    host_manifest = json.loads((repo / 'tool/office_host_evidence.json').read_text())
    runtime = json.loads(subprocess.check_output(['flutter', '--version', '--machine'], text=True))
    require(runtime['frameworkVersion'] == '3.47.8', 'Expected pinned Flutter3.47.8')
    require(not output.exists(), 'Use a fresh output directory')
    output.mkdir(parents=True)
    command = [sys.executable, 'tool/with_ci_system_sqlite.py', 'bash', 'tool/check_office_fidelity.sh']
    receipt = {'status': 'running', 'started_utc': utc(), 'app_commit': args.commit,
               'source_commit': args.source_commit, 'source_before': before,
               'managed_source_files': len(sync['files']), 'runtime': runtime,
               'command': command, 'cwd': str(repo), 'runner_sha256': sha(Path(__file__)),
               'expected_engine_outputs': engine_manifest['expected_file_count'],
               'expected_host_outputs': len(host_manifest['outputs']), 'artifacts': {}}

    def save():
        (output / 'producer-acceptance.json').write_text(json.dumps(receipt, indent=2) + '\n')

    save()
    started = time.monotonic()
    log_path = output / 'host-gate.log'
    try:
        print(json.dumps({'stage': 'complete-host-gate', 'status': 'running', 'output': str(output)}), flush=True)
        with log_path.open('w') as log:
            completed = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT, timeout=1500)
        receipt['exit_code'] = completed.returncode
        receipt['source_after'] = snapshot()
        require(receipt['source_after'] == before, 'Tracked source, Git pin or clean state changed')
        require(completed.returncode == 0, 'Complete host gate failed; see preserved log')
        text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', log_path.read_text(errors='replace'))
        successes = [line for line in text.replace('\r', '\n').splitlines() if 'All tests passed!' in line]
        require(len(successes) == 2, 'Expected engine and host test completion markers')
        results = [{'passed': int(re.search(r'\+(\d+)', line)[1]),
                    'skipped': int(match[1]) if (match := re.search(r'~(\d+)', line)) else 0,
                    'completion': line} for line in successes]
        require(all(item['skipped'] == 0 for item in results), 'Unexpected skipped test')
        receipt['tests'] = {'mandatory_engine': results[0], 'host': results[1]}
        receipt['python_test_cohorts'] = [int(count) for count in re.findall(r'^Ran (\d+) tests? in ', text, re.MULTILINE)]
        copies = {
            'engine-inventory.json': 'packages/quds_office_engine/build/fidelity-inventory.json',
            'host-inventory.json': 'build/fidelity-host/inventory.json',
            'host-coverage.json': 'build/fidelity-host/coverage/gaps.json',
            'host-lcov.info': 'build/fidelity-host/coverage/lcov.info',
        }
        for name, source in copies.items():
            shutil.copyfile(repo / source, output / name)
            receipt['artifacts'][name] = sha(output / name)
        engine = json.loads((output / 'engine-inventory.json').read_text())
        host = json.loads((output / 'host-inventory.json').read_text())
        coverage = json.loads((output / 'host-coverage.json').read_text())
        require(engine['ok'] and not engine['errors'] and
                engine['observed_files'] == engine['verified_files'] == engine['expected_files'] == receipt['expected_engine_outputs'],
                'Engine inventory mismatch')
        require(not host['failures'] and host['verified'] == host['expected'] == receipt['expected_host_outputs'],
                'Host inventory mismatch')
        for rows, prefix in ((engine['files'], repo / 'packages/quds_office_engine/build'), (host['files'], repo)):
            for row in rows:
                path = prefix / row['path']
                require(path.stat().st_size == row['bytes'] and sha(path) == row['sha256'], f'Output changed: {path}')
        require(not coverage['uninstrumented_files'] and not coverage['source_git_dirty'], 'Incomplete or dirty host coverage')
        require(coverage['source_git_commit'] == args.commit, 'Coverage commit mismatch')
        receipt['inventory'] = {'engine': engine['verified_files'], 'host': host['verified'], 'all_hashes_match': True}
        receipt['coverage'] = {key: coverage[key] for key in ('covered_lines', 'instrumented_lines', 'uninstrumented_files', 'source_tree_sha256', 'source_sha256')}
        receipt['status'] = 'passed'
    except Exception as error:
        receipt['status'] = 'failed'
        receipt['error'] = repr(error)
        raise
    finally:
        receipt['finished_utc'] = utc()
        receipt['elapsed_seconds'] = time.monotonic() - started
        if log_path.exists():
            receipt['artifacts']['host-gate.log'] = sha(log_path)
        save()
    print(json.dumps({'status': receipt['status'], 'tests': receipt['tests'], 'inventory': receipt['inventory'],
                      'receipt': str(output / 'producer-acceptance.json')}, indent=2), flush=True)


if __name__ == '__main__':
    main()

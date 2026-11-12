#!/usr/bin/env python3
"""Run the unchanged frozen host gate once and preserve verifiable receipts."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def json_write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def read_json(path):
    return json.loads(path.read_text())


def safe_file(root, name):
    relative = Path(name)
    require(not relative.is_absolute() and '..' not in relative.parts,
            f'Unsafe relative path: {name}')
    path = root / relative
    require(path.resolve().is_relative_to(root) and path.is_file(),
            f'Missing or escaping file: {name}')
    return path


def git(repo, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=repo)


def tracked_snapshot(repo, expected):
    head = git(repo, 'rev-parse', 'HEAD').decode().strip()
    status = git(repo, 'status', '--porcelain=v1', '--untracked-files=all').decode()
    require(head == expected, f'HEAD mismatch: {head}')
    require(not status, f'Worktree is not clean: {status}')
    files = {}
    for entry in git(repo, 'ls-files', '--stage', '-z').split(b'\0'):
        if not entry:
            continue
        metadata, raw_name = entry.split(b'\t', 1)
        mode, blob, stage = metadata.decode().split()
        name = os.fsdecode(raw_name)
        require(stage == '0', f'Unmerged file: {name}')
        path = repo / name
        if mode == '120000':
            contents = os.fsencode(os.readlink(path))
            digest, size = hashlib.sha256(contents).hexdigest(), len(contents)
        else:
            require(mode in ('100644', '100755'), f'Unsupported tracked mode {mode}: {name}')
            require(path.is_file() and not path.is_symlink(), f'Tracked file missing: {name}')
            digest, size = sha(path), path.stat().st_size
        files[name] = {'mode': mode, 'git_blob': blob, 'sha256': digest, 'bytes': size}
    return {'commit': head, 'tree': git(repo, 'rev-parse', 'HEAD^{tree}').decode().strip(),
            'clean': True, 'files': files, 'file_count': len(files),
            'tree_sha256': hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}


def verify_pin(repo, expected, count):
    path = repo / 'tool/office_fidelity_manifest.json'
    manifest = read_json(path)
    require(manifest['source_commit'] == expected, 'Managed source commit mismatch')
    require(len(manifest['files']) == count, 'Managed source count mismatch')
    for name, digest in manifest['files'].items():
        require(sha(safe_file(repo, name)) == digest, f'Managed hash mismatch: {name}')
    return {'source_commit': expected, 'files': count, 'manifest_sha256': sha(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'expected-commit', 'expected-source-commit', 'output'):
        parser.add_argument('--' + name, required=True)
    for name in ('managed-count', 'engine-count', 'host-count'):
        parser.add_argument('--' + name, required=True, type=int)
    args = parser.parse_args()
    repo, output = Path(args.repo).resolve(), Path(args.output).resolve()
    for value in (args.expected_commit, args.expected_source_commit):
        require(re.fullmatch('[0-9a-f]{40}', value), 'Expected commits must be full lowercase SHA-1 values')
    require(not output.exists() and not output.is_relative_to(repo), 'Output must be fresh and outside repository')
    output.mkdir(parents=True)
    started = time.time()
    receipt = {'status': 'running', 'started_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
               'repo': str(repo), 'arguments': vars(args), 'runner_sha256': sha(Path(__file__)),
               'command': ['python3', 'tool/with_ci_system_sqlite.py', 'bash', 'tool/check_office_fidelity.sh'],
               'errors': []}
    before = None
    try:
        print('Preflight: checking frozen host tree and managed source hashes', flush=True)
        before = tracked_snapshot(repo, args.expected_commit)
        json_write(output / 'tracked-before.json', before)
        receipt['pin_before'] = verify_pin(repo, args.expected_source_commit, args.managed_count)
        env_file = Path(__file__).resolve().parent / 'env-host.sh'
        raw_env = subprocess.check_output(
            ['bash', '--noprofile', '--norc', '-c', 'set -a; source "$1"; env -0',
             'host-acceptance-env', str(env_file)])
        env = dict(os.fsdecode(entry).split('=', 1) for entry in raw_env.split(b'\0') if entry)
        require(env.get('CI') == 'true', 'Host environment must explicitly set CI=true')
        version = subprocess.check_output(['flutter', '--version', '--machine'], cwd=repo, env=env)
        (output / 'flutter-version.json').write_bytes(version)
        runtime = json.loads(version)
        require(runtime['frameworkVersion'] == '3.47.8', f'Unexpected Flutter version: {runtime}')
        wrapper = Path(shutil.which('flutter', path=env['PATH']))
        receipt['runtime'] = {'version': runtime, 'CI': env['CI'], 'env_file': str(env_file),
                              'env_sha256': sha(env_file), 'flutter_wrapper': str(wrapper),
                              'wrapper_sha256': sha(wrapper)}
        json_write(output / 'acceptance.json', receipt)
        print(f'Running one existing gate; log: {output / "gate.log"}', flush=True)
        with (output / 'gate.log').open('wb') as log:
            process = subprocess.Popen(receipt['command'], cwd=repo, env=env,
                                       stdout=log, stderr=subprocess.STDOUT)
            receipt['gate_pid'] = process.pid
            json_write(output / 'acceptance.json', receipt)
            print(f'Gate PID: {process.pid}', flush=True)
            try:
                result = process.wait()
            except BaseException:
                process.terminate()
                process.wait()
                raise
        receipt['gate_exit_code'] = result
        require(result == 0, f'Existing host gate failed with exit code {result}')

        text = (output / 'gate.log').read_text(errors='replace')
        text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text).replace('\r', '\n')
        marker = f'Cleared only {args.host_count} declared host outputs and receipt'
        require(text.count(marker) == 1, 'Missing or repeated host phase boundary')
        phases = text.split(marker)
        receipt['test_phases'] = {}
        for name, phase in zip(('engine', 'host'), phases):
            summaries = [line for line in phase.splitlines() if 'All tests passed!' in line]
            require(len(summaries) == 1, f'Expected one {name} Dart/Flutter test success summary: {summaries}')
            match = re.search(r'\+(\d+)([^:]*): All tests passed!', summaries[0])
            require(match and int(match[1]) > 0 and not re.search(r'[~-][1-9]', match[2]),
                    f'Invalid {name} test summary: {summaries[0]}')
            receipt['test_phases'][name] = {'passed': int(match[1]), 'summary': summaries[0].strip(),
                'python_unittest_counts': [int(n) for n in re.findall(r'Ran (\d+) tests? in ', phase)]}

        engine = repo / 'packages/quds_office_engine'
        engine_manifest = engine / 'tool/fidelity/output_manifest.json'
        manifest = read_json(engine_manifest)
        engine_names = [item['pattern'].format(cycle=cycle) for item in manifest['series'] for cycle in item['cycles']]
        engine_names += [item['path'] for item in manifest['standalone']]
        require(len(engine_names) == len(set(engine_names)) == args.engine_count == manifest['expected_file_count'],
                'Engine manifest count mismatch')
        host_manifest = repo / 'tool/office_host_evidence.json'
        host_names = read_json(host_manifest)['outputs']
        require(len(host_names) == len(set(host_names)) == args.host_count, 'Host manifest count mismatch')
        engine_report = read_json(engine / 'build/fidelity-inventory.json')
        host_report = read_json(repo / 'build/fidelity-host/inventory.json')
        require(engine_report['ok'] and not engine_report['errors'], 'Engine inventory errors')
        require(all(engine_report[key] == args.engine_count for key in ('expected_files', 'observed_files', 'verified_files')),
                'Incomplete engine inventory')
        require(not host_report['failures'] and host_report['expected'] == host_report['verified'] == args.host_count,
                'Incomplete host inventory')
        snapshots = []
        for category, root, names, report, manifest_path in (
                ('engine', engine / 'build', engine_names, engine_report, engine_manifest),
                ('host', repo, host_names, host_report, host_manifest)):
            require(report['manifest_sha256'] == sha(manifest_path), f'{category} inventory manifest mismatch')
            records = report['files']
            require(len(records) == len(names) and {r['path'] for r in records} == set(names),
                    f'{category} inventory path mismatch')
            for item in records:
                source = safe_file(root, item['path'])
                require(source.stat().st_size == item['bytes'] and sha(source) == item['sha256'],
                        f'{category} output hash mismatch: {item["path"]}')
                target = output / 'inputs' / category / item['path']
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                require(sha(target) == item['sha256'], f'Snapshot hash mismatch: {target}')
                snapshots.append({'category': category, 'source': str(source),
                                  'snapshot': str(target.relative_to(output)),
                                  'bytes': item['bytes'], 'sha256': item['sha256']})
            json_write(output / f'{category}-inventory.json', report)
        json_write(output / 'output-snapshot.json', {'files': snapshots, 'count': len(snapshots)})
        receipt['inventories'] = {'engine': args.engine_count, 'host': args.host_count,
                                 'total': len(snapshots), 'snapshot_manifest_sha256': sha(output / 'output-snapshot.json')}

        coverage_path = repo / 'build/fidelity-host/coverage/gaps.json'
        coverage = read_json(coverage_path)
        expected_sources = {path.relative_to(repo).as_posix() for pattern in coverage['scope'] for path in repo.glob(pattern)}
        require(expected_sources and not coverage['uninstrumented_files'], 'Missing host coverage sources')
        require(set(coverage['source_sha256']) == expected_sources == {item['path'] for item in coverage['files']},
                'Coverage source inventory mismatch')
        require(coverage['source_git_commit'] == args.expected_commit and coverage['source_git_dirty'] is False,
                'Coverage source revision mismatch')
        for name, digest in coverage['source_sha256'].items():
            require(sha(safe_file(repo, name)) == digest, f'Coverage source hash mismatch: {name}')
        require(coverage['covered_lines'] == sum(item['hit'] for item in coverage['files']) and
                coverage['instrumented_lines'] == sum(item['total'] for item in coverage['files']) > 0,
                'Coverage totals mismatch')
        require(all(0 <= item['hit'] <= item['total'] and item['total'] > 0 for item in coverage['files']),
                'Invalid source coverage counts')
        shutil.copyfile(coverage_path, output / 'coverage.json')
        shutil.copyfile(repo / 'build/fidelity-host/coverage/lcov.info', output / 'lcov.info')
        receipt['coverage'] = {'source_count': len(expected_sources), 'all_sources_instrumented': True,
                               'covered_lines': coverage['covered_lines'], 'instrumented_lines': coverage['instrumented_lines']}
    except BaseException as error:
        receipt['errors'].append(f'{type(error).__name__}: {error}')
    finally:
        try:
            after = tracked_snapshot(repo, args.expected_commit)
            json_write(output / 'tracked-after.json', after)
            receipt['pin_after'] = verify_pin(repo, args.expected_source_commit, args.managed_count)
            require(before is not None and before == after, 'Tracked files changed during host gate')
            receipt['tracked_files_unchanged'] = True
            receipt['tracked_tree_sha256'] = after['tree_sha256']
            receipt['dependency_files_restored'] = {name: row['sha256'] for name, row in after['files'].items()
                                                    if Path(name).name in ('pubspec.yaml', 'pubspec.lock')}
        except BaseException as error:
            receipt['errors'].append(f'Postflight {type(error).__name__}: {error}')
        receipt['status'] = 'passed' if not receipt['errors'] else 'failed'
        receipt['completed_utc'] = dt.datetime.now(dt.timezone.utc).isoformat()
        receipt['elapsed_seconds'] = round(time.time() - started, 3)
        receipt['evidence_sha256'] = {path.name: sha(path) for path in output.iterdir() if path.is_file() and path.name != 'acceptance.json'}
        json_write(output / 'acceptance.json', receipt)
        print(json.dumps({'status': receipt['status'], 'receipt': str(output / 'acceptance.json'),
                          'errors': receipt['errors'], 'test_phases': receipt.get('test_phases')}), flush=True)
    return 0 if receipt['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

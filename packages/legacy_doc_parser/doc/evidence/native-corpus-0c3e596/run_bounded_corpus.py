#!/usr/bin/env python3
"""Run separately receipted corpus cases, sealing each before reclaiming its raw run.

No native run starts unless the caller's expected parser commit is checked out
cleanly. This is a sequence of independent run.py invocations, not one corpus
invocation. A failed or incomplete case is retained for inspection. --resume
reuses verified completed seals and can finish sealing a completed raw case;
it never retries or overwrites an incomplete measurement directory.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


MIB = 1024 * 1024
SCHEMA = 'legacy-doc-parser/bounded-corpus-index'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def git(parser, *args):
    return subprocess.run(['git', '-C', str(parser), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


def require_source(parser, commit, tree=None):
    require(git(parser, 'rev-parse', 'HEAD') == commit, 'Parser HEAD changed or differs from --expected-commit')
    require(not git(parser, 'status', '--porcelain', '--untracked-files=all'),
            'Parser worktree must be clean; current changes are not this run\'s checkpoint')
    actual_tree = git(parser, 'rev-parse', 'HEAD^{tree}')
    require(tree is None or actual_tree == tree, 'Parser source tree changed')
    return actual_tree


def free_bytes(output):
    return shutil.disk_usage(output).free


def require_space(output, minimum_mib, operation):
    free = free_bytes(output)
    require(free >= minimum_mib * MIB,
            f'{operation} requires {minimum_mib} MiB free; available {free / MIB:.1f} MiB')
    return free


def stop_child(process):
    if process.poll() is not None:
        return
    if os.name == 'posix':
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
    else:
        process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        if os.name == 'posix':
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
        process.wait(timeout=10)


def run_logged(command, log_path, *, cwd, output, environment=None, emergency_mib=100):
    """Keep logs out of the raw directory and stop only the child group we own."""
    with log_path.open('a') as log:
        log.write('\n' + now() + ' ' + json.dumps([str(arg) for arg in command]) + '\n')
        log.flush()
        process = subprocess.Popen([str(arg) for arg in command], cwd=cwd,
                                   env=environment, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=os.name == 'posix')
        try:
            while True:
                try:
                    code = process.wait(timeout=5)
                    break
                except subprocess.TimeoutExpired:
                    if emergency_mib is not None and free_bytes(output) < emergency_mib * MIB:
                        raise OSError(f'Free space fell below {emergency_mib} MiB; preserving this case')
        except BaseException:
            stop_child(process)
            raise
    require(code == 0, f'Command exited {code}; inspect {log_path}')


def load_runner(parser):
    path = parser / 'tool/fidelity/run.py'
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location('bounded_corpus_native_runner', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def report_fingerprint(report):
    build = report['build']
    value = {'sourceInputs': build['sources']['sha256'],
             'python': build['python'], 'platform': build['platform'],
             'tools': {name: build[name] for name in
                       ('compiler', 'office', 'pdftotext', 'pdftoppm', 'pdfinfo')},
             'sourceGoldens': report['sourceGoldens'],
             'goldenEnvironment': report['goldenEnvironment']}
    encoded = json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(encoded).hexdigest()


def validate_measurement(raw, case, args, runner, index):
    report_path = raw / 'report.json'
    require(report_path.is_file() and not report_path.is_symlink(), 'Measurement report missing')
    report = json.loads(report_path.read_text())
    require(report.get('schema') == 'legacy-doc-parser/fidelity-report' and report.get('version') == 4,
            'Unexpected measurement report schema')
    require(report.get('status') == 'measured', 'Measurement did not finish; raw artifacts retained')
    require(report.get('parserCommit') == index['sourceCommit']
            and report.get('parserWorktreeDirty') is False, 'Measurement source provenance differs')
    require(report.get('corpusSha256') == index['corpusSha256'], 'Measurement used a different corpus')
    require(report.get('rasterStorage') == 'gzip'
            and report.get('roundtripCyclesRequested') == args.roundtrip_cycles,
            'Measurement options differ')
    require(all(stage.get('status') == 'complete' for stage in report.get('stages', [])),
            'An environment or compiler stage did not complete')
    cases = report.get('cases', [])
    require(len(cases) == 1 and cases[0].get('id') == case['id'], 'Expected exactly this corpus case')
    measured = cases[0]
    require(not runner.case_has_errors(measured), 'Case has failed stages, changed inputs or incomplete cycles')
    require(measured.get('roundtripCyclesRequested') == args.roundtrip_cycles
            and measured.get('rasterStorage') == 'gzip', 'Case options differ')
    require(measured.get('sourceSha256') == case['sha256'], 'Case source hash differs')
    build = report['build']
    require(build.get('sourcesUnchangedDuringCompilation') is True, 'Compilation source changed')
    require(build['sources'] == runner.source_receipt(), 'Current inputs no longer match the measured source receipt')
    executable = raw / build['executable']['path']
    require(executable.parent == raw and executable.is_file()
            and not executable.is_symlink() and digest(executable) == build['executable']['sha256'],
            'Compiled executable does not match its receipt')
    fingerprint = report_fingerprint(report)
    require(index.get('measurementEnvironmentSha256', fingerprint) == fingerprint,
            'Compiler/source/renderer/font environment differs between independent case invocations')
    index.setdefault('measurementEnvironmentSha256', fingerprint)
    return report, measured, digest(report_path)


def summarize(measured, report):
    return {'reportStatus': report['status'], 'caseStatus': measured['status'],
            'roundtripCyclesCompleted': len(measured['roundtripCycles']),
            'pagination': measured.get('pagination'),
            'bridgePagination': measured.get('bridgePagination'),
            'nativeConversionPagination': measured.get('nativeConversionPagination'),
            'sourceGolden': measured.get('sourceGolden'),
            'parserAgainstSourceGolden': measured.get('parserAgainstSourceGolden'),
            'semanticDifferenceCount': len(measured.get('semanticDifferencesFromNativeDoc', [])),
            'exactOnThisRenderer': report['exactOnThisRenderer'],
            'compiledExecutableSha256': report['build']['executable']['sha256'],
            'measurementDurationSeconds': measured.get('durationSeconds')}


def require_owned_raw(raw, output, entry):
    require(raw.parent == output / 'runs'
            and raw.relative_to(output).as_posix() == entry['rawDirectory'],
            'Refusing to remove a directory outside this case\'s generated run')
    require(not raw.is_symlink() and raw.resolve() == raw, 'Refusing to follow a raw directory symlink')
    require(raw.is_dir(), 'Expected generated raw directory is absent')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parser', type=Path, required=True)
    parser.add_argument('--expected-commit', required=True, help='Exact already-saved full commit SHA')
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sealer', type=Path, default=Path(__file__).with_name('seal_native_evidence.py'))
    parser.add_argument('--verifier', type=Path, default=Path(__file__).with_name('verify_native_artifacts.py'))
    parser.add_argument('--case', action='append', default=[])
    parser.add_argument('--roundtrip-cycles', type=int, default=3, choices=range(0, 11))
    parser.add_argument('--dpi', type=int, default=72, choices=(72, 96, 144))
    parser.add_argument('--start-free-mib', type=int, default=400)
    parser.add_argument('--case-free-mib', type=int, default=250)
    parser.add_argument('--emergency-free-mib', type=int, default=100)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    for name in ('parser', 'office', 'dart', 'output', 'sealer', 'verifier'):
        setattr(args, name, getattr(args, name).absolute())
    require(args.parser.resolve() == args.parser, 'Use the resolved parser path')
    require(args.output.resolve() == args.output and not args.output.is_symlink(), 'Use a non-symlink output path')
    require(re.fullmatch('[0-9a-f]{40}', args.expected_commit), 'Expected a full lowercase commit SHA')
    require(args.start_free_mib >= args.case_free_mib > args.emergency_free_mib >= 32,
            'Expected start-free >= case-free > emergency-free >= 32 MiB')
    tree = require_source(args.parser, args.expected_commit)
    corpus_path = args.parser / 'tool/fidelity/corpus.json'
    corpus = json.loads(corpus_path.read_text())
    known = {case['id'] for case in corpus['cases']}
    require(not set(args.case) - known, 'Unknown selected corpus case')
    cases = [case for case in corpus['cases'] if not args.case or case['id'] in args.case]
    require(cases and len({case['id'] for case in cases}) == len(cases), 'Empty or duplicate case inventory')
    require(all(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', case['id']) for case in cases), 'Unsafe case ID')
    identity = {'schema': SCHEMA, 'version': 1, 'parserDirectory': str(args.parser),
                'sourceCommit': args.expected_commit, 'sourceTree': tree,
                'corpusSha256': digest(corpus_path),
                'caseIds': [case['id'] for case in cases],
                'roundtripCyclesRequested': args.roundtrip_cycles, 'rasterDpi': args.dpi,
                'rasterStorage': 'gzip', 'dart': str(args.dart), 'office': str(args.office),
                'helperSha256': {'wrapper': digest(Path(__file__)),
                                 'sealer': digest(args.sealer), 'verifier': digest(args.verifier)}}
    index_path = args.output / 'index.json'
    if args.resume:
        require(index_path.is_file(), 'Resume requires this wrapper\'s existing index')
        index = json.loads(index_path.read_text())
        require(all(index.get(key) == value for key, value in identity.items()),
                'Resume provenance/options/helpers differ from the saved index')
    else:
        args.output.mkdir(parents=True, exist_ok=False)
        for name in ('runs', 'sealed', 'logs'):
            (args.output / name).mkdir()
        index = {**identity, 'status': 'running', 'startedAt': now(),
                 'method': 'Sequential independent run.py invocations; each separate compiler, environment and native report is retained. This is not one combined invocation.',
                 'cases': [], 'events': []}
        write_json(index_path, index)
    lock_path = args.output / 'wrapper.lock'
    with lock_path.open('x') as lock:
        lock.write(json.dumps({'pid': os.getpid(), 'startedAt': now()}) + '\n')
    active = None

    def checkpoint(stage, entry=None):
        index['updatedAt'] = now()
        index['events'].append({'time': index['updatedAt'], 'case': entry['id'] if entry else None,
                                'stage': stage, 'freeBytes': free_bytes(args.output)})
        if entry is not None:
            entry['stage'] = stage
        write_json(index_path, index)
        print(f"{index['updatedAt']} {entry['id'] if entry else 'corpus'}: {stage}; free={free_bytes(args.output) / MIB:.1f} MiB", flush=True)

    def terminate(signum, _frame):
        raise SystemExit(128 + signum)

    old_sigterm = signal.signal(signal.SIGTERM, terminate)
    try:
        # A resume that only needs read-only verification/cleanup can recover
        # space before another case; the first new measurement still needs 400 MiB.
        runner = load_runner(args.parser)
        first_new_measurement = True
        index['status'] = 'running'
        checkpoint('started' if not args.resume else 'resumed')
        by_id = {entry['id']: entry for entry in index['cases']}
        for ordinal, case in enumerate(cases, 1):
            require_source(args.parser, index['sourceCommit'], index['sourceTree'])
            stem = f'{ordinal:02d}-{case["id"]}'
            raw = args.output / 'runs' / stem
            sealed = args.output / 'sealed' / stem
            entry = by_id.get(case['id'])
            if entry is None:
                entry = {'id': case['id'], 'status': 'pending',
                         'rawDirectory': raw.relative_to(args.output).as_posix(),
                         'sealedDirectory': sealed.relative_to(args.output).as_posix()}
                index['cases'].append(entry)
                by_id[case['id']] = entry
            active = entry
            require(entry['rawDirectory'] == raw.relative_to(args.output).as_posix()
                    and entry['sealedDirectory'] == sealed.relative_to(args.output).as_posix(),
                    'Saved case directories differ')
            manifest_path = sealed / 'native-artifacts.manifest.json'
            if entry['status'] in ('complete', 'verified'):
                require(digest(manifest_path) == entry['sealedManifestSha256'], 'Completed seal manifest changed')
                run_logged([sys.executable, args.verifier, '--directory', sealed],
                           args.output / 'logs' / (stem + '-verify.log'), cwd=args.parser,
                           output=args.output, emergency_mib=None)
                if entry['status'] == 'complete':
                    require(not raw.exists(), 'Complete case unexpectedly has a raw run directory')
                elif raw.exists():
                    # A prior process can stop during or just after cleanup.
                    # Its index already bound the verified seal before deletion.
                    require_owned_raw(raw, args.output, entry)
                    if (raw / 'report.json').exists():
                        require(digest(raw / 'report.json') == entry['reportSha256'],
                                'Raw report changed after its verified seal')
                    shutil.rmtree(raw)
                entry.update(status='complete', completedAt=entry.get('completedAt', now()),
                             rawRemovedAfterVerification=True)
                checkpoint('completed-seal-reverified', entry)
                continue
            if not raw.exists():
                require(not sealed.exists(), 'Missing raw run beside an unfinished seal; inspect before resuming')
                threshold = args.start_free_mib if first_new_measurement else args.case_free_mib
                entry['freeBytesBeforeMeasurement'] = require_space(args.output, threshold, 'Starting a native case')
                first_new_measurement = False
                command = [sys.executable, args.parser / 'tool/fidelity/run.py',
                           '--office', args.office, '--dart', args.dart,
                           '--case', case['id'], '--roundtrip-cycles', str(args.roundtrip_cycles),
                           '--raster-storage', 'gzip', '--dpi', str(args.dpi), '--output', raw]
                entry.update(status='running', startedAt=now(), command=[str(value) for value in command])
                checkpoint('measurement-running', entry)
                environment = dict(os.environ, TMPDIR=str(raw / 'tmp'))
                run_logged(command, args.output / 'logs' / (stem + '-measure.log'),
                           cwd=args.parser, output=args.output, environment=environment,
                           emergency_mib=args.emergency_free_mib)
            require_owned_raw(raw, args.output, entry)
            report, measured, report_hash = validate_measurement(raw, case, args, runner, index)
            require_source(args.parser, index['sourceCommit'], index['sourceTree'])
            entry.update(status='measured', reportSha256=report_hash, summary=summarize(measured, report))
            checkpoint('measurement-verified', entry)
            if not sealed.exists():
                checkpoint('sealing', entry)
                run_logged([sys.executable, args.sealer, '--run', raw, '--parser', args.parser,
                            '--output', sealed], args.output / 'logs' / (stem + '-seal.log'),
                           cwd=args.parser, output=args.output, emergency_mib=args.emergency_free_mib)
            require(manifest_path.is_file() and not manifest_path.is_symlink(),
                    'Seal is incomplete; raw directory retained, nothing overwritten')
            manifest = json.loads(manifest_path.read_text())
            require(manifest['sourceCommit'] == index['sourceCommit']
                    and manifest['sourceWorktreeDirty'] is False
                    and manifest['report']['uncompressedSha256'] == report_hash,
                    'Sealed report/source provenance does not match this measurement')
            checkpoint('verifying-seal', entry)
            # Verification is read-only, so allow it to finish at low space and
            # enable safe cleanup of an already completed archive.
            run_logged([sys.executable, args.verifier, '--directory', sealed],
                       args.output / 'logs' / (stem + '-verify.log'), cwd=args.parser,
                       output=args.output, emergency_mib=None)
            require(digest(raw / 'report.json') == report_hash, 'Raw report changed while sealing')
            require_source(args.parser, index['sourceCommit'], index['sourceTree'])
            entry.update(status='verified', sealedManifestSha256=digest(manifest_path),
                         sealedReport=manifest['report'], sealedArchive=manifest['archive'],
                         sealedFileCount=manifest['fileCount'])
            checkpoint('seal-verified-before-cleanup', entry)
            require_owned_raw(raw, args.output, entry)
            shutil.rmtree(raw)
            entry.update(status='complete', completedAt=now(), rawRemovedAfterVerification=True)
            checkpoint('complete', entry)
        index['status'] = 'complete'
        index['completedAt'] = now()
        index['completedCases'] = len(index['cases'])
        index['completedRoundtripCycles'] = sum(entry['summary']['roundtripCyclesCompleted'] for entry in index['cases'])
        checkpoint('all-independent-cases-complete')
        return 0
    except BaseException as error:
        index['status'] = 'error'
        failure = {'time': now(), 'error': str(error), 'errorType': type(error).__name__}
        index.setdefault('failures', []).append(failure)
        if active is not None:
            active.setdefault('failures', []).append(failure)
        try:
            checkpoint('stopped-with-artifacts-retained', active)
        except OSError:
            print('Could not write new failure receipt; the previous atomic index remains.', flush=True)
        raise
    finally:
        signal.signal(signal.SIGTERM, old_sigterm)
        lock_path.unlink(missing_ok=True)


if __name__ == '__main__':
    raise SystemExit(main())

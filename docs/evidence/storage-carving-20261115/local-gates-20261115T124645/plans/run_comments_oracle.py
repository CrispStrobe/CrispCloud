#!/usr/bin/env python3
"""Generate fresh comments packages, bind their bytes, and run an independent reader."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


EXPECTED_OUTPUTS = ({f'comments-cycle-{cycle}.xlsx' for cycle in range(1, 4)}
                    | {f'collision-{kind}-{phase}.xlsx'
                       for kind in ('valid', 'malformed')
                       for phase in ('empty', 'added', 'cleared')}
                    | {'expected-comments.json', 'collision-cases.json'})


def fingerprint(path):
    data = path.read_bytes()
    return {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def now():
    return datetime.now(timezone.utc).isoformat()


def generated_inventory(folder):
    if not folder.is_dir() or folder.is_symlink():
        raise RuntimeError('Generator output directory is missing or is a symlink')
    paths = list(folder.iterdir())
    if {path.name for path in paths} != EXPECTED_OUTPUTS:
        raise RuntimeError('Generator output inventory differs from the eleven authored fixture files')
    if any(path.is_symlink() or not path.is_file() for path in paths):
        raise RuntimeError('Every generated output must be a regular file')
    return {path.name: fingerprint(path) for path in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--tested-head', required=True)
    parser.add_argument('--source-resolution-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.tested_head):
        parser.error('--tested-head must be an immutable full Git commit')
    if not re.fullmatch(r'[0-9a-f]{64}', args.source_resolution_sha256):
        parser.error('--source-resolution-sha256 must be the recorder input digest')
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error('Use a new output directory; retain every earlier attempt.')
    output.mkdir(parents=True, exist_ok=True)
    engine = repo / 'packages/quds_office_engine'
    fixture = engine / 'tool/fidelity/comment_schema_fixture.dart'
    verifier = Path(__file__).resolve().with_name('verify_comments.py')
    dart = args.dart.resolve(strict=True)
    generated = output / 'workbooks'
    report_path = output / 'reader-report.json'
    records = []
    tools_before = {}
    tools_after = {}
    generation = None
    report = {}
    failures = []
    code = 1

    def tool_inventory():
        return {str(path): fingerprint(path) for path in
                (Path(__file__).resolve(), fixture, verifier, dart, Path(sys.executable).resolve())}

    def head():
        return subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()

    def run(name, command):
        started = now()
        # Direct file capture retains partial output even if execution is interrupted.
        with (output / (name + '.stdout.log')).open('wb') as stdout, (output / (name + '.stderr.log')).open('wb') as stderr:
            try:
                result = subprocess.run(command, cwd=engine, stdout=stdout, stderr=stderr, check=False)
                returncode = result.returncode
            except (Exception, KeyboardInterrupt) as error:
                records.append({'name': name, 'argv': command, 'cwd': str(engine),
                                'started_at': started, 'finished_at': now(),
                                'returncode': None, 'exception': repr(error)})
                write_json(output / 'commands.json', records)
                raise
        records.append({'name': name, 'argv': command, 'cwd': str(engine),
                        'started_at': started, 'finished_at': now(), 'returncode': returncode})
        write_json(output / 'commands.json', records)
        if returncode != 0:
            raise RuntimeError(name + ' failed with return code ' + str(returncode))

    try:
        tools_before = tool_inventory()
        if head() != args.tested_head:
            raise RuntimeError('App HEAD differs from the supplied source-bound gate head')
        run('generate', [str(dart), 'run', str(fixture), str(generated)])
        # This is written before the independent reader can touch the generated files.
        generation = {'schema': 1, 'tested_head': args.tested_head,
                      'source_resolution_sha256': args.source_resolution_sha256,
                      'generated_at': now(), 'files': generated_inventory(generated),
                      'dart': {'path': str(dart), **tools_before[str(dart)]},
                      'generator': {'path': str(fixture), **tools_before[str(fixture)]},
                      'scope': 'Fresh outputs from the actual pinned Dart command, hashed before independent readback; the enclosing recorder proves stable source and resolution inputs.'}
        write_json(output / 'generation.json', generation)
        run('independent-reader', [sys.executable, str(verifier), '--input-dir', str(generated),
                                   '--report', str(report_path)])
        report = json.loads(report_path.read_text())
        if report.get('success') is not True:
            raise RuntimeError('Independent reader did not report success')
        if report.get('oracle_script_sha256') != tools_before[str(verifier)]['sha256']:
            raise RuntimeError('Independent reader script identity differs')
        expected_reader_inputs = {name: {'bytes': item['size'], 'sha256': item['sha256']}
                                  for name, item in generation['files'].items()}
        if (report.get('inputs_before') != expected_reader_inputs
                or report.get('inputs_after') != expected_reader_inputs
                or report.get('inputs_unchanged') is not True):
            raise RuntimeError('Independent reader inputs do not match the immediately bound generator outputs')
        if generated_inventory(generated) != generation['files']:
            raise RuntimeError('Generated output bytes changed after generation')
        tools_after = tool_inventory()
        if tools_before != tools_after or head() != args.tested_head:
            raise RuntimeError('The generator, reader, executable or app HEAD changed during this gate')
        code = 0
    except (Exception, KeyboardInterrupt) as error:
        failures.append(repr(error))
        code = 130 if isinstance(error, KeyboardInterrupt) else 1
    finally:
        if not tools_after:
            try:
                tools_after = tool_inventory()
            except Exception as error:
                failures.append('Final tool inventory failed: ' + repr(error))
                code = code or 1
        # Failed reader reports still carry useful individual failure diagnostics.
        if report_path.is_file() and not report:
            try:
                report = json.loads(report_path.read_text())
            except Exception as error:
                failures.append('Reader report could not be decoded: ' + repr(error))
                code = code or 1
        summary = {'schema': 2, 'success': code == 0 and not failures,
                   'tested_head': args.tested_head,
                   'source_resolution_sha256': args.source_resolution_sha256,
                   'commands': records, 'tools_before': tools_before, 'tools_after': tools_after,
                   'tools_unchanged': bool(tools_before) and tools_before == tools_after,
                   'generation_sha256': fingerprint(output / 'generation.json')['sha256'] if generation else None,
                   'reader_report_sha256': fingerprint(report_path)['sha256'] if report_path.is_file() else None,
                   'reader_success': report.get('success') is True,
                   'expected_outputs': sorted(EXPECTED_OUTPUTS), 'failures': failures,
                   'scope': 'Three repeated-save XLSX packages with six plain comments, plus six valid/invalid-root orphan-collision lifecycle packages. Independent ZIP/XML relationship and namespace checks, exact orphan bytes/relationship preservation, explicit empty authority, and openpyxl text/author reads. No broad Open XML schema or native Office rendering claim.'}
        write_json(output / 'summary.json', summary)
        files = {str(path.relative_to(output)): fingerprint(path) for path in sorted(output.rglob('*'))
                 if path.is_file() and path != output / 'artifacts-sha256.json'}
        write_json(output / 'artifacts-sha256.json', files)
        print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0 if summary['success'] else code or 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Merge Dart VM coverage and inventory every uncovered engine line.

The CLI requires a successful, unchanged collect_coverage.py receipt by default.
Use --allow-unverified only to inspect historical data; the result explicitly
marks collection provenance as unverified. Executed lines do not measure branch
coverage or certify that a line is correct.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from collect_coverage import RECEIPT, verify_receipt

ENGINE = Path(__file__).resolve().parents[2]
PACKAGE_PREFIX = 'package:quds_office_engine/'


def report_coverage(directory, root=ENGINE, *, require_receipt=False,
                    verify_collection=True):
    root = root.resolve()
    provenance = {'verified': False,
                  'reason': 'No verified successful collection receipt; current source hashes alone cannot establish when these hits were collected.'}
    if verify_collection and (require_receipt or (directory / RECEIPT).exists()):
        provenance = verify_receipt(directory, root)
    sources = {path.relative_to(root).as_posix(): path
               for path in sorted((root / 'lib').rglob('*.dart'))}
    if not sources:
        raise ValueError('No engine Dart sources found')
    source_lengths = {name: len(path.read_text().splitlines())
                      for name, path in sources.items()}
    merged = {}
    for path in sorted(directory.rglob('*.json')):
        if path == directory / RECEIPT:
            continue
        data = json.loads(path.read_text())
        if not isinstance(data, dict) or not isinstance(data.get('coverage'), list):
            raise ValueError(f'Malformed VM coverage record: {path}')
        for item in data.get('coverage', []):
            if not isinstance(item, dict) or not isinstance(item.get('source'), str):
                raise ValueError(f'Malformed VM coverage item: {path}')
            source = item['source']
            if not source.startswith(PACKAGE_PREFIX):
                continue
            name = 'lib/' + source[len(PACKAGE_PREFIX):]
            if name not in sources:
                raise ValueError(f'Coverage references missing or invalid engine source: {name}')
            hits = item.get('hits', [])
            if not isinstance(hits, list) or len(hits) % 2:
                raise ValueError(f'Malformed VM hit pairs: {name}')
            lines = merged.setdefault(name, {})
            for line, count in zip(hits[::2], hits[1::2]):
                if (type(line) is not int or type(count) is not int
                        or line < 1 or count < 0):
                    raise ValueError(f'Invalid VM line or hit count: {name}: {line}, {count}')
                if line > source_lengths[name]:
                    raise ValueError(f'Coverage exceeds current source length: {name}; rerun tests')
                lines[line] = lines.get(line, 0) + count
    merged = {name: hits for name, hits in merged.items() if hits}
    if not merged:
        raise ValueError('No engine coverage found; run dart test --coverage=coverage/vm')
    files = [{'path': name, 'hit': sum(count > 0 for count in hits.values()),
              'total': len(hits),
              'uncovered_lines': sorted(line for line, count in hits.items() if count == 0)}
             for name, hits in sorted(merged.items())]
    uninstrumented = sorted(set(sources) - set(merged))
    hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest()
              for name, path in sources.items()}
    components = {}
    for name in ('word', 'sheet', 'slide', 'pdf', 'reports'):
        prefix = f'lib/src/{name}/'
        subset = [file for file in files if file['path'].startswith(prefix)]
        components[name] = {
            'covered_lines': sum(file['hit'] for file in subset),
            'instrumented_lines': sum(file['total'] for file in subset),
            'uninstrumented_files': [path for path in uninstrumented if path.startswith(prefix)],
        }
    if provenance['verified']:
        # Detect an input/output change while the report was being assembled.
        if verify_receipt(directory, root) != provenance:
            raise ValueError('Collection provenance changed while building coverage report')
    return {
        'measurement': 'executed instrumented lines; not branch coverage',
        'collection': provenance,
        'source_tree_sha256': hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest(),
        'source_sha256': hashes,
        'components': components,
        'uninstrumented_files': uninstrumented,
        'covered_lines': sum(file['hit'] for file in files),
        'instrumented_lines': sum(file['total'] for file in files),
        'files': files,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=ENGINE / 'coverage/vm')
    parser.add_argument('--output', type=Path, default=ENGINE / 'build/fidelity/coverage-gaps.json')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--require-receipt', action='store_true',
                      help='require source-bound successful collection (the default)')
    mode.add_argument('--allow-unverified', action='store_true',
                      help='inspect historical unbound hits with an explicit unverified label')
    args = parser.parse_args()
    if args.output.resolve().is_relative_to(args.directory.resolve()):
        parser.error('Report output must be outside the raw coverage directory')
    # Reusing a report destination must not leave an earlier success behind if
    # validation fails or this process is interrupted before publishing a result.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    pending = {'status': 'running', 'coverage_directory': str(args.directory),
               'collection': {'verified': False, 'reason': 'Report validation has not completed'}}
    args.output.write_text(json.dumps(pending, indent=2) + '\n')
    try:
        report = report_coverage(args.directory, require_receipt=not args.allow_unverified)
    except BaseException as error:
        pending.update(status='failed', error=f'{type(error).__name__}: {error}')
        args.output.write_text(json.dumps(pending, indent=2) + '\n')
        raise
    report['status'] = 'complete'
    try:
        report['source_git_commit'] = subprocess.run(
            ['git', 'rev-parse', 'HEAD'], cwd=ENGINE, check=True,
            capture_output=True, text=True).stdout.strip()
        # Include newly added source files; git diff alone omits untracked files.
        report['source_git_dirty'] = bool(subprocess.run(
            ['git', 'status', '--porcelain', '--untracked-files=all', '--', 'lib'],
            cwd=ENGINE, check=True, capture_output=True, text=True).stdout.strip())
    except (OSError, subprocess.CalledProcessError):
        report['source_git_commit'], report['source_git_dirty'] = None, None
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    hit, total = report['covered_lines'], report['instrumented_lines']
    print(f'Engine coverage: {hit}/{total} instrumented lines ({100*hit/total:.1f}%).')
    print('Collection provenance: ' + ('verified source/output receipt'
                                     if report['collection']['verified'] else 'UNVERIFIED historical hits'))
    print('Largest uncovered files:')
    for file in sorted(report['files'], key=lambda item: item['total'] - item['hit'], reverse=True)[:10]:
        print(f"  {file['path']}: {file['total'] - file['hit']} uncovered lines")


if __name__ == '__main__':
    main()

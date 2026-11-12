#!/usr/bin/env python3
"""Inventory unhit Office host lines, requiring source-bound LCOV by default."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from collect_office_host_coverage import CollectionError, RECEIPT, verify_receipt

ROOT = Path(__file__).resolve().parents[1]


def office_sources(root):
    return sorted(path for directory in ('lib/services', 'lib/widgets')
                  for path in (root / directory).glob('office_*.dart'))


def report_coverage(lcov, root=ROOT):
    """Parse LCOV text only; use report_file to verify collection provenance."""
    root = root.resolve()
    sources = {path.relative_to(root).as_posix(): path for path in office_sources(root)}
    if not sources:
        raise ValueError('No Office host sources found')
    # Dart's coverage formatter emits unique DA lines, exact LF/LH totals and
    # end_of_record for each SF. Validate each record before merging repeated SF
    # entries, so truncated or contradictory output cannot shrink the denominator.
    merged, current = {}, None
    record_hits, summaries = {}, {}
    for entry in lcov.splitlines():
        if entry.startswith('SF:'):
            if current is not None:
                raise ValueError(f'LCOV record lacks end_of_record: {current}')
            path = Path(entry[3:])
            if not path.is_absolute():
                path = root / path
            try:
                name = path.resolve().relative_to(root).as_posix()
            except ValueError:
                name = None
            current = name if name in sources else None
            record_hits, summaries = {}, {}
        elif entry == 'end_of_record':
            if current is not None:
                expected = {'LF': len(record_hits),
                            'LH': sum(count > 0 for count in record_hits.values())}
                if summaries != expected:
                    raise ValueError(f'Missing or inconsistent LCOV LF/LH totals: {current}')
                hits = merged.setdefault(current, {})
                for line, count in record_hits.items():
                    hits[line] = hits.get(line, 0) + count
            current = None
        elif entry.startswith('DA:') and current is not None:
            fields = entry[3:].split(',')
            if len(fields) not in (2, 3):
                raise ValueError(f'Malformed LCOV line: {entry}')
            line, count = int(fields[0]), int(fields[1])
            if line < 1 or count < 0:
                raise ValueError(f'Invalid LCOV count: {entry}')
            if line in record_hits:
                raise ValueError(f'Duplicate LCOV DA line: {current}: {line}')
            record_hits[line] = count
        elif current is not None and entry.startswith(('LF:', 'LH:')):
            key, value = entry.split(':', 1)
            if key in summaries or int(value) < 0:
                raise ValueError(f'Invalid or duplicate LCOV summary: {entry}')
            summaries[key] = int(value)
    if current is not None:
        raise ValueError(f'LCOV record lacks end_of_record: {current}')
    merged = {name: hits for name, hits in merged.items() if hits}
    if not merged:
        raise ValueError('No Office host line coverage found; run the host Flutter suite with --coverage')
    hashes = {name: hashlib.sha256(path.read_bytes()).hexdigest()
              for name, path in sources.items()}
    files = []
    for name, hits in sorted(merged.items()):
        if max(hits) > len(sources[name].read_text().splitlines()):
            raise ValueError(f'Coverage exceeds current source length: {name}; rerun tests')
        files.append({'path': name, 'hit': sum(count > 0 for count in hits.values()),
                      'total': len(hits),
                      'uncovered_lines': sorted(line for line, count in hits.items() if count == 0)})
    return {'measurement': 'executed instrumented host lines; not branch coverage',
            'collection': {'verified': False, 'reason': 'LCOV text parsed without a collection receipt'},
            'scope': ['lib/services/office_*.dart', 'lib/widgets/office_*.dart'],
            'source_tree_sha256': hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest(),
            'source_sha256': hashes,
            'covered_lines': sum(file['hit'] for file in files),
            'instrumented_lines': sum(file['total'] for file in files),
            'uninstrumented_files': sorted(set(sources) - set(merged)), 'files': files}


def report_file(lcov, root=ROOT, *, require_receipt=True):
    """Historical mode permits a missing receipt, never a damaged existing one."""
    lcov = Path(lcov)
    receipt = lcov.parent / RECEIPT
    collection = None
    if require_receipt or receipt.exists() or receipt.is_symlink():
        collection = verify_receipt(lcov, root)
    report = report_coverage(lcov.read_text(encoding='utf-8'), root)
    if collection is not None:
        if verify_receipt(lcov, root) != collection:
            raise CollectionError('Collection provenance changed while building coverage report')
        report['collection'] = collection
    return report


def require_all_sources(report):
    """A smaller instrumented subset must not make the host gate look greener."""
    missing = report['uninstrumented_files']
    if missing:
        raise ValueError('Office host sources absent from coverage: ' + ', '.join(missing))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lcov', nargs='?', type=Path,
                        default=ROOT / 'build/fidelity-host/coverage/lcov.info')
    parser.add_argument('--output', type=Path,
                        default=ROOT / 'build/fidelity-host/coverage/gaps.json')
    parser.add_argument('--require-all-sources', action='store_true',
                        help='fail when any Office host source has no instrumented lines')
    verification = parser.add_mutually_exclusive_group()
    verification.add_argument('--require-receipt', dest='require_receipt', action='store_true',
                              help='require an exact-source successful collection receipt (default)')
    verification.add_argument('--allow-unverified', dest='require_receipt', action='store_false',
                              help='inspect historical LCOV without a receipt; report remains unverified')
    parser.set_defaults(require_receipt=True)
    args = parser.parse_args(argv)
    if args.output.resolve() in {args.lcov.resolve(), (args.lcov.parent / RECEIPT).resolve()}:
        parser.error('--output must not overwrite raw LCOV or its collection receipt')

    def write_report(report):
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

    # A failed retry (or interruption) must not leave an older successful summary.
    write_report({'status': 'pending', 'collection': {'verified': False},
                  'reason': 'Coverage validation has not completed.'})
    try:
        report = report_file(args.lcov, require_receipt=args.require_receipt)
        if args.require_all_sources:
            require_all_sources(report)
    except (OSError, ValueError) as error:
        write_report({'status': 'failed', 'collection': {'verified': False},
                      'error': str(error)})
        raise
    try:
        report['source_git_commit'] = subprocess.run(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, check=True,
            capture_output=True, text=True).stdout.strip()
        report['source_git_dirty'] = bool(subprocess.run(
            ['git', 'status', '--porcelain', '--untracked-files=all', '--',
             *report['source_sha256']],
            cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip())
    except (OSError, subprocess.CalledProcessError):
        report['source_git_commit'] = None
        report['source_git_dirty'] = None
    report['status'] = 'complete'
    write_report(report)
    hit, total = report['covered_lines'], report['instrumented_lines']
    print(f'Office host coverage: {hit}/{total} instrumented lines ({100*hit/total:.1f}%); '
          f'{len(report["uninstrumented_files"])} files absent from instrumentation.')
    if not report['collection']['verified']:
        print('Unverified historical LCOV: source/run provenance has not been established.')


if __name__ == '__main__':
    main()

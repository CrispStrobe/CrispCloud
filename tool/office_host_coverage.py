#!/usr/bin/env python3
"""Inventory unhit Office host lines from a fresh Flutter LCOV run."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def office_sources(root):
    return sorted(path for directory in ('lib/services', 'lib/widgets')
                  for path in (root / directory).glob('office_*.dart'))


def report_coverage(lcov, root=ROOT):
    root = root.resolve()
    sources = {path.relative_to(root).as_posix(): path for path in office_sources(root)}
    if not sources:
        raise ValueError('No Office host sources found')
    merged, current = {}, None
    for entry in lcov.splitlines():
        if entry.startswith('SF:'):
            path = Path(entry[3:])
            if not path.is_absolute():
                path = root / path
            try:
                name = path.resolve().relative_to(root).as_posix()
            except ValueError:
                name = None
            current = name if name in sources else None
            if current is not None:
                merged.setdefault(current, {})
        elif entry == 'end_of_record':
            current = None
        elif entry.startswith('DA:') and current is not None:
            fields = entry[3:].split(',')
            if len(fields) < 2:
                raise ValueError(f'Malformed LCOV line: {entry}')
            line, count = int(fields[0]), int(fields[1])
            if line < 1 or count < 0:
                raise ValueError(f'Invalid LCOV count: {entry}')
            hits = merged[current]
            hits[line] = hits.get(line, 0) + count
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
            'scope': ['lib/services/office_*.dart', 'lib/widgets/office_*.dart'],
            'source_tree_sha256': hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest(),
            'source_sha256': hashes,
            'covered_lines': sum(file['hit'] for file in files),
            'instrumented_lines': sum(file['total'] for file in files),
            'uninstrumented_files': sorted(set(sources) - set(merged)), 'files': files}


def require_all_sources(report):
    """A smaller instrumented subset must not make the host gate look greener."""
    missing = report['uninstrumented_files']
    if missing:
        raise ValueError('Office host sources absent from coverage: ' + ', '.join(missing))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lcov', nargs='?', type=Path,
                        default=ROOT / 'build/fidelity-host/coverage/lcov.info')
    parser.add_argument('--output', type=Path,
                        default=ROOT / 'build/fidelity-host/coverage/gaps.json')
    parser.add_argument('--require-all-sources', action='store_true',
                        help='fail when any Office host source has no instrumented lines')
    args = parser.parse_args()
    report = report_coverage(args.lcov.read_text())
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
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    hit, total = report['covered_lines'], report['instrumented_lines']
    print(f'Office host coverage: {hit}/{total} instrumented lines ({100*hit/total:.1f}%); '
          f'{len(report["uninstrumented_files"])} files absent from instrumentation.')
    if args.require_all_sources:
        require_all_sources(report)


if __name__ == '__main__':
    main()

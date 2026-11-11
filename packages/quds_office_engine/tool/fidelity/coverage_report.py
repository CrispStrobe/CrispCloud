#!/usr/bin/env python3
"""Merge fresh Dart VM coverage and inventory every uncovered engine line.

The source fingerprint records the files present when this report is made.
Always collect into a fresh coverage directory: stale data from a same-length
source edit cannot be detected from VM hit counts alone. Executed lines do not
measure branch coverage or certify that a line is correct.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ENGINE = Path(__file__).resolve().parents[2]
PACKAGE_PREFIX = 'package:quds_office_engine/'


def report_coverage(directory, root=ENGINE):
    root = root.resolve()
    sources = {path.relative_to(root).as_posix(): path
               for path in sorted((root / 'lib').rglob('*.dart'))}
    if not sources:
        raise ValueError('No engine Dart sources found')
    source_lengths = {name: len(path.read_text().splitlines())
                      for name, path in sources.items()}
    merged = {}
    for path in sorted(directory.rglob('*.json')):
        data = json.loads(path.read_text())
        for item in data.get('coverage', []):
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
    return {
        'measurement': 'executed instrumented lines; not branch coverage',
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
    args = parser.parse_args()
    report = report_coverage(args.directory)
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
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    hit, total = report['covered_lines'], report['instrumented_lines']
    print(f'Engine coverage: {hit}/{total} instrumented lines ({100*hit/total:.1f}%).')
    print('Largest uncovered files:')
    for file in sorted(report['files'], key=lambda item: item['total'] - item['hit'], reverse=True)[:10]:
        print(f"  {file['path']}: {file['total'] - file['hit']} uncovered lines")


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Merge Dart VM coverage and retain every uncovered engine line as a gap."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('directory', type=Path, nargs='?', default=Path('coverage/vm'))
p.add_argument('--output', type=Path, default=Path('build/fidelity/coverage-gaps.json'))
a = p.parse_args()
merged = {}
for path in a.directory.rglob('*.json'):
    data = json.loads(path.read_text())
    for item in data.get('coverage', []):
        source = item['source']
        if not source.startswith('package:quds_office_engine/'): continue
        source = 'lib/' + source.split('/', 1)[1]
        lines = merged.setdefault(source, {})
        hits = item.get('hits', [])
        for line, count in zip(hits[::2], hits[1::2]):
            lines[line] = lines.get(line, 0) + count
if not merged: raise SystemExit('No engine coverage found; run dart test --coverage=coverage/vm')
files = [{'path': path, 'hit': sum(v > 0 for v in lines.values()), 'total': len(lines),
          'uncovered_lines': sorted(k for k, v in lines.items() if v == 0)} for path, lines in sorted(merged.items())]
uninstrumented = sorted(str(p) for p in Path('lib').rglob('*.dart') if str(p) not in merged)
source_hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in sorted(Path('lib').rglob('*.dart'))}
fingerprint = hashlib.sha256(json.dumps(source_hashes, sort_keys=True).encode()).hexdigest()
components = {}
for name in ('word', 'sheet', 'slide', 'pdf', 'reports'):
    prefix = f'lib/src/{name}/'
    subset = [file for file in files if file['path'].startswith(prefix)]
    components[name] = {'covered_lines': sum(file['hit'] for file in subset),
                        'instrumented_lines': sum(file['total'] for file in subset),
                        'uninstrumented_files': [path for path in uninstrumented if path.startswith(prefix)]}
try:
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], check=True,
                              capture_output=True, text=True).stdout.strip()
    source_dirty = subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', 'lib'],
                                  capture_output=True).returncode != 0
except (OSError, subprocess.CalledProcessError):
    revision, source_dirty = None, None
report = {'measurement': 'executed instrumented lines; not branch coverage',
          'source_git_commit': revision, 'source_git_dirty': source_dirty,
          'source_tree_sha256': fingerprint, 'source_sha256': source_hashes, 'components': components,
          'uninstrumented_files': uninstrumented, 'covered_lines': sum(f['hit'] for f in files),
          'instrumented_lines': sum(f['total'] for f in files), 'files': files}
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(report, indent=2)+'\n')
print(f"Engine coverage: {report['covered_lines']}/{report['instrumented_lines']} instrumented lines ({100*report['covered_lines']/report['instrumented_lines']:.1f}%).")
print('Largest uncovered files:')
for f in sorted(files, key=lambda f: f['total']-f['hit'], reverse=True)[:10]:
    print(f"  {f['path']}: {f['total']-f['hit']} uncovered lines")

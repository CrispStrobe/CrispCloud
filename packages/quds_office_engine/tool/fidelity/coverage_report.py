#!/usr/bin/env python3
"""Merge Dart VM coverage and retain every uncovered engine line as a gap."""
import argparse
import json
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
report = {'uninstrumented_files': uninstrumented, 'covered_lines': sum(f['hit'] for f in files), 'instrumented_lines': sum(f['total'] for f in files), 'files': files}
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(report, indent=2)+'\n')
print(f"Engine coverage: {report['covered_lines']}/{report['instrumented_lines']} instrumented lines ({100*report['covered_lines']/report['instrumented_lines']:.1f}%).")
print('Largest uncovered files:')
for f in sorted(files, key=lambda f: f['total']-f['hit'], reverse=True)[:10]:
    print(f"  {f['path']}: {f['total']-f['hit']} uncovered lines")

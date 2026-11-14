#!/usr/bin/env python3
"""Copy current tracked source plus new Dart fixtures to the isolated test tree."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

root = Path(__file__).resolve().parent
source = root.parent / 'crispcloud'
target = root / 'app-validation'
if (root / 'validation-running').exists():
    raise SystemExit('Validation is running; do not change its source snapshot')
names = subprocess.check_output(
    ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    cwd=source).decode().split('\0')
files = {}
updated = []
for name in sorted(set(names)):
    if not name or name.startswith('docs/'):
        continue
    src = source / name
    if not src.is_file():
        continue
    data = src.read_bytes()
    dest = target / name
    digest = hashlib.sha256(data).hexdigest()
    if not dest.exists() or hashlib.sha256(dest.read_bytes()).hexdigest() != digest:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        updated.append(name)
    files[name] = digest
record = {
    'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source).decode().strip(),
    'source_dirty': subprocess.check_output(['git', 'status', '--porcelain'], cwd=source).decode(),
    'files': files,
}
(root / 'validation-source-sync.json').write_text(json.dumps(record, indent=2)+'\n')
print(json.dumps({'source_head': record['source_head'], 'files': len(files), 'updated': updated}))

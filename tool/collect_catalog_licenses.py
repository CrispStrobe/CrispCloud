#!/usr/bin/env python3
"""Bundle licence texts for the locked catalogue graph selected on this host."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
cargo = os.environ.get('CARGO') or shutil.which('cargo') or str(Path.home() / '.cargo/bin/cargo')
rustc = shutil.which('rustc') or str(Path.home() / '.cargo/bin/rustc')
host = next(line.split(': ', 1)[1] for line in subprocess.check_output([rustc, '-vV'], text=True).splitlines() if line.startswith('host: '))
metadata = json.loads(subprocess.check_output([
    cargo, 'metadata', '--locked', '--format-version', '1', '--filter-platform', host,
    '--manifest-path', str(root / 'packages/crisp_catalog/native/Cargo.toml'),
], text=True))
nodes = {node['id']: node for node in metadata['resolve']['nodes']}
selected = set()
pending = [metadata['resolve']['root']]
while pending:
    key = pending.pop()
    if key in selected:
        continue
    selected.add(key)
    pending.extend(dep['pkg'] for dep in nodes[key]['deps'])
args.output.mkdir(parents=True, exist_ok=True)
records = []
for package in metadata['packages']:
    if package['id'] not in selected:
        continue
    base = Path(package['manifest_path']).parent
    texts = [file for file in base.iterdir() if file.is_file() and file.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE', 'UNLICENSE'))]
    if package.get('license_file'):
        texts.append(base / package['license_file'])
    if not texts:
        raise SystemExit(f"No licence text found for {package['name']} {package['version']}")
    target = args.output / f"{package['name']}-{package['version']}"
    target.mkdir(exist_ok=True)
    for file in set(texts):
        if file.is_symlink() or file.stat().st_size > 256 * 1024:
            raise SystemExit(f'Unexpected licence file: {file}')
        shutil.copyfile(file, target / file.name)
    records.append({'name': package['name'], 'version': package['version'], 'license': package.get('license'), 'repository': package.get('repository')})
(args.output / 'packages.json').write_text(json.dumps({'target': host, 'packages': records}, indent=2) + '\n')
print(f'Collected catalogue licence texts for {len(records)} locked packages ({host}).')

#!/usr/bin/env python3
"""Build both CLI names and publish one complete native-assets bundle."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--dart', default=shutil.which('dart') or 'dart')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
output = (args.output or root / 'cli/build/cli').resolve()
if output == root or output == root / 'cli' or output in root.parents:
    raise SystemExit('Choose a CLI build output directory.')
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='.crispcloud-cli-', dir=output.parent) as work:
    work = Path(work)
    for name in ['crispcloud', 'crisp']:
        subprocess.run([args.dart, 'build', 'cli', '--target', f'bin/{name}.dart', '-o', str(work / name)], cwd=root / 'cli', check=True)
    bundle = work / 'crispcloud/bundle'
    compatibility = work / 'crisp/bundle'
    for file in compatibility.rglob('*'):
        if not file.is_file():
            continue
        target = bundle / file.relative_to(compatibility)
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            if hashlib.sha256(target.read_bytes()).digest() != hashlib.sha256(file.read_bytes()).digest():
                raise SystemExit(f'Native asset differs between CLI names: {file.name}')
        else:
            shutil.copy2(file, target)
    shutil.copy2(root / 'packages/crisp_storage/NOTICE-LIBSMB2.txt', bundle)
    if (root / 'LICENSE').exists():
        shutil.copy2(root / 'LICENSE', bundle / 'LICENSE-CRISPCLOUD.txt')
    shutil.copy2(root / 'packages/crisp_catalog/README.md', bundle / 'CATALOG-README.md')
    subprocess.run([sys.executable, str(root / 'tool/collect_catalog_licenses.py'), '--output', str(bundle / 'catalog-licenses')], check=True)
    destination = output / 'bundle'
    backup = output / f'.previous-bundle-{uuid.uuid4().hex}'
    moved = False
    try:
        if destination.exists():
            destination.rename(backup)
            moved = True
        bundle.rename(destination)
    except BaseException:
        if moved and not destination.exists():
            backup.rename(destination)
        raise
    if moved:
        shutil.rmtree(backup)
print(f'Built crispcloud and crisp with native libraries and notices: {output / "bundle"}')

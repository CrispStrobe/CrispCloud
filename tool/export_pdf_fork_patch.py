#!/usr/bin/env python3
"""Export and verify the staged extension tree in the pinned PDF checkout."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


PIN = '87adaa022c5ed6b22ca3232b6cae4a03e8389e98'
ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, required=True)
    args = parser.parse_args()
    source = args.upstream.resolve()

    def git(*arguments: str, env=None) -> bytes:
        return subprocess.check_output(['git', '-C', str(source), *arguments], env=env)

    if git('rev-parse', 'HEAD').decode().strip() != PIN:
        raise SystemExit('The extension checkout must have the recorded base at HEAD.')
    subprocess.run(['git', '-C', str(source), 'diff', '--quiet'], check=True)
    # Runtime code must be exactly the code exercised by the host workflows.
    for package in ('pdf_document', 'pdf_operations'):
        directory = ROOT / 'packages' / package / 'lib'
        for path in directory.rglob('*.dart'):
            counterpart = source / path.relative_to(ROOT)
            if path.read_bytes() != counterpart.read_bytes():
                raise SystemExit(f'Unsynchronized runtime: {path.relative_to(ROOT)}')
    insertion = Path('packages/dart_pdf_editor/lib/src/insert_pages_dialog.dart')
    if (ROOT / insertion).read_bytes() != (source / insertion).read_bytes():
        raise SystemExit('Unsynchronized editor insertion API')

    patch = git('diff', '--cached', '--binary', PIN)
    expected = git('write-tree').decode().strip()
    (ROOT / 'build').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='pdf-fork-', dir=ROOT / 'build') as temp:
        temporary = Path(temp)
        patch_file = temporary / 'fork.patch'
        patch_file.write_bytes(patch)
        environment = dict(os.environ)
        environment['GIT_INDEX_FILE'] = str(temporary / 'index')
        git('read-tree', PIN, env=environment)
        git('apply', '--cached', '--check', str(patch_file), env=environment)
        git('apply', '--cached', str(patch_file), env=environment)
        actual = git('write-tree', env=environment).decode().strip()
        if actual != expected:
            raise RuntimeError(f'Reconstructed tree differs: {actual} != {expected}')

    output = ROOT / 'packages/pdf_fork_transfer'
    output.mkdir(exist_ok=True)
    (output / 'fork.patch').write_bytes(patch)
    manifest = {
        'upstream': 'https://github.com/ben-milanko/dart-pdf',
        'baseCommit': PIN,
        'expectedTree': expected,
        'patchSha256': hashlib.sha256(patch).hexdigest(),
        'intendedRepository': 'CrispStrobe/dart-pdf',
        'featureBranch': 'feature/crispcloud-pdf-operations',
        'status': 'fork creation awaiting authenticated access',
    }
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Verified fork patch ({len(patch)} bytes), tree {expected}')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Rebuild and verify the maintained PDF runtime patches against pinned upstream."""

from __future__ import annotations

import argparse
import io
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile


PIN = '87adaa022c5ed6b22ca3232b6cae4a03e8389e98'
ROOT = Path(__file__).resolve().parents[1]
METADATA = ('LICENSE', 'README.md', 'CHANGELOG.md', 'pubspec.yaml',
            'analysis_options.yaml')


def rebuild(upstream: Path, package: str, write: bool) -> None:
    relative = Path('packages') / package
    parts = [*METADATA, 'lib']
    if package == 'dart_pdf_editor':
        parts += ['shaders', 'l10n.yaml']
    with tempfile.TemporaryDirectory(prefix='pdf-vendor-', dir=ROOT / 'build') as temp:
        directory = Path(temp)
        base, current = directory / 'base', directory / 'current'
        base.mkdir()
        current.mkdir()
        archive = subprocess.check_output(
            ['git', '-C', str(upstream), 'archive', PIN,
             *[str(relative / part) for part in parts]])
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(base, filter='data')
        for part in parts:
            source, destination = ROOT / relative / part, current / relative / part
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, destination)
            else:
                shutil.copy2(source, destination)
        diff = subprocess.run(
            ['git', 'diff', '--no-index', '--binary',
             str(Path('base') / relative), str(Path('current') / relative)],
            cwd=directory, capture_output=True, check=False)
        if diff.returncode not in (0, 1):
            raise RuntimeError(diff.stderr.decode())
        patch = diff.stdout.replace(b'a/base/', b'a/').replace(b'b/current/', b'b/')
        patch_file = directory / 'changes.patch'
        patch_file.write_bytes(patch)
        # Isolate git apply from the containing application's repository: a
        # subdirectory prefix can otherwise make it silently skip the paths.
        subprocess.run(['git', 'init', '--quiet'], cwd=base, check=True)
        subprocess.run(['git', 'apply', '--check', str(patch_file)], cwd=base, check=True)
        subprocess.run(['git', 'apply', str(patch_file)], cwd=base, check=True)
        expected = {p.relative_to(current): p.read_bytes()
                    for p in current.rglob('*') if p.is_file()}
        actual = {p.relative_to(base): p.read_bytes()
                  for p in base.rglob('*')
                  if p.is_file() and '.git' not in p.relative_to(base).parts}
        if expected != actual:
            raise RuntimeError(f'{package}: reconstructed files differ')
        target = ROOT / relative / 'UPSTREAM.patch'
        if write:
            target.write_bytes(patch)
        elif not target.exists() or target.read_bytes() != patch:
            raise SystemExit(f'{target}: patch is out of date; run with --write')
        print(f'{package}: verified {len(expected)} files against {PIN}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, required=True,
                        help='Local checkout containing the immutable upstream commit')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    (ROOT / 'build').mkdir(exist_ok=True)
    for package in ('dart_pdf_editor', 'pdf_document'):
        rebuild(args.upstream.resolve(), package, args.write)


if __name__ == '__main__':
    main()

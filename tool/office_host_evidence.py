#!/usr/bin/env python3
"""Require all actual Office host exports before reporting schema validation."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree
from zipfile import BadZipFile, ZipFile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = Path(__file__).with_suffix('.json')
REPORT = 'build/fidelity-host/inventory.json'
MAIN_PARTS = {
    '.docx': ('word/document.xml',
              '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}document'),
    '.xlsx': ('xl/workbook.xml',
              '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}workbook'),
    '.pptx': ('ppt/presentation.xml',
              '{http://schemas.openxmlformats.org/presentationml/2006/main}presentation'),
}
for extension in ('.docm', '.dotx', '.dotm'):
    MAIN_PARTS[extension] = MAIN_PARTS['.docx']
OFFICE = set(MAIN_PARTS)


def expected_paths():
    paths = json.loads(MANIFEST.read_text())['outputs']
    if not paths or len(paths) != len(set(paths)):
        raise ValueError('Host evidence manifest must be nonempty and unique')
    for name in paths:
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or path.suffix not in OFFICE:
            raise ValueError(f'Invalid host evidence path: {name}')
    return paths


def clean(root):
    """Remove only the declared artifacts and this helper's previous receipt."""
    root = root.resolve()
    targets = [root / name for name in [*expected_paths(), REPORT]]
    # Preflight the whole cleanup before removing any previous evidence.
    for target in targets:
        current = target
        while current != root:
            if current.is_symlink():
                raise ValueError(f'Refusing symlink in host cleanup path: {current}')
            current = current.parent
        if target.exists() and not target.is_file():
            raise ValueError(f'Host artifact is not a file: {target}')
    for target in targets:
        target.unlink(missing_ok=True)


def inspect(root):
    root = root.resolve()
    expected = expected_paths()
    # GitHub artifact downloads may add a directory around the original tree.
    # Match the complete build/... suffix, never a filename from engine output.
    bases = {
        directory.parent.parent
        for directory in root.rglob('fidelity-host')
        if directory.is_dir() and directory.parent.name == 'build'
    }
    bases.add(root)
    files = []
    failures = []
    used_bases = set()
    for name in expected:
        matches = sorted(base / name for base in bases if (base / name).is_file())
        if len(matches) != 1:
            failures.append(f'{name}: expected one file, found {len(matches)}')
            continue
        file = matches[0]
        if not file.resolve().is_relative_to(root):
            failures.append(f'{name}: file escapes the evidence directory')
            continue
        used_bases.add(file.parents[len(PurePosixPath(name).parts) - 1])
        extension = PurePosixPath(name).suffix
        try:
            with ZipFile(file) as archive:
                main_part, root_tag = MAIN_PARTS[extension]
                if main_part not in archive.namelist():
                    raise ValueError(f'missing main part {main_part}')
                if ElementTree.fromstring(archive.read(main_part)).tag != root_tag:
                    raise ValueError(f'wrong document root in {main_part}')
                if archive.testzip() is not None:
                    raise ValueError('damaged ZIP entry')
            content = file.read_bytes()
        except (BadZipFile, OSError, ValueError, ElementTree.ParseError) as error:
            failures.append(f'{name}: invalid {extension[1:].upper()}: {error}')
            continue
        files.append({
            'path': name,
            'file': str(file.relative_to(root)),
            'bytes': len(content),
            'sha256': hashlib.sha256(content).hexdigest(),
        })
    if len(used_bases) > 1:
        failures.append('Required host files are spread across different artifact roots')
    for base in used_bases:
        for directory in ('build/fidelity-host', 'build/fidelity',
                          'build/fidelity-custom-tabs'):
            for file in (base / directory).rglob('*'):
                if (file.is_file() and file.suffix.lower() in OFFICE
                        and file.relative_to(base).as_posix() not in expected):
                    failures.append(f'Unexpected host Office output: {file.relative_to(base)}')
    return {
        'expected': len(expected),
        'verified': len(files),
        'manifest_sha256': hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
        'files': files,
        'failures': failures,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['clean', 'verify'])
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.command == 'clean':
        clean(args.root)
        print(f'Cleared only {len(expected_paths())} declared host outputs and receipt')
        return 0
    report = inspect(args.root)
    output = args.report or args.root / REPORT
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    for failure in report['failures']:
        print(failure)
    print(f"Host inventory: {report['verified']}/{report['expected']} verified; "
          f"{len(report['failures'])} failures; receipt {output}")
    return int(bool(report['failures']))


if __name__ == '__main__':
    raise SystemExit(main())

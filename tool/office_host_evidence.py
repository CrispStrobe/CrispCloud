#!/usr/bin/env python3
"""Require all actual Office host exports before reporting schema validation."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import posixpath
from urllib.parse import unquote, urlsplit
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = Path(__file__).with_suffix('.json')
REPORT = 'build/fidelity-host/inventory.json'
OFFICE = {'.docx', '.xlsx', '.pptx'}
PACKAGE_REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CONTENT_TYPES = 'http://schemas.openxmlformats.org/package/2006/content-types'
MAIN_TYPES = {
    '.docx': ('wordprocessingml.document', 'wordprocessingml', 'document'),
    '.xlsx': ('spreadsheetml.sheet', 'spreadsheetml', 'workbook'),
    '.pptx': ('presentationml.presentation', 'presentationml', 'presentation'),
}


def expected_paths():
    data = json.loads(MANIFEST.read_text())
    paths = data.get('outputs') if isinstance(data, dict) else None
    if (not isinstance(data, dict) or data.get('version') != 1
            or not isinstance(paths, list) or not paths
            or any(not isinstance(name, str) for name in paths)
            or len(paths) != len(set(paths))):
        raise ValueError('Host evidence manifest must be nonempty and unique')
    for name in paths:
        path = PurePosixPath(name)
        if (path.is_absolute() or '..' in path.parts or '\\' in name
                or str(path) != name or path.suffix not in OFFICE
                or path.parts[:2] not in (('build', 'fidelity-host'), ('build', 'fidelity'))):
            raise ValueError(f'Invalid host evidence path: {name}')
    return paths


def inspect_package(file):
    """Require the expected format through the owning OPC relationship.

    This is an artifact-integrity check; the Open XML SDK remains responsible
    for schema validation. Main parts may be relocated within the package.
    """
    content_type, namespace, local_name = MAIN_TYPES[file.suffix.lower()]
    with ZipFile(file) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('duplicate ZIP member names')
        if not {'[Content_Types].xml', '_rels/.rels'}.issubset(names):
            raise ValueError('missing OPC content types or package relationships')
        if archive.testzip() is not None:
            raise ValueError('damaged ZIP entry')
        relationships = ET.fromstring(archive.read('_rels/.rels'))
        if relationships.tag != f'{{{PACKAGE_REL}}}Relationships':
            raise ValueError('invalid package relationships namespace')
        main_relationships = [r for r in relationships if r.get('Type') in {
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
            'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument',
        }]
        if len(main_relationships) != 1:
            raise ValueError('expected exactly one Office main-part relationship')
        relation = main_relationships[0]
        target = relation.get('Target', '')
        uri = urlsplit(target)
        if relation.get('TargetMode', 'Internal') != 'Internal' or uri.scheme or uri.netloc or uri.query or uri.fragment:
            raise ValueError('Office main part must be an internal package target')
        decoded = unquote(uri.path)
        if not decoded or '\\' in decoded:
            raise ValueError('invalid Office main-part target')
        main = posixpath.normpath(decoded.lstrip('/'))
        if main in ('.', '..') or main.startswith('../') or main not in names:
            raise ValueError('missing or escaping Office main part')
        types = ET.fromstring(archive.read('[Content_Types].xml'))
        if types.tag != f'{{{CONTENT_TYPES}}}Types':
            raise ValueError('invalid content-types namespace')
        matches = [entry.get('ContentType') for entry in types.findall(f'{{{CONTENT_TYPES}}}Override')
                   if unquote(entry.get('PartName', '')).lstrip('/') == main]
        expected_type = f'application/vnd.openxmlformats-officedocument.{content_type}.main+xml'
        if matches != [expected_type]:
            raise ValueError('Office main-part content type does not match filename format')
        document = ET.fromstring(archive.read(main))
        if document.tag not in {
            f'{{http://schemas.openxmlformats.org/{namespace}/2006/main}}{local_name}',
            f'{{http://purl.oclc.org/ooxml/{namespace}/main}}{local_name}',
        }:
            raise ValueError('Office main-part root does not match filename format')
    return main


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
        try:
            main_part = inspect_package(file)
            content = file.read_bytes()
        except (BadZipFile, OSError, ValueError, ET.ParseError, KeyError) as error:
            failures.append(f'{name}: invalid Office package: {error}')
            continue
        files.append({
            'path': name,
            'file': str(file.relative_to(root)),
            'bytes': len(content),
            'sha256': hashlib.sha256(content).hexdigest(),
            'format': file.suffix.lower()[1:],
            'main_part': main_part,
        })
    if len(used_bases) > 1:
        failures.append('Required host files are spread across different artifact roots')
    for base in used_bases:
        for directory in ('build/fidelity-host', 'build/fidelity'):
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

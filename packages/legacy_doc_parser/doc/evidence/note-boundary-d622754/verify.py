#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify this sealed native receipt, optionally extracting its exact files."""
import argparse
from collections import Counter
import hashlib
import io
import json
import lzma
from pathlib import Path, PurePosixPath
import tarfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify(base, extract=None):
    manifest = json.loads((base / 'manifest.json').read_text())
    summary = json.loads((base / 'summary.json').read_text())
    reports = {}
    for name, expected in manifest['reports'].items():
        compressed = (base / name).read_bytes()
        require(sha(compressed) == expected['compressedSha256'], 'Compressed report changed')
        data = lzma.decompress(compressed)
        require(len(data) == expected['uncompressedBytes']
                and sha(data) == expected['uncompressedSha256'], 'Raw report changed')
        reports[name] = json.loads(data)
    report = reports['native-report.json.xz']
    schema = reports['schema-report.json.xz']
    require(report['parserCommit'] == manifest['parserCommit'] == summary['parserCommit'],
            'Parser source identities disagree')
    require(report['sourceUnchanged'] is True, 'Measured source changed')
    # The original global SDK failure remains red. This verifier does not turn
    # the native-export errors into a passing whole-corpus validation result.
    require(report['writerContractPassed'] is False
            and report['allNativeComparisonsExact'] is False
            and report['errors'] == ['ValueError: Open XML SDK rejected the corpus with 48 schema errors'],
            'Original red aggregate result changed')
    expected_ids = {f'{kind}-{name}' for kind in ('footnote', 'endnote') for name in (
        'plain', 'empty', 'trailing-blank', 'two-trailing-blanks',
        'table', 'table-blank', 'table-two-blanks', 'table-text')}
    require(len(report['cases']) == 16 and {case['id'] for case in report['cases']} == expected_ids,
            'Native case coverage changed')
    for case in report['cases']:
        require(case['completed'] and not case['errors']
                and [cycle['index'] for cycle in case['cycles']] == [0, 1, 2, 3],
                'Incomplete native cycle sequence')
        require(all(cycle['writerPreservesSourceBlocks'] and cycle['sourceUnchanged']
                    and cycle['binaryUnchanged'] for cycle in case['cycles']),
                'Writer or source-integrity check failed')

    archive = (base / manifest['archive']['path']).read_bytes()
    require(len(archive) == manifest['archive']['bytes']
            and sha(archive) == manifest['archive']['sha256'], 'Archive changed')
    records = manifest['files']
    require(len(records) == manifest['fileCount'] == 304, 'Artifact count changed')
    require([item['path'] for item in records] == sorted(report['artifacts']),
            'Manifest differs from exact recorded artifact inventory')
    require(sum(item['bytes'] for item in records) == manifest['rawBytes'], 'Byte total changed')
    require(dict(Counter(PurePosixPath(item['path']).suffix for item in records))
            == manifest['types'] == {'.doc': 64, '.docx': 96, '.pdf': 144}, 'File type counts changed')
    contents = {}
    with tarfile.open(fileobj=io.BytesIO(lzma.decompress(archive)), mode='r:') as package:
        members = package.getmembers()
        require(len(members) == len(records), 'Archive contains extra or missing entries')
        for member, record in zip(members, records):
            name = member.name
            path = PurePosixPath(name)
            require(name == record['path'] and name == path.as_posix() and not path.is_absolute()
                    and '\\' not in name and not any(part in ('', '.', '..') for part in name.split('/')),
                    'Unsafe or unexpected archive path')
            require(member.isreg() and member.type == tarfile.REGTYPE
                    and member.mode == 0o644 and member.uid == member.gid == member.mtime == 0
                    and member.uname == member.gname == '' and not member.pax_headers
                    and not member.linkname, 'Unexpected archive metadata or file type')
            data = package.extractfile(member).read()
            require(len(data) == member.size == record['bytes']
                    and sha(data) == record['sha256'] == report['artifacts'][name],
                    'Archived bytes disagree with the measured file')
            contents[name] = data
    rebuilt = io.BytesIO()
    with tarfile.open(fileobj=rebuilt, mode='w', format=tarfile.USTAR_FORMAT) as package:
        for name, data in contents.items():
            item = tarfile.TarInfo(name)
            item.size, item.mode = len(data), 0o644
            item.uid = item.gid = item.mtime = 0
            item.uname = item.gname = ''
            package.addfile(item, io.BytesIO(data))
    require(lzma.compress(rebuilt.getvalue(), format=lzma.FORMAT_XZ,
                          check=lzma.CHECK_CRC64, preset=9) == archive,
            'Deterministic archive rebuild differs')

    expected_docx = {name: sha(data) for name, data in contents.items() if name.endswith('.docx')}
    actual_docx = {}
    route_counts = Counter()
    route_errors = Counter()
    for item in schema['Reports']:
        name = Path(item['File']).relative_to(manifest['sourceOutputDirectory']).as_posix()
        require(name in expected_docx and name not in actual_docx
                and item['Sha256'] == expected_docx[name]
                and 'Exception' not in item and isinstance(item['Errors'], list),
                'SDK coverage, file hash or execution failed')
        actual_docx[name] = item['Sha256']
        route = ('native' if '/native-docx/' in name else
                 'parser' if name.endswith('/converted.docx') else 'authored')
        route_counts[route] += 1
        route_errors[route] += len(item['Errors'])
        require(all(error.get('Id') for error in item['Errors']), 'Malformed SDK error')
    require(actual_docx == expected_docx and schema['Files'] == 96
            and schema['Failures'] == sum(route_errors.values()) == 48,
            'SDK total or complete exact-file coverage changed')
    require(route_counts == {'authored': 16, 'parser': 64, 'native': 16}
            and route_errors == {'authored': 0, 'parser': 0, 'native': 48},
            'Schema results differ from the recorded route attribution')
    require(summary['rawWriterBlockChecks'] == 64 and summary['completedRoundtripImports'] == 48,
            'Summary coverage changed')
    for route, count in route_counts.items():
        result = summary['sdkRoutes'][route]
        require(result['files'] == count and result['errors'] == route_errors[route]
                and result['valid'] == (route_errors[route] == 0) and result['hashesVerified'],
                'Summary schema attribution differs')
    if extract is not None:
        extract.mkdir(parents=True, exist_ok=False)
        for name, data in contents.items():
            destination = extract / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open('xb') as output:
                output.write(data)
            require(destination.read_bytes() == data, 'Extracted file differs')
    return {'files': len(contents), 'rawBytes': manifest['rawBytes'],
            'writerBlockChecks': 64, 'validAuthoredAndParserDocx': 80,
            'nativeProjectionSchemaErrors': 48, 'deterministicArchiveVerified': True,
            'extracted': str(extract) if extract is not None else None}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract', type=Path)
    arguments = parser.parse_args()
    print(json.dumps(verify(Path(__file__).resolve().parent, arguments.extract), indent=2))

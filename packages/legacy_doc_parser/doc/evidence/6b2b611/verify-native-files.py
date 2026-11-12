#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify the sealed native files, optionally extracting to a new directory."""
import argparse
from collections import Counter
import hashlib
import io
import json
import lzma
from pathlib import Path, PurePosixPath
import re
import tarfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract', type=Path, help='New directory for verified files')
    args = parser.parse_args()
    base = Path(__file__).resolve().parent
    manifest = json.loads((base / 'native-files.manifest.json').read_text())
    archive_bytes = (base / 'native-files.tar.xz').read_bytes()
    require(digest(archive_bytes) == manifest['archive']['sha256'], 'Archive hash differs')
    require(len(archive_bytes) == manifest['archive']['bytes'], 'Archive size differs')
    report = base / 'native-report.json.xz'
    require(digest(report.read_bytes()) == manifest['sealedReport']['compressedSha256'],
            'Sealed report hash differs')
    report_hash = hashlib.sha256()
    report_size = 0
    report_hashes = Counter()
    with lzma.open(report, 'rb') as stream:
        for line in stream:
            report_hash.update(line)
            report_size += len(line)
            report_hashes.update(value.decode() for value in re.findall(rb'"([0-9a-f]{64})"', line))
    require(report_hash.hexdigest() == manifest['sealedReport']['jsonSha256'],
            'Decoded report hash differs')
    require(report_size == manifest['sealedReport']['jsonBytes'], 'Decoded report size differs')
    expected = {entry['path']: entry for entry in manifest['files']}
    require(len(expected) == len(manifest['files']) == manifest['fileCount'],
            'Duplicate or missing manifest paths')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:xz') as archive:
        require(archive.getnames() == sorted(expected), 'Archive membership/order differs')
        for member in archive:
            name = member.name
            path = PurePosixPath(name)
            require(not path.is_absolute() and all(part not in ('', '.', '..')
                    for part in name.split('/')) and '\\' not in name,
                    f'Unsafe member path: {name}')
            require(member.isfile() and member.mode == 0o644 and
                    member.uid == member.gid == member.mtime == 0 and
                    member.uname == member.gname == '' and not member.linkname and
                    not member.pax_headers, f'Unexpected member metadata: {name}')
            entry = expected[name]
            require(member.size == entry['bytes'], f'Member size differs: {name}')
            data = archive.extractfile(member).read()
            require(len(data) == entry['bytes'] and digest(data) == entry['sha256'],
                    f'Member bytes differ: {name}')
            require(report_hashes[entry['sha256']] == entry['sealedReportHashOccurrences'] > 0,
                    f'Member hash missing from sealed report: {name}')
            files[name] = data
    require(sum(map(len, files.values())) == manifest['uncompressedFileBytes'],
            'Uncompressed total differs')
    require(dict(Counter(name.split('/')[0] for name in files)) == manifest['caseFileCounts'],
            'Case file counts differ')

    # Rebuilding with the declared fixed metadata must reproduce the archive.
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            archive.addfile(info, io.BytesIO(data))
    rebuilt = lzma.compress(buffer.getvalue(), format=lzma.FORMAT_XZ,
                            check=lzma.CHECK_CRC64, preset=9)
    require(rebuilt == archive_bytes, 'Deterministic archive rebuild differs')
    if args.extract is not None:
        # No tar extraction API is used: only verified regular-file bytes are
        # written beneath a newly created output directory.
        args.extract.mkdir(parents=True, exist_ok=False)
        for name, data in files.items():
            target = args.extract.joinpath(*PurePosixPath(name).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            require(target.read_bytes() == data, f'Extracted bytes differ: {name}')
    print(json.dumps({'files': len(files), 'bytes': sum(map(len, files.values())),
                      'archiveSha256': digest(archive_bytes),
                      'allHashesInSealedReport': True, 'deterministicRebuildMatches': True,
                      'extracted': str(args.extract) if args.extract is not None else None}))


if __name__ == '__main__':
    main()

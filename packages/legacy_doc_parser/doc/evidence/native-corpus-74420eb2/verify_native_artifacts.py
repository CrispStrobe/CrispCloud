#!/usr/bin/env python3
"""Verify retained native evidence; optionally extract to a new directory."""
import argparse
import gzip
import hashlib
import io
import json
import lzma
from pathlib import Path, PurePosixPath
import re
import tarfile


def require(value, message):
    if not value:
        raise ValueError(message)


def hash_file(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument('--directory', type=Path, default=Path(__file__).resolve().parent)
    arguments.add_argument('--extract', type=Path)
    args = arguments.parse_args()
    manifest = json.loads((args.directory / 'native-artifacts.manifest.json').read_text())
    require(manifest['version'] == 1, 'Unknown evidence manifest version')
    for key in ('report', 'archive'):
        item = manifest[key]
        require(Path(item['path']).name == item['path'], 'Unsafe top-level artifact path')
        path = args.directory / item['path']
        require(path.is_file() and not path.is_symlink(), 'Missing artifact: ' + key)
        require(path.stat().st_size == item['bytes'] and hash_file(path) == item['sha256'],
                'Artifact bytes differ: ' + key)
    report_record = manifest['report']
    with lzma.open(args.directory / report_record['path'], 'rb') as stream:
        report_hash, report_size = hashlib.sha256(), 0
        report_hashes = set()
        for line in stream:
            report_hash.update(line)
            report_size += len(line)
            report_hashes.update(v.decode() for v in re.findall(rb'"([0-9a-f]{64})"', line))
    require(report_hash.hexdigest() == report_record['uncompressedSha256']
            and report_size == report_record['uncompressedBytes'], 'Decoded report differs')
    entries = manifest['files']
    names = [entry['path'] for entry in entries]
    require(names == sorted(set(names)) and len(names) == manifest['fileCount'],
            'Duplicate, unordered, or missing manifest entries')
    for name in names:
        path = PurePosixPath(name)
        require(not path.is_absolute() and '\\' not in name
                and all(part not in ('', '.', '..') for part in name.split('/'))
                and path.as_posix() == name, 'Unsafe member path: ' + name)
    require(sum(x['bytes'] for x in entries) == manifest['uncompressedFileBytes'],
            'Manifest size total differs')
    if args.extract is not None:
        require(not args.extract.exists() and not args.extract.is_symlink(),
                'Extraction requires a new destination')
    expected = iter(entries)
    count = raw_rasters = total = 0
    sidecars = {}
    expected_by_path = {entry['path']: entry for entry in entries}
    archive_path = args.directory / manifest['archive']['path']
    # Verify every member before creating an extraction destination.
    with tarfile.open(archive_path, 'r|xz') as archive:
        for member in archive:
            entry = next(expected, None)
            require(entry is not None and member.name == entry['path'],
                    'Unexpected or reordered archive member')
            require(member.isfile() and member.size == entry['bytes'] and member.mode == 0o644
                    and member.uid == member.gid == member.mtime == 0
                    and member.uname == member.gname == '' and not member.linkname
                    and not member.pax_headers, 'Archive metadata differs: ' + member.name)
            stream = archive.extractfile(member)
            if 'uncompressedSha256' in entry:
                data = stream.read()
                require(hashlib.sha256(data).hexdigest() == entry['sha256'], 'Compressed page differs')
                with gzip.GzipFile(fileobj=io.BytesIO(data)) as raw:
                    raw_hash, raw_size = hashlib.sha256(), 0
                    for chunk in iter(lambda: raw.read(1024 * 1024), b''):
                        raw_hash.update(chunk)
                        raw_size += len(chunk)
                    require(raw_hash.hexdigest() == entry['uncompressedSha256']
                            and raw_size == entry['uncompressedBytes'], 'Decoded PPM bytes differ')
                raw_rasters += 1
            elif member.name.endswith(('-render.json', '/raster-manifest.json')):
                data = stream.read()
                require(hashlib.sha256(data).hexdigest() == entry['sha256'], 'Render sidecar differs')
                sidecars[member.name] = json.loads(data)
            else:
                require(hashlib.file_digest(stream, 'sha256').hexdigest() == entry['sha256'],
                        'Member bytes differ: ' + member.name)
            count += 1
            total += member.size
    require(next(expected, None) is None and count == manifest['fileCount'], 'Missing archive members')
    require(total == manifest['uncompressedFileBytes'], 'Archive size total differs')
    for entry in entries:
        if 'rasterContext' not in entry:
            continue
        context = entry['rasterContext']
        render, storage = sidecars[context['render']], sidecars[context['manifest']]
        page = context['page']
        require(type(page) is int and 1 <= page <= len(render['rasterArtifacts']), 'Invalid page index')
        artifact = render['rasterArtifacts'][page - 1]
        require(artifact['page'] == page and artifact['path'] == PurePosixPath(entry['path']).name,
                'Page artifact identity differs')
        require(artifact['sha256'] == entry['sha256'] and artifact['sizeBytes'] == entry['bytes']
                and artifact['uncompressedSha256'] == entry['uncompressedSha256']
                and artifact['uncompressedSizeBytes'] == entry['uncompressedBytes']
                and render['rasterSha256'][page - 1] == entry['uncompressedSha256'],
                'Page bytes do not match render receipt')
        require(expected_by_path[context['render']]['sha256'] in report_hashes,
                'Render receipt is not bound by the measured report')
        require(PurePosixPath(context['manifest']).name == render['rasterManifest']['path']
                and expected_by_path[context['manifest']]['sha256'] == render['rasterManifest']['sha256'],
                'Raster manifest does not match render receipt')
        require(storage['pages'] == render['rasterArtifacts'] and storage['status'] == 'complete'
                and storage['expectedPages'] == len(render['pages']) == len(render['rasterArtifacts'])
                and storage['pdfSha256'] == render['pdfSha256'], 'Raster manifest is inconsistent')
    if args.extract is not None:
        args.extract.mkdir(parents=True, exist_ok=False)
        with tarfile.open(archive_path, 'r|xz') as archive:
            for member, entry in zip(archive, entries, strict=True):
                destination = args.extract.joinpath(*PurePosixPath(member.name).parts)
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, destination.open('xb') as target:
                    for chunk in iter(lambda: source.read(1024 * 1024), b''):
                        target.write(chunk)
                require(hash_file(destination) == entry['sha256'], 'Extracted bytes differ')
    print(json.dumps({'verified': True, 'sourceCommit': manifest['sourceCommit'],
                      'files': count, 'bytes': total, 'verifiedGzipPages': raw_rasters,
                      'archiveSha256': manifest['archive']['sha256'],
                      'extracted': str(args.extract) if args.extract else None}))


if __name__ == '__main__':
    main()

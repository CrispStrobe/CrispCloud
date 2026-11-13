#!/usr/bin/env python3
"""Seal completed native measurement files without altering measured bytes."""
import argparse
import gzip
import hashlib
import io
import json
import lzma
from pathlib import Path
import re
import shutil
import tarfile


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--parser', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report_path = args.run / 'report.json'
    report_hash = digest(report_path)
    report = json.loads(report_path.read_text())
    args.output.mkdir(parents=True, exist_ok=False)
    report_archive = args.output / 'native-report.json.xz'
    with report_path.open('rb') as source, lzma.open(report_archive, 'wb', preset=6) as target:
        shutil.copyfileobj(source, target, length=1024 * 1024)
    with lzma.open(report_archive, 'rb') as source:
        restored = hashlib.file_digest(source, 'sha256').hexdigest()
    assert restored == report_hash == digest(report_path)
    report_hashes = set()
    with report_path.open('rb') as stream:
        for line in stream:
            report_hashes.update(v.decode() for v in re.findall(rb'"([0-9a-f]{64})"', line))
    files = {}
    for path in sorted(args.run.rglob('*')):
        relative = path.relative_to(args.run)
        if any(part in {'profile', 'tmp'} for part in relative.parts):
            continue
        if relative.as_posix() in {'report.json', 'convert'}:
            continue
        if path.is_symlink():
            raise ValueError(f'Unexpected artifact link: {relative}')
        if path.is_file():
            files['run/' + relative.as_posix()] = path
    corpus = json.loads((args.parser / 'tool/fidelity/corpus.json').read_text())
    cases = {case['id']: case for case in corpus['cases']}
    for case in report['cases']:
        source = args.parser / cases[case['id']]['path']
        assert digest(source) == case['sourceSha256']
        files['inputs/' + case['id'] + source.suffix] = source
    inventory = []
    for name, path in sorted(files.items()):
        sha = digest(path)
        if path.suffix in {'.doc', '.docx'} and sha not in report_hashes:
            raise ValueError(f'Document is absent from measured hashes: {name}')
        entry = {'path': name, 'bytes': path.stat().st_size, 'sha256': sha}
        if path.name.endswith('.ppm.gz'):
            with gzip.open(path, 'rb') as stream:
                raw_digest, raw_size = hashlib.sha256(), 0
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    raw_digest.update(chunk)
                    raw_size += len(chunk)
            raw_hash = raw_digest.hexdigest()
            render_file = path.parent.parent / (path.parent.name.removeprefix('render-') + '-render.json')
            render = json.loads(render_file.read_text())
            assert digest(render_file) in report_hashes
            artifacts = render['rasterArtifacts']
            matches = [(index, item) for index, item in enumerate(artifacts) if item['path'] == path.name]
            assert len(matches) == 1
            page, artifact = matches[0]
            assert artifact['page'] == page + 1
            assert artifact['sha256'] == sha and artifact['sizeBytes'] == entry['bytes']
            assert artifact['uncompressedSha256'] == raw_hash == render['rasterSha256'][page]
            assert artifact['uncompressedSizeBytes'] == raw_size
            manifest_name = render['rasterManifest']['path']
            assert Path(manifest_name).name == manifest_name
            raster_manifest_file = path.parent / manifest_name
            assert digest(raster_manifest_file) == render['rasterManifest']['sha256']
            raster_manifest = json.loads(raster_manifest_file.read_text())
            assert raster_manifest['pages'] == artifacts
            assert raster_manifest['status'] == 'complete'
            assert raster_manifest['expectedPages'] == len(artifacts) == len(render['pages'])
            assert raster_manifest['pdfSha256'] == render['pdfSha256']
            entry.update(uncompressedSha256=raw_hash, uncompressedBytes=raw_size,
                         rasterContext={'render': 'run/' + render_file.relative_to(args.run).as_posix(),
                                        'manifest': 'run/' + raster_manifest_file.relative_to(args.run).as_posix(),
                                        'page': page + 1})
        inventory.append(entry)
    artifact_archive = args.output / 'native-artifacts.tar.xz'
    with lzma.open(artifact_archive, 'wb', preset=6) as compressed:
        with tarfile.open(fileobj=compressed, mode='w|', format=tarfile.USTAR_FORMAT) as archive:
            for entry in inventory:
                info = tarfile.TarInfo(entry['path'])
                info.size, info.mode, info.mtime = entry['bytes'], 0o644, 0
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                with files[entry['path']].open('rb') as source:
                    archive.addfile(info, source)
    for entry in inventory:
        assert digest(files[entry['path']]) == entry['sha256']
    manifest = {
        'version': 1, 'sourceCommit': report['parserCommit'],
        'sourceWorktreeDirty': report['parserWorktreeDirty'],
        'report': {'path': report_archive.name, 'sha256': digest(report_archive),
                   'bytes': report_archive.stat().st_size,
                   'uncompressedSha256': report_hash, 'uncompressedBytes': report_path.stat().st_size},
        'archive': {'path': artifact_archive.name, 'sha256': digest(artifact_archive),
                    'bytes': artifact_archive.stat().st_size, 'format': 'USTAR/XZ',
                    'compressionPreset': 6},
        'fileCount': len(inventory), 'uncompressedFileBytes': sum(x['bytes'] for x in inventory),
        'excludedGeneratedFiles': ['Office profile directories', 'temporary directory',
                                   'compiled parser executable (hash retained in report)'],
        'files': inventory,
    }
    (args.output / 'native-artifacts.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({k: manifest[k] for k in ('sourceCommit','fileCount','uncompressedFileBytes','archive','report')}))


if __name__ == '__main__':
    if not __debug__:
        raise SystemExit('Run without Python optimization: evidence checks use assertions')
    main()

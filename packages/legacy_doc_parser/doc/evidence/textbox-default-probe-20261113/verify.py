#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify retained Word14 counterfactuals without adopting them as goldens."""
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'tool/fidelity'))
from goldens import compare_render  # noqa: E402


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    manifest = json.loads((HERE / 'manifest.json').read_text())
    summary_bytes = (HERE / 'summary.json').read_bytes()
    assert digest(summary_bytes) == manifest['summarySha256']
    summary = json.loads(summary_bytes)
    archive = HERE / manifest['archive']['path']
    data = archive.read_bytes()
    assert len(data) == manifest['archive']['sizeBytes']
    assert digest(data) == manifest['archive']['sha256']
    expected = {entry['path']: entry for entry in manifest['files']}
    assert len(expected) == len(manifest['files'])
    files = {}
    with tarfile.open(archive, 'r:xz') as retained:
        for member in retained.getmembers():
            path = PurePosixPath(member.name)
            assert member.isfile() and not path.is_absolute()
            assert '..' not in path.parts and member.name not in files
            assert member.name in expected
            payload = retained.extractfile(member).read()
            record = expected[member.name]
            assert len(payload) == record['sizeBytes'] == member.size
            assert digest(payload) == record['sha256']
            files[member.name] = payload
    assert files.keys() == expected.keys()

    rasters = 0
    for name, payload in files.items():
        if not name.endswith('/raster-manifest.json'):
            continue
        record = json.loads(payload)
        parent = PurePosixPath(name).parent
        assert record['status'] == 'complete'
        assert len(record['pages']) == record['expectedPages']
        pdfs = [value for key, value in files.items()
                if PurePosixPath(key).parent == parent and key.endswith('.pdf')]
        assert len(pdfs) == 1 and digest(pdfs[0]) == record['pdfSha256']
        for page in record['pages']:
            compressed = files[str(parent / page['path'])]
            assert digest(compressed) == page['sha256']
            assert len(compressed) == page['sizeBytes']
            raw = gzip.decompress(compressed)
            assert len(raw) == page['uncompressedSizeBytes']
            assert digest(raw) == page['uncompressedSha256']
            rasters += 1

    def verify_render(record, directory):
        manifest_path = str(PurePosixPath(directory) / 'raster-manifest.json')
        raster = json.loads(files[manifest_path])
        assert record['pdfSha256'] == raster['pdfSha256']
        assert record['rasterDpi'] == raster['rasterDpi']
        assert record['rasterColorSpace'] == raster['rasterColorSpace'] == 'RGB'
        assert record['rasterSha256'] == [page['uncompressedSha256']
                                         for page in raster['pages']]

    counterfactuals = json.loads(files['counterfactuals.json'])
    verify_render(counterfactuals['original'], 'original')
    for name, expected_comparison in summary['counterfactuals'].items():
        verify_render(counterfactuals[name]['render'], 'render-' + name)
        comparison = compare_render(counterfactuals['original'],
                                    counterfactuals[name]['render'])
        assert comparison == expected_comparison == counterfactuals[name]['comparison']
        assert not comparison['rasterExactlyMatches']
    native = json.loads(files['current-baseline/report.json'])
    assert native['parserCommit'] == summary['runtime']['commit']
    assert native['parserWorktreeDirty'] is False
    assert native['build']['sourcesUnchangedDuringCompilation'] is True
    case = native['cases'][0]
    render_base = PurePosixPath('current-baseline') / case['id']
    renders = {}
    for name, reference in case['renders'].items():
        payload = files[str(render_base / reference['path'])]
        assert digest(payload) == reference['sha256']
        renders[name] = json.loads(payload)
        verify_render(renders[name], str(render_base / ('render-' + name)))
    assert case['sourceUnchanged'] and case['binaryDocUnchanged']
    assert case['pagination'] == summary['currentRuntime']['initial']
    assert compare_render(renders['binary'], renders['converted']) == case['pagination']
    assert len(case['roundtripCycles']) == 3
    for actual, expected_cycle in zip(case['roundtripCycles'],
                                      summary['currentRuntime']['cycles']):
        assert all(actual[key] == value for key, value in expected_cycle.items())
        assert actual['paginationFromBinaryDoc']['exactOnThisRenderer']
        index = actual['index']
        converted = renders[f'roundtrip-{index:02d}-converted']
        previous = renders['converted' if index == 1 else
                           f'roundtrip-{index - 1:02d}-converted']
        for reference, key in [
                (renders[f'roundtrip-{index:02d}-binary'], 'paginationFromBinaryDoc'),
                (previous, 'paginationFromPreviousImport'),
                (renders['converted'], 'paginationFromFirstImport')]:
            assert compare_render(reference, converted) == actual[key]
    assert digest(files['word14-source.doc']) == summary['source']['sha256']
    assert digest(files['retained-wrap-output.docx']) == summary['counterfactualInput']['sha256']
    assert all(value is False for value in summary['scope'].values())
    rejected = json.loads(files['controls-baseline.json'])
    assert len(rejected) == summary['rejectedSyntheticControls']['count'] == 6
    assert all(not item['comparison']['pageDimensionsMatch'] and
               not item['comparison']['pageTextMatches'] for item in rejected)
    print(json.dumps({'verified': True, 'archiveFiles': len(files),
                      'rasterPages': rasters, 'counterfactuals': 4,
                      'nativeRepeats': 3, 'acceptedDefaultChange': False}))


if __name__ == '__main__':
    main()

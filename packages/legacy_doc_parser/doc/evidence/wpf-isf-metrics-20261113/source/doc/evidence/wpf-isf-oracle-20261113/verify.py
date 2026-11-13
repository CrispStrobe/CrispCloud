#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify retained independent WPF ISF bytes, decoded observations and rasters."""
import argparse
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import struct
import subprocess
import zipfile
import zlib

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SOURCE_COMMIT = '5da4906ac8ccc76583329af23467e135dd3698a9'
SOURCE_TREE = '4ccb56b1de7e0b49e391afb8a038d89edbdadc37'
RUN_ID = 43382035366
JOB_ID = 131741781381
CASES = {'polyline-solid': [5], 'single-dot': [1], 'paint-ellipse-alpha': [3],
         'multiple-strokes': [2, 2, 2], 'pressure-ramp': [5], 'signed-quantization': [4]}
MODES = ('uncompressed', 'compressed')
RATIO = 96 / 2540
SOURCE_FILES = {'.github/workflows/ink-oracle.yml', 'tool/ink_oracle/InkOracle.csproj',
                'tool/ink_oracle/Program.cs', 'tool/ink_oracle/README.md', 'tool/ink_oracle/global.json'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def obj(data):
    return json.loads(data.decode('utf-8-sig'))


def safe_path(name):
    path = PurePosixPath(name)
    require(name not in ('', '.') and not path.is_absolute() and '..' not in path.parts
            and str(path) == name and '\\' not in name, 'Unsafe retained path: ' + name)


def close(actual, expected, label, tolerance=1e-10):
    require(math.isfinite(actual) and math.isfinite(expected) and
            abs(actual - expected) <= tolerance, label)


def png_bgra(data):
    """Decode the actual bounded, 8-bit RGB/RGBA PNG; no renderer is involved."""
    require(data[:8] == b'\x89PNG\r\n\x1a\n', 'PNG signature')
    at = 8
    chunks = []
    image_data = bytearray()
    info = None
    while at < len(data):
        require(at + 12 <= len(data), 'Truncated PNG chunk')
        size = struct.unpack_from('>I', data, at)[0]
        kind = data[at + 4:at + 8]
        payload = data[at + 8:at + 8 + size]
        require(at + 12 + size <= len(data), 'Truncated PNG payload')
        expected = struct.unpack_from('>I', data, at + 8 + size)[0]
        require(zlib.crc32(kind + payload) & 0xffffffff == expected, 'PNG chunk CRC')
        chunks.append(kind)
        if kind == b'IHDR':
            require(info is None and len(chunks) == 1 and len(payload) == 13, 'PNG header order')
            info = struct.unpack('>IIBBBBB', payload)
        elif kind == b'IDAT':
            image_data.extend(payload)
        elif kind == b'IEND':
            require(size == 0 and at + 12 == len(data), 'PNG ending')
        at += 12 + size
    require(info is not None and chunks[-1] == b'IEND', 'Complete PNG')
    width, height, bits, color, compression, filtering, interlace = info
    require((width, height, bits, compression, filtering, interlace) == (256, 192, 8, 0, 0, 0)
            and color in (2, 6), 'Expected bounded WPF PNG format')
    channels = 4 if color == 6 else 3
    stride = width * channels
    decoder = zlib.decompressobj()
    raw = decoder.decompress(image_data, height * (stride + 1) + 1)
    require(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail and
            len(raw) == height * (stride + 1), 'PNG decompressed size')
    output = bytearray()
    previous = bytearray(stride)
    for y in range(height):
        filter_type = raw[y * (stride + 1)]
        require(0 <= filter_type <= 4, 'PNG row filter')
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i, value in enumerate(row):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = up
            elif filter_type == 3:
                predictor = (left + up) // 2
            else:
                p = left + up - upper_left
                distances = [abs(p - left), abs(p - up), abs(p - upper_left)]
                predictor = [left, up, upper_left][distances.index(min(distances))]
            row[i] = (value + predictor) & 255
        for x in range(width):
            r, g, b = row[x * channels:x * channels + 3]
            alpha = row[x * channels + 3] if channels == 4 else 255
            require(alpha == 255, 'Opaque white-backed WPF bitmap')
            output.extend((b, g, r, alpha))
        previous = row
    return bytes(output)


def pixels(data, receipt, name):
    require(receipt['path'] == name and sha(data) == receipt['pngSha256'], 'PNG byte receipt')
    raw = png_bgra(data)
    require(sha(raw) == receipt['pixelSha256'], 'Decoded WPF BGRA bytes')
    coordinates = [(n // 4 % 256, n // 4 // 256) for n in range(0, len(raw), 4)
                   if raw[n:n + 4] != b'\xff\xff\xff\xff']
    require(len(coordinates) > 0 and len(coordinates) == receipt['nonWhitePixelCount'], 'Visible pixel count')
    left, top = min(x for x, y in coordinates), min(y for x, y in coordinates)
    right, bottom = max(x for x, y in coordinates) + 1, max(y for x, y in coordinates) + 1
    require([left, top, right, bottom] == receipt['nonWhiteBoundsPixels'] and
            0 < left < right < 256 and 0 < top < bottom < 192, 'Visible non-clipped pixel bounds')
    return raw


def changed_pixels(left, right):
    require(len(left) == len(right), 'Comparable pixel buffers')
    return sum(left[n:n + 4] != right[n:n + 4] for n in range(0, len(left), 4))


def snapshot(value, counts):
    require(value['coordinateUnit'] == 'DIP (1/96 inch)' and value['dipPerHimetric'] == RATIO and
            value['strokeCount'] == len(value['strokes']) == len(counts), 'Snapshot units/stroke count')
    for index, (stroke, count) in enumerate(zip(value['strokes'], counts)):
        require(stroke['index'] == index and len(stroke['points']) == count, 'Snapshot point count/order')
        attrs = stroke['attributes']
        close(attrs['widthHimetric'], attrs['width'] / RATIO, 'Width unit conversion')
        close(attrs['heightHimetric'], attrs['height'] / RATIO, 'Height unit conversion')
        require(attrs['width'] > 0 and attrs['height'] > 0, 'Positive WPF pen dimensions')
        for coordinate in stroke['boundsDip']:
            require(math.isfinite(coordinate), 'Finite WPF bounds')
        metric = stroke['pressureMetric']
        require(metric['minimum'] < metric['maximum'] and math.isfinite(metric['resolution']), 'Pressure metric')
        for point in stroke['points']:
            close(point['himetricX'], point['x'] / RATIO, 'X unit conversion')
            close(point['himetricY'], point['y'] / RATIO, 'Y unit conversion')
            require(0 <= point['pressureFactor'] <= 1 and metric['minimum'] <= point['pressurePropertyValue']
                    <= metric['maximum'], 'WPF pressure bounds')


def authored_binding(authored, original, name):
    require(authored['name'] == name and authored['coordinateUnit'] == 'Himetric (1/100 millimeter)' and
            authored['dipPerHimetric'] == RATIO and authored['expectedStrokeCount'] == len(CASES[name]) and
            authored['expectedPointCounts'] == CASES[name], 'Authored control identity')
    for expected, actual in zip(authored['strokes'], original['strokes']):
        require(len(expected['points']) == len(actual['points']), 'Authored point count')
        a = actual['attributes']
        close(a['width'], expected['widthHimetric'] * RATIO, 'Authored width')
        close(a['height'], expected['heightHimetric'] * RATIO, 'Authored height')
        require(a['colorArgb'] == expected['colorArgb'] and a['ignorePressure'] == expected['ignorePressure']
                and a['stylusTip'] == {0: 'Rectangle', 1: 'Ellipse'}[expected['tip']]
                and a['fitToCurve'] is False and a['isHighlighter'] is False
                and a['stylusTipTransform'] == [1, 0, 0, 1, 0, 0], 'Authored drawing attributes')
        for p, q in zip(expected['points'], actual['points']):
            close(q['x'], p['xHimetric'] * RATIO, 'Authored X')
            close(q['y'], p['yHimetric'] * RATIO, 'Authored Y')
            close(q['pressureFactor'], p['pressure'], 'Authored pressure', 1e-7)


def differences(left, right, reported):
    coordinate = pressure = width = height = 0
    attrs_equal = True
    for a, b in zip(left['strokes'], right['strokes']):
        for p, q in zip(a['points'], b['points']):
            coordinate = max(coordinate, abs(p['x'] - q['x']), abs(p['y'] - q['y']))
            pressure = max(pressure, abs(p['pressureFactor'] - q['pressureFactor']))
        width = max(width, abs(a['attributes']['width'] - b['attributes']['width']))
        height = max(height, abs(a['attributes']['height'] - b['attributes']['height']))
        attrs_equal &= a['attributes'] == b['attributes']
    for key, value in [('maximumCoordinateDeltaDip', coordinate),
                       ('maximumCoordinateDeltaHimetric', coordinate / RATIO),
                       ('maximumWidthDeltaDip', width), ('maximumHeightDeltaDip', height)]:
        close(reported[key], value, 'Snapshot difference: ' + key)
    close(reported['maximumPressureDelta'], pressure, 'Float32 pressure difference', 1e-7)
    require(reported['drawingAttributesExactlyEqual'] == attrs_equal, 'Drawing attribute equality result')


def verify_oracle(files):
    manifest = obj(files['manifest.json'])
    require(manifest['schema'] == 'legacy-doc-parser/wpf-isf-files' and manifest['version'] == 1 and
            manifest['sourceCommit'] == SOURCE_COMMIT, 'WPF manifest identity')
    inventory = {item['path']: item for item in manifest['files']}
    require(len(inventory) == len(manifest['files']) == manifest['fileCount'] == 91 and
            set(inventory) == set(files) - {'manifest.json'}, 'Exact WPF file inventory')
    for name, entry in inventory.items():
        safe_path(name)
        require(entry['bytes'] == len(files[name]) and entry['sha256'] == sha(files[name]), 'WPF file hash: ' + name)
    require(manifest['totalBytes'] == sum(len(files[name]) for name in inventory), 'WPF total byte count')
    summary = obj(files['summary.json'])
    require(summary['schema'] == 'legacy-doc-parser/wpf-isf-oracle' and summary['version'] == 1 and
            summary['status'] == 'complete' and summary['sourceCommit'] == SOURCE_COMMIT and
            summary['gitHub']['sha'] == SOURCE_COMMIT and summary['gitHub']['repository'] == 'CrispStrobe/legacy-doc-parser'
            and summary['gitHub']['runId'] == str(RUN_ID) and summary['gitHub']['runAttempt'] == '1'
            and summary['gitHub']['workflow'] == 'Independent WPF ink oracle', 'WPF runtime/CI identity')
    require(summary['framework'].startswith('.NET 8.') and 'Windows' in summary['operatingSystem'] and
            summary['architecture'] == 'X64' and summary['wpfAssembly'].startswith('PresentationCore, Version=8.0.0.0,')
            and len(summary['wpfAssemblySha256']) == 64, 'Actual Windows .NET8 WPF identity')
    require(summary['render'] == {'pixelWidth': 256, 'pixelHeight': 192, 'dpi': 96, 'translationDip': [32, 32],
            'backgroundArgb': '#FFFFFFFF', 'modePreference': 'SoftwareOnly', 'pixelFormat': 'Pbgra32'},
            'Fixed WPF render configuration')
    require([case['name'] for case in summary['cases']] == list(CASES), 'Exact control case inventory/order')
    nonempty = 0
    observations = []
    for case in summary['cases']:
        name = case['name']
        prefix = name + '/'
        read = lambda path: obj(files[prefix + path])
        original = read('original.json')
        snapshot(original, CASES[name])
        authored_binding(read('authored.json'), original, name)
        require(read('uncompressed.reloaded.json') == read('compressed.reloaded.json'),
                'Compression modes have identical decoded observations')
        require(case['strokeCount'] == len(CASES[name]) and case['originalUnchanged'] is True, 'Original WPF invariant')
        original_pixels = pixels(files[prefix + 'original.png'], case['originalRender'], 'original.png')
        require([mode['mode'] for mode in case['encodings']] == list(MODES), 'Exact compression mode inventory')
        require(case['compressionChangesBytes'] == (files[prefix + 'compressed.isf'] != files[prefix + 'uncompressed.isf']),
                'Compression difference receipt')
        for mode in case['encodings']:
            kind = mode['mode']
            require(mode['compressArgument'] == (kind == 'compressed'), 'Compression argument')
            raw = files[prefix + kind + '.isf']
            second_raw = files[prefix + kind + '.roundtrip.isf']
            for part, data, leaf in [(mode['isf'], raw, kind + '.isf'),
                                      (mode['roundtripIsf'], second_raw, kind + '.roundtrip.isf')]:
                require(part == {'path': leaf, 'bytes': len(data), 'sha256': sha(data)} and
                        len(data) > 2 and data[0] == 0, 'Nonempty WPF ISF byte binding')
                nonempty += 1
            require(mode['bytesStableAfterReload'] == (raw == second_raw), 'ISF roundtrip byte equality')
            reloaded = read(kind + '.reloaded.json')
            second = read(kind + '.second-reloaded.json')
            snapshot(reloaded, CASES[name]); snapshot(second, CASES[name])
            require(reloaded == second, 'Stable second decoded observation')
            differences(original, reloaded, mode['originalToReloaded'])
            differences(reloaded, second, mode['reloadedToSecond'])
            first_pixels = pixels(files[prefix + kind + '.reloaded.png'], mode['reloadedRender'], kind + '.reloaded.png')
            second_pixels = pixels(files[prefix + kind + '.second-reloaded.png'], mode['secondReloadedRender'],
                                   kind + '.second-reloaded.png')
            require(mode['originalToReloadedChangedPixels'] == changed_pixels(original_pixels, first_pixels) and
                    mode['reloadedToSecondChangedPixels'] == changed_pixels(first_pixels, second_pixels),
                    'Actual raster difference counts')
            observations.append({'case': name, 'mode': kind, 'isfBytes': len(raw),
                                 'originalToReloaded': mode['originalToReloaded'],
                                 'changedPixels': mode['originalToReloadedChangedPixels'],
                                 'secondChangedPixels': mode['reloadedToSecondChangedPixels']})
    require(any(case['compressionChangesBytes'] for case in summary['cases']), 'Discriminating compression control')
    return {'cases': len(CASES), 'nonemptyIsfFiles': nonempty, 'retainedOracleFiles': len(files),
            'renderedPngFiles': 30, 'observations': observations}


def read_zip(raw):
    with zipfile.ZipFile(io.BytesIO(raw)) as packed:
        names = packed.namelist()
        require(len(names) == len(set(names)), 'Duplicate archive path')
        result = {}
        for item in packed.infolist():
            safe_path(item.filename)
            require(not item.is_dir() and item.file_size <= 1000000, 'Bounded artifact entry')
            result[item.filename] = packed.read(item)
        return result


def verify(directory=HERE, fixtures=None, check_git=None):
    receipt = obj((directory / 'receipt.json').read_bytes())
    expected_evidence = {entry['path']: entry for entry in receipt['files']}
    actual_evidence = {p.relative_to(directory).as_posix(): p.read_bytes() for p in directory.rglob('*')
                       if p.is_file() and p.name != 'receipt.json' and '__pycache__' not in p.parts}
    require(len(expected_evidence) == len(receipt['files']) and set(expected_evidence) == set(actual_evidence),
            'Exact evidence file inventory')
    for name, data in actual_evidence.items():
        safe_path(name)
        require(expected_evidence[name] == {'path': name, 'bytes': len(data), 'sha256': sha(data)},
                'Evidence file byte receipt: ' + name)
    provenance = obj((directory / 'provenance.json').read_bytes())
    require(provenance['sourceCommit'] == SOURCE_COMMIT and provenance['sourceTree'] == SOURCE_TREE,
            'Retained source identity')
    artifact = provenance['artifact']
    raw = (directory / 'successful-run.zip').read_bytes()
    require(artifact['name'] == 'independent-wpf-isf-' + SOURCE_COMMIT and artifact['workflow_run']['id'] == RUN_ID and
            artifact['workflow_run']['head_sha'] == SOURCE_COMMIT and artifact['size_in_bytes'] == len(raw) and
            artifact['digest'] == 'sha256:' + sha(raw), 'Downloaded GitHub artifact identity/hash')
    run, jobs = provenance['run'], provenance['jobs']['jobs']
    require(run['id'] == RUN_ID and run['head_sha'] == SOURCE_COMMIT and run['run_attempt'] == 1 and
            run['name'] == 'Independent WPF ink oracle' and run['status'] == 'completed' and run['conclusion'] == 'success',
            'Successful exact-commit GitHub run')
    require(len(jobs) == 1 and jobs[0]['id'] == JOB_ID and jobs[0]['run_id'] == RUN_ID and
            jobs[0]['status'] == 'completed' and jobs[0]['conclusion'] == 'success' and
            all(step['status'] == 'completed' and step['conclusion'] == 'success' for step in jobs[0]['steps']),
            'Completed successful WPF job/steps')
    archived = read_zip(raw)
    files = {name[len('ink-oracle/'):]: data for name, data in archived.items() if name.startswith('ink-oracle/')}
    require(set(archived) - {'ink-oracle/' + name for name in files} ==
            {'ink-oracle-logs/build.txt', 'ink-oracle-logs/dotnet-info.txt', 'ink-oracle-logs/git-status.txt',
             'ink-oracle-logs/run.txt'}, 'Archive oracle/log inventory')
    require(archived['ink-oracle-logs/git-status.txt'].decode('utf-8-sig').strip() == '', 'Clean CI checkout')
    require('Build succeeded.' in archived['ink-oracle-logs/build.txt'].decode('utf-8-sig') and
            '0 Error(s)' in archived['ink-oracle-logs/build.txt'].decode('utf-8-sig'), 'Successful original build log')
    require('Complete: 6 cases, 12 independently reloaded ISFs, 91 retained files.' in
            archived['ink-oracle-logs/run.txt'].decode('utf-8-sig'), 'Complete original oracle log')
    require(set(provenance['sourceFiles']) == SOURCE_FILES, 'Exact oracle source inventory')
    first_raw = (directory / 'first-run.zip').read_bytes()
    require(len(first_raw) == 2191 and sha(first_raw) ==
            '1dad60c3499b57ff43cd690eba55f9ae6124abd783a97efc3db7d4c793b9f1b1', 'Original failed-run artifact')
    first_logs = read_zip(first_raw)
    require('Build FAILED.' in first_logs['ink-oracle-logs/build.txt'].decode('utf-8-sig') and
            'CS0103' in first_logs['ink-oracle-logs/build.txt'].decode('utf-8-sig') and
            not any(name.startswith('ink-oracle/') for name in first_logs), 'Preserved pre-fix build failure')
    for name, item in provenance['sourceFiles'].items():
        safe_path(name)
        data = (directory / 'source' / name).read_bytes()
        require(len(data) == item['bytes'] and sha(data) == item['sha256'], 'Retained source file')
        if check_git:
            expected = subprocess.check_output(['git', '-C', str(check_git), 'show', SOURCE_COMMIT + ':' + name])
            require(data == expected, 'Source differs from oracle Git commit: ' + name)
    if fixtures:
        actual = {p.relative_to(fixtures).as_posix(): p.read_bytes() for p in fixtures.rglob('*') if p.is_file()}
        require(actual == files, 'Published fixture copies differ from downloaded artifact')
    result = verify_oracle(files)
    result.update(verified=True, sourceCommit=SOURCE_COMMIT, githubRun=RUN_ID,
                  fixturesVerified=bool(fixtures), gitSourcesVerified=bool(check_git))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, default=REPO / 'test/fixtures/ink_wpf')
    parser.add_argument('--check-git', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(fixtures=args.fixtures, check_git=args.check_git), indent=2))


if __name__ == '__main__':
    main()

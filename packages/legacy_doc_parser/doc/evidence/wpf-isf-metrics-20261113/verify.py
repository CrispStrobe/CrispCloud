#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify exact Windows WPF header controls, raw inputs and observed differences."""
import argparse
from functools import lru_cache
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import zlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
COMMIT = 'bb23b6c7a3de66d1402ae7286e563b3951aa88ca'
TREE = '9481131016f842f5b14800d313f00a328a8a23c7'
RUN = 43384946189
JOB = 131751112801
ARTIFACT = 14017873774
ZIP_SHA = '79561a6936904aa3268d4220852707c30d999ebee86fc2b57fd51e27434d381a'
WIDTH, HEIGHT = 512, 256
RATIO = 96 / 2540
SOURCE_NAMES = {'.github/workflows/ink-metrics-oracle.yml',
    'tool/ink_metrics_oracle/InkMetricsOracle.csproj', 'tool/ink_metrics_oracle/Program.cs',
    'tool/ink_metrics_oracle/README.md', 'tool/ink_metrics_oracle/author_controls.py',
    'tool/ink_metrics_oracle/global.json', 'tool/ink_oracle/Program.cs',
    'doc/evidence/wpf-isf-oracle-20261113/verify.py',
    'test/fixtures/ink_wpf/polyline-solid/uncompressed.isf',
    'test/fixtures/ink_wpf/pressure-ramp/uncompressed.isf'}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


prior = module('original_wpf_oracle_verifier', ROOT / 'doc/evidence/wpf-isf-oracle-20261113/verify.py')
author = module('independent_header_author', ROOT / 'tool/ink_metrics_oracle/author_controls.py')
require, sha, obj, close = prior.require, prior.sha, prior.obj, prior.close


@lru_cache(maxsize=64)
def png_bgra(data):
    """Decode the bounded actual PNG using its filters/CRCs; do not render ink."""
    require(data[:8] == b'\x89PNG\r\n\x1a\n', 'PNG signature')
    at, chunks, image_data, info = 8, [], bytearray(), None
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
            require(size == 0 and at + 12 + size == len(data), 'PNG ending')
        at += 12 + size
    require(info is not None and chunks[-1] == b'IEND', 'Complete PNG')
    width, height, bits, color, compression, filtering, interlace = info
    require((width, height, bits, compression, filtering, interlace) == (WIDTH, HEIGHT, 8, 0, 0, 0)
            and color in (2, 6), 'Fixed bounded WPF PNG format')
    channels = 4 if color == 6 else 3
    stride = width * channels
    decoder = zlib.decompressobj()
    raw = decoder.decompress(image_data, height * (stride + 1) + 1)
    require(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
            and len(raw) == height * (stride + 1), 'PNG decompressed size')
    output, previous = bytearray(), bytearray(stride)
    for y in range(height):
        filtering = raw[y * (stride + 1)]
        require(0 <= filtering <= 4, 'PNG row filter')
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i, value in enumerate(row):
            left, up = row[i - channels] if i >= channels else 0, previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filtering == 0:
                predictor = 0
            elif filtering == 1:
                predictor = left
            elif filtering == 2:
                predictor = up
            elif filtering == 3:
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


@lru_cache(maxsize=64)
def pixel_statistics(raw):
    coordinates = [(n // 4 % WIDTH, n // 4 // WIDTH) for n in range(0, len(raw), 4)
                   if raw[n:n + 4] != b'\xff\xff\xff\xff']
    require(coordinates, 'Visible WPF ink')
    return len(coordinates), [min(x for x, _ in coordinates), min(y for _, y in coordinates),
                              max(x for x, _ in coordinates) + 1, max(y for _, y in coordinates) + 1]


@lru_cache(maxsize=128)
def changed_pixels(a, b):
    return prior.changed_pixels(a, b)


def pixels(data, reported, name):
    require(reported['path'] == name and reported['pngSha256'] == sha(data), 'PNG byte receipt')
    raw = png_bgra(data)
    count, bounds = pixel_statistics(raw)
    require(sha(raw) == reported['pixelSha256'], 'Decoded pixel hash')
    require(reported['nonWhitePixelCount'] == count and reported['nonWhiteBoundsPixels'] == bounds,
            'Actual nonwhite pixel inventory')
    require(0 < bounds[0] < bounds[2] < WIDTH and 0 < bounds[1] < bounds[3] < HEIGHT, 'Unclipped ink')
    return raw


def expected_controls():
    sources = {name: (ROOT / f'test/fixtures/ink_wpf/{name}/uncompressed.isf').read_bytes()
               for name in author.SOURCES}
    for name, data in sources.items():
        require(sha(data) == author.SOURCES[name], 'Immutable original WPF source')
    result = [author.make_case(name + '-baseline', name, data) for name, data in sources.items()]
    for name, tag, values, matrix in author.TRANSFORMS:
        for extended in (False, True):
            mode = 'float-and-double' if extended else 'float-only'
            result.append(author.make_case(name + '-' + mode, 'polyline-solid', sources['polyline-solid'],
                replacements=author.transform(tag, values, extended),
                transform_info={'tag': tag, 'coefficients': values, 'mode': mode, 'sourceMatrixHimetric': matrix}))
    for maximum in (1023, 2047):
        result.append(author.make_case(f'pressure-explicit-0-{maximum}', 'pressure-ramp', sources['pressure-ramp'],
                                       metric_max=maximum))
    require(len(result) == 16 and len({sha(raw) for raw, _ in result}) == 16, 'Sixteen discriminating controls')
    return result


def formula_observation(control, snapshot, reported):
    stroke = snapshot['strokes'][0]
    expected = control['sourceFormula']
    coords = max(abs(p[axis] - pair[i]) for p, pair in zip(stroke['points'], expected['points'])
                 for i, axis in enumerate(('himetricX', 'himetricY')))
    pressure = max(abs(p['pressureFactor'] - f) for p, f in zip(stroke['points'], expected['pressureFactors'])) \
        if expected['pressureFactors'] is not None else 0
    close(reported['maximumCoordinateDeltaHimetric'], coords, 'Source formula coordinate difference')
    close(reported['maximumPressureFactorDelta'], pressure, 'Source formula pressure difference', 1e-7)
    require(reported['coordinatesMatchSourceFormulaWithinTolerance'] == (coords < 1e-8), 'Recorded formula agreement')
    require(reported['pressureMatchesSourceFormulaWithinFloatTolerance'] == (pressure < 1e-7), 'Recorded pressure agreement')
    declared = {k: v for k, v in control['pressureMetric'].items() if k != 'explicit'}
    require(reported['pressureMetricMatchesDeclaration'] == (stroke['pressureMetric'] == declared), 'Recorded metric agreement')
    require(reported['observedPressureMetric'] == stroke['pressureMetric']
            and reported['observedPressureFactors'] == [p['pressureFactor'] for p in stroke['points']]
            and reported['observedPressurePropertyValues'] == [p['pressurePropertyValue'] for p in stroke['points']],
            'Observed pressure values/metric binding')


def verify_payloads(files):
    manifest, summary, controls = [obj(files[p]) for p in ('manifest.json', 'summary.json', 'controls.json')]
    inventory = {r['path']: r for r in manifest['files']}
    require(manifest['sourceCommit'] == COMMIT and manifest['version'] == 1
            and manifest['schema'] == 'legacy-doc-parser/wpf-isf-header-files', 'Native manifest identity')
    require(len(inventory) == len(manifest['files']) == manifest['fileCount'] == 115
            and set(inventory) == set(files) - {'manifest.json'}, 'Exact native file inventory')
    for name, record in inventory.items():
        prior.safe_path(name)
        require(record == {'path': name, 'bytes': len(files[name]), 'sha256': sha(files[name])}, 'Native file bytes: ' + name)
    require(manifest['totalBytes'] == sum(len(files[n]) for n in inventory), 'Native total size')
    expected = expected_controls()
    require(controls['sourceCommit'] == COMMIT and controls['baseCommit'] == author.BASE_COMMIT
            and controls['caseCount'] == 16 and controls['cases'] == [item for _, item in expected],
            'Exact pre-execution mutation inventories/formulas')
    source = obj(files['source-inventory.json'])
    source_names = {f['path'] for f in source['files']}
    require(source['sourceCommit'] == COMMIT and len(source_names) == len(source['files']) == 10
            and source_names == SOURCE_NAMES, 'Source inventory identity')
    for item in source['files']:
        data = (HERE / 'source' / item['path']).read_bytes()
        require(item == {'path': item['path'], 'bytes': len(data), 'sha256': sha(data)}, 'Source bytes: ' + item['path'])
        if item['path'] in ('tool/ink_metrics_oracle/author_controls.py', 'doc/evidence/wpf-isf-oracle-20261113/verify.py'):
            require(data.replace(b'\r\n', b'\n') == (ROOT / item['path']).read_bytes().replace(b'\r\n', b'\n'),
                    'Exact reused author/verifier dependency')
    require(summary['sourceCommit'] == COMMIT and summary['baseCommit'] == author.BASE_COMMIT
            and summary['schema'] == 'legacy-doc-parser/wpf-isf-header-oracle' and summary['version'] == 1
            and summary['status'] == 'complete' and summary['caseCount'] == 16, 'Summary identity/status')
    require(summary['actualArguments'] == ['../../build/ink-metrics-input', '../../build/ink-metrics', COMMIT], 'Exact native arguments')
    require(summary['gitHub'] == {'repository': 'CrispStrobe/legacy-doc-parser', 'runId': str(RUN),
            'runAttempt': '1', 'workflow': 'Independent WPF ink transforms and metrics', 'sha': COMMIT}, 'Exact native GitHub identity')
    require(summary['framework'] == '.NET 8.0.34' and summary['operatingSystem'] == 'Microsoft Windows 10.0.26100'
            and summary['architecture'] == 'X64' and summary['wpfAssemblySha256'] ==
            'cc1664768c1852d209f7c1121285c5bcc94262f9e60e38860d0143f8e28c0d11', 'Measured actual WPF identity')
    require(summary['wpfAssembly'] == 'PresentationCore, Version=8.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35'
            and summary['wpfInformationalVersion'] == '8.0.34-servicing.26522.17+c45b7b239ce0d0b210c0c7b48862804f4a038c78'
            and summary['wpfFileVersion'] == '8.0.3426.52217'
            and summary['inspectedWpfSourceCommit'] == author.WPF_SOURCE, 'Actual and inspected WPF versions')
    require(summary['render'] == {'pixelWidth': WIDTH, 'pixelHeight': HEIGHT, 'dpi': 96, 'translationDip': [32, 32],
            'backgroundArgb': '#FFFFFFFF', 'modePreference': 'SoftwareOnly', 'pixelFormat': 'Pbgra32'}, 'Fixed native render')
    require([c['name'] for c in summary['cases']] == [c['name'] for _, c in expected], 'Case inventory/order')
    values = {}
    for reported, (raw, control) in zip(summary['cases'], expected):
        name, source_name = control['name'], control['sourceName']
        prefix = name + '/'
        read = lambda leaf: obj(files[prefix + leaf])
        require(reported['sourceName'] == source_name and files[prefix + 'input.isf'] == raw, 'Exact authored ISF')
        require(reported['inputSha256'] == sha(raw) and reported['inputBytes'] == len(raw), 'Input receipt')
        saved = files[prefix + 'roundtrip.isf']
        author.records(saved)  # Bounded native record framing, without decoding its packets.
        require(reported['roundtripSha256'] == sha(saved) and reported['roundtripBytes'] == len(saved)
                and reported['bytesStableAfterReload'] == (saved == raw), 'Saved WPF ISF receipt')
        require(reported['originalDecodedObjectsUnchanged'] is True, 'Unchanged loaded WPF objects')
        first, second = read('reloaded.json'), read('second-reloaded.json')
        prior.snapshot(first, [5]); prior.snapshot(second, [5])
        for snapshot in (first, second):
            stroke = snapshot['strokes'][0]
            metric = stroke['pressureMetric']
            for point in stroke['points']:
                scaled = metric['minimum'] + point['pressureFactor'] * (metric['maximum'] - metric['minimum'])
                require(abs(point['pressurePropertyValue'] - scaled) < 1.001,
                        'Observed pressure property/factor/metric consistency')
        first_pixels = pixels(files[prefix + 'reloaded.png'], reported['reloadedRender'], 'reloaded.png')
        second_pixels = pixels(files[prefix + 'second-reloaded.png'], reported['secondReloadedRender'], 'second-reloaded.png')
        values[name] = (first, first_pixels, second)
        baseline, baseline_pixels, _ = values[source_name + '-baseline']
        prior.differences(baseline, first, reported['baselineToReloaded'])
        prior.differences(first, second, reported['reloadedToSecond'])
        require(reported['baselineToReloadedChangedPixels'] == changed_pixels(baseline_pixels, first_pixels)
                and reported['reloadedToSecondChangedPixels'] == changed_pixels(first_pixels, second_pixels), 'Measured raster differences')
        formula = read('formula-observation.json')
        require(formula == reported['sourceFormulaObservation'], 'Formula result file binding')
        formula_observation(control, first, formula)
        for stroke in (first['strokes'][0], second['strokes'][0]):
            require(stroke['attributes'] == baseline['strokes'][0]['attributes'], 'Preserved source pen attributes')
        if control['rawPressurePackets'] is not None:
            for snapshot in (first, second):
                stroke = snapshot['strokes'][0]
                require([p['pressurePropertyValue'] for p in stroke['points']] == control['rawPressurePackets'],
                        'Unchanged first/second observed raw pressure packet values')
                metric = stroke['pressureMetric']
                for point in stroke['points']:
                    expected_factor = (point['pressurePropertyValue'] - metric['minimum']) / (metric['maximum'] - metric['minimum'])
                    close(point['pressureFactor'], expected_factor, 'Explicit pressure packet normalization', 1e-7)
        else:
            declared = {k: v for k, v in control['pressureMetric'].items() if k != 'explicit'}
            require(first['strokes'][0]['pressureMetric'] == second['strokes'][0]['pressureMetric'] == declared,
                    'Unchanged implicit default pressure metric')
    comparisons = [(name + '-float-only', name + '-float-and-double') for name, *_ in author.TRANSFORMS]
    for mode in ('float-only', 'float-and-double'):
        comparisons.extend([('translate-100-minus50-' + mode, 'affine-translate-100-minus50-' + mode),
                            ('scale-translate-2-half-100-minus50-' + mode, 'affine-scale-translate-2-half-100-minus50-' + mode)])
    comparisons.extend([('pressure-ramp-baseline', 'pressure-explicit-0-1023'),
                        ('pressure-ramp-baseline', 'pressure-explicit-0-2047')])
    require([(c['left'], c['right']) for c in summary['comparisons']] == comparisons, 'Exact comparison inventory')
    for reported in summary['comparisons']:
        left, a, _ = values[reported['left']]
        right, b, _ = values[reported['right']]
        prior.differences(left, right, reported['difference'])
        require(reported['changedPixels'] == changed_pixels(a, b), 'Pairwise actual raster differences')
    return {'verified': True, 'sourceCommit': COMMIT, 'cases': 16, 'nativeFiles': len(files),
            'nonemptyIsfFiles': 32, 'renderedPngFiles': 32, 'comparisons': len(comparisons),
            'preExecutionFormulaDisagreements': [c['name'] for c in summary['cases']
                if not c['sourceFormulaObservation']['coordinatesMatchSourceFormulaWithinTolerance']]}


def verify(directory=HERE, check_git=None):
    receipt = obj((directory / 'receipt.json').read_bytes())
    require(receipt['schema'] == 'legacy-doc-parser/wpf-isf-header-evidence' and receipt['version'] == 1
            and receipt['sourceCommit'] == COMMIT, 'Evidence receipt identity')
    actual = {p.relative_to(directory).as_posix(): p.read_bytes() for p in directory.rglob('*')
              if p.is_file() and p.name != 'receipt.json' and '__pycache__' not in p.parts}
    expected = {item['path']: item for item in receipt['files']}
    require(len(expected) == len(receipt['files']) and set(expected) == set(actual), 'Exact evidence inventory')
    for name, data in actual.items():
        require(expected[name] == {'path': name, 'bytes': len(data), 'sha256': sha(data)}, 'Evidence byte receipt: ' + name)
    raw = actual['successful-run.zip']
    require(len(raw) == 105562 and sha(raw) == ZIP_SHA, 'Original GitHub ZIP size/hash')
    provenance = obj(actual['provenance.json'])
    artifact, run, jobs = provenance['artifact'], provenance['run'], provenance['jobs']['jobs']
    require(artifact['id'] == ARTIFACT and artifact['digest'] == 'sha256:' + ZIP_SHA and artifact['size_in_bytes'] == len(raw)
            and artifact['name'] == 'independent-wpf-isf-headers-' + COMMIT
            and artifact['workflow_run']['id'] == RUN and artifact['workflow_run']['head_sha'] == COMMIT, 'GitHub artifact receipt')
    require(run['id'] == RUN and run['head_sha'] == COMMIT and run['head_commit']['tree_id'] == TREE
            and run['status'] == 'completed' and run['conclusion'] == 'success' and run['run_attempt'] == 1,
            'Successful exact-source Windows run')
    require(run['name'] == 'Independent WPF ink transforms and metrics'
            and run['path'] == '.github/workflows/ink-metrics-oracle.yml'
            and run['head_branch'] == 'checkpoint/ink-metrics-oracle-20261113', 'Exact workflow/branch identity')
    require(len(jobs) == 1 and jobs[0]['id'] == JOB and jobs[0]['run_id'] == RUN and jobs[0]['status'] == 'completed'
            and jobs[0]['conclusion'] == 'success' and all(s['conclusion'] == 'success' and s['status'] == 'completed'
            for s in jobs[0]['steps']), 'Successful Windows job and steps')
    archived = prior.read_zip(raw)
    require(len(archived) == 142 and sum(map(len, archived.values())) == 389309, 'Complete raw artifact inventory')
    files = {n.removeprefix('ink-metrics/'): b for n, b in archived.items() if n.startswith('ink-metrics/')}
    result = verify_payloads(files)
    duplicates = {'controls.json', 'source-inventory.json', *(c['inputPath'] for c in obj(files['controls.json'])['cases'])}
    logs = {'author.txt', 'build.txt', 'dotnet-info.txt', 'git-after.txt', 'git-before.txt', 'git-identity.txt', 'python-info.txt', 'run.txt'}
    require(set(archived) == {'ink-metrics/' + n for n in files} | {'ink-metrics-input/' + n for n in duplicates}
            | {'ink-metrics-logs/' + n for n in logs}, 'Exact archive output/input/log paths')
    for name in duplicates:
        require(archived['ink-metrics-input/' + name] == files[name], 'Original authored/loaded input copy')
    for name in ('git-before.txt', 'git-after.txt'):
        require(archived['ink-metrics-logs/' + name].decode('utf-8-sig').strip() == '', 'Clean original source checkout')
    require(archived['ink-metrics-logs/git-identity.txt'].decode('utf-8-sig').split() == [COMMIT, TREE], 'Checked out exact source/tree')
    require('Build succeeded.' in archived['ink-metrics-logs/build.txt'].decode('utf-8-sig')
            and '0 Error(s)' in archived['ink-metrics-logs/build.txt'].decode('utf-8-sig'), 'Actual successful build log')
    require('Complete: 16 cases, 12 recorded comparisons, 115 inventoried output files.' in
            archived['ink-metrics-logs/run.txt'].decode('utf-8-sig'), 'Complete actual native run log')
    fixture = ROOT / 'test/fixtures/ink_wpf_headers'
    actual_files = {p.relative_to(fixture).as_posix(): p.read_bytes() for p in fixture.rglob('*') if p.is_file()}
    require(actual_files == files, 'Exact fixture copies of original downloaded outputs')
    checkout = obj(actual['checkout-source-binding.json'])
    bindings = {item['path']: item for item in checkout['files']}
    require(checkout['sourceCommit'] == COMMIT and len(bindings) == len(checkout['files']) == 10
            and set(bindings) == SOURCE_NAMES, 'Checkout source binding inventory')
    for item in obj(files['source-inventory.json'])['files']:
        name = item['path']
        windows = actual['source/' + name]
        git_bytes = windows if name.endswith('.isf') else windows.replace(b'\r\n', b'\n')
        binding = bindings[name]
        require(binding['gitBytes'] == len(git_bytes) and binding['gitSha256'] == sha(git_bytes)
                and binding['windowsBytes'] == len(windows) and binding['windowsSha256'] == sha(windows)
                and item['bytes'] == len(windows) and item['sha256'] == sha(windows), 'Exact Git/Windows source-byte binding')
        require(name.endswith('.isf') or git_bytes.replace(b'\n', b'\r\n') == windows, 'Only checkout line endings differ')
        if check_git:
            data = subprocess.check_output(['git', '-C', str(check_git), 'show', COMMIT + ':' + name])
            require(data == git_bytes, 'Source differs from measured Git commit: ' + name)
    if check_git:
        require(subprocess.check_output(['git', '-C', str(check_git), 'rev-parse', COMMIT + '^{tree}']).decode().strip()
                == TREE, 'Measured Git tree')
    return result | {'runId': RUN, 'artifactFiles': len(archived), 'artifactBytes': len(raw), 'artifactSha256': sha(raw)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-git', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(check_git=args.check_git), sort_keys=True))

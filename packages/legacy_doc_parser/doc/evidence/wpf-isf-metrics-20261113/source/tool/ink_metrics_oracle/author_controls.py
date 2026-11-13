#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Author bounded ISF header controls without decoding/changing stroke packets."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
BASE_COMMIT = 'db1e2755a2a4ac98bf2df1e84e86d3c6f1716415'
WPF_SOURCE = 'e7acf467c05e51901b17684b1f2c330e7dc5fc4d'
SOURCES = {
    'polyline-solid': '39e578f56447df936949a31d4c250ae63bf74379d0ed361c5a800fcea0cd0e2f',
    'pressure-ramp': '98b16493ed4399dce44157426d9358d6656cc17a07562afde106144c3acc7e7d',
}
TRANSFORMS = (
    ('isotropic-2', 17, [2], [2, 0, 0, 2, 0, 0]),
    ('anisotropic-2-half', 18, [2, .5], [2, 0, 0, .5, 0, 0]),
    ('translate-100-minus50', 20, [100, -50], [1, 0, 0, 1, 100, -50]),
    ('affine-translate-100-minus50', 16, [1, 0, 0, 1, 100, -50], [1, 0, 0, 1, 100, -50]),
    ('scale-translate-2-half-100-minus50', 21, [2, .5, 100, -50], [2, 0, 0, .5, 100, -50]),
    ('affine-scale-translate-2-half-100-minus50', 16, [2, 0, 0, .5, 100, -50], [2, 0, 0, .5, 100, -50]),
)
TRANSFORM_VALUES = {16: 6, 17: 1, 18: 2, 20: 2, 21: 4}


def require(ok, label):
    if not ok:
        raise ValueError(label)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def uvar(value):
    require(isinstance(value, int) and 0 <= value <= 0xffffffff, 'Unsigned record length/tag')
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def read_uvar(raw, at):
    start = at
    value = 0
    for shift in range(0, 35, 7):
        require(at < len(raw), 'Truncated unsigned integer')
        byte = raw[at]
        at += 1
        value |= (byte & 127) << shift
        if byte < 128:
            require(raw[start:at] == uvar(value), 'Noncanonical unsigned integer')
            return value, at
    raise ValueError('Unbounded unsigned integer')


def signed(value):
    # WPF SerializationHelper.SignEncode: magnitude shifted left, sign in bit 0.
    return uvar(abs(value) * 2 + int(value < 0))


def records(raw):
    require(raw[0] == 0, 'Raw ISF version')
    length, at = read_uvar(raw, 1)
    require(length == len(raw) - at, 'ISF declared length')
    result = [{'offset': 0, 'end': at, 'kind': 'header', 'tag': 0,
               'hex': raw[:at].hex(), 'sha256': sha(raw[:at])}]
    while at < len(raw):
        start = at
        tag, at = read_uvar(raw, at)
        if tag in TRANSFORM_VALUES:
            at += TRANSFORM_VALUES[tag] * 4
        elif tag in (3, 5, 10, 25, 31):
            size, at = read_uvar(raw, at)
            at += size
        else:
            raise ValueError('Unexpected source/control record tag: ' + str(tag))
        require(at <= len(raw), 'Bounded record')
        part = raw[start:at]
        result.append({'offset': start, 'end': at, 'kind': 'record', 'tag': tag,
                       'hex': part.hex(), 'sha256': sha(part)})
    return result


def raw_record(item):
    return bytes.fromhex(item['hex'])


def transform(tag, values, extended):
    require(len(values) == TRANSFORM_VALUES[tag], 'Transform coefficient count')
    single = uvar(tag) + struct.pack('<' + 'f' * len(values), *values)
    if not extended:
        return [single]
    double = uvar(tag) + struct.pack('<' + 'd' * len(values), *values)
    return [single, uvar(31) + uvar(len(double)) + double]


def metric(maximum):
    # MetricBlock(25), NormalPressure known GUID index 50+6=56, sized payload.
    # Complete payload: signed minimum, signed maximum, unit=None(0), float resolution=1.
    data = signed(0) + signed(maximum) + uvar(0) + struct.pack('<f', 1)
    entry = uvar(56) + uvar(len(data)) + data
    return uvar(25) + uvar(len(entry)) + entry


def source_points(name):
    if name == 'polyline-solid':
        return [[0, 0], [1270, 0], [1270, 635], [2540, 635], [3175, 1270]]
    return [[0, 1270], [635, 635], [1270, 1270], [1905, 635], [2540, 1270]]


def make_case(name, source_name, raw, replacements=None, metric_max=None, transform_info=None):
    before = records(raw)
    require([r['tag'] for r in before] == ([0, 3, 17, 31, 10] if source_name == 'polyline-solid'
                                         else [0, 3, 5, 17, 31, 10]), 'Exact retained source record inventory')
    body = []
    for rec in before[1:]:
        if rec['tag'] == 17 and replacements is not None:
            body.extend(replacements)
        elif rec['tag'] == 31 and replacements is not None:
            continue
        elif rec['tag'] == 10 and metric_max is not None:
            body.extend([metric(metric_max), raw_record(rec)])
        else:
            body.append(raw_record(rec))
    body = b''.join(body)
    changed = b'\0' + uvar(len(body)) + body
    after = records(changed)
    stable_tags = (3, 5, 10)
    stable = []
    for tag in stable_tags:
        old = [r for r in before if r['tag'] == tag]
        new = [r for r in after if r['tag'] == tag]
        require([r['hex'] for r in old] == [r['hex'] for r in new], 'Unchanged drawing/stroke/descriptor payload')
        stable.extend({'tag': tag, 'beforeOffset': a['offset'], 'afterOffset': b['offset'],
                       'bytes': a['end'] - a['offset'], 'sha256': a['sha256']}
                      for a, b in zip(old, new))
    matrix = transform_info['sourceMatrixHimetric'] if transform_info else [1, 0, 0, 1, 0, 0]
    points = source_points(source_name)
    expected = [[x * matrix[0] + y * matrix[2] + matrix[4],
                 x * matrix[1] + y * matrix[3] + matrix[5]] for x, y in points]
    pressures = [0, 127, 511, 895, 1023] if source_name == 'pressure-ramp' else None
    return changed, {
        'name': name, 'sourceName': source_name,
        'sourcePath': f'test/fixtures/ink_wpf/{source_name}/uncompressed.isf',
        'inputPath': f'{name}/input.isf',
        'sourceSha256': sha(raw), 'sourceBytes': len(raw),
        'sha256': sha(changed), 'bytes': len(changed),
        'beforeHex': raw.hex(), 'afterHex': changed.hex(),
        'beforeRecords': before, 'afterRecords': after, 'unchangedRecords': stable,
        'transform': transform_info,
        'pressureMetric': {'explicit': metric_max is not None, 'minimum': 0,
                           'maximum': metric_max if metric_max is not None else 1023,
                           'unit': 'None', 'resolution': 1},
        'sourcePacketCoordinatesHimetric': points, 'rawPressurePackets': pressures,
        'sourceFormula': {'coordinateUnit': 'Himetric (1/100 millimeter)',
                          'formula': "x'=x*m11+y*m21+dx; y'=x*m12+y*m22+dy",
                          'matrix': matrix, 'points': expected,
                          'pressureFactors': [p / (metric_max or 1023) for p in pressures] if pressures else None,
                          'policy': 'Prediction authored before Windows execution; disagreement is recorded, never rewritten.'},
    }


def author(output, commit):
    require(not output.exists(), 'New output directory required')
    sources = {}
    for name, expected_hash in SOURCES.items():
        raw = (ROOT / 'test/fixtures/ink_wpf' / name / 'uncompressed.isf').read_bytes()
        require(sha(raw) == expected_hash, 'Exact retained WPF source: ' + name)
        sources[name] = raw
    output.mkdir(parents=True)
    cases = []
    for name, raw in sources.items():
        cases.append(make_case(name + '-baseline', name, raw))
    for name, tag, values, matrix in TRANSFORMS:
        for extended in (False, True):
            mode = 'float-and-double' if extended else 'float-only'
            cases.append(make_case(name + '-' + mode, 'polyline-solid', sources['polyline-solid'],
                                  replacements=transform(tag, values, extended),
                                  transform_info={'tag': tag, 'coefficients': values, 'mode': mode,
                                                  'sourceMatrixHimetric': matrix}))
    for maximum in (1023, 2047):
        cases.append(make_case(f'pressure-explicit-0-{maximum}', 'pressure-ramp', sources['pressure-ramp'],
                              metric_max=maximum))
    for data, description in cases:
        path = output / description['inputPath']
        path.parent.mkdir(parents=True)
        path.write_bytes(data)
    write_json(output / 'controls.json', {
        'schema': 'legacy-doc-parser/wpf-isf-header-controls', 'version': 1,
        'sourceCommit': commit, 'baseCommit': BASE_COMMIT, 'inspectedWpfSourceCommit': WPF_SOURCE,
        'caseCount': len(cases), 'scope': 'Only explicit ISF headers/metrics and outer lengths change; packet bodies stay byte-identical.',
        'cases': [case for _, case in cases],
    })
    source_paths = ['tool/ink_metrics_oracle/author_controls.py', 'tool/ink_metrics_oracle/Program.cs',
                    'tool/ink_metrics_oracle/InkMetricsOracle.csproj', 'tool/ink_metrics_oracle/global.json',
                    'tool/ink_metrics_oracle/README.md', '.github/workflows/ink-metrics-oracle.yml',
                    'tool/ink_oracle/Program.cs', 'doc/evidence/wpf-isf-oracle-20261113/verify.py']
    source_paths += [f'test/fixtures/ink_wpf/{name}/uncompressed.isf' for name in SOURCES]
    write_json(output / 'source-inventory.json', {'sourceCommit': commit, 'files': [
        {'path': path, 'bytes': len((ROOT / path).read_bytes()), 'sha256': sha((ROOT / path).read_bytes())}
        for path in sorted(source_paths)]})
    print(f'Authored {len(cases)} bounded controls; both original WPF fixtures and every stroke packet remain unchanged.')
    return [case for _, case in cases]


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('source_commit')
    args = parser.parse_args()
    require(len(args.source_commit) == 40 and all(c in '0123456789abcdef' for c in args.source_commit), 'Exact source commit')
    author(args.output.resolve(), args.source_commit)

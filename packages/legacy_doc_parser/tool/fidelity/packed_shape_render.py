#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check packed OfficeArt POINTs against native DOC playback and authored geometry.

The full-width and packed source encodings must produce identical native PDF
paths. Converted paths are also checked against independent numeric endpoints
and Bezier controls, including a reflection in both axes. No measured output
is adopted as a new expected shape. Requires installed LibreOffice/PyMuPDF.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

from oracle import ROOT, digest
from run import command, render
from shape_render import near, pdf_paths


def expected_path(flip):
    def point(x, y):
        return [84 - x, 60 - y] if flip == 'xy' else [x, y]

    return [
        ['l', point(6, 12), point(78, 12)],
        ['c', point(78, 12), point(78, 24), point(42, 48), point(6, 48)],
        ['l', point(6, 48), point(6, 12)],
    ]


def check_geometry(paths, flip, tolerance):
    strokes = [path for path in paths if path['color'] is not None]
    fills = [path for path in paths if path['fill'] is not None]
    if len(strokes) != 1 or len(fills) != 1:
        raise ValueError('Native curve lost or added a fill/stroke')
    stroke, fill = strokes[0], fills[0]
    if not near(stroke['bounds'], [6, 12, 78, 48], tolerance):
        raise ValueError('Native shape placement or bounds changed')
    if (not near(fill['fill'], [0.2, 0.4, 0.8], 0.0001)
            or not near(fill['bounds'], [6, 12, 78, 48], tolerance)):
        raise ValueError('Native fill color or geometry bounds changed')
    if not near(stroke['color'], [0, 0, 0], 0.0001) or abs(stroke['width'] - 2) > 0.01:
        raise ValueError('Native stroke changed')
    expected, actual = expected_path(flip), stroke['items']
    if len(actual) != len(expected) or any(
            item[0] != target[0] or len(item) != len(target) or
            any(not near(a, b, tolerance) for a, b in zip(item[1:], target[1:]))
            for item, target in zip(actual, expected)):
        raise ValueError('Native signed endpoints, cubic controls or reflection changed')
    drift = max(abs(a - b) for item, target in zip(actual, expected)
                for point, reference in zip(item[1:], target[1:])
                for a, b in zip(point, reference))
    return {'passes': True, 'maxCoordinateDriftPoints': drift,
            'tolerancePoints': tolerance, 'strokePoints': 2}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault('TMPDIR', str(output / 'tmp'))
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    report = {'schema': 'legacy-doc-parser/native-packed-points', 'version': 1,
              'method': 'Native full-width/packed DOC equivalence plus independent authored PDF coordinates.',
              'cases': {}, 'errors': []}
    try:
        import fitz

        report['renderer'] = command([args.office, '--version']).strip()
        report['pdfInspectorVersion'] = fitz.VersionBind
        report['parserCommit'] = command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        report['parserWorktreeDirty'] = bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip())
        command([args.dart, 'run', 'tool/fidelity/packed_shape_probe.dart', output / 'inputs'], cwd=ROOT)
        reference_paths = {}
        for flip in ('none', 'xy'):
            for encoding in ('full', 'packed', 'packed-header-excluded'):
                name = encoding + '-' + flip
                source = output / 'inputs' / (name + '.doc')
                converted = source.with_suffix('.docx')
                original_hash, converted_hash = digest(source), digest(converted)
                case = report['cases'][name] = {'sourceDocSha256': original_hash,
                                               'convertedDocxSha256': converted_hash}
                try:
                    case['sourceRender'] = render(args.office, source, output / name / 'source', 72)
                    case['convertedRender'] = render(args.office, converted, output / name / 'converted', 72)
                    with fitz.open(output / name / 'source' / (name + '.pdf')) as document:
                        source_paths = pdf_paths(document)
                    with fitz.open(output / name / 'converted' / (name + '.pdf')) as document:
                        converted_paths = pdf_paths(document)
                    case['sourcePdfPaths'] = source_paths
                    case['convertedPdfPaths'] = converted_paths
                    if encoding == 'full':
                        reference_paths[flip] = source_paths
                    case['nativeEncodingEquivalent'] = source_paths == reference_paths.get(flip)
                    if not case['nativeEncodingEquivalent']:
                        report['errors'].append(name + ': packed source differs from native full-width paths')
                    # Measure source and conversion independently, so a source
                    # placement failure cannot conceal successful path decoding.
                    # Native DOC playback may round its far frame by one twip.
                    for key, paths, tolerance in [('sourceGeometry', source_paths, 0.06),
                                                  ('convertedGeometry', converted_paths, 0.02)]:
                        try:
                            case[key] = check_geometry(paths, flip, tolerance)
                        except ValueError as error:
                            case[key] = {'passes': False, 'error': str(error)}
                            report['errors'].append(name + ': ' + key + ': ' + str(error))
                    case['sourcesUnchanged'] = digest(source) == original_hash and digest(converted) == converted_hash
                    if not case['sourcesUnchanged']:
                        raise ValueError('Input changed during native measurement')
                except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    case['error'] = str(error)
                    report['errors'].append(name + ': ' + str(error))
    except (ImportError, ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'checks': {name: {'geometry': case.get('convertedGeometry', {'passes': False}),
                                      'nativeEncodingEquivalent': case.get('nativeEncodingEquivalent', False)}
                                for name, case in report['cases'].items()},
                      'errors': report['errors']}, indent=2))
    return int(bool(report['errors']))


if __name__ == '__main__':
    raise SystemExit(main())

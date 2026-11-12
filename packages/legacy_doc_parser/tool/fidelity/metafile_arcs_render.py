#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check native EMF/WMF arc previews against authored geometric/color controls.

Each input contains an independent magenta reference rectangle. Arc positions
are measured relative to that rectangle, never fitted to the observed arc.
Samples distinguish small/large sweeps, chord/pie closure, and open-arc paint.
The geometric preview does not assert GDI raster equivalence.
"""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess

from oracle import ROOT, digest
from run import command, render, write_json


POINTS = {
    'upperCurve': (100 + 80 / math.sqrt(2), 50 - 40 / math.sqrt(2)),
    'lowerCurve': (100 - 80 / math.sqrt(2), 50 + 40 / math.sqrt(2)),
    'innerUpper': (124, 38),
    'innerLower': (76, 62),
    'chordClosure': (140, 30),
    'radialClosure': (140, 50),
}


def expectations(kind, variant):
    if kind not in ('arc', 'chord', 'pie', 'arcto') or variant not in (
            'counterclockwise', 'clockwise', 'full') or (kind in ('pie', 'arcto') and variant == 'full'):
        raise ValueError('Unsupported authored arc scenario')
    full = variant == 'full'
    clockwise = variant == 'clockwise'
    filled = kind in ('chord', 'pie')
    return {
        'upperCurve': 'red' if not clockwise or full else 'white',
        'lowerCurve': 'red' if clockwise or full else 'white',
        'innerUpper': 'black' if filled and (full or (kind == 'chord' and clockwise)
                                           or (kind == 'pie' and not clockwise)) else 'white',
        'innerLower': 'black' if filled and (clockwise or full) else 'white',
        'chordClosure': ('black' if full and filled else 'red' if kind == 'chord'
                         else 'black' if kind == 'pie' and not clockwise else 'white'),
        'radialClosure': ('red' if kind == 'pie' else 'black' if filled and (clockwise or full)
                          else 'white'),
    }


def assert_colors(kind, variant, samples):
    expected = expectations(kind, variant)
    if samples != expected:
        raise ValueError(f'{kind}-{variant} paint differs: expected {expected}, got {samples}')
    return {'passes': True, 'samples': samples}


def color_name(rgb):
    if all(value <= 20 for value in rgb):
        return 'black'
    if all(value >= 235 for value in rgb):
        return 'white'
    if rgb[0] >= 235 and rgb[1] <= 20 and rgb[2] <= 20:
        return 'red'
    raise ValueError('Authored sample is not a solid expected color: ' + str(rgb))


def check_bounds(kind, variant, observed):
    expected = [100, 10, 180, 50] if variant == 'counterclockwise' else [20, 10, 180, 90]
    if kind == 'arcto':
        expected[-1] = 95  # Authored connecting line starts below the ellipse.
    if len(observed) != 4 or not all(math.isfinite(value) for value in observed):
        raise ValueError('Invalid arc bounds')
    error = max(abs(a - b) for a, b in zip(observed, expected))
    # Native GDI record playback can quantize inclusive ellipse edges before
    # DOCX scaling. Two logical units cover that observed device quantization;
    # the reference canvas is 200 x 100, and the original radials are far outside it.
    if error > 2.1:
        raise ValueError(f'{kind}-{variant} bounds differ: {observed}, expected {expected}')
    return {'passes': True, 'logicalBounds': observed, 'expectedLogicalBounds': expected,
            'maximumLogicalError': error, 'toleranceLogicalUnits': 2.1}


def check_arcto_endpoint(points):
    expected = [100, 10, 20, 80]
    if len(points) != 4 or not all(math.isfinite(value) for value in points):
        raise ValueError('Invalid ArcTo following line')
    error = max(abs(a - b) for a, b in zip(points, expected))
    if error > 2.1:
        raise ValueError(f'ArcTo following line lost projected endpoint: {points}')
    return {'passes': True, 'logicalEndpoints': points, 'expectedLogicalEndpoints': expected,
            'maximumLogicalError': error, 'toleranceLogicalUnits': 2.1}


def inspect_page(page, kind, variant, *, native):
    import fitz

    drawings = page.get_drawings()
    anchors = [path for path in drawings if path['color'] == (1.0, 0.0, 1.0)]
    if len(anchors) != 1:
        raise ValueError('Expected exactly one independent magenta reference frame')
    anchor = anchors[0]['rect']
    if anchor.width <= 0 or anchor.height <= 0:
        raise ValueError('Invalid independent reference frame')
    def page_point(x, y):
        return anchor.x0 + (x - 10) * anchor.width / 180, anchor.y0 + (y - 5) * anchor.height / 90
    def logical_rect(rect):
        return [10 + (rect.x0 - anchor.x0) * 180 / anchor.width,
                5 + (rect.y0 - anchor.y0) * 90 / anchor.height,
                10 + (rect.x1 - anchor.x0) * 180 / anchor.width,
                5 + (rect.y1 - anchor.y0) * 90 / anchor.height]
    arcs = [path for path in drawings if path['color'] == (1.0, 0.0, 0.0)]
    if len(arcs) != 1:
        raise ValueError('Expected exactly one red arc outline')
    scale = 8
    image = page.get_pixmap(matrix=fitz.Matrix(scale, scale), colorspace=fitz.csRGB, alpha=False)
    samples = {name: color_name(image.pixel(round(scale * page_point(x, y)[0]),
                                            round(scale * page_point(x, y)[1])))
               for name, (x, y) in POINTS.items()}
    result = {'referenceFrame': list(anchor), 'native': native,
              'geometry': check_bounds(kind, variant, logical_rect(arcs[0]['rect'])),
              'paint': assert_colors(kind, variant, samples)}
    if kind == 'arcto':
        blue = [path for path in drawings if path['color'] == (0.0, 0.0, 1.0)]
        if len(blue) != 1 or len(blue[0]['items']) != 1 or blue[0]['items'][0][0] != 'l':
            raise ValueError('Expected one following blue line to inspect ArcTo current position')
        _, first, last = blue[0]['items'][0]
        points = [10 + (point.x - anchor.x0) * 180 / anchor.width if axis == 0
                  else 5 + (point.y - anchor.y0) * 90 / anchor.height
                  for point in (first, last) for axis in (0, 1)]
        result['followingLine'] = check_arcto_endpoint(points)
    return result


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
    report = {'schema': 'legacy-doc-parser/metafile-arcs', 'version': 1,
              'method': 'Native embedded EMF/WMF and generated SVG against independent reference frame and authored color samples.',
              'cases': {}, 'errors': []}
    try:
        import fitz

        report['renderer'] = command([args.office, '--version']).strip()
        report['pdfSvgInspectorVersion'] = fitz.VersionBind
        report['parserCommit'] = command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        report['parserWorktreeDirty'] = bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip())
        command([args.dart, 'run', 'tool/fidelity/metafile_arcs_probe.dart', output / 'inputs'], cwd=ROOT)
        for source in sorted((output / 'inputs').glob('*.docx')):
            format_name, kind, variant = source.stem.split('-')
            paths = {extension: source.with_suffix('.' + extension)
                     for extension in (format_name, 'doc', 'docx', 'svg')}
            case = report['cases'][source.stem] = {
                'sourceHashes': {extension: digest(path) for extension, path in paths.items()}}
            try:
                case['nativeRender'] = render(args.office, source, output / source.stem, 72)
                with fitz.open(output / source.stem / (source.stem + '.pdf')) as document:
                    if len(document) != 1:
                        raise ValueError('Authored metafile probe must render on one page')
                    case['native'] = inspect_page(document[0], kind, variant, native=True)
                with fitz.open(paths['svg']) as document:
                    case['preview'] = inspect_page(document[0], kind, variant, native=False)
                case['sourceUnchanged'] = all(digest(path) == case['sourceHashes'][extension]
                                            for extension, path in paths.items())
                if not case['sourceUnchanged']:
                    raise ValueError('Authored probe bytes changed during native measurement')
                case['passes'] = True
            except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                case['error'] = str(error)
                report['errors'].append(source.stem + ': ' + str(error))
            write_json(output / 'report.json', report)
        if len(report['cases']) != 15:
            raise ValueError('Expected all fifteen authored arc controls')
    except (ImportError, ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        write_json(output / 'report.json', report)
    print(json.dumps({'passed': sum(case.get('passes', False) for case in report['cases'].values()),
                      'cases': len(report['cases']), 'errors': report['errors']}, indent=2))
    return int(bool(report['errors']))


if __name__ == '__main__':
    raise SystemExit(main())

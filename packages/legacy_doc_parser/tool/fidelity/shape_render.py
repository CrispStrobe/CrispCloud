#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check native PDF geometry from authored binary OfficeArt fixtures.

Requires the already installed LibreOffice, Poppler and PyMuPDF. Coordinates
below are authored expectations; they are never copied from converted XML or
updated from a renderer run. This checks the supported geometry subset, not
arbitrary effects or universal Office raster equivalence.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

from oracle import ROOT, digest
from run import command, render


def near(actual, expected, tolerance=0.02):
    return len(actual) == len(expected) and all(abs(a - b) <= tolerance
                                               for a, b in zip(actual, expected))


def check_geometry(name, paths):
    axis_line = name.startswith('line-')
    is_line = name == 'line' or axis_line
    expected_bounds = ([6, 84, 78, 84] if name.startswith('line-h-')
                       else [6, 84, 6, 120] if name.startswith('line-v-')
                       else [6, 84, 78, 120])
    strokes = [path for path in paths if path['color'] is not None]
    fills = [path for path in paths if path['fill'] is not None]
    if len(strokes) != 1 or len(fills) != (0 if is_line else 1):
        raise ValueError('Native PDF lost or added a shape fill/stroke')
    stroke = strokes[0]
    if not near(stroke['bounds'], expected_bounds) or not near(stroke['color'], [0, 0, 0]):
        raise ValueError('Native shape bounds or stroke color changed')
    if abs(stroke['width'] - 2) > 0.01:
        raise ValueError('Native stroke width differs from the source 25400 EMU')
    if fills and (not near(fills[0]['fill'], [0.2, 0.4, 0.8], 0.0001)
                  or not near(fills[0]['bounds'], expected_bounds)):
        raise ValueError('Native fill color or bounds changed')
    if is_line:
        start, end = expected_bounds[:2], expected_bounds[2:]
        if axis_line:
            _, axis, flip = name.split('-')
            if (axis == 'h' and 'x' in flip) or (axis == 'v' and 'y' in flip):
                start, end = end, start
        items = stroke['items']
        if (len(items) != 1 or items[0][0] != 'l'
                or not near(items[0][1], start) or not near(items[0][2], end)):
            raise ValueError('Native line endpoints or direction changed')
    elif name == 'rect':
        corners = [[6, 84], [78, 84], [78, 120], [6, 120]]
        edges = fills[0]['items']
        if [item[0] for item in edges] == ['re']:
            actual = edges[0][1]
            if not near(actual, expected_bounds):
                raise ValueError('Native rectangle corners changed')
        else:
            if len(edges) != 4 or any(item[0] != 'l' for item in edges):
                raise ValueError('Native rectangle is no longer four straight edges')
            for index, edge in enumerate(edges):
                if not near(edge[1], corners[index]) or not near(edge[2], corners[(index + 1) % 4]):
                    raise ValueError('Native rectangle is distorted despite matching outer bounds')
    elif name == 'custom':
        expected = [
            ['l', [6, 84], [78, 84]],
            ['c', [78, 84], [78, 96], [42, 120], [6, 120]],
            ['l', [6, 120], [6, 84]],
        ]
        actual = stroke['items']
        if len(actual) != len(expected) or any(
                item[0] != target[0] or len(item) != len(target) or
                any(not near(a, b) for a, b in zip(item[1:], target[1:]))
                for item, target in zip(actual, expected)):
            raise ValueError('Native custom path endpoints or cubic controls changed')
    elif name == 'ellipse':
        if len(stroke['items']) < 4 or any(item[0] != 'c' for item in stroke['items']):
            raise ValueError('Native ellipse lost its closed curve geometry')
    return {'passes': True, 'boundsPoints': expected_bounds, 'strokePoints': 2}


def pdf_paths(document):
    import fitz

    if len(document) != 1:
        raise ValueError('Authored shape probe must render on one page')

    def serial(value):
        if isinstance(value, fitz.Quad):
            return [list(point) for point in value]
        if isinstance(value, (fitz.Point, fitz.Rect)):
            return list(value)
        return value

    return [{'bounds': list(path['rect']), 'color': path['color'],
             'fill': path['fill'], 'width': path['width'],
             'items': [[serial(value) for value in item] for item in path['items']]}
            for path in document[0].get_drawings()]


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
    report = {'schema': 'legacy-doc-parser/native-shape-geometry', 'version': 1,
              'method': 'Independent native PDF vectors against authored source coordinates; no generated goldens.',
              'cases': {}, 'errors': []}
    try:
        import fitz

        report['renderer'] = command([args.office, '--version']).strip()
        report['pdfInspectorVersion'] = fitz.VersionBind
        report['parserCommit'] = command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        report['parserWorktreeDirty'] = bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip())
        command([args.dart, 'run', 'tool/fidelity/shape_probe.dart', output / 'inputs'], cwd=ROOT)
        names = ['rect', 'ellipse', 'line', 'custom'] + [
            f'line-{axis}-{flip}' for axis in ('h', 'v') for flip in ('none', 'x', 'y', 'xy')]
        for name in names:
            source = output / 'inputs' / (name + '.docx')
            before = digest(source)
            case = report['cases'][name] = {'sourceDocSha256': digest(source.with_suffix('.doc')),
                                           'convertedDocxSha256': before}
            try:
                case['render'] = render(args.office, source, output / name, 72)
                with fitz.open(output / name / (name + '.pdf')) as document:
                    case['pdfPaths'] = pdf_paths(document)
                case['geometry'] = check_geometry(name, case['pdfPaths'])
                case['sourceUnchanged'] = digest(source) == before
                if not case['sourceUnchanged']:
                    raise ValueError('Converted probe changed during native measurement')
            except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                case['error'] = str(error)
                report['errors'].append(name + ': ' + str(error))
    except (ImportError, ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'checks': {name: case.get('geometry', {'passes': False})
                                for name, case in report['cases'].items()},
                      'errors': report['errors']}, indent=2))
    return int(bool(report['errors']))


if __name__ == '__main__':
    raise SystemExit(main())

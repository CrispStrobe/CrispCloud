#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Measure authored, native-DOC and converted three-shape controls separately."""
import argparse
import hashlib
import json
from pathlib import Path

import fitz
import numpy as np

from run import command, digest, office_convert

ROOT = Path(__file__).resolve().parents[2]


def path_items(items):
    """Keep commands and every coordinate in a JSON-compatible form."""
    return [[item[0], *[list(value) if isinstance(value, (fitz.Point, fitz.Rect))
                       else [list(point) for point in value] if isinstance(value, fitz.Quad)
                       else value for value in item[1:]]] for item in items]


def line_edges(items):
    """Exact, direction-independent line edges; never equate unknown curves."""
    edges = []
    for item in items:
        if item[0] == 'l':
            pairs = [(item[1], item[2])]
        elif item[0] == 'qu':
            points = item[1]
            pairs = [(points[a], points[b]) for a, b in ((0, 1), (1, 3), (3, 2), (2, 0))]
        else:
            return None
        edges.extend(sorted((tuple(first), tuple(second))) for first, second in pairs)
    return sorted(edges)


def command_drift(left, right):
    if len(left) != len(right) or any(a[0] != b[0] or len(a) != len(b)
                                    for a, b in zip(left, right)):
        return None
    if any(item[0] not in ('l', 'c') for item in left):
        return None
    return max((abs(a-b) for first, second in zip(left, right)
                for point_a, point_b in zip(first[1:], second[1:])
                for a, b in zip(point_a, point_b)), default=0)


def measure(pdf):
    with fitz.open(pdf) as document:
        assert len(document) == 1
        page = document[0]
        pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
        pixels = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(
            pixmap.height, pixmap.width, pixmap.n)[:, :, :3].copy()
        paths = []
        for path in page.get_drawings():
            paths.append({key: list(value) if isinstance(value, fitz.Rect) else value
                for key, value in path.items() if key != 'items'})
            paths[-1]['items'] = path_items(path['items'])
        shapes = []
        for path in paths:
            # Different fill/stroke opacity can require separate PDF paint
            # operators. Join only adjacent fill/stroke paths with identical
            # rectangles AND exact line edges; retain every raw path.
            if path['type'] == 's' and shapes and shapes[-1]['type'] == 'f' and \
                    shapes[-1]['rect'] == path['rect'] and \
                    line_edges(path['items']) is not None and \
                    line_edges(shapes[-1]['items']) == line_edges(path['items']):
                for key in ('color', 'width', 'lineCap', 'lineJoin', 'dashes', 'stroke_opacity'):
                    shapes[-1][key] = path[key]
                shapes[-1]['type'] = 'fs'
                shapes[-1]['paintOperators'] = 2
            else:
                shapes.append({**path, 'paintOperators': 1})
        return {'pdfSha256': digest(pdf), 'rasterSha256': hashlib.sha256(pixels.tobytes()).hexdigest(),
            'pagePoints': list(page.rect)[2:], 'text': page.get_text(), 'paths': paths,
            'paintedShapes': shapes}, pixels


def compare(reference, actual):
    expected, expected_pixels = reference
    observed, observed_pixels = actual
    same_page = expected['pagePoints'] == observed['pagePoints']
    same_paths = len(expected['paths']) == len(observed['paths'])
    same_shapes = len(expected['paintedShapes']) == len(observed['paintedShapes'])
    differences = []
    if same_shapes:
        for index, (left, right) in enumerate(zip(expected['paintedShapes'], observed['paintedShapes'])):
            differences.append({'index': index,
                'maximumBoundDriftPoints': max(abs(a-b) for a, b in zip(left['rect'], right['rect'])),
                'orderedCommandCoordinateDriftPoints': command_drift(left['items'], right['items']),
                'fillMatches': left['fill'] == right['fill'], 'strokeColorMatches': left['color'] == right['color'],
                'strokeWidthDifferencePoints': abs(left['width'] - right['width']),
                'dashMatches': left['dashes'] == right['dashes'],
                'referenceDash': left['dashes'], 'actualDash': right['dashes']})
    return {'pageDimensionsMatch': same_page, 'textMatches': expected['text'] == observed['text'],
        'rawPathCountsMatch': same_paths,
        'rawPathCounts': [len(expected['paths']), len(observed['paths'])],
        'paintedShapeCountsMatch': same_shapes, 'shapes': differences,
        'rgbChangedPixels': int(np.any(expected_pixels != observed_pixels, axis=2).sum()) if same_page else None,
        'rgbExactlyMatches': same_page and bool(np.array_equal(expected_pixels, observed_pixels))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True, type=Path)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    converted = output / 'converted'
    command([args.dart, 'run', ROOT / 'tool/fidelity/shape_context_probe.dart', converted], cwd=ROOT)
    manifest = json.loads((converted / 'manifest.json').read_text())
    assert manifest['counts']['editableShapes'] == 3
    assert manifest['counts']['shapePathEditingHints'] == 5
    sources = {'authored': ROOT / 'test/fixtures/fidelity/officeart-shapes.docx',
        'nativeDoc': ROOT / 'test/fixtures/fidelity/officeart-shapes.doc',
        'converted': converted / 'officeart-shapes.docx'}
    hashes = {kind: digest(path) for kind, path in sources.items()}
    measured = {kind: measure(office_convert(args.office, path, output / 'render' / kind, 'pdf'))
                for kind, path in sources.items()}
    assert hashes == {kind: digest(path) for kind, path in sources.items()}
    native_comparison = compare(measured['nativeDoc'], measured['converted'])
    geometry_checks = (
        native_comparison['pageDimensionsMatch'] and native_comparison['textMatches'] and
        native_comparison['paintedShapeCountsMatch'] and len(native_comparison['shapes']) == 3 and
        all(path['maximumBoundDriftPoints'] <= 0.1 and path['fillMatches'] and
            path['strokeColorMatches'] and path['strokeWidthDifferencePoints'] <= 0.03
            for path in native_comparison['shapes']) and
        native_comparison['shapes'][2]['orderedCommandCoordinateDriftPoints'] is not None and
        native_comparison['shapes'][2]['orderedCommandCoordinateDriftPoints'] <= 0.1)
    report = {'implementationBaseCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
        'workingTreeChanges': command(['git', 'status', '--short'], cwd=ROOT).splitlines(),
        'officeVersion': command([args.office, '--version']).strip(), 'rasterDpi': 144,
        'nativeGeometryTolerancePoints': 0.1, 'sourceSha256': hashes,
        'sourceModel': manifest, 'sourceFilesUnchanged': True,
        'renders': {kind: result[0] for kind, result in measured.items()},
        'authoredToNativeDoc': compare(measured['authored'], measured['nativeDoc']),
        'authoredToConverted': compare(measured['authored'], measured['converted']),
        'nativeDocToConverted': native_comparison,
        'nativeGeometryChecksPass': geometry_checks,
        'nativeTangentEditorBehaviorMapped': False,
        'scope': 'Resolved geometry, inactive solid backgrounds and explicit cell layout; original native bridge and renderer dash differences remain visible.'}
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'nativeDocToConverted': native_comparison, 'sourceFilesUnchanged': True}, indent=2))
    assert geometry_checks, 'Native geometry checks failed; see retained report.json'


if __name__ == '__main__':
    main()

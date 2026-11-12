#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compare authored image controls, native DOC bridges and converted DOCX."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
import zipfile

import fitz
import numpy as np

from image_appearance_cases import CASES, write_cases
from run import command, digest, office_convert

ROOT = Path(__file__).resolve().parents[2]
COLORS = {'red': (255, 0, 0), 'green': (0, 255, 0),
          'blue': (0, 0, 255), 'yellow': (255, 255, 0)}
A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'


def measure(pdf):
    with fitz.open(pdf) as document:
        assert len(document) == 1
        page = document[0]
        pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
        raster = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(pixmap.height, pixmap.width, pixmap.n)[:, :, :3]
        rgb = raster.astype(np.int16)
        masks = {name: np.all(np.abs(rgb - color) < 16, axis=2)
                 for name, color in COLORS.items()}
        rows, columns = np.where(np.logical_or.reduce(list(masks.values())))
        assert len(columns), 'No quadrant pixels were rendered'
        bounds = [int(columns.min()), int(rows.min()), int(columns.max() + 1), int(rows.max() + 1)]
        centroids = {}
        for name, mask in masks.items():
            y, x = np.where(mask)
            assert len(x), 'Missing quadrant: ' + name
            centroids[name] = [float((x.mean() - bounds[0]) / (bounds[2] - bounds[0])),
                               float((y.mean() - bounds[1]) / (bounds[3] - bounds[1]))]
        shadow_mask = np.all(np.abs(rgb - np.array([162, 170, 178])) <= 5, axis=2)
        shadow_pixels = rgb[shadow_mask]
        record = {
            'pdfSha256': digest(pdf), 'pagePoints': [page.rect.width, page.rect.height],
            'rasterDpi': 144, 'rasterSha256': hashlib.sha256(raster.tobytes()).hexdigest(),
            'quadrantBoundsPoints': [value / 2 for value in bounds],
            'normalizedColorCentroids': centroids,
            'quadrantPixels': {name: int(mask.sum()) for name, mask in masks.items()},
            'magentaPixels': int(np.all(np.abs(rgb - [255, 0, 255]) < 16, axis=2).sum()),
            'shadowPixels': int(shadow_mask.sum()),
            'medianShadowRgb': np.median(shadow_pixels, axis=0).tolist() if len(shadow_pixels) else None,
            'paths': [{'type': path['type'], 'rect': list(path['rect']),
                       'color': path['color'], 'fill': path['fill'],
                       'width': path['width'], 'dashes': path['dashes']}
                      for path in page.get_drawings()],
        }
        return record, raster.copy()


def compare(reference, actual):
    expected, expected_rgb = reference
    observed, observed_rgb = actual
    same_page = expected['pagePoints'] == observed['pagePoints']
    return {
        'samePageDimensions': same_page,
        'maximumQuadrantBoundDriftPoints': max(abs(a - b) for a, b in zip(
            expected['quadrantBoundsPoints'], observed['quadrantBoundsPoints'])),
        'maximumNormalizedCentroidDrift': max(abs(a - b)
            for color in COLORS for a, b in zip(expected['normalizedColorCentroids'][color],
                                               observed['normalizedColorCentroids'][color])),
        'rgbChangedPixels': int(np.any(expected_rgb != observed_rgb, axis=2).sum()) if same_page else None,
        'rgbExactlyMatches': same_page and bool(np.array_equal(expected_rgb, observed_rgb)),
    }


def check_paint(path, reference, actual):
    with zipfile.ZipFile(path) as package:
        document = ET.fromstring(package.read('word/document.xml'))
    line = document.find('.//' + A + 'ln')
    assert line is not None
    assert abs(int(line.attrib['w']) - 25400) <= 200
    assert line.attrib['cap'] == 'flat'
    assert line.find(A + 'prstDash').attrib['val'] == 'sysDot'
    assert line.find('.//' + A + 'srgbClr').attrib['val'] == 'FF00FF'
    shadow = document.find('.//' + A + 'outerShdw')
    assert shadow is not None and shadow.attrib['blurRad'] == '0'
    assert shadow.attrib['rotWithShape'] == '0'
    assert shadow.find(A + 'srgbClr').attrib['val'] == '445566'
    assert abs(int(shadow.find('.//' + A + 'alpha').attrib['val']) - 50000) <= 100
    distance = int(shadow.attrib['dist'])
    angle = int(shadow.attrib['dir']) * math.pi / 10800000
    assert abs(distance * math.cos(angle) - 38100) <= 1000
    assert abs(distance * math.sin(angle) - 50800) <= 1000
    magenta = [path for path in actual['paths'] if path['color'] == (1.0, 0.0, 1.0)]
    assert len(magenta) == 1 and abs(magenta[0]['width'] - 2) <= 0.03
    assert actual['magentaPixels'] > 0 and actual['shadowPixels'] > 0
    assert reference['medianShadowRgb'] is not None
    assert max(abs(a - b) for a, b in zip(reference['medianShadowRgb'], actual['medianShadowRgb'])) <= 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True, type=Path)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    authored = output / 'authored'
    write_cases(authored)
    binary = output / 'binary'
    binary.mkdir()
    for name in CASES:
        native = office_convert(args.office, authored / (name + '.docx'), output / 'native-doc' / name, 'doc')
        shutil.copyfile(native, binary / (name + '.doc'))
    converted = output / 'converted'
    command([args.dart, 'run', ROOT / 'tool/fidelity/image_appearance_probe.dart', binary, converted], cwd=ROOT)
    source_model = json.loads((converted / 'manifest.json').read_text())
    report = {
        'officeVersion': command([args.office, '--version']).strip(),
        'implementationBaseCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
        'workingTreeChanges': command(['git', 'status', '--short'], cwd=ROOT).splitlines(),
        'scope': 'Quarter-turn image frames, FSP flips, direct line and simple offset shadow; native DOC interpretation loss is measured separately.',
        'tolerances': {'quadrantBoundsPoints': 0.5, 'normalizedCentroid': 0.025, 'shadowMedianRgb': 2},
        'cases': {},
    }
    for name, case in CASES.items():
        paths = {'authored': authored / (name + '.docx'), 'binary': binary / (name + '.doc'),
                 'converted': converted / (name + '.docx')}
        hashes = {kind: digest(path) for kind, path in paths.items()}
        measured = {}
        for kind, path in paths.items():
            pdf = office_convert(args.office, path, output / 'render' / name / kind, 'pdf')
            measured[kind] = measure(pdf)
        comparison = compare(measured['authored'], measured['converted'])
        assert comparison['samePageDimensions']
        assert comparison['maximumQuadrantBoundDriftPoints'] <= 0.5, (name, comparison)
        assert comparison['maximumNormalizedCentroidDrift'] <= 0.025, (name, comparison)
        if case.get('paint'):
            check_paint(paths['converted'], measured['authored'][0], measured['converted'][0])
        assert hashes == {kind: digest(path) for kind, path in paths.items()}
        report['cases'][name] = {
            'sourceSha256': hashes, 'sourceModel': source_model[name],
            'render': {kind: result[0] for kind, result in measured.items()},
            'authoredToBinary': compare(measured['authored'], measured['binary']),
            'authoredToConverted': comparison,
            'binaryToConverted': compare(measured['binary'], measured['converted']),
            'supportedChecksPass': True, 'sourceFilesUnchanged': True,
        }
        print(name + ': supported appearance checks pass; RGB exact=' + str(comparison['rgbExactlyMatches']), flush=True)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()

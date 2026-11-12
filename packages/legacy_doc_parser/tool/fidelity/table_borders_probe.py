#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Independently compare native row-border projections and colored border pixels."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from PIL import Image
from run import command, office_convert

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def colored_mask(image):
    rgb = iter(image.convert('RGB').tobytes())
    return bytes(255 if max(color) - min(color) > 60 else 0
                 for color in zip(rgb, rgb, rgb))


def visible_borders(path):
    with ZipFile(path) as archive:
        document = ET.fromstring(archive.read('word/document.xml'))
    cells = []
    for cell in document.findall(f'.//{W}tc'):
        values = {}
        for side in ('top', 'left', 'start', 'bottom', 'right', 'end'):
            border = cell.find(f'{W}tcPr/{W}tcBorders/{W}{side}')
            if border is None or border.get(W + 'val') in ('none', 'nil'):
                continue
            key = {'start': 'left', 'end': 'right'}.get(side, side)
            values[key] = {'style': border.get(W + 'val'),
                           'width': int(border.get(W + 'sz', '0')),
                           'color': border.get(W + 'color', 'auto').upper()}
        cells.append(values)
    return cells


def colored_pixels(office, source, output):
    pdf = office_convert(office, source, output, 'pdf')
    prefix = output / 'border'
    command(['pdftoppm', '-f', '1', '-singlefile', '-r', '144', pdf, prefix])
    with Image.open(prefix.with_suffix('.ppm')) as rendered:
        image = rendered.convert('RGB')
        pixels = colored_mask(image)
        mask = Image.frombytes('L', image.size, pixels)
        mask.save(output / 'border-mask.png')
        metadata = {'size': list(image.size), 'pixelCount': pixels.count(255),
                    'bounds': list(mask.getbbox()) if mask.getbbox() else None,
                    'sha256': hashlib.sha256(pixels).hexdigest()}
    return metadata, pixels


def probe(office, fixtures, output, case):
    name = case['name']
    source = fixtures / (name + '.doc')
    converted = fixtures / (name + '-converted.docx')
    folder = output / name
    native = office_convert(office, source, folder / 'native', 'docx')
    original_mask, original_pixels = colored_pixels(office, source, folder / 'source-pdf')
    actual_mask, actual_pixels = colored_pixels(office, converted, folder / 'converted-pdf')
    return {'name': name, 'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'nativeBorders': visible_borders(native),
            'convertedBorders': visible_borders(converted),
            'sourceMask': original_mask, 'convertedMask': actual_mask,
            'differingColoredPixels': sum(a != b for a, b in zip(
                original_pixels, actual_pixels)) if
            original_mask['size'] == actual_mask['size'] else None}


def compare_golden(results, golden):
    prior = {case['name']: case for case in golden['cases']}
    failures = []
    if len(results) != len(prior) or set(prior) != {case['name'] for case in results}:
        failures.append('fixture names differ')
    for case in results:
        expected = prior.get(case['name'])
        if expected is None:
            continue
        if case['sourceSha256'] != expected['sourceSha256']:
            failures.append(case['name'] + ': source bytes changed')
        for label in ('nativeBorders', 'convertedBorders'):
            if case[label] != expected['borders']:
                failures.append(case['name'] + ': ' + label)
        for label in ('sourceMask', 'convertedMask'):
            if case[label] != expected['coloredMask']:
                failures.append(case['name'] + ': ' + label)
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--fixtures', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--golden', type=Path,
                        help='Reviewed native projections; never updated by the probe')
    arguments = parser.parse_args()
    fixtures, output = arguments.fixtures.resolve(), arguments.output.resolve()
    cases = json.loads((fixtures / 'manifest.json').read_text())
    output.mkdir(parents=True, exist_ok=False)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda case: probe(arguments.office, fixtures, output, case),
                                cases))
    report = {'schema': 'legacy-doc-parser/table-borders-probe', 'version': 1,
              'renderer': command([arguments.office, '--version']).strip(), 'cases': results}
    if arguments.golden:
        report['goldenFailures'] = compare_golden(
            results, json.loads(arguments.golden.read_text()))
    (output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    for case in results:
        print(case['name'], 'nativeBordersMatch=',
              case['nativeBorders'] == case['convertedBorders'],
              'differingColoredPixels=', case['differingColoredPixels'])
    if report.get('goldenFailures'):
        raise SystemExit('Table-border golden mismatch: ' + ', '.join(report['goldenFailures']))


if __name__ == '__main__':
    main()

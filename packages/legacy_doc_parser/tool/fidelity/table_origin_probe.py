#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compare independently assembled DOC row origins on an installed renderer."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from run import command, office_convert

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def text_positions(office, source, output):
    pdf = office_convert(office, source, output, 'pdf')
    xml = ET.fromstring(command(['pdftotext', '-bbox-layout', pdf, '-']))
    words = {e.text: {k: float(v) for k, v in e.attrib.items()}
             for e in xml.iter() if e.tag.endswith('}word')}
    return {key: words[key] for key in ('BODY', 'CELL', 'AFTER', 'OUTER')
            if key in words}


def native_indent(path):
    with ZipFile(path) as archive:
        root = ET.fromstring(archive.read('word/document.xml'))
    return [int(value.get(W + 'w', '0'))
            for value in root.findall(f'.//{W}tblPr/{W}tblInd')]


def probe(office, fixtures, output, case):
    name = case['name']
    folder = output / name
    source = fixtures / (name + '.doc')
    converted = fixtures / (name + '-converted.docx')
    native = office_convert(office, source, folder / 'native', 'docx')
    original = text_positions(office, source, folder / 'source-pdf')
    actual = text_positions(office, converted, folder / 'converted-pdf')
    anchor = 'BODY' if case.get('depth', 1) == 1 else 'OUTER'
    return {**case, 'nativeIndentTwips': native_indent(native),
            'convertedIndentTwips': native_indent(converted),
            'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'source': original, 'converted': actual,
            'cellHorizontalDriftPoints': round(
                (actual['CELL']['xMin'] - actual[anchor]['xMin']) -
                (original['CELL']['xMin'] - original[anchor]['xMin']), 4),
            'alignmentAnchor': anchor}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--fixtures', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--golden', type=Path,
                        help='Optional reviewed native measurements; never updated')
    arguments = parser.parse_args()
    cases = json.loads((arguments.fixtures / 'manifest.json').read_text())
    arguments.output.mkdir(parents=True, exist_ok=False)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda case: probe(
            arguments.office, arguments.fixtures, arguments.output, case), cases))
    report = {'schema': 'legacy-doc-parser/table-origin-probe', 'version': 1,
              'renderer': command([arguments.office, '--version']).strip(),
              'cases': results,
              'maximumHorizontalDriftPoints': max(
                  abs(case['cellHorizontalDriftPoints']) for case in results)}
    if arguments.golden:
        expected = {case['name']: case for case in
                    json.loads(arguments.golden.read_text())['cases']}
        failures = []
        if set(expected) != {case['name'] for case in results}:
            failures.append('fixture names differ')
        for case in results:
            golden = expected.get(case['name'])
            if golden is None:
                continue
            anchor = case['alignmentAnchor']
            x = case['converted']['CELL']['xMin'] - case['converted'][anchor]['xMin']
            if (case['sourceSha256'] != golden['sourceSha256'] or
                    case['nativeIndentTwips'] != golden['nativeIndentTwips'] or
                    case['convertedIndentTwips'] != golden['nativeIndentTwips'] or
                    abs(x - golden['relativeCellXPoints']) > 0.1 or
                    abs(case['cellHorizontalDriftPoints']) > 0.1):
                failures.append(case['name'])
        report['goldenFailures'] = failures
    (arguments.output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    for case in results:
        print(case['name'], 'nativeIndent=', case['nativeIndentTwips'],
              'actualIndent=', case['convertedIndentTwips'],
              'cellDrift=', case['cellHorizontalDriftPoints'])
    if report.get('goldenFailures'):
        raise SystemExit('Table-origin golden mismatch: ' + ', '.join(report['goldenFailures']))


if __name__ == '__main__':
    main()

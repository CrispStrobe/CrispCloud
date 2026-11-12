#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Measure authored MS-DOC row heights and page-break constraints independently."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from run import command, office_convert

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def normalized_rows(rows):
    return [{'heightTwips': int(row.get('trHeight', {}).get('val', '0')),
             'heightRule': row.get('trHeight', {}).get('hRule', 'auto'),
             'cantSplit': row.get('cantSplit', {}).get('val', False)}
            for row in rows]


def normalized_cells(cells):
    return [{'textDirection': cell.get('textDirection', 'lrTb'),
             'fitText': cell.get('tcFitText', 'off') in ('on', 'true', '1'),
             'hideMark': cell.get('hideMark', 'off') in ('on', 'true', '1')}
            for cell in cells]


def compare_golden(results, golden):
    """Compare both current source-renderer output and parser output to review."""
    expected = {case['name']: case for case in golden['cases']}
    failures = []
    if set(expected) != {case['name'] for case in results}:
        failures.append('fixture names differ')
    for case in results:
        prior = expected.get(case['name'])
        if prior is None:
            continue
        if case['sourceSha256'] != prior['sourceSha256']:
            failures.append(case['name'] + ': source bytes changed')
        for label in ('native', 'converted'):
            if normalized_rows(case[label]['rows']) != prior['rows']:
                failures.append(case['name'] + ': ' + label + ' row properties')
        if 'cellProperties' in prior:
            if normalized_cells(case['converted']['cells']) != prior['cellProperties']:
                failures.append(case['name'] + ': converted cell properties')
            if case['native']['cells'] != prior['nativeCellProjection']:
                failures.append(case['name'] + ': native cell projection changed')
        if 'layout' not in prior:
            continue
        for label in ('sourceLayout', 'convertedLayout'):
            actual = case[label]
            if actual['pages'] != prior['layout']['pages']:
                failures.append(case['name'] + ': ' + label + ' page count')
            for word, position in prior['layout']['words'].items():
                found = actual['words'].get(word)
                if (found is None or found['page'] != position['page'] or
                        any(abs(found[key] - position[key]) > 0.1
                            for key in ('xMin', 'yMin', 'xMax', 'yMax'))):
                    failures.append(case['name'] + ': ' + label + ' ' + word)
    return failures


def native_properties(path):
    with ZipFile(path) as archive:
        document = ET.fromstring(archive.read('word/document.xml'))
    rows = []
    for row in document.findall(f'.//{W}tr'):
        properties = {}
        for tag in ('trHeight', 'cantSplit'):
            value = row.find(f'{W}trPr/{W}{tag}')
            if value is not None:
                attributes = {k.removeprefix(W): v for k, v in value.attrib.items()}
                if tag == 'cantSplit':
                    attributes = {'val': attributes.get('val', 'true')
                                  in ('true', '1', 'on')}
                properties[tag] = attributes
        rows.append(properties)
    cells = []
    for cell in document.findall(f'.//{W}tcPr'):
        cells.append({tag: element.get(W + 'val', 'true')
                      for tag in ('textDirection', 'tcFitText', 'hideMark')
                      if (element := cell.find(W + tag)) is not None})
    return {'rows': rows, 'cells': cells}


def positions(office, source, output):
    pdf = office_convert(office, source, output, 'pdf')
    root = ET.fromstring(command(['pdftotext', '-bbox-layout', pdf, '-']))
    pages = [element for element in root.iter() if element.tag.endswith('}page')]
    words = {}
    for page_number, page in enumerate(pages, 1):
        for word in page.iter():
            if word.tag.endswith('}word') and word.text:
                words[word.text] = {'page': page_number,
                                   **{k: float(v) for k, v in word.attrib.items()}}
    return {'pages': len(pages), 'words': words}


def probe(office, fixtures, output, case):
    folder = output / case['name']
    source = fixtures / (case['name'] + '.doc')
    converted = fixtures / (case['name'] + '-converted.docx')
    native = office_convert(office, source, folder / 'native', 'docx')
    result = {**case, 'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'native': native_properties(native),
              'converted': native_properties(converted)}
    if case['kind'] != 'cell':
        original = positions(office, source, folder / 'source-pdf')
        actual = positions(office, converted, folder / 'converted-pdf')
        result.update({'sourceLayout': original, 'convertedLayout': actual})
        if case['kind'] == 'height':
            def extent(layout):
                return layout['words']['NEXT']['yMin'] - layout['words']['CELL']['yMin']
            result['rowExtentDriftPoints'] = round(extent(actual) - extent(original), 4)
        else:
            result['rowWordPagesMatch'] = all(
                actual['words'][f'ROW2{letter}']['page'] ==
                original['words'][f'ROW2{letter}']['page'] for letter in 'ABCDEF')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--golden', type=Path,
                        help='Optional reviewed native measurements; never updated')
    arguments = parser.parse_args()
    arguments.fixtures = arguments.fixtures.resolve()
    arguments.output = arguments.output.resolve()
    cases = json.loads((arguments.fixtures / 'manifest.json').read_text())
    arguments.output.mkdir(parents=True, exist_ok=False)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda case: probe(arguments.office, arguments.fixtures,
                                                  arguments.output, case), cases))
    report = {'schema': 'legacy-doc-parser/table-layout-probe', 'version': 1,
              'renderer': command([arguments.office, '--version']).strip(), 'cases': results}
    if arguments.golden:
        report['goldenFailures'] = compare_golden(
            results, json.loads(arguments.golden.read_text()))
    (arguments.output / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    for case in results:
        print(case['name'], 'rowExtentDrift=', case.get('rowExtentDriftPoints'),
              'rowWordPagesMatch=', case.get('rowWordPagesMatch'))
    if report.get('goldenFailures'):
        raise SystemExit('Table-layout golden mismatch: ' +
                         ', '.join(report['goldenFailures']))


if __name__ == '__main__':
    main()

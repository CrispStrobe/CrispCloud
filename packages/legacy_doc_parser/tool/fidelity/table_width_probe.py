#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compare literal TC80/range preferred-width records with a native Office bridge."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from run import command, office_convert
from table_layout_probe import positions

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def properties(path):
    with ZipFile(path) as archive:
        root = ET.fromstring(archive.read('word/document.xml'))
    tables = []
    for table in root.findall(f'.//{W}tbl'):
        value = {'grid': [int(c.get(W + 'w')) for c in table.findall(f'{W}tblGrid/{W}gridCol')], 'cells': []}
        for cell in table.findall(f'{W}tr/{W}tc/{W}tcPr'):
            width = cell.find(W + 'tcW')
            wrap = cell.find(W + 'noWrap')
            value['cells'].append({
                'widthType': None if width is None else width.get(W + 'type'),
                'width': None if width is None else width.get(W + 'w'),
                'noWrap': wrap is not None and wrap.get(W + 'val', 'on') in ('1', 'on', 'true'),
                **{tag: element.get(W + 'val', 'true')
                   for tag in ('textDirection', 'tcFitText', 'hideMark')
                   if (element := cell.find(W + tag)) is not None},
            })
        tables.append(value)
    return tables


def compare_layout(left, right):
    words_equal = set(left['words']) == set(right['words'])
    page_equal = left['pages'] == right['pages'] and all(
        left['words'][word]['page'] == right['words'].get(word, {}).get('page')
        for word in left['words'])
    delta = max((abs(left['words'][word][key] - right['words'][word][key])
                 for word in left['words'].keys() & right['words'].keys()
                 for key in ('xMin', 'yMin', 'xMax', 'yMax')), default=None)
    return {'sameWords': words_equal, 'samePages': page_equal, 'maxWordDeltaPoints': delta}


def compare_golden(results, golden):
    """Keep lossy native projections separate from the expected native XML output."""
    expected = {case['name']: case for case in golden['cases']}
    failures = []
    names = [case['name'] for case in results]
    if set(expected) != set(names) or len(names) != len(expected):
        failures.append('fixture names differ')
    for case in results:
        prior = expected.get(case['name'])
        if prior is None:
            continue
        name = case['name']
        if case['sourceSha256'] != prior['sourceSha256']:
            failures.append(name + ': source bytes changed')
        for label in ('native', 'converted'):
            if case[label] != prior[label]:
                failures.append(name + ': ' + label + ' properties')
        for label in ('sourceLayout', 'convertedLayout'):
            comparison = compare_layout(prior.get(label, prior['layout']), case[label])
            delta = comparison['maxWordDeltaPoints']
            if (not comparison['sameWords'] or not comparison['samePages'] or
                    delta is None or delta > 0.1):
                failures.append(name + ': ' + label)
    return failures


def probe(office, fixtures, output, case):
    name = case['name']
    source = fixtures / (name + '.doc')
    converted = fixtures / (name + '-converted.docx')
    before = {'source': digest(source), 'converted': digest(converted)}
    directory = output / name
    native = office_convert(office, source, directory / 'native', 'docx')
    source_layout = positions(office, source, directory / 'source-pdf')
    converted_layout = positions(office, converted, directory / 'converted-pdf')
    if before != {'source': digest(source), 'converted': digest(converted)}:
        raise ValueError('Native conversion modified an input')
    return {**case, 'sourceSha256': before['source'], 'convertedSha256': before['converted'],
            'nativeSha256': digest(native), 'native': properties(native), 'converted': properties(converted),
            'sourceLayout': source_layout, 'convertedLayout': converted_layout,
            'layoutComparison': compare_layout(source_layout, converted_layout)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--fixtures', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--only', action='append', default=[], help='Select an explicitly named case; report keeps the full inventory.')
    parser.add_argument('--golden', type=Path,
                        help='Optional reviewed measurements; never rewritten. Requires the full inventory.')
    args = parser.parse_args()
    if args.golden and args.only:
        parser.error('--golden requires the full fixture inventory')
    fixtures, output = args.fixtures.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    cases = json.loads((fixtures / 'manifest.json').read_text())
    inventory = [case['name'] for case in cases]
    if args.only:
        if not set(args.only) <= set(inventory):
            raise ValueError('Unknown preferred-width case')
        cases = [case for case in cases if case['name'] in args.only]
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda case: probe(args.office.resolve(), fixtures, output, case), cases))
    by_name = {case['name']: case for case in results}
    pairs = []
    for kind in ('nil', 'auto', 'percent', 'dxa', 'narrow', 'asymmetric'):
        if 'tc80-' + kind not in by_name or 'range-' + kind not in by_name:
            continue
        left, right = by_name['tc80-' + kind], by_name['range-' + kind]
        pairs.append({'kind': kind, 'nativeProjectionEqual': left['native'] == right['native'],
                      'nativeLayout': compare_layout(left['sourceLayout'], right['sourceLayout']),
                      'convertedProjectionEqual': left['converted'] == right['converted'],
                      'convertedLayout': compare_layout(left['convertedLayout'], right['convertedLayout'])})
    report = {'version': 1, 'office': command([str(args.office), '--version']).strip(),
              'scope': 'Native differential measurements; schema and full Word equivalence are separate checks.',
              'fixtureInventory': inventory, 'selectedCases': [case['name'] for case in cases],
              'cases': results, 'pairs': pairs}
    if args.golden:
        report['goldenFailures'] = compare_golden(results, json.loads(args.golden.read_text()))
    (output / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    for case in results:
        print(case['name'], case['layoutComparison'])
    for pair in pairs:
        print('PAIR', pair['kind'], pair['nativeProjectionEqual'], pair['nativeLayout'])
    if report.get('goldenFailures'):
        raise SystemExit('Table-width golden mismatch: ' + ', '.join(report['goldenFailures']))


if __name__ == '__main__':
    main()

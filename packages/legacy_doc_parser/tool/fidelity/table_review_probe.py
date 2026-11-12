#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compare projected row-review states with independently authored native DOC controls."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import copy
import io
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

from oracle import ROOT, REVISION_TAGS, digest
from run import command, render, render_comparison, write_json

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
RECEIPT = ROOT / 'test/fixtures/word_native/table-review-source-receipt.json'
EXPECTED = {
    'height': {'row': 0, 'rows': 2, 'previous': (240, 'atLeast', False, False),
               'current': (720, 'atLeast', True, False)},
    'split': {'row': 1, 'rows': 2, 'previous': (0, 'auto', False, False),
              'current': (0, 'auto', True, False)},
    'header': {'row': 0, 'rows': 4, 'previous': (240, 'atLeast', False, True),
               'current': (240, 'atLeast', False, False)},
}


def read_document(path):
    with zipfile.ZipFile(path) as package:
        return ET.fromstring(package.read('word/document.xml'))


def row_state(properties):
    def on(name):
        value = None if properties is None else properties.find(W + name)
        return value is not None and value.get(W + 'val', 'on') in ('on', '1', 'true')
    height = None if properties is None else properties.find(W + 'trHeight')
    return (0 if height is None else int(height.get(W + 'val', '0')),
            'auto' if height is None else height.get(W + 'hRule', 'auto'),
            on('cantSplit'), on('tblHeader'))


def verify_review(document, kind):
    """Enforce literal authored states even if a native renderer loses history."""
    expected = EXPECTED[kind]
    rows = document.findall('.//' + W + 'tr')
    changes = document.findall('.//' + W + 'trPrChange')
    if any(node.tag.startswith(W) and node.tag[len(W):] in REVISION_TAGS and
           node.tag != W + 'trPrChange' for node in document.iter()):
        raise ValueError('Fixture contains a revision outside bounded row properties')
    if len(rows) != expected['rows'] or len(changes) != 1:
        raise ValueError('Missing rows or native row-review snapshot')
    current = rows[expected['row']].find(W + 'trPr')
    change = None if current is None else current.find(W + 'trPrChange')
    if change is None or change is not changes[0]:
        raise ValueError('Revision is attached to the wrong table row')
    old = change.findall(W + 'trPr')
    if len(old) != 1 or len(change) != 1:
        raise ValueError('Row revision must contain one complete prior trPr')
    previous = old[0]
    for properties, name in ((current, 'current'), (previous, 'previous')):
        if row_state(properties) != expected[name]:
            raise ValueError(kind + ': incorrect ' + name + ' row properties')
        names = [child.tag for child in properties if child.tag != W + 'trPrChange']
        if len(names) != len(set(names)) or not set(names) <= {
                W + 'trHeight', W + 'cantSplit', W + 'tblHeader'}:
            raise ValueError('Unexpected or duplicate fixture row properties')
    if (change.get(W + 'author') != 'Alice' or
            change.get(W + 'date') != '2026-11-12T08:45:00' or
            not change.get(W + 'id', '').isdigit()):
        raise ValueError('Source review metadata changed')
    if kind == 'header' and row_state(rows[1].find(W + 'trPr'))[3]:
        raise ValueError('The native header control must not depend on a dormant second flag')
    return {'passed': True, 'row': expected['row'],
            'current': list(expected['current']), 'previous': list(expected['previous']),
            'nativeOutputUsedAsExpected': False}


def project_review(source, target, kind, *, reject):
    """Apply only this bounded fixture's row-property review to a new package."""
    if target.exists():
        raise ValueError('Projection output already exists')
    document = read_document(source)
    verify_review(document, kind)
    for row in document.findall('.//' + W + 'tr'):
        current = row.find(W + 'trPr')
        change = None if current is None else current.find(W + 'trPrChange')
        if change is None:
            continue
        if reject:
            previous = copy.deepcopy(change.find(W + 'trPr'))
            index = list(row).index(current)
            row.remove(current)
            row.insert(index, previous)
        else:
            current.remove(change)
    # ElementTree otherwise renames all prefixes without updating mc:Ignorable.
    # Bind every source prefix before serializing this one XML part.
    with zipfile.ZipFile(source) as original:
        bindings = []
        for event, value in ET.iterparse(io.BytesIO(original.read('word/document.xml')),
                                        events=('start-ns', 'start')):
            if event == 'start':
                break
            bindings.append(value)
        used = {name[1:].split('}', 1)[0] for node in document.iter()
                for name in [node.tag, *node.attrib] if name.startswith('{')}
        for prefix, uri in bindings:
            if prefix and not (prefix.startswith('ns') and prefix[2:].isdigit()):
                ET.register_namespace(prefix, uri)
            if prefix and uri not in used:
                document.set('xmlns:' + prefix, uri)
        xml = ET.tostring(document, encoding='utf-8', xml_declaration=True)
        with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_DEFLATED) as output:
            for item in original.infolist():
                output.writestr(item, xml if item.filename == 'word/document.xml'
                                else original.read(item.filename))


def verify_sources(fixtures):
    receipt = json.loads(RECEIPT.read_text())
    actual = {path.name: digest(path) for path in fixtures.glob('*.doc')}
    if actual != receipt['sources']:
        raise ValueError('Table-review DOC inputs differ from the reviewed source receipt')
    return actual


def check_render(comparison):
    return (comparison['referencePages'] > 0 and
            comparison['referencePages'] == comparison['actualPages'] and
            comparison['pageDimensionsMatch'] and comparison['pageTextMatches'] and
            comparison['maximumWordDriftPoints'] is not None and
            comparison['maximumWordDriftPoints'] <= 0.1)


def probe_case(office, fixtures, output, kind):
    folder = output / kind
    folder.mkdir()
    source = fixtures / f'table-review-{kind}-review.docx'
    result = {'kind': kind, 'reviewSha256': digest(source),
              'verification': verify_review(read_document(source), kind), 'states': {}}
    write_json(folder / 'report.json', result)
    controls = {}
    for state in ('accepted', 'rejected'):
        projected = folder / (state + '.docx')
        project_review(source, projected, kind, reject=state == 'rejected')
        control = fixtures / f'table-review-{kind}-{state}.doc'
        reference = render(office, control, folder / (state + '-control'), 96)
        actual = render(office, projected, folder / (state + '-projected'), 96)
        comparison = render_comparison(reference, actual)
        result['states'][state] = {
            'controlSourceSha256': digest(control), 'projectedSha256': digest(projected),
            'reference': reference, 'actual': actual, 'comparison': comparison,
            'geometryPassed': check_render(comparison),
        }
        controls[state] = reference
        write_json(folder / 'report.json', result)
    difference = render_comparison(controls['accepted'], controls['rejected'])
    result['controlsExerciseDifferentLayouts'] = not check_render(difference)
    result['passed'] = (result['controlsExerciseDifferentLayouts'] and
                        all(value['geometryPassed'] for value in result['states'].values()))
    write_json(folder / 'report.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    fixtures, output = args.fixtures.resolve(), args.output.resolve()
    sources = verify_sources(fixtures)
    output.mkdir(parents=True, exist_ok=False)
    report = {'schema': 'legacy-doc-parser/table-review-probe', 'version': 1,
              'renderer': command([args.office, '--version']).strip(),
              'sourceReceiptSha256': digest(RECEIPT), 'sources': sources,
              'method': 'Parser row history is projected independently into accepted/rejected '
                        'DOCX copies; native renders are compared with separately authored '
                        'accepted/rejected DOC inputs. Source review is never accepted in place.',
              'cases': []}
    write_json(output / 'report.json', report)
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(lambda kind: probe_case(args.office, fixtures, output, kind), EXPECTED):
            report['cases'].append(result)
            write_json(output / 'report.json', report)
    report['sourcesUnchanged'] = verify_sources(fixtures) == sources
    report['passed'] = report['sourcesUnchanged'] and all(case['passed'] for case in report['cases'])
    write_json(output / 'report.json', report)
    print(json.dumps({'passed': report['passed'], 'cases': [
        {'kind': case['kind'], 'passed': case['passed'],
         'rgbExact': {name: state['comparison']['rasterExactlyMatches']
                      for name, state in case['states'].items()}}
        for case in report['cases']]}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

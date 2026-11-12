#!/usr/bin/env python3
"""Independent raw ZIP/XML oracle for logical table scripts and native widths.

The source XML and expected JSON are authored fixtures. No Quds model or output
is used to generate expectations, and this command never rewrites a baseline.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}
Q = '{' + W + '}'
PHASES = ('format', 'replace', 'unmerge')


def equal(actual, expected, label):
    if actual != expected:
        raise AssertionError(f'{label}: expected {expected!r}, got {actual!r}')


def attr(node, name, default=None):
    return default if node is None else node.get(Q + name, default)


def text(node):
    return ''.join(part.text or '' for part in node.iter(Q + 't'))


def enabled(node):
    return node is not None and attr(node, 'val', '1') not in ('0', 'false', 'off')


def table_view(table):
    rows = [row.findall('w:tc', NS) for row in table.findall('w:tr', NS)]
    for cells in rows:
        for cell in cells:
            widths = cell.findall('w:tcPr/w:tcW', NS)
            equal(len(widths), 1, 'one preferred width per cell')
            properties = cell.find('w:tcPr', NS)
            names = [child.tag.removeprefix(Q) for child in properties]
            order = {'tcW': 0, 'gridSpan': 1, 'vMerge': 2, 'shd': 3}
            selected = [order[name] for name in names if name in order]
            equal(selected, sorted(set(selected)), 'unique schema-ordered cell properties')
    return {
        'text': [['|'.join(text(p) for p in cell.findall('w:p', NS))
                  for cell in row] for row in rows],
        'spans': [[int(attr(cell.find('w:tcPr/w:gridSpan', NS), 'val', '1'))
                   for cell in row] for row in rows],
        'merges': [[None if cell.find('w:tcPr/w:vMerge', NS) is None
                    else attr(cell.find('w:tcPr/w:vMerge', NS), 'val', 'continue')
                    for cell in row] for row in rows],
        'widths': [[[attr(cell.find('w:tcPr/w:tcW', NS), 'type', 'dxa'),
                     attr(cell.find('w:tcPr/w:tcW', NS), 'w')]
                    for cell in row] for row in rows],
        'fills': [[attr(cell.find('w:tcPr/w:shd', NS), 'fill')
                   for cell in row] for row in rows],
    }


def verify_parts(parts, phase):
    expected = json.loads((FIXTURES / 'table_grid_expected.json').read_text())[phase]
    root = ET.fromstring(parts['word/document.xml'])
    body = root.find('w:body', NS)
    if body is None:
        raise AssertionError('Missing Word body')
    equal([text(p) for p in body.findall('w:p', NS)],
          ['Before grid.', 'After grid.'], 'untouched body context')
    tables = body.findall('w:tbl', NS)
    equal(len(tables), 1, 'one outer table')
    outer = tables[0]
    nested = outer.findall('.//w:tbl', NS)
    equal(len(nested), 1, 'one retained nested table')
    nested = nested[0]
    for name, table, grid in [('outer', outer, ['1800'] * 3),
                              ('nested', nested, ['600'] * 3)]:
        equal([attr(col, 'w') for col in table.findall('w:tblGrid/w:gridCol', NS)],
              grid, name + ' logical grid')
        view = table_view(table)
        for key in ('text', 'spans', 'widths', 'fills'):
            equal(view[key], expected[name + '_' + key], name + ' ' + key)
        if name == 'outer':
            equal(view['merges'], expected['outer_merges'], 'vertical merge owners')
        else:
            equal(view['merges'], [[None] * len(view['spans'][0])], 'nested merge flags')
    starts = root.findall('.//w:bookmarkStart', NS)
    ends = root.findall('.//w:bookmarkEnd', NS)
    equal([(attr(b, 'id'), attr(b, 'name')) for b in starts],
          [('31', 'MergedOrigin')] if expected['bookmark'] else [], 'retained bookmark identity')
    equal([attr(b, 'id') for b in ends],
          ['31'] if expected['bookmark'] else [], 'paired bookmark endpoint')
    first = outer.find('w:tr/w:tc', NS)
    if expected['rich_origin']:
        paragraphs = first.findall('w:p', NS)
        runs = paragraphs[0].findall('w:r', NS)
        equal([text(run) for run in runs], ['Merged ', 'origin'], 'rich source run order')
        equal(enabled(runs[1].find('w:rPr/w:b', NS)), True, 'rich origin bold')
        equal(attr(runs[1].find('w:rPr/w:color', NS), 'val'), '112233', 'rich origin color')
        equal(enabled(paragraphs[1].find('w:r/w:rPr/w:i', NS)), True, 'rich second paragraph italic')
    nested_head = nested.find('w:tr/w:tc/w:p/w:r', NS)
    equal(enabled(nested_head.find('w:rPr/w:b', NS)), True, 'nested bold retained')
    nested_owner = outer.findall('w:tr', NS)[2].find('w:tc', NS)
    equal([child.tag.removeprefix(Q) for child in nested_owner],
          ['tcPr', 'tbl', 'p'], 'nested table remains in its actual owner')


def required_paths():
    return [('source.docx', 'source')] + [
        (f'expected-{phase}.docx', phase) for phase in PHASES] + [
        (f'{route}/{phase}-{cycle}.docx', 'source' if phase == 'unchanged' else phase)
        for route in ('direct', 'isolate')
        for phase in ('unchanged', *PHASES) for cycle in (1, 2, 3)]


def verify_directory(directory):
    entries = required_paths()
    equal({p.relative_to(directory).as_posix() for p in directory.rglob('*.docx')},
          {path for path, _ in entries}, 'complete table grid export inventory')
    receipts = []
    for name, phase in entries:
        path = directory / name
        with ZipFile(path) as archive:
            equal(archive.testzip(), None, 'ZIP integrity')
            verify_parts({n: archive.read(n) for n in archive.namelist()}, phase)
        receipts.append({'path': name, 'phase': phase,
                         'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return receipts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT / 'build/fidelity-table-grid')
    args = parser.parse_args()
    receipts = verify_directory(args.directory)
    report = args.directory / 'oracle-report.json'
    report.write_text(json.dumps({'checked': len(receipts), 'files': receipts}, indent=2) + '\n')
    print(f'Table grid oracle: {len(receipts)} packages passed.')


if __name__ == '__main__':
    main()

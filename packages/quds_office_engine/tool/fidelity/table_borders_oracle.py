#!/usr/bin/env python3
"""Independent ZIP/XML oracle for absent, inherited and edited table borders.

The fixture and expected values are authored directly as OOXML/JSON. This gate
checks direct formatting as well as effective borders, so flattening inherited
formatting cannot pass simply because the current rendering looks the same.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}
EDGES = ('top', 'left', 'bottom', 'right', 'insideH', 'insideV')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def attribute(element, name):
    return None if element is None else element.get('{' + W + '}' + name)


def inspect_borders(properties):
    nodes = properties.findall('w:tblBorders', NS)
    require(len(nodes) <= 1, 'Duplicate direct table border properties')
    if not nodes:
        return None
    children = list(nodes[0])
    require([child.tag for child in children] == ['{' + W + '}' + edge for edge in EDGES],
            'The six authored table borders are incomplete or reordered')
    borders = []
    for child in children:
        size = attribute(child, 'sz')
        require(attribute(child, 'space') in (None, '0'), 'Unexpected border spacing')
        borders.append({'value': attribute(child, 'val'), 'color': attribute(child, 'color'),
                        'size': None if size is None else int(size)})
    require(all(border == borders[0] for border in borders), 'Table edges have inconsistent borders')
    return borders[0]


def verify_file(path, expected, mode):
    require(mode in ('imported', 'edited'), 'Unknown table oracle mode')
    with ZipFile(path) as package:
        names = package.namelist()
        require(len(names) == len(set(names)), 'Duplicate ZIP members')
        roots = {part: ET.fromstring(package.read(part)) for part in
                 ('word/document.xml', 'word/styles.xml', 'word/footnotes.xml')}
        styles = roots['word/styles.xml'].findall('w:style', NS)
        matched = [style for style in styles if attribute(style, 'styleId') == expected['style']['id']]
        require(len(matched) == 1, 'Missing or duplicate inherited table style')
        require(attribute(matched[0], 'type') == 'table', 'Table style changed type')
        style_properties = matched[0].find('w:tblPr', NS)
        require(style_properties is not None, 'Inherited style lost table properties')
        style_border = inspect_borders(style_properties)
        require(style_border == expected['style']['border'], 'Inherited style border changed')

        tables = {}
        for part in ('word/document.xml', 'word/footnotes.xml'):
            for table in roots[part].iter('{' + W + '}tbl'):
                text = ''.join(node.text or '' for node in table.iter('{' + W + '}t'))
                require((part, text) not in tables, 'Duplicate authored table')
                tables[part, text] = table
        require(set(tables) == {(row['part'], row['text']) for row in expected['tables']},
                'Authored body/note table inventory changed')

        for row in expected['tables']:
            label = row['text']
            table = tables[row['part'], label]
            require(len(table.findall('w:tr', NS)) == 1 and
                    len(table.findall('w:tr/w:tc', NS)) == 1, f'{label}: table shape changed')
            properties = table.findall('w:tblPr', NS)
            require(len(properties) == 1, f'{label}: missing or duplicate table properties')
            properties = properties[0]
            style = attribute(properties.find('w:tblStyle', NS), 'val')
            require(style == row['style'], f'{label}: inherited style reference changed')
            width = properties.find('w:tblW', NS)
            require(attribute(width, 'type') == 'dxa' and attribute(width, 'w') == str(row['width']),
                    f'{label}: authored table width changed')
            require(attribute(properties.find('w:tblLayout', NS), 'type') == row['layout'],
                    f'{label}: authored table layout changed')
            margin = properties.find('w:tblCellMar/w:top', NS)
            require(attribute(margin, 'w') == (None if row['top_margin'] is None else str(row['top_margin'])),
                    f'{label}: authored top cell margin changed')
            if row['top_margin'] is not None:
                require(attribute(margin, 'type') == 'dxa', f'{label}: cell margin unit changed')
            require(attribute(properties.find('w:tblCaption', NS), 'val') == row['caption'],
                    f'{label}: authored caption changed')
            direct = inspect_borders(properties)
            require(direct == row[mode], f'{label}: direct {mode} border changed: {direct!r}')
            effective = direct if direct is not None else (style_border if style else None)
            expected_effective = row[mode] if row[mode] is not None else (
                expected['style']['border'] if row['style'] else None)
            require(effective == expected_effective, f'{label}: effective borders changed')
            required = ['tblStyle'] if row['style'] else []
            required += ['tblW']
            if row[mode] is not None:
                required += ['tblBorders']
            if row['layout'] is not None:
                required += ['tblLayout']
            if row['top_margin'] is not None:
                required += ['tblCellMar']
            if row['caption'] is not None:
                required += ['tblCaption']
            require([node.tag for node in properties] == ['{' + W + '}' + name for name in required],
                    f'{label}: sparse direct properties were added, removed or reordered')


def verify_corpus(directory, expected):
    required = {f'tables-{mode}-{cycle}.docx' for mode in ('imported', 'edited') for cycle in (1, 2, 3)}
    actual = {path.name for path in directory.glob('*.docx')}
    require(actual == required,
            f'Table corpus inventory: missing={sorted(required - actual)}, extra={sorted(actual - required)}')
    for mode in ('imported', 'edited'):
        for cycle in (1, 2, 3):
            verify_file(directory / f'tables-{mode}-{cycle}.docx', expected, mode)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=ROOT / 'build/fidelity-table-borders')
    args = parser.parse_args(argv)
    expected = json.loads((FIXTURES / 'table_borders_expected.json').read_text())
    verify_file(FIXTURES / 'table-borders.docx', expected, 'imported')
    verify_corpus(args.directory, expected)
    print('Table border oracle: authored source and all 6 import/edit cycle exports passed')


if __name__ == '__main__':
    main()

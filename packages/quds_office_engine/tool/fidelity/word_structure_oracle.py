#!/usr/bin/env python3
"""Independent ZIP/XML oracle for the create/edit/remove structural scripts.

Expected values are authored in word_structure_expected.json. This never calls
the Dart model, rewrites fixtures, or accepts new expected output automatically.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import posixpath
import re
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'
NS = {
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'pr': 'http://schemas.openxmlformats.org/package/2006/relationships',
    'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
    'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
    'pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture',
    'wps': 'http://schemas.microsoft.com/office/word/2010/wordprocessingShape',
    'w14': 'http://schemas.microsoft.com/office/word/2010/wordml',
    'w15': 'http://schemas.microsoft.com/office/word/2012/wordml',
}


def attr(node, name, default=None, prefix='w'):
    return default if node is None else node.get('{' + NS[prefix] + '}' + name, default)


def equal(actual, expected, label):
    if actual != expected:
        raise AssertionError(f'{label}: expected {expected!r}, got {actual!r}')


def required(node, path):
    result = node.find(path, NS)
    if result is None:
        raise AssertionError(f'Missing {path}')
    return result


def text(node):
    return ''.join(element.text or '' for element in node.iter('{' + NS['w'] + '}t'))


def verify_parts(parts, phase, expected=None):
    expected = expected or json.loads((FIXTURES / 'word_structure_expected.json').read_text())
    want = expected[phase]
    document = ET.fromstring(parts['word/document.xml'])
    body = required(document, 'w:body')
    paragraphs = body.findall('w:p', NS)
    equal([text(p) for p in paragraphs[:5]], expected['body'], 'original body and reference result')
    source = paragraphs[1]
    equal(attr(required(source, 'w:bookmarkStart'), 'name'), expected['bookmark'], 'bookmark target')
    equal(len(source.findall('w:bookmarkStart', NS)), 1, 'bookmark start count')
    equal(attr(required(source, 'w:bookmarkStart'), 'id'), attr(required(source, 'w:bookmarkEnd'), 'id'), 'bookmark endpoints')
    instructions = [''.join(node.itertext()).strip() for node in paragraphs[2].findall('.//w:instrText', NS)]
    instructions += [attr(node, 'instr').strip() for node in paragraphs[2].findall('.//w:fldSimple', NS)]
    equal(instructions, [expected['reference_instruction']], 'reference field instruction')

    properties = required(source, 'w:pPr')
    spacing = required(properties, 'w:spacing')
    indent = required(properties, 'w:ind')
    para = want['paragraph']
    for name in ('before', 'after'):
        equal(attr(spacing, name), para[name], f'explicit paragraph spacing/{name}')
    equal(attr(spacing, 'line'), '300', 'retained line spacing')
    for name in ('left', 'right', 'firstLine'):
        equal(attr(indent, name, '0'), para[name], f'paragraph indent/{name}')
    equal([[attr(t, 'pos'), attr(t, 'val'), attr(t, 'leader', 'none')]
           for t in properties.findall('w:tabs/w:tab', NS)], para['tabs'], 'tab positions and metadata')
    breaks = source.findall('.//w:br', NS)
    equal([attr(b, 'type') for b in breaks], ['column'] if para['column_break'] else [], 'column break add/remove')
    equal(attr(properties.find('w:framePr', NS), 'lines'), '2' if phase == 'edit' else None, 'drop cap')
    equal(attr(properties.find('w:shd', NS), 'fill'), 'FFF000' if phase == 'edit' else None, 'paragraph shading')
    borders = properties.findall('w:pBdr/*', NS)
    equal([attr(b, 'color') for b in borders], ['FF0000'] * 4 if phase == 'edit' else [], 'paragraph border add/remove')

    comment_root = ET.fromstring(parts['word/comments.xml']) if 'word/comments.xml' in parts else ET.Element('none')
    comments = comment_root.findall('w:comment', NS)
    equal([text(c) for c in comments], want['comments'], 'comment text and thread deletion')
    equal([attr(c, 'id') for c in comments], ['0', '1'] if comments else [], 'stable comment ids')
    anchored = []
    active = False
    for node in source:
        if node.tag == '{' + NS['w'] + '}commentRangeStart':
            equal(attr(node, 'id'), '0', 'comment anchor id')
            active = True
        elif node.tag == '{' + NS['w'] + '}commentRangeEnd':
            equal(attr(node, 'id'), '0', 'comment end id')
            active = False
        elif active:
            anchored.append(text(node))
    equal(''.join(anchored), expected['comment_anchor'] if comments else '', 'precise comment anchor')
    equal(len(source.findall('.//w:commentReference', NS)), 1 if comments else 0, 'comment reference count')
    if comments:
        equal([attr(c, 'author') for c in comments], ['Reviewer', 'Author'], 'comment authors')
        equal([attr(c, 'initials') for c in comments], ['RV', 'AU'], 'comment initials')
        ids = [attr(c.findall('w:p', NS)[-1], 'paraId', prefix='w14') for c in comments]
        equal(len(set(ids)), 2, 'unique comment paragraph ids')
        extensions = ET.fromstring(parts['word/commentsExtended.xml']).findall('w15:commentEx', NS)
        by_id = {attr(e, 'paraId', prefix='w15'): e for e in extensions}
        equal(set(by_id), set(ids), 'native comment metadata joins')
        equal(attr(by_id[ids[1]], 'paraIdParent', prefix='w15'), ids[0], 'reply parent')
        equal(attr(by_id[ids[0]], 'done', '0', prefix='w15'), '1' if want['resolved'] else '0', 'resolved comment')
        if phase == 'edit':
            equal(attr(required(comments[0], './/w:rPr/w:b'), 'val', '1'), '1', 'rich comment formatting')

    tables = body.findall('w:tbl', NS)
    equal(len(tables), 1, 'table count')
    table = tables[0]
    rows = table.findall('w:tr', NS)
    equal([[text(c) for c in row.findall('w:tc', NS)] for row in rows], want['table_cells'], 'table cell content')
    equal([[int(attr(c.find('w:tcPr/w:gridSpan', NS), 'val', '1')) for c in row.findall('w:tc', NS)] for row in rows], want['spans'], 'table merge spans')
    equal([attr(c, 'w') for c in table.findall('w:tblGrid/w:gridCol', NS)], ['2400', '2400'], 'table grid width')
    equal(attr(required(table, 'w:tblPr/w:jc'), 'val'), 'center', 'table alignment')
    equal(attr(required(table, 'w:tblPr/w:bidiVisual'), 'val', '1'), '1', 'table text direction')
    grid_borders = table.findall('w:tblPr/w:tblBorders/*', NS)
    equal([(attr(b, 'color'), attr(b, 'sz')) for b in grid_borders], [('224466', '12')] * 6, 'table borders')
    equal(attr(required(rows[0], 'w:trPr/w:trHeight'), 'val'), '480', 'row height')
    required(rows[0], 'w:trPr/w:cantSplit')
    equal(attr(required(rows[1].findall('w:tc', NS)[1], 'w:tcPr/w:shd'), 'fill'), 'FFEEDD', 'retained cell shading')

    toc_titles, toc_entries, toc_instructions = [], [], []
    for p in paragraphs:
        style = attr(p.find('w:pPr/w:pStyle', NS), 'val', '')
        if style == 'TOCHeading':
            toc_titles.append(text(p))
        elif re.fullmatch(r'TOC[1-9]', style):
            runs = p.findall('.//w:t', NS)
            entry = ''.join(t.text or '' for t in runs)
            has_page = bool(p.findall('.//w:tab', NS))
            equal(has_page, want['page_numbers'], 'TOC cached page numbers')
            if has_page:
                equal(runs[-1].text, '1', 'authored TOC page result')
                entry = entry[:-1]
            toc_entries.append(entry)
        for node in p.findall('.//w:instrText', NS):
            instruction = ''.join(node.itertext()).strip()
            if instruction.startswith('TOC '):
                toc_instructions.append(instruction)
    equal(toc_titles, [want['toc_title']] if want['toc_title'] else [], 'TOC title/deletion')
    equal(toc_entries, want['toc_entries'], 'TOC heading selection')
    equal(len(toc_instructions), 1 if want['toc_title'] else 0, 'TOC field count')
    if toc_instructions:
        if f'\\o "{want["toc_range"]}"' not in toc_instructions[0]:
            raise AssertionError('Wrong TOC field heading range')
        equal(bool(re.search(r'\\n(?:\s|$)', toc_instructions[0])), not want['page_numbers'], 'native TOC page suppression switch')

    anchors = document.findall('.//wp:anchor', NS)
    frames = [a for a in anchors if a.find('.//wps:wsp', NS) is not None]
    pictures = [a for a in anchors if a.find('.//pic:pic', NS) is not None]
    equal(len(frames), 1 if want['frame'] else 0, 'drawing removal')
    equal(len(pictures), 1 if want['picture'] else 0, 'picture removal')
    if frames:
        frame, target = frames[0], want['frame']
        for axis, field in [('H', 'x'), ('V', 'y')]:
            position = required(frame, f'wp:position{axis}')
            equal(position.get('relativeFrom'), target['anchor'], 'drawing coordinate anchor')
            equal(int(required(position, 'wp:posOffset').text), round(target[field] * 12700), f'drawing {field}')
        extent = required(frame, 'wp:extent')
        equal([int(extent.get('cx')), int(extent.get('cy'))], [round(target[k] * 12700) for k in ('width', 'height')], 'drawing size')
        required(frame, 'wp:wrapSquare' if target['wrap'] == 'square' else 'wp:wrapNone')
        shape = required(frame, './/wps:spPr')
        fill = shape.find('a:solidFill/a:srgbClr', NS)
        stroke = shape.find('a:ln/a:solidFill/a:srgbClr', NS)
        equal(fill.get('val') if fill is not None else None, target['fill'], 'drawing fill')
        equal(stroke.get('val') if stroke is not None else None, target['stroke'], 'drawing stroke')
        equal(text(required(frame, './/w:txbxContent')), 'Placed text', 'drawing text')
    if pictures:
        picture, target = pictures[0], want['picture']
        equal([int(picture.get(a, '0')) for a in ('distT', 'distB', 'distL', 'distR')], target['distances'], 'picture wrap distances')
        equal(picture.get('behindDoc'), '1' if target['wrap'] == 'behind' else '0', 'picture stacking')
        required(picture, 'wp:wrapNone' if target['wrap'] == 'behind' else 'wp:wrapSquare')
        equal(int(required(picture, './/pic:spPr/a:xfrm').get('rot', '0')), target['rotation'], 'picture rotation')
        equal(required(picture, 'wp:docPr').get('title'), 'Accessible picture', 'picture alternative title')
        equal(required(picture, 'wp:docPr').get('descr'), 'Two color test picture', 'picture alternative description')
        rid = attr(required(picture, './/a:blip'), 'embed', prefix='r')
        rels = ET.fromstring(parts['word/_rels/document.xml.rels'])
        matches = [r for r in rels if r.get('Id') == rid]
        equal(len(matches), 1, 'picture relationship ownership')
        relationship = matches[0]
        equal(relationship.get('TargetMode', 'Internal'), 'Internal', 'picture internal target')
        media = posixpath.normpath(posixpath.join('word', relationship.get('Target'))).lstrip('/')
        if media not in parts:
            raise AssertionError('Picture relationship target is absent')
        equal(hashlib.sha256(parts[media]).hexdigest(), hashlib.sha256((FIXTURES/'scripts/replacement.png').read_bytes()).hexdigest(), 'picture payload')


def verify_file(path, phase):
    with ZipFile(path) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    verify_parts(parts, phase)


def verify(root):
    paths = []
    for phase in ('create', 'edit', 'remove'):
        for filename in ('edited.docx', 'roundtrip-1.docx', 'roundtrip-2.docx', 'roundtrip-3.docx'):
            path = root / phase / filename
            if not path.is_file():
                raise AssertionError(f'Missing structural scenario output: {path}')
            verify_file(path, phase)
            paths.append(str(path))
    return {'schema_version': 1, 'files_verified': len(paths), 'files': paths,
            'oracle': 'Authored JSON expectations compared to native ZIP/XML and original media bytes.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=ROOT/'build/fidelity-structure')
    args = parser.parse_args()
    result = verify(args.root)
    (args.root/'oracle-report.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f"Verified {result['files_verified']} structural exports against authored expectations.")

#!/usr/bin/env python3
"""Verify exact native bookmark endpoints against authored XML and edit intent.

The XML fixture and JSON expectations are hand-authored. This oracle parses
native OOXML independently of the Dart model and never updates either fixture.
It checks endpoint order, raw IDs, all native attributes, UTF-16 positions,
selected text, source absence, cross-paragraph/overlapping ranges and REF caches.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
MC = 'http://schemas.openxmlformats.org/markup-compatibility/2006'
NS = {'w': W, 'r': R}


def equal(actual, expected, label):
    if actual != expected:
        raise AssertionError(f'{label}: expected {expected!r}, got {actual!r}')


def attr(node, name):
    return node.get('{'+W+'}'+name)


def utf16(text):
    return len(text.encode('utf-16-le')) // 2


def character(node):
    local = node.tag.removeprefix('{'+W+'}')
    if local == 't':
        return node.text or ''
    if local == 'tab':
        return '\t'
    if local in ('br', 'cr'):
        return '\n'
    return ''


def structure(node):
    tags = {'p', 'tbl', 'tr', 'tc'}
    return [[child.tag.rsplit('}', 1)[-1], structure(child)]
            for child in node
            if child.tag.startswith('{'+W+'}') and child.tag.rsplit('}', 1)[-1] in tags]


def native_fields(paragraph, index):
    fields, stack = [], []
    def visit(node):
        if node.tag == '{'+W+'}fldSimple':
            value = ''.join(character(child) for child in node.iter())
            fields.append({'paragraph': index,
                           'instruction': ' '.join((attr(node, 'instr') or '').split()),
                           'text': value})
            for field in stack:
                if field['separated']:
                    field['text'] += value
            return
        if node.tag == '{'+W+'}fldChar':
            kind = attr(node, 'fldCharType')
            if kind == 'begin':
                stack.append({'paragraph': index, 'instruction': '', 'text': '', 'separated': False})
            elif kind == 'separate':
                if not stack or stack[-1]['separated']:
                    raise AssertionError('Invalid native field separator')
                stack[-1]['separated'] = True
            elif kind == 'end':
                if not stack or not stack[-1]['separated']:
                    raise AssertionError('Unpaired or unseparated native field')
                field = stack.pop()
                field.pop('separated')
                field['instruction'] = ' '.join(field['instruction'].split())
                fields.append(field)
        elif node.tag == '{'+W+'}instrText':
            if not stack or stack[-1]['separated']:
                raise AssertionError('Orphan native field instruction')
            stack[-1]['instruction'] += node.text or ''
        else:
            for field in stack:
                if field['separated']:
                    field['text'] += character(node)
        for child in node:
            visit(child)
    visit(paragraph)
    if stack:
        raise AssertionError('Unclosed native field')
    return fields


def snapshot(root):
    paragraphs, endpoints, ranges, fields = [], [], {}, []
    open_ranges, ids, names = {}, set(), set()
    for paragraph_index, p in enumerate(root.findall('.//w:p', NS)):
        if paragraph_index:
            for bookmark in open_ranges.values():
                bookmark['text'] += '\n'
        chunks, offset = [], 0
        for node in p.iter():
            if node.tag in ('{'+W+'}bookmarkStart', '{'+W+'}bookmarkEnd'):
                start = node.tag.endswith('bookmarkStart')
                raw_id = attr(node, 'id')
                if raw_id is None:
                    raise AssertionError('Native bookmark endpoint has no ID')
                canonical_id = str(int(raw_id))
                point = [paragraph_index, offset]
                endpoints.append({'kind': 'start' if start else 'end',
                                  'point': point, 'attributes': dict(node.attrib)})
                if start:
                    name = attr(node, 'name')
                    if not name or name in names or canonical_id in ids:
                        raise AssertionError('Duplicate or missing native bookmark name/ID')
                    names.add(name)
                    ids.add(canonical_id)
                    open_ranges[canonical_id] = {'name': name, 'id': raw_id,
                                                 'start': point, 'text': ''}
                else:
                    if canonical_id not in open_ranges:
                        raise AssertionError('Unpaired native bookmark end')
                    bookmark = open_ranges.pop(canonical_id)
                    name = bookmark.pop('name')
                    bookmark['end'] = point
                    ranges[name] = bookmark
            value = character(node)
            chunks.append(value)
            offset += utf16(value)
            for bookmark in open_ranges.values():
                bookmark['text'] += value
        paragraphs.append(''.join(chunks))
        fields.extend(native_fields(p, paragraph_index))
    if open_ranges:
        raise AssertionError('Unpaired native bookmark start')
    body = root.find('w:body', NS)
    if body is None:
        raise AssertionError('Missing native document body')
    return {'paragraphs': paragraphs, 'endpoints': endpoints, 'ranges': ranges,
            'fields': fields, 'structure': structure(body)}


def authored_expected(phase):
    source = snapshot(ET.fromstring((FIXTURES/'bookmark_ranges.xml').read_bytes()))
    specification = json.loads((FIXTURES/'bookmark_ranges_expected.json').read_text())
    equal(source['ranges'], specification['source_ranges'], 'authored source range intent')
    if phase != 'edited':
        return source
    expected = copy.deepcopy(source)
    expected['ranges'] = specification['edited_ranges']
    expected['paragraphs'].insert(3, 'paragraph start')
    for index, text in specification['edited_paragraphs'].items():
        expected['paragraphs'][int(index)] = text
    expected['paragraphs'].append('New generated target')
    by_id = {item['id']: item for item in expected['ranges'].values()}
    for endpoint in expected['endpoints']:
        endpoint['point'] = by_id[endpoint['attributes']['{'+W+'}id']][endpoint['kind']]
    for kind in ('start', 'end'):
        expected['endpoints'].append({'kind': kind,
            'point': expected['ranges']['Generated'][kind],
            'attributes': {'{'+W+'}id': '2', **({'{'+W+'}name': 'Generated'} if kind == 'start' else {})}})
    for name in specification['reference_names']:
        text = expected['ranges'][name]['text']
        expected['fields'].append({'paragraph': len(expected['paragraphs']),
                                   'instruction': f'REF {name}', 'text': text})
        expected['paragraphs'].append(text)
    expected['structure'].insert(3, ['p', []])
    expected['structure'].extend([['p', []] for _ in range(1 + len(specification['reference_names']))])
    return expected


def verify_parts(parts, phase):
    if phase not in ('source', 'imported', 'cloned', 'edited'):
        raise AssertionError(f'Unknown bookmark phase: {phase}')
    root = ET.fromstring(parts['word/document.xml'])
    equal(snapshot(root), authored_expected(phase), f'{phase} exact native bookmarks and text')
    rels = ET.fromstring(parts['word/_rels/document.xml.rels'])
    relationship_by_id = {rel.get('Id'): rel for rel in rels}
    links = []
    for link in root.findall('.//w:hyperlink', NS):
        relationship = relationship_by_id.get(link.get('{'+R+'}id'))
        if relationship is None:
            raise AssertionError('Unresolved bookmark-adjacent hyperlink')
        links.append({'type': relationship.get('Type'),
                      'target': relationship.get('Target'),
                      'mode': relationship.get('TargetMode'),
                      'text': ''.join(character(node) for node in link.iter())})
    equal(links, [{'type': R+'/hyperlink', 'target': 'https://example.org/bookmark-target',
                   'mode': 'External', 'text': 'linked'}], 'hyperlink range and ownership')


def active_markup(node):
    """Resolve the authored/produced WPS alternative once, without double text."""
    result = ET.Element(node.tag, node.attrib)
    result.text, result.tail = node.text, node.tail
    for child in node:
        if child.tag == '{'+MC+'}AlternateContent':
            choice = child.find('{'+MC+'}Choice')
            if choice is None:
                choice = child.find('{'+MC+'}Fallback')
            if choice is None:
                raise AssertionError('Empty drawing markup compatibility container')
            for selected in choice:
                result.append(active_markup(selected))
        else:
            result.append(active_markup(child))
    return result


def frame_stories(root):
    root = active_markup(root)
    boxes = root.findall('.//w:txbxContent', NS)
    equal(len(boxes), 1, 'exactly one textbox story')
    textbox = ET.Element('{'+W+'}document')
    content = ET.SubElement(textbox, '{'+W+'}body')
    for child in boxes[0]:
        content.append(copy.deepcopy(child))
    # The empty anchor paragraph still belongs to the body; only textbox
    # paragraphs are excluded from the surrounding body range.
    boxes[0].clear()
    return {'body': snapshot(root), 'textbox': snapshot(textbox)}


def verify_frame_parts(parts, source=False):
    expected = frame_stories(ET.fromstring((FIXTURES/'bookmark_frame_stories.xml').read_bytes()))
    equal(expected['body']['ranges']['BodyAroundFrame']['text'],
          'Body before\n\nBody after', 'authored body paragraph separators')
    equal(expected['textbox']['ranges']['TextBox']['text'],
          'Textbox content', 'authored separate textbox range')
    if not source:
        for name, story in [('BodyAroundFrame', 'body'), ('TextBox', 'textbox')]:
            text = expected[story]['ranges'][name]['text']
            expected['body']['fields'].append({'paragraph': len(expected['body']['paragraphs']),
                                               'instruction': f'REF {name}', 'text': text})
            expected['body']['paragraphs'].append(text)
            expected['body']['structure'].append(['p', []])
    actual = frame_stories(ET.fromstring(parts['word/document.xml']))
    equal(actual, expected, 'body/textbox endpoint ownership and REF caches')


def read_parts(path):
    with ZipFile(path) as package:
        names = package.namelist()
        equal(len(names), len(set(names)), 'unique ZIP entries')
        return {name: package.read(name) for name in names}


def verify(root):
    expected = {'source.docx': 'source',
                **{f'{phase}-{cycle}.docx': phase for phase in ('imported', 'cloned', 'edited')
                   for cycle in range(1, 4)},
                'frame-source.docx': 'frame-source',
                **{f'frame-{cycle}.docx': 'frame' for cycle in range(1, 4)}}
    equal({path.name for path in root.glob('*.docx')}, set(expected), 'complete bookmark evidence inventory')
    for filename, phase in expected.items():
        if phase.startswith('frame'):
            verify_frame_parts(read_parts(root/filename), source=phase == 'frame-source')
        else:
            verify_parts(read_parts(root/filename), phase)
    return {'schema_version': 1, 'files_verified': len(expected), 'files': list(expected),
            'source_bookmark_ranges': 11, 'edited_bookmark_ranges': 12, 'edited_ref_fields': 12,
            'separate_frame_stories': 2,
            'oracle': 'Authored XML and explicit edit intent; exact native endpoint order/metadata, UTF-16 locations, marked text, REF caches and hyperlink ownership.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=ROOT/'build/fidelity-bookmarks')
    args = parser.parse_args()
    result = verify(args.root)
    (args.root/'oracle-report.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f"Verified {result['files_verified']} bookmark packages against authored endpoints.")

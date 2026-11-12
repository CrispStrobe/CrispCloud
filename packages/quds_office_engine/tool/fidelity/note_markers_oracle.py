#!/usr/bin/env python3
"""Check note-marker position, absence and rPr against authored source XML.

The source fixtures are hand-authored OOXML, never a serializer baseline.
Edited paragraph text is specified separately in note_markers_expected.json.
No command in this module updates either source or expected values.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import posixpath
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS = {'w': W}
SEPARATOR_TYPES = {'separator', 'continuationSeparator', 'continuationNotice'}


def equal(actual, expected, label):
    if actual != expected:
        raise AssertionError(f'{label}: expected {expected!r}, got {actual!r}')


def attr(node, name):
    return node.get('{'+W+'}'+name)


def properties(node):
    if node is None:
        return None
    return [node.tag, sorted(node.attrib.items()),
            [properties(child) for child in node]]


def structure(node):
    tags = {'p', 'tbl', 'tr', 'tc'}
    return [[child.tag.rsplit('}', 1)[-1], structure(child)]
            for child in node
            if child.tag.startswith('{'+W+'}') and child.tag.rsplit('}', 1)[-1] in tags]


def paragraph_snapshot(paragraph):
    chunks, markers = [], []
    offset = 0
    for run in paragraph.findall('.//w:r', NS):
        rpr = run.find('w:rPr', NS)
        for child in run:
            local = child.tag.removeprefix('{'+W+'}')
            if local in ('footnoteRef', 'endnoteRef'):
                markers.append({'kind': local, 'offset': offset, 'properties': properties(rpr)})
                continue
            if local == 't':
                value = child.text or ''
            elif local == 'tab':
                value = '\t'
            elif local in ('br', 'cr'):
                value = '\n'
            else:
                continue
            chunks.append(value)
            offset += len(value.encode('utf-16-le')) // 2
    return {'text': ''.join(chunks), 'markers': markers}


def snapshot(root, kind):
    result = {}
    ids = []
    for note in root.findall('w:'+kind, NS):
        if attr(note, 'type') in SEPARATOR_TYPES:
            continue
        note_id = attr(note, 'id')
        ids.append(note_id)
        result[note_id] = {'structure': structure(note),
                           'paragraphs': [paragraph_snapshot(p) for p in note.findall('.//w:p', NS)]}
    equal(len(set(ids)), len(ids), f'{kind} ids are unique')
    return result


def separator_definitions(root, kind):
    return [properties(note) for note in root.findall('w:'+kind, NS)
            if attr(note, 'type') in SEPARATOR_TYPES]


def authored_expected(kind, phase):
    expected = snapshot(ET.fromstring((FIXTURES/f'note_markers_{kind}s.xml').read_bytes()), kind)
    specification = json.loads((FIXTURES/'note_markers_expected.json').read_text())
    equal(sorted(map(int, expected)), specification['note_ids'], f'authored {kind} cases')
    for note_id, note in expected.items():
        positions = {str(index): [marker['offset'] for marker in p['markers']]
                     for index, p in enumerate(note['paragraphs']) if p['markers']}
        equal(positions, specification['marker_offsets'][note_id], f'authored {kind} {note_id} positions')
    if phase == 'edited':
        for note_id, edits in specification['edited_paragraphs'].items():
            for paragraph, text in edits.items():
                expected[note_id]['paragraphs'][int(paragraph)]['text'] = text
    return expected


def verify_parts(parts, phase):
    if phase not in ('source', 'imported', 'cloned', 'edited'):
        raise AssertionError(f'Unknown note-marker phase: {phase}')
    main = ET.fromstring(parts['word/document.xml'])
    rels = ET.fromstring(parts['word/_rels/document.xml.rels'])
    for kind in ('footnote', 'endnote'):
        matches = [rel for rel in rels if rel.get('Type') == R+'/'+kind+'s']
        equal(len(matches), 1, f'{kind} relationship ownership')
        equal(matches[0].get('TargetMode', 'Internal'), 'Internal', f'{kind} internal part')
        target = posixpath.normpath(posixpath.join('word', matches[0].get('Target'))).lstrip('/')
        if target not in parts:
            raise AssertionError(f'Missing {kind} part: {target}')
        expected = authored_expected(kind, phase)
        native = ET.fromstring(parts[target])
        authored = ET.fromstring((FIXTURES/f'note_markers_{kind}s.xml').read_bytes())
        equal(separator_definitions(native, kind), separator_definitions(authored, kind),
              f'{phase} {kind} native separator definitions')
        actual = snapshot(native, kind)
        equal(actual, expected, f'{phase} {kind} content and marker placement')
        references = [attr(node, 'id') for node in main.findall('.//w:'+kind+'Reference', NS)]
        equal(references, list(expected), f'{kind} body-reference ids')


def read_parts(path):
    with ZipFile(path) as package:
        names = package.namelist()
        equal(len(set(names)), len(names), 'unique ZIP entries')
        return {name: package.read(name) for name in names}


def verify(root):
    expected = {'source.docx': 'source',
                **{f'{phase}-{cycle}.docx': phase for phase in ('imported', 'cloned', 'edited')
                   for cycle in range(1, 4)}}
    equal({path.name for path in root.glob('*.docx')}, set(expected), 'complete note-marker evidence inventory')
    for filename, phase in expected.items():
        verify_parts(read_parts(root/filename), phase)
    return {'schema_version': 1, 'files_verified': len(expected),
            'files': list(expected), 'cases_per_story': 6,
            'oracle': 'Authored source XML plus explicit edited-text expectations; marker kind, UTF-16 offset, block location and run properties.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=ROOT/'build/fidelity-note-markers')
    args = parser.parse_args()
    result = verify(args.root)
    (args.root/'oracle-report.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f"Verified {result['files_verified']} note-marker packages against authored XML.")

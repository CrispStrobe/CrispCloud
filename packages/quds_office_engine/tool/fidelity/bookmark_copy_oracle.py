#!/usr/bin/env python3
"""Independent native XML oracle for complete bookmark insertion copies.

Expected text, UTF-16 positions and allocated IDs/names are authored separately
from the Dart producer. The native reference clones the two authored XML
paragraphs and changes only the specified marker identities. Field and link
targets intentionally continue to refer to the original bookmark.

Engine and editor modes have independent inventories so either producer can
finish first. No oracle invocation reads the other package's output.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

from bookmark_ranges_oracle import NS, W, attr, character, equal, snapshot

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'


def specification():
    return json.loads((FIXTURES / 'bookmark_copy_expected.json').read_text())


def authored_root(copied=False):
    root = ET.fromstring((FIXTURES / 'bookmark_copy.xml').read_bytes())
    spec = specification()
    equal(snapshot(root)['ranges'], spec['source_ranges'], 'authored source range intent')
    if not copied:
        return root
    body = root.find('w:body', NS)
    paragraphs = body.findall('w:p', NS)
    incoming = [copy.deepcopy(paragraph) for paragraph in paragraphs[:2]]
    by_id = {int(spec['source_ranges'][name]['id']): target
             for name, target in spec['copy_mapping'].items()}
    for paragraph in incoming:
        for marker in paragraph.iter():
            if marker.tag not in ('{' + W + '}bookmarkStart', '{' + W + '}bookmarkEnd'):
                continue
            target = by_id[int(attr(marker, 'id'))]
            marker.set('{' + W + '}id', target['id'])
            if marker.tag.endswith('bookmarkStart'):
                marker.set('{' + W + '}name', target['name'])
    body.remove(paragraphs[3])
    for paragraph in incoming:
        body.insert(len(body) - 1, paragraph)
    equal(snapshot(root)['ranges'], {**spec['source_ranges'], **spec['copied_ranges']},
          'authored insertion range intent')
    return root


def links(root):
    return [{'anchor': attr(node, 'anchor'),
             'text': ''.join(character(child) for child in node.iter())}
            for node in root.findall('.//w:hyperlink', NS)]


def bold_text(root):
    result = []
    for run in root.findall('.//w:r', NS):
        bold = run.find('w:rPr/w:b', NS)
        if bold is not None and attr(bold, 'val') not in ('0', 'false', 'off'):
            result.append(''.join(character(child) for child in run.iter()))
    return result


def verify_xml(data, *, copied):
    actual = ET.fromstring(data)
    expected = authored_root(copied)
    equal(snapshot(actual), snapshot(expected), 'exact native copy range/text/field intent')
    equal(links(actual), links(expected), 'original hyperlink targets')
    equal(bold_text(actual), bold_text(expected), 'source bold text runs')


def verify(root: Path, *, editor=False):
    expected = (['copied-expected.docx', *[f'editor-{cycle}.docx' for cycle in (1, 2, 3)]] if editor else
                ['source.docx', 'copied-expected.docx', *[f'copied-{cycle}.docx' for cycle in (1, 2, 3)]])
    equal(sorted(path.name for path in root.glob('*.docx')), sorted(expected),
          'authored bookmark copy output inventory')
    receipts = []
    for name in expected:
        path = root / name
        if name == 'copied-expected.docx':
            equal(path.read_bytes(), (FIXTURES / 'bookmark_copy_expected.docx').read_bytes(),
                  'independent native reference bytes')
        with ZipFile(path) as package:
            verify_xml(package.read('word/document.xml'), copied=name != 'source.docx')
        receipts.append({'name': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return {'status': 'passed', 'producer': 'editor' if editor else 'engine',
            'files_verified': len(expected), 'files': receipts,
            'checks': ['exact marker order and native attributes', 'unchanged source IDs',
                       'explicit free copy IDs and names', 'UTF-16 and empty ranges',
                       'cross-paragraph overlapping range text', 'unchanged REF and hyperlink targets',
                       'source bold formatting'],
            'bounds': ['complete editable ranges only', 'opaque and native TOC cache copies rejected',
                       'partial ranges rejected before mutation', 'no reference target retargeting']}


def write_native_reference(source: Path, target: Path):
    """Author an external-render reference from source bytes and explicit intent."""
    with ZipFile(source) as package:
        verify_xml(package.read('word/document.xml'), copied=False)
        parts = [(entry, package.read(entry.filename)) for entry in package.infolist()]
    native = ET.tostring(authored_root(True), encoding='utf-8', xml_declaration=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(target, 'w') as package:
        for entry, data in parts:
            package.writestr(entry, native if entry.filename == 'word/document.xml' else data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT / 'build/fidelity-bookmark-copy')
    parser.add_argument('--editor', action='store_true')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--write-native-reference', type=Path)
    args = parser.parse_args()
    report = verify(args.root, editor=args.editor)
    if args.write_native_reference:
        if args.editor:
            parser.error('author the reference from the engine source inventory')
        write_native_reference(args.root / 'source.docx', args.write_native_reference)
        report['native_reference'] = str(args.write_native_reference)
        report['native_reference_sha256'] = hashlib.sha256(
            args.write_native_reference.read_bytes()).hexdigest()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

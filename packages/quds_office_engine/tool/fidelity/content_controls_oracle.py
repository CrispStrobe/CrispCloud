#!/usr/bin/env python3
"""Independently check native SDT metadata, nesting, empty slots and edited text."""
import argparse
import json
from pathlib import Path, PurePosixPath
import posixpath
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ENGINE = Path(__file__).resolve().parents[2]
FIXTURES = ENGINE / 'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
MC = 'http://schemas.openxmlformats.org/markup-compatibility/2006'
WP = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
NS = {'w': W, 'r': R, 'wp': WP}


def _logical(element):
    for child in list(element):
        if child.tag == '{' + MC + '}AlternateContent':
            choice = child.find('{' + MC + '}Choice')
            # The authored legacy frame is exported as the known wps branch.
            if choice is None or choice.get('Requires') != 'wps':
                choice = child.find('{' + MC + '}Fallback')
            assert choice is not None, 'No understood frame compatibility branch'
            index = list(element).index(child)
            element.remove(child)
            for replacement in list(choice):
                element.insert(index, replacement)
                index += 1
        else:
            _logical(child)
    for child in list(element):
        if child.tag == '{' + MC + '}AlternateContent':
            raise AssertionError('Unprocessed compatibility wrapper')


def _part(package, owner, relationship_type):
    parent = PurePosixPath(owner)
    relationships = str(parent.parent / '_rels' / (parent.name + '.rels')) if owner else '_rels/.rels'
    root = ET.fromstring(package.read(relationships))
    matches = [node for node in root if node.get('Type') == R + '/' + relationship_type]
    assert len(matches) == 1, (owner, relationship_type, len(matches))
    rel = matches[0]
    assert rel.get('TargetMode') != 'External'
    target = rel.get('Target', '')
    path = posixpath.normpath(posixpath.join(str(parent.parent) if owner else '', target))
    return path.lstrip('/')


def snapshot(path):
    observed = {}
    with ZipFile(path) as package:
        main = _part(package, '', 'officeDocument')
        parts = [('document', main), ('header', _part(package, main, 'header')),
                 ('footnotes', _part(package, main, 'footnotes'))]
        first_text = None
        for story, name in parts:
            root = ET.fromstring(package.read(name))
            _logical(root)
            if story == 'document':
                first = root.find('w:body/w:p', NS)
                first_text = ''.join(first.itertext()) if first is not None else None

            def visit(node, parent_id=None):
                if node.tag == '{' + W + '}sdt':
                    props = node.find('w:sdtPr', NS)
                    assert props is not None, 'Missing sdtPr'

                    def val(local):
                        item = props.find('w:' + local, NS)
                        return None if item is None else item.get('{' + W + '}val')

                    identifier = val('id')
                    assert identifier is not None and identifier not in observed, 'Missing/duplicate SDT ID'
                    content = node.find('w:sdtContent', NS)
                    end_color = node.find('w:sdtEndPr/w:rPr/w:color', NS)
                    observed[identifier] = {
                        'values': [story, parent_id, val('alias'), val('tag'), content is not None,
                                   ''.join(item.text or '' for item in node.iter('{' + W + '}t'))],
                        'end_color': None if end_color is None else end_color.get('{' + W + '}val'),
                        'kind': 'richText' if props.find('w:richText', NS) is not None else None,
                        'children': [child.tag for child in node],
                        'paragraphs': [] if content is None else [
                            ''.join(item.text or '' for item in paragraph.iter('{' + W + '}t'))
                            for paragraph in content.findall('w:p', NS)],
                    }
                    parent_id = identifier
                for child in node:
                    visit(child, parent_id)

            visit(root)
    return observed, first_text


def verify_file(path, expected, mode='imported', *, converted_legacy=False):
    assert mode in ('imported', 'edited', 'editor', 'legacy'), mode
    observed, first_text = snapshot(path)
    assert set(observed) == set(expected['controls']), ('Control identity set', set(observed))
    for identifier, values in expected['controls'].items():
        wanted = list(values)
        if mode == 'legacy':
            wanted = expected['legacy_controls'].get(identifier, wanted)
        elif mode in ('edited', 'editor'):
            wanted[-1] = expected[mode + '_text'].get(identifier, wanted[-1])
        actual = observed[identifier]
        assert actual['values'] == wanted, (identifier, actual['values'], wanted)
        assert actual['end_color'] == expected['end_color'], (identifier, 'sdtEndPr')
        assert actual['kind'] == expected['kind'], (identifier, 'control kind')
        children = ['sdtPr', 'sdtEndPr'] + (['sdtContent'] if wanted[4] else [])
        assert actual['children'] == ['{' + W + '}' + name for name in children], (identifier, 'wrapper order')
        if mode == 'editor' and identifier in expected['editor_paragraphs']:
            assert actual['paragraphs'] == expected['editor_paragraphs'][identifier], (identifier, 'editor split paragraphs')
    assert first_text == ('Before edited' if mode == 'edited' else 'Before'), ('Adjacent paragraph edit', first_text)
    if converted_legacy:
        assert mode == 'legacy'
        with ZipFile(path) as package:
            root = ET.fromstring(package.read(_part(package, '', 'officeDocument')))
        _logical(root)
        anchors = root.findall('.//wp:anchor', NS)
        assert len(anchors) == 1, ('Legacy frame must convert exactly once', len(anchors))
        anchor = anchors[0]
        geometry = {
            'x': int(anchor.find('wp:positionH/wp:posOffset', NS).text),
            'y': int(anchor.find('wp:positionV/wp:posOffset', NS).text),
            'cx': int(anchor.find('wp:extent', NS).get('cx')),
            'cy': int(anchor.find('wp:extent', NS).get('cy')),
        }
        assert geometry == expected['legacy_frame_emu'], ('Legacy frame geometry', geometry)


def verify_source_copy(path):
    assert path.read_bytes() == (FIXTURES / 'content-controls.docx').read_bytes(), \
        'The renderer baseline must be an exact copy of the independently authored SDT input'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--editor-dir', type=Path,
                        help='Also verify all three actual editor split/history exports in this directory')
    args = parser.parse_args()
    expected = json.loads((FIXTURES / 'content_controls_expected.json').read_text())
    verify_file(FIXTURES / 'content-controls.docx', expected)
    verify_file(FIXTURES / 'content-controls-legacy.docx', expected, 'legacy')
    copied_source = ENGINE / 'build/fidelity-content-controls-legacy/controls-source.docx'
    verify_source_copy(copied_source)
    verify_file(copied_source, expected)
    for mode in ('imported', 'edited'):
        for cycle in range(1, 4):
            verify_file(ENGINE / f'build/fidelity-content-controls-legacy/controls-{mode}-{cycle}.docx', expected, mode)
    for cycle in range(1, 4):
        verify_file(ENGINE / f'build/fidelity-content-controls-legacy/legacy-frame-{cycle}.docx',
                    expected, 'legacy', converted_legacy=True)
    print('Content-control oracle: exact authored source copy, six native exports and three legacy conversion exports passed')
    if args.editor_dir is not None:
        for cycle in range(1, 4):
            verify_file(args.editor_dir / f'editor-controls-{cycle}.docx', expected, 'editor')
        print('Content-control oracle: all three actual editor split/history exports passed')


if __name__ == '__main__':
    main()

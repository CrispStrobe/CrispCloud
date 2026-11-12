#!/usr/bin/env python3
"""Inspect native single-paragraph auxiliary SDTs without using the engine."""
from pathlib import Path
import json
import posixpath
from xml.etree import ElementTree as ET
from zipfile import ZipFile

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
P = 'http://schemas.openxmlformats.org/package/2006/relationships'
W14 = 'http://schemas.microsoft.com/office/word/2010/wordml'
W15 = 'http://schemas.microsoft.com/office/word/2012/wordml'
EXT = 'http://schemas.microsoft.com/office/2011/relationships/commentsExtended'
NS = {'w': W, 'r': R, 'p': P, 'w14': W14, 'w15': W15}
STORIES = ['header_default', 'header_first', 'header_even', 'footer_default',
           'footer_first', 'footer_even', 'comments']
EXPECTED_FILES = {'source.docx'} | {
    f'{phase}-{cycle}.docx' for phase in ['imported', 'edited'] for cycle in range(1, 4)}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def relationships(parts, owner):
    path = posixpath.join(posixpath.dirname(owner), '_rels',
                         posixpath.basename(owner) + '.rels')
    if path not in parts:
        return {}
    nodes = ET.fromstring(parts[path]).findall('p:Relationship', NS)
    require(len({node.get('Id') for node in nodes}) == len(nodes), 'duplicate relationship ID')
    return {node.get('Id'): node.attrib for node in nodes}


def resolve(owner, relationship):
    target = relationship['Target']
    return posixpath.normpath(posixpath.join(posixpath.dirname(owner), target)).lstrip('/')


def inspect_parts(parts, *, edited=False, wrapped_comment=True):
    main = 'word/document.xml'
    document = ET.fromstring(parts[main])
    main_rels = relationships(parts, main)
    locations = {}
    for kind in ['header', 'footer']:
        for reference in document.findall(f'w:body/w:sectPr/w:{kind}Reference', NS):
            name = kind + '_' + reference.get(f'{{{W}}}type')
            require(name not in locations, 'duplicate auxiliary story reference')
            relation = main_rels.get(reference.get(f'{{{R}}}id'))
            require(relation is not None and relation.get('Type') == R + '/' + kind,
                    'auxiliary story relationship changed')
            locations[name] = resolve(main, relation)
    for relation in main_rels.values():
        if relation.get('Type') == R + '/comments':
            require('comments' not in locations, 'duplicate comments relationship')
            locations['comments'] = resolve(main, relation)
    require(set(locations) == set(STORIES), 'missing auxiliary story')
    ids = set()
    for index, story in enumerate(STORIES):
        owner = locations[story]
        root = ET.fromstring(parts[owner])
        host = root
        if story == 'comments':
            comments = root.findall('w:comment', NS)
            require(len(comments) == 1 and comments[0].get(f'{{{W}}}id') == '7',
                    'comment identity changed')
            host = comments[0]
        for level in range(2 if story != 'comments' or wrapped_comment else 0):
            children = list(host)
            require(len(children) == 1 and children[0].tag == f'{{{W}}}sdt',
                    'auxiliary block wrapper flattened or duplicated')
            control = children[0]
            expected = str(700 + index * 2 + level)
            props = control.find('w:sdtPr', NS)
            require(props is not None, 'control properties lost')
            for name, value in [('id', expected), ('alias', 'Auxiliary ' + expected),
                                ('tag', story + '-' + expected), ('lock', 'unlocked')]:
                node = props.find('w:' + name, NS)
                require(node is not None and node.get(f'{{{W}}}val') == value,
                        'control metadata or nesting order changed')
            require(expected not in ids, 'duplicate native control ID')
            ids.add(expected)
            require(props.find('w:richText', NS) is not None, 'control type lost')
            end_color = control.find('w:sdtEndPr/w:rPr/w:color', NS)
            require(end_color is not None and end_color.get(f'{{{W}}}val') == '123456',
                    'control end properties lost')
            host = control.find('w:sdtContent', NS)
            require(host is not None, 'control content lost')
        children = list(host)
        require(len(children) == 1 and children[0].tag == f'{{{W}}}p',
                'control no longer owns exactly one paragraph')
        paragraph = children[0]
        if story == 'footer_default':
            instructions = [''.join(node.itertext()).strip()
                            for node in paragraph.findall('.//w:instrText', NS)]
            require(instructions == [r'PAGE \* MERGEFORMAT'], 'native PAGE field instruction changed')
            chars = [node.get(f'{{{W}}}fldCharType')
                     for node in paragraph.findall('.//w:fldChar', NS)]
            require(chars == ['begin', 'separate', 'end'], 'native PAGE field structure changed')
            alignment = paragraph.find('w:pPr/w:jc', NS)
            require(alignment is not None and alignment.get(f'{{{W}}}val') == 'center',
                    'PAGE paragraph formatting changed')
        else:
            expected_text = ('Changed' if edited else 'Original') + ' ' + story + ' link'
            text = ''.join(node.text or '' for node in paragraph.findall('.//w:t', NS))
            require(text == expected_text, 'live controlled text changed')
            links = paragraph.findall('w:hyperlink', NS)
            require(len(links) == 1, 'controlled hyperlink lost')
            relation = relationships(parts, owner).get(links[0].get(f'{{{R}}}id'))
            require(relation is not None and relation.get('TargetMode') == 'External'
                    and relation.get('Target') == 'https://example.test/' + story,
                    'controlled hyperlink relationship ownership changed')
            if edited:
                require(paragraph.find('w:r/w:rPr/w:b', NS) is not None,
                        'controlled text formatting edit lost')
        if story == 'comments':
            require(paragraph.get(f'{{{W14}}}paraId') == '00000077',
                    'wrapped comment paragraph anchor changed')
    extensions = [relation for relation in main_rels.values() if relation.get('Type') == EXT]
    require(len(extensions) == 1, 'comment extension relationship lost')
    extension = ET.fromstring(parts[resolve(main, extensions[0])])
    status = extension.findall('w15:commentEx', NS)
    require(len(status) == 1 and status[0].get(f'{{{W15}}}paraId') == '00000077'
            and status[0].get(f'{{{W15}}}done') == '1', 'wrapped comment resolution detached')
    body = ''.join(node.text or '' for node in document.findall('w:body/w:p/w:r/w:t', NS))
    require(body == ('Body edited' if edited else 'Body'), 'body text changed')
    return {'stories': len(locations), 'native_controls': len(ids), 'edited': edited}


def main():
    for corpus, wrapped in [('fidelity-aux-controls', True), ('fidelity-aux-header-footer', False)]:
        directory = Path('build') / corpus
        actual = {path.name for path in directory.glob('*.docx')}
        require(actual == EXPECTED_FILES, f'{corpus} inventory mismatch: {actual ^ EXPECTED_FILES}')
        for name in sorted(EXPECTED_FILES):
            with ZipFile(directory / name) as archive:
                require(len(archive.namelist()) == len(set(archive.namelist())), 'duplicate ZIP entries')
                require(archive.testzip() is None, 'invalid ZIP content')
                inspect_parts({part: archive.read(part) for part in archive.namelist()},
                              edited=name.startswith('edited-'), wrapped_comment=wrapped)
    print(json.dumps({'status': 'passed', 'documents': len(EXPECTED_FILES) * 2,
                      'native_control_counts': [14, 12], 'stories_per_document': 7}))


if __name__ == '__main__':
    main()

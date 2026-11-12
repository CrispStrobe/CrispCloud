#!/usr/bin/env python3
"""Independent authored expectations for exact native bookmark endpoints."""
import argparse
from pathlib import Path
import posixpath
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'test/fixtures/fidelity/bookmarks.docx'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
NS = {'w': W, 'r': R}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def marker(start, identifier, paragraph, offset, name=None, **extra):
    attributes = {'id': str(identifier), **extra}
    if start:
        attributes['name'] = name
    return {'kind': 'start' if start else 'end', 'paragraph': paragraph,
            'offset': offset, 'attributes': attributes}


def expected(edited):
    """Hand-authored endpoints; these are not learned from engine output."""
    shift = int(edited)
    body = [marker(True, 10, 1, 0, 'Alpha'), marker(False, 10, 1, 6 if edited else 5),
            marker(True, 11, 1, 7 if edited else 6, 'Beta'), marker(False, 11, 1, 12 if edited else 10),
            marker(True, 12, 2, 0, 'AcrossParagraphs'), marker(False, 12, 3 + shift, 19),
            marker(True, 20, 4 + shift, 0, 'OverlapA'), marker(True, 21, 4 + shift, 1, 'OverlapB'),
            marker(False, 20, 4 + shift, 4 if edited else 3),
            marker(False, 21, 4 + shift, 5 if edited else 4),
            marker(True, 22, 4 + shift, 5 if edited else 4, 'Cursor'),
            marker(False, 22, 4 + shift, 5 if edited else 4),
            marker(True, 23, 5 + shift, 0, 'Linked'), marker(False, 23, 5 + shift, 4),
            marker(True, 30, 6 + shift, 0, 'TableCell', colFirst='0', colLast='0'),
            marker(False, 30, 6 + shift, 11 if edited else 9)]
    texts = (['Edited probe prefix', 'ALPHA! Be+ta', 'Cross-', 'new paragraph start',
              'CROSS-paragraph end', 'AB+CD', 'Link', 'Cell edited', 'Notes ']
             if edited else ['Probe prefix', 'Alpha Beta', 'Cross-paragraph start',
                             'Cross-paragraph end', 'ABCD', 'Link', 'Cell text', 'Notes '])
    result = {'body': {'paragraphs': texts, 'markers': body}}
    for variant in ('default', 'first', 'even'):
        for kind in ('header', 'footer'):
            label = f'{variant}_{kind}'
            text = label + ('!' if edited else '')
            result[label] = {'paragraphs': [text], 'markers': [
                marker(True, 100, 0, 0, label), marker(False, 100, 0, len(text))]}
    for kind, identifier, bookmark_id, name in [('footnote', 7, 40, 'FootnoteRange'),
                                                ('endnote', 8, 50, 'EndnoteRange')]:
        text = f'Edited {kind}' if edited else name
        result[f'{kind}:{identifier}'] = {'paragraphs': [text], 'markers': [
            marker(True, bookmark_id, 0, 0, name), marker(False, bookmark_id, 0, len(text))]}
    return result


def snapshot(root):
    paragraphs, markers = [], []
    for index, paragraph in enumerate(root.iter('{' + W + '}p')):
        text = ''
        for element in paragraph.iter():
            if element.tag == '{' + W + '}t':
                text += element.text or ''
            elif element.tag == '{' + W + '}tab':
                text += '\t'
            elif element.tag in ('{' + W + '}br', '{' + W + '}cr'):
                text += '\n'
            elif element.tag in ('{' + W + '}bookmarkStart', '{' + W + '}bookmarkEnd'):
                attributes = {key.removeprefix('{' + W + '}'): value
                              for key, value in element.attrib.items()}
                markers.append({'kind': 'start' if element.tag.endswith('Start') else 'end',
                                'paragraph': index, 'offset': len(text.encode('utf-16-le')) // 2,
                                'attributes': attributes})
        paragraphs.append(text)
    # Reject out-of-paragraph markup rather than ignoring an extra endpoint.
    total = sum(element.tag in ('{' + W + '}bookmarkStart', '{' + W + '}bookmarkEnd')
                for element in root.iter())
    require(total == len(markers), 'Bookmark endpoint outside a modeled paragraph')
    return {'paragraphs': paragraphs, 'markers': markers}


def inspect_package(path):
    with ZipFile(path) as package:
        require(len(package.namelist()) == len(set(package.namelist())), 'Duplicate ZIP member')
        def relationships(owner):
            name = (posixpath.join(posixpath.dirname(owner), '_rels', posixpath.basename(owner) + '.rels')
                    if owner else '_rels/.rels')
            root = ET.fromstring(package.read(name))
            records = root.findall('{' + REL + '}Relationship')
            require(len({row.attrib['Id'] for row in records}) == len(records), 'Duplicate relationship ID')
            return {row.attrib['Id']: row.attrib for row in records}

        def target(owner, row):
            require(row.get('TargetMode') != 'External', 'External story relationship')
            return posixpath.normpath(posixpath.join(posixpath.dirname(owner), row['Target'])).lstrip('/')

        main = [row for row in relationships('').values() if row['Type'] == R + '/officeDocument']
        require(len(main) == 1, 'Expected one main document relationship')
        uri = target('', main[0])
        root = ET.fromstring(package.read(uri))
        rels = relationships(uri)
        result = {'body': snapshot(root)}
        for kind in ('header', 'footer'):
            for reference in root.findall('.//w:' + kind + 'Reference', NS):
                label = reference.attrib['{' + W + '}type'] + '_' + kind
                require(label not in result, 'Duplicate header/footer story')
                relationship = rels[reference.attrib['{' + R + '}id']]
                require(relationship['Type'] == R + '/' + kind, 'Wrong story relationship type')
                result[label] = snapshot(ET.fromstring(package.read(target(uri, relationship))))
        for kind in ('footnote', 'endnote'):
            related = [row for row in rels.values() if row['Type'] == R + '/' + kind + 's']
            require(len(related) == 1, 'Expected exactly one notes relationship')
            notes = ET.fromstring(package.read(target(uri, related[0])))
            for note in notes.findall('w:' + kind, NS):
                if note.get('{' + W + '}type') in ('separator', 'continuationSeparator', 'continuationNotice'):
                    continue
                label = kind + ':' + note.attrib['{' + W + '}id']
                require(label not in result, 'Duplicate note ID')
                result[label] = snapshot(note)
        return result


def verify_file(path, edited=False):
    actual, wanted = inspect_package(path), expected(edited)
    require(actual == wanted, f'{path.name}: exact bookmark text/endpoints/attributes changed\n'
            f'actual={actual!r}\nexpected={wanted!r}')


def verify_editor_file(path):
    wanted = expected(False)
    wanted['body']['paragraphs'] = ['Probe prefix', 'Alpha Be', 't+a',
                                  'Cross-paragraph start', 'Cross-paragraph end',
                                  'ABCD', 'Link', 'Cell text', 'Notes ']
    for endpoint in wanted['body']['markers']:
        if endpoint['paragraph'] >= 2:
            endpoint['paragraph'] += 1
        if endpoint['kind'] == 'end' and endpoint['attributes']['id'] == '11':
            endpoint['paragraph'], endpoint['offset'] = 2, 3
    actual = inspect_package(path)
    require(actual == wanted, f'{path.name}: editor split/history lost native bookmark boundaries\n'
            f'actual={actual!r}\nexpected={wanted!r}')


def verify_editor_corpus(directory):
    names = {f'editor-bookmarks-{cycle}.docx' for cycle in (1, 2, 3)}
    observed = {path.name for path in directory.glob('*.docx')}
    require(observed == names, f'Editor bookmark corpus missing={sorted(names-observed)}, extra={sorted(observed-names)}')
    for name in sorted(names):
        verify_editor_file(directory / name)


def verify_corpus(directory):
    names = {f'bookmarks-{mode}-{cycle}.docx' for mode in ('imported', 'edited') for cycle in (1, 2, 3)}
    names.add('bookmarks-source.docx')
    observed = {path.name for path in directory.glob('*.docx')}
    require(observed == names, f'Bookmark corpus missing={sorted(names-observed)}, extra={sorted(observed-names)}')
    require((directory / 'bookmarks-source.docx').read_bytes() == SOURCE.read_bytes(),
            'Source must be copied exactly, not reexported')
    verify_file(directory / 'bookmarks-source.docx')
    for mode in ('imported', 'edited'):
        for cycle in (1, 2, 3):
            verify_file(directory / f'bookmarks-{mode}-{cycle}.docx', mode == 'edited')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=ROOT / 'build/fidelity-bookmarks-legacy')
    parser.add_argument('--editor-dir', type=Path,
                        help='Also require all three actual editor split/history outputs')
    args = parser.parse_args(argv)
    verify_file(SOURCE)
    verify_corpus(args.directory)
    if args.editor_dir is not None:
        verify_editor_corpus(args.editor_dir)
    print('Bookmark oracle: authored source and all six cycle exports passed')


if __name__ == '__main__':
    main()

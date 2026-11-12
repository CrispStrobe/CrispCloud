#!/usr/bin/env python3
"""Independent OOXML oracle for automatic note mark positions and absence."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def local(name):
    return name.removeprefix('{' + W + '}')


def properties(run):
    root = run.find('w:rPr', NS)

    def node(element):
        result = {'name': local(element.tag),
                  'attributes': {local(key): value for key, value in element.attrib.items()}}
        if len(element):
            result['children'] = [node(child) for child in element]
        return result

    return [] if root is None else [node(child) for child in root]


def inspect_package(path):
    result = {}
    with ZipFile(path) as package:
        names = package.namelist()
        require(len(names) == len(set(names)), 'Duplicate ZIP members')
        for kind in ('footnote', 'endnote'):
            part = f'word/{kind}s.xml'
            root = ET.fromstring(package.read(part))
            require(root.tag == '{' + W + '}' + kind + 's', 'Incorrect note part root')
            for note in root.findall('w:' + kind, NS):
                if note.get('{' + W + '}type') in ('separator', 'continuationSeparator', 'continuationNotice'):
                    continue
                identifier = int(note.attrib['{' + W + '}id'])
                require((kind, identifier) not in result, 'Duplicate note IDs')
                texts, markers = [], []
                for index, paragraph in enumerate(note.iter('{' + W + '}p')):
                    text = ''
                    for run in paragraph.iter('{' + W + '}r'):
                        for child in run.iter():
                            if child.tag == '{' + W + '}t':
                                text += child.text or ''
                            elif child.tag == '{' + W + '}tab':
                                text += '\t'
                            elif child.tag in ('{' + W + '}br', '{' + W + '}cr'):
                                text += '\n'
                            elif child.tag in ('{' + W + '}footnoteRef', '{' + W + '}endnoteRef'):
                                require(local(child.tag) == kind + 'Ref', 'Automatic mark kind differs from its owning note')
                                markers.append({'paragraph': index,
                                                'offset': len(text.encode('utf-16-le')) // 2,
                                                'properties': properties(run)})
                    texts.append(text)
                result[kind, identifier] = {
                    'blocks': [local(child.tag) for child in note],
                    'paragraphs': texts,
                    'markers': markers,
                }
    return result


def verify_file(path, expected, mode):
    require(mode in ('imported', 'edited'), 'Unknown marker oracle mode')
    actual = inspect_package(path)
    require(set(actual) == {(row['kind'], row['id']) for row in expected['notes']},
            'Authored footnote/endnote inventory changed')
    for row in expected['notes']:
        key = row['kind'], row['id']
        marker_key = 'edited_markers' if mode == 'edited' else 'markers'
        text_key = 'edited_paragraphs' if mode == 'edited' else 'paragraphs'
        wanted = {
            'blocks': row['blocks'], 'paragraphs': row[text_key],
            'markers': [dict(marker, properties=expected['properties'][marker['properties']])
                        for marker in row[marker_key]],
        }
        require(actual[key] == wanted,
                f'{path.name}: {key} note marker position/absence/properties/text changed\n'
                + json.dumps({'actual': actual[key], 'expected': wanted}, indent=2))


def verify_corpus(directory, expected):
    names = {f'markers-{mode}-{cycle}.docx' for mode in ('imported', 'edited') for cycle in (1, 2, 3)}
    names.add('markers-source.docx')
    observed = {path.name for path in directory.glob('*.docx')}
    require(observed == names,
            f'Note marker corpus inventory: missing={sorted(names-observed)}, extra={sorted(observed-names)}')
    source = directory / 'markers-source.docx'
    require(source.read_bytes() == (FIXTURES / 'note-markers.docx').read_bytes(),
            'Authored note source must be copied exactly, not reexported')
    verify_file(source, expected, 'imported')
    for mode in ('imported', 'edited'):
        for cycle in (1, 2, 3):
            verify_file(directory / f'markers-{mode}-{cycle}.docx', expected, mode)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=ROOT / 'build/fidelity-note-markers')
    args = parser.parse_args(argv)
    expected = json.loads((FIXTURES / 'note_markers_expected.json').read_text())
    verify_file(FIXTURES / 'note-markers.docx', expected, 'imported')
    verify_corpus(args.directory, expected)
    print('Note marker oracle: authored source and all 6 imported/edited cycle exports passed')


if __name__ == '__main__':
    main()

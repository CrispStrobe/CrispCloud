#!/usr/bin/env python3
"""Independent XML oracle for MC selection and retained section metadata.

The DOCX input and semantic expectations are independently authored fixtures.
Neither this checker nor its expected values use the Quds reader/writer.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from corpus import FIXTURES, NS, R, W, read_zip, validate
from story_media_oracle import require, target

MC = '{http://schemas.openxmlformats.org/markup-compatibility/2006}'
EXPECTED_NAMES = frozenset(
    f'compatibility-{state}-{cycle}.docx'
    for state in ('imported', 'edited') for cycle in range(1, 4))
MODELED = frozenset(('type', 'pgSz', 'pgMar', 'cols', 'lnNumType', 'titlePg'))


def sections(body):
    result = []
    for child in body:
        if child.tag == f'{{{W}}}sectPr':
            result.append(child)
        elif child.tag == f'{{{W}}}p':
            section = child.find('w:pPr/w:sectPr', NS)
            if section is not None:
                result.append(section)
    return result


def canonical(node):
    if node is None:
        return None
    return (node.tag, sorted(node.attrib.items()), (node.text or '').strip(),
            [canonical(child) for child in node])


def paragraph_text(paragraph):
    result = []
    for node in paragraph.iter():
        if node.tag == f'{{{W}}}t':
            result.append(node.text or '')
        elif node.tag == f'{{{W}}}tab':
            result.append('\t')
        elif node.tag == f'{{{W}}}br':
            result.append('\n')
        elif node.tag == f'{{{W}}}footnoteReference':
            result.append(node.get(f'{{{W}}}id'))
    return ''.join(result)


def verify_document(parts, *, edited=False):
    failures = validate(parts)
    require(not failures, '; '.join(failures))
    main = target(parts, '', kind='officeDocument')
    body = ET.fromstring(parts[main]).find('w:body', NS)
    require(body is not None, 'Missing document body')
    require(body.find('.//' + MC + 'AlternateContent') is None,
            'Unresolved alternate branch remained in the modeled body')
    golden = json.loads((FIXTURES / 'word_compatibility_expected.json').read_text())
    expected_text = list(golden['body_paragraphs'])
    expected_text[0] = 'Edited compatibility text'
    actual_text = [paragraph_text(p) for p in body.findall('.//w:p', NS)]
    require(actual_text == expected_text, f'Wrong branch, duplicated or lost text: {actual_text}')
    require(len(body.findall('w:tbl', NS)) == 1, 'Selected table structure changed')
    actual_sections = sections(body)
    require(len(actual_sections) == 2, f'Expected two sections, found {len(actual_sections)}')
    original = read_zip(FIXTURES / 'word-compatibility.docx')
    source_sections = sections(ET.fromstring(original['word/document.xml']).find('w:body', NS))
    for index, (actual, source) in enumerate(zip(actual_sections, source_sections)):
        require(actual.attrib == source.attrib, f'Section {index}: source attributes changed')
        for child in source:
            key = child.tag.split('}')[-1]
            if key in MODELED or key in ('headerReference', 'footerReference'):
                continue
            require(canonical(actual.find(child.tag)) == canonical(child),
                    f'Section {index}: retained {key} metadata changed')
        for key in MODELED:
            expected = deepcopy(source.find(f'{{{W}}}{key}'))
            if edited and index == 0:
                if key in ('lnNumType', 'titlePg'):
                    expected = None
                elif key == 'pgSz':
                    expected.set(f'{{{W}}}w', '12240')
                    expected.set(f'{{{W}}}h', '15840')
                    expected.attrib.pop(f'{{{W}}}orient', None)
                elif key == 'pgMar':
                    expected.set(f'{{{W}}}left', '1800')
                elif key == 'cols':
                    expected.set(f'{{{W}}}num', '3')
                    expected.set(f'{{{W}}}space', '480')
                    expected.set(f'{{{W}}}equalWidth', '1')
                    expected.attrib.pop(f'{{{W}}}sep', None)
                    for child in list(expected):
                        expected.remove(child)
            require(canonical(actual.find(f'{{{W}}}{key}')) == canonical(expected),
                    f'Section {index}: modeled {key} edit or source preservation failed')
    references = actual_sections[0].findall('w:headerReference', NS)
    require(len(references) == 2, 'First section lost one of its two headers')
    observed = {}
    for reference in references:
        variant = reference.get(f'{{{W}}}type')
        require(variant not in observed, 'Duplicate header variant')
        owner = target(parts, main, rid=reference.get(f'{{{R}}}id'))
        story = ET.fromstring(parts[owner])
        require(story.find('.//' + MC + 'AlternateContent') is None,
                'Header retained multiple alternate branches')
        observed[variant] = ''.join(paragraph_text(p) for p in story.findall('w:p', NS)).strip()
    require(observed == {'default': golden['default_header'], 'first': golden['first_header']},
            f'Header branch selection or section binding changed: {observed}')
    notes = ET.fromstring(parts[target(parts, main, kind='footnotes')])
    note = notes.find('w:footnote[@w:id="3"]', NS)
    require(note is not None, 'Missing footnote 3')
    content = ''.join(paragraph_text(p) for p in note.findall('w:p', NS)).strip()
    require(content == golden['footnote'], 'Footnote branch selection changed')
    require(note.find('.//' + MC + 'AlternateContent') is None,
            'Footnote retained multiple alternate branches')
    return {'sections': len(actual_sections), 'paragraphs': actual_text,
            'headers': observed, 'footnote': content, 'modeled_edits': edited}


def verify_directory(folder):
    folder = Path(folder)
    actual = {path.name for path in folder.glob('*.docx')}
    failures = []
    if actual != EXPECTED_NAMES:
        failures.append(f'Unexpected inventory: missing={sorted(EXPECTED_NAMES - actual)}, '
                        f'extra={sorted(actual - EXPECTED_NAMES)}')
    snapshots = {}
    for name in sorted(EXPECTED_NAMES & actual):
        try:
            snapshots[name] = verify_document(read_zip(folder / name),
                                               edited=name.startswith('compatibility-edited'))
        except (AssertionError, KeyError, ValueError, ET.ParseError) as error:
            failures.append(f'{name}: {error}')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'word-compatibility-oracle-report.json').write_text(json.dumps(
        {'files': len(actual), 'checked': len(snapshots), 'failures': failures,
         'snapshots': snapshots}, indent=2) + '\n')
    require(not failures, '\n'.join(failures))
    return len(snapshots)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', nargs='?', default='build/fidelity-word-compatibility')
    args = parser.parse_args()
    print(f'{verify_directory(args.folder)} compatibility/section exports: PASS')


if __name__ == '__main__':
    main()

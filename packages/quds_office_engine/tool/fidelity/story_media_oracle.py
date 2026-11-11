#!/usr/bin/env python3
"""Independent ZIP/XML/pixel oracle for all Word stories and OPC part routing.

Expected semantics are authored in story_media_expected.json. No Quds reader
or writer is called here. Normal runs never create or update input fixtures.
"""
import argparse
import hashlib
import json
from pathlib import Path
import posixpath
import xml.etree.ElementTree as ET

from corpus import FIXTURES, NS, R, W, read_zip, relationship_map, validate
from notes_oracle import pixels

EXPECTED_NAMES = frozenset(
    [f'story-{state}-{cycle}.docx' for state in ('imported', 'edited')
     for cycle in range(1, 4)]
    + [f'relocated-edited-{cycle}.docx' for cycle in range(1, 4)]
)


def require(condition, message):
    # Explicit raises keep the oracle active under python -O as well.
    if not condition:
        raise AssertionError(message)


def target(parts, owner, *, rid=None, kind=None):
    rows = relationship_map(parts, owner)
    matches = [row for row in rows.values()
               if row['Id'] == rid] if rid else [
                   row for row in rows.values() if row['Type'].endswith('/' + kind)]
    require(len(matches) == 1, f'{owner}: expected one relationship {rid or kind}')
    row = matches[0]
    require(row.get('TargetMode') != 'External', f'{owner}: unexpected external part')
    name = posixpath.normpath(posixpath.join(posixpath.dirname(owner), row['Target'])).lstrip('/')
    require(name in parts, f'{owner}: missing target {name}')
    return name


def image_snapshot(parts, owner, root):
    content_types = ET.fromstring(parts['[Content_Types].xml'])
    defaults = {e.get('Extension'): e.get('ContentType') for e in content_types
                if e.tag.endswith('Default')}
    overrides = {e.get('PartName').lstrip('/'): e.get('ContentType') for e in content_types
                 if e.tag.endswith('Override')}
    result = []
    for drawing in root.findall('.//w:drawing', NS):
        blips = drawing.findall('.//a:blip', NS)
        require(len(blips) == 1, f'{owner}: expected one image per drawing')
        uri = target(parts, owner, rid=blips[0].get(f'{{{R}}}embed'))
        mime = overrides.get(uri, defaults.get(uri.rsplit('.', 1)[-1]))
        require(mime == 'image/png', f'{owner}: expected PNG content type, got {mime}')
        extents = drawing.findall('.//wp:extent', NS)
        require(len(extents) == 1, f'{owner}: image extents missing or duplicated')
        result.append({
            'pixels': list(pixels(parts[uri])),
            'extents': [int(extents[0].get('cx')), int(extents[0].get('cy'))],
        })
    return result


def expected_image(golden, color, extents=None):
    width, height = golden['image_pixels']
    return {
        'pixels': [width, height, hashlib.sha256(bytes(color) * (width * height)).hexdigest()],
        'extents': extents or [golden['width_emu'], golden['height_emu']],
    }


def verify_document(parts, *, edited=False, relocated=False):
    golden = json.loads((FIXTURES / 'story_media_expected.json').read_text())
    failures = validate(parts)
    require(not failures, '; '.join(failures))
    main = target(parts, '', kind='officeDocument')
    expected_main = golden['relocated_main'] if relocated else 'word/document.xml'
    require(main == expected_main, f'Wrong main part: {main}')
    root = ET.fromstring(parts[main])
    body = root.find('w:body', NS)
    require(body is not None, 'Missing document body')
    text = ''.join(node.text or '' for node in body.findall('.//w:t', NS)).strip()
    require(text == golden['edited_body_text' if relocated else 'body_text'], f'Body text changed: {text!r}')
    body_images = image_snapshot(parts, main, body)
    expected_body = [expected_image(golden, color) for color in golden['body_colors']]
    if edited:
        expected_body[0] = expected_image(golden, golden['replacement_body_color'], golden['replacement_body_extents'])
    require(body_images == expected_body, f'Wrong body images: {body_images}')

    section = body.find('w:sectPr', NS)
    require(section is not None, 'Missing final section')
    references = [node for node in section if node.tag in
                  (f'{{{W}}}headerReference', f'{{{W}}}footerReference')]
    require(len(references) == 6, f'Expected six header/footer references, found {len(references)}')
    # CT_SectPr requires all headerReference children before footerReference.
    kinds = [node.tag.endswith('footerReference') for node in references]
    require(kinds == sorted(kinds), 'Header/footer section reference order is invalid')
    stories = {}
    for ref in references:
        kind = ref.tag.split('}')[-1].replace('Reference', '')
        key = f'{ref.get(f"{{{W}}}type")} {kind}'
        require(key in golden['story_colors'] and key not in stories, f'Invalid or duplicate story {key}')
        owner = target(parts, main, rid=ref.get(f'{{{R}}}id'))
        story = ET.fromstring(parts[owner])
        require(story.tag == f'{{{W}}}' + ('hdr' if kind == 'header' else 'ftr'), f'Wrong story root for {key}')
        actual = image_snapshot(parts, owner, story)
        expected = expected_image(golden, golden['story_colors'][key])
        if edited and key == 'default header':
            expected = expected_image(golden, golden['replacement_header_color'], golden['replacement_header_extents'])
        require(actual == [expected], f'{key}: wrong, missing or cross-wired image')
        changed_footer = edited and key == 'default footer'
        require(len(story.findall('w:p', NS)) == (2 if changed_footer else 1), f'{key}: blank paragraphs accumulated')
        content = ''.join(node.text or '' for node in story.findall('.//w:t', NS)).strip()
        require(content == (golden['footer_edit'] if changed_footer else ''), f'{key}: wrong text')
        if changed_footer:
            link = story.find('w:p/w:hyperlink', NS)
            require(link is not None, 'Edited footer lost its hyperlink')
            rows = relationship_map(parts, owner)
            row = rows.get(link.get(f'{{{R}}}id'), {})
            require(row.get('Target') == golden['footer_link'] and row.get('TargetMode') == 'External',
                    'Footer hyperlink relationship is not owned by the footer')
        stories[key] = actual

    notes = target(parts, main, kind='footnotes')
    if relocated:
        require(notes == golden['relocated_notes'], 'Relocated notes wrote to the wrong part')
        require('word/document.xml' not in parts and 'word/footnotes.xml' not in parts,
                'Unused conventional parts were recreated')
        styles = target(parts, main, kind='styles')
        require(styles == golden['relocated_styles'], 'Relocated style relationship changed')
        require(b'336699' in parts[styles], 'Relocated style definition disappeared')
    note = ET.fromstring(parts[notes]).find('w:footnote[@w:id="3"]', NS)
    require(note is not None, 'Note 3 disappeared')
    require(len(note.findall('.//w:footnoteRef', NS)) == 1, 'Note body marker missing or duplicated')
    note_text = ''.join(node.text or '' for node in note.findall('.//w:t', NS)).strip()
    require(note_text == golden['edited_note_text' if relocated else 'note_text'], 'Note text changed')
    require(image_snapshot(parts, notes, note) == [expected_image(golden, golden['note_color'])],
            'Note picture relationship changed')
    source = read_zip(FIXTURES / 'story-media.docx')
    for name in ('customXml/consumer.xml', 'word/media/image1.png', 'word/charts/chart1.xml'):
        require(parts.get(name) == source[name], f'Retained consumer payload overwritten: {name}')
    return {'main_part': main, 'body_images': body_images, 'stories': stories, 'note_part': notes}


def verify_directory(folder):
    folder = Path(folder)
    actual_names = {path.name for path in folder.glob('*.docx')}
    failures = []
    if actual_names != EXPECTED_NAMES:
        failures.append(f'Unexpected corpus inventory: missing={sorted(EXPECTED_NAMES - actual_names)}, '
                        f'extra={sorted(actual_names - EXPECTED_NAMES)}')
    reports = {}
    for name in sorted(EXPECTED_NAMES & actual_names):
        try:
            reports[name] = verify_document(read_zip(folder / name),
                edited=name.startswith('story-edited'), relocated=name.startswith('relocated'))
        except (AssertionError, KeyError, ValueError, ET.ParseError) as error:
            failures.append(f'{name}: {error}')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'story-media-oracle-report.json').write_text(json.dumps(
        {'files': len(actual_names), 'checked': len(reports), 'failures': failures, 'snapshots': reports},
        indent=2) + '\n')
    require(not failures, '\n'.join(failures))
    return len(reports)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', nargs='?', default='build/fidelity-story-media')
    args = parser.parse_args()
    print(f'{verify_directory(args.folder)} Word story-media exports: PASS')


if __name__ == '__main__':
    main()

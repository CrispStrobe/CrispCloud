#!/usr/bin/env python3
"""Check retained altChunk order, scoped links and exact payload bytes.

Expected values come from independently authored XML/HTML and a committed JSON
fixture. This checker never invokes the Quds reader/writer or regenerates inputs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from corpus import FIXTURES, NS, R, W, read_zip, relationship_map, validate
from story_media_oracle import require, target

EXPECTED_NAMES = frozenset(
    f'altchunk-{state}-{cycle}.docx'
    for state in ('imported', 'moved') for cycle in range(1, 4))


def content_type(parts, name):
    root = ET.fromstring(parts['[Content_Types].xml'])
    overrides = {node.get('PartName').lstrip('/'): node.get('ContentType')
                 for node in root if node.tag.endswith('Override')}
    defaults = {node.get('Extension'): node.get('ContentType')
                for node in root if node.tag.endswith('Default')}
    return overrides.get(name, defaults.get(name.rsplit('.', 1)[-1]))


def sequence(parts, owner, parent):
    result = []
    for child in parent:
        if child.tag == f'{{{W}}}p':
            result.append('p:' + ''.join(node.text or '' for node in child.findall('.//w:t', NS)).strip())
        elif child.tag == f'{{{W}}}tbl':
            result.append('table')
        elif child.tag == f'{{{W}}}altChunk':
            rid = child.get(f'{{{R}}}id')
            row = relationship_map(parts, owner).get(rid)
            require(row is not None and row.get('Type') == R + '/aFChunk',
                    f'{owner}: altChunk relationship type or ID changed')
            name = target(parts, owner, rid=rid)
            properties = child.find('w:altChunkPr/w:matchSrc', NS)
            require(properties is not None and
                    properties.get(f'{{{W}}}val') == ('0' if name == 'payload/cell.html' else '1'),
                    f'{owner}: source-format properties changed for {name}')
            result.append('chunk:' + name)
    return result


def verify_document(parts, *, moved=False, edited=True):
    failures = validate(parts)
    require(not failures, '; '.join(failures))
    golden = json.loads((FIXTURES / 'altchunk_expected.json').read_text())
    main = target(parts, '', kind='officeDocument')
    note_owner = target(parts, main, kind='footnotes')
    body = ET.fromstring(parts[main]).find('w:body', NS)
    require(body is not None, 'Missing body')
    note = ET.fromstring(parts[note_owner]).find('w:footnote[@w:id="3"]', NS)
    require(note is not None, 'Missing note 3')
    cell = body.find('w:tbl/w:tr/w:tc', NS)
    require(cell is not None, 'Missing table cell')
    state = 'moved' if moved else 'imported'
    expected_body = list(golden[state + '_body_order'])
    expected_note = list(golden[state + '_note_order'])
    if not edited:
        expected_body[0] = 'p:Before opaque body'
        expected_note[2] = 'p:After opaque note'
    actual = {
        'body': sequence(parts, main, body),
        'cell': sequence(parts, main, cell),
        'note': sequence(parts, note_owner, note),
    }
    require(actual['body'] == expected_body, f'Body chunk order/owner changed: {actual["body"]}')
    require(actual['cell'] == golden['cell_order'], f'Cell chunk order changed: {actual["cell"]}')
    require(actual['note'] == expected_note, f'Note chunk order/owner changed: {actual["note"]}')
    require(len(body.findall('.//w:altChunk', NS)) == (3 if moved else 2), 'Wrong body chunk count')
    require(len(note.findall('.//w:altChunk', NS)) == (2 if moved else 1), 'Wrong note chunk count')
    payloads = {}
    for name, expected in golden['payloads'].items():
        require(name in parts, f'Missing opaque payload {name}')
        digest = hashlib.sha256(parts[name]).hexdigest()
        require(digest == expected['sha256'], f'Opaque payload bytes changed: {name}')
        require(content_type(parts, name) == expected['content_type'], f'Opaque payload content type changed: {name}')
        payloads[name] = digest
    actual['payloads'] = payloads
    return actual


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
            snapshots[name] = verify_document(read_zip(folder / name), moved=name.startswith('altchunk-moved'))
        except (AssertionError, KeyError, ValueError, ET.ParseError) as error:
            failures.append(f'{name}: {error}')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'altchunk-oracle-report.json').write_text(json.dumps(
        {'files': len(actual), 'checked': len(snapshots), 'failures': failures,
         'snapshots': snapshots}, indent=2) + '\n')
    require(not failures, '\n'.join(failures))
    return len(snapshots)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', nargs='?', default='build/fidelity-altchunk')
    args = parser.parse_args()
    print(f'{verify_directory(args.folder)} opaque-content exports: PASS')


if __name__ == '__main__':
    main()

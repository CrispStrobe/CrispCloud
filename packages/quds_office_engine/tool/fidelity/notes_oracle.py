#!/usr/bin/env python3
"""Independent rich-note XML, owner-relationship and decoded-pixel oracle."""
import hashlib
import json
from pathlib import Path
import posixpath
import re
import struct
import zlib
import xml.etree.ElementTree as ET
from corpus import read_zip, validate, relationship_map, links, attrs, word_text, NS, R


def pixels(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'note image is not PNG'
    offset, compressed, width, height, channels = 8, b'', 0, 0, 0
    while offset < len(data):
        size = struct.unpack('>I', data[offset:offset + 4])[0]
        kind, body = data[offset + 4:offset + 8], data[offset + 8:offset + 8 + size]
        if kind == b'IHDR':
            width, height, depth, color, *_ = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and color in (2, 6), 'unexpected PNG format'
            channels = 3 if color == 2 else 4
        if kind == b'IDAT': compressed += body
        offset += size + 12
    raw, previous, result = zlib.decompress(compressed), bytearray(width * channels), bytearray()
    for y in range(height):
        start = y * (width * channels + 1)
        filter_type, row = raw[start], bytearray(raw[start + 1:start + 1 + width * channels])
        for x in range(len(row)):
            a = row[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            if filter_type == 1: row[x] = (row[x] + a) & 255
            elif filter_type == 2: row[x] = (row[x] + b) & 255
            elif filter_type == 3: row[x] = (row[x] + (a + b) // 2) & 255
            elif filter_type == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[x] = (row[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
            else: assert filter_type == 0, 'unknown PNG filter'
        for x in range(width): result.extend(row[x * channels:x * channels + 3])
        previous = row
    return width, height, hashlib.sha256(result).hexdigest()


def snapshot(parts):
    owner = 'word/footnotes.xml'
    root = ET.fromstring(parts[owner])
    note = root.find("w:footnote[@w:id='12']", NS)
    assert note is not None, 'missing note 12'
    paras = [word_text(p).strip() for p in note.findall('w:p', NS)]
    run = next(r for r in note.findall('.//w:r', NS) if 'note' in ''.join(r.itertext()))
    rp = run.find('w:rPr', NS)
    blip = note.find('.//a:blip', NS)
    rel = relationship_map(parts, owner)[blip.get(f'{{{R}}}embed')]
    target = posixpath.normpath(posixpath.join('word', rel['Target']))
    return {
        'blocks': [e.tag.split('}')[-1] for e in note],
        'paragraphs': [p for p in paras if p],
        'leading_whitespace': re.match(r'^\s*', word_text(note.find('w:p', NS))).group(),
        'table': [''.join(e.itertext()).strip() for e in note.findall('.//w:tc', NS)],
        'bold': rp.find('w:b', NS) is not None and attrs(rp.find('w:b', NS)).get('val', '1') != '0',
        'color': attrs(rp.find('w:color', NS)).get('val'),
        'half_points': attrs(rp.find('w:sz', NS)).get('val'),
        'image': list(pixels(parts[target])),
        'extent': attrs(note.find('.//wp:extent', NS)),
        'links': [list(x) for x in links(parts, owner, note)],
    }


def main():
    folder = Path('build/fidelity-notes')
    files = sorted(folder.glob('*.docx'))
    assert len(files) == 7, f'Expected source plus six note exports, found {len(files)}'
    failures = []
    for path in files:
        expected = json.loads((Path('test/fixtures/fidelity') /
            ('notes_edited.json' if path.name.startswith('edited') else 'notes_imported.json')).read_text())
        parts = read_zip(path)
        actual = snapshot(parts)
        errors = validate(parts)
        if actual != expected: errors.append(f'expected {expected!r}, got {actual!r}')
        failures.extend(f'{path.name}: {e}' for e in errors)
        path.with_suffix('.actual.json').write_text(json.dumps(actual, indent=2) + '\n')
        print(f'{path.name}: {"FAIL" if errors else "PASS"}')
    (folder/'oracle-report.json').write_text(json.dumps({'files': len(files), 'failures': failures}, indent=2))
    if failures: raise SystemExit('\n'.join(failures))


if __name__ == '__main__': main()

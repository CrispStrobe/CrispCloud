"""Independent checks for replacement pixels and opaque body XML preservation."""
import hashlib
import json
from pathlib import Path
from xml.etree import ElementTree as E
from corpus import NS, R, read_zip, validate
from native_oracle import target
from notes_oracle import pixels


def verify_image(parts):
    root = E.fromstring(parts['word/document.xml'])
    blip = root.find('.//a:blip', NS)
    media = target(parts, 'word/document.xml', rid=blip.get('{'+R+'}embed'))
    assert pixels(parts[media]) == (6, 4, hashlib.sha256(bytes((20, 60, 210))*24).hexdigest())
    assert root.find('.//wp:extent', NS).attrib == {'cx': '457200', 'cy': '457200'}


def verify_opaque(parts):
    body = E.fromstring(parts['word/document.xml']).find('w:body', NS)
    assert [e.tag.split('}')[-1] for e in body] == ['p', 'altChunk', 'p', 'sectPr']
    assert ''.join(body[0].itertext()) == 'Edited before'
    assert ''.join(body[2].itertext()) == 'After'
    chunk = body.find('w:altChunk', NS)
    assert chunk.find('w:altChunkPr/w:matchSrc', NS).get('{'+NS['w']+'}val') == '0'
    html = target(parts, 'word/document.xml', rid=chunk.get('{'+R+'}id'))
    assert parts[html] == b'<html><body><p>Imported HTML payload</p></body></html>'


def main():
    failures = []
    count = 0
    for folder, verify in [('image', verify_image), ('opaque', verify_opaque)]:
        paths = sorted(Path('build/fidelity-'+folder).glob('*.docx'))
        assert len(paths) == 3, f'Expected three {folder} exports, got {len(paths)}'
        for path in paths:
            count += 1
            try:
                parts = read_zip(path)
                errors = validate(parts)
                assert not errors, errors
                verify(parts)
                print(f'{path.name}: PASS')
            except Exception as error:
                failures.append(f'{path}: {error}')
    Path('build/fidelity-edge-report.json').write_text(json.dumps({'files': count, 'failures': failures}, indent=2)+'\n')
    if failures:
        raise SystemExit('\n'.join(failures))


if __name__ == '__main__':
    main()

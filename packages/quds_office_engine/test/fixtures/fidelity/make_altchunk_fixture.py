#!/usr/bin/env python3
"""Author an altChunk DOCX with colliding story-local IDs, without Quds."""
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

HERE = Path(__file__).resolve().parent
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PKG = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'application/vnd.openxmlformats-officedocument.wordprocessingml.'


def paragraph(text):
    return f'<w:p><w:r><w:t>{text}</w:t></w:r></w:p>'


def chunk(rid, match='1'):
    return (f'<w:altChunk r:id="{rid}"><w:altChunkPr>'
            f'<w:matchSrc w:val="{match}"/></w:altChunkPr></w:altChunk>')


def rels(rows):
    return f'<Relationships xmlns="{PKG}">' + ''.join(
        f'<Relationship Id="{rid}" Type="{R}/{kind}" Target="{target}"/>'
        for rid, kind, target in rows) + '</Relationships>'


def generate():
    payloads = {
        'payload/body.html': b'<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><h1>ALT_BODY_PAYLOAD</h1><p>Preserve body content exactly.</p></body></html>\n',
        'payload/cell.html': b'<!DOCTYPE html><html><body><p><b>ALT_CELL_PAYLOAD</b>: preserve table content.</p></body></html>\n',
        'payload/note.html': b'<!DOCTYPE html><html><body><p>ALT_NOTE_PAYLOAD: preserve note content.</p></body></html>\n',
    }
    body_chunk = (f'<s:altChunk xmlns:s="{W}" xmlns:link="{R}" link:id="chunk">'
                  '<s:altChunkPr><s:matchSrc s:val="1"/></s:altChunkPr></s:altChunk>')
    parts = dict(payloads)
    parts.update({
        'word/document.xml': (
            f'<w:document xmlns:w="{W}" xmlns:r="{R}"><w:body>'
            + paragraph('Before opaque body') + body_chunk + paragraph('After opaque body')
            + '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="5000"/></w:tblGrid>'
              '<w:tr><w:tc><w:tcPr><w:tcW w:w="5000" w:type="dxa"/></w:tcPr>'
            + paragraph('Before opaque cell') + chunk('tableChunk', '0') + paragraph('After opaque cell')
            + '</w:tc></w:tr></w:tbl>'
              '<w:p><w:r><w:t>Reference note</w:t></w:r><w:r><w:footnoteReference w:id="3"/></w:r></w:p>'
              '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
              '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
              'w:header="720" w:footer="720"/></w:sectPr></w:body></w:document>'),
        'word/footnotes.xml': (
            f'<w:footnotes xmlns:w="{W}" xmlns:r="{R}"><w:footnote w:id="3">'
            '<w:p><w:r><w:footnoteRef/></w:r><w:r><w:t>Before opaque note</w:t></w:r></w:p>'
            + chunk('chunk') + paragraph('After opaque note') + '</w:footnote></w:footnotes>'),
        'word/_rels/document.xml.rels': rels([
            ('chunk', 'aFChunk', '../payload/body.html'),
            ('tableChunk', 'aFChunk', '../payload/cell.html'),
            ('notes', 'footnotes', 'footnotes.xml'),
        ]),
        'word/_rels/footnotes.xml.rels': rels([
            ('chunk', 'aFChunk', '../payload/note.html'),
        ]),
        '_rels/.rels': rels([('main', 'officeDocument', 'word/document.xml')]),
        '[Content_Types].xml': (
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Default Extension="html" ContentType="text/html"/>'
            f'<Override PartName="/word/document.xml" ContentType="{CT}document.main+xml"/>'
            f'<Override PartName="/word/footnotes.xml" ContentType="{CT}footnotes+xml"/>'
            '</Types>'),
    })
    with ZipFile(HERE / 'word-altchunk.docx', 'w') as archive:
        for name, content in sorted(parts.items()):
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            archive.writestr(info, content.encode() if isinstance(content, str) else content)
    expected = {
        'payloads': {name: {'sha256': hashlib.sha256(payload).hexdigest(), 'content_type': 'text/html'}
                     for name, payload in payloads.items()},
        'imported_body_order': ['p:Edited before body', 'chunk:payload/body.html', 'p:After opaque body', 'table', 'p:Reference note'],
        'moved_body_order': ['p:Edited before body', 'chunk:payload/note.html', 'p:After opaque body', 'table', 'p:Reference note', 'chunk:payload/body.html'],
        'cell_order': ['p:Before opaque cell', 'chunk:payload/cell.html', 'p:After opaque cell'],
        'imported_note_order': ['p:Before opaque note', 'chunk:payload/note.html', 'p:Edited after note'],
        'moved_note_order': ['p:Before opaque note', 'chunk:payload/body.html', 'p:Edited after note', 'chunk:payload/cell.html'],
    }
    (HERE / 'altchunk_expected.json').write_text(json.dumps(expected, indent=2) + '\n')


if __name__ == '__main__':
    generate()

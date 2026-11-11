#!/usr/bin/env python3
"""Author a story-media DOCX independently of the Quds reader/writer.

Normal tests use the committed input. Run explicitly after reviewing fixture
changes. PNG scanlines and all Office XML are authored here, using stdlib only.
"""
from pathlib import Path
import struct
import zlib
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

HERE = Path(__file__).resolve().parent
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PKG = 'http://schemas.openxmlformats.org/package/2006/relationships'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
WP = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
PIC = 'http://schemas.openxmlformats.org/drawingml/2006/picture'
CT = 'application/vnd.openxmlformats-officedocument.wordprocessingml.'
NS = f'xmlns:w="{W}" xmlns:r="{R}" xmlns:wp="{WP}" xmlns:a="{A}" xmlns:pic="{PIC}"'
COLORS = [(255, 0, 0), (0, 128, 0), (0, 0, 255), (255, 255, 0),
          (0, 255, 255), (255, 0, 255), (255, 165, 0), (128, 0, 128)]


def png(rgb):
    def chunk(kind, payload):
        data = kind + payload
        return struct.pack('>I', len(payload)) + data + struct.pack('>I', zlib.crc32(data))
    raw = (b'\0' + bytes(rgb) * 2) * 2
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def rels(rows):
    return f'<Relationships xmlns="{PKG}">' + ''.join(
        f'<Relationship Id="{rid}" Type="{R}/{kind}" Target="{target}"/>'
        for rid, kind, target in rows) + '</Relationships>'


def picture(rid, name, width=36, height=18):
    cx, cy = width * 12700, height * 12700
    return (f'<w:p><w:r><w:drawing><wp:inline><wp:extent cx="{cx}" cy="{cy}"/>'
            f'<wp:docPr id="1" name="{name}"/><a:graphic><a:graphicData uri="{PIC}">'
            f'<pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="{name}"/><pic:cNvPicPr/>'
            f'</pic:nvPicPr><pic:blipFill><a:blip r:embed="{rid}"/>'
            '<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr>'
            f'<a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
            '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')


def generate():
    parts = {}
    overrides = {'word/document.xml': 'document.main+xml',
                 'word/footnotes.xml': 'footnotes+xml',
                 'word/settings.xml': 'settings+xml'}
    main_rels = [('bodyImage', 'image', 'media/body.png'),
                 ('bodyImage2', 'image', 'media/image2.png'),
                 ('notes', 'footnotes', 'footnotes.xml'),
                 ('settings', 'settings', 'settings.xml')]
    refs = []
    for i, (kind, variant) in enumerate([
        ('header', 'default'), ('footer', 'default'), ('header', 'first'),
        ('footer', 'first'), ('header', 'even'), ('footer', 'even'),
    ]):
        part = f'{kind}{11 + i}.xml'
        rid = f'story{i}'
        label = f'{variant} {kind}'
        main_rels.append((rid, kind, part))
        refs.append(f'<w:{kind}Reference w:type="{variant}" r:id="{rid}"/>')
        image = 'image1.png' if i == 0 else f'story{i}.png'
        parts[f'word/media/{image}'] = png(COLORS[i + 1])
        root = 'hdr' if kind == 'header' else 'ftr'
        parts[f'word/{part}'] = f'<w:{root} {NS}>' + picture('localImage', label) + f'</w:{root}>'
        parts[f'word/_rels/{part}.rels'] = rels([('localImage', 'image', f'media/{image}')])
        overrides[f'word/{part}'] = f'{kind}+xml'
    parts['word/media/body.png'] = png(COLORS[0])
    parts['word/media/image2.png'] = png(COLORS[7])
    parts['word/media/note.png'] = png(COLORS[2])
    parts['word/document.xml'] = (f'<w:document {NS}><w:body>'
        '<w:p><w:r><w:t>Story media fixture</w:t></w:r>'
        '<w:r><w:footnoteReference w:id="3"/></w:r></w:p>'
        + picture('bodyImage', 'body picture') + picture('bodyImage2', 'body second')
        + '<w:sectPr>' + ''.join(sorted(refs, key=lambda ref: 'footerReference' in ref))
        + '<w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" '
          'w:bottom="1440" w:left="1440" w:header="720" w:footer="720"/>'
          '<w:titlePg/></w:sectPr></w:body></w:document>')
    parts['word/_rels/document.xml.rels'] = rels(main_rels)
    parts['word/settings.xml'] = f'<w:settings xmlns:w="{W}"><w:evenAndOddHeaders/></w:settings>'
    parts['word/footnotes.xml'] = (f'<w:footnotes {NS}><w:footnote w:id="3">'
        '<w:p><w:r><w:footnoteRef/></w:r><w:r><w:t>Note picture</w:t></w:r></w:p>'
        + picture('localImage', 'note picture') + '</w:footnote></w:footnotes>')
    parts['word/_rels/footnotes.xml.rels'] = rels([('localImage', 'image', 'media/note.png')])
    parts['customXml/consumer.xml'] = ('<consumer xmlns="urn:independent:consumer" '
        f'xmlns:r="{R}"><image r:id="sharedImage"/><chart r:id="sharedChart"/></consumer>')
    parts['customXml/_rels/consumer.xml.rels'] = rels([
        ('sharedImage', 'image', '../word/media/image1.png'),
        ('sharedChart', 'chart', '../word/charts/chart1.xml'),
    ])
    parts['word/charts/chart1.xml'] = '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:layout/></c:plotArea></c:chart></c:chartSpace>'
    parts['_rels/.rels'] = rels([('office', 'officeDocument', 'word/document.xml')])
    parts['[Content_Types].xml'] = (
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        + ''.join(f'<Override PartName="/{part}" ContentType="{CT}{kind}"/>'
                  for part, kind in overrides.items())
        + '<Override PartName="/word/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>')
    with ZipFile(HERE / 'story-media.docx', 'w', compression=ZIP_DEFLATED) as archive:
        for name, content in sorted(parts.items()):
            info = ZipInfo(name, date_time=(2000, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            archive.writestr(info, content.encode() if isinstance(content, str) else content)


if __name__ == '__main__':
    generate()

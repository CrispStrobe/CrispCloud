#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Author independent minimal OOXML image appearance controls."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import struct
import zlib

CASES = {
    'inline-horizontal': {'inline': True, 'flipH': True},
    'floating-control': {},
    'floating-horizontal': {'flipH': True},
    'floating-vertical': {'flipV': True},
    'floating-both': {'flipH': True, 'flipV': True},
    'floating-quarter': {'rotation': 90},
    'floating-negative-quarter': {'rotation': 270},
    'floating-margin-quarter': {'rotation': 90, 'origin': 'margin', 'x': -360000, 'y': -180000},
    'floating-outline-shadow': {'paint': True},
}


def quadrants_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    colors = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0))
    rows = bytearray()
    for y in range(40):
        rows.append(0)
        for x in range(80):
            rows.extend(colors[(2 if y >= 20 else 0) + (1 if x >= 40 else 0)])
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 80, 40, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


def write_case(path, case):
    xfrm = ''.join(f' {name}="1"' for name in ('flipH', 'flipV') if case.get(name))
    if case.get('rotation'):
        xfrm += f' rot="{case["rotation"] * 60000}"'
    paint = ''
    if case.get('paint'):
        paint = ('<a:ln w="25400" cap="flat"><a:solidFill><a:srgbClr val="FF00FF"/>'
                 '</a:solidFill><a:prstDash val="sysDot"/><a:round/></a:ln>'
                 '<a:effectLst><a:outerShdw blurRad="0" dist="63500" dir="3187806" '
                 'algn="ctr" rotWithShape="0"><a:srgbClr val="445566"><a:alpha val="50000"/>'
                 '</a:srgbClr></a:outerShdw></a:effectLst>')
    graphic = ('<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
               '<pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="Quadrant control"/><pic:cNvPicPr/>'
               '</pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImage"/><a:stretch><a:fillRect/>'
               '</a:stretch></pic:blipFill><pic:spPr><a:xfrm' + xfrm + '><a:off x="0" y="0"/>'
               '<a:ext cx="914400" cy="457200"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/>'
               '</a:prstGeom>' + paint + '</pic:spPr></pic:pic></a:graphicData></a:graphic>')
    extent = '<wp:extent cx="914400" cy="457200"/>'
    info = '<wp:docPr id="1" name="Independent control"/><wp:cNvGraphicFramePr/>'
    if case.get('inline'):
        drawing = '<wp:inline distT="0" distB="0" distL="0" distR="0">' + extent + info + graphic + '</wp:inline>'
    else:
        origin = case.get('origin', 'page')
        drawing = ('<wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" '
                   'relativeHeight="1" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
                   '<wp:simplePos x="0" y="0"/>'
                   f'<wp:positionH relativeFrom="{origin}"><wp:posOffset>{case.get("x", 914400)}</wp:posOffset></wp:positionH>'
                   f'<wp:positionV relativeFrom="{origin}"><wp:posOffset>{case.get("y", 914400)}</wp:posOffset></wp:positionV>'
                   + extent + '<wp:wrapNone/>' + info + graphic + '</wp:anchor>')
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
                'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
                'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
                'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
                '<w:body><w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:drawing>'
                + drawing + '</w:drawing></w:r></w:p><w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
                '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="0" '
                'w:footer="0" w:gutter="0"/></w:sectPr></w:body></w:document>')
    parts = {
        '[Content_Types].xml': ('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                               '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                               '<Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" '
                               'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'),
        '_rels/.rels': ('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                       '<Relationship Id="rIdDocument" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
                       'Target="word/document.xml"/></Relationships>'),
        'word/document.xml': document,
        'word/_rels/document.xml.rels': ('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                                       '<Relationship Id="rIdImage" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
                                       'Target="media/quadrants.png"/></Relationships>'),
        'word/media/quadrants.png': quadrants_png(),
    }
    with ZipFile(path, 'w') as package:
        for name, data in parts.items():
            info = ZipInfo(name, date_time=(2000, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            package.writestr(info, data)


def write_cases(output):
    output.mkdir(parents=True, exist_ok=False)
    for name, case in CASES.items():
        write_case(output / (name + '.docx'), case)

#!/usr/bin/env python3
"""Author Word compatibility/section inputs independently of the Quds engine.

The committed DOCX and semantic expectations are test inputs. Normal checks do
not invoke this generator or derive expectations from the engine's output.
"""
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

HERE = Path(__file__).resolve().parent
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
MC = 'http://schemas.openxmlformats.org/markup-compatibility/2006'
PKG = 'http://schemas.openxmlformats.org/package/2006/relationships'
FUTURE = 'urn:independently-authored:unsupported-word-feature'
NS = f'xmlns:w="{W}" xmlns:r="{R}" xmlns:mc="{MC}" xmlns:alias="{W}" xmlns:future="{FUTURE}"'
CT = 'application/vnd.openxmlformats-officedocument.wordprocessingml.'


def paragraph(text):
    return f'<w:p><w:r><w:t xml:space="preserve">{text}</w:t></w:r></w:p>'


def alternate(choices, fallback=None):
    return ('<mc:AlternateContent>' + ''.join(
        f'<mc:Choice Requires="{requires}">{content}</mc:Choice>'
        for requires, content in choices)
        + (f'<mc:Fallback>{fallback}</mc:Fallback>' if fallback is not None else '')
        + '</mc:AlternateContent>')


def rels(rows):
    return f'<Relationships xmlns="{PKG}">' + ''.join(
        f'<Relationship Id="{rid}" Type="{R}/{kind}" Target="{target}"/>'
        for rid, kind, target in rows) + '</Relationships>'


def generate():
    body = alternate([
        ('future', paragraph('UNSELECTED unsupported body')),
        ('alias', paragraph('Selected supported body')),
        ('w', paragraph('UNSELECTED later supported choice')),
    ], paragraph('UNSELECTED body fallback'))
    body += alternate([
        ('alias future', paragraph('UNSELECTED partially supported choice')),
    ], paragraph('Selected fallback body'))
    body += alternate([
        ('alias', alternate([
            ('future', paragraph('UNSELECTED nested choice')),
        ], paragraph('Selected nested fallback'))),
    ], paragraph('UNSELECTED outer fallback'))
    body += ('<w:p><w:r><w:t xml:space="preserve">Before </w:t></w:r>'
             + alternate([('future', '<w:r><w:t>UNSELECTED inline</w:t></w:r>')],
                         '<w:r><w:t>selected inline</w:t></w:r>')
             + '<w:r><w:t xml:space="preserve"> after</w:t></w:r></w:p>')
    body += '<w:p><w:r>' + alternate([
        ('future', '<w:t>UNSELECTED run</w:t>'),
    ], '<w:t>Selected run fallback</w:t>') + '</w:r></w:p>'
    body += alternate([('future', paragraph('UNSELECTED without fallback'))])
    body += ('<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="1200"/></w:tblGrid>'
             '<w:tr><w:tc><w:tcPr><w:tcW w:w="1200" w:type="dxa"/></w:tcPr>'
             + alternate([('future', paragraph('UNSELECTED table'))],
                         paragraph('Selected table fallback'))
             + '</w:tc></w:tr></w:tbl>')
    first_section = (
        '<w:sectPr w:rsidR="00112233" w:rsidSect="44556677">'
        '<w:headerReference w:type="default" r:id="headerDefault"/>'
        '<w:headerReference w:type="first" r:id="headerFirst"/>'
        '<w:footnotePr><w:numFmt w:val="lowerRoman"/><w:numStart w:val="4"/>'
        '<w:numRestart w:val="eachSect"/></w:footnotePr>'
        '<w:type w:val="continuous"/>'
        '<w:pgSz w:w="15840" w:h="12240" w:orient="landscape" w:code="9"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
        'w:header="720" w:footer="720" w:gutter="240"/>'
        '<w:paperSrc w:first="256" w:other="257"/>'
        '<w:pgBorders w:offsetFrom="page"><w:top w:val="single" w:sz="4" '
        'w:space="12" w:color="884422"/></w:pgBorders>'
        '<w:lnNumType w:countBy="5" w:start="3" w:distance="240" w:restart="newSection"/>'
        '<w:pgNumType w:fmt="upperRoman" w:start="17" w:chapStyle="2" w:chapSep="colon"/>'
        '<w:cols w:num="2" w:space="600" w:sep="1" w:equalWidth="0">'
        '<w:col w:w="3000" w:space="600"/><w:col w:w="3600" w:space="0"/></w:cols>'
        '<w:formProt w:val="true"/><w:vAlign w:val="center"/><w:noEndnote/>'
        '<w:titlePg/><w:textDirection w:val="lrTb"/><w:bidi/><w:rtlGutter/>'
        '<w:docGrid w:type="lines" w:linePitch="360" w:charSpace="0"/>'
        '<w:sectPrChange w:author="Independent Fixture" w:date="2026-01-01T00:00:00Z" w:id="7">'
        '<w:sectPr><w:pgSz w:w="20000" w:h="25000"/><w:pgNumType w:start="99"/>'
        '</w:sectPr></w:sectPrChange></w:sectPr>')
    body += ('<w:p><w:pPr>' + first_section + '</w:pPr>'
             '<w:r><w:t>First section ending</w:t></w:r></w:p>')
    body += ('<w:p><w:r><w:t>Second section text</w:t></w:r>'
             '<w:r><w:footnoteReference w:id="3"/></w:r></w:p>')
    last_section = (
        f'<n:sectPr xmlns:n="{W}" n:rsidR="AABBCCDD">'
        '<n:type n:val="oddPage"/><n:pgSz n:w="12240" n:h="15840" n:code="9"/>'
        '<n:pgMar n:top="1200" n:right="1200" n:bottom="1200" n:left="1200" '
        'n:header="600" n:footer="600" n:gutter="120"/>'
        '<n:lnNumType n:countBy="2" n:restart="continuous"/>'
        '<n:pgNumType n:fmt="decimal" n:start="31"/>'
        '<n:cols n:num="1" n:space="720"/><n:titlePg n:val="0"/>'
        '<n:docGrid n:type="linesAndChars" n:linePitch="400" n:charSpace="100"/>'
        '</n:sectPr>')
    parts = {
        'word/document.xml': f'<w:document {NS}><w:body>{body}{last_section}</w:body></w:document>',
        'word/header-compat.xml': f'<w:hdr {NS}>' + alternate([
            ('future', paragraph('UNSELECTED header')),
        ], paragraph('Selected header fallback')) + '</w:hdr>',
        'word/header-first.xml': f'<w:hdr {NS}>' + paragraph('First page header retained') + '</w:hdr>',
        'word/footnotes.xml': f'<w:footnotes {NS}><w:footnote w:id="3">' + alternate([
            ('future', paragraph('UNSELECTED footnote')),
            ('alias', paragraph('Selected supported footnote').replace(
                '<w:p>', '<w:p><w:r><w:footnoteRef/></w:r>', 1)),
        ], paragraph('UNSELECTED footnote fallback')) + '</w:footnote></w:footnotes>',
        'word/_rels/document.xml.rels': rels([
            ('headerDefault', 'header', 'header-compat.xml'),
            ('headerFirst', 'header', 'header-first.xml'),
            ('notes', 'footnotes', 'footnotes.xml'),
        ]),
        '_rels/.rels': rels([('main', 'officeDocument', 'word/document.xml')]),
    }
    overrides = {
        'word/document.xml': 'document.main+xml',
        'word/header-compat.xml': 'header+xml',
        'word/header-first.xml': 'header+xml',
        'word/footnotes.xml': 'footnotes+xml',
    }
    parts['[Content_Types].xml'] = (
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        + ''.join(f'<Override PartName="/{name}" ContentType="{CT}{content_type}"/>'
                  for name, content_type in overrides.items()) + '</Types>')
    with ZipFile(HERE / 'word-compatibility.docx', 'w') as archive:
        for name, text in sorted(parts.items()):
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            archive.writestr(info, text.encode('utf-8'))
    expected = {
        'body_paragraphs': ['Selected supported body', 'Selected fallback body',
                            'Selected nested fallback', 'Before selected inline after',
                            'Selected run fallback', 'Selected table fallback',
                            'First section ending', 'Second section text3'],
        'default_header': 'Selected header fallback',
        'first_header': 'First page header retained',
        'footnote': 'Selected supported footnote',
        'page_number_starts': ['17', '31'],
        'grid_line_pitches': ['360', '400'],
        'grid_types': ['lines', 'linesAndChars'],
        'gutters': ['240', '120'],
        'paper_codes': ['9', '9'],
    }
    (HERE / 'word_compatibility_expected.json').write_text(json.dumps(expected, indent=2) + '\n')


if __name__ == '__main__':
    generate()

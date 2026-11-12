#!/usr/bin/env python3
"""Author bookmark endpoint specimens directly as OPC and OOXML."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'


def run(text):
    return f'<w:r><w:t xml:space="preserve">{text}</w:t></w:r>'


def start(identifier, name, extra=''):
    return f'<b:bookmarkStart b:id="{identifier}" b:name="{name}" {extra}/>'


def end(identifier):
    return f'<b:bookmarkEnd b:id="{identifier}"/>'


def paragraph(contents):
    return f'<w:p>{contents}</w:p>'


BODY = ''.join([
    paragraph(run('Probe prefix')),
    paragraph(start(10, 'Alpha') + run('Alpha') + end(10) + run(' ') +
              start(11, 'Beta') + '<w:r><w:rPr><w:b/><w:color w:val="345678"/></w:rPr><w:t>Beta</w:t></w:r>' + end(11)),
    paragraph(start(12, 'AcrossParagraphs') + run('Cross-paragraph start')),
    paragraph(run('Cross-paragraph end') + end(12)),
    paragraph(start(20, 'OverlapA') + run('A') + start(21, 'OverlapB') + run('BC') +
              end(20) + run('D') + end(21) + start(22, 'Cursor') + end(22)),
    paragraph('<w:hyperlink w:anchor="Beta">' + start(23, 'Linked') + run('Link') + end(23) + '</w:hyperlink>'),
    '<w:tbl><w:tblPr><w:tblW w:w="2400" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid><w:tr><w:tc>' +
    paragraph(start(30, 'TableCell', 'b:colFirst="0" b:colLast="0"') + run('Cell text') + end(30)) +
    '</w:tc></w:tr></w:tbl>',
    paragraph(run('Notes ') + '<w:r><w:footnoteReference w:id="7"/></w:r><w:r><w:endnoteReference w:id="8"/></w:r>'),
])

STORIES = [('header', 'default'), ('footer', 'default'), ('header', 'first'),
           ('footer', 'first'), ('header', 'even'), ('footer', 'even')]
PARTS = {}
overrides = ['<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>']
relationships = []
references = []
for index, (kind, variant) in enumerate(STORIES, 1):
    stem = f'{kind}{index}'
    label = f'{variant}_{kind}'
    tag = 'hdr' if kind == 'header' else 'ftr'
    PARTS[f'word/{stem}.xml'] = f'<w:{tag} xmlns:w="{W}" xmlns:b="{W}">' + paragraph(
        start(100, label) + run(label) + end(100)) + f'</w:{tag}>'
    overrides.append(f'<Override PartName="/word/{stem}.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.{kind}+xml"/>')
    relationships.append(f'<Relationship Id="{stem}" Type="{R}/{kind}" Target="{stem}.xml"/>')
    references.append(f'<w:{kind}Reference w:type="{variant}" r:id="{stem}"/>')
for kind, identifier, bookmark_id, label in [('footnote', 7, 40, 'FootnoteRange'), ('endnote', 8, 50, 'EndnoteRange')]:
    PARTS[f'word/{kind}s.xml'] = f'<w:{kind}s xmlns:w="{W}" xmlns:b="{W}"><w:{kind} w:id="{identifier}">' + paragraph(
        f'<w:r><w:{kind}Ref/></w:r>' + start(bookmark_id, label) + run(label) + end(bookmark_id)) + f'</w:{kind}></w:{kind}s>'
    overrides.append(f'<Override PartName="/word/{kind}s.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.{kind}s+xml"/>')
    relationships.append(f'<Relationship Id="{kind}s" Type="{R}/{kind}s" Target="{kind}s.xml"/>')
PARTS['word/document.xml'] = f'<w:document xmlns:w="{W}" xmlns:b="{W}" xmlns:r="{R}"><w:body>{BODY}<w:sectPr>' + ''.join(references) + '<w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/><w:titlePg/></w:sectPr></w:body></w:document>'
PARTS['word/_rels/document.xml.rels'] = f'<Relationships xmlns="{REL}">' + ''.join(relationships) + '</Relationships>'
PARTS['_rels/.rels'] = f'<Relationships xmlns="{REL}"><Relationship Id="main" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>'
PARTS['[Content_Types].xml'] = f'<Types xmlns="{CT}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>' + ''.join(overrides) + '</Types>'


def main():
    target = Path(__file__).with_name('bookmarks.docx')
    with ZipFile(target, 'w') as archive:
        for name, text in PARTS.items():
            info = ZipInfo(name, date_time=(2026, 1, 2, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            archive.writestr(info, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + text)
    print(target)


if __name__ == '__main__':
    main()

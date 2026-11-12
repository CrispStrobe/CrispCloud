#!/usr/bin/env python3
"""Author automatic note-body marker cases directly as OPC/OOXML."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
SUPER = '<w:rPr><w:vertAlign w:val="superscript"/></w:rPr>'
COLOR = '<w:rPr><w:color w:val="123456"/></w:rPr>'
BOLD_SUB = '<w:rPr><w:b/><w:color w:val="445566"/><w:vertAlign w:val="subscript"/></w:rPr>'


def paragraph(text):
    return f'<w:p><w:r><w:t xml:space="preserve">{text}</w:t></w:r></w:p>'


FOOTNOTES = f'''<w:footnotes xmlns:w="{W}">
  <w:footnote w:id="11"><w:p><w:r>{SUPER}<w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> Conventional footnote</w:t></w:r></w:p></w:footnote>
  <w:footnote w:id="12">{paragraph('Unmarked footnote')}</w:footnote>
  <w:footnote w:id="13"><w:p><w:r>{COLOR}<w:t xml:space="preserve">Before </w:t><w:footnoteRef/><w:t xml:space="preserve"> after</w:t></w:r></w:p></w:footnote>
  <w:footnote w:id="14">{paragraph('Opening paragraph')}<w:p><w:r><w:footnoteRef/></w:r><w:r><w:t>Later paragraph</w:t></w:r></w:p></w:footnote>
  <w:footnote w:id="15"><w:p><w:r><w:footnoteRef/><w:t xml:space="preserve"> first </w:t><w:footnoteRef/></w:r><w:r>{BOLD_SUB}<w:t xml:space="preserve"> second </w:t><w:footnoteRef/><w:t>tail</w:t></w:r></w:p></w:footnote>
  <w:footnote w:id="16"><w:tbl><w:tblPr><w:tblW w:w="2400" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t xml:space="preserve">Table before </w:t><w:footnoteRef/><w:t xml:space="preserve"> tail</w:t></w:r></w:p></w:tc></w:tr></w:tbl>{paragraph('After note table')}</w:footnote>
</w:footnotes>'''

ENDNOTES = f'''<w:endnotes xmlns:w="{W}">
  <w:endnote w:id="31"><w:p><w:r>{SUPER}<w:endnoteRef/></w:r><w:r><w:t xml:space="preserve"> Conventional endnote</w:t></w:r></w:p></w:endnote>
  <w:endnote w:id="32">{paragraph('Unmarked endnote')}</w:endnote>
  <w:endnote w:id="33"><w:p><w:r>{COLOR}<w:t xml:space="preserve">End before </w:t><w:endnoteRef/><w:t xml:space="preserve"> middle </w:t><w:endnoteRef/><w:t>tail</w:t></w:r></w:p></w:endnote>
</w:endnotes>'''

REFERENCES = ''.join(
    f'<w:r>{SUPER}<w:{kind}Reference w:id="{identifier}"/></w:r>'
    for kind, identifiers in [('footnote', range(11, 17)), ('endnote', range(31, 34))]
    for identifier in identifiers)

PARTS = {
    '[Content_Types].xml': f'''<Types xmlns="{CT}">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
      <Override PartName="/word/endnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml"/>
    </Types>''',
    '_rels/.rels': f'<Relationships xmlns="{REL}"><Relationship Id="main" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels': f'''<Relationships xmlns="{REL}">
      <Relationship Id="footnotes" Type="{R}/footnotes" Target="footnotes.xml"/>
      <Relationship Id="endnotes" Type="{R}/endnotes" Target="endnotes.xml"/>
    </Relationships>''',
    'word/document.xml': f'''<w:document xmlns:w="{W}"><w:body>
      {paragraph('Authored automatic note markers')}
      <w:p><w:r><w:t xml:space="preserve">References </w:t></w:r>{REFERENCES}</w:p>
      <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
    </w:body></w:document>''',
    'word/footnotes.xml': FOOTNOTES,
    'word/endnotes.xml': ENDNOTES,
}


def main():
    target = Path(__file__).with_name('note-markers.docx')
    with ZipFile(target, 'w') as package:
        for name, text in PARTS.items():
            info = ZipInfo(name, date_time=(2026, 1, 2, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            package.writestr(info, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + text)
    print(target)


if __name__ == '__main__':
    main()

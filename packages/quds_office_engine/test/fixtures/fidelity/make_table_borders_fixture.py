#!/usr/bin/env python3
"""Author absent, inherited, and explicit nil table borders without Quds."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
EDGES = ('top', 'left', 'bottom', 'right', 'insideH', 'insideV')


def borders(value, color=None, size=None):
    return '<w:tblBorders>' + ''.join(
        f'<w:{edge} w:val="{value}"'
        + (f' w:color="{color}"' if color else '')
        + (f' w:sz="{size}"' if size else '') + '/>' for edge in EDGES) + '</w:tblBorders>'


def table(label, props, width=3600):
    return (f'<w:tbl><w:tblPr>{props}</w:tblPr><w:tblGrid><w:gridCol w:w="{width}"/>'
            f'</w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>{label}</w:t></w:r>'
            '</w:p></w:tc></w:tr></w:tbl>')


WIDTH = '<w:tblW w:w="3600" w:type="dxa"/>'
RETAINED = WIDTH + '<w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="80" w:type="dxa"/></w:tblCellMar><w:tblCaption w:val="Retained caption"/>'
PARTS = {
    '[Content_Types].xml': f'''<Types xmlns="{CT}">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      <Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
    </Types>''',
    '_rels/.rels': f'<Relationships xmlns="{REL}"><Relationship Id="main" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels': f'''<Relationships xmlns="{REL}">
      <Relationship Id="styles" Type="{R}/styles" Target="styles.xml"/>
      <Relationship Id="notes" Type="{R}/footnotes" Target="footnotes.xml"/>
    </Relationships>''',
    'word/document.xml': f'''<w:document xmlns:w="{W}" xmlns:r="{R}"><w:body>
      <w:p><w:r><w:t>Authored table border cases</w:t></w:r><w:r><w:footnoteReference w:id="12"/></w:r></w:p>
      {table('Unbordered body table', RETAINED)}
      {table('Inherited table borders', '<w:tblStyle w:val="ReviewGrid"/>' + WIDTH)}
      {table('Explicitly hidden borders', '<w:tblStyle w:val="ReviewGrid"/>' + WIDTH + borders('nil'))}
      <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
    </w:body></w:document>''',
    'word/styles.xml': f'''<w:styles xmlns:w="{W}"><w:style w:type="table" w:styleId="ReviewGrid">
      <w:name w:val="Authored review grid"/><w:tblPr>{borders('single', 'CC0000', '8')}</w:tblPr>
    </w:style></w:styles>''',
    'word/footnotes.xml': f'''<w:footnotes xmlns:w="{W}"><w:footnote w:id="12">
      <w:p><w:r><w:footnoteRef/></w:r><w:r><w:t>Note table follows</w:t></w:r></w:p>
      {table('Unbordered note table', '<w:tblW w:w="2000" w:type="dxa"/>', 2000)}
    </w:footnote></w:footnotes>''',
}


def main():
    target = Path(__file__).with_name('table-borders.docx')
    with ZipFile(target, 'w') as package:
        for name, text in PARTS.items():
            info = ZipInfo(name, date_time=(2026, 1, 2, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            package.writestr(info, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + text)
    print(target)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Author editable native SDT controls and independent expectations without Quds."""
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'


def run(text):
    return f'<w:r><w:t xml:space="preserve">{text}</w:t></w:r>'


def paragraph(text):
    return f'<w:p>{run(text)}</w:p>'


def control(identifier, alias, tag, content, color='4488AA'):
    body = '' if content is None else f'<w:sdtContent>{content}</w:sdtContent>'
    return (f'<w:sdt><w:sdtPr><w:alias w:val="{alias}"/>'
            f'<w:tag w:val="{tag}"/><w:id w:val="{identifier}"/><w:richText/>'
            f'</w:sdtPr><w:sdtEndPr><w:rPr><w:color w:val="{color}"/>'
            f'</w:rPr></w:sdtEndPr>{body}</w:sdt>')


INLINE = control(201, 'Customer value', 'customer.value', run('Alpha'))
NESTED = control(102, 'Nested block', 'nested.block', paragraph('Nested Beta'))
CELL = control(103, 'Cell block', 'cell.block', paragraph('Cell Gamma'))
TABLE = ('<w:tbl><w:tblPr><w:tblW w:w="3600" w:type="dxa"/></w:tblPr>'
         '<w:tblGrid><w:gridCol w:w="3600"/></w:tblGrid><w:tr><w:tc>'
         + CELL + '</w:tc></w:tr></w:tbl>')
OUTER = control(101, 'Customer details', 'customer.info',
                '<w:p>' + run('Customer ') + INLINE + run(' tail') + '</w:p>' + NESTED + TABLE)
EMPTY = control(104, 'Empty block', 'empty.block', '')
ABSENT = control(105, 'Absent slot', 'absent.block', None)
INLINE_PARAGRAPH = ('<w:p>' + run('Inline before ')
                    + control(202, 'Inline content', 'inline.content',
                              run('In') + control(207, 'Nested inline', 'nested.inline', run('si')) + run('de'))
                    + control(203, 'Empty inline', 'empty.inline', '')
                    + control(204, 'Absent inline', 'absent.inline', None)
                    + run(' after') + '</w:p>')
LEGACY_TAG = 'qudsFrame:72,90,200,120,page,none,FFFFFF,000000'
LEGACY = control(106, 'Legacy frame', LEGACY_TAG, paragraph('Legacy frame'))
ORDINARY = control(106, 'Ordinary block', 'ordinary.block', paragraph('Ordinary block'))

PARTS = {
    '[Content_Types].xml': f'''<Types xmlns="{CT}">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
      <Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
    </Types>''',
    '_rels/.rels': f'<Relationships xmlns="{REL}"><Relationship Id="main" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels': f'''<Relationships xmlns="{REL}">
      <Relationship Id="header" Type="{R}/header" Target="header1.xml"/>
      <Relationship Id="notes" Type="{R}/footnotes" Target="footnotes.xml"/>
    </Relationships>''',
    'word/document.xml': f'''<w:document xmlns:w="{W}" xmlns:r="{R}"><w:body>
      <w:p>{run('Before')}<w:r><w:footnoteReference w:id="1"/></w:r></w:p>
      {OUTER}{EMPTY}{ABSENT}{INLINE_PARAGRAPH}{ORDINARY}{paragraph('After')}
      <w:sectPr><w:headerReference w:type="default" r:id="header"/>
      <w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
    </w:body></w:document>''',
    'word/header1.xml': f'<w:hdr xmlns:w="{W}"><w:p>'
                        + control(206, 'Header inline', 'header.inline', run('Header value')) + '</w:p></w:hdr>',
    'word/footnotes.xml': f'<w:footnotes xmlns:w="{W}"><w:footnote w:id="1">'
                          '<w:p><w:r><w:footnoteRef/></w:r>' + run('Note prefix') + '</w:p>'
                          + control(107, 'Note block', 'note.block', paragraph('Note Delta'))
                          + '</w:footnote></w:footnotes>',
}

# Hand-authored semantics, independent of any imported/exported model values.
EXPECTED = {
    '101': ['document', None, 'Customer details', 'customer.info', True, 'Customer Alpha tailNested BetaCell Gamma'],
    '201': ['document', '101', 'Customer value', 'customer.value', True, 'Alpha'],
    '102': ['document', '101', 'Nested block', 'nested.block', True, 'Nested Beta'],
    '103': ['document', '101', 'Cell block', 'cell.block', True, 'Cell Gamma'],
    '104': ['document', None, 'Empty block', 'empty.block', True, ''],
    '105': ['document', None, 'Absent slot', 'absent.block', False, ''],
    '202': ['document', None, 'Inline content', 'inline.content', True, 'Inside'],
    '207': ['document', '202', 'Nested inline', 'nested.inline', True, 'si'],
    '203': ['document', None, 'Empty inline', 'empty.inline', True, ''],
    '204': ['document', None, 'Absent inline', 'absent.inline', False, ''],
    '106': ['document', None, 'Ordinary block', 'ordinary.block', True, 'Ordinary block'],
    '206': ['header', None, 'Header inline', 'header.inline', True, 'Header value'],
    '107': ['footnotes', None, 'Note block', 'note.block', True, 'Note Delta'],
}


def write_package(target, parts):
    with ZipFile(target, 'w') as package:
        for name, text in parts.items():
            info = ZipInfo(name, date_time=(2026, 1, 2, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            package.writestr(info, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + text)


def main():
    target = Path(__file__).with_name('content-controls.docx')
    write_package(target, PARTS)
    # Legacy private frame tags intentionally convert ordinary source flow to
    # positioned native frames. Keep that conversion apart from the native
    # preservation fixture used for strict source-to-first-save rendering.
    legacy_parts = dict(PARTS)
    legacy_parts['word/document.xml'] = legacy_parts['word/document.xml'].replace(ORDINARY, LEGACY)
    legacy_target = target.with_name('content-controls-legacy.docx')
    write_package(legacy_target, legacy_parts)
    target.with_name('content_controls_expected.json').write_text(json.dumps({
        'controls': EXPECTED,
        'legacy_controls': {'106': ['document', None, 'Legacy frame', LEGACY_TAG, True, 'Legacy frame']},
        'legacy_frame_emu': {'x': 914400, 'y': 1143000, 'cx': 2540000, 'cy': 1524000},
        'end_color': '4488AA',
        'kind': 'richText',
        'edited_text': {'101': 'Customer Omega tailNested editedCell Gamma',
                        '201': 'Omega', '102': 'Nested edited', '202': 'Updated', '207': '',
                        '206': 'Header edited', '107': 'Note edited'},
        'editor_text': {'101': 'Customer Alpha tailNested Be edited taCell Gamma',
                        '102': 'Nested Be edited ta'},
        'editor_paragraphs': {'102': ['Nested ', 'Be edited ta']},
    }, indent=2) + '\n')
    print(target)
    print(legacy_target)


if __name__ == '__main__':
    main()

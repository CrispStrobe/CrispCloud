#!/usr/bin/env python3
"""Author a comment-ID/paragraph-ID fixture without using the Quds writer.

Microsoft's CT_CommentEx definition joins each comment through its last
paragraph's w14:paraId, including paraIdParent for replies:
https://learn.microsoft.com/dotnet/api/documentformat.openxml.office2013.word.commentex
The numeric w:comment ID is deliberately unrelated to either paragraph ID.
"""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
W14 = 'http://schemas.microsoft.com/office/word/2010/wordml'
W15 = 'http://schemas.microsoft.com/office/word/2012/wordml'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
MC = 'http://schemas.openxmlformats.org/markup-compatibility/2006'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'

PARTS = {
    '[Content_Types].xml': f'''<Types xmlns="{CT}">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/custom/document-main.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/review/threads.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>
      <Override PartName="/review/thread-state.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml"/>
    </Types>''',
    '_rels/.rels': f'''<Relationships xmlns="{REL}">
      <Relationship Id="main" Type="{R}/officeDocument" Target="custom/document-main.xml"/>
    </Relationships>''',
    'custom/document-main.xml': f'''<w:document xmlns:w="{W}" xmlns:r="{R}"><w:body>
      <w:p><w:commentRangeStart w:id="41"/><w:r><w:t>Thread review anchor</w:t></w:r><w:commentRangeEnd w:id="41"/><w:r><w:commentReference w:id="41"/></w:r></w:p>
      <w:p><w:commentRangeStart w:id="99"/><w:r><w:t>Second independent thread</w:t></w:r><w:commentRangeEnd w:id="99"/><w:r><w:commentReference w:id="99"/></w:r></w:p>
      <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
    </w:body></w:document>''',
    'custom/_rels/document-main.xml.rels': f'''<Relationships xmlns="{REL}">
      <Relationship Id="comments" Type="{R}/comments" Target="../review/threads.xml"/>
      <Relationship Id="threads" Type="http://schemas.microsoft.com/office/2011/relationships/commentsExtended" Target="/review/thread-state.xml"/>
    </Relationships>''',
    'review/threads.xml': f'''<w:comments xmlns:w="{W}" xmlns:w14="{W14}" xmlns:mc="{MC}" mc:Ignorable="w14">
      <w:comment w:id="7" w:author="Reply reviewer" w:initials="RR" w:date="2026-01-02T10:00:00Z">
        <w:p w14:paraId="0077BB07"><w:r><w:rPr><w:b/></w:rPr><w:t>Reply arrived first</w:t></w:r></w:p>
      </w:comment>
      <w:comment w:id="41" w:author="Root reviewer" w:initials="RT" w:date="2026-01-02T09:00:00Z">
        <w:p w14:paraId="00112233"><w:r><w:t>Root opening paragraph</w:t></w:r></w:p>
        <w:p w14:paraId="00ABC123"><w:r><w:t>Root final paragraph</w:t></w:r></w:p>
      </w:comment>
      <w:comment w:id="99" w:author="Other reviewer" w:initials="OR">
        <w:p w14:paraId="00000001"><w:r><w:t>Independent unresolved comment</w:t></w:r></w:p>
      </w:comment>
    </w:comments>''',
    'review/thread-state.xml': f'''<w15:commentsEx xmlns:w15="{W15}">
      <w15:commentEx w15:paraId="0077bb07" w15:paraIdParent="00abc123" w15:done="0"/>
      <w15:commentEx w15:paraId="00ABC123" w15:done="on"/>
      <w15:commentEx w15:paraId="00000001"/>
    </w15:commentsEx>''',
}


def main():
    output = Path(__file__).with_name('comment-threads.docx')
    with ZipFile(output, 'w') as archive:
        for name, text in PARTS.items():
            info = ZipInfo(name, date_time=(2026, 1, 2, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            archive.writestr(info, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + text)
    print(output)


if __name__ == '__main__':
    main()

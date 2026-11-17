// Exercise the production DOCX import, ODT export and host preview together.
// The input XML and expected document semantics are independently authored.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart' as q;
import 'package:xml/xml.dart' as xml;

const _word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _relationship =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _packageRelationship =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _authoredNote = '  Notiz  \t(Müller, 2026)\nEnde';

Uint8List _source() {
  final parts = <String, String>{
    '[Content_Types].xml': '''
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
<Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>
</Types>''',
    '_rels/.rels':
        '''
<Relationships xmlns="$_packageRelationship">
<Relationship Id="office" Type="$_relationship/officeDocument" Target="word/document.xml"/>
</Relationships>''',
    'word/_rels/document.xml.rels':
        '''
<Relationships xmlns="$_packageRelationship">
<Relationship Id="numbering" Type="$_relationship/numbering" Target="numbering.xml"/>
<Relationship Id="notes" Type="$_relationship/footnotes" Target="footnotes.xml"/>
<Relationship Id="comments" Type="$_relationship/comments" Target="comments.xml"/>
<Relationship Id="link" Type="$_relationship/hyperlink" Target="https://example.org/quelle" TargetMode="External"/>
</Relationships>''',
    'word/document.xml':
        '''
<w:document xmlns:w="$_word" xmlns:r="$_relationship"><w:body>
<w:p><w:pPr><w:shd w:fill="FF0000"/><w:pBdr><w:bottom w:val="single" w:color="112233"/></w:pBdr></w:pPr><w:bookmarkStart w:id="1" w:name="ziel"/><w:commentRangeStart w:id="3"/><w:r><w:t>Grüße aus Köln</w:t></w:r><w:commentRangeEnd w:id="3"/><w:bookmarkEnd w:id="1"/></w:p>
<w:p><w:pPr><w:shd w:fill="00FF00"/><w:pBdr><w:bottom w:val="single" w:color="445566"/></w:pBdr></w:pPr><w:hyperlink r:id="link"><w:r><w:t>Zweiter Absatz</w:t></w:r></w:hyperlink></w:p>
<w:p><w:pPr><w:shd w:fill="FF0000"/><w:pBdr><w:bottom w:val="single" w:color="112233"/></w:pBdr></w:pPr><w:r><w:t>Wieder rot</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr><w:r><w:t>Liste für München</w:t></w:r></w:p>
<w:tbl><w:tblGrid><w:gridCol w:w="2400"/><w:gridCol w:w="2400"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Stadt</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>München</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r><w:t>Quelle</w:t></w:r><w:r><w:footnoteReference w:id="2"/></w:r></w:p>
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
</w:body></w:document>''',
    'word/numbering.xml':
        '''
<w:numbering xmlns:w="$_word">
<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>
<w:num w:numId="7"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>''',
    'word/footnotes.xml':
        '''
<w:footnotes xmlns:w="$_word"><w:footnote w:id="2"><w:p>
<w:r><w:footnoteRef/></w:r><w:commentRangeStart w:id="4"/><w:r><w:t xml:space="preserve">  Notiz  </w:t><w:tab/></w:r><w:commentRangeEnd w:id="4"/>
<w:fldSimple w:instr="ADDIN ZOTERO_ITEM HIDDEN_FIELD"><w:r><w:t>(Müller, 2026)</w:t></w:r></w:fldSimple><w:r><w:br/><w:t>Ende</w:t></w:r>
</w:p></w:footnote></w:footnotes>''',
    'word/comments.xml':
        '''
<w:comments xmlns:w="$_word">
<w:comment w:id="3" w:author="HIDDEN AUTHOR"><w:p><w:r><w:t>HIDDEN BODY REVIEW</w:t></w:r></w:p></w:comment>
<w:comment w:id="4" w:author="HIDDEN NOTE AUTHOR"><w:p><w:r><w:t>HIDDEN NOTE REVIEW</w:t></w:r></w:p></w:comment>
</w:comments>''',
  };
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

// Independent ODF text decoding; annotations remain separate stories.
String _visibleText(xml.XmlNode node) {
  if (node is xml.XmlText) return node.value;
  if (node is! xml.XmlElement) return '';
  if (node.namespaceUri == _office && node.localName == 'annotation') {
    return '';
  }
  if (node.namespaceUri == _text) {
    switch (node.localName) {
      case 's':
        return ' ' * int.parse(node.getAttribute('c', namespace: _text) ?? '1');
      case 'tab':
        return '\t';
      case 'line-break':
        return '\n';
    }
  }
  return node.children.map(_visibleText).join();
}

xml.XmlElement _properties(xml.XmlDocument content, xml.XmlElement paragraph) {
  final name = paragraph.getAttribute('style-name', namespace: _text);
  return content
      .findAllElements('automatic-styles', namespace: _office)
      .single
      .findElements('style', namespace: _style)
      .singleWhere(
        (style) => style.getAttribute('name', namespace: _style) == name,
      )
      .findElements('paragraph-properties', namespace: _style)
      .single;
}

void main() {
  test('exported note paragraphs and projected cells keep word boundaries', () async {
    q.WmlParagraph paragraph(String text) =>
        q.WmlParagraph(inlines: [q.WmlRun(text: text)]);
    final model = q.WmlDocument(
      sections: [
        q.WmlSection(
          blocks: [
            q.WmlParagraph(
              inlines: [
                q.WmlRun(text: 'Quelle'),
                q.WmlRun(noteRefId: 7),
              ],
            ),
          ],
        ),
      ],
      footnotes: [
        q.WmlNote(
          id: 7,
          endnote: false,
          addReferenceSpace: false,
          blocks: [
            paragraph('Erster Absatz'),
            paragraph('Zweiter Absatz'),
            q.WmlTable(
              rows: [
                q.WmlTableRow(
                  cells: [
                    q.WmlTableCell(blocks: [paragraph('Dritte Zelle')]),
                    q.WmlTableCell(blocks: [paragraph('Vierte Zelle')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final exported = q.OdtDocumentWriter.writeBytes(model);
    final archive = ZipDecoder().decodeBytes(exported);
    final contentText = utf8.decode(archive.findFile('content.xml')!.content);
    final content = xml.XmlDocument.parse(contentText);
    final noteBody = content
        .findAllElements('note-body', namespace: _text)
        .single;
    // The supported writer contract projects note tables to paragraphs. Assert
    // the independent XML boundaries before checking the host's readable view.
    expect(noteBody.findElements('p', namespace: _text).map(_visibleText), [
      'Erster Absatz',
      'Zweiter Absatz',
      'Dritte Zelle',
      'Vierte Zelle',
    ]);
    expect(noteBody.findAllElements('table', namespace: _table), isEmpty);
    final preview = await parseOfficeDocument(exported, 'notiz.odt');
    expect(preview.fallback, isNull);
    expect(preview.markdown, contains('Quelle[1]'));
    const readable =
        '1. Erster Absatz Zweiter Absatz Dritte Zelle Vierte Zelle';
    expect(preview.markdown, contains(readable));
    expect(preview.plainText, contains(readable));
    expect(preview.rawXml, '<!-- content.xml -->\n$contentText');
    expect(model.footnotes.single.blocks, hasLength(3));
    expect(model.footnotes.single.blocks.last, isA<q.WmlTable>());
  });

  test(
    'authored DOCX exports independent ODT stories and readable host preview',
    () async {
      final source = _source();
      final sourceSnapshot = Uint8List.fromList(source);
      final model = q.WordDeserializer().readBytes(source);
      final note = model.footnotes.single;
      final noteParagraph = note.paragraphs.single;
      final originalNoteText = noteParagraph.text;
      final originalComments = model.comments
          .map((comment) => (comment.id, comment.text))
          .toList();
      expect(originalNoteText, _authoredNote);
      expect(originalComments.map((comment) => comment.$1), [3, 4]);

      final exported = q.OdtDocumentWriter.writeBytes(model);
      final archive = ZipDecoder().decodeBytes(exported);
      expect(
        utf8.decode(archive.findFile('mimetype')!.content),
        'application/vnd.oasis.opendocument.text',
      );
      final contentText = utf8.decode(archive.findFile('content.xml')!.content);
      final content = xml.XmlDocument.parse(contentText);
      final body = content
          .findAllElements('body', namespace: _office)
          .single
          .findElements('text', namespace: _office)
          .single;
      final paragraphs = body.findElements('p', namespace: _text).toList();
      expect(paragraphs, hasLength(4));
      expect(paragraphs.take(3).map(_visibleText), [
        'Grüße aus Köln',
        'Zweiter Absatz',
        'Wieder rot',
      ]);
      for (var index = 0; index < 3; index++) {
        final properties = _properties(content, paragraphs[index]);
        expect(
          properties.getAttribute('background-color', namespace: _fo),
          index == 1 ? '#00ff00' : '#ff0000',
        );
        expect(
          properties.getAttribute('border', namespace: _fo),
          index == 1 ? '0.5pt solid #445566' : '0.5pt solid #112233',
        );
      }
      final bookmark = paragraphs.first
          .findElements('bookmark-start', namespace: _text)
          .single;
      expect(bookmark.getAttribute('name', namespace: _text), 'ziel');
      expect(
        paragraphs.first
            .findElements('bookmark-end', namespace: _text)
            .single
            .getAttribute('name', namespace: _text),
        'ziel',
      );
      final link = paragraphs[1].findElements('a', namespace: _text).single;
      expect(
        link.getAttribute('href', namespace: _xlink),
        'https://example.org/quelle',
      );
      expect(_visibleText(link), 'Zweiter Absatz');
      final list = body.findElements('list', namespace: _text).single;
      expect(_visibleText(list), 'Liste für München');
      expect(list.findElements('list-item', namespace: _text), hasLength(1));
      final table = body.findElements('table', namespace: _table).single;
      expect(
        table
            .findAllElements('table-cell', namespace: _table)
            .map(_visibleText),
        ['Stadt', 'München'],
      );

      final odtNote = paragraphs.last
          .findAllElements('note', namespace: _text)
          .single;
      expect(odtNote.getAttribute('note-class', namespace: _text), 'footnote');
      final citation = odtNote
          .findElements('note-citation', namespace: _text)
          .single;
      expect(citation.innerText, '1');
      expect(citation.getAttribute('label', namespace: _text), '1');
      final noteBody = odtNote
          .findElements('note-body', namespace: _text)
          .single;
      expect(_visibleText(noteBody), _authoredNote);
      final annotations = body
          .findAllElements('annotation', namespace: _office)
          .toList();
      expect(annotations, hasLength(2));
      expect(annotations.first.parent, same(paragraphs.first));
      expect(annotations.last.ancestors, contains(noteBody));
      expect(annotations.first.innerText, contains('HIDDEN BODY REVIEW'));
      expect(annotations.last.innerText, contains('HIDDEN NOTE REVIEW'));
      expect(contentText, isNot(contains('HIDDEN_FIELD')));

      final preview = await parseOfficeDocument(exported, 'prüfbericht.odt');
      expect(preview.fallback, isNull);
      expect(preview.kind, OfficeDocumentKind.document);
      expect(preview.markdown, contains('Grüße aus Köln'));
      expect(
        preview.markdown,
        contains('[Zweiter Absatz](https://example.org/quelle)'),
      );
      expect(preview.markdown, contains('Wieder rot'));
      expect(preview.markdown, contains('1. Liste für München'));
      expect(preview.markdown, contains('| Stadt | München |'));
      expect(preview.markdown, contains('Quelle[1]'));
      expect(preview.markdown, contains('1. Notiz (Müller, 2026) Ende'));
      expect(preview.markdown, isNot(contains('HIDDEN')));
      expect(preview.plainText, isNot(contains('HIDDEN')));
      expect(preview.plainText, contains('Notiz (Müller, 2026) Ende'));
      expect(preview.rawXml, '<!-- content.xml -->\n$contentText');

      expect(source, sourceSnapshot);
      expect(model.footnotes.single, same(note));
      expect(note.paragraphs.single, same(noteParagraph));
      expect(noteParagraph.text, originalNoteText);
      expect(
        model.comments.map((comment) => (comment.id, comment.text)),
        originalComments,
      );
    },
  );
}

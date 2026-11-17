import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart' as q;

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _namespaces =
    'xmlns:office="$_office" xmlns:o="$_office" '
    'xmlns:table="$_table" xmlns:text="$_text" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:foreign="urn:foreign"';

String _document(String body, {String kind = 'text'}) =>
    '<office:document-content $_namespaces>'
    '<office:body><office:$kind>$body</office:$kind></office:body>'
    '</office:document-content>';

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

q.WmlParagraph _annotated(String text, int id) => q.WmlParagraph(
      inlines: [
        q.WmlRun(text: text, commentIds: [id]),
      ],
    );

void _expectNoAnnotationText(OfficeDocument document) {
  expect(document.fallback, isNull);
  expect(document.markdown, isNot(contains('HIDDEN')));
  expect(document.plainText, isNot(contains('HIDDEN')));
  if (document.csv != null) {
    expect(document.csv, isNot(contains('HIDDEN')));
  }
}

void main() {
  test('exported ODT comments stay separate from body, list, table and notes',
      () async {
    final model = q.WmlDocument(
      comments: [
        for (var id = 1; id <= 6; id++)
          q.WmlComment(
            id: id,
            author: 'HIDDEN AUTHOR $id',
            dateIso: '2026-11-17T00:00:00Z',
            text: 'HIDDEN COMMENT $id',
          ),
      ],
      footnotes: [
        q.WmlNote(
          id: 7,
          endnote: false,
          paragraphs: [_annotated('Note body', 4)],
        ),
      ],
      sections: [
        q.WmlSection(
          blocks: [
            q.WmlParagraph(
              inlines: [
                q.WmlRun(text: 'Before ', commentIds: [1]),
                q.WmlRun(text: 'after'),
              ],
            ),
            q.WmlParagraph(
              properties: q.WmlParagraphProps(numId: 1),
              inlines: [
                q.WmlRun(text: 'List body', commentIds: [2]),
              ],
            ),
            q.WmlTable(
              rows: [
                q.WmlTableRow(
                  cells: [
                    q.WmlTableCell(blocks: [_annotated('Cell body', 3)]),
                  ],
                ),
              ],
            ),
            q.WmlParagraph(
              inlines: [
                q.WmlRun(text: 'Reference'),
                q.WmlRun(noteRefId: 7),
              ],
            ),
          ],
          header: [_annotated('Header body', 5)],
          footer: [_annotated('Footer body', 6)],
        ),
      ],
    );
    final bytes = q.OdtDocumentWriter.writeBytes(model);
    final document = await parseOfficeDocument(bytes, 'writer-comments.odt');
    _expectNoAnnotationText(document);
    expect(document.markdown, contains('Before after'));
    expect(document.markdown, contains('- List body'));
    expect(document.markdown, contains('| Cell body |'));
    expect(document.markdown, contains('Reference[1]'));
    expect(document.markdown, contains('1. Note body'));
    expect(document.markdown, contains('> **Header:** Header body'));
    expect(document.markdown, contains('> **Footer:** Footer body'));
    expect(document.plainText, isNot(contains('2026-11-17T00:00:00Z')));
    for (var id = 1; id <= 4; id++) {
      expect(document.rawXml, contains('HIDDEN COMMENT $id'));
    }
    final package = q.OpcPackage.openBytes(bytes);
    final styles = package.getPart('/styles.xml')!.readText();
    expect(styles, contains('HIDDEN COMMENT 5'));
    expect(styles, contains('HIDDEN COMMENT 6'));
    expect(model.comments.map((comment) => comment.text), [
      for (var id = 1; id <= 6; id++) 'HIDDEN COMMENT $id',
    ]);
  });

  for (final extension in ['odt', 'ods']) {
    test('$extension table cells exclude inline and sibling annotations',
        () async {
      const table = '<table:table table:name="Data">'
          '<table:table-row><table:table-cell office:value-type="string">'
          '<text:p>Before<![CDATA[ & visible ]]>'
          '<o:annotation><dc:creator>HIDDEN AUTHOR</dc:creator>'
          '<text:p>HIDDEN INLINE</text:p></o:annotation>After</text:p>'
          '<o:annotation><text:p>HIDDEN CELL</text:p>'
          '<table:table><table:table-row><table:table-cell>'
          '<text:p>HIDDEN NESTED</text:p>'
          '</table:table-cell></table:table-row></table:table></o:annotation>'
          '<table:covered-table-cell><text:p>HIDDEN COVERED</text:p>'
          '</table:covered-table-cell>'
          '<foreign:annotation><text:p>Foreign paragraph</text:p>'
          '</foreign:annotation>'
          '<office:annotation xmlns:office="urn:foreign">'
          '<text:p>Shadow paragraph</text:p></office:annotation>'
          '<text:p>Tail</text:p>'
          '</table:table-cell></table:table-row></table:table>';
      final xml = _document(
        table,
        kind: extension == 'ods' ? 'spreadsheet' : 'text',
      );
      final document = await parseOfficeDocument(
        _zip({'content.xml': xml}),
        'cell-comments.$extension',
      );
      _expectNoAnnotationText(document);
      const visible =
          'Before & visible After Foreign paragraph Shadow paragraph Tail';
      expect(document.markdown, contains(visible));
      expect(document.plainText, contains(visible));
      if (extension == 'ods') {
        expect(document.csv!.trim(), visible);
      }
      expect(document.rawXml, '<!-- content.xml -->\n$xml');
    });
  }

  test('ODT aliased annotations stay out of paragraphs, blocks, lists and notes',
      () async {
    final xml = _document(
      '<text:p>Before<o:annotation><dc:creator>HIDDEN AUTHOR</dc:creator>'
      '<text:p>HIDDEN INLINE</text:p></o:annotation>After'
      '<foreign:annotation> foreign inline</foreign:annotation></text:p>'
      '<o:annotation><text:p>HIDDEN BLOCK</text:p></o:annotation>'
      '<office:annotation xmlns:office="urn:foreign">'
      '<text:p>Shadow block</text:p></office:annotation>'
      '<foreign:annotation><text:p>Foreign block</text:p>'
      '</foreign:annotation>'
      '<text:list><text:list-item><text:p>List<o:annotation>'
      '<text:p>HIDDEN LIST</text:p></o:annotation> tail</text:p>'
      '</text:list-item></text:list>'
      '<text:p>Reference<text:note text:note-class="footnote" text:id="n1">'
      '<text:note-citation>1</text:note-citation><text:note-body>'
      '<text:p>Note<o:annotation><text:p>HIDDEN NOTE</text:p></o:annotation>'
      ' tail<foreign:annotation> foreign note</foreign:annotation></text:p>'
      '</text:note-body></text:note> after</text:p>',
    );
    final document = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'namespaces.odt',
    );
    _expectNoAnnotationText(document);
    expect(document.markdown, contains('BeforeAfter foreign inline'));
    expect(document.markdown, contains('Shadow block'));
    expect(document.markdown, contains('Foreign block'));
    expect(document.markdown, contains('- List tail'));
    expect(document.markdown, contains('Reference[1] after'));
    expect(document.markdown, contains('1. Note tail foreign note'));
    expect(document.rawXml, '<!-- content.xml -->\n$xml');
  });

  test('ODT headers and footers exclude annotations by namespace', () async {
    final xml = _document('<text:p>Body</text:p>');
    const styles = '<office:document-styles $_namespaces>'
        '<office:master-styles><style:master-page style:name="Standard">'
        '<style:header><text:p>Header<o:annotation>'
        '<dc:creator>HIDDEN HEADER AUTHOR</dc:creator>'
        '<text:p>HIDDEN HEADER</text:p></o:annotation> tail'
        '<foreign:annotation> foreign header</foreign:annotation></text:p>'
        '</style:header>'
        '<style:footer><text:p>Footer<office:annotation>'
        '<text:p>HIDDEN FOOTER</text:p></office:annotation> tail'
        '<office:annotation xmlns:office="urn:foreign">'
        ' shadow footer</office:annotation></text:p></style:footer>'
        '</style:master-page></office:master-styles>'
        '</office:document-styles>';
    final document = await parseOfficeDocument(
      _zip({'content.xml': xml, 'styles.xml': styles}),
      'header-comments.odt',
    );
    _expectNoAnnotationText(document);
    expect(
      document.markdown,
      contains('> **Header:** Header tail foreign header'),
    );
    expect(
      document.markdown,
      contains('> **Footer:** Footer tail shadow footer'),
    );
    expect(document.rawXml, '<!-- content.xml -->\n$xml');
  });

  test('annotation-only ODT documents have no body text', () async {
    final xml = _document(
      '<o:annotation><dc:creator>HIDDEN AUTHOR</dc:creator>'
      '<text:p>HIDDEN BODY</text:p><![CDATA[HIDDEN RAW]]></o:annotation>',
    );
    final document = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'only-comments.odt',
    );
    _expectNoAnnotationText(document);
    expect(document.markdown, isEmpty);
    expect(document.plainText, isEmpty);
    expect(document.rawXml, '<!-- content.xml -->\n$xml');
  });

  test('empty annotations do not hide following paragraphs or table cells',
      () async {
    final xml = _document(
      '<o:annotation/><text:p>Before</text:p>'
      '<office:annotation></office:annotation>'
      '<table:table><table:table-row><table:table-cell>'
      '<text:p>Cell</text:p></table:table-cell></table:table-row>'
      '</table:table><o:annotation/><text:p>After</text:p>',
    );
    final document = await parseOfficeDocument(
      _zip({'content.xml': xml}),
      'empty-comments.odt',
    );
    _expectNoAnnotationText(document);
    expect(document.markdown, contains('Before'));
    expect(document.markdown, contains('| Cell |'));
    expect(document.markdown, contains('After'));
    expect(document.rawXml, '<!-- content.xml -->\n$xml');
  });

  test('ODS writer annotations stay in raw XML and out of CSV values', () async {
    final sheet = q.SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1')
      ..value = 'Visible cell'
      ..type = q.SmlCellType.string;
    sheet.comments.add(
      q.SmlComment(
        ref: q.SmlCellRef.parse('A1'),
        text: 'HIDDEN COMMENT',
        author: 'HIDDEN AUTHOR',
      ),
    );
    final bytes = q.OdsSheetWriter.writeBytes(q.SmlWorkbook(sheets: [sheet]));
    final document = await parseOfficeDocument(bytes, 'writer-comments.ods');
    _expectNoAnnotationText(document);
    expect(document.csv!.trim(), 'Visible cell');
    expect(document.markdown, contains('| Visible cell |'));
    expect(document.rawXml, contains('HIDDEN COMMENT'));
    expect(document.rawXml, contains('HIDDEN AUTHOR'));
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/odf/odf_text.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

String _document(String body, {String kind = 'text'}) =>
    '<office:document-content xmlns:office="$_office" '
    'xmlns:table="$_table" xmlns:text="$_text" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:foreign="urn:foreign">'
    '<office:body><office:$kind>$body</office:$kind></office:body>'
    '</office:document-content>';

Uint8List _archive(String xml) {
  final writer = ZipWriter();
  writer.addFile('content.xml', utf8.encode(xml));
  return writer.close();
}

String _raw(Uint8List bytes) =>
    utf8.decode(ZipReader.fromBytes(bytes).read('content.xml'));

void main() {
  for (final (extension, kind) in [
    ('odt', 'text'),
    ('ods', 'spreadsheet'),
  ]) {
    test(
      '$extension annotations do not create body paragraphs or table text',
      () async {
        final xml = _document(
          '<text:p>Lead</text:p>'
          '<office:annotation><dc:creator>HIDDEN AUTHOR</dc:creator>'
          '<text:p>HIDDEN BLOCK</text:p>'
          '<table:table><table:table-row><table:table-cell>'
          '<text:p>HIDDEN TABLE</text:p>'
          '</table:table-cell></table:table-row></table:table>'
          '</office:annotation>'
          '<table:table><table:table-row><table:table-cell>'
          '<text:p>Before<office:annotation>'
          '<text:p>HIDDEN INLINE</text:p></office:annotation>After</text:p>'
          '<office:annotation><text:p>HIDDEN CELL</text:p>'
          '</office:annotation><text:p>Tail</text:p>'
          '</table:table-cell></table:table-row></table:table>'
          '<text:p>End</text:p>',
          kind: kind,
        );
        final bytes = _archive(xml);
        final result = OfficeTextExtractor.extract(
          bytes,
          name: 'comments.$extension',
        );
        expect(result.tables, [
          [
            ['BeforeAfter\nTail'],
          ],
        ]);
        if (extension == 'odt') {
          expect(result.paragraphs, ['Lead', 'End']);
        } else {
          expect(result.sheets.single.rows, [
            ['BeforeAfter\nTail'],
          ]);
        }
        expect(result.plainString, isNot(contains('HIDDEN')));
        expect(
          await officeSearchText(bytes, 'comments.$extension', 65536),
          'Lead\nBeforeAfter\nTail\nEnd',
        );
        expect(_raw(bytes), xml);
      },
    );
  }

  test('inline annotation omission preserves authored spaces and CDATA', () async {
    final bytes = _archive(
      _document(
        '<text:p>Before<text:s text:c="2"/>'
        '<office:annotation><text:p>HIDDEN</text:p></office:annotation>'
        '<![CDATA[& visible]]><text:tab/>After</text:p>',
      ),
    );
    expect(OfficeTextExtractor.extract(bytes, name: 'inline.odt').paragraphs, [
      'Before  & visible\tAfter',
    ]);
    expect(
      await officeSearchText(bytes, 'inline.odt', 65536),
      'Before  & visible\tAfter',
    );
  });

  test('annotation recognition uses namespace identity and keeps foreign text',
      () async {
    final bytes = _archive(
      _document(
        '<other:annotation xmlns:other="$_office">'
        '<text:p>HIDDEN ALIAS</text:p></other:annotation>'
        '<office:annotation xmlns:office="urn:foreign">'
        '<text:p>Visible shadow</text:p></office:annotation>'
        '<foreign:annotation><text:p>Visible foreign</text:p>'
        '</foreign:annotation><text:p>Tail</text:p>',
      ),
    );
    expect(
      OfficeTextExtractor.extract(bytes, name: 'namespaces.odt').paragraphs,
      ['Visible shadow', 'Visible foreign', 'Tail'],
    );
    expect(
      await officeSearchText(bytes, 'namespaces.odt', 65536),
      'Visible shadow\nVisible foreign\nTail',
    );
  });

  test('empty annotations do not consume following paragraphs or tables',
      () async {
    final bytes = _archive(
      _document(
        '<office:annotation/><text:p>Before</text:p>'
        '<office:annotation></office:annotation>'
        '<table:table><table:table-row><table:table-cell>'
        '<text:p>Cell</text:p></table:table-cell></table:table-row>'
        '</table:table><office:annotation/><text:p>After</text:p>',
      ),
    );
    final result = OfficeTextExtractor.extract(bytes, name: 'empty.odt');
    expect(result.paragraphs, ['Before', 'After']);
    expect(result.tables, [
      [
        ['Cell'],
      ],
    ]);
    expect(
      await officeSearchText(bytes, 'empty.odt', 65536),
      'Before\nCell\nAfter',
    );
  });

  test('annotation-only documents do not fall back to comment metadata', () async {
    final bytes = _archive(
      _document(
        '<office:annotation><dc:creator>HIDDEN AUTHOR</dc:creator>'
        '<text:p>HIDDEN BODY</text:p><![CDATA[HIDDEN RAW]]>'
        '</office:annotation>',
      ),
    );
    final result = OfficeTextExtractor.extract(bytes, name: 'only.odt');
    expect(result.paragraphs, isEmpty);
    expect(result.plainString, isEmpty);
    expect(await officeSearchText(bytes, 'only.odt', 65536), isEmpty);
    expect(_raw(bytes), contains('HIDDEN BODY'));
  });

  test('namespace-less fallback excludes only ODF annotations', () async {
    final bytes = _archive(
      '<document xmlns:o="$_office" xmlns:f="urn:foreign">'
      '<p>Before</p><o:annotation><p>HIDDEN</p></o:annotation>'
      '<f:annotation><p>Foreign</p></f:annotation>'
      '<p><![CDATA[After]]></p></document>',
    );
    expect(
      await officeSearchText(bytes, 'fallback.odt', 65536),
      'Before Foreign After',
    );
  });

  test('hidden annotation text is neither expanded nor charged to output',
      () async {
    final xml = _document(
      '<office:annotation><text:p>'
      '<text:s text:c="999999999999999999999999999999"/>'
      '<text:s text:c="-1"/></text:p></office:annotation>'
      '<text:p>A</text:p>',
    );
    final bytes = _archive(xml);
    expect(
      OfficeTextExtractor.extract(bytes, name: 'bounded.odt').paragraphs,
      ['A'],
    );
    expect(await officeSearchText(bytes, 'bounded.odt', 65536), 'A');
    final root = XmlDocument.parse(xml).root!;
    final before = XmlDocument(root: root).toXmlString();
    expect(readOdfText(root, OdfTextBudget(1)), 'A');
    expect(XmlDocument(root: root).toXmlString(), before);

    final visible = _archive(_document('<text:p><text:s text:c="-1"/></text:p>'));
    expect(
      () => OfficeTextExtractor.extract(visible, name: 'visible.odt'),
      throwsFormatException,
    );
    await expectLater(
      officeSearchText(visible, 'visible.odt', 65536),
      throwsFormatException,
    );
  });

  test('annotations still count toward the package byte budget', () async {
    final xml = _document(
      '<office:annotation><text:p>' +
          'x' * 4096 +
          '</text:p></office:annotation><text:p>A</text:p>',
    );
    await expectLater(
      officeSearchText(
        _archive(xml),
        'package-budget.odt',
        utf8.encode(xml).length - 1,
      ),
      throwsA(isA<OfficeSearchLimitException>()),
    );
  });

  test('ODS writer comments stay in the package without becoming cell text',
      () async {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1')
      ..value = 'Visible cell'
      ..type = SmlCellType.string;
    sheet.comments.add(
      SmlComment(
        ref: SmlCellRef.parse('A1'),
        text: 'HIDDEN COMMENT',
        author: 'HIDDEN AUTHOR',
      ),
    );
    final bytes = OdsSheetWriter.writeBytes(SmlWorkbook(sheets: [sheet]));
    final result = OfficeTextExtractor.extract(bytes, name: 'writer.ods');
    expect(result.sheets.single.rows, [
      ['Visible cell'],
    ]);
    expect(await officeSearchText(bytes, 'writer.ods', 65536), 'Visible cell');
    expect(_raw(bytes), contains('HIDDEN COMMENT'));
    expect(_raw(bytes), contains('HIDDEN AUTHOR'));
    expect(OdsSheetReader.readBytes(bytes).sheets.single.comments.single.text,
        'HIDDEN COMMENT');
  });

  test('ODT writer comments retain their body and do not enter body search',
      () async {
    final document = WmlDocument(
      comments: [
        WmlComment(
          id: 1,
          author: 'HIDDEN AUTHOR',
          dateIso: '2026-11-17T00:00:00Z',
          paragraphs: [
            WmlParagraph(inlines: [WmlRun(text: 'HIDDEN COMMENT')]),
          ],
        ),
      ],
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Before ', commentIds: [1]),
                WmlRun(text: 'after'),
              ],
            ),
          ],
        ),
      ],
    );
    final bytes = OdtDocumentWriter.writeBytes(document);
    expect(OfficeTextExtractor.extract(bytes, name: 'writer.odt').paragraphs, [
      'Before after',
    ]);
    expect(await officeSearchText(bytes, 'writer.odt', 65536), 'Before after');
    expect(_raw(bytes), contains('HIDDEN COMMENT'));
    expect(_raw(bytes), contains('HIDDEN AUTHOR'));
    expect(document.comments.single.text, 'HIDDEN COMMENT');
  });
}

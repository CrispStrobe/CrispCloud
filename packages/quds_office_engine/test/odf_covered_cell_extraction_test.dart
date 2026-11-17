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
    'xmlns:table="$_table" xmlns:text="$_text" xmlns:foreign="urn:foreign">'
    '<office:body><office:$kind>$body</office:$kind></office:body>'
    '</office:document-content>';

Uint8List _archive(String xml) {
  final writer = ZipWriter();
  writer.addFile('content.xml', utf8.encode(xml));
  return writer.close();
}

Uint8List _native(String body, {String kind = 'text'}) =>
    _archive(_document(body, kind: kind));

String _allResults(OfficeTextExtract extract) => jsonEncode({
  'paragraphs': extract.paragraphs,
  'tables': extract.tables,
  'sheets': [for (final sheet in extract.sheets) sheet.rows],
  'slides': [
    for (final slide in extract.slides)
      [slide.title, slide.body, slide.notes, slide.tables],
  ],
});

void main() {
  for (final (extension, kind) in [
    ('odt', 'text'),
    ('ods', 'spreadsheet'),
    ('odp', 'presentation'),
  ]) {
    test(
      '$extension extraction excludes entire covered stories and resumes after them',
      () async {
        final bytes = _native(
          '<text:p>Lead</text:p>'
          '<table:table><table:table-row>'
          '<table:table-cell table:number-columns-spanned="2"><text:p>Anchor</text:p></table:table-cell>'
          '<table:covered-table-cell><text:p>Hidden</text:p>'
          '<table:table><table:table-row><table:table-cell><text:p>Phantom</text:p></table:table-cell></table:table-row></table:table>'
          '</table:covered-table-cell>'
          '<table:table-cell><text:p>Right</text:p></table:table-cell>'
          '</table:table-row></table:table><text:p>Tail</text:p>',
          kind: kind,
        );
        final result = OfficeTextExtractor.extract(
          bytes,
          name: 'native.$extension',
        );
        final tables = result.slides.isEmpty
            ? result.tables
            : result.slides.single.tables;
        expect(tables, [
          [
            ['Anchor', 'Right'],
          ],
        ]);
        expect(_allResults(result), isNot(contains('Hidden')));
        expect(_allResults(result), isNot(contains('Phantom')));
        if (extension == 'odt') expect(result.paragraphs, ['Lead', 'Tail']);
        expect(
          await officeSearchText(bytes, 'native.$extension', 65536),
          'Lead\nAnchor\nRight\nTail',
        );
      },
    );
  }

  test(
    'nested covered cells are omitted when decoding an enclosing visible cell',
    () async {
      final bytes = _native(
        '<table:table><table:table-row><table:table-cell>'
        '<text:p>Outer</text:p><table:table><table:table-row>'
        '<table:table-cell><text:p>Inner</text:p></table:table-cell>'
        '<table:covered-table-cell><text:p>Hidden nested</text:p></table:covered-table-cell>'
        '</table:table-row></table:table><text:p>Tail</text:p>'
        '</table:table-cell></table:table-row></table:table>',
      );
      final result = OfficeTextExtractor.extract(bytes, name: 'nested.odt');
      expect(result.paragraphs, isEmpty);
      expect(result.tables, [
        [
          ['Outer\nInner\nTail'],
        ],
      ]);
      expect(
        await officeSearchText(bytes, 'nested.odt', 65536),
        'Outer\nInner\nTail',
      );
    },
  );

  test('all-covered documents do not fall back to hidden raw text', () async {
    final bytes = _native(
      '<table:table><table:table-row><table:covered-table-cell>'
      '<text:p>Hidden only</text:p><![CDATA[Hidden raw]]>'
      '</table:covered-table-cell></table:table-row></table:table>',
    );
    final result = OfficeTextExtractor.extract(bytes, name: 'hidden.odt');
    expect(result.paragraphs, isEmpty);
    expect(result.plainString, isEmpty);
    expect(_allResults(result), isNot(contains('Hidden')));
    expect(await officeSearchText(bytes, 'hidden.odt', 65536), isEmpty);
  });

  test(
    'namespace-less search fallback still omits namespaced covered content',
    () async {
      final bytes = _archive(
        '<document xmlns:t="$_table">'
        '<p>Before</p><t:covered-table-cell><p>Hidden fallback</p></t:covered-table-cell>'
        '<p><![CDATA[After]]></p></document>',
      );
      expect(
        await officeSearchText(bytes, 'fallback.odt', 65536),
        'Before After',
      );
    },
  );

  test(
    'covered-cell recognition follows namespace identity rather than prefix',
    () async {
      final bytes = _native(
        '<other:covered-table-cell xmlns:other="$_table"><text:p>Hidden alias</text:p></other:covered-table-cell>'
        '<table:covered-table-cell xmlns:table="urn:foreign"><text:p>Visible foreign</text:p></table:covered-table-cell>'
        '<foreign:covered-table-cell><text:p>Another visible</text:p></foreign:covered-table-cell>',
      );
      expect(
        OfficeTextExtractor.extract(bytes, name: 'namespaces.odt').paragraphs,
        ['Visible foreign', 'Another visible'],
      );
      expect(
        await officeSearchText(bytes, 'namespaces.odt', 65536),
        'Visible foreign\nAnother visible',
      );
    },
  );

  test('empty covered cells do not consume the following paragraph', () async {
    final bytes = _native(
      '<text:p>Before</text:p><table:covered-table-cell/>'
      '<text:p>Between</text:p><table:covered-table-cell></table:covered-table-cell>'
      '<text:p>After</text:p>',
    );
    expect(OfficeTextExtractor.extract(bytes, name: 'empty.odt').paragraphs, [
      'Before',
      'Between',
      'After',
    ]);
    expect(
      await officeSearchText(bytes, 'empty.odt', 65536),
      'Before\nBetween\nAfter',
    );
  });

  test(
    'hidden whitespace is neither expanded nor charged against decoded text',
    () async {
      final bytes = _native(
        '<table:covered-table-cell><text:p><text:s text:c="999999999999999999999999999999"/></text:p></table:covered-table-cell>'
        '<text:p>Visible</text:p>',
      );
      expect(
        OfficeTextExtractor.extract(bytes, name: 'bounded.odt').paragraphs,
        ['Visible'],
      );
      expect(await officeSearchText(bytes, 'bounded.odt', 65536), 'Visible');
      final root = XmlDocument.parse(
        '<root xmlns:table="$_table" xmlns:text="$_text">'
        '<table:covered-table-cell><text:p>Hidden</text:p></table:covered-table-cell>'
        '<text:p>A</text:p></root>',
      ).root!;
      final before = XmlDocument(root: root).toXmlString();
      expect(readOdfText(root, OdfTextBudget(1)), 'A');
      expect(XmlDocument(root: root).toXmlString(), before);
    },
  );

  test(
    'skipping hidden output does not bypass the package byte budget',
    () async {
      final xml = _document(
        '<table:covered-table-cell><text:p>${'x' * 4096}</text:p></table:covered-table-cell><text:p>A</text:p>',
      );
      await expectLater(
        officeSearchText(
          _archive(xml),
          'bounded.odt',
          utf8.encode(xml).length - 1,
        ),
        throwsA(isA<OfficeSearchLimitException>()),
      );
    },
  );

  test(
    'malformed hidden whitespace is skipped while visible validation remains',
    () async {
      final hidden = _native(
        '<table:covered-table-cell><text:p><text:s text:c="-1"/></text:p></table:covered-table-cell><text:p>A</text:p>',
      );
      expect(
        OfficeTextExtractor.extract(hidden, name: 'hidden.odt').paragraphs,
        ['A'],
      );
      expect(await officeSearchText(hidden, 'hidden.odt', 65536), 'A');
      final visible = _native('<text:p><text:s text:c="-1"/></text:p>');
      expect(
        () => OfficeTextExtractor.extract(visible, name: 'visible.odt'),
        throwsFormatException,
      );
      await expectLater(
        officeSearchText(visible, 'visible.odt', 65536),
        throwsFormatException,
      );
    },
  );

  test(
    'actual merged ODT retains source stories but extracts only visible content',
    () async {
      WmlParagraph paragraph(String value) =>
          WmlParagraph(inlines: [WmlRun(text: value)]);
      final anchor = WmlTableCell(
        vMerge: WmlVMerge.restart,
        blocks: [paragraph('Anchor')],
      );
      final continuation = WmlTableCell(
        vMerge: WmlVMerge.cont,
        blocks: [paragraph('Retained hidden')],
      );
      final bytes = OdtDocumentWriter.writeBytes(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                paragraph('Before'),
                WmlTable(
                  rows: [
                    WmlTableRow(cells: [anchor]),
                    WmlTableRow(cells: [continuation]),
                  ],
                ),
                paragraph('After'),
              ],
            ),
          ],
        ),
      );
      final xml = OpcPackage.openBytes(
        bytes,
      ).getPart('/content.xml')!.readText();
      expect(xml, contains('<table:covered-table-cell'));
      expect(xml, contains('Retained hidden'));
      final result = OfficeTextExtractor.extract(bytes, name: 'exported.odt');
      expect(result.paragraphs, ['Before', 'After']);
      expect(result.tables, [
        [
          ['Anchor'],
          <String>[],
        ],
      ]);
      expect(
        await officeSearchText(bytes, 'exported.odt', 65536),
        'Before\nAnchor\nAfter',
      );
      expect(
        (continuation.blocks.single as WmlParagraph).text,
        'Retained hidden',
      );
      expect(continuation.vMerge, WmlVMerge.cont);
    },
  );
}

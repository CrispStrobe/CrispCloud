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
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:foreign="urn:foreign">'
    '<office:body><office:$kind>$body</office:$kind></office:body>'
    '</office:document-content>';

Uint8List _archive(String xml) {
  final zip = ZipWriter();
  zip.addFile('content.xml', utf8.encode(xml));
  return zip.close();
}

String _changeInfo([String comment = '']) =>
    '<office:change-info><dc:creator>HIDDEN AUTHOR</dc:creator>'
    '<dc:date>2026-11-17T00:00:00</dc:date>$comment</office:change-info>';

String _textHistory(String deleted) =>
    '<text:tracked-changes><text:changed-region text:id="deleted">'
    '<text:deletion>${_changeInfo('<text:p>HIDDEN COMMENT</text:p>')}'
    '$deleted</text:deletion></text:changed-region>'
    '<text:changed-region text:id="inserted"><text:insertion>'
    '${_changeInfo('<text:p>HIDDEN INSERTION COMMENT</text:p>')}'
    '</text:insertion></text:changed-region></text:tracked-changes>';

void main() {
  test(
    'ODT stored revisions do not become current paragraphs or tables',
    () async {
      final history = _textHistory(
        '<text:p>HIDDEN DELETED WORDS</text:p>'
        '<table:table><table:table-row><table:table-cell>'
        '<text:p>HIDDEN DELETED CELL</text:p>'
        '</table:table-cell></table:table-row></table:table>',
      );
      final xml = _document(
        '$history<text:p>Before<text:change text:change-id="deleted"/>After'
        '<text:s/><text:change-start text:change-id="inserted"/>'
        '<text:span>current insertion</text:span>'
        '<text:change-end text:change-id="inserted"/></text:p>'
        '<table:table><table:table-row><table:table-cell>'
        '<text:p>Current cell</text:p>'
        '</table:table-cell></table:table-row></table:table>',
      );
      final bytes = _archive(xml);
      final result = OfficeTextExtractor.extract(bytes, name: 'revisions.odt');
      expect(result.paragraphs, ['BeforeAfter current insertion']);
      expect(result.tables, [
        [
          ['Current cell'],
        ],
      ]);
      expect(
        await officeSearchText(bytes, 'revisions.odt', 65536),
        'BeforeAfter current insertion\nCurrent cell',
      );
      expect(utf8.decode(ZipReader.fromBytes(bytes).read('content.xml')), xml);
    },
  );

  test(
    'ODS previous cell values and revision comments stay out of search',
    () async {
      final xml = _document(
        '<table:tracked-changes><table:cell-content-change table:id="c1">'
        '${_changeInfo('<text:p>HIDDEN CELL COMMENT</text:p>')}'
        '<table:cell-address table:column="0" table:row="0" table:table="0"/>'
        '<table:previous><table:change-track-table-cell office:value-type="string">'
        '<text:p>HIDDEN PREVIOUS VALUE</text:p>'
        '</table:change-track-table-cell></table:previous>'
        '</table:cell-content-change></table:tracked-changes>'
        '<table:table table:name="Current"><table:table-row><table:table-cell '
        'office:value-type="string"><text:p>Current value</text:p>'
        '</table:table-cell></table:table-row></table:table>',
        kind: 'spreadsheet',
      );
      final bytes = _archive(xml);
      final result = OfficeTextExtractor.extract(bytes, name: 'revisions.ods');
      expect(result.sheets.single.rows, [
        ['Current value'],
      ]);
      expect(
        await officeSearchText(bytes, 'revisions.ods', 65536),
        'Current value',
      );
      expect(
        OdsSheetReader.readBytes(bytes).firstSheet.cellA1('A1').value,
        'Current value',
      );
      expect(utf8.decode(ZipReader.fromBytes(bytes).read('content.xml')), xml);
    },
  );

  test(
    'revision containers use namespace identity and retain foreign text',
    () async {
      final xml = _document(
        '<alias:tracked-changes xmlns:alias="$_text">'
        '<alias:changed-region alias:id="deleted"><alias:deletion>'
        '${_changeInfo()}<alias:p>HIDDEN ALIAS</alias:p>'
        '</alias:deletion></alias:changed-region></alias:tracked-changes>'
        '<text:tracked-changes xmlns:text="urn:foreign">'
        '<visible:p xmlns:visible="$_text">Visible shadow</visible:p>'
        '</text:tracked-changes>'
        '<foreign:tracked-changes><text:p>Visible extension</text:p>'
        '</foreign:tracked-changes><text:p>Tail</text:p>',
      );
      final bytes = _archive(xml);
      expect(
        OfficeTextExtractor.extract(bytes, name: 'aliases.odt').paragraphs,
        ['Visible shadow', 'Visible extension', 'Tail'],
      );
      expect(
        await officeSearchText(bytes, 'aliases.odt', 65536),
        'Visible shadow\nVisible extension\nTail',
      );
      expect(utf8.decode(ZipReader.fromBytes(bytes).read('content.xml')), xml);
    },
  );

  for (final (extension, kind, prefix) in [
    ('odt', 'text', 'text'),
    ('ods', 'spreadsheet', 'table'),
  ]) {
    test(
      '$extension revision-only content does not trigger metadata fallback',
      () async {
        final history = prefix == 'text'
            ? '<text:changed-region text:id="c1"><text:insertion>'
                  '${_changeInfo()}</text:insertion></text:changed-region>'
            : '<table:insertion table:id="c1" table:type="row" '
                  'table:table="0" table:position="0">'
                  '${_changeInfo()}</table:insertion>';
        final xml = _document(
          '<$prefix:tracked-changes>$history</$prefix:tracked-changes>'
          '${extension == 'ods' ? '<table:table table:name="Empty"/>' : ''}',
          kind: kind,
        );
        final bytes = _archive(xml);
        expect(
          OfficeTextExtractor.extract(
            bytes,
            name: 'history.$extension',
          ).paragraphs,
          isEmpty,
        );
        expect(
          await officeSearchText(bytes, 'history.$extension', 65536),
          isEmpty,
        );
        expect(
          utf8.decode(ZipReader.fromBytes(bytes).read('content.xml')),
          xml,
        );
      },
    );
  }

  test(
    'stored revision whitespace is neither expanded nor charged to output',
    () async {
      final history = _textHistory(
        '<text:p><text:s text:c="999999999999999999999999"/>'
        '<text:s text:c="-1"/></text:p>',
      );
      final xml = _document('$history<text:p>A</text:p>');
      final bytes = _archive(xml);
      expect(
        OfficeTextExtractor.extract(bytes, name: 'bounded.odt').paragraphs,
        ['A'],
      );
      expect(await officeSearchText(bytes, 'bounded.odt', 65536), 'A');
      final root = XmlDocument.parse(xml).root!;
      final before = XmlDocument(root: root).toXmlString();
      final budget = OdfTextBudget(1);
      expect(readOdfText(root, budget), 'A');
      expect(budget.remaining, 0);
      expect(XmlDocument(root: root).toXmlString(), before);
    },
  );

  test('empty revision containers preserve following current stories', () async {
    final bytes = _archive(
      _document(
        '<text:tracked-changes/><text:p>Before</text:p>'
        '<text:tracked-changes></text:tracked-changes>'
        '<table:table><table:table-row><table:table-cell>'
        '<text:p>Cell</text:p></table:table-cell></table:table-row></table:table>'
        '<text:p>After</text:p>',
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

  test(
    'stored revisions still consume the selected package byte budget',
    () async {
      final history = _textHistory('<text:p>${'x' * 4096}</text:p>');
      final xml = _document('$history<text:p>A</text:p>');
      await expectLater(
        officeSearchText(
          _archive(xml),
          'package-budget.odt',
          utf8.encode(xml).length - 1,
        ),
        throwsA(isA<OfficeSearchLimitException>()),
      );
    },
  );
}

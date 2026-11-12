// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

List<TableFixtureParagraph> _row(int origin, {List<int> extra = const []}) => [
  const TableFixtureParagraph('Left\x07', depth: 1, cell: true),
  const TableFixtureParagraph('Right\x07', depth: 1, cell: true),
  TableFixtureParagraph(
    '\x07',
    depth: 1,
    row: true,
    widths: const [1200, 1200],
    extra: [
      ...tableFixtureDefinition([1200, 1200], origin: origin),
      ...extra,
    ],
  ),
];

XmlDocument _document(List<int> bytes) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content,
  ),
);

void main() {
  test('retains the signed first table edge instead of shifting content', () {
    for (final origin in [-108, 0, 720]) {
      final bytes = tableFixture(_row(origin));
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      expect(table.rows.single.originTwips, origin);
      expect(table.rows.single.cells.map((c) => c.widthTwips), [1200, 1200]);
      // The OOXML legacy indentation locates leading text; the signed
      // binary outer edge remains separate from the 108-twip cell margin.
      final xml = _document(convertLegacyWordToStructuredDocx(bytes).bytes);
      expect(
        xml.findAllElements('w:tblInd').single.getAttribute('w:w'),
        '${origin + 108}',
      );
      expect(
        xml.findAllElements('w:gridCol').map((e) => e.getAttribute('w:w')),
        ['1200', '1200'],
      );
    }
  });

  test('row origins share an absolute grid with missing edge cells', () {
    final bytes = tableFixture([..._row(-108), ..._row(492)]);
    final xml = _document(convertLegacyWordToStructuredDocx(bytes).bytes);
    expect(
      xml.findAllElements('w:gridCol').map((e) => e.getAttribute('w:w')),
      List.filled(5, '600'),
    );
    final rows = xml.findAllElements('w:tr').toList();
    expect(
      rows.first.findAllElements('w:gridAfter').single.getAttribute('w:val'),
      '1',
    );
    expect(
      rows.last.findAllElements('w:gridBefore').single.getAttribute('w:val'),
      '1',
    );
    expect(
      rows.last.findAllElements('w:wBefore').single.getAttribute('w:w'),
      '600',
    );
    expect(
      xml.findAllElements('w:gridSpan').map((e) => e.getAttribute('w:val')),
      List.filled(4, '2'),
    );
  });

  test(
    'explicit left and half-gap are ordered independently of cell widths',
    () {
      final bytes = tableFixture(
        _row(
          -108,
          extra: [
            ...wordSprm(0x9601, wordU16(720)),
            ...wordSprm(0x9602, wordU16(120)),
          ],
        ),
      );
      final table =
          parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable;
      expect(table.rows.single.originTwips, 600);
      expect(table.rows.single.cells.map((c) => c.widthTwips), [1200, 1200]);
      expect(
        () => parseLegacyWordDocument(
          tableFixture(_row(0, extra: wordSprm(0x9602, wordU16(-1)))),
        ),
        throwsFormatException,
      );
    },
  );
}

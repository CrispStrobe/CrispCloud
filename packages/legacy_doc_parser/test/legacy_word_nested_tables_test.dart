// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

void main() {
  test(
    'nested rows remain ordered cell blocks in the model, HTML and DOCX',
    () {
      final bytes = tableFixture([
        const TableFixtureParagraph('Outer before\r', depth: 1),
        const TableFixtureParagraph('Nested left\r', depth: 2, cell: true),
        const TableFixtureParagraph('Nested right\r', depth: 2, cell: true),
        const TableFixtureParagraph(
          '\r',
          depth: 2,
          row: true,
          widths: [900, 900],
        ),
        const TableFixtureParagraph('Outer after\x07', depth: 1, cell: true),
        const TableFixtureParagraph('Second cell\x07', depth: 1, cell: true),
        const TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: [2400, 1200],
        ),
        const TableFixtureParagraph('Following paragraph\r'),
      ]);
      final original = bytes.toList();
      final document = parseLegacyWordDocument(bytes);
      final outer = document.blocks.first as LegacyWordTable;
      final cell = outer.rows.single.cells.first;
      expect(cell.blocks.map((b) => b.runtimeType), [
        LegacyWordParagraph,
        LegacyWordTable,
        LegacyWordParagraph,
      ]);
      expect(cell.paragraphs.map((p) => p.runs.single.text), [
        'Outer before',
        'Outer after',
      ]);
      final nested = cell.blocks[1] as LegacyWordTable;
      expect(nested.rows.single.cells.map((c) => c.widthTwips), [900, 900]);
      expect(
        document.plainText,
        'Outer before\nNested left\tNested right\n'
        'Outer after\tSecond cell\nFollowing paragraph',
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.nestedTablesFlattened)),
      );
      expect(RegExp('<table ').allMatches(document.safeHtml), hasLength(2));
      expect(
        document.safeHtml.indexOf('Nested left'),
        greaterThan(document.safeHtml.indexOf('<td')),
      );

      final converted = convertLegacyWordToStructuredDocx(bytes);
      final archive = ZipDecoder().decodeBytes(converted.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      final body = xml.rootElement.getElement('w:body')!;
      final outerXml = body.getElement('w:tbl')!;
      final firstCell = outerXml.getElement('w:tr')!.findElements('w:tc').first;
      expect(firstCell.childElements.map((e) => e.name.local), [
        'tcPr',
        'p',
        'tbl',
        'p',
      ]);
      final nestedXml = firstCell.getElement('w:tbl')!;
      expect(nestedXml.getElement('w:tr')!.findElements('w:tc'), hasLength(2));
      expect(xml.findAllElements('w:t').map((e) => e.innerText), [
        'Outer before',
        'Nested left',
        'Nested right',
        'Outer after',
        'Second cell',
        'Following paragraph',
      ]);
      expect(bytes, original);
    },
  );

  test(
    'a cell can begin with a nested table and still retains its final paragraph',
    () {
      final document = parseLegacyWordDocument(
        tableFixture([
          const TableFixtureParagraph('Inner\r', depth: 2, cell: true),
          const TableFixtureParagraph('\r', depth: 2, row: true, widths: [720]),
          const TableFixtureParagraph('\x07', depth: 1, cell: true),
          const TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            widths: [1440],
          ),
        ]),
      );
      final cell =
          (document.blocks.single as LegacyWordTable).rows.single.cells.single;
      expect(cell.blocks.first, isA<LegacyWordTable>());
      expect(cell.blocks.last, isA<LegacyWordParagraph>());
      expect(cell.paragraphs.single.runs, isEmpty);
    },
  );

  test(
    'PDtap applies signed depth adjustments and restores out-of-table content',
    () {
      final document = parseLegacyWordDocument(
        tableFixture([
          TableFixtureParagraph(
            'Inner\r',
            depth: 1,
            cell: true,
            extra: [
              ...wordSprm(0x664a, wordU32(1)),
              ...wordSprm(0x244b, [1]),
            ],
          ),
          const TableFixtureParagraph('\r', depth: 2, row: true, widths: [720]),
          const TableFixtureParagraph('\x07', depth: 1, cell: true),
          const TableFixtureParagraph(
            '\x07',
            depth: 1,
            row: true,
            widths: [1440],
          ),
          TableFixtureParagraph(
            'Outside\r',
            depth: 1,
            extra: wordSprm(0x664a, wordU32(0xffffffff)),
          ),
        ]),
      );
      expect(document.blocks.last, isA<LegacyWordParagraph>());
      expect(
        (document.blocks.last as LegacyWordParagraph).runs.single.text,
        'Outside',
      );
    },
  );

  for (final (label, values) in <(String, List<TableFixtureParagraph>)>[
    (
      'missing nested cell mark',
      [
        const TableFixtureParagraph('Inner\r', depth: 2),
        const TableFixtureParagraph('\r', depth: 2, row: true, widths: [720]),
      ],
    ),
    (
      'wrong nested terminator',
      [const TableFixtureParagraph('Inner\x07', depth: 2, cell: true)],
    ),
    (
      'missing outer row',
      [
        const TableFixtureParagraph('Outer\x07', depth: 1, cell: true),
        const TableFixtureParagraph('Outside\r'),
      ],
    ),
    (
      'negative table adjustment',
      [
        TableFixtureParagraph(
          'Invalid\r',
          extra: wordSprm(0x664a, wordU32(0xffffffff)),
        ),
      ],
    ),
    (
      'row definition count mismatch',
      [
        const TableFixtureParagraph('Outer\x07', depth: 1, cell: true),
        const TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: [720, 720],
        ),
      ],
    ),
  ]) {
    test(
      'rejects $label',
      () => expect(
        () => parseLegacyWordDocument(tableFixture(values)),
        throwsFormatException,
      ),
    );
  }
}

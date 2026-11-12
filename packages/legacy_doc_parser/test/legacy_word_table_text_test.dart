// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

List<int> _cnf(int code, int mask, List<int> properties) =>
    wordSprm(code, [properties.length + 2, ...wordU16(mask), ...properties]);
List<int> _style(int id, [int options = 0x20]) => [
  ...wordSprm(0x563a, wordU16(id)),
  ...wordSprm(0x740a, [...wordU16(0), ...wordU16(options)]),
];
WordFixtureStyle _textStyle({
  List<int> p = const [],
  List<int> c = const [],
  int parent = 0xfff,
}) => WordFixtureStyle(
  name: 'Table text',
  table: true,
  parentIndex: parent,
  paragraphProperties: p,
  characterProperties: c,
);
Uint8List _one(
  WordFixtureStyle style, {
  List<int> paragraph = const [],
  List<int> character = const [],
  Map<int, WordFixtureStyle> styles = const {},
}) => tableFixture(
  [
    TableFixtureParagraph(
      'Cell\x07',
      depth: 1,
      cell: true,
      extra: paragraph,
      character: character,
    ),
    TableFixtureParagraph(
      '\x07',
      depth: 1,
      row: true,
      widths: const [2000],
      extra: _style(20),
    ),
  ],
  styles: {
    0: const WordFixtureStyle(name: 'Normal'),
    ...styles,
    20: style,
  },
);
LegacyWordParagraph _paragraph(Uint8List bytes) =>
    (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
        .rows
        .single
        .cells
        .single
        .paragraphs
        .single;
XmlDocument _part(Uint8List bytes, String name) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWordToStructuredDocx(bytes).bytes)
        .findFile(name)!
        .content,
  ),
);

void main() {
  test(
    'nonconforming style highlight remains on runs without invalid style XML',
    () {
      final bytes = _one(_textStyle(c: wordSprm(0x2a0c, [7])));
      expect(_paragraph(bytes).runs.single.style.highlightHex, 'FFFF00');
      expect(
        _part(bytes, 'word/styles.xml').findAllElements('w:highlight'),
        isEmpty,
      );
      expect(
        _part(bytes, 'word/document.xml')
            .findAllElements('w:highlight')
            .map((element) => element.getAttribute('w:val')),
        contains('yellow'),
      );
      final result = convertLegacyWordToStructuredDocx(bytes);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
      final evidence = ZipDecoder()
          .decodeBytes(result.bytes)
          .files
          .where((file) => file.name.endsWith('.json'))
          .map((file) => utf8.decode(file.content))
          .join();
      expect(evidence, contains('tableStyleDirectOnlyProperty'));
    },
  );

  test(
    'conditional paragraph and run differences precede direct properties',
    () {
      final style = _textStyle(
        p: [
          ...wordSprm(0xa413, wordU16(120)),
          ..._cnf(0xc666, 1, wordSprm(0x2403, [1])),
        ],
        c: [
          ...wordSprm(0x4a43, wordU16(26)),
          ..._cnf(0xca85, 1, wordSprm(0x0835, [1])),
        ],
      );
      final ordinary = _paragraph(_one(style));
      expect(ordinary.style.alignment, LegacyWordAlignment.center);
      expect(ordinary.style.spaceBeforeTwips, 120);
      expect(ordinary.runs.single.style.bold, isTrue);
      expect(ordinary.runs.single.style.fontSizeHalfPoints, 26);
      expect(ordinary.mark!.style.bold, isTrue);
      final direct = _paragraph(
        _one(
          style,
          paragraph: wordSprm(0x2403, [0]),
          character: wordSprm(0x0835, [0]),
        ),
      );
      expect(direct.style.alignment, LegacyWordAlignment.left);
      expect(direct.runs.single.style.bold, isFalse);
      expect(direct.style.spaceBeforeTwips, 120);
    },
  );

  test(
    'evaluates source toggles before coalescing identical unstyled runs',
    () {
      final bytes = StructuredWordFixture(
        pieces: const [WordFixturePiece('ABCD\x07\x07')],
        paragraphRuns: [
          WordFixtureFkpRun(8192, 8197, properties: wordSprm(0x2416, [1])),
          WordFixtureFkpRun(
            8197,
            8198,
            properties: [
              ...wordSprm(0x2416, [1]),
              ...wordSprm(0x2417, [1]),
              ...tableFixtureDefinition([2000]),
              ..._style(20),
            ],
          ),
        ],
        characterRuns: [
          const WordFixtureFkpRun(8192, 8193),
          WordFixtureFkpRun(8193, 8194, properties: wordSprm(0x0835, [0])),
          WordFixtureFkpRun(8194, 8195, properties: wordSprm(0x0835, [0x80])),
          WordFixtureFkpRun(8195, 8196, properties: wordSprm(0x0835, [0x81])),
          const WordFixtureFkpRun(8196, 8198),
        ],
        styles: {
          0: const WordFixtureStyle(name: 'Normal'),
          20: _textStyle(c: _cnf(0xca85, 1, wordSprm(0x0835, [1]))),
        },
      ).build();
      final paragraph = _paragraph(bytes);
      expect(paragraph.runs.map((r) => (r.text, r.style.bold)), [
        ('A', true),
        ('B', false),
        ('C', true),
        ('D', false),
      ]);
      expect(paragraph.runs.map((r) => (r.startCp, r.endCp)), [
        (0, 1),
        (1, 2),
        (2, 3),
        (3, 4),
      ]);
    },
  );

  test('paragraph and character style toggles inherit the table context', () {
    final table = _textStyle(c: wordSprm(0x0835, [1]));
    final bytes = _one(
      table,
      paragraph: wordSprm(0x4600, wordU16(1)),
      character: wordSprm(0x4a30, wordU16(10)),
      styles: {
        1: WordFixtureStyle(
          name: 'Inherited bold',
          characterProperties: wordSprm(0x0835, [0x80]),
        ),
        10: WordFixtureStyle(
          name: 'Invert bold',
          character: true,
          characterProperties: wordSprm(0x0835, [0x81]),
        ),
      },
    );
    expect(_paragraph(bytes).runs.single.style.bold, isFalse);
    final withoutCharacter = _one(
      table,
      paragraph: wordSprm(0x4600, wordU16(1)),
      styles: {
        1: WordFixtureStyle(
          name: 'Inherited bold',
          characterProperties: wordSprm(0x0835, [0x80]),
        ),
      },
    );
    expect(_paragraph(withoutCharacter).runs.single.style.bold, isTrue);
  });

  test('innermost table supplies text conditions independently', () {
    final bytes = tableFixture(
      [
        const TableFixtureParagraph('Outer\r', depth: 1),
        const TableFixtureParagraph('Inner\r', depth: 2, cell: true),
        TableFixtureParagraph(
          '\r',
          depth: 2,
          row: true,
          widths: const [1200],
          extra: _style(21),
        ),
        const TableFixtureParagraph('\x07', depth: 1, cell: true),
        TableFixtureParagraph(
          '\x07',
          depth: 1,
          row: true,
          widths: const [2400],
          extra: _style(20),
        ),
      ],
      styles: {
        0: const WordFixtureStyle(name: 'Normal'),
        20: _textStyle(c: wordSprm(0x0835, [1])),
        21: _textStyle(c: wordSprm(0x0836, [1])),
      },
    );
    final cell =
        (parseLegacyWordDocument(bytes).blocks.single as LegacyWordTable)
            .rows
            .single
            .cells
            .single;
    final outer = cell.paragraphs.first.runs.single.style;
    final inner = (cell.blocks.whereType<LegacyWordTable>().single)
        .rows
        .single
        .cells
        .single
        .paragraphs
        .single
        .runs
        .single
        .style;
    expect((outer.bold, outer.italic), (true, false));
    expect((inner.bold, inner.italic), (false, true));
  });

  test(
    'native style rules retain only their explicit property differences',
    () {
      final bytes = _one(
        _textStyle(
          p: [
            ...wordSprm(0xa413, wordU16(120)),
            ..._cnf(0xc666, 1, wordSprm(0x2403, [1])),
          ],
          c: _cnf(0xca85, 1, wordSprm(0x0835, [1])),
        ),
      );
      final styles = _part(bytes, 'word/styles.xml');
      final table = styles
          .findAllElements('w:style')
          .singleWhere((style) => style.getAttribute('w:type') == 'table');
      final baseSpacing = table.getElement('w:pPr')!.getElement('w:spacing')!;
      expect(baseSpacing.getAttribute('w:before'), '120');
      expect(baseSpacing.getAttribute('w:after'), isNull);
      final rule = table.findAllElements('w:tblStylePr').single;
      expect(rule.getAttribute('w:type'), 'firstRow');
      expect(
        rule.findAllElements('w:jc').single.getAttribute('w:val'),
        'center',
      );
      expect(rule.findAllElements('w:b').single.getAttribute('w:val'), '1');
      expect(rule.findAllElements('w:i'), isEmpty);
      expect(rule.findAllElements('w:spacing'), isEmpty);
      expect(table.getElement('w:rPr'), isNull);
    },
  );

  test('relative table toggles are resolved and retained as evidence', () {
    final bytes = _one(
      _textStyle(
        c: [
          ...wordSprm(0x0835, [1]),
          ..._cnf(0xca85, 1, wordSprm(0x0835, [0x81])),
        ],
      ),
    );
    expect(_paragraph(bytes).runs.single.style.bold, isFalse);
    final model = parseLegacyWordDocument(bytes).tableStyles.single;
    expect(
      model
          .textConditions[LegacyWordTableCondition.firstRow]!
          .relativeCharacterToggles[LegacyWordTableCharacterProperty.bold],
      0x81,
    );
    final result = convertLegacyWordToStructuredDocx(bytes);
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.partialFormatting),
    );
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final evidence = archive.files
        .where((f) => f.name.endsWith('.json'))
        .map((f) => utf8.decode(f.content))
        .join();
    expect(evidence, contains('tableTextRelativeToggle'));
  });

  for (final item in [
    ('combined paragraph condition', _textStyle(p: _cnf(0xc666, 3, []))),
    (
      'nested character condition',
      _textStyle(c: _cnf(0xca85, 1, _cnf(0xca85, 1, []))),
    ),
  ]) {
    test('rejects ${item.$1}', () {
      expect(
        () => parseLegacyWordDocument(_one(item.$2)),
        throwsFormatException,
      );
    });
  }
}

import 'dart:typed_data';

import 'package:crisp_cloud/services/legacy_word_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/structured_word_fixture.dart';

List<LegacyWordParagraph> _paragraphs(LegacyWordDocument document) =>
    document.blocks.whereType<LegacyWordParagraph>().toList();

String _text(LegacyWordParagraph paragraph) =>
    paragraph.runs.map((run) => run.text).join();

LegacyWordRun _run(LegacyWordParagraph paragraph, String text) =>
    paragraph.runs.singleWhere((run) => run.text == text);

List<int> _property(int opcode, int value) => wordSprm(opcode, [value]);
List<int> _property16(int opcode, int value) =>
    wordSprm(opcode, wordU16(value));

void main() {
  test('maps mixed disordered pieces to physical character properties', () {
    final fixture = StructuredWordFixture(
      pieces: const [
        WordFixturePiece('First ', offset: 12288),
        WordFixturePiece('α\r', compressed: false),
        WordFixturePiece('Next\r', offset: 10240),
      ],
      characterRuns: [
        WordFixtureFkpRun(12288, 12294, properties: _property(0x0835, 1)),
        WordFixtureFkpRun(8192, 8196, properties: _property(0x0836, 1)),
        WordFixtureFkpRun(10240, 10245, properties: _property(0x2a3e, 1)),
      ],
      paragraphRuns: [
        WordFixtureFkpRun(12288, 12294, properties: _property(0x2403, 1)),
        WordFixtureFkpRun(8192, 8196, properties: _property(0x2403, 2)),
        WordFixtureFkpRun(10240, 10245, properties: _property(0x2403, 0)),
      ],
    );
    final bytes = fixture.build();
    final before = Uint8List.fromList(bytes);
    final document = parseLegacyWordDocument(bytes);
    final paragraphs = _paragraphs(document);
    expect(paragraphs.map(_text), ['First α', 'Next']);
    expect(_run(paragraphs[0], 'First ').style.bold, isTrue);
    expect(_run(paragraphs[0], 'α').style.italic, isTrue);
    expect(_run(paragraphs[1], 'Next').style.underline, isTrue);
    // Paragraph properties follow the terminating mark in the Unicode piece,
    // not the physically later piece containing the paragraph's first word.
    expect(paragraphs[0].style.alignment, LegacyWordAlignment.right);
    expect(paragraphs[1].style.alignment, LegacyWordAlignment.left);
    expect(paragraphs.map((p) => (p.startCp, p.endCp)), [(0, 8), (8, 13)]);
    expect(document.plainText, isNot(contains('UNREFERENCED')));
    expect(bytes, before);
  });

  test('compressed Unicode mapping does not change with the FIB locale', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        languageId: 0x0419,
        pieces: const [WordFixturePiece('\xe9\x81\x93X\x94\r')],
      ).build(),
    );
    expect(_paragraphs(document).map(_text).join(), 'é\u0081“X”');
  });

  test('retains a surrogate pair split between physical Unicode pieces', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [
          WordFixturePiece('A\ud83d', offset: 12288, compressed: false),
          WordFixturePiece('\ude00\r', compressed: false),
        ],
      ).build(),
    );
    expect(_paragraphs(document).map(_text).join(), 'A😀');
    expect(document.safeHtml, contains('😀'));
    expect(document.safeHtml, isNot(contains('�')));
  });

  test('reads the complete cb=0 PAPX including its last property', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Kept\r')],
        paragraphRuns: [
          WordFixtureFkpRun(
            8192,
            8197,
            properties: [..._property(0x2403, 1), ..._property(0x2405, 1)],
          ),
        ],
      ).build(),
    );
    final style = _paragraphs(document).single.style;
    expect(style.alignment, LegacyWordAlignment.center);
    expect(style.keepTogether, isTrue);
  });

  test('inherits custom styles and resolves toggles against the style', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('AB\r')],
        styles: {
          0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
          1: WordFixtureStyle(
            name: 'Heading 1',
            builtinId: 1,
            parentIndex: 0,
            paragraphProperties: _property(0x2640, 0),
            characterProperties: [
              ..._property(0x0835, 1),
              ..._property16(0x4a43, 32),
            ],
          ),
          15: const WordFixtureStyle(name: 'Derived heading', parentIndex: 1),
        },
        paragraphRuns: const [WordFixtureFkpRun(8192, 8195, styleIndex: 15)],
        characterRuns: [
          WordFixtureFkpRun(
            8192,
            8193,
            properties: [..._property(0x0835, 0), ..._property(0x0835, 0x80)],
          ),
          WordFixtureFkpRun(
            8193,
            8195,
            properties: [..._property(0x0835, 1), ..._property(0x0835, 0x81)],
          ),
        ],
      ).build(),
    );
    final paragraph = _paragraphs(document).single;
    expect(paragraph.style.styleName, 'Derived heading');
    expect(paragraph.style.headingLevel, 1);
    expect(_run(paragraph, 'A').style.bold, isTrue);
    expect(_run(paragraph, 'B').style.bold, isFalse);
    expect(
      paragraph.runs.every((r) => r.style.fontSizeHalfPoints == 32),
      isTrue,
    );
  });

  test('piece PRM1 overrides direct CHPX and the terminal PAPX', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Piece\r', prm: 1)],
        prcs: [
          [..._property(0x0835, 0), ..._property(0x2403, 2)],
        ],
        characterRuns: [
          WordFixtureFkpRun(8192, 8198, properties: _property(0x0835, 1)),
        ],
        paragraphRuns: [
          WordFixtureFkpRun(8192, 8198, properties: _property(0x2403, 1)),
        ],
      ).build(),
    );
    final paragraph = _paragraphs(document).single;
    expect(paragraph.style.alignment, LegacyWordAlignment.right);
    expect(paragraph.runs.every((run) => !run.style.bold), isTrue);
  });

  test('PRM0 deleted text remains marked instead of accepting revisions', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Deleted\r', prm: 0x0182)],
      ).build(),
    );
    final paragraph = _paragraphs(document).single;
    expect(_text(paragraph), 'Deleted');
    expect(paragraph.runs.every((run) => run.deleted), isTrue);
    expect(document.plainText, contains('Deleted'));
    expect(document.safeHtml, contains('<del'));
  });

  test(
    'keeps inserted and deleted text with its revision authors and dates',
    () {
      const date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
      final document = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: const [WordFixturePiece('oldnew\r')],
          characterRuns: [
            WordFixtureFkpRun(
              8192,
              8195,
              properties: [
                ..._property(0x0800, 1),
                ..._property16(0x4863, 1),
                ...wordSprm(0x6864, wordU32(date)),
              ],
            ),
            WordFixtureFkpRun(
              8195,
              8199,
              properties: [
                ..._property(0x0801, 1),
                ..._property16(0x4804, 2),
                ...wordSprm(0x6805, wordU32(date)),
              ],
            ),
          ],
          extraTablePairs: {
            51: _stringTable(['Unknown', 'Alice', 'Bob']),
          },
        ).build(),
      );
      final paragraph = _paragraphs(document).single;
      final old = _run(paragraph, 'old');
      final current = _run(paragraph, 'new');
      expect(old.deleted, isTrue);
      expect(old.inserted, isFalse);
      expect(old.revisionAuthor, 'Alice');
      expect(current.inserted, isTrue);
      expect(current.deleted, isFalse);
      expect(current.revisionAuthor, 'Bob');
      expect(
        (
          old.revisionTime?.year,
          old.revisionTime?.month,
          old.revisionTime?.day,
          old.revisionTime?.hour,
          old.revisionTime?.minute,
        ),
        (2026, 11, 12, 8, 45),
      );
      expect(document.safeHtml, contains('<del'));
      expect(document.safeHtml, contains('<ins'));
      expect(document.plainText, contains('oldnew'));
    },
  );

  test(
    'table cells retain multiple paragraphs, widths and actual row flags',
    () {
      final document = parseLegacyWordDocument(tableWordFixture());
      final table = document.blocks.first as LegacyWordTable;
      expect(table.rows, hasLength(1));
      final row = table.rows.single;
      expect(row.isHeader, isFalse);
      expect(row.cells, hasLength(2));
      expect(row.cells[0].paragraphs.map(_text), ['A', 'B']);
      expect(row.cells[1].paragraphs.map(_text), ['C']);
      expect(row.cells.map((cell) => cell.widthTwips), [1440, 2160]);
      expect(_paragraphs(document).map(_text), ['After']);
      expect(document.safeHtml, contains('<table'));
    },
  );

  test('TCGRF horizontal merge values are 2=start and 1=continuation', () {
    final document = parseLegacyWordDocument(tableWordFixture(merged: true));
    final row = (document.blocks.first as LegacyWordTable).rows.single;
    expect(row.cells[0].mergeStart, isTrue);
    expect(row.cells[0].mergeContinue, isFalse);
    expect(row.cells[1].mergeStart, isFalse);
    expect(row.cells[1].mergeContinue, isTrue);
    // A continuation cell's model is retained even when its presentation is
    // suppressed by the merge; conversion must not silently discard its data.
    expect(row.cells[1].paragraphs.map(_text), ['C']);
  });

  test('distinguishes section terminators from manual page breaks', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('One\fTwo\fLast\r')],
        sections: [
          WordFixtureSection(8, [
            ..._property16(0xb01f, 12240),
            ..._property16(0xb020, 15840),
            ..._property16(0xb021, 1440),
            ..._property16(0xb022, 720),
            ..._property16(0x9023, 1080),
            ..._property16(0x9024, 1080),
            ..._property16(0x500b, 1),
            ..._property16(0x900c, 360),
            ..._property(0x3009, 0),
          ]),
          WordFixtureSection(13, [
            ..._property16(0xb01f, 15840),
            ..._property16(0xb020, 12240),
            ..._property(0x301d, 2),
          ]),
        ],
      ).build(),
    );
    expect(document.sections, hasLength(2));
    final first = document.sections.first;
    expect((first.startCp, first.endCp), (0, 8));
    expect((first.pageWidthTwips, first.pageHeightTwips), (12240, 15840));
    expect((first.marginLeftTwips, first.marginRightTwips), (1440, 720));
    expect((first.marginTopTwips, first.marginBottomTwips), (1080, 1080));
    expect((first.columns, first.columnsSpaceTwips), (2, 360));
    expect(first.breakKind, LegacyWordSectionBreak.continuous);
    expect(document.sections.last.landscape, isTrue);
    final text = _paragraphs(document).map(_text).join('|');
    expect(text, contains('One\fTwo'));
    expect(text, contains('Last'));
    expect(text.split('\f'), hasLength(2));
  });

  test('preserves stored field results and escapes generated HTML', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [
          WordFixturePiece(
            'Before \x13HYPERLINK "private-instruction"\x14'
            '<script>&link\x15 after\r',
          ),
        ],
      ).build(),
    );
    expect(
      _paragraphs(document).map(_text).join(),
      'Before <script>&link after',
    );
    expect(document.safeHtml, isNot(contains('<script>')));
    expect(document.safeHtml, contains('&lt;script&gt;&amp;link'));
    expect(document.safeHtml, isNot(contains('private-instruction')));
    expect(
      document.warnings,
      contains(LegacyWordWarning.fieldsUseStoredResults),
    );
  });

  test('does not invent decimal numbering for unknown list definitions', () {
    final document = parseLegacyWordDocument(
      StructuredWordFixture(
        pieces: const [WordFixturePiece('Item\r')],
        paragraphRuns: [
          WordFixtureFkpRun(
            8192,
            8197,
            properties: [..._property16(0x460b, 7), ..._property(0x260a, 2)],
          ),
        ],
      ).build(),
    );
    final paragraph = _paragraphs(document).single;
    expect((paragraph.style.listId, paragraph.style.listLevel), (7, 2));
    expect(_text(paragraph), 'Item');
    expect(
      document.warnings,
      contains(LegacyWordWarning.numberingNotReconstructed),
    );
    expect(document.safeHtml, isNot(contains('<ol')));
  });

  test('rejects malformed FKP payloads, PRM references and style cycles', () {
    final truncated =
        StructuredWordFixture(
          pieces: const [WordFixturePiece('Text\r')],
          characterRuns: [
            WordFixtureFkpRun(8192, 8197, properties: _property(0x0835, 1)),
          ],
        ).build(
          mutate: (word, _) {
            const descriptor = StructuredWordFixture.characterFkpOffset + 8;
            final payload =
                StructuredWordFixture.characterFkpOffset +
                2 * word.getUint8(descriptor);
            word.setUint8(payload, 255);
          },
        );
    final missingPrc = StructuredWordFixture(
      pieces: const [WordFixturePiece('Text\r', prm: 3)],
    ).build();
    final cycle = StructuredWordFixture(
      pieces: const [WordFixturePiece('Text\r')],
      styles: const {
        0: WordFixtureStyle(name: 'Normal', builtinId: 0),
        15: WordFixtureStyle(name: 'Cycle A', parentIndex: 16),
        16: WordFixtureStyle(name: 'Cycle B', parentIndex: 15),
      },
      paragraphRuns: const [WordFixtureFkpRun(8192, 8197, styleIndex: 15)],
    ).build();
    for (final bytes in [truncated, missingPrc, cycle]) {
      expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
    }
  });
}

List<int> _stringTable(List<String> strings) => [
  ...wordU16(0xffff),
  ...wordU16(strings.length),
  ...wordU16(0),
  for (final value in strings) ...[
    ...wordU16(value.length),
    for (final unit in value.codeUnits) ...wordU16(unit),
  ],
];

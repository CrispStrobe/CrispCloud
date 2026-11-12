// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/src/legacy_word_document.dart';
import 'package:test/test.dart';

import 'support/decorated_word_fixture.dart';
import 'support/structured_word_fixture.dart';

LegacyWordParagraphStyle _style(
  List<int> operations, {
  List<int> inherited = const [],
}) =>
    (parseLegacyWordDocument(
              paragraphDecorationFixture(operations, inherited: inherited),
            ).blocks.single
            as LegacyWordParagraph)
        .style;

void main() {
  test(
    'custom tabs inherit and delete stops within 25 twips before adding',
    () {
      final style = _style(
        wordTabChange(deleted: [625], added: [(1500, 2, 1)]),
        inherited: wordTabChange(
          added: [(600, 0, 0), (1200, 1, 0), (1800, 3, 2)],
        ),
      );
      expect(style.tabs.map((t) => t.positionTwips), [1200, 1500, 1800]);
      expect(style.tabs[1].alignment, LegacyWordTabAlignment.right);
      expect(style.tabs[1].leader, LegacyWordTabLeader.dot);
      expect(style.tabs.last.alignment, LegacyWordTabAlignment.decimal);
    },
  );
  test('close deletion uses independent distances with a 25-twip minimum', () {
    final style = _style(
      wordTabChange(
        close: true,
        deleted: [600, 1500],
        distances: [0, 200],
        added: [(2400, 4, 6)],
      ),
      inherited: wordTabChange(
        added: [(620, 0, 0), (1300, 0, 0), (1700, 0, 0), (2100, 0, 0)],
      ),
    );
    expect(style.tabs.map((t) => t.positionTwips), [2100, 2400]);
    expect(style.tabs.last.alignment, LegacyWordTabAlignment.bar);
    expect(style.tabs.last.leader, LegacyWordTabLeader.none);
  });
  test('extended cb255 tab operands use their computed bounded length', () {
    final inherited = wordTabChange(
      added: [for (var i = 0; i < 64; i++) (i * 100, 0, 0)],
    );
    final operation = wordTabChange(
      close: true,
      extended: true,
      deleted: [for (var i = 0; i < 32; i++) i * 100],
      added: [for (var i = 0; i < 32; i++) (10000 + i * 100, 6, 5)],
    );
    final style = _style(operation, inherited: inherited);
    expect(style.tabs, hasLength(64));
    expect(style.tabs.first.positionTwips, 3200);
    expect(style.tabs.last.alignment, LegacyWordTabAlignment.list);
    expect(style.tabs.last.leader, LegacyWordTabLeader.middleDot);
  });
  test(
    'default tab interval comes from document options without rewriting run tabs',
    () {
      final document = parseLegacyWordDocument(
        paragraphDecorationFixture([], defaultTabStopTwips: 960),
      );
      expect(document.defaultTabStopTwips, 960);
      expect(document.plainText, 'Left\tRight');
      expect(
        parseLegacyWordDocument(
          paragraphDecorationFixture([], defaultTabStopTwips: 0),
        ).defaultTabStopTwips,
        isNull,
      );
    },
  );
  test(
    'invalid tab descriptors, ordering, truncation and final count fail explicitly',
    () {
      for (final operation in [
        wordTabChange(added: [(200, 5, 0)]),
        wordTabChange(added: [(200, 0, 6)]),
        wordTabChange(added: [(400, 0, 0), (200, 0, 0)]),
        wordSprm(0xc60d, [2, 0, 1]),
      ]) {
        expect(() => _style(operation), throwsFormatException);
      }
      expect(
        () => _style(
          wordTabChange(added: [(10000, 0, 0)]),
          inherited: wordTabChange(
            added: [for (var i = 0; i < 64; i++) (i * 100, 0, 0)],
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('modern shading keeps foreground separate from clear background', () {
    final clear = _style(wordParagraphShading()).shading!;
    expect(
      (clear.pattern, clear.foregroundHex, clear.backgroundHex),
      ('clear', '112233', 'AABBCC'),
    );
    final solid = _style(wordParagraphShading(pattern: 1)).shading!;
    expect(solid.pattern, 'solid');
    final stripe = _style(wordParagraphShading(pattern: 20)).shading!;
    expect(stripe.pattern, 'thinHorzStripe');
    expect(stripe.rawPattern, 20);
  });
  test(
    'legacy shading palette bits and Nil resets follow their exact fields',
    () {
      final shade = _style(wordSprm(0x442d, wordU16(6 | (4 << 5)))).shading!;
      expect(
        (shade.pattern, shade.foregroundHex, shade.backgroundHex),
        ('clear', 'FF0000', '00FF00'),
      );
      expect(_style(wordSprm(0x442d, wordU16(0xffff))).shading!.pattern, 'nil');
      expect(
        _style(wordParagraphShading(pattern: 0xffff)).shading!.pattern,
        'nil',
      );
      expect(
        _style(
          wordParagraphShading(foreground: 0xffffffff, background: 0xffffffff),
        ).shading!.pattern,
        'nil',
      );
    },
  );
  test(
    'valid legacy-only shading is explicit instead of a different OOXML pattern',
    () {
      final document = parseLegacyWordDocument(
        paragraphDecorationFixture(wordParagraphShading(pattern: 35)),
      );
      final shade =
          (document.blocks.single as LegacyWordParagraph).style.shading!;
      expect(shade.pattern, isNull);
      expect(shade.rawPattern, 35);
      expect(
        document.warnings,
        contains(LegacyWordWarning.unsupportedFormatting),
      );
    },
  );
  test(
    'border cascade keeps independent sides and applies explicit none resets',
    () {
      final style = _style(
        [
          ...wordParagraphBorder(0, type: 0),
          ...wordParagraphBorder(
            2,
            type: 3,
            width: 1,
            spacing: 7,
            shadow: true,
            frame: true,
            unused: 255,
          ),
        ],
        inherited: [
          ...wordParagraphBorder(0),
          ...wordParagraphBorder(1, old: true, type: 6, color: 6, unused: 128),
        ],
      );
      expect(style.borders[LegacyWordBorderSide.top]!.style, 'none');
      expect(style.borders[LegacyWordBorderSide.left]!.style, 'dotted');
      expect(style.borders[LegacyWordBorderSide.left]!.colorHex, 'FF0000');
      final bottom = style.borders[LegacyWordBorderSide.bottom]!;
      expect(
        (
          bottom.style,
          bottom.widthEighthPoints,
          bottom.spacingPoints,
          bottom.shadow,
          bottom.frame,
        ),
        ('double', 2, 7, true, true),
      );
    },
  );
  test('between and inert bar borders retain their distinct source sides', () {
    final style = _style([
      ...wordParagraphBorder(4, type: 7),
      ...wordParagraphBorder(5, old: true, type: 1, color: 1),
    ]);
    expect(style.borders[LegacyWordBorderSide.between]!.style, 'dashed');
    expect(style.borders[LegacyWordBorderSide.bar]!.rawType, 1);
  });
  test(
    'invalid paragraph border types and truncated shading fail explicitly',
    () {
      for (final operation in [
        wordParagraphBorder(0, type: 2),
        wordParagraphBorder(0, type: 0x40),
        wordParagraphBorder(0, old: true, type: 26, color: 1),
        wordSprm(0xc64d, [9, ...List.filled(9, 0)]),
        wordParagraphShading(pattern: 26),
      ]) {
        expect(() => _style(operation), throwsFormatException);
      }
    },
  );
  test(
    'table-cell modern shading uses each cell foreground/background/pattern',
    () {
      final values = [
        ...wordShading(background: 0x000000ff),
        ...wordShading(foreground: 0x0000ff00, pattern: 1),
      ];
      final document = parseLegacyWordDocument(
        tableDecorationFixture(wordSprm(0xd612, [values.length, ...values])),
      );
      final cells =
          (document.blocks.first as LegacyWordTable).rows.single.cells;
      expect(cells[0].shading!.backgroundHex, 'FF0000');
      expect(cells[1].shading!.foregroundHex, '00FF00');
      expect(cells[1].shading!.pattern, 'solid');
    },
  );
  test(
    'cell shading chunks start at cells 23 and 45, not at the first cell',
    () {
      for (final (opcode, cells, index) in [
        (0xd616, 23, 22),
        (0xd60c, 45, 44),
      ]) {
        final document = parseLegacyWordDocument(
          tableDecorationFixture(
            wordSprm(opcode, [10, ...wordShading(background: 0x00ff0000)]),
            cells: cells,
          ),
        );
        final row = (document.blocks.first as LegacyWordTable).rows.single;
        expect(row.cells.first.shading, isNull);
        expect(row.cells[index].shading!.backgroundHex, '0000FF');
      }
    },
  );
  test(
    'a replacement shading array clears previously shaded trailing cells',
    () {
      final document = parseLegacyWordDocument(
        tableDecorationFixture([
          ...wordSprm(0xd612, [
            20,
            ...wordShading(),
            ...wordShading(pattern: 1),
          ]),
          ...wordSprm(0xd612, [10, ...wordShading(background: 0x000000ff)]),
        ]),
      );
      final cells =
          (document.blocks.first as LegacyWordTable).rows.single.cells;
      expect(cells.first.shading!.backgroundHex, 'FF0000');
      expect(cells.last.shading, isNull);
    },
  );
  test('legacy cell shading and raw table-style Nil are distinguished', () {
    var document = parseLegacyWordDocument(
      tableDecorationFixture(
        wordSprm(0xd609, [4, ...wordU16(6 | (4 << 5)), ...wordU16(0xffff)]),
      ),
    );
    var cells = (document.blocks.first as LegacyWordTable).rows.single.cells;
    expect(cells.first.shading!.backgroundHex, '00FF00');
    expect(cells.last.shading!.pattern, 'nil');
    document = parseLegacyWordDocument(
      tableDecorationFixture(
        wordSprm(0xd670, [10, ...wordShading(pattern: 0xffff)]),
      ),
    );
    expect(
      document.warnings,
      contains(LegacyWordWarning.unsupportedFormatting),
    );
  });
  test('rejects malformed or excessive table shading arrays', () {
    for (final values in [List.filled(11, 0), List.filled(230, 0)]) {
      expect(
        () => parseLegacyWordDocument(
          tableDecorationFixture(wordSprm(0xd612, [values.length, ...values])),
        ),
        throwsFormatException,
      );
    }
  });
}

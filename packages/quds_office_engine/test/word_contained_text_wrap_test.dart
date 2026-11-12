import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _fixture(String phase) {
  final package = OpcPackage.create(OpcPackageKind.word);
  final name = phase == 'unchanged'
      ? 'table_grid_source.xml'
      : 'table_grid_${phase}_expected.xml';
  package
      .getPart('/word/document.xml')!
      .writeText(File('test/fixtures/fidelity/$name').readAsStringSync());
  return WordDeserializer().read(package);
}

void _expectAllCellTextFits(WmlDocument document) {
  final layout = WordLayoutEngine(font: null).layout(document);
  final paragraphs = document.paragraphs.toList();
  for (var index = 0; index < paragraphs.length; index++) {
    _expectGlyphOwnership(
      paragraphs[index].text,
      layout.pages
          .expand((page) => page.lines)
          .where((line) => line.paragraphIndex == index)
          .expand((line) => line.glyphs)
          .map((glyph) => glyph.glyph),
    );
  }
  for (final page in layout.pages) {
    for (final line in page.lines) {
      final cells = page.frames.where(
        (box) =>
            box.kind == LaidOutBoxKind.tableCell &&
            box.paragraphIndex != null &&
            line.paragraphIndex >= box.paragraphIndex! &&
            line.paragraphIndex <= (box.paragraphEnd ?? box.paragraphIndex!),
      );
      if (cells.isEmpty) continue;
      final cell = cells.reduce((a, b) => a.width < b.width ? a : b);
      final text = paragraphs[line.paragraphIndex].text;
      expect(
        line.x,
        greaterThanOrEqualTo(cell.x + LaidOutLine.tableCellPad - .01),
      );
      expect(line.y, greaterThanOrEqualTo(cell.y - .01));
      expect(
        line.x + line.width,
        lessThanOrEqualTo(cell.x + cell.width - LaidOutLine.tableCellPad + .01),
        reason: 'Full text must fit the innermost cell: $text',
      );
      expect(
        line.y + line.height,
        lessThanOrEqualTo(cell.y + cell.height + .01),
        reason: 'The row must grow to contain all wrapped text: $text',
      );
    }
  }
}

double _unitWidth(int cp) => 1;

List<BrokenLine> _break(String text, double width, {int? baseLevel}) =>
    LineBreaker.breakLines(
      text: text,
      maxWidth: width,
      widthOf: _unitWidth,
      baseLevel: baseLevel,
      justify: false,
      breakLongWords: true,
    );

List<String> _sourceLines(String text, List<BrokenLine> lines) => [
  for (final line in lines) text.substring(line.logicalStart, line.logicalEnd),
];

void _expectGlyphOwnership(String text, Iterable<ShapedGlyph> glyphs) {
  final expected = <int>[];
  var offset = 0;
  for (final cp in text.runes) {
    if (cp != 32 && cp != 10 && cp != 13 && !Uax9Bidi.isInvisibleFormat(cp)) {
      expected.add(offset);
    }
    offset += cp > 0xffff ? 2 : 1;
  }
  final actual =
      glyphs
          .where((glyph) => !glyph.isSpace)
          .map((glyph) => glyph.logicalIndex)
          .toList()
        ..sort();
  expect(
    actual,
    expected,
    reason: 'Each original visible codepoint occurs once',
  );
}

void _expectWholeClusters(String text, List<BrokenLine> lines) {
  for (final cluster in GraphemeClusters.segment(text)) {
    final owners = <int>{
      for (var i = 0; i < lines.length; i++)
        if (lines[i].glyphs.any(
          (glyph) =>
              glyph.logicalIndex >= cluster.start &&
              glyph.logicalIndex < cluster.end,
        ))
          i,
    };
    expect(owners.length, lessThanOrEqualTo(1), reason: cluster.text);
  }
  _expectGlyphOwnership(text, lines.expand((line) => line.glyphs));
}

void main() {
  for (final phase in ['unchanged', 'format', 'replace', 'unmerge']) {
    test(
      '$phase nested cells display complete words through both save paths',
      () async {
        for (final isolate in [false, true]) {
          var document = _fixture(phase);
          for (var cycle = 0; cycle <= 3; cycle++) {
            _expectAllCellTextFits(document);
            if (cycle == 3) break;
            final bytes = isolate
                ? await OfficeIsolateSave.word(document)
                : WordSerializer().writeBytes(document);
            document = WordDeserializer().readBytes(bytes);
          }
        }
      },
    );
  }

  for (final framed in [false, true]) {
    test(
      '${framed ? 'frame' : 'cell'} wraps without changing body word policy',
      () {
        const text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
        WmlParagraph paragraph() => WmlParagraph(
          properties: WmlParagraphProps(spacingAfter: 0, lineSpacing: 1),
          inlines: [WmlRun(text: text)],
        );
        final body = paragraph();
        final contained = paragraph();
        const width = 60.0;
        final document = WmlDocument(
          sections: [
            WmlSection(
              pageSize: const WmlPageSize(width: 200, height: 800),
              margins: const WmlPageMargins(
                left: 24,
                right: 24,
                top: 24,
                bottom: 24,
              ),
              blocks: [
                body,
                if (framed)
                  WmlFrame(
                    x: 24,
                    y: 100,
                    width: width,
                    height: 600,
                    anchor: WmlFrameAnchor.page,
                    wrap: WmlFrameWrap.none,
                    blocks: [contained],
                  )
                else
                  WmlTable(
                    grid: [width],
                    rows: [
                      WmlTableRow(
                        cells: [
                          WmlTableCell(blocks: [contained]),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        );
        final lines = WordLayoutEngine(
          font: null,
        ).layout(document).pages.expand((page) => page.lines);
        expect(lines.where((line) => line.paragraphIndex == 0), hasLength(1));
        final wrapped = lines
            .where((line) => line.paragraphIndex == 1)
            .toList();
        expect(wrapped.length, greaterThan(1));
        final inner =
            width -
            2 * (framed ? LaidOutLine.framePad : LaidOutLine.tableCellPad);
        expect(wrapped.every((line) => line.width <= inner + .001), isTrue);
        _expectGlyphOwnership(
          text,
          wrapped.expand((line) => line.glyphs).map((glyph) => glyph.glyph),
        );
      },
    );
  }

  group('fixed-container line breaks', () {
    test('long words split only when explicitly requested', () {
      const text = 'ABCDEFGHIJK';
      final ordinary = LineBreaker.breakLines(
        text: text,
        maxWidth: 3,
        widthOf: _unitWidth,
        justify: false,
      );
      expect(ordinary.single.width, 11);
      final contained = _break(text, 3);
      expect(_sourceLines(text, contained), ['ABC', 'DEF', 'GHI', 'JK']);
      _expectWholeClusters(text, contained);
    });

    test('a fitting word moves intact before emergency splitting', () {
      const text = 'a bcde f';
      final lines = _break(text, 4);
      expect(_sourceLines(text, lines), ['a', 'bcde', 'f']);
      expect(lines.every((line) => line.width <= 4), isTrue);
      _expectWholeClusters(text, lines);
    });

    test('a long unbroken token makes bounded forward progress', () {
      final text = List.filled(4096, 'x').join();
      final lines = _break(text, 64);
      expect(lines, hasLength(64));
      expect(lines.every((line) => line.width == 64), isTrue);
      expect(_sourceLines(text, lines).join(), text);
    });

    test('repair also bounds a normally overflowing final line', () {
      const text = 'one two three';
      final lines = _break(text, 5);
      expect(_sourceLines(text, lines), ['one', 'two', 'three']);
      expect(lines.every((line) => line.width <= 5), isTrue);
      _expectWholeClusters(text, lines);
    });

    test('hard breaks and blank lines preserve every source offset', () {
      const text = 'abcd\r\n\r\nefgh\n';
      final lines = _break(text, 2);
      expect(_sourceLines(text, lines), ['ab', 'cd', '', 'ef', 'gh']);
      _expectWholeClusters(text, lines);
    });

    for (final sample in <({String text, double width, List<String> expected})>[
      (text: 'a\u0301b\u0308c\u0302', width: 2, expected: ['á', 'b̈', 'ĉ']),
      (text: '😀🧭🚀', width: 1, expected: ['😀', '🧭', '🚀']),
      (text: '🇵🇸🇬🇧🇺🇸', width: 2, expected: ['🇵🇸', '🇬🇧', '🇺🇸']),
      (text: '👍🏽👍🏻', width: 2, expected: ['👍🏽', '👍🏻']),
      (
        text: '👩🏽‍💻👨‍👩‍👧‍👦',
        width: 4,
        expected: ['👩🏽‍💻', '👨‍👩‍👧‍👦'],
      ),
      (text: '👩\u0301‍💻a\u0301', width: 3, expected: ['👩́‍💻', 'á']),
      (text: '각난', width: 3, expected: ['각', '난']),
    ]) {
      test('keeps authored Unicode clusters intact: ${sample.text}', () {
        final lines = _break(sample.text, sample.width);
        expect(_sourceLines(sample.text, lines), sample.expected);
        expect(lines.every((line) => line.width <= sample.width), isTrue);
        _expectWholeClusters(sample.text, lines);
      });
    }

    test('a cluster wider than its box stays whole and makes progress', () {
      const text = '👨‍👩‍👧‍👦Z';
      final lines = _break(text, 1);
      expect(_sourceLines(text, lines), ['👨‍👩‍👧‍👦', 'Z']);
      expect(lines.first.width, 4);
      _expectWholeClusters(text, lines);
    });

    test(
      'regional indicators pair from the start of each uninterrupted run',
      () {
        expect(
          GraphemeClusters.segment(
            '🇵🇸🇬🇧🇺!🇫🇷',
          ).map((cluster) => cluster.text),
          ['🇵🇸', '🇬🇧', '🇺', '!', '🇫🇷'],
        );
        expect(
          GraphemeClusters.segment('👍🏽👍🏻').map((cluster) => cluster.text),
          ['👍🏽', '👍🏻'],
        );
        for (final sample in <({String text, List<String> expected})>[
          (text: '🇵', expected: ['🇵']),
          (text: '🇵🇸', expected: ['🇵🇸']),
          (text: '🇵🇸🇬', expected: ['🇵🇸', '🇬']),
          (text: '🇵🇸🇬🇧', expected: ['🇵🇸', '🇬🇧']),
        ]) {
          expect(
            GraphemeClusters.segment(
              sample.text,
            ).map((cluster) => cluster.text),
            sample.expected,
          );
        }
      },
    );

    test('modifier sequences stay whole even with one-codepoint capacity', () {
      const text = '👍🏽👍🏻';
      final lines = _break(text, 1);
      expect(_sourceLines(text, lines), ['👍🏽', '👍🏻']);
      expect(lines.map((line) => line.width), [2, 2]);
      _expectWholeClusters(text, lines);
    });

    test('supplementary line ends use UTF-16 units in both modes', () {
      const text = 'A😀';
      for (final emergency in [false, true]) {
        final line = LineBreaker.breakLines(
          text: text,
          maxWidth: 30,
          widthOf: _unitWidth,
          breakLongWords: emergency,
        ).single;
        expect(line.logicalEnd, text.length);
        expect(text.substring(line.logicalStart, line.logicalEnd), text);
        expect(visualXToLogical(line, 100), text.length);
      }
    });

    test('RTL Hebrew marks retain cluster order and line ownership', () {
      const text = 'א\u05b7ב\u05b8ג\u05b6ד\u05b7';
      final lines = _break(text, 4, baseLevel: 1);
      expect(_sourceLines(text, lines), ['אַבָ', 'גֶדַ']);
      expect(
        lines.map((line) => line.glyphs.map((glyph) => glyph.logicalIndex)),
        [
          [2, 3, 0, 1],
          [6, 7, 4, 5],
        ],
      );
      _expectWholeClusters(text, lines);
    });

    test('Arabic joining and lam-alef ghosts survive emergency breaks', () {
      const text = 'مَلَاحَظَةمَلَاحَظَة';
      final lines = _break(text, 2, baseLevel: 1);
      expect(lines.length, greaterThan(1));
      expect(lines.every((line) => line.width <= 2), isTrue);
      _expectWholeClusters(text, lines);
      final wide = _break(text, 100, baseLevel: 1).single;
      final originalByOffset = {
        for (final glyph in wide.glyphs) glyph.logicalIndex: glyph,
      };
      for (final line in lines) {
        for (final glyph in line.glyphs) {
          final original = originalByOffset[glyph.logicalIndex]!;
          expect(
            (glyph.codePoint, glyph.level),
            (original.codePoint, original.level),
          );
          if (glyph.codePoint == 0) {
            final painted = originalByOffset.values
                .where(
                  (candidate) =>
                      candidate.logicalIndex < glyph.logicalIndex &&
                      candidate.advance > 0,
                )
                .reduce((a, b) => a.logicalIndex > b.logicalIndex ? a : b);
            expect(
              line.glyphs.map((g) => g.logicalIndex),
              contains(painted.logicalIndex),
            );
          }
        }
      }
    });
  });
}

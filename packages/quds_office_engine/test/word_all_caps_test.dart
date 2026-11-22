import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRun _run(String text, {bool allCaps = true, bool smallCaps = false}) =>
    WmlRun(
      text: text,
      properties: WmlRunProps(
        allCaps: allCaps,
        smallCaps: smallCaps,
        fontSizeHalfPoints: 20,
      ),
    );

WmlDocument _document(String text) {
  final document = WmlDocument.empty(text: text);
  document.paragraphs.single.inlines = [_run(text)];
  return document;
}

SfntFont _font() => SfntFont.parse(
  File(
    '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
  ).readAsBytesSync(),
);

String _painted(LaidOutLine line) =>
    String.fromCharCodes(line.glyphs.map((glyph) => glyph.glyph.codePoint));

void main() {
  test('full-size Unicode capitals retain complete source graphemes', () {
    const source = 'ßﬃև\u1ffcα\u0345\u0301𐐨 العربية 42!';
    final segments = WordSmallCaps.segments(source, allCaps: true);
    expect(segments.take(6).map((segment) => segment.text), [
      'SS',
      'FFI',
      'ԵՒ',
      'ΩΙ',
      'Α\u0301Ι',
      '𐐀',
    ]);
    expect(segments.every((segment) => segment.scale == 1), isTrue);
    expect(
      segments
          .map((segment) => source.substring(segment.start, segment.end))
          .join(),
      source,
    );
    expect(
      segments.map((segment) => segment.text).join(),
      'SSFFIԵՒΩΙΑ\u0301Ι𐐀 العربية 42!',
    );
    expect(WordSmallCaps.segments('aß').map((segment) => segment.scale), [
      WordSmallCaps.fontScale,
      WordSmallCaps.fontScale,
    ]);
  });

  test(
    'all capitals use uppercase advances at original size before wrapping',
    () {
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(inlines: [_run('ab cd', allCaps: false)]),
            ],
            pageSize: const WmlPageSize(width: 45, height: 500),
            margins: const WmlPageMargins(
              left: 10,
              right: 10,
              top: 10,
              bottom: 10,
            ),
          ),
        ],
      );
      final calls = <(int, double)>[];
      final engine = WordLayoutEngine(
        font: null,
        measure: (cp, size, props) {
          calls.add((cp, size));
          return cp == 32
              ? 5
              : cp >= 65 && cp <= 90
              ? 10
              : 3;
        },
      );
      expect(engine.layout(document).pages.single.lines, hasLength(1));
      document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties
              .allCaps =
          true;
      final lines = engine.layout(document).pages.single.lines;
      expect(lines, hasLength(2));
      expect(lines.map(_painted).join().replaceAll(' ', ''), 'ABCD');
      expect(
        lines.expand((line) => line.glyphs).every((g) => g.fontSize == 10),
        isTrue,
      );
      expect(calls, contains(('A'.codeUnitAt(0), 10)));
      expect(document.paragraphs.single.text, 'ab cd');
    },
  );

  test('mixed all-capital and small-capital runs retain distinct sizes', () {
    final document = WmlDocument.empty();
    document.paragraphs.single.inlines = [
      _run('Ab'),
      _run('Cd', allCaps: false, smallCaps: true),
      _run('Ef', allCaps: false),
      _run('Gh', smallCaps: true),
    ];
    final line = WordLayoutEngine(
      font: null,
    ).layout(document).pages.single.lines.single;
    expect(_painted(line), 'ABCDEfGH');
    expect(line.glyphs.map((glyph) => glyph.fontSize), [
      10,
      10,
      10,
      8,
      10,
      10,
      10,
      10,
    ]);
    expect(document.paragraphs.single.text, 'AbCdEfGh');
    final malformed = document.paragraphs.single.inlines.last as WmlRun;
    expect(malformed.properties.allCaps, isTrue);
    expect(malformed.properties.smallCaps, isTrue);
  });

  test('expansions and combining marks retain authored UTF-16 ownership', () {
    const source = 'a\u0301ßﬃ𐐨 مرحبا';
    final document = _document(source);
    final glyphs = WordLayoutEngine(
      font: null,
    ).layout(document).pages.single.lines.single.glyphs;
    for (final segment in WordSmallCaps.segments(source, allCaps: true).where(
      (segment) => segment.text != source.substring(segment.start, segment.end),
    )) {
      final group = glyphs
          .where((glyph) => glyph.glyph.logicalIndex == segment.start)
          .toList();
      expect(group.map((glyph) => glyph.glyph.codePoint), segment.text.runes);
      expect(group.every((glyph) => glyph.logicalEnd == segment.end), isTrue);
      expect(group.every((glyph) => glyph.displayText == segment.text), isTrue);
      expect(group.every((glyph) => glyph.fontSize == 10), isTrue);
      expect(
        group.every(
          (glyph) =>
              glyph.actualText == source.substring(segment.start, segment.end),
        ),
        isTrue,
      );
      var displayOffset = 0;
      for (final glyph in group) {
        expect(glyph.displayOffset, displayOffset);
        displayOffset += glyph.glyph.codePoint > 0xffff ? 2 : 1;
      }
    }
    expect(document.paragraphs.single.text, source);
    expect(
      glyphs.every(
        (g) => g.glyph.logicalIndex >= 0 && g.logicalEnd <= source.length,
      ),
      isTrue,
    );
  });

  test('a grapheme spanning unlike runs is not partially capitalized', () {
    final document = WmlDocument.empty();
    document.paragraphs.single.inlines = [
      _run('a'),
      _run('\u0301', allCaps: false),
      _run('b'),
    ];
    final line = WordLayoutEngine(
      font: null,
    ).layout(document).pages.single.lines.single;
    expect(_painted(line), 'a\u0301B');
    expect(document.paragraphs.single.text, 'a\u0301b');
  });

  test(
    'host shaping receives full-size expansions with their source intact',
    () {
      final calls = <(String, double)>[];
      final document = _document('ßﬃa\u0301');
      final line = WordLayoutEngine(
        font: null,
        measureRun: (text, size, props, level) {
          calls.add((text, size));
          return [
            for (final cluster in GraphemeClusters.segment(text))
              WordMeasuredCluster(
                start: cluster.start,
                end: cluster.end,
                advance: 5,
              ),
          ];
        },
      ).layout(document).pages.single.lines.single;
      expect(calls.toSet(), {('SS', 10.0), ('FFI', 10.0), ('A\u0301', 10.0)});
      expect(line.width, 30);
      expect(line.sourceText, 'ßﬃa\u0301');
      expect(_painted(line), 'SSFFIA\u0301');
    },
  );

  test('narrow cells never divide an uppercase expansion between lines', () {
    final paragraph = _document('aßﬃb').paragraphs.single;
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlTable(
              grid: [18],
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(blocks: [paragraph]),
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
      measure: (cp, size, props) => size / 2,
    ).layout(document).pages.expand((page) => page.lines).toList();
    expect(lines.length, greaterThan(1));
    for (final (index, count) in [(0, 1), (1, 2), (2, 3), (3, 1)]) {
      final owners = lines
          .where(
            (line) =>
                line.glyphs.any((glyph) => glyph.glyph.logicalIndex == index),
          )
          .toList();
      expect(owners, hasLength(1));
      final group = owners.single.glyphs.where(
        (glyph) => glyph.glyph.logicalIndex == index,
      );
      expect(group, hasLength(count));
      expect(group.every((glyph) => glyph.logicalEnd == index + 1), isTrue);
      expect(group.every((glyph) => glyph.fontSize == 10), isTrue);
    }
    final pdf = PdfFile.open(OfficePdfExport.word(document, font: _font()));
    expect(PdfExtract.documentText(pdf).replaceAll('\n', ''), 'aßﬃb');
  });

  test(
    'PDF paints full-size uppercase outlines and extracts authored text',
    () {
      final font = _font();
      final document = _document('Straße ﬃ');
      final glyphs = WordLayoutEngine(
        font: font,
      ).layout(document).pages.single.lines.single.glyphs;
      for (final glyph in glyphs) {
        expect(glyph.fontSize, 10);
        expect(glyph.glyph.glyphId, font.glyphIdFor(glyph.glyph.codePoint));
      }
      final pdf = PdfFile.open(OfficePdfExport.word(document, font: font));
      final painted = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
      expect(painted.map((op) => op.text).join(), 'STRASSE FFI');
      expect(painted.every((op) => op.size == 10), isTrue);
      expect(painted.every((op) => op.fontBytes != null), isTrue);
      expect(PdfExtract.pageText(pdf, 0), 'Straße ﬃ');
      expect(document.paragraphs.single.text, 'Straße ﬃ');
    },
  );

  test('split, copy and coalescing preserve all-capital boundaries', () {
    final paragraph = WmlParagraph(
      inlines: [_run('Capital'), _run('Normal', allCaps: false)],
    );
    WmlRunEdit.splitAt(paragraph, 2);
    expect(
      paragraph.inlines.whereType<WmlRun>().map(
        (run) => run.properties.allCaps,
      ),
      [true, true, false],
    );
    WmlRunEdit.coalesce(paragraph);
    expect(
      paragraph.inlines.whereType<WmlRun>().map(
        (run) => (run.text, run.properties.allCaps),
      ),
      [('Capital', true), ('Normal', false)],
    );
    final clones = WmlClone.inlines(paragraph.inlines).cast<WmlRun>().toList();
    clones.first.properties.allCaps = false;
    expect((paragraph.inlines.first as WmlRun).properties.allCaps, isTrue);
    expect(clones.first.text, 'Capital');
  });

  test(
    'comparison detects all capitals as formatting without changing text',
    () {
      final before = WmlDocument.empty(text: 'Capital');
      final after = WmlDocument.empty(text: 'Capital');
      after.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties
              .allCaps =
          true;
      final result = WordCompare.diff(before, after);
      expect(result.formattingCount, 1);
      expect(
        result.changes.single.formattingChanges,
        contains('Direct character formatting changed.'),
      );
      expect(result.changes.single.originalText, 'Capital');
      expect(result.changes.single.revisedText, 'Capital');
      expect(
        WordCompare.diff(
          before,
          after,
          options: const WordComparisonOptions(includeFormatting: false),
        ).hasChanges,
        isFalse,
      );
    },
  );

  test('pending Zotero transfer refuses concurrent all-capital changes', () {
    final document = _document('Citation');
    final prefs = jsonEncode({
      'dataVersion': 4,
      'sessionID': 'all-caps-transfer',
      'style': {'styleID': 'http://www.zotero.org/styles/apa'},
      'prefs': {'fieldType': 'Http', 'noteType': 0},
    });
    final plan = WordZoteroTransfer.prepareExport(
      document,
      instructions: 'Open this document in the destination and refresh.',
      documentData: prefs,
    );
    plan.assertUnchanged();
    document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .allCaps =
        false;
    expect(() => plan.assertUnchanged(), throwsStateError);
    expect(() => plan.apply(), throwsStateError);
    expect(document.paragraphs.single.text, 'Citation');
    expect(WordZoteroTransfer.isTransferDocument(document), isFalse);
  });

  test(
    'DOCX saves retain uppercase rendering and the original source text',
    () {
      var document = _document('Straße a\u0301');
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        expect(document.paragraphs.single.text, 'Straße a\u0301');
        expect(
          document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties
              .allCaps,
          isTrue,
        );
        final line = WordLayoutEngine(
          font: null,
        ).layout(document).pages.single.lines.single;
        expect(_painted(line), 'STRASSE A\u0301');
        expect(line.glyphs.every((glyph) => glyph.fontSize == 10), isTrue);
      }
    },
  );

  test('incremental relayout invalidates changed capital widths and text', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            for (var index = 0; index < 8; index++)
              WmlParagraph(inlines: [_run('Straße $index', allCaps: false)]),
          ],
        ),
      ],
    );
    final engine = WordLayoutEngine(font: null);
    var laid = engine.layout(document, updateFields: false);
    final paragraph = document.paragraphs.elementAt(3);
    for (final value in [true, false, true]) {
      paragraph.inlines.whereType<WmlRun>().single.properties.allCaps = value;
      laid = engine.layout(
        document,
        updateFields: false,
        reuse: laid,
        dirtyParagraphs: {paragraph},
      );
      final fresh = WordLayoutEngine(
        font: null,
      ).layout(document, updateFields: false);
      expect(wordLayoutFingerprint(laid), wordLayoutFingerprint(fresh));
      final line = laid.pages
          .expand((page) => page.lines)
          .singleWhere((line) => line.paragraphIndex == 3);
      expect(_painted(line), value ? 'STRASSE 3' : 'Straße 3');
    }
  });
}

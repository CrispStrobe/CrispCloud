import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRun _run(
  String text, {
  int position = 0,
  WmlVertAlign script = WmlVertAlign.baseline,
}) => WmlRun(
  text: text,
  properties: WmlRunProps(
    fontSizeHalfPoints: 24,
    positionHalfPoints: position,
    vertAlign: script,
  ),
);

WmlDocument _document(
  String text, {
  int position = 0,
  WmlVertAlign script = WmlVertAlign.baseline,
}) {
  final document = WmlDocument.empty(text: text);
  document.paragraphs.single.inlines = [
    _run(text, position: position, script: script),
  ];
  return document;
}

List<LaidOutGlyph> _glyphs(WmlDocument document) => WordLayoutEngine(font: null)
    .layout(document, updateFields: false)
    .pages
    .expand((page) => page.lines)
    .expand((line) => line.glyphs)
    .toList();

void _exactSpacing(WmlDocument document) {
  for (final paragraph in document.paragraphs) {
    paragraph.properties
      ..lineSpacingRule = WmlLineSpacingRule.exact
      ..lineSpacing = 20;
  }
}

WmlDocument _mixedLines({
  WmlLineSpacingRule rule = WmlLineSpacingRule.auto,
  double spacing = 1,
  bool noSpaceRaiseLower = false,
}) => WmlDocument(
  sourceNoSpaceRaiseLower: noSpaceRaiseLower,
  sections: [
    WmlSection(
      blocks: [
        WmlParagraph(
          properties: WmlParagraphProps(
            lineSpacingRule: rule,
            lineSpacing: spacing,
            spacingAfter: 0,
          ),
          inlines: [
            _run('A'),
            _run('B', position: 60),
            _run('C', position: -60),
          ],
        ),
        WmlParagraph(
          properties: WmlParagraphProps(lineSpacing: 1, spacingAfter: 0),
          inlines: [_run('Next')],
        ),
      ],
    ),
  ],
);

void main() {
  for (final position in [-9, 0, 8]) {
    test(
      'position $position half-points preserves size and horizontal metrics',
      () {
        const text = 'Latin é😀 العربية';
        final normalDocument = _document(text);
        _exactSpacing(normalDocument);
        final baseline = _glyphs(normalDocument);
        final document = _document(text, position: position);
        _exactSpacing(document);
        final positioned = _glyphs(document);
        expect(positioned, hasLength(baseline.length));
        for (var index = 0; index < positioned.length; index++) {
          final normal = baseline[index];
          final shifted = positioned[index];
          expect(shifted.y, closeTo(normal.y - position / 2, 1e-10));
          expect(shifted.x, normal.x);
          expect(shifted.advance, normal.advance);
          expect(shifted.fontSize, normal.fontSize);
          expect(shifted.glyph.logicalIndex, normal.glyph.logicalIndex);
          expect(shifted.logicalEnd, normal.logicalEnd);
          expect(shifted.glyph.codePoint, normal.glyph.codePoint);
          expect(shifted.positionHalfPoints, position);
        }
        expect(document.paragraphs.single.text, text);
      },
    );
  }

  for (final script in WmlVertAlign.values) {
    test('position composes with ${script.name} without changing its size', () {
      final normalDocument = _document('abc', script: script);
      final shiftedDocument = _document('abc', position: 5, script: script);
      _exactSpacing(normalDocument);
      _exactSpacing(shiftedDocument);
      final baseline = _glyphs(normalDocument);
      final shifted = _glyphs(shiftedDocument);
      for (var index = 0; index < baseline.length; index++) {
        expect(shifted[index].y, closeTo(baseline[index].y - 2.5, 1e-10));
        expect(shifted[index].fontSize, baseline[index].fontSize);
        expect(shifted[index].advance, baseline[index].advance);
        expect(shifted[index].vertAlign, script);
      }
    });
  }

  test('mixed positions preserve individual baseline and UTF-16 ownership', () {
    final document = WmlDocument.empty();
    document.paragraphs.single.inlines = [
      _run('A'),
      _run('😀', position: 6),
      _run('C', position: -4),
    ];
    final glyphs = _glyphs(document);
    expect(glyphs.map((g) => g.glyph.logicalIndex), [0, 1, 3]);
    expect(glyphs.map((g) => g.logicalEnd), [1, 3, 4]);
    expect(glyphs[1].y, closeTo(glyphs[0].y - 3, 1e-10));
    expect(glyphs[2].y, closeTo(glyphs[0].y + 2, 1e-10));
    expect(glyphs.map((g) => g.fontSize), everyElement(12));
  });

  for (final rule in [WmlLineSpacingRule.auto, WmlLineSpacingRule.atLeast]) {
    test('${rule.name} line boxes contain raised and lowered run extents', () {
      final document = _mixedLines(
        rule: rule,
        spacing: rule == WmlLineSpacingRule.auto ? 1 : 10,
      );
      final lines = WordLayoutEngine(
        font: null,
      ).layout(document, updateFields: false).pages.single.lines;
      final first = lines.first;
      final glyphs = first.glyphs;
      expect(first.height, closeTo(12 * 1.32 + 60, 1e-10));
      expect(glyphs[1].y, closeTo(glyphs[0].y - 30, 1e-10));
      expect(glyphs[2].y, closeTo(glyphs[0].y + 30, 1e-10));
      // Glyph y is its baseline; the fallback typographic ascent is .8em.
      expect(glyphs[1].y - 12 * .8, closeTo(first.y, 1e-10));
      expect(glyphs[2].y + 12 * .52, closeTo(first.y + first.height, 1e-10));
      expect(lines[1].y, closeTo(first.y + first.height, 1e-10));
    });
  }

  test('atLeast floor and exact spacing retain their distinct line rules', () {
    for (final entry in [
      (WmlLineSpacingRule.atLeast, 120.0, 120.0),
      (WmlLineSpacingRule.exact, 12.0, 12.0),
    ]) {
      final lines = WordLayoutEngine(font: null)
          .layout(
            _mixedLines(rule: entry.$1, spacing: entry.$2),
            updateFields: false,
          )
          .pages
          .single
          .lines;
      expect(lines.first.height, entry.$3);
      expect(lines[1].y, closeTo(lines.first.y + entry.$3, 1e-10));
      expect(
        lines.first.glyphs[1].y,
        closeTo(lines.first.glyphs[0].y - 30, 1e-10),
      );
    }
  });

  test(
    'noSpaceRaiseLower suppresses expansion and invalidates incremental reuse',
    () {
      final document = _mixedLines(noSpaceRaiseLower: true);
      final engine = WordLayoutEngine(font: null);
      var layout = engine.layout(document, updateFields: false);
      expect(layout.pages.single.lines.first.height, closeTo(12 * 1.32, 1e-10));
      document.sourceNoSpaceRaiseLower = false;
      layout = engine.layout(
        document,
        updateFields: false,
        reuse: layout,
        dirtyParagraphs: {},
      );
      final full = WordLayoutEngine(
        font: null,
      ).layout(document, updateFields: false);
      expect(
        layout.pages.single.lines.first.height,
        closeTo(12 * 1.32 + 60, 1e-10),
      );
      expect(wordLayoutFingerprint(layout), wordLayoutFingerprint(full));
    },
  );

  test('expanded line height participates in pagination', () {
    final document = _mixedLines();
    final section = document.sections.single;
    section.pageSize = const WmlPageSize(width: 200, height: 120);
    section.margins = const WmlPageMargins(
      top: 20,
      bottom: 20,
      left: 20,
      right: 20,
    );
    section.blocks.insert(
      0,
      WmlParagraph(
        properties: WmlParagraphProps(lineSpacing: 1, spacingAfter: 0),
        inlines: [_run('Previous')],
      ),
    );
    final pages = WordLayoutEngine(
      font: null,
    ).layout(document, updateFields: false).pages;
    expect(pages, hasLength(3));
    expect(pages[0].lines.single.sourceParagraph, same(section.blocks[0]));
    expect(pages[1].lines.single.sourceParagraph, same(section.blocks[1]));
    expect(pages[2].lines.single.sourceParagraph, same(section.blocks[2]));
  });

  test(
    'signed32 imported position extremes stay finite and terminate layout',
    () {
      for (final position in [-2147483648, 2147483647]) {
        final layout = WordLayoutEngine(
          font: null,
        ).layout(_document('X', position: position), updateFields: false);
        expect(layout.pages, hasLength(1));
        final line = layout.pages.single.lines.single;
        expect(line.height.isFinite, isTrue);
        expect(line.height, greaterThan(1000000000));
        expect(line.glyphs.single.y.isFinite, isTrue);
      }
    },
  );

  test(
    'incremental relayout translates cached raised and lowered glyphs consistently',
    () {
      final paragraphs = [
        for (var i = 0; i < 30; i++)
          WmlParagraph(
            inlines: [_run('Paragraph $i', position: i.isEven ? 8 : -5)],
          ),
      ];
      final document = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
      final engine = WordLayoutEngine(font: null);
      var layout = engine.layout(document, updateFields: false);
      WordIncrementalLayoutStats.reset();
      for (final spacing in [25.0, 0.0, 14.0]) {
        paragraphs[3].properties.spacingAfter = spacing;
        layout = engine.layout(
          document,
          updateFields: false,
          reuse: layout,
          dirtyParagraphs: {paragraphs[3]},
        );
        final full = WordLayoutEngine(
          font: null,
        ).layout(document, updateFields: false);
        expect(wordLayoutFingerprint(layout), wordLayoutFingerprint(full));
      }
      expect(WordIncrementalLayoutStats.incremental, 3);
      expect(WordIncrementalLayoutStats.blocksTranslated, greaterThan(0));
      paragraphs[6].inlines
              .whereType<WmlRun>()
              .single
              .properties
              .positionHalfPoints =
          0;
      layout = engine.layout(
        document,
        updateFields: false,
        reuse: layout,
        dirtyParagraphs: {paragraphs[6]},
      );
      expect(
        wordLayoutFingerprint(layout),
        wordLayoutFingerprint(
          WordLayoutEngine(font: null).layout(document, updateFields: false),
        ),
      );
    },
  );

  test('header/footer and note layout copies keep position metadata', () {
    final document = _document('Body');
    document.sections.single.header.add(
      WmlParagraph(inlines: [_run('Header', position: 4)]),
    );
    document.sections.single.footer.add(
      WmlParagraph(inlines: [_run('Footer', position: -6)]),
    );
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'Note',
    );
    note.paragraphs.single.inlines = [_run('Note', position: 10)];
    final layout = WordLayoutEngine(
      font: null,
    ).layout(document, updateFields: false);
    final page = layout.pages.single;
    expect(
      page.header
          .expand((line) => line.glyphs)
          .map((g) => g.positionHalfPoints),
      everyElement(4),
    );
    expect(
      page.footer
          .expand((line) => line.glyphs)
          .map((g) => g.positionHalfPoints),
      everyElement(-6),
    );
    final noteGlyphs = page.notes
        .expand((line) => line.glyphs)
        .where((g) => g.positionHalfPoints == 10)
        .toList();
    expect(noteGlyphs, hasLength(4));
  });

  test(
    'PDF paints displaced baselines at unchanged size and extracts source order',
    () {
      final font = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final document = WmlDocument.empty();
      document.paragraphs.single.inlines = [
        _run('A'),
        _run('B', position: 6),
        _run('C', position: -4),
      ];
      final pdf = PdfFile.open(OfficePdfExport.word(document, font: font));
      final painted = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
      expect(painted.map((op) => op.text).join(), 'ABC');
      expect(painted, hasLength(3));
      expect(painted.map((op) => op.size), everyElement(12));
      expect(painted[1].y, closeTo(painted[0].y - 3, 1e-6));
      expect(painted[2].y, closeTo(painted[0].y + 2, 1e-6));
      expect(PdfExtract.pageText(pdf, 0), 'ABC');
      expect(document.paragraphs.single.text, 'ABC');
    },
  );

  test(
    'comparison detects positioning as formatting without altering text',
    () {
      final before = _document('Position');
      final after = _document('Position', position: 6);
      final result = WordCompare.diff(before, after);
      expect(result.formattingCount, 1);
      expect(result.changes.single.originalText, 'Position');
      expect(result.changes.single.revisedText, 'Position');
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

  test('pending Zotero transfer detects concurrent position-only changes', () {
    final document = _document('Citation');
    final plan = WordZoteroTransfer.prepareExport(
      document,
      instructions: 'Open in the destination and refresh.',
      documentData: jsonEncode({
        'dataVersion': 4,
        'sessionID': 'position-transfer',
        'style': {'styleID': 'http://www.zotero.org/styles/apa'},
        'prefs': {'fieldType': 'Http', 'noteType': 0},
      }),
    );
    plan.assertUnchanged();
    document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .positionHalfPoints =
        2;
    expect(() => plan.assertUnchanged(), throwsStateError);
    expect(() => plan.apply(), throwsStateError);
    expect(document.paragraphs.single.text, 'Citation');
  });
}

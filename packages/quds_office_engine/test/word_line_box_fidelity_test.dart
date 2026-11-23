import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRun run(String text, [int size = 12]) => WmlRun(
  text: text,
  properties: WmlRunProps(asciiFont: 'Arial', fontSizeHalfPoints: size * 2),
);
WmlParagraph paragraph(String text, {double before = 0, double after = 0}) =>
    WmlParagraph(
      properties: WmlParagraphProps(
        lineSpacing: 1,
        spacingBefore: before,
        spacingAfter: after,
      ),
      inlines: [run(text)],
    );
WmlDocument document(List<WmlBlock> blocks) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 612, height: 792),
      margins: const WmlPageMargins(top: 72, bottom: 72, left: 72, right: 72),
      blocks: blocks,
    ),
  ],
);

void main() {
  final sans = SfntFont.parse(
    File(
      '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
    ).readAsBytesSync(),
  );
  WordLayoutEngine engine() => WordLayoutEngine(
    font: null,
    measureFont: (_, size, _) => FontMetrics(font: sans, fontSizePoints: size),
  );

  test('tabs contribute their font metrics to the line height', () {
    final lines = WordLayoutEngine(font: sans)
        .layout(
          document([
            paragraph('One two'),
            paragraph('One\ttwo'),
            paragraph('\tTwo'),
          ]),
        )
        .pages
        .single
        .lines;
    expect(lines, hasLength(3));
    expect(
      lines.map((line) => line.height),
      everyElement(closeTo(13.7988, .001)),
    );
  });

  test('exact and minimum table row heights survive save and reopen', () {
    WmlTableRow row({required bool exact}) => WmlTableRow(
      height: 24,
      heightIsExact: exact,
      cells: [
        WmlTableCell(
          blocks: [
            for (var i = 0; i < 4; i++)
              paragraph('Line $i')
                ..properties.lineSpacingRule = WmlLineSpacingRule.exact
                ..properties.lineSpacing = 18,
          ],
        ),
      ],
    );
    final doc = document([
      WmlTable(
        grid: [210],
        properties: WmlTableProps(cellMargin: 0),
        rows: [row(exact: true), row(exact: false)],
      ),
      paragraph('After'),
    ]);
    final bytes = WordSerializer().writeBytes(doc);
    final xml = OpcPackage.openBytes(
      bytes,
    ).getPart('/word/document.xml')!.readText();
    expect(xml, contains('w:hRule="exact"'));
    expect(xml, contains('w:hRule="atLeast"'));
    for (final source in [doc, WordDeserializer().readBytes(bytes)]) {
      final page = WordLayoutEngine(font: sans).layout(source).pages.single;
      final cells = page.frames
          .where((box) => box.kind == LaidOutBoxKind.tableCell)
          .toList();
      expect(cells.map((box) => box.height), [24, 72]);
      expect(cells[1].y, cells[0].y + 24);
      expect(page.lines.last.text, 'After');
      if (!identical(source, doc)) {
        expect(cells.first.y, 72);
        expect(page.lines.last.y, cells.last.y + cells.last.height);
      }
    }
  });

  test('each line uses its own size after a larger opening run', () {
    final p = paragraph('');
    p.inlines = [
      run('Large opening\n', 24),
      run('Small second\n', 11),
      run('Small third', 11),
    ];
    final lines = engine().layout(document([p])).pages.single.lines;
    expect(lines, hasLength(3));
    expect(lines[0].height, closeTo(27.59765625, .001));
    expect(lines[1].height, closeTo(12.64892578125, .001));
    expect(lines[2].y - lines[1].y, closeTo(12.64892578125, .001));
    expect(lines[1].glyphs.first.y - lines[1].y, lessThan(11));
  });

  test(
    'mixed run sizes share the fixed-height baseline without shifting small text',
    () {
      final p = paragraph('');
      p.properties
        ..lineSpacingRule = WmlLineSpacingRule.exact
        ..lineSpacing = 18;
      p.inlines = [run('Small ', 8), run('LARGE ', 24), run('small', 11)];
      final line = engine().layout(document([p])).pages.single.lines.single;
      expect(line.glyphs.map((g) => g.y).toSet(), hasLength(1));
      expect(line.glyphs.first.y, closeTo(86.53, .25));
    },
  );

  test(
    'adjacent spacing uses the greater value and preserves model properties',
    () {
      final first = paragraph('First', after: 12);
      final second = paragraph('Second', before: 6, after: 4);
      final third = paragraph('Third', before: 10);
      final doc = document([first, second, third]);
      final lines = engine().layout(doc).pages.single.lines;
      expect(lines[1].y - lines[0].y, closeTo(13.798828125 + 12, .001));
      expect(lines[2].y - lines[1].y, closeTo(13.798828125 + 10, .001));
      expect(first.properties.spacingAfter, 12);
      expect(second.properties.spacingBefore, 6);
      final copy = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      expect(copy.paragraphs.elementAt(1).properties.spacingBefore, 6);
      expect(copy.paragraphs.elementAt(1).properties.spacingAfter, 4);
    },
  );

  test('paragraph gaps do not collapse across an explicit page break', () {
    final first = paragraph('First', after: 12);
    final second = paragraph('Second', before: 6)
      ..properties.pageBreakBefore = true;
    final laid = engine().layout(document([first, second]));
    expect(laid.pages, hasLength(2));
    expect(laid.pages[1].lines.single.y, 78);
  });

  test('a standalone page break leaves no blank line on the next page', () {
    WmlParagraph pageBreak({bool bookmarked = false}) => WmlParagraph(
      inlines: [
        WmlBreak(WmlBreakType.page),
        if (bookmarked) ...[
          WmlBookmarkBoundary(id: '45', isStart: true, name: 'BreakAnchor'),
          WmlBookmarkBoundary(id: '45', isStart: false),
        ],
      ],
    );
    final doc = document([
      paragraph('First'),
      pageBreak(bookmarked: true),
      paragraph('Second'),
      pageBreak(),
      paragraph(''),
      paragraph('Third'),
    ]);
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    for (final version in [doc, reopened]) {
      final pages = engine().layout(version).pages;
      expect(pages, hasLength(3));
      expect(pages.map((p) => p.lines.single.paragraphIndex), [0, 2, 5]);
      expect(pages[0].lines.single.y, 72);
      expect(pages[1].lines.single.y, 72);
      expect(pages[2].lines.single.y, closeTo(72 + 13.798828125, 0.001));
    }
  });

  for (final columns in [1, 2]) {
    test(
      'an overflowing blank line moves with its height in $columns columns',
      () {
        WmlParagraph fixed(String text) => paragraph(text)
          ..properties.lineSpacingRule = WmlLineSpacingRule.exact
          ..properties.lineSpacing = 14;
        final source = WmlDocument(
          sections: [
            WmlSection(
              pageSize: const WmlPageSize(width: 400, height: 160),
              margins: const WmlPageMargins(
                top: 20,
                bottom: 24,
                left: 20,
                right: 20,
              ),
              columnCount: columns,
              blocks: [
                for (var i = 0; i < 8; i++) fixed('Line $i'),
                fixed(''),
                fixed('Following text'),
              ],
            ),
          ],
        );
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(source),
        );
        for (final version in [source, reopened]) {
          final pages = engine().layout(version).pages;
          expect(pages, hasLength(columns == 1 ? 2 : 1));
          final line = pages.last.lines.last;
          expect(line.paragraphIndex, 9);
          expect(line.y, 34);
          expect(line.boxX, version.sections.single.columnOriginX(columns - 1));
        }
      },
    );
  }

  test('keep lines moves a fitting paragraph and allows an oversized one', () {
    List<int> pagesFor({required bool keep, required int lineCount}) {
      WmlParagraph fixed(String text) => paragraph(text)
        ..properties.lineSpacingRule = WmlLineSpacingRule.exact
        ..properties.lineSpacing = 18;
      final fillers = [for (var i = 0; i < 11; i++) fixed('Filler $i')];
      final target = fixed(List.filled(lineCount, 'Target').join('\n'))
        ..properties.keepTogether = keep
        ..properties.widowControl = false;
      final doc = WmlDocument(
        sections: [
          WmlSection(
            pageSize: const WmlPageSize(width: 500, height: 300),
            margins: const WmlPageMargins(
              top: 36,
              bottom: 36,
              left: 36,
              right: 36,
            ),
            blocks: [...fillers, target],
          ),
        ],
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      return [
        for (final page in engine().layout(reopened).pages)
          for (final line in page.lines)
            if (line.paragraphIndex == fillers.length) page.index,
      ];
    }

    expect(pagesFor(keep: true, lineCount: 3), [1, 1, 1]);
    expect(pagesFor(keep: false, lineCount: 3), [0, 1, 1]);
    final oversized = pagesFor(keep: true, lineCount: 15);
    expect(oversized, hasLength(15));
    expect(oversized.first, 0);
    expect(oversized.toSet(), {0, 1, 2});
  });

  test('widow control prevents one line at either side of a page break', () {
    for (final (fillers, lines, control, expected) in [
      (11, 4, null, [1, 1, 1, 1]),
      (11, 4, false, [0, 1, 1, 1]),
      (9, 4, true, [0, 0, 1, 1]),
      (9, 4, false, [0, 0, 0, 1]),
      (10, 3, null, [1, 1, 1]),
    ]) {
      WmlParagraph fixed(String text) => paragraph(text)
        ..properties.lineSpacingRule = WmlLineSpacingRule.exact
        ..properties.lineSpacing = 18;
      final target = fixed(List.filled(lines, 'Target').join('\n'))
        ..properties.widowControl = control;
      final source = WmlDocument(
        sections: [
          WmlSection(
            pageSize: const WmlPageSize(width: 500, height: 300),
            margins: const WmlPageMargins(
              top: 36,
              bottom: 36,
              left: 36,
              right: 36,
            ),
            blocks: [for (var i = 0; i < fillers; i++) fixed('Filler'), target],
          ),
        ],
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(source),
      );
      expect(reopened.paragraphs.last.properties.widowControl, control);
      expect([
        for (final page in engine().layout(reopened).pages)
          for (final line in page.lines)
            if (line.paragraphIndex == fillers) page.index,
      ], expected);
    }
  });

  test('editing the body reflows the whole preceding keep-with-next chain', () {
    WmlParagraph fixed(String text, {bool keep = false}) => paragraph(text)
      ..properties.lineSpacingRule = WmlLineSpacingRule.exact
      ..properties.lineSpacing = 18
      ..properties.keepWithNext = keep;
    final target = fixed('Body');
    final doc = WmlDocument(
      sections: [
        WmlSection(
          pageSize: const WmlPageSize(width: 500, height: 300),
          margins: const WmlPageMargins(
            top: 36,
            bottom: 36,
            left: 36,
            right: 36,
          ),
          blocks: [
            for (var i = 0; i < 9; i++) fixed('Filler'),
            fixed('First heading', keep: true),
            fixed('Second heading', keep: true),
            target,
          ],
        ),
      ],
    );
    final word = engine();
    final original = word.layout(doc, updateFields: false);
    expect(original.pages.single.lines.last.paragraphIndex, 11);
    (target.inlines.single as WmlRun).text = List.filled(4, 'Body').join('\n');
    final edited = word.layout(
      doc,
      updateFields: false,
      reuse: original,
      dirtyParagraphs: {target},
    );
    expect(edited.pages, hasLength(2));
    expect(edited.pages.last.lines.map((line) => line.paragraphIndex), [
      9,
      10,
      11,
      11,
      11,
      11,
    ]);
    expect(
      wordLayoutFingerprint(edited),
      wordLayoutFingerprint(engine().layout(doc, updateFields: false)),
    );
  });

  test('same-style spacing suppresses only the opted-in side', () {
    // Baseline deltas come from native Word's exact 18 pt line spacing
    // with a 10 pt after-space and a 12 pt before-space.
    for (final (suppressAfter, suppressBefore, sameStyle, gap) in [
      (false, false, true, 12.0),
      (true, false, true, 2.0),
      (false, true, true, 10.0),
      (true, true, true, 0.0),
      (true, true, false, 12.0),
    ]) {
      final first = paragraph('Upper', after: 10);
      final second = paragraph('Lower', before: 12);
      first.properties
        ..styleId = 'Normal'
        ..contextualSpacing = suppressAfter;
      second.properties
        ..styleId = sameStyle ? null : 'Heading1'
        ..contextualSpacing = suppressBefore;
      for (final p in [first, second]) {
        p.properties
          ..lineSpacingRule = WmlLineSpacingRule.exact
          ..lineSpacing = 18;
      }
      final doc = document([first, second]);
      final lines = engine().layout(doc).pages.single.lines;
      expect(lines[1].y - lines[0].y, closeTo(18 + gap, .001));
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      expect(reopened.paragraphs.map((p) => p.properties.contextualSpacing), [
        suppressAfter,
        suppressBefore,
      ]);
    }
  });

  test('table rows measure and paint contextual spacing for each cell', () {
    WmlTableCell cell(String title, {required bool contextual}) {
      final first = paragraph('$title upper', after: 10);
      final second = paragraph('$title lower', before: 12);
      for (final p in [first, second]) {
        p.properties
          ..lineSpacingRule = WmlLineSpacingRule.exact
          ..lineSpacing = 18
          ..contextualSpacing = contextual;
      }
      return WmlTableCell(blocks: [first, second]);
    }

    final table = WmlTable(
      grid: [240],
      rows: [
        WmlTableRow(cells: [cell('Ordinary', contextual: false)]),
        WmlTableRow(cells: [cell('Contextual', contextual: true)]),
      ],
    );
    final page = engine().layout(document([table])).pages.single;
    expect(page.lines[1].y - page.lines[0].y, closeTo(30, .001));
    expect(page.lines[3].y - page.lines[2].y, closeTo(18, .001));
    final cells = page.frames.where((frame) => frame.table == table).toList();
    expect(cells, hasLength(2));
    expect(cells[0].height - cells[1].height, closeTo(12, .001));
  });

  test(
    'center and right tabs position their following fields at real stops',
    () {
      final p = paragraph('Left\tCenter\tRight');
      p.properties.tabs.addAll([
        const WmlTabStop(position: 216, alignment: WmlTabAlignment.center),
        const WmlTabStop(position: 468, alignment: WmlTabAlignment.right),
      ]);
      // Scalar 6pt characters keep the independent expected anchors simple.
      final line = WordLayoutEngine(
        font: null,
      ).layout(document([p])).pages.single.lines.single;
      final center = line.glyphs.firstWhere((g) => g.glyph.logicalIndex == 5);
      final right = line.glyphs.firstWhere((g) => g.glyph.logicalIndex == 12);
      expect(center.x, closeTo(72 + 216 - 18, .001));
      expect(right.x, closeTo(72 + 468 - 30, .001));
      expect(line.glyphs.last.x + line.glyphs.last.advance, closeTo(540, .001));
      expect(p.properties.tabs[0].position, 216);
    },
  );

  test(
    'default tabs advance to the next half-inch grid rather than add 36pt',
    () {
      final line = WordLayoutEngine(
        font: null,
      ).layout(document([paragraph('ABC\tD')])).pages.single.lines.single;
      expect(line.glyphs.last.x, closeTo(108, .001));
      expect(line.glyphs[3].advance, closeTo(18, .001));
    },
  );

  test('decimal-point tabs align the decimal rather than the field end', () {
    final p = paragraph('A\t123.45');
    p.properties.tabs.add(
      const WmlTabStop(position: 216, alignment: WmlTabAlignment.decimal),
    );
    final line = WordLayoutEngine(
      font: null,
    ).layout(document([p])).pages.single.lines.single;
    final point = line.glyphs.firstWhere((g) => g.glyph.codePoint == 46);
    expect(point.x, closeTo(288, .001));
  });
}

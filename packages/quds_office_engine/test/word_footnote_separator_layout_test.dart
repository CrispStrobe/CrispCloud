import 'dart:math' as math;

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document({
  WmlFootnoteSeparator? separator,
  String noteText = 'Footnote text',
  int bodyParagraphs = 1,
  bool addNote = true,
  double height = 260,
}) {
  final document = WmlDocument(
    footnoteSeparator: separator,
    sections: [
      WmlSection(
        pageSize: WmlPageSize(width: 320, height: height),
        margins: const WmlPageMargins(top: 20, bottom: 20, left: 24, right: 16),
        blocks: [
          for (var i = 0; i < bodyParagraphs; i++) _paragraph('Body $i'),
        ],
      ),
    ],
  );
  if (addNote) {
    WordNotes.insert(
      document,
      document.paragraphs.first,
      endnote: false,
      text: noteText,
    );
  }
  return document;
}

WmlFootnoteSeparator _separator({
  double before = 12,
  double thickness = 2,
  double after = 6,
  double width = .25,
  WmlFootnoteSeparatorAlignment alignment = WmlFootnoteSeparatorAlignment.left,
  WmlFootnoteSeparatorLineStyle lineStyle = WmlFootnoteSeparatorLineStyle.solid,
}) => WmlFootnoteSeparator(
  beforeSpacing: before,
  thickness: thickness,
  afterSpacing: after,
  relativeWidth: width,
  alignment: alignment,
  color: 0xCC3399,
  lineStyle: lineStyle,
);

List<LaidOutBox> _separators(LaidOutPage page) =>
    page.frames.where((box) => box.kind == LaidOutBoxKind.footnote).toList();

void _expectClearBand(LaidOutDocument layout, WmlDocument document) {
  final separator = document.footnoteSeparator!;
  for (final page in layout.pages) {
    final noteTops = [
      ...page.notes.map((line) => line.y),
      ...page.frames
          .where(
            (box) => box.isNoteContent && box.kind != LaidOutBoxKind.footnote,
          )
          .map((box) => box.y),
    ];
    if (noteTops.isEmpty) {
      expect(_separators(page), isEmpty);
      continue;
    }
    final noteTop = noteTops.reduce(math.min);
    final reservationTop = separator.visible
        ? _separators(page).single.y - separator.beforeSpacing
        : noteTop - separator.reservedHeight;
    for (final line in page.lines) {
      expect(line.y + line.height, lessThanOrEqualTo(reservationTop + .01));
    }
    for (final frame in page.frames) {
      if (frame.isNoteContent || frame.kind == LaidOutBoxKind.columnSep) {
        continue;
      }
      expect(frame.y + frame.height, lessThanOrEqualTo(reservationTop + .01));
    }
    final section = document.sections[page.sectionIndex];
    for (final line in page.notes) {
      expect(line.y, greaterThanOrEqualTo(section.margins.top));
      expect(
        line.y + line.height,
        lessThanOrEqualTo(
          section.pageSize.height - section.margins.bottom + .01,
        ),
      );
    }
    for (final frame in page.frames.where(
      (box) => box.isNoteContent && box.kind != LaidOutBoxKind.footnote,
    )) {
      expect(frame.y, greaterThanOrEqualTo(section.margins.top - .01));
      expect(
        frame.y + frame.height,
        lessThanOrEqualTo(
          section.pageSize.height - section.margins.bottom + .01,
        ),
      );
    }
    if (separator.visible) {
      final rule = _separators(page).single;
      expect(rule.y, closeTo(reservationTop + separator.beforeSpacing, .01));
      expect(
        noteTop - rule.y - rule.height,
        greaterThanOrEqualTo(separator.afterSpacing - .01),
      );
    } else {
      expect(_separators(page), isEmpty);
    }
  }
}

void main() {
  for (final alignment in WmlFootnoteSeparatorAlignment.values) {
    for (final bidi in [false, true]) {
      test('physical $alignment separator geometry with bidi=$bidi', () {
        final document = _document(separator: _separator(alignment: alignment));
        document.paragraphs.first.properties.rightToLeft = bidi;
        final layout = WordLayoutEngine(font: null).layout(document);
        final rule = _separators(layout.pages.single).single;
        // Body width is 320 - 24 - 16 = 280 pt; a quarter is 70 pt.
        expect(rule.width, 70);
        expect(rule.x, switch (alignment) {
          WmlFootnoteSeparatorAlignment.left => 24,
          WmlFootnoteSeparatorAlignment.center => 129,
          WmlFootnoteSeparatorAlignment.right => 234,
        });
        expect(rule.height, 2);
        expect(rule.fillColor!.toUpperCase(), 'CC3399');
        expect(rule.strokeColor, isEmpty);
        expect(rule.isNoteContent, isTrue);
        _expectClearBand(layout, document);
      });
    }
  }

  test('several footnotes share one separator band per page', () {
    final document = _document(separator: _separator());
    WordNotes.insert(
      document,
      document.paragraphs.first,
      endnote: false,
      text: 'Second footnote',
    );
    final layout = WordLayoutEngine(font: null).layout(document);
    expect(layout.pages, hasLength(1));
    expect(_separators(layout.pages.single), hasLength(1));
    final text = layout.pages.single.notes.map((line) => line.text).join(' ');
    expect(text, contains('Footnote text'));
    expect(text, contains('Second footnote'));
    _expectClearBand(layout, document);
  });

  test('short footnotes reserve their authored line height', () {
    final document = _document(separator: _separator());
    final paragraph = document.footnotes.single.paragraphs.single;
    paragraph.properties
      ..lineSpacingRule = WmlLineSpacingRule.exact
      ..lineSpacing = 10;
    final engine = WordLayoutEngine(font: null);
    final roomy = engine.layout(document).pages.single;
    final note = roomy.notes.single;
    expect(note.height, 10);
    final section = document.sections.single;
    expect(
      note.y + note.height,
      section.pageSize.height - section.margins.bottom,
    );

    // Leave room for the body, separator, the note's exact line and one
    // spare point. The note has no continuation to place on another page.
    final height =
        roomy.lines.single.y +
        roomy.lines.single.height +
        document.footnoteSeparator!.reservedHeight +
        note.height +
        section.margins.bottom +
        1;
    section.pageSize = WmlPageSize(
      width: section.pageSize.width,
      height: height,
    );
    final tight = engine.layout(document);
    expect(tight.pages.single.notes.single.text, contains('Footnote text'));
    _expectClearBand(tight, document);
  });

  test('footnote table starts on the page of its reference', () {
    final document = _document(
      separator: _separator(),
      bodyParagraphs: 2,
      addNote: false,
    );
    document.paragraphs.first.properties
      ..lineSpacingRule = WmlLineSpacingRule.exact
      ..lineSpacing = 36;
    WordNotes.insert(document, document.paragraphs.last, endnote: false);
    WmlParagraph cellLine(String text, double height) => _paragraph(text)
      ..properties.lineSpacingRule = WmlLineSpacingRule.exact
      ..properties.lineSpacing = height;
    document.footnotes[0] = WmlNote(
      id: document.footnotes.single.id,
      endnote: false,
      addReference: false,
      blocks: [
        WmlTable(
          grid: [140, 140],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [cellLine('Short cell', 10)]),
                WmlTableCell(blocks: [cellLine('Tall cell', 26)]),
              ],
            ),
          ],
        ),
      ],
    );

    final section = document.sections.single;
    final engine = WordLayoutEngine(font: null);
    final roomy = engine.layout(document).pages.single;
    final body = roomy.lines.last;
    final short = roomy.notes.singleWhere((line) => line.text == 'Short cell');
    final tall = roomy.notes.singleWhere((line) => line.text == 'Tall cell');
    expect(short.y, closeTo(tall.y, .01));
    expect(tall.height, greaterThan(short.height));
    // The first page can fit the reference and the short cell, but a cut
    // there would split the tall cell's line. Move the reference as well.
    section.pageSize = WmlPageSize(
      width: section.pageSize.width,
      height:
          body.y +
          body.height +
          document.footnoteSeparator!.reservedHeight +
          (short.height + tall.height) / 2 +
          section.margins.bottom,
    );

    final layout = engine.layout(document);
    final pages = layout.pages;
    expect(pages, hasLength(2));
    expect(pages.first.notes, isEmpty);
    expect(pages.last.lines.single.text, startsWith('Body 1'));
    expect(pages.last.notes.map((line) => line.text), [
      'Short cell',
      'Tall cell',
    ]);
    _expectClearBand(layout, document);
  });

  for (final widowControl in [true, false]) {
    test('footnote continuation respects widow control $widowControl', () {
      final document = _document(
        separator: _separator(),
        noteText: 'First\nSecond\nThird\nFourth\nFifth',
      );
      document.footnotes.single.paragraphs.single.properties
        ..lineSpacingRule = WmlLineSpacingRule.exact
        ..lineSpacing = 10
        ..widowControl = widowControl;
      final engine = WordLayoutEngine(font: null);
      final body = engine.layout(document).pages.single.lines.single;
      final section = document.sections.single;
      section.pageSize = WmlPageSize(
        width: section.pageSize.width,
        height:
            body.y +
            body.height +
            document.footnoteSeparator!.reservedHeight +
            40.5 +
            section.margins.bottom,
      );
      final layout = engine.layout(document);
      expect(layout.pages.map((page) => page.notes.length), [
        if (widowControl) ...[3, 2] else ...[4, 1],
      ]);
      expect(layout.pages.last.notes.last.text, 'Fifth');
      _expectClearBand(layout, document);
    });
  }

  test('multiple generated note labels preserve UTF-16 source offsets', () {
    final document = _document();
    final paragraph = document.footnotes.single.paragraphs.single;
    paragraph.inlines
      ..clear()
      ..addAll([
        WmlRun(text: 'A'),
        WmlNoteMarker(endnote: false, properties: WmlRunProps()),
        WmlRun(text: '😀'),
        WmlNoteMarker(endnote: false, properties: WmlRunProps()),
        WmlRun(text: 'Z'),
      ]);

    final note =
        WordLayoutEngine(font: null).layout(document).pages.single.notes.single;
    expect(note.sourceParagraph, same(paragraph));
    expect(note.proofingOffsets, [0, null, 1, 2, null, 3, 4]);
    expect(note.proofingOffsetAt(7), isNull);
  });

  test('long footnote continuations keep every line in order', () {
    final rows = List.generate(41, (index) => 'Note line $index.');
    final document = _document(
      separator: _separator(),
      noteText: rows.join('\n'),
      height: 150,
    );
    document.footnotes.single.paragraphs.single.properties
      ..lineSpacingRule = WmlLineSpacingRule.exact
      ..lineSpacing = 10
      ..widowControl = true;

    final layout = WordLayoutEngine(font: null).layout(document);
    final continued = layout.pages.expand((page) => page.notes).toList();
    expect(layout.pages.length, greaterThan(3));
    expect(continued.first.text, endsWith(rows.first));
    expect(continued.skip(1).map((line) => line.text), rows.skip(1));
    expect(layout.pages.last.notes.length, greaterThanOrEqualTo(2));
    _expectClearBand(layout, document);
  });

  test('incremental resume preserves footnote continuations', () {
    final document = _document(
      noteText: List.generate(
        45,
        (i) => 'Continued footnote line $i.',
      ).join('\n'),
      bodyParagraphs: 20,
      height: 150,
    );
    final engine = WordLayoutEngine(font: null);
    final before = engine.layout(document, updateFields: false);
    expect(
      before.pages.where((page) => page.notes.isNotEmpty).length,
      greaterThan(2),
    );

    final edited = document.paragraphs.elementAt(1);
    WmlRunEdit.replaceRange(edited, 0, 1, 'X');
    WordIncrementalLayoutStats.reset();
    final resumed = engine.layout(
      document,
      updateFields: false,
      reuse: before,
      dirtyParagraphs: {edited},
    );
    final fresh = WordLayoutEngine(font: null)
        .layout(document, updateFields: false);
    expect(wordLayoutFingerprint(resumed), wordLayoutFingerprint(fresh));
    expect(WordIncrementalLayoutStats.incremental, 1);
    expect(
      engine.layout(WmlDocument.empty(text: 'New document')).pages,
      hasLength(1),
    );
  });

  test('unused footnote preferences do not reserve body space', () {
    final document = _document(addNote: false, bodyParagraphs: 40);
    final engine = WordLayoutEngine(font: null);
    final before = wordLayoutFingerprint(engine.layout(document));
    document.footnoteSeparator = _separator(before: 170);
    // An unreferenced definition is not a visible note.
    document.footnotes.add(WmlNote(id: 42, endnote: false)..text = 'Unused');
    final layout = engine.layout(document);
    expect(wordLayoutFingerprint(layout), before);
    expect(layout.pages.expand(_separators), isEmpty);
  });

  test('dense body and every continued footnote page keep the band clear', () {
    final document = _document(
      separator: _separator(before: 22, thickness: 3, after: 11, width: .6),
      noteText: List.generate(
        180,
        (i) => 'N${i.toString().padLeft(3, '0')}',
      ).join(' '),
      bodyParagraphs: 35,
    );
    final layout = WordLayoutEngine(font: null).layout(document);
    final notePages = layout.pages
        .where((page) => page.notes.isNotEmpty)
        .toList();
    expect(notePages.length, greaterThan(1));
    expect(notePages.every((page) => _separators(page).length == 1), isTrue);
    final text = notePages
        .expand((page) => page.notes)
        .map((line) => line.text)
        .join(' ');
    for (var i = 0; i < 180; i++) {
      expect(
        RegExp('N${i.toString().padLeft(3, '0')}').allMatches(text),
        hasLength(1),
      );
    }
    expect(
      layout.pages
          .expand((page) => page.lines)
          .map((line) => line.text)
          .join(' '),
      contains('Body 34'),
    );
    _expectClearBand(layout, document);
  });

  test('column body leaves one full-body-width note band clear', () {
    final document = _document(
      separator: _separator(width: 1),
      bodyParagraphs: 45,
    );
    document.sections.single.columnCount = 2;
    final layout = WordLayoutEngine(font: null).layout(document);
    expect(_separators(layout.pages.first).single.width, 280);
    _expectClearBand(layout, document);
  });

  for (final style in WmlFootnoteSeparatorLineStyle.values) {
    test('zero-width / $style line still retains explicit gaps', () {
      final document = _document(
        separator: _separator(
          before: 24,
          after: 17,
          width: style == WmlFootnoteSeparatorLineStyle.solid ? 0 : .25,
          lineStyle: style,
        ),
        bodyParagraphs: 40,
      );
      final layout = WordLayoutEngine(font: null).layout(document);
      expect(layout.pages.expand(_separators), isEmpty);
      _expectClearBand(layout, document);
    });
  }

  for (final hiddenByStyle in [false, true]) {
    test(
      'hidden separator reserves nominal thickness: byStyle=$hiddenByStyle',
      () {
        final document = _document(
          separator: _separator(thickness: 24),
          bodyParagraphs: 40,
        );
        final engine = WordLayoutEngine(font: null);
        final visible = engine.layout(document);
        document.footnoteSeparator = _separator(
          thickness: 24,
          width: hiddenByStyle ? .25 : 0,
          lineStyle: hiddenByStyle
              ? WmlFootnoteSeparatorLineStyle.none
              : WmlFootnoteSeparatorLineStyle.solid,
        );
        final hidden = engine.layout(document);
        expect(document.footnoteSeparator!.reservedHeight, 42);
        expect(hidden.pages.expand(_separators), isEmpty);
        Object positions(LaidOutDocument layout) => [
          for (final page in layout.pages)
            [
              for (final line in [...page.lines, ...page.notes])
                (line.pageIndex, line.x, line.y, line.height, line.text),
            ],
        ];
        // LibreOffice reserves nominal thickness even without visible separator ink.
        expect(positions(hidden), positions(visible));
        document.footnoteSeparator = _separator(
          thickness: 0,
          lineStyle: WmlFootnoteSeparatorLineStyle.none,
        );
        final zeroThickness = engine.layout(document);
        expect(
          hidden.pages.first.lines.length,
          lessThan(zeroThickness.pages.first.lines.length),
        );
      },
    );
  }

  test('larger separator reservation repaginates a dense body', () {
    final document = _document(
      separator: _separator(before: 0, thickness: 1, after: 0),
      bodyParagraphs: 30,
    );
    final engine = WordLayoutEngine(font: null);
    final small = engine.layout(document);
    document.footnoteSeparator = _separator(
      before: 80,
      thickness: 4,
      after: 25,
    );
    final large = engine.layout(document);
    expect(
      large.pages.first.lines.length,
      lessThan(small.pages.first.lines.length),
    );
    expect(
      large.pages.expand((page) => page.lines).length,
      small.pages.expand((page) => page.lines).length,
    );
    _expectClearBand(large, document);
  });

  test('separator preference change invalidates incremental note pages', () {
    final document = _document(separator: _separator(), bodyParagraphs: 50);
    final engine = WordLayoutEngine(font: null);
    final before = engine.layout(document, updateFields: false);
    document.footnoteSeparator = _separator(
      before: 60,
      thickness: 3,
      after: 15,
      alignment: WmlFootnoteSeparatorAlignment.right,
    );
    WordIncrementalLayoutStats.reset();
    final reused = engine.layout(
      document,
      updateFields: false,
      reuse: before,
      dirtyParagraphs: <WmlParagraph>{},
    );
    final full = WordLayoutEngine(
      font: null,
    ).layout(document, updateFields: false);
    expect(wordLayoutFingerprint(reused), wordLayoutFingerprint(full));
    expect(WordIncrementalLayoutStats.incremental, 0);
    _expectClearBand(reused, document);
  });

  test('ordinary typing still reuses supported separator pages correctly', () {
    final document = _document(separator: _separator(), bodyParagraphs: 50);
    final engine = WordLayoutEngine(font: null);
    final before = engine.layout(document, updateFields: false);
    final paragraph = document.paragraphs.elementAt(30);
    paragraph.inlines.whereType<WmlRun>().single.text += ' changed';
    final reused = engine.layout(
      document,
      updateFields: false,
      reuse: before,
      dirtyParagraphs: {paragraph},
    );
    final full = WordLayoutEngine(
      font: null,
    ).layout(document, updateFields: false);
    expect(wordLayoutFingerprint(reused), wordLayoutFingerprint(full));
  });

  test('oversized note picture is fitted below the separator reservation', () {
    final document = _document(
      separator: _separator(before: 110, thickness: 4, after: 16),
    );
    document.footnotes.single.blocks.add(
      WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          width: 200,
          height: 200,
          imageBytes: PngBytes.studioCard(width: 2, height: 2),
        ),
      ),
    );
    final original = document.footnotes.single.blocks
        .whereType<WmlVisual>()
        .single
        .visual;
    final layout = WordLayoutEngine(font: null).layout(document);
    final picture = layout.pages
        .expand((page) => page.frames)
        .singleWhere((frame) => frame.visual != null);
    expect(picture.height, lessThanOrEqualTo(90));
    expect(original.height, 200);
    _expectClearBand(layout, document);
  });

  test('separator exhausting the page refuses without changing the source', () {
    final document = _document(separator: _separator(before: 220));
    final text = document.paragraphs.first.text;
    expect(
      () => WordLayoutEngine(font: null).layout(document),
      throwsStateError,
    );
    expect(document.paragraphs.first.text, text);
    expect(document.footnotes.single.text, 'Footnote text');
  });

  test('PDF paints exactly one colored filled separator with exact bounds', () {
    final document = _document(
      separator: _separator(
        before: 10,
        thickness: 3,
        after: 8,
        width: .5,
        alignment: WmlFootnoteSeparatorAlignment.right,
      ),
    );
    final layout = WordLayoutEngine(font: null).layout(document);
    final rule = _separators(layout.pages.single).single;
    final display = PdfFile.open(
      OfficePdfExport.word(document, laidOut: layout),
    ).displayList(0);
    final fills = display.ops
        .whereType<PdfFillPath>()
        .where((path) => (path.color & 0xFFFFFF) == 0xCC3399)
        .toList();
    expect(fills, hasLength(1));
    expect(
      display.ops.whereType<PdfStrokePath>().where(
        (path) => (path.color & 0xFFFFFF) == 0xCC3399,
      ),
      isEmpty,
    );
    final points = fills.single.points
        .where((point) => point.kind != PdfPathKind.close)
        .toList();
    expect(
      points.map((point) => point.x).reduce(math.min),
      closeTo(rule.x, .01),
    );
    expect(
      points.map((point) => point.x).reduce(math.max),
      closeTo(rule.x + rule.width, .01),
    );
    expect(
      points.map((point) => point.y).reduce(math.min),
      closeTo(rule.y, .01),
    );
    expect(
      points.map((point) => point.y).reduce(math.max),
      closeTo(rule.y + rule.height, .01),
    );
  });
}

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

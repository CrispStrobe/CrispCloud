import 'dart:math' as math;

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(
    spacingBefore: 0,
    spacingAfter: 0,
    lineSpacing: 1,
  ),
  inlines: [WmlRun(text: text)],
);

WmlTable _table({bool rtl = false, int span = 1, int rows = 4}) => WmlTable(
  grid: span == 1 ? [100, 100] : [50, 50, 100],
  properties: WmlTableProps(
    borders: true,
    borderColor: '335577',
    borderWidth: 1,
    rightToLeft: rtl,
  ),
  rows: [
    for (var r = 0; r < rows; r++)
      WmlTableRow(
        height: 60,
        cantSplit: true,
        cells: [
          WmlTableCell(
            gridSpan: span,
            vMerge: r == 0 ? WmlVMerge.restart : WmlVMerge.cont,
            fillColor: r == 0 ? 'FFEEDD' : null,
            blocks: [_paragraph(r == 0 ? 'Master' : '')],
          ),
          WmlTableCell(blocks: [_paragraph('Neighbor $r')]),
        ],
      ),
  ],
);

WmlDocument _document(WmlTable table, {double height = 180}) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: WmlPageSize(width: 220, height: height),
      margins: const WmlPageMargins(left: 10, right: 10, top: 10, bottom: 10),
      blocks: [table],
    ),
  ],
);

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

void _expectOnce(LaidOutDocument layout, WmlParagraph paragraph) {
  final glyphs =
      layout.pages
          .expand((page) => [...page.lines, ...page.notes])
          .where((line) => identical(line.sourceParagraph, paragraph))
          .expand((line) => line.glyphs)
          .where((glyph) => !glyph.glyph.isSpace)
          .toList()
        ..sort((a, b) => a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex));
  expect(glyphs.map((glyph) => glyph.glyph.logicalIndex), [
    for (var index = 0; index < paragraph.text.length; index++)
      if (paragraph.text.codeUnitAt(index) != 32) index,
  ], reason: 'One glyph per source character in ${paragraph.text}');
  expect(
    String.fromCharCodes(glyphs.map((glyph) => glyph.glyph.codePoint)),
    paragraph.text.replaceAll(' ', ''),
  );
}

void main() {
  for (final reopen in [false, true]) {
    for (final rtl in [false, true]) {
      for (final span in [1, 2]) {
        test('vertical merge pages reopen=$reopen rtl=$rtl colspan=$span', () {
          var document = _document(_table(rtl: rtl, span: span));
          if (reopen) document = _reopen(document);
          final table = document.sections.single.blocks.single as WmlTable;
          final master =
              table.rows.first.cells.first.blocks.single as WmlParagraph;
          final masterIndex = document.paragraphs.toList().indexOf(master);
          final layout = WordLayoutEngine(font: null).layout(document);
          expect(layout.pages, hasLength(2));
          for (final page in layout.pages) {
            final frames = page.frames.where(
              (box) => identical(box.table, table),
            );
            final neighbors = frames.where((box) => box.tableCol == 1).toList();
            final merged = frames
                .where((box) => box.tableCol == 0 && box.height > 0)
                .toList();
            expect(neighbors, hasLength(2));
            expect(merged, hasLength(1));
            final box = merged.single;
            expect(
              box.y,
              closeTo(neighbors.map((b) => b.y).reduce(math.min), 0.001),
            );
            expect(
              box.y + box.height,
              closeTo(
                neighbors.map((b) => b.y + b.height).reduce(math.max),
                0.001,
              ),
            );
            expect(box.width, 100);
            expect(box.x, rtl ? 110 : 10);
            expect(box.fillColor, 'FFEEDD');
            expect(box.strokeColor, '335577');
            expect(box.strokeWidth, 1);
            expect([
              box.strokeTop,
              box.strokeRight,
              box.strokeBottom,
              box.strokeLeft,
            ], everyElement(isTrue));
            expect((box.tableRow, box.tableCol, box.tableGridCol), (0, 0, 0));
            expect(
              (box.paragraphIndex, box.paragraphEnd),
              (masterIndex, masterIndex),
            );
            expect(box.y, greaterThanOrEqualTo(10));
            expect(box.y + box.height, lessThanOrEqualTo(170));
            for (final hidden in frames.where((box) => box.height == 0)) {
              expect(hidden.fillColor, isNull);
              expect(hidden.strokeColor, '00000000');
              expect(hidden.paragraphIndex, isNull);
              expect(hidden.paragraphEnd, isNull);
            }
          }
          _expectOnce(layout, master);
          for (final row in table.rows) {
            _expectOnce(layout, row.cells.last.blocks.single as WmlParagraph);
          }
        });
      }
    }
  }

  test('separate merge chains and following cells remain independent', () {
    final table = _table(rows: 5);
    table.rows[2].cells.first
      ..vMerge = WmlVMerge.restart
      ..fillColor = 'AABBCC'
      ..blocks = [_paragraph('Second master')];
    table.rows[4].cells.first
      ..vMerge = WmlVMerge.none
      ..fillColor = 'CCDDEE'
      ..blocks = [_paragraph('Independent')];
    final document = _document(table, height: 500);
    final layout = WordLayoutEngine(font: null).layout(document);
    final boxes = layout.pages.single.frames
        .where(
          (box) =>
              identical(box.table, table) &&
              box.tableCol == 0 &&
              box.height > 0,
        )
        .toList();
    expect(boxes.map((box) => box.tableRow), [0, 2, 4]);
    expect(boxes.map((box) => box.height), [120.0, 120.0, 60.0]);
    expect(boxes.map((box) => box.fillColor), ['FFEEDD', 'AABBCC', 'CCDDEE']);
    for (final row in [0, 2, 4]) {
      _expectOnce(
        layout,
        table.rows[row].cells.first.blocks.single as WmlParagraph,
      );
    }
  });

  for (final invalid in [
    'orphan',
    'shifted',
    'mismatched',
    'omitted',
    'nonpositive',
  ]) {
    test('$invalid native continuation does not swallow adjacent cells', () {
      final table = _table(span: 2, rows: 2);
      switch (invalid) {
        case 'orphan':
          table.rows.first.cells.first.vMerge = WmlVMerge.none;
        case 'shifted':
          final continuation = table.rows[1].cells.removeAt(0);
          table.rows[1].cells.add(continuation);
        case 'mismatched':
          table.rows[1].cells.first.gridSpan = 1;
        case 'omitted':
          table.rows.first.cells = table.rows.first.cells.reversed.toList();
          table.rows[1].gridBefore = 1;
        case 'nonpositive':
          table.rows[1].cells.first.gridSpan = 0;
      }
      final layout = WordLayoutEngine(
        font: null,
      ).layout(_document(table, height: 500));
      final first = layout.pages.single.frames.firstWhere(
        (box) =>
            identical(box.table, table) &&
            box.tableRow == 0 &&
            box.tableCol == (invalid == 'omitted' ? 1 : 0),
      );
      expect(first.height, 60);
      for (final row in table.rows) {
        for (final cell in row.cells) {
          for (final paragraph in WordTree.paragraphs(cell.blocks)) {
            _expectOnce(layout, paragraph);
          }
        }
      }
    });
  }

  test(
    'tall restart slices retain master ownership on every physical page',
    () {
      final table = _table(rows: 2);
      table.rows.first
        ..height = null
        ..cantSplit = false;
      table.rows.first.cells.first.blocks = [
        for (var i = 0; i < 35; i++) _paragraph('Master line $i'),
      ];
      final document = _document(table);
      final layout = WordLayoutEngine(font: null).layout(document);
      expect(layout.pages.length, greaterThan(2));
      final masterParagraphs = table.rows.first.cells.first.blocks
          .cast<WmlParagraph>();
      for (final page in layout.pages) {
        final fragments = page.frames
            .where(
              (box) =>
                  identical(box.table, table) &&
                  box.tableCol == 0 &&
                  box.height > 0,
            )
            .toList();
        if (fragments.isEmpty) continue;
        expect(fragments, hasLength(1));
        final fragment = fragments.single;
        expect(fragment.tableRow, 0);
        expect(fragment.fillColor, 'FFEEDD');
        expect(fragment.paragraphIndex, 0);
        expect(fragment.paragraphEnd, 34);
        expect(fragment.y + fragment.height, lessThanOrEqualTo(170.01));
      }
      for (final paragraph in masterParagraphs) {
        _expectOnce(layout, paragraph);
      }
    },
  );

  for (final widowControl in [true, false]) {
    test('tall merged cell cuts respect widow control $widowControl', () {
      final source = _table(rows: 2);
      source.rows.first
        ..height = null
        ..cantSplit = false;
      // Each paragraph wraps to two lines in the narrow cell.
      source.rows.first.cells.first.blocks = [
        for (var i = 0; i < 35; i++)
          _paragraph('Master line $i')..properties.widowControl = widowControl,
      ];
      final document = _document(source);
      final table = document.sections.single.blocks.single as WmlTable;
      final layout = WordLayoutEngine(font: null).layout(document);
      final paragraphs = table.rows.first.cells.first.blocks;
      final pagesOf = <Object, List<int>>{};
      var split = false;
      for (final page in layout.pages) {
        for (final line in page.lines) {
          final paragraph = line.sourceParagraph;
          if (paragraph == null || !paragraphs.contains(paragraph)) continue;
          pagesOf.putIfAbsent(paragraph, () => []).add(page.index);
        }
      }
      for (final pages in pagesOf.values) {
        expect(pages, hasLength(2));
        if (pages.first != pages.last) split = true;
      }
      // Two-line paragraphs either stay together, or (without widow
      // control) fill each page and leave single lines at the cuts.
      expect(split, !widowControl);
    });
  }

  for (final explicitBorder in [false, true]) {
    for (final tableBorders in [false, true]) {
      for (final reopen in [false, true]) {
        test(
          'tall merge keeps interior cuts open with explicit=$explicitBorder tableBorders=$tableBorders reopen=$reopen',
          () {
            final source = _table(rows: 2);
            source.properties.borders = tableBorders;
            source.rows.first
              ..height = null
              ..cantSplit = false;
            source.rows.first.cells.first
              ..borderTop = explicitBorder
              ..borderBottom = explicitBorder
              // One line per paragraph: widow control must not decide where
              // the cell ends (that is covered separately below).
              ..blocks = [for (var i = 0; i < 35; i++) _paragraph('Line $i')];
            var document = _document(source);
            if (reopen) document = _reopen(document);
            final table = document.sections.single.blocks.single as WmlTable;
            final layout = WordLayoutEngine(font: null).layout(document);
            final fragments = layout.pages
                .expand((page) => page.frames)
                .where(
                  (box) =>
                      identical(box.table, table) &&
                      box.tableCol == 0 &&
                      box.height > 0,
                )
                .toList();
            expect(fragments.length, greaterThan(2));
            for (var i = 0; i < fragments.length; i++) {
              expect(fragments[i].strokeTop, explicitBorder && i == 0);
              expect(
                fragments[i].strokeBottom,
                explicitBorder && i == fragments.length - 1,
              );
              expect(fragments[i].strokeLeft, tableBorders);
              expect(fragments[i].strokeRight, tableBorders);
            }
          },
        );

        test(
          'continuation-only pages inherit master edges with explicit=$explicitBorder tableBorders=$tableBorders reopen=$reopen',
          () {
            final source = _table();
            source.properties.borders = tableBorders;
            source.rows.first.cells.first
              ..borderTop = explicitBorder
              ..borderBottom = explicitBorder;
            var document = _document(source);
            if (reopen) document = _reopen(document);
            final table = document.sections.single.blocks.single as WmlTable;
            final layout = WordLayoutEngine(font: null).layout(document);
            expect(layout.pages, hasLength(2));
            for (final page in layout.pages) {
              final fragment = page.frames.singleWhere(
                (box) =>
                    identical(box.table, table) &&
                    box.tableCol == 0 &&
                    box.height > 0,
              );
              // A page starting at a new physical continuation row has a
              // complete outer edge, even when only the master enables it.
              expect(fragment.strokeTop, explicitBorder);
              expect(fragment.strokeBottom, explicitBorder);
              expect(fragment.strokeLeft, tableBorders);
              expect(fragment.strokeRight, tableBorders);
            }
          },
        );
      }
    }
  }

  for (final endnote in [false, true]) {
    for (final explicitBorder in [false, true]) {
      test(
        'reopened note clips master edges with explicit=$explicitBorder endnote=$endnote',
        () {
          final body = _paragraph('Body');
          body.inlines.add(
            WmlRun(text: '1', noteRefId: 1, noteRefEndnote: endnote),
          );
          final table = _table(rows: 6);
          table.properties.borders = !explicitBorder;
          table.rows.first.cells.first
            ..borderTop = explicitBorder
            ..borderBottom = explicitBorder;
          var document = _document(table);
          document.sections.single.blocks = [body];
          final note = WmlNote(id: 1, endnote: endnote, blocks: [table]);
          (endnote ? document.endnotes : document.footnotes).add(note);
          document = _reopen(document);
          final layout = WordLayoutEngine(font: null).layout(document);
          final fragments = layout.pages
              .expand((page) => page.frames)
              .where(
                (box) =>
                    box.isNoteContent &&
                    box.kind == LaidOutBoxKind.tableCell &&
                    box.tableCol == 0 &&
                    box.height > 0,
              )
              .toList();
          expect(fragments.length, greaterThan(1));
          for (var i = 0; i < fragments.length; i++) {
            expect(fragments[i].strokeTop, explicitBorder && i == 0);
            expect(
              fragments[i].strokeBottom,
              explicitBorder && i == fragments.length - 1,
            );
            expect(fragments[i].strokeLeft, !explicitBorder);
            expect(fragments[i].strokeRight, !explicitBorder);
          }
        },
      );
    }
  }

  for (final endnote in [false, true]) {
    for (final reopen in [false, true]) {
      test(
        'note merge remains styled and source owned endnote=$endnote reopen=$reopen',
        () {
          final body = _paragraph('Body');
          body.inlines.add(
            WmlRun(text: '1', noteRefId: 1, noteRefEndnote: endnote),
          );
          var document = _document(_table());
          document.sections.single.blocks = [body];
          final note = WmlNote(
            id: 1,
            endnote: endnote,
            blocks: [_table(span: 2, rows: 6)],
          );
          (endnote ? document.endnotes : document.footnotes).add(note);
          if (reopen) document = _reopen(document);
          final currentNote =
              (endnote ? document.endnotes : document.footnotes).single;
          final table = currentNote.blocks.whereType<WmlTable>().single;
          final master =
              table.rows.first.cells.first.blocks.single as WmlParagraph;
          final layout = WordLayoutEngine(font: null).layout(document);
          expect(layout.pages.length, greaterThan(1));
          _expectOnce(layout, master);
          final fragments = layout.pages
              .expand((page) => page.frames)
              .where(
                (box) =>
                    box.isNoteContent &&
                    box.kind == LaidOutBoxKind.tableCell &&
                    box.tableCol == 0 &&
                    box.height > 0,
              )
              .toList();
          expect(fragments.length, greaterThan(1));
          for (final box in fragments) {
            expect(box.fillColor, 'FFEEDD');
            expect(box.width, 100);
            expect(box.tableRow, 0);
            expect(box.height.isFinite, isTrue);
            expect(box.height, greaterThan(0));
          }
          for (final row in table.rows) {
            _expectOnce(layout, row.cells.last.blocks.single as WmlParagraph);
          }
        },
      );
    }
  }
}

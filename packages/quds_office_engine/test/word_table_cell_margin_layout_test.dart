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

WmlTable _table(double margin, List<WmlBlock> blocks, {double width = 200}) =>
    WmlTable(
      grid: [width],
      properties: WmlTableProps(cellMargin: margin),
      rows: [
        WmlTableRow(cells: [WmlTableCell(blocks: blocks)]),
      ],
    );

WmlDocument _document(List<WmlBlock> blocks, {double height = 500}) =>
    WmlDocument(
      sections: [
        WmlSection(
          pageSize: WmlPageSize(width: 400, height: height),
          margins: const WmlPageMargins(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20,
          ),
          blocks: blocks,
        ),
      ],
    );

WordLayoutEngine _engine() =>
    WordLayoutEngine(font: null, measure: (_, _, _) => 5);

List<LaidOutLine> _lines(LaidOutDocument laid, WmlParagraph paragraph) => [
  for (final page in laid.pages)
    for (final line in [...page.lines, ...page.notes])
      if (identical(line.sourceParagraph, paragraph)) line,
];

void main() {
  test('legacy cell inset fallback matches the native model default', () {
    expect(LaidOutLine.tableCellPad, WmlTableProps().cellMargin);
    expect(LaidOutLine.tableCellPad, 4);
  });

  for (final margin in [0.0, 4.0, 4.25, 12.0]) {
    for (final rtl in [false, true]) {
      test('margin $margin in ${rtl ? 'RTL' : 'LTR'} merged cells', () {
        final first = _paragraph('Merged citation');
        final second = _paragraph('Sibling');
        final table = WmlTable(
          grid: [80, 120, 100],
          properties: WmlTableProps(cellMargin: margin, rightToLeft: rtl),
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(gridSpan: 2, blocks: [first]),
                WmlTableCell(blocks: [second]),
              ],
            ),
          ],
        );
        final laid = _engine().layout(_document([table]));
        expect(laid.pages, hasLength(1));
        final boxes = laid.pages.single.frames
            .where((box) => identical(box.table, table))
            .toList();
        expect(boxes, hasLength(2));
        expect(boxes[0].x, rtl ? 120 : 20);
        expect(boxes[1].x, rtl ? 20 : 220);
        expect(boxes.map((box) => box.width), [200, 100]);
        for (final (index, paragraph) in [first, second].indexed) {
          final line = _lines(laid, paragraph).single;
          final cell = boxes[index];
          expect(line.boxX, cell.x + margin);
          expect(line.boxWidth, cell.width - margin * 2);
          expect(line.y, cell.y + margin);
          expect(cell.height, closeTo(line.height + margin * 2, 0.001));
        }
      });
    }
  }

  test('wrapping and measured row height use the same inner width', () {
    final paragraph = _paragraph('one two three four');
    final table = _table(0, [paragraph], width: 100);
    final document = _document([table]);
    final plain = _engine().layout(document);
    expect(_lines(plain, paragraph), hasLength(1));
    final plainHeight = plain.pages.single.frames.single.height;
    table.properties.cellMargin = 15;
    final padded = _engine().layout(document);
    final lines = _lines(padded, paragraph);
    expect(lines, hasLength(2));
    expect(lines.every((line) => line.boxWidth == 70), isTrue);
    expect(
      padded.pages.single.frames.single.height,
      closeTo(plainHeight + lines.first.height + 30, 0.001),
    );
  });

  test('configured margins move a nonsplitting row before it overflows', () {
    final before = _paragraph(List.filled(9, 'Introduction').join('\n'));
    final paragraph = _paragraph('Row citation');
    final table = _table(0, [paragraph]);
    table.rows.single.cantSplit = true;
    final document = _document([before, table]);
    final baseline = _engine().layout(document);
    final baselineLine = _lines(baseline, paragraph).single;
    // Leave ten points below the unpadded row, independently of font metrics.
    final pageBottom = baselineLine.y + baselineLine.height + 10;
    document.sections.single.pageSize = WmlPageSize(
      width: 400,
      height: pageBottom + 20,
    );
    final plain = _engine().layout(document);
    expect(_lines(plain, paragraph).single.pageIndex, 0);
    table.properties.cellMargin = 20;
    final padded = _engine().layout(document);
    final line = _lines(padded, paragraph).single;
    expect(line.pageIndex, 1);
    final cell = padded.pages[1].frames.singleWhere(
      (box) => identical(box.table, table),
    );
    expect(cell.y, 20);
    expect(line.y, cell.y + 20);
    expect(cell.y + cell.height, lessThanOrEqualTo(pageBottom));
  });

  test('nested heterogeneous margins compose without leaking to siblings', () {
    final innerText = _paragraph('Nested source');
    final siblingText = _paragraph('Unpadded sibling');
    final inner = _table(19, [innerText], width: 250);
    final outer = _table(7, [inner]);
    final sibling = _table(0, [siblingText]);
    final laid = _engine().layout(_document([outer, sibling]));
    final frames = laid.pages.single.frames;
    final outerBox = frames.singleWhere((box) => identical(box.table, outer));
    final innerBox = frames.singleWhere((box) => identical(box.table, inner));
    final siblingBox = frames.singleWhere(
      (box) => identical(box.table, sibling),
    );
    expect(innerBox.x, outerBox.x + 7);
    expect(innerBox.y, outerBox.y + 7 + 6);
    expect(innerBox.width, outerBox.width - 14);
    final innerLine = _lines(laid, innerText).single;
    expect(innerLine.boxX, innerBox.x + 19);
    expect(innerLine.boxWidth, innerBox.width - 38);
    expect(innerLine.y, innerBox.y + 19);
    expect(outerBox.height, innerBox.height + 14 + 10);
    final siblingLine = _lines(laid, siblingText).single;
    expect(siblingLine.boxX, siblingBox.x);
    expect(siblingLine.boxWidth, siblingBox.width);
    expect(siblingLine.y, siblingBox.y);
  });

  test('vertical merged origins retain their configured text inset', () {
    final paragraph = _paragraph('Merged vertically');
    final table = WmlTable(
      grid: [180, 120],
      properties: WmlTableProps(cellMargin: 12),
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(vMerge: WmlVMerge.restart, blocks: [paragraph]),
            WmlTableCell(blocks: [_paragraph('First row')]),
          ],
        ),
        WmlTableRow(
          cells: [
            WmlTableCell(vMerge: WmlVMerge.cont),
            WmlTableCell(blocks: [_paragraph('Second row')]),
          ],
        ),
      ],
    );
    final laid = _engine().layout(_document([table]));
    final origin = laid.pages.single.frames.firstWhere(
      (box) => identical(box.table, table) && box.tableCol == 0,
    );
    final line = _lines(laid, paragraph).single;
    expect(line.boxX, origin.x + 12);
    expect(line.boxWidth, origin.width - 24);
    expect(line.y, origin.y + 12);
    expect(origin.height, greaterThan(line.height + 24));
  });

  for (final tall in [false, true]) {
    test('nested picture budgets use actual margins, tall row $tall', () {
      final text = [
        for (var index = 0; index < (tall ? 40 : 0); index++)
          _paragraph('Row$index'),
      ];
      final visual = OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: 'Nested research picture',
        imageBytes: PngBytes.studioCard(width: 12, height: 12),
        width: 60,
        height: 1000,
      );
      final inner = _table(19, [
        ...text.take(20),
        WmlVisual(visual: visual),
        ...text.skip(20),
      ]);
      final outer = _table(7, [inner], width: 300);
      final document = _document([outer], height: 300);
      final laid = _engine().layout(document);
      if (tall) expect(laid.pages.length, greaterThan(1));
      final pictures = [
        for (final page in laid.pages)
          for (final box in page.frames)
            if (identical(box.visual, visual)) (page: page, box: box),
      ];
      expect(pictures, hasLength(1));
      final picture = pictures.single;
      // 260 point body, 18 picture flow gaps, outer7+inner19 on each
      // vertical side, and ten points of flow around the nested table.
      expect(picture.box.height, 180);
      expect(picture.box.width, 60);
      expect(picture.box.x, 20 + 7 + 19);
      expect(picture.box.y, greaterThanOrEqualTo(20));
      expect(picture.box.y + picture.box.height, lessThanOrEqualTo(280));
      expect(visual.height, 1000, reason: 'Layout never mutates the image.');
      for (final paragraph in text) {
        final lines = _lines(laid, paragraph);
        expect(lines, hasLength(1), reason: paragraph.text);
        expect(lines.single.boxX, 20 + 7 + 19);
        expect(lines.single.boxWidth, 200 - 38);
      }
    });
  }

  for (final endnote in [false, true]) {
    for (final margin in [0.0, 11.0]) {
      test('${endnote ? 'endnote' : 'footnote'} table margin $margin', () {
        final paragraph = _paragraph('Note citation');
        final table = _table(margin, [paragraph]);
        final anchor = _paragraph('Body');
        anchor.inlines.add(
          WmlRun(text: '1', noteRefId: 1, noteRefEndnote: endnote),
        );
        final document = _document([anchor]);
        final note = WmlNote(
          id: 1,
          endnote: endnote,
          addReference: false,
          blocks: [table],
        );
        (endnote ? document.endnotes : document.footnotes).add(note);
        final laid = _engine().layout(document);
        final frames = [
          for (final page in laid.pages)
            for (final box in page.frames)
              if (box.table != null) box,
        ];
        expect(frames, hasLength(1));
        final frame = frames.single;
        expect(frame.isNoteContent, isTrue);
        final line = _lines(laid, paragraph).single;
        expect(line.boxX, frame.x + margin);
        expect(line.boxWidth, frame.width - 2 * margin);
        expect(line.y, frame.y + margin);
        expect(frame.height, closeTo(line.height + 2 * margin, 0.001));
        expect(table.properties.cellMargin, margin);
      });
    }

    test('${endnote ? 'endnote' : 'footnote'} nested picture margins', () {
      final visual = OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: 'Note research picture',
        imageBytes: PngBytes.studioCard(width: 12, height: 12),
        width: 60,
        height: 40,
      );
      final inner = _table(19, [WmlVisual(visual: visual)]);
      final outer = _table(7, [inner], width: 300);
      final anchor = _paragraph('Body');
      anchor.inlines.add(
        WmlRun(text: '1', noteRefId: 1, noteRefEndnote: endnote),
      );
      final document = _document([anchor]);
      (endnote ? document.endnotes : document.footnotes).add(
        WmlNote(id: 1, endnote: endnote, addReference: false, blocks: [outer]),
      );
      final laid = _engine().layout(document);
      final frames = laid.pages.expand((page) => page.frames).toList();
      final picture = frames.singleWhere((box) => box.visual != null);
      final innerBox = frames.singleWhere(
        (box) => box.table?.properties.cellMargin == 19,
      );
      expect(picture.isNoteContent, isTrue);
      expect(picture.x, innerBox.x + 19);
      expect(picture.y, innerBox.y + 19 + 8);
      expect(picture.width, 60);
      expect(picture.height, 40);
      expect(innerBox.height, 38 + 18 + 40);
      expect(visual.width, 60);
      expect(visual.height, 40);
    });
  }

  for (final margin in [
    -1.0,
    double.nan,
    double.infinity,
    double.negativeInfinity,
    50.0,
    51.0,
    double.maxFinite,
  ]) {
    test('invalid or exhausted cell margin $margin fails explicitly', () {
      final table = _table(margin, [_paragraph('Source')], width: 100);
      expect(() => _engine().layout(_document([table])), throwsArgumentError);
    });
  }

  test('visual-only endnotes require a unique referenced definition', () {
    WmlNote pictureNote(int id, String title) => WmlNote(
      id: id,
      endnote: true,
      addReference: false,
      blocks: [
        WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.picture,
            title: title,
            imageBytes: PngBytes.studioCard(width: 12, height: 12),
            width: 40,
            height: 30,
          ),
        ),
      ],
    );
    final anchor = _paragraph('Body');
    anchor.inlines.addAll([
      WmlRun(text: '1', noteRefId: 1, noteRefEndnote: true),
      WmlRun(text: '3', noteRefId: 3, noteRefEndnote: true),
    ]);
    final document = _document([anchor]);
    document.sections.single.blocks.add(
      WmlFrame(
        x: 20,
        y: 80,
        width: 160,
        height: 40,
        blocks: [
          WmlParagraph(
            inlines: [WmlRun(text: '4', noteRefId: 4, noteRefEndnote: true)],
          ),
        ],
      ),
    );
    document.endnotes.addAll([
      pictureNote(1, 'Referenced'),
      pictureNote(2, 'Orphan'),
      pictureNote(3, 'Ambiguous first'),
      pictureNote(3, 'Ambiguous second'),
      pictureNote(4, 'Frame-only reference'),
    ]);
    final laid = _engine().layout(document);
    expect(
      laid.pages
          .expand((page) => page.frames)
          .map((box) => box.visual?.title)
          .whereType<String>(),
      ['Referenced'],
    );
    expect(document.endnotes, hasLength(5));
  });

  test('failed nested layout restores the enclosing margin budget', () {
    final engine = _engine();
    final inner = _table(100, [_paragraph('Invalid')], width: 100);
    final outer = _table(7, [inner]);
    expect(() => engine.layout(_document([outer])), throwsArgumentError);
    final visual = OfficeVisual(
      kind: OfficeVisualKind.picture,
      title: 'Recovery picture',
      imageBytes: PngBytes.studioCard(width: 12, height: 12),
      width: 60,
      height: 1000,
    );
    final table = _table(0, [WmlVisual(visual: visual)]);
    final laid = engine.layout(_document([table], height: 300));
    final picture = laid.pages
        .expand((page) => page.frames)
        .singleWhere((box) => identical(box.visual, visual));
    expect(picture.height, 260 - 18);
  });
}

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

WmlDocument _document(List<WmlBlock> cellBlocks) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 500, height: 600),
      margins: const WmlPageMargins(left: 24, right: 24, top: 24, bottom: 24),
      blocks: [
        _paragraph('Body before'),
        WmlTable(
          grid: [260, 160],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: cellBlocks),
                WmlTableCell(blocks: [_paragraph('Sibling cell')]),
              ],
            ),
          ],
        ),
        _paragraph('Body after'),
      ],
    ),
  ],
);

List<LaidOutLine> _lines(
  LaidOutDocument laid,
  WmlDocument document,
  WmlParagraph paragraph,
) {
  final index = document.paragraphs.toList().indexOf(paragraph);
  expect(index, greaterThanOrEqualTo(0));
  return laid.pages
      .expand((page) => page.lines)
      .where((line) => line.paragraphIndex == index)
      .toList();
}

void _expectVisibleText(
  LaidOutDocument laid,
  WmlDocument document,
  WmlParagraph paragraph,
) {
  final lines = _lines(laid, document, paragraph);
  expect(lines, isNotEmpty, reason: 'Visible paragraph: ${paragraph.text}');
  final glyphs =
      lines
          .expand((line) => line.glyphs)
          .where((glyph) => !glyph.glyph.isSpace)
          .toList()
        ..sort((a, b) => a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex));
  final expected = [
    for (var index = 0; index < paragraph.text.length; index++)
      if (paragraph.text.codeUnitAt(index) != 32) index,
  ];
  expect(
    glyphs.map((glyph) => glyph.glyph.logicalIndex),
    expected,
    reason: 'Each character belongs to the actual paragraph ${paragraph.text}',
  );
  expect(
    String.fromCharCodes(glyphs.map((glyph) => glyph.glyph.codePoint)),
    paragraph.text.replaceAll(' ', ''),
    reason: 'The correct text is painted under its paragraph identity',
  );
}

void main() {
  for (final reopen in [false, true]) {
    final mode = reopen ? 'native reopened' : 'live';
    test(
      '$mode cell picture is visible within the cell before following text',
      () {
        var document = _document([
          _paragraph('Cell starts'),
          WmlVisual(
            visual: OfficeVisual(
              kind: OfficeVisualKind.picture,
              title: 'Cell picture',
              imageBytes: PngBytes.studioCard(width: 32, height: 24),
              width: 80,
              height: 60,
            ),
          ),
          _paragraph('Cell ends'),
        ]);
        if (reopen) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final outer = document.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        final cell = outer.rows.single.cells.first;
        cell.fillColor = 'FFF1D6';
        final picture = cell.blocks.whereType<WmlVisual>().single.visual;
        final before = cell.blocks.first as WmlParagraph;
        final after = cell.blocks.last as WmlParagraph;
        expect(picture.imageBytes, isNotEmpty);
        final laid = WordLayoutEngine(font: null).layout(document);
        expect(laid.pages, hasLength(1));
        final frames = laid.pages.single.frames;
        final pictureFrames = frames
            .where((frame) => identical(frame.visual, picture))
            .toList();
        expect(
          pictureFrames,
          hasLength(1),
          reason:
              'Export preservation does not prove the cell picture is painted',
        );
        final visible = pictureFrames.single;
        expect(visible.kind, LaidOutBoxKind.picture);
        expect(visible.width, greaterThan(0));
        expect(visible.height, greaterThan(0));
        final cellFrame = frames.singleWhere(
          (frame) => identical(frame.table, outer) && frame.tableCol == 0,
        );
        expect(
          frames.indexOf(cellFrame),
          lessThan(frames.indexOf(visible)),
          reason: 'Opaque parent fill must paint before the child picture',
        );
        expect(visible.x, greaterThanOrEqualTo(cellFrame.x));
        expect(
          visible.x + visible.width,
          lessThanOrEqualTo(cellFrame.x + cellFrame.width + 0.01),
        );
        expect(visible.y, greaterThan(_lines(laid, document, before).last.y));
        expect(
          _lines(laid, document, after).first.y,
          greaterThanOrEqualTo(visible.y + visible.height),
        );
        expect(
          visible.y + visible.height,
          lessThanOrEqualTo(cellFrame.y + cellFrame.height + 0.01),
        );
        for (final paragraph in document.paragraphs) {
          _expectVisibleText(laid, document, paragraph);
        }
      },
    );

    test(
      '$mode nested table paints child cells without stealing following paragraph identities',
      () {
        var document = _document([
          _paragraph('Cell starts'),
          WmlTable(
            grid: [110, 110],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(blocks: [_paragraph('Nested left')]),
                  WmlTableCell(blocks: [_paragraph('Nested right')]),
                ],
              ),
            ],
          ),
          _paragraph('Cell ends'),
        ]);
        if (reopen) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final outer = document.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        final outerCell = outer.rows.single.cells.first;
        final nested = outerCell.blocks.whereType<WmlTable>().single;
        final left =
            nested.rows.single.cells.first.blocks.single as WmlParagraph;
        final right =
            nested.rows.single.cells.last.blocks.single as WmlParagraph;
        final after = outerCell.blocks.last as WmlParagraph;
        final laid = WordLayoutEngine(font: null).layout(document);
        expect(laid.pages, hasLength(1));
        final frames = laid.pages.single.frames;
        final nestedFrames = frames
            .where((frame) => identical(frame.table, nested))
            .toList();
        expect(
          nestedFrames,
          hasLength(2),
          reason: 'Both nested cells need actual visible border/layout objects',
        );
        _expectVisibleText(laid, document, left);
        _expectVisibleText(laid, document, right);
        _expectVisibleText(laid, document, after);
        final leftLine = _lines(laid, document, left).single;
        final rightLine = _lines(laid, document, right).single;
        expect(rightLine.x, greaterThan(leftLine.x));
        expect(rightLine.y, closeTo(leftLine.y, 0.01));
        final nestedBottom = nestedFrames
            .map((frame) => frame.y + frame.height)
            .reduce((a, b) => a > b ? a : b);
        expect(
          _lines(laid, document, after).first.y,
          greaterThanOrEqualTo(nestedBottom),
        );
        final outerFrame = frames.singleWhere(
          (frame) => identical(frame.table, outer) && frame.tableCol == 0,
        );
        expect(
          outerFrame.paragraphIndex,
          document.paragraphs.toList().indexOf(
            outerCell.blocks.first as WmlParagraph,
          ),
        );
        expect(
          outerFrame.paragraphEnd,
          document.paragraphs.toList().indexOf(after),
        );
        for (final paragraph in document.paragraphs) {
          _expectVisibleText(laid, document, paragraph);
        }
      },
    );

    test(
      '$mode absolute cell frame paints its own text and keeps following identities',
      () {
        var document = _document([
          _paragraph('Cell starts'),
          WmlFrame(
            x: 72,
            y: 120,
            width: 140,
            height: 52,
            anchor: WmlFrameAnchor.page,
            wrap: WmlFrameWrap.none,
            fillColor: 'F0F4F8',
            strokeColor: '234567',
            blocks: [_paragraph('Frame text visible')],
          ),
          _paragraph('Cell ends'),
        ]);
        if (reopen) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final outer = document.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        final cell = outer.rows.single.cells.first;
        final frame = cell.blocks.whereType<WmlFrame>().single;
        final framedText = frame.blocks.single as WmlParagraph;
        final laid = WordLayoutEngine(font: null).layout(document);
        final visible = laid.pages
            .expand((page) => page.frames)
            .where((box) => identical(box.frame, frame))
            .toList();
        expect(
          visible,
          hasLength(1),
          reason:
              'The absolute frame still needs a visible layout object inside a cell',
        );
        expect(visible.single.kind, LaidOutBoxKind.frame);
        expect(
          visible.single.x,
          closeTo(frame.pageX(document.sections.single), 0.01),
        );
        expect(
          visible.single.y,
          closeTo(frame.pageY(document.sections.single), 0.01),
        );
        expect(visible.single.width, closeTo(frame.width, 0.01));
        expect(visible.single.height, closeTo(frame.height, 0.01));
        _expectVisibleText(laid, document, framedText);
        final line = _lines(laid, document, framedText).first;
        expect(line.x, greaterThanOrEqualTo(visible.single.x));
        expect(line.y, greaterThanOrEqualTo(visible.single.y));
        for (final paragraph in document.paragraphs) {
          _expectVisibleText(laid, document, paragraph);
        }
      },
    );

    test(
      '$mode cell TOC paints title, each entry and correct following paragraphs',
      () {
        var document = _document([
          _paragraph('Cell starts'),
          WmlToc(title: 'Cell contents'),
          _paragraph('Cell ends'),
        ]);
        final heading = document.paragraphs.last;
        heading.inlines
          ..clear()
          ..add(WmlRun(text: 'Outside heading'));
        WordToc.applyHeading(heading, 1);
        WordToc.refreshAll(document);
        if (reopen) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final toc = WordToc.tocs(document).single;
        expect(toc.entries, hasLength(1));
        expect(toc.itemParagraphs, hasLength(1));
        expect(toc.entries.single.text, 'Outside heading');
        final laid = WordLayoutEngine(font: null).layout(document);
        _expectVisibleText(laid, document, toc.titleParagraph);
        _expectVisibleText(laid, document, toc.itemParagraphs.single);
        final entryBoxes = laid.pages
            .expand((page) => page.frames)
            .where((box) => box.kind == LaidOutBoxKind.tocEntry)
            .toList();
        expect(
          entryBoxes,
          hasLength(1),
          reason: 'Every TOC entry must have an actual clickable layout box',
        );
        final entryLines = _lines(laid, document, toc.itemParagraphs.single);
        expect(
          entryLines.every(
            (line) =>
                line.tocTargetParagraph ==
                toc.entries.single.headingParagraphIndex,
          ),
          isTrue,
        );
        expect(entryLines.last.overlayText, '${toc.entries.single.pageNumber}');
        final outer = document.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        final after = outer.rows.single.cells.first.blocks.last as WmlParagraph;
        expect(
          _lines(laid, document, after).first.y,
          greaterThan(entryLines.last.y),
        );
        for (final paragraph in document.paragraphs) {
          _expectVisibleText(laid, document, paragraph);
        }
      },
    );

    test(
      '$mode continued sibling cells retain source paragraph identities',
      () {
        var document = _document([
          for (var i = 0; i < 6; i++)
            _paragraph(
              'Left $i has enough words to wrap across two cell lines',
            ),
        ]);
        document.paragraphs.first.properties.spacingAfter = 430;
        final table = document.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        table.rows.single.cells.last.blocks
          ..clear()
          ..add(_paragraph('Right alpha'))
          ..add(_paragraph('Right beta'));
        if (reopen) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final laid = WordLayoutEngine(font: null).layout(document);
        expect(laid.pages.length, greaterThan(1));
        final actualTable = document.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        final first =
            actualTable.rows.single.cells.first.blocks.first as WmlParagraph;
        final last =
            actualTable.rows.single.cells.first.blocks.last as WmlParagraph;
        expect(
          _lines(laid, document, first).first.pageIndex,
          lessThan(_lines(laid, document, last).last.pageIndex),
        );
        for (final paragraph in document.paragraphs) {
          _expectVisibleText(laid, document, paragraph);
        }
      },
    );

    test(
      '$mode narrow picture-only cell does not claim sibling paragraph identity',
      () {
        var document = _document([
          WmlVisual(
            visual: OfficeVisual(
              kind: OfficeVisualKind.picture,
              title: 'Tiny cell picture',
              imageBytes: PngBytes.studioCard(width: 8, height: 8),
              width: 80,
              height: 24,
            ),
          ),
        ]);
        document.sections.single.blocks.whereType<WmlTable>().single.grid[0] =
            18;
        if (reopen) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final table = document.sections.single.blocks
            .whereType<WmlTable>()
            .single;
        final visual = table.rows.single.cells.first.blocks
            .whereType<WmlVisual>()
            .single
            .visual;
        final laid = WordLayoutEngine(font: null).layout(document);
        final frames = laid.pages.single.frames;
        final cell = frames.singleWhere(
          (b) => identical(b.table, table) && b.tableCol == 0,
        );
        final picture = frames.singleWhere((b) => identical(b.visual, visual));
        expect(picture.width, greaterThan(0));
        expect(
          picture.x + picture.width,
          lessThanOrEqualTo(cell.x + cell.width),
        );
        expect(cell.paragraphIndex, isNull);
        expect(cell.paragraphEnd, isNull);
        for (final paragraph in document.paragraphs) {
          _expectVisibleText(laid, document, paragraph);
        }
      },
    );
  }
}

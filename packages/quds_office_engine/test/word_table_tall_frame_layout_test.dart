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

WmlDocument _document(WmlFrameAnchor anchor, {required bool last}) {
  final child = _paragraph('Frame child');
  child.inlines.add(
    WmlRun(
      text: '1',
      noteRefId: 1,
      properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
    ),
  );
  final frame = WmlFrame(
    x: 72,
    y: 80,
    width: 140,
    height: 52,
    anchor: anchor,
    wrap: WmlFrameWrap.none,
    fillColor: 'E5EEF8',
    strokeColor: '234567',
    blocks: [child],
  );
  final blocks = <WmlBlock>[
    for (var index = 0; index < 40; index++)
      _paragraph('Flow ${index.toString().padLeft(2, '0')}'),
  ]..insert(last ? 40 : 24, frame);
  final document = WmlDocument(
    sections: [
      WmlSection(
        pageSize: const WmlPageSize(width: 500, height: 320),
        margins: const WmlPageMargins(left: 24, right: 24, top: 24, bottom: 24),
        blocks: [
          _paragraph('Before table'),
          WmlTable(
            grid: [260, 160],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(blocks: blocks),
                  WmlTableCell(blocks: [_paragraph('Sibling cell')]),
                ],
              ),
            ],
          ),
          _paragraph('After table'),
        ],
      ),
    ],
  );
  document.footnotes.add(
    WmlNote(
      id: 1,
      endnote: false,
      paragraphs: [_paragraph('Note from the frame')],
    ),
  );
  return document;
}

void _expectParagraphOnce(
  LaidOutDocument laid,
  WmlDocument document,
  WmlParagraph paragraph,
) {
  final index = document.paragraphs.toList().indexOf(paragraph);
  final glyphs =
      laid.pages
          .expand((page) => page.lines)
          .where((line) => line.paragraphIndex == index)
          .expand((line) => line.glyphs)
          .where((glyph) => !glyph.glyph.isSpace)
          .toList()
        ..sort((a, b) => a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex));
  expect(
    glyphs.map((glyph) => glyph.glyph.logicalIndex),
    [
      for (var index = 0; index < paragraph.text.length; index++)
        if (paragraph.text.codeUnitAt(index) != 32) index,
    ],
    reason: 'Exactly one visible glyph per source character: ${paragraph.text}',
  );
  expect(
    String.fromCharCodes(glyphs.map((glyph) => glyph.glyph.codePoint)),
    paragraph.text.replaceAll(' ', ''),
  );
}

void main() {
  for (final reopen in [false, true]) {
    for (final anchor in WmlFrameAnchor.values) {
      for (final last in [false, true]) {
        test(
          '${reopen ? 'reopened' : 'live'} tall-row ${anchor.name} frame '
          '${last ? 'at final boundary' : 'at a later source position'} '
          'keeps absolute coordinates, child identity and its footnote page',
          () {
            var document = _document(anchor, last: last);
            if (reopen) {
              document = WordDeserializer().readBytes(
                WordSerializer().writeBytes(document),
              );
            }
            final section = document.sections.single;
            final table = section.blocks.whereType<WmlTable>().single;
            final cell = table.rows.single.cells.first;
            final frame = cell.blocks.whereType<WmlFrame>().single;
            final child = frame.blocks.single as WmlParagraph;
            final paragraphs = document.paragraphs.toList();
            final laid = WordLayoutEngine(font: null).layout(document);
            expect(laid.pages.length, greaterThan(1));

            final visible = [
              for (final page in laid.pages)
                for (final box in page.frames)
                  if (identical(box.frame, frame)) (page: page, box: box),
            ];
            expect(
              visible,
              hasLength(1),
              reason: 'An anchored frame is never sliced',
            );
            final placed = visible.single;
            expect(placed.page.index, greaterThan(0));
            expect(placed.box.x, closeTo(frame.pageX(section), 0.01));
            expect(placed.box.y, closeTo(frame.pageY(section), 0.01));
            expect(placed.box.width, closeTo(frame.width, 0.01));
            expect(placed.box.height, closeTo(frame.height, 0.01));
            final childLines = placed.page.lines
                .where(
                  (line) => line.paragraphIndex == paragraphs.indexOf(child),
                )
                .toList();
            expect(childLines, hasLength(1));
            expect(
              childLines.single.x,
              closeTo(frame.pageX(section) + LaidOutLine.framePad, 0.01),
            );
            expect(
              childLines.single.y,
              closeTo(frame.pageY(section) + LaidOutLine.framePad, 0.01),
            );
            if (last) {
              final finalRowPage = laid.pages.lastWhere(
                (page) => page.frames.any((box) => identical(box.table, table)),
              );
              expect(placed.page.index, finalRowPage.index);
            } else {
              final after = cell.blocks.whereType<WmlParagraph>().singleWhere(
                (paragraph) => paragraph.text == 'Flow 24',
              );
              final anchorPage = laid.pages.singleWhere(
                (page) => page.lines.any(
                  (line) => line.paragraphIndex == paragraphs.indexOf(after),
                ),
              );
              expect(placed.page.index, anchorPage.index);
            }
            final notePages = laid.pages
                .where((page) => page.notes.isNotEmpty)
                .toList();
            expect(notePages, hasLength(1));
            expect(notePages.single.index, placed.page.index);
            expect(
              notePages.single.notes.map((line) => line.sourceText).join(' '),
              contains('Note from the frame'),
            );
            for (final paragraph in paragraphs) {
              _expectParagraphOnce(laid, document, paragraph);
            }
          },
        );
      }
    }
  }
}

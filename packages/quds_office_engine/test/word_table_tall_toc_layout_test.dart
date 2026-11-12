import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(
    spacingBefore: 0,
    spacingAfter: 0,
    lineSpacing: 1,
  ),
  inlines: [
    WmlRun(text: text, properties: WmlRunProps(fontSizeHalfPoints: 22)),
  ],
);

WmlDocument _document({required bool pageNumbers}) {
  // This entry is taller than a real page even by itself. Its target is
  // outside the table and deliberately differs from the row's paragraph base.
  final heading = _paragraph(
    List.generate(90, (index) => 'Section${index + 1}').join(' '),
  );
  heading.properties
    ..styleId = 'Heading1'
    ..headingLevel = 1;
  final toc = WmlToc(title: 'Tall row contents', showPageNumbers: pageNumbers);
  final document = WmlDocument(
    sections: [
      WmlSection(
        pageSize: const WmlPageSize(width: 400, height: 250),
        margins: const WmlPageMargins(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20,
          header: 0,
          footer: 0,
        ),
        blocks: [
          _paragraph('Prelude'),
          heading,
          _paragraph('Before the table'),
          WmlTable(
            grid: [180],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    blocks: [
                      for (var index = 0; index < 4; index++)
                        _paragraph('Before entry $index'),
                      toc,
                      for (var index = 0; index < 4; index++)
                        _paragraph('After entry $index'),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _paragraph('After the table'),
        ],
      ),
    ],
  );
  WordToc.refreshAll(document);
  toc.entries.single.pageNumber = 7;
  toc.itemParagraphs.single.properties.lineSpacing = 1;
  return document;
}

void main() {
  for (final reopen in [false, true]) {
    for (final pageNumbers in [true, false]) {
      final mode = reopen ? 'native reopened' : 'live';
      test(
        '$mode tall-row TOC retains global links and '
        '${pageNumbers ? 'final page overlay' : 'suppressed page overlay'}',
        () {
          var document = _document(pageNumbers: pageNumbers);
          if (reopen) {
            document = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
          }
          final toc = WordToc.tocs(document).single;
          final paragraphs = document.paragraphs.toList();
          final entry = toc.itemParagraphs.single;
          final entryIndex = paragraphs.indexOf(entry);
          final target = paragraphs.indexWhere(
            (paragraph) => WordToc.headingLevelOf(paragraph) == 1,
          );
          expect(target, 1);
          final targetParagraph = paragraphs[target];
          expect(targetParagraph.properties.headingLevel, 1);
          expect(entryIndex, greaterThan(target));
          expect(toc.showPageNumbers, pageNumbers);

          final laid = WordLayoutEngine(font: null).layout(document);
          expect(laid.pages.length, greaterThan(1));
          final entryLines = laid.pages
              .expand((page) => page.lines)
              .where((line) => line.paragraphIndex == entryIndex)
              .toList();
          expect(entryLines, isNotEmpty);
          expect(
            entryLines.map((line) => line.pageIndex).toSet().length,
            greaterThan(1),
            reason: 'The entry itself must cross a row continuation boundary',
          );
          expect(
            entryLines.map((line) => line.tocTargetParagraph).toSet(),
            {target},
            reason: 'A row-local source index must not replace the global link',
          );
          expect(
            entryLines
                .take(entryLines.length - 1)
                .every((line) => line.overlayText == null && !line.tocLeader),
            isTrue,
          );
          expect(
            entryLines.last.overlayText,
            pageNumbers ? '${toc.entries.single.pageNumber}' : null,
          );
          expect(entryLines.last.tocLeader, pageNumbers);

          final glyphs = entryLines.expand((line) => line.glyphs).toList()
            ..sort(
              (a, b) => a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex),
            );
          expect(
            String.fromCharCodes(
              glyphs
                  .where((glyph) => !glyph.glyph.isSpace)
                  .map((glyph) => glyph.glyph.codePoint),
            ),
            entry.text.replaceAll(' ', ''),
            reason: 'Slicing must preserve the complete entry under its own ID',
          );
          final anchor = targetParagraph.properties.bookmarkName;
          expect(anchor, isNotNull);
          expect(
            glyphs
                .where((glyph) => !glyph.glyph.isSpace)
                .every((glyph) => glyph.hyperlink?.anchor == anchor),
            isTrue,
          );

          var hitboxes = 0;
          for (final page in laid.pages) {
            for (final box in page.frames.where(
              (box) => box.kind == LaidOutBoxKind.tocEntry,
            )) {
              hitboxes++;
              expect(box.paragraphIndex, target);
              expect(box.height, greaterThan(0));
              expect(
                page.lines.any(
                  (line) =>
                      line.paragraphIndex == entryIndex &&
                      line.y < box.y + box.height &&
                      line.y + line.height > box.y,
                ),
                isTrue,
                reason: 'Each continuation hitbox covers visible entry text',
              );
            }
          }
          expect(hitboxes, greaterThan(1));
          expect(toc.entries.single.headingParagraphIndex, target);
        },
      );
    }
  }
}

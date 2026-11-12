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

WmlDocument _document(List<WmlBlock> blocks) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 500, height: 320),
      margins: const WmlPageMargins(left: 24, right: 24, top: 24, bottom: 24),
      blocks: [
        _paragraph('Before table'),
        ...blocks,
        _paragraph('After table'),
      ],
    ),
  ],
);

WmlTable _wrap(WmlBlock content, int depth, {bool surroundingText = true}) {
  WmlBlock current = content;
  for (var level = depth; level >= 1; level--) {
    current = WmlTable(
      grid: surroundingText ? [260, 100] : [260],
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(
              blocks: [
                if (surroundingText) _paragraph('Before nested $level'),
                current,
                if (surroundingText) _paragraph('After nested $level'),
              ],
            ),
            if (surroundingText)
              WmlTableCell(blocks: [_paragraph('Sibling $level')]),
          ],
        ),
      ],
    );
  }
  return current as WmlTable;
}

void _expectTextOnce(LaidOutDocument laid, WmlDocument document) {
  final paragraphs = document.paragraphs.toList();
  for (var index = 0; index < paragraphs.length; index++) {
    final paragraph = paragraphs[index];
    final glyphs =
        laid.pages
            .expand((page) => page.lines)
            .where((line) => line.paragraphIndex == index)
            .expand((line) => line.glyphs)
            .where((glyph) => !glyph.glyph.isSpace)
            .toList()
          ..sort(
            (a, b) => a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex),
          );
    expect(glyphs.map((glyph) => glyph.glyph.logicalIndex), [
      for (var index = 0; index < paragraph.text.length; index++)
        if (paragraph.text.codeUnitAt(index) != 32) index,
    ], reason: 'Exactly one visible source character: ${paragraph.text}');
    expect(
      String.fromCharCodes(glyphs.map((glyph) => glyph.glyph.codePoint)),
      paragraph.text.replaceAll(' ', ''),
    );
  }
}

void main() {
  for (final reopen in [false, true]) {
    final mode = reopen ? 'reopened' : 'live';
    for (final depth in [1, 2, 3]) {
      test('$mode 500pt inline picture fits at table depth $depth', () {
        final bytes = PngBytes.studioCard(width: 32, height: 24);
        var document = _document([
          _wrap(
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                imageBytes: bytes,
                width: 80,
                height: 500,
              ),
            ),
            depth,
          ),
        ]);
        if (reopen) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final visual = document.visuals.single.visual;
        final section = document.sections.single;
        final laid = WordLayoutEngine(font: null).layout(document);
        final visible = [
          for (final page in laid.pages)
            for (final box in page.frames)
              if (identical(box.visual, visual)) (page: page, box: box),
        ];
        expect(
          visible,
          hasLength(1),
          reason: 'The picture is not split or lost',
        );
        final placed = visible.single;
        expect(placed.box.width, greaterThan(0));
        expect(placed.box.height, greaterThan(0));
        expect(placed.box.height, lessThan(500));
        expect(placed.box.y, greaterThanOrEqualTo(section.margins.top - 0.01));
        expect(
          placed.box.y + placed.box.height,
          lessThanOrEqualTo(
            section.pageSize.height - section.margins.bottom + 0.01,
          ),
        );
        expect(
          placed.page.frames
              .where((box) => box.table != null)
              .any(
                (cell) =>
                    cell.x <= placed.box.x + 0.01 &&
                    cell.y <= placed.box.y + 0.01 &&
                    cell.x + cell.width >=
                        placed.box.x + placed.box.width - 0.01 &&
                    cell.y + cell.height >=
                        placed.box.y + placed.box.height - 0.01,
              ),
          isTrue,
          reason: 'The visible picture remains inside a visible cell slice',
        );
        expect((visual.width, visual.height), (80.0, 500.0));
        expect(visual.imageBytes, orderedEquals(bytes));
        final saved = WordDeserializer()
            .readBytes(WordSerializer().writeBytes(document))
            .visuals
            .single
            .visual;
        expect((saved.width, saved.height), (80.0, 500.0));
        expect(saved.imageBytes, orderedEquals(bytes));
        _expectTextOnce(laid, document);
      });
    }

    test('$mode nested note-cell image uses the physical page height', () {
      final bytes = PngBytes.studioCard(width: 32, height: 24);
      var document = _document([]);
      document.paragraphs.first.inlines.add(WmlRun(text: '1', noteRefId: 1));
      document.footnotes.add(
        WmlNote(
          id: 1,
          endnote: false,
          blocks: [
            _wrap(
              WmlVisual(
                visual: OfficeVisual(
                  kind: OfficeVisualKind.picture,
                  imageBytes: bytes,
                  width: 80,
                  height: 500,
                ),
              ),
              3,
            ),
          ],
        ),
      );
      if (reopen) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
      final note = document.footnotes.single;
      final source = WordTree.descendants(
        note.blocks,
      ).whereType<WmlVisual>().single.visual;
      final section = document.sections.single;
      final laid = WordLayoutEngine(font: null).layout(document);
      final pictures = laid.pages
          .expand((page) => page.frames)
          .where((box) => box.visual != null && box.isNoteContent)
          .toList();
      expect(pictures, hasLength(1));
      final picture = pictures.single;
      expect(picture.height, greaterThan(0));
      expect(picture.y, greaterThanOrEqualTo(section.margins.top - 0.01));
      expect(
        picture.y + picture.height,
        lessThanOrEqualTo(
          section.pageSize.height - section.margins.bottom + 0.01,
        ),
      );
      expect(picture.visual!.imageBytes, orderedEquals(bytes));
      expect((source.width, source.height), (80.0, 500.0));
      expect(source.imageBytes, orderedEquals(bytes));
      _expectTextOnce(laid, document);
    });

    for (final wrap in [PictureWrap.behind, PictureWrap.inFront]) {
      for (final last in [false, true]) {
        test(
          '$mode tall-row ${wrap.name} picture keeps absolute source placement ${last ? 'at final boundary' : 'after earlier flow'}',
          () {
            final imageBytes = PngBytes.studioCard(width: 32, height: 24);
            final source = WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                imageBytes: imageBytes,
                width: 80,
                height: 50,
                offsetX: 72,
                offsetY: 120,
                picture: PictureAdjust(wrap: wrap),
              ),
            );
            final blocks = <WmlBlock>[
              for (var index = 0; index < 40; index++)
                _paragraph('Flow ${index.toString().padLeft(2, '0')}'),
            ]..insert(last ? 40 : 24, source);
            var document = _document([
              WmlTable(
                grid: [260, 100],
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(blocks: blocks),
                      WmlTableCell(blocks: [_paragraph('Sibling')]),
                    ],
                  ),
                ],
              ),
            ]);
            if (reopen) {
              document = WordDeserializer().readBytes(
                WordSerializer().writeBytes(document),
              );
            }
            final table = document.sections.single.blocks
                .whereType<WmlTable>()
                .single;
            final visual = document.visuals.single.visual;
            final laid = WordLayoutEngine(font: null).layout(document);
            final visible = [
              for (final page in laid.pages)
                for (final box in page.frames)
                  if (identical(box.visual, visual)) (page: page, box: box),
            ];
            expect(visible, hasLength(1));
            final placed = visible.single;
            expect(placed.page.index, greaterThan(0));
            expect(placed.box.x, closeTo(72, 0.01));
            expect(placed.box.y, closeTo(120, 0.01));
            expect(placed.box.width, closeTo(80, 0.01));
            expect(placed.box.height, closeTo(50, 0.01));
            if (last) {
              expect(
                placed.page.index,
                laid.pages
                    .lastWhere(
                      (page) =>
                          page.frames.any((box) => identical(box.table, table)),
                    )
                    .index,
              );
            } else {
              final paragraphs = document.paragraphs.toList();
              final anchorIndex = paragraphs.indexWhere(
                (paragraph) => paragraph.text == 'Flow 24',
              );
              final anchorPage = laid.pages.singleWhere(
                (page) => page.lines.any(
                  (line) => line.paragraphIndex == anchorIndex,
                ),
              );
              expect(placed.page.index, anchorPage.index);
            }
            expect(visual.picture.wrap, wrap);
            expect((visual.offsetX, visual.offsetY), (72.0, 120.0));
            expect(visual.imageBytes, orderedEquals(imageBytes));
            _expectTextOnce(laid, document);
          },
        );
      }
    }
  }

  test(
    'an image with no remaining physical height reports the nesting bound',
    () {
      final visual = OfficeVisual(
        kind: OfficeVisualKind.picture,
        width: 80,
        height: 500,
      );
      final document = _document([
        _wrap(WmlVisual(visual: visual), 15, surroundingText: false),
      ]);
      expect(
        () => WordLayoutEngine(font: null).layout(document),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'explicit physical-page bound',
            contains('table nesting depth'),
          ),
        ),
      );
      expect((visual.width, visual.height), (80.0, 500.0));
    },
  );
}

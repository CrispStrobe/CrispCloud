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

List<LaidOutLine> _lines(
  WmlDocument document,
  LaidOutDocument layout,
  WmlParagraph paragraph,
) {
  final index = document.paragraphs.toList().indexOf(paragraph);
  expect(index, greaterThanOrEqualTo(0));
  return layout.pages
      .expand((page) => page.lines)
      .where((line) => line.paragraphIndex == index)
      .toList();
}

void _expectFullLayout(
  WmlDocument document,
  LaidOutDocument incremental, {
  required String step,
}) {
  final full = WordLayoutEngine(
    font: null,
  ).layout(document, updateFields: false);
  expect(
    wordLayoutFingerprint(incremental),
    wordLayoutFingerprint(full),
    reason: step,
  );
}

void main() {
  late bool savedIncremental;
  late bool savedVerification;
  setUp(() {
    savedIncremental = WordLayoutEngine.incrementalLayout;
    savedVerification = WordLayoutEngine.verifyIncrementalLayout;
    WordLayoutEngine.incrementalLayout = true;
    WordLayoutEngine.verifyIncrementalLayout = false;
    WordIncrementalLayoutStats.reset();
  });
  tearDown(() {
    WordLayoutEngine.incrementalLayout = savedIncremental;
    WordLayoutEngine.verifyIncrementalLayout = savedVerification;
    WordIncrementalLayoutStats.reset();
  });

  for (final addPicture in [false, true]) {
    final kind = addPicture ? 'frame' : 'line';
    test(
      'sequential edits retain page prefixes after fixed-height row $kind changes',
      () {
        final firstCellParagraph = _paragraph('Cell first');
        final cell = WmlTableCell(blocks: [firstCellParagraph]);
        final table = WmlTable(
          grid: [300],
          rows: [
            WmlTableRow(height: 100, cells: [cell]),
          ],
        );
        final following = [
          for (var index = 0; index < 8; index++)
            _paragraph('Following $index'),
        ];
        final document = WmlDocument(
          sections: [
            WmlSection(
              pageSize: const WmlPageSize(width: 500, height: 600),
              margins: const WmlPageMargins(
                top: 24,
                bottom: 24,
                left: 24,
                right: 24,
              ),
              blocks: [_paragraph('Before table'), table, ...following],
            ),
          ],
        );
        final engine = WordLayoutEngine(font: null);
        var layout = engine.layout(document, updateFields: false);
        expect(layout.pages, hasLength(1));
        expect(layout.supportsIncrementalReuse, isTrue);
        final originalLines = layout.pages.single.lines.length;
        final originalFrames = layout.pages.single.frames.length;
        final originalFollowingY = _lines(
          document,
          layout,
          following.first,
        ).single.y;

        // The row's minimum height absorbs the extra content. Equal flow y
        // therefore does not imply equal line/frame prefix lengths.
        final WmlBlock inserted = addPicture
            ? WmlVisual(
                visual: OfficeVisual(
                  kind: OfficeVisualKind.picture,
                  title: 'Small cell picture',
                  width: 20,
                  height: 20,
                ),
              )
            : _paragraph('Cell second');
        cell.blocks.add(inserted);
        layout = engine.layout(
          document,
          updateFields: false,
          reuse: layout,
          dirtyParagraphs: {firstCellParagraph},
        );
        expect(WordIncrementalLayoutStats.incremental, greaterThan(0));
        expect(layout.pages, hasLength(1));
        expect(
          _lines(document, layout, following.first).single.y,
          originalFollowingY,
          reason: 'The mutation must leave the row footprint unchanged',
        );
        expect(
          layout.pages.single.lines.length,
          originalLines + (addPicture ? 0 : 1),
        );
        expect(
          layout.pages.single.frames.length,
          originalFrames + (addPicture ? 1 : 0),
        );
        _expectFullLayout(document, layout, step: 'after adding row content');

        // This later edit resumes on the same partial page. Stale checkpoint
        // slice lengths from the old row would discard a line or picture.
        following[4].inlines
          ..clear()
          ..add(WmlRun(text: 'Changed following four'));
        layout = engine.layout(
          document,
          updateFields: false,
          reuse: layout,
          dirtyParagraphs: {following[4]},
        );
        _expectFullLayout(document, layout, step: 'after the later body edit');

        // Exercise the inverse count change and another reuse of its result.
        cell.blocks.remove(inserted);
        layout = engine.layout(
          document,
          updateFields: false,
          reuse: layout,
          dirtyParagraphs: {firstCellParagraph},
        );
        _expectFullLayout(document, layout, step: 'after removing row content');
        following[6].inlines
          ..clear()
          ..add(WmlRun(text: 'Changed following six'));
        layout = engine.layout(
          document,
          updateFields: false,
          reuse: layout,
          dirtyParagraphs: {following[6]},
        );
        _expectFullLayout(
          document,
          layout,
          step: 'after the second later body edit',
        );
      },
    );
  }
}

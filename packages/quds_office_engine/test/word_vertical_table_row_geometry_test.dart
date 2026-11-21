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

WmlTable _mergedTable({int rows = 6}) => WmlTable(
  grid: [80, 80],
  rows: [
    for (var row = 0; row < rows; row++)
      WmlTableRow(
        height: 70,
        cells: [
          WmlTableCell(
            gridSpan: 2,
            vMerge: row == 0 ? WmlVMerge.restart : WmlVMerge.cont,
            fillColor: 'FFEEDD',
            blocks: [_paragraph(row == 0 ? 'Origin' : '')],
          ),
        ],
      ),
  ],
);

WmlSection _section(List<WmlBlock> blocks, {double height = 240}) => WmlSection(
  blocks: blocks,
  pageSize: WmlPageSize(width: 240, height: height),
  margins: const WmlPageMargins(left: 20, right: 20, top: 20, bottom: 20),
);

Map<int, double> _physicalHeights(Iterable<LaidOutBox> boxes) {
  final heights = <int, double>{};
  for (final box in boxes) {
    final physical = box.tableRowGeometry;
    if (physical == null || physical.height <= 0) continue;
    heights.update(
      physical.row,
      (height) => height + physical.height,
      ifAbsent: () => physical.height,
    );
  }
  return heights;
}

void main() {
  for (final endnote in [false, true]) {
    test(
      '${endnote ? 'endnote' : 'footnote'} slicing retains covered physical rows',
      () {
        final anchor = _paragraph('Anchor');
        final document = WmlDocument(
          sections: [
            _section([anchor]),
          ],
        );
        final note = WordNotes.insert(
          document,
          anchor,
          endnote: endnote,
          text: ' Note',
        );
        note.blocks.add(_mergedTable());
        final laid = WordLayoutEngine(font: null).layout(document);
        final boxes = laid.pages
            .expand((page) => page.frames)
            .where(
              (box) =>
                  box.isNoteContent &&
                  box.table != null &&
                  box.kind == LaidOutBoxKind.tableCell,
            )
            .toList();
        expect(laid.pages, hasLength(greaterThan(1)));
        final heights = _physicalHeights(boxes);
        expect(heights.keys.toSet(), {0, 1, 2, 3, 4, 5});
        for (final height in heights.values) {
          expect(
            height,
            closeTo(70, .01),
            reason: 'A hidden continuation must survive slicing exactly once',
          );
        }
        expect(boxes.every((box) => box.height >= 0), isTrue);
        expect(
          boxes
              .where((box) => box.height > 0)
              .every((box) => box.tableRow == 0),
          isTrue,
        );
        expect(
          boxes.any(
            (box) => box.height == 0 && (box.tableRowGeometry?.height ?? 0) > 0,
          ),
          isTrue,
        );
        expect(
          boxes.any(
            (box) => box.height > 0 && box.tableRowGeometry?.height == 0,
          ),
          isTrue,
          reason: 'A later painted fragment does not invent the origin row',
        );
      },
    );
  }

  test(
    'tall-row slices retain original row identity and total physical height',
    () {
      WmlDocument document(double height) {
        final table = WmlTable(
          grid: [100],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  vMerge: WmlVMerge.restart,
                  blocks: [
                    for (var index = 0; index < 40; index++)
                      _paragraph('Line $index'),
                  ],
                ),
              ],
            ),
            WmlTableRow(
              cells: [
                WmlTableCell(vMerge: WmlVMerge.cont, blocks: [_paragraph('')]),
              ],
            ),
          ],
        );
        return WmlDocument(
          sections: [
            _section([table], height: height),
          ],
        );
      }

      final paged = WordLayoutEngine(font: null).layout(document(240));
      final unpaged = WordLayoutEngine(font: null).layout(document(100000));
      final pagedBoxes = paged.pages
          .expand((page) => page.frames)
          .where((box) => box.table != null);
      final unpagedBoxes = unpaged.pages
          .expand((page) => page.frames)
          .where((box) => box.table != null);
      final heights = _physicalHeights(pagedBoxes);
      final reference = _physicalHeights(unpagedBoxes);
      expect(paged.pages, hasLength(greaterThan(1)));
      expect(heights.keys.toSet(), reference.keys.toSet());
      for (final row in reference.keys) {
        expect(heights[row], closeTo(reference[row]!, .01));
      }
      expect(
        pagedBoxes
            .where((box) => box.height > 0)
            .every((box) => box.tableRow == 0),
        isTrue,
      );
      for (final page in paged.pages) {
        for (final box in page.frames.where(
          (box) => box.tableRowGeometry != null,
        )) {
          final physical = box.tableRowGeometry!;
          expect(physical.row, isIn([0, 1]));
          expect(physical.y, greaterThanOrEqualTo(20));
          expect(physical.y + physical.height, lessThanOrEqualTo(220.01));
        }
      }
    },
  );
}

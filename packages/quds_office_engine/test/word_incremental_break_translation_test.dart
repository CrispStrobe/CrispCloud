import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]);

void main() {
  for (final type in <WmlBreakType>[WmlBreakType.page, WmlBreakType.column]) {
    for (final columns in <int>[1, 2]) {
      test('inline ${type.name} break after empty paragraphs '
          'matches full layout with $columns columns', () {
        final changed = _paragraph('');
        final target = WmlParagraph(
          inlines: <WmlInline>[
            WmlBreak(type),
            WmlRun(text: 'Break target'),
          ],
        );
        final document = WmlDocument(
          sections: <WmlSection>[
            WmlSection(
              columnCount: columns,
              blocks: <WmlBlock>[
                changed,
                _paragraph(''),
                _paragraph(''),
                target,
                _paragraph('Following one'),
                _paragraph('Following two'),
              ],
            ),
          ],
        );
        final engine = WordLayoutEngine(font: null);
        var layout = engine.layout(document, updateFields: false);
        for (final text in <String>['x', '', 'More text before the break.']) {
          // A page break on the initially empty page does nothing. Adding
          // content makes it advance, even though the break's paragraph did
          // not change and remains outside the widened dirty range.
          changed.inlines.whereType<WmlRun>().single.text = text;
          WordIncrementalLayoutStats.reset();
          layout = engine.layout(
            document,
            updateFields: false,
            reuse: layout,
            dirtyParagraphs: Set<WmlParagraph>.identity()..add(changed),
          );
          final full = WordLayoutEngine(
            font: null,
          ).layout(document, updateFields: false);
          expect(
            wordLayoutFingerprint(layout),
            wordLayoutFingerprint(full),
            reason: 'edit to "$text"',
          );
          expect(WordIncrementalLayoutStats.incremental, 1);
          for (final page in layout.pages) {
            for (final line in page.lines) {
              expect(line.pageIndex, page.index);
            }
          }
        }
      });
    }
  }
}

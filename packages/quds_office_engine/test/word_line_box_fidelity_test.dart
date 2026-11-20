import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRun run(String text, [int size = 12]) => WmlRun(
  text: text,
  properties: WmlRunProps(asciiFont: 'Arial', fontSizeHalfPoints: size * 2),
);
WmlParagraph paragraph(String text, {double before = 0, double after = 0}) =>
    WmlParagraph(
      properties: WmlParagraphProps(
        lineSpacing: 1,
        spacingBefore: before,
        spacingAfter: after,
      ),
      inlines: [run(text)],
    );
WmlDocument document(List<WmlBlock> blocks) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 612, height: 792),
      margins: const WmlPageMargins(top: 72, bottom: 72, left: 72, right: 72),
      blocks: blocks,
    ),
  ],
);

void main() {
  final sans = SfntFont.parse(
    File(
      '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
    ).readAsBytesSync(),
  );
  WordLayoutEngine engine() => WordLayoutEngine(
    font: null,
    measureFont: (_, size, _) => FontMetrics(font: sans, fontSizePoints: size),
  );

  test('each line uses its own size after a larger opening run', () {
    final p = paragraph('');
    p.inlines = [
      run('Large opening\n', 24),
      run('Small second\n', 11),
      run('Small third', 11),
    ];
    final lines = engine().layout(document([p])).pages.single.lines;
    expect(lines, hasLength(3));
    expect(lines[0].height, closeTo(27.59765625, .001));
    expect(lines[1].height, closeTo(12.64892578125, .001));
    expect(lines[2].y - lines[1].y, closeTo(12.64892578125, .001));
    expect(lines[1].glyphs.first.y - lines[1].y, lessThan(11));
  });

  test(
    'mixed run sizes share the fixed-height baseline without shifting small text',
    () {
      final p = paragraph('');
      p.properties
        ..lineSpacingRule = WmlLineSpacingRule.exact
        ..lineSpacing = 18;
      p.inlines = [run('Small ', 8), run('LARGE ', 24), run('small', 11)];
      final line = engine().layout(document([p])).pages.single.lines.single;
      expect(line.glyphs.map((g) => g.y).toSet(), hasLength(1));
      expect(line.glyphs.first.y, closeTo(86.53, .25));
    },
  );

  test(
    'adjacent spacing uses the greater value and preserves model properties',
    () {
      final first = paragraph('First', after: 12);
      final second = paragraph('Second', before: 6, after: 4);
      final third = paragraph('Third', before: 10);
      final doc = document([first, second, third]);
      final lines = engine().layout(doc).pages.single.lines;
      expect(lines[1].y - lines[0].y, closeTo(13.798828125 + 12, .001));
      expect(lines[2].y - lines[1].y, closeTo(13.798828125 + 10, .001));
      expect(first.properties.spacingAfter, 12);
      expect(second.properties.spacingBefore, 6);
      final copy = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      expect(copy.paragraphs.elementAt(1).properties.spacingBefore, 6);
      expect(copy.paragraphs.elementAt(1).properties.spacingAfter, 4);
    },
  );

  test('paragraph gaps do not collapse across an explicit page break', () {
    final first = paragraph('First', after: 12);
    final second = paragraph('Second', before: 6)
      ..properties.pageBreakBefore = true;
    final laid = engine().layout(document([first, second]));
    expect(laid.pages, hasLength(2));
    expect(laid.pages[1].lines.single.y, 78);
  });

  test(
    'center and right tabs position their following fields at real stops',
    () {
      final p = paragraph('Left\tCenter\tRight');
      p.properties.tabs.addAll([
        const WmlTabStop(position: 216, alignment: WmlTabAlignment.center),
        const WmlTabStop(position: 468, alignment: WmlTabAlignment.right),
      ]);
      // Scalar 6pt characters keep the independent expected anchors simple.
      final line = WordLayoutEngine(
        font: null,
      ).layout(document([p])).pages.single.lines.single;
      final center = line.glyphs.firstWhere((g) => g.glyph.logicalIndex == 5);
      final right = line.glyphs.firstWhere((g) => g.glyph.logicalIndex == 12);
      expect(center.x, closeTo(72 + 216 - 18, .001));
      expect(right.x, closeTo(72 + 468 - 30, .001));
      expect(line.glyphs.last.x + line.glyphs.last.advance, closeTo(540, .001));
      expect(p.properties.tabs[0].position, 216);
    },
  );

  test(
    'default tabs advance to the next half-inch grid rather than add 36pt',
    () {
      final line = WordLayoutEngine(
        font: null,
      ).layout(document([paragraph('ABC\tD')])).pages.single.lines.single;
      expect(line.glyphs.last.x, closeTo(108, .001));
      expect(line.glyphs[3].advance, closeTo(18, .001));
    },
  );

  test('decimal-point tabs align the decimal rather than the field end', () {
    final p = paragraph('A\t123.45');
    p.properties.tabs.add(
      const WmlTabStop(position: 216, alignment: WmlTabAlignment.decimal),
    );
    final line = WordLayoutEngine(
      font: null,
    ).layout(document([p])).pages.single.lines.single;
    final point = line.glyphs.firstWhere((g) => g.glyph.codePoint == 46);
    expect(point.x, closeTo(288, .001));
  });
}

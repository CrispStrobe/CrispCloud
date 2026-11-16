import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _doc(String text, {bool framed = false, double width = 12}) =>
    WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            if (framed)
              WmlFrame(
                x: 0,
                y: 0,
                width: 100,
                height: 400,
                anchor: WmlFrameAnchor.margin,
                wrap: WmlFrameWrap.square,
                hasTextBox: false,
              ),
            WmlParagraph(inlines: [WmlRun(text: text)]),
          ],
          pageSize: WmlPageSize(
            width: width + 20 + (framed ? 100 : 0),
            height: 500,
          ),
          margins: const WmlPageMargins(
            left: 10,
            right: 10,
            top: 10,
            bottom: 10,
          ),
        ),
      ],
    );

List<WordMeasuredCluster>? _measure(
  String text,
  String complete,
  bool invalid,
) => text == complete
    ? [
        for (final c in GraphemeClusters.segment(text))
          WordMeasuredCluster(start: c.start, end: c.end, advance: 1),
      ]
    : invalid
    ? const [WordMeasuredCluster(start: 0, end: 1, advance: 900)]
    : null;

void main() {
  for (final framed in [false, true]) {
    for (final invalid in [false, true]) {
      test(
        '${invalid ? 'invalid' : 'null'} line fragment restores scalar metrics (${framed ? 'prepared' : 'batch'})',
        () {
          const text = 'AA BB CC DD EE';
          final lines =
              WordLayoutEngine(
                    font: null,
                    measure: (_, _, _) => 5,
                    measureRun: (source, _, _, _) =>
                        _measure(source, text, invalid),
                  )
                  .layout(_doc(text, framed: framed))
                  .pages
                  .expand((p) => p.lines)
                  .toList();
          expect(lines.map((l) => l.text), ['AA', 'BB', 'CC', 'DD', 'EE']);
          expect(lines.map((l) => l.width), everyElement(10));
          expect(
            lines.expand((l) => l.glyphs).map((g) => g.advance),
            everyElement(5),
          );
          expect(
            lines
                .expand((l) => l.glyphs)
                .map((g) => g.glyph.logicalIndex)
                .toList()
              ..sort(),
            [0, 1, 3, 4, 6, 7, 9, 10, 12, 13],
          );
        },
      );
    }
  }
  test('declined fragments restore real-font metrics without changing IDs', () {
    const text = 'AA BB CC DD EE';
    final font = SfntFont.parse(
      File(
        '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
      ).readAsBytesSync(),
    );
    final baseline = WordLayoutEngine(
      font: font,
    ).layout(_doc(text, width: 500)).pages.single.lines.single;
    final baselineGlyphs = {
      for (final g in baseline.glyphs) g.glyph.logicalIndex: g,
    };
    final lines = WordLayoutEngine(
      font: font,
      measureRun: (source, _, _, _) => _measure(source, text, false),
    ).layout(_doc(text)).pages.expand((p) => p.lines).toList();
    for (final glyph in lines.expand((l) => l.glyphs)) {
      final expected = baselineGlyphs[glyph.glyph.logicalIndex]!;
      expect(glyph.advance, closeTo(expected.advance, .00001));
      expect(glyph.glyph.glyphId, expected.glyph.glyphId);
      expect(glyph.glyph.codePoint, expected.glyph.codePoint);
    }
    expect(lines.map((l) => l.text), ['AA', 'BB', 'CC', 'DD', 'EE']);
  });
  test(
    'declined Arabic fragments restore zero-width lam-alef continuation',
    () {
      const text = 'لا لا لا لا لا';
      final lines = WordLayoutEngine(
        font: null,
        measure: (_, _, _) => 5,
        measureRun: (source, _, _, _) => _measure(source, text, false),
      ).layout(_doc(text)).pages.expand((p) => p.lines).toList();
      final glyphs = lines.expand((l) => l.glyphs).toList();
      final ghosts = glyphs.where((g) => g.glyph.codePoint == 0).toList();
      expect(ghosts, hasLength(5));
      expect(ghosts.map((g) => g.advance), everyElement(0));
      expect(
        glyphs
            .where((g) => !g.glyph.isSpace && g.glyph.codePoint != 0)
            .map((g) => g.advance),
        everyElement(5),
      );
      expect(lines.map((l) => l.text), ['لا', 'لا', 'لا', 'لا', 'لا']);
    },
  );
}

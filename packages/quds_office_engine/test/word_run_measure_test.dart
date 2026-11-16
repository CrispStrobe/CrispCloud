import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

List<WordMeasuredCluster> _measure(String text, double width) => [
  for (final cluster in GraphemeClusters.segment(text))
    WordMeasuredCluster(
      start: cluster.start,
      end: cluster.end,
      advance: cluster.text == ' ' ? width / 2 : width,
    ),
];

WmlDocument _doc(List<WmlRun> runs, {double width = 200}) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [WmlParagraph(inlines: runs)],
      pageSize: WmlPageSize(width: width + 20, height: 500),
      margins: const WmlPageMargins(left: 10, right: 10, top: 10, bottom: 10),
    ),
  ],
);

void main() {
  test('contextual advances affect wrapping before paint fitting', () {
    final doc = _doc([WmlRun(text: 'AV AV')], width: 23);
    final scalar = WordLayoutEngine(
      font: null,
      measure: (_, _, _) => 10,
    ).layout(doc);
    final inputs = <String>[];
    final shaped = WordLayoutEngine(
      font: null,
      measure: (_, _, _) => 10,
      measureRun: (text, size, props, level) {
        inputs.add(text);
        return _measure(text, 4);
      },
    ).layout(doc);
    expect(scalar.pages.single.lines, hasLength(2));
    expect(shaped.pages.single.lines, hasLength(1));
    expect(shaped.pages.single.lines.single.width, 18);
    expect(shaped.pages.single.lines.single.text, 'AV AV');
    expect(inputs, isNotEmpty);
    expect(inputs.toSet(), {'AV AV'});
  });

  test('host metrics override font advances without changing glyph IDs', () {
    final font = SfntFont.parse(
      File(
        '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
      ).readAsBytesSync(),
    );
    final line = WordLayoutEngine(
      font: font,
      measureRun: (text, _, _, _) => _measure(text, 3),
    ).layout(_doc([WmlRun(text: 'AV')])).pages.single.lines.single;
    expect(line.width, 6);
    expect(line.glyphs.map((g) => g.glyph.glyphId), [
      font.glyphIdFor(65),
      font.glyphIdFor(86),
    ]);
  });

  test('equal adjacent styles form one contextual run', () {
    final calls = <String>[];
    WordLayoutEngine(
      font: null,
      measureRun: (text, _, _, _) {
        calls.add(text);
        return _measure(text, 5);
      },
    ).layout(_doc([WmlRun(text: 'A'), WmlRun(text: 'V')]));
    expect(calls, isNotEmpty);
    expect(calls.toSet(), {'AV'});
  });

  test('paint style changes and tabs keep independent metrics', () {
    final calls = <(String, double, bool)>[];
    WordLayoutEngine(
      font: null,
      measureRun: (text, size, props, _) {
        calls.add((text, size, props.bold));
        return _measure(text, 4);
      },
    ).layout(
      _doc([
        WmlRun(text: 'AV\t'),
        WmlRun(
          text: 'To',
          properties: WmlRunProps(bold: true, fontSizeHalfPoints: 40),
        ),
      ]),
    );
    expect(calls, isNotEmpty);
    expect(calls.toSet(), {('AV', 11.0, false), ('To', 20.0, true)});
  });

  test('combining and supplementary text retains source ownership', () {
    const text = 'e\u0301\u{1f469}\u200d\u{1f4bb}';
    final line = WordLayoutEngine(
      font: null,
      measureRun: (source, _, _, _) => _measure(source, 8),
    ).layout(_doc([WmlRun(text: text)])).pages.single.lines.single;
    expect(line.width, 16);
    expect(line.sourceText, text);
    expect(line.text, text);
    expect(
      line.glyphs.map((g) => g.glyph.logicalIndex),
      // The invisible ZWJ stays in source text without a separate glyph.
      containsAll([0, 1, 2, 5]),
    );
    expect(line.glyphs.where((g) => g.advance > 0), hasLength(2));
  });

  test('Arabic host input uses original letters and paragraph direction', () {
    final calls = <(String, int)>[];
    final doc = _doc([WmlRun(text: 'سَلَام')]);
    doc.paragraphs.single.properties.rightToLeft = true;
    final line = WordLayoutEngine(
      font: null,
      measureRun: (text, _, _, level) {
        calls.add((text, level));
        return _measure(text, 6);
      },
    ).layout(doc).pages.single.lines.single;
    expect(calls, isNotEmpty);
    expect(calls.toSet(), {('سَلَام', 1)});
    expect(line.width, 24);
    expect(line.sourceText, 'سَلَام');
  });

  test('small caps measure presented text at its scaled size', () {
    final calls = <(String, double)>[];
    final line =
        WordLayoutEngine(
              font: null,
              measureRun: (text, size, _, _) {
                calls.add((text, size));
                return _measure(text, 5);
              },
            )
            .layout(
              _doc([
                WmlRun(
                  text: 'av',
                  properties: WmlRunProps(
                    smallCaps: true,
                    fontSizeHalfPoints: 40,
                  ),
                ),
              ]),
            )
            .pages
            .single
            .lines
            .single;
    expect(calls, isNotEmpty);
    expect(calls.map((call) => call.$1).toSet(), {'A', 'V'});
    expect(calls.every((call) => call.$2 < 20), isTrue);
    expect(line.sourceText, 'av');
    expect(line.width, 10);
  });

  test('null result preserves legacy scalar metrics', () {
    final line = WordLayoutEngine(
      font: null,
      measure: (_, _, _) => 10,
      measureRun: (_, _, _, _) => null,
    ).layout(_doc([WmlRun(text: 'AV')])).pages.single.lines.single;
    expect(line.width, 20);
  });

  for (final alignment in [
    WmlJustification.left,
    WmlJustification.center,
    WmlJustification.right,
  ]) {
    test('$alignment lines retain natural width and correct alignment', () {
      final doc = _doc([WmlRun(text: 'AV AV')], width: 18);
      doc.paragraphs.single.properties.justification = alignment;
      final lines = WordLayoutEngine(
        font: null,
        measureRun: (text, _, _, _) => _measure(text, 5),
      ).layout(doc).pages.single.lines;
      expect(lines, hasLength(2));
      for (final line in lines) {
        expect(line.width, 10);
        expect(line.justificationRatio, 0);
        expect(line.x, switch (alignment) {
          WmlJustification.right => 18,
          WmlJustification.center => 14,
          _ => 10,
        });
      }
    });
  }

  final invalid = <String, List<WordMeasuredCluster>>{
    'incomplete': [const WordMeasuredCluster(start: 0, end: 1, advance: 3)],
    'negative': [
      const WordMeasuredCluster(start: 0, end: 1, advance: -3),
      const WordMeasuredCluster(start: 1, end: 2, advance: 3),
    ],
    'nonfinite': [
      const WordMeasuredCluster(start: 0, end: 1, advance: double.nan),
      const WordMeasuredCluster(start: 1, end: 2, advance: 3),
    ],
    'overlap': [
      const WordMeasuredCluster(start: 0, end: 1, advance: 3),
      const WordMeasuredCluster(start: 0, end: 2, advance: 3),
    ],
    'combined graphemes': [
      const WordMeasuredCluster(start: 0, end: 2, advance: 3),
    ],
  };
  for (final entry in invalid.entries) {
    test('${entry.key} result preserves the complete fallback run', () {
      final line = WordLayoutEngine(
        font: null,
        measure: (_, _, _) => 10,
        measureRun: (_, _, _, _) => entry.value,
      ).layout(_doc([WmlRun(text: 'AV')])).pages.single.lines.single;
      expect(line.width, 20);
    });
  }

  test('a range cannot split a surrogate pair or extended grapheme', () {
    for (final text in ['e\u0301', '\u{1f600}']) {
      final line = WordLayoutEngine(
        font: null,
        measure: (_, _, _) => 10,
        measureRun: (_, _, _, _) => const [
          WordMeasuredCluster(start: 0, end: 1, advance: 2),
          WordMeasuredCluster(start: 1, end: 2, advance: 2),
        ],
      ).layout(_doc([WmlRun(text: text)])).pages.single.lines.single;
      expect(line.width, text.runes.length * 10);
    }
  });
}

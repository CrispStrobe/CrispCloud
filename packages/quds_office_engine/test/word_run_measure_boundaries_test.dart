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

WmlDocument _document(List<WmlBlock> blocks, {double height = 500}) =>
    WmlDocument(
      sections: [
        WmlSection(
          blocks: blocks,
          pageSize: WmlPageSize(width: 240, height: height),
          margins: const WmlPageMargins(
            left: 10,
            right: 10,
            top: 10,
            bottom: 10,
          ),
        ),
      ],
    );

List<WordMeasuredCluster> _uniformMetrics(String text, double advance) => [
  for (final cluster in GraphemeClusters.segment(text))
    WordMeasuredCluster(
      start: cluster.start,
      end: cluster.end,
      advance: advance,
    ),
];

void main() {
  test('lam-alef continuation keeps its source complex-script font', () {
    final calls = <(String, int)>[];
    final properties = WmlRunProps(
      asciiFont: 'Latin face',
      csFont: 'Arabic face',
    );
    final paragraph = WmlParagraph(
      inlines: [WmlRun(text: 'لا', properties: properties)],
    );
    final line = WordLayoutEngine(
      font: null,
      measure: (_, _, _) => 20,
      measureRun: (text, _, _, level) {
        calls.add((text, level));
        return text == 'لا'
            ? const [
                WordMeasuredCluster(start: 0, end: 1, advance: 7),
                WordMeasuredCluster(start: 1, end: 2, advance: 0),
              ]
            : null;
      },
    ).layout(_document([paragraph])).pages.single.lines.single;

    expect(calls, isNotEmpty);
    expect(calls.toSet(), {('لا', 1)});
    expect(line.width, 7);
    expect(line.text, 'لا');
    expect(line.glyphs.map((glyph) => glyph.fontFamily).toSet(), {
      'Arabic face',
    });
    expect(line.glyphs.map((glyph) => glyph.glyph.logicalIndex).toSet(), {
      0,
      1,
    });
    final continuation = line.glyphs.singleWhere(
      (glyph) => glyph.glyph.codePoint == 0,
    );
    expect(continuation.glyph.logicalIndex, 1);
    expect(continuation.advance, 0);
  });

  test(
    'invisible source controls retain offsets without consuming advance',
    () {
      const source = 'A\u200bV';
      final calls = <String>[];
      final line = WordLayoutEngine(
        font: null,
        measure: (_, _, _) => 20,
        measureRun: (text, _, _, _) {
          calls.add(text);
          return const [
            WordMeasuredCluster(start: 0, end: 1, advance: 4),
            WordMeasuredCluster(start: 1, end: 2, advance: 0),
            WordMeasuredCluster(start: 2, end: 3, advance: 3),
          ];
        },
      ).layout(_document([_paragraph(source)])).pages.single.lines.single;

      expect(calls, isNotEmpty);
      expect(calls.toSet(), {source});
      expect(line.width, 7);
      expect(line.sourceText, source);
      expect(line.text, source);
      expect(line.glyphs.map((glyph) => glyph.glyph.logicalIndex), [0, 2]);
      expect(line.glyphs.map((glyph) => glyph.advance), [4, 3]);
    },
  );

  test('an advance on an absent control rejects the whole measured run', () {
    final line = WordLayoutEngine(
      font: null,
      measure: (_, _, _) => 7,
      measureRun: (text, _, _, _) => _uniformMetrics(text, 2),
    ).layout(_document([_paragraph('A\u200bV')])).pages.single.lines.single;

    expect(line.width, 14);
    expect(line.glyphs.map((glyph) => glyph.advance), [7, 7]);
    expect(line.text, 'A\u200bV');
  });

  test('generated note labels and nested note cells inherit host metrics', () {
    final nestedParagraph = _paragraph('AVAV');
    final inner = WmlTable(
      grid: [70],
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: [nestedParagraph]),
          ],
        ),
      ],
    );
    final outer = WmlTable(
      grid: [100],
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: [inner]),
          ],
        ),
      ],
    );
    final reference = WmlParagraph(
      inlines: [
        WmlRun(
          text: '42',
          noteRefId: 42,
          properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
        ),
      ],
    );
    final document = _document([reference]);
    document.footnotes.add(
      WmlNote(id: 42, endnote: false, addReference: false, blocks: [outer]),
    );
    final calls = <String>[];
    final layout = WordLayoutEngine(
      font: null,
      measure: (_, _, _) => 20,
      measureRun: (text, _, _, _) {
        calls.add(text);
        return _uniformMetrics(text, 2);
      },
    ).layout(document);

    final body = layout.pages.expand((page) => page.lines).single;
    expect(body.sourceText, '42');
    expect(body.text, '1');
    expect(body.width, 2);
    expect(body.glyphs.single.displayText, '1');
    expect(body.glyphs.single.logicalEnd, 2);
    final noteLines = layout.pages
        .expand((page) => page.notes)
        .where((line) => identical(line.sourceParagraph, nestedParagraph))
        .toList();
    expect(noteLines, hasLength(1));
    expect(noteLines.single.text, 'AVAV');
    expect(noteLines.single.width, 8);
    expect(
      noteLines.single.glyphs.every((glyph) => glyph.advance == 2),
      isTrue,
    );
    expect(calls, containsAll(['1', 'AVAV']));
    expect(reference.text, '42');
    expect(nestedParagraph.text, 'AVAV');
  });

  test('tall row continuation preserves metrics on every physical page', () {
    final paragraphs = [
      for (var index = 0; index < 30; index++) _paragraph('AV'),
    ];
    final table = WmlTable(
      grid: [100],
      rows: [
        WmlTableRow(cells: [WmlTableCell(blocks: paragraphs)]),
      ],
    );
    final layout = WordLayoutEngine(
      font: null,
      measure: (_, _, _) => 20,
      measureRun: (text, _, _, _) => _uniformMetrics(text, 2),
    ).layout(_document([table], height: 180));

    expect(layout.pages.length, greaterThan(1));
    final lines = layout.pages.expand((page) => page.lines).toList();
    expect(lines, hasLength(paragraphs.length));
    for (final paragraph in paragraphs) {
      final line = lines.singleWhere(
        (candidate) => identical(candidate.sourceParagraph, paragraph),
      );
      expect(line.text, 'AV');
      expect(line.width, 4);
      expect(line.glyphs.map((glyph) => glyph.advance), [2, 2]);
    }
  });
}

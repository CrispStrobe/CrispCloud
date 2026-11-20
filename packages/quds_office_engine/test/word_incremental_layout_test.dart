// Engine-level equivalence of incremental relayout: after direct model edits
// declared through `dirtyParagraphs`, the result equals a fresh engine's full
// layout (wordLayoutFingerprint). The editor package's
// word_incremental_layout_equivalence_test.dart covers real edit paths.
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _p(String text, {WmlRunProps? props}) => WmlParagraph(
  inlines: <WmlInline>[WmlRun(text: text, properties: props ?? WmlRunProps())],
);

String _text(int i) => switch (i % 3) {
  0 =>
    'Die Gemeinde hat einen neuen Haushaltsplan beschlossen, der die '
        'Sanierung der Schulen vorsieht ($i).',
  1 => 'Short line $i.',
  _ =>
    'The committee reviewed the proposal and agreed that the timeline is '
            'realistic, provided that the funding arrives in time ($i). ' *
        2,
};

WmlTable _table(int rows) => WmlTable(
  rows: <WmlTableRow>[
    for (int r = 0; r < rows; r++)
      WmlTableRow(
        cells: <WmlTableCell>[
          for (int c = 0; c < 2; c++)
            WmlTableCell(blocks: <WmlBlock>[_p('Cell $r/$c ${_text(r)}')]),
        ],
      ),
  ],
);

WmlDocument _document() => WmlDocument(
  sections: <WmlSection>[
    WmlSection(
      blocks: <WmlBlock>[
        for (int i = 0; i < 60; i++) _p(_text(i)),
        _table(20),
        for (int i = 0; i < 20; i++) _p(_text(i + 1)),
      ],
      footer: <WmlParagraph>[_p('Page ')..properties.pageNumberField = true],
    ),
    WmlSection(
      blocks: <WmlBlock>[for (int i = 0; i < 40; i++) _p(_text(i))],
      columnCount: 2,
      breakKind: WmlSectionBreakKind.continuous,
    ),
    WmlSection(
      blocks: <WmlBlock>[for (int i = 0; i < 20; i++) _p(_text(i + 2))],
      breakKind: WmlSectionBreakKind.oddPage,
    ),
  ],
);

void main() {
  late WmlDocument document;
  late WordLayoutEngine engine;
  late LaidOutDocument laid;

  setUp(() {
    WordIncrementalLayoutStats.reset();
    document = _document();
    engine = WordLayoutEngine(font: null);
    laid = engine.layout(document, updateFields: false);
  });

  void relayout(Iterable<WmlParagraph> dirty) {
    laid = engine.layout(
      document,
      updateFields: false,
      reuse: laid,
      dirtyParagraphs: Set<WmlParagraph>.identity()..addAll(dirty),
    );
    final String full = wordLayoutFingerprint(
      WordLayoutEngine(font: null).layout(document, updateFields: false),
    );
    expect(wordLayoutFingerprint(laid), full);
  }

  WmlRun runOf(WmlParagraph p) => p.inlines.whereType<WmlRun>().first;

  test('typing converges after the edited paragraph', () {
    final WmlParagraph p = document.sections[0].blocks[10] as WmlParagraph;
    for (final String ch in 'abc'.split('')) {
      runOf(p).text += ch;
      relayout(<WmlParagraph>[p]);
    }
    expect(WordIncrementalLayoutStats.incremental, 3);
    expect(WordIncrementalLayoutStats.converged, 3);
    expect(WordIncrementalLayoutStats.blocksLaidOut, lessThan(15));
  });

  test('growing and shrinking a paragraph shifts pages both ways', () {
    final WmlParagraph p = document.sections[0].blocks[5] as WmlParagraph;
    final String before = runOf(p).text;
    runOf(p).text = '$before ${'lange Zeile ' * 120}';
    relayout(<WmlParagraph>[p]);
    runOf(p).text = before;
    relayout(<WmlParagraph>[p]);
    expect(WordIncrementalLayoutStats.incremental, 2);
    expect(WordIncrementalLayoutStats.breaksReused, greaterThan(100));
  });

  test('inserting and removing paragraphs renumbers reused lines', () {
    final List<WmlBlock> blocks = document.sections[0].blocks;
    final WmlParagraph inserted = _p('Inserted paragraph');
    blocks.insert(20, inserted);
    relayout(<WmlParagraph>[inserted]);
    blocks.remove(inserted);
    relayout(const <WmlParagraph>[]);
    final WmlParagraph empty = _p('');
    blocks.insert(3, empty);
    relayout(<WmlParagraph>[empty]);
    runOf(empty).text = 'x';
    relayout(<WmlParagraph>[empty]);
  });

  test('edits in a table cell, in columns and in a later section', () {
    final WmlTable table = document.sections[0].blocks[60] as WmlTable;
    final WmlParagraph cell =
        table.rows[3].cells[1].blocks.first as WmlParagraph;
    runOf(cell).text += ' mehr Text in der Zelle' * 6;
    relayout(<WmlParagraph>[cell]);
    final WmlParagraph column = document.sections[1].blocks[7] as WmlParagraph;
    runOf(column).text += ' Spalte' * 30;
    relayout(<WmlParagraph>[column]);
    final WmlParagraph last = document.sections[2].blocks[3] as WmlParagraph;
    runOf(last).text = 'kurz';
    relayout(<WmlParagraph>[last]);
  });

  test('property changes inside the declared paragraphs', () {
    final WmlParagraph p = document.sections[0].blocks[30] as WmlParagraph;
    p.properties.spacingAfter = 30;
    relayout(<WmlParagraph>[p]);
    runOf(p).properties.fontSizeHalfPoints = 40;
    relayout(<WmlParagraph>[p]);
    p.properties.pageBreakBefore = true;
    relayout(<WmlParagraph>[p]);
  });

  test('missing state, footnotes and the switch fall back', () {
    final WmlParagraph p = document.sections[0].blocks[1] as WmlParagraph;
    laid.discardIncrementalState();
    runOf(p).text += 'x';
    relayout(<WmlParagraph>[p]);
    expect(WordIncrementalLayoutStats.fallbacks, 1);
    WordLayoutEngine.incrementalLayout = false;
    addTearDown(() => WordLayoutEngine.incrementalLayout = true);
    runOf(p).text += 'y';
    relayout(<WmlParagraph>[p]);
    expect(WordIncrementalLayoutStats.incremental, 0);
  });
}

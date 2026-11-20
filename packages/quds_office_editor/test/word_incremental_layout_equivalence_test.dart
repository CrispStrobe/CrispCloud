// Incremental Word relayout must equal a fresh full layout exactly.
//
// For a corpus of repository fixtures and synthetic documents (mixed
// German/English/Arabic, tables, images, lists, headings with a TOC,
// columns, section breaks, headers/footers with page numbers, line numbers,
// footnotes) this applies scripted edits through the controller's real edit
// paths — typing, Enter, Backspace/Delete across paragraph joins, deleting
// selections across paragraphs, plain paste, run formatting, undo — and after
// every local edit compares the controller's layout with a fresh engine's
// full layout of the same model (wordLayoutFingerprint: every line box,
// glyph position, page assignment, box and chrome line).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/editor_word/word_run_metrics.dart';

/// The controller's default engine, built afresh (no shared layout state).
WordLayoutEngine _freshEngine(WordEditorController c) {
  final String? theme = c.config.theme.fontFamily;
  return WordLayoutEngine(
    font: null,
    measureFont: (codePoint, sizePoints, props) => OfficeHostFonts.wordMetrics(
      codePoint,
      sizePoints,
      props,
      themeFamily: theme,
    ),
    measureRun: (text, sizePoints, props, bidiLevel) => WordRunMetrics.measure(
      text,
      sizePoints,
      props,
      bidiLevel,
      respectKerningThreshold: true,
      themeFamily: theme,
    ),
    measure: (codePoint, sizePoints, props) => PaintRunText.advanceOf(
      codePoint,
      sizePoints,
      props,
      themeFamily: theme,
    ),
  );
}

final class _Run {
  int checks = 0;
  int steps = 0;
  final List<String> history = <String>[];
  final List<String> modelErrors = <String>[];
}

final class _StopDocument implements Exception {
  const _StopDocument();
}

void _expectEquivalent(WordEditorController c, String step, _Run run) {
  run.checks++;
  final String incremental = wordLayoutFingerprint(c.documentLaidOut);
  final String full = wordLayoutFingerprint(
    _freshEngine(c).layout(c.document, updateFields: false),
  );
  if (incremental == full) return;
  final List<String> a = incremental.split('\n');
  final List<String> b = full.split('\n');
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  final List<WmlParagraph> paras = _paras(c);
  final String model = <String>[
    for (int i = 0; i < paras.length; i++)
      '  ¶$i ${paras[i].properties.justification.name} '
          'rtl=${paras[i].properties.rightToLeft} "${paras[i].text}"',
  ].join('\n');
  fail(
    'steps: ${run.history.join(' → ')}\nmodel:\n$model\n'
    '$step: incremental layout differs from a full layout at fingerprint '
    'line $i of ${b.length}\n'
    '  incremental: ${i < a.length ? a[i] : '<end>'}\n'
    '  full:        ${i < b.length ? b[i] : '<end>'}',
  );
}

void _at(WordEditorController c, int paragraph, int offset) {
  c.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..collapseSelection();
}

void _select(WordEditorController c, int p0, int o0, int p1, int o1) {
  c.caret
    ..selectionAnchorParagraph = p0
    ..selectionAnchor = o0
    ..paragraphIndex = p1
    ..logicalIndex = o1;
}

List<WmlParagraph> _paras(WordEditorController c) =>
    c.document.paragraphs.toList();

const String _long =
    ' Zusätzlich wurde beschlossen, die Arbeiten an der Brücke vorzuziehen, '
    'because the committee expects the funding to arrive earlier than planned, '
    'وقد وافقت اللجنة على ذلك بالإجماع بعد نقاش طويل حول التكاليف والجدول الزمني '
    'und die Bürgerinnen und Bürger rechtzeitig zu informieren.';

/// Runs the edit script around body paragraph [p]; every local edit is
/// compared with a full layout.
Future<void> _script(
  WordEditorController c,
  int p,
  String label,
  _Run run,
) async {
  Future<void> step(
    String name,
    void Function() edit, {
    bool local = true,
  }) async {
    run.steps++;
    run.history.add(name);
    try {
      edit();
    } on UnsupportedError {
      return; // e.g. joining across a structural content control
    } on StateError catch (error) {
      // A full relayout (unchanged by incremental layout) rejects a model
      // that earlier scripted edits left inconsistent. Not a layout
      // mismatch: stop editing this document and fail with the reason.
      if (local) rethrow;
      run.modelErrors.add('$label: $name: $error');
      throw const _StopDocument();
    }
    if (local) _expectEquivalent(c, '$label: $name', run);
  }

  int len(int i) => _paras(c)[i].text.length;
  if (p >= _paras(c).length) return;
  final int base = len(p);

  // Typing at the end of the paragraph.
  _at(c, p, base);
  await step('type a', () => c.insertText('a'));
  await step('type bc', () => c.insertText(' bc'));
  // Typing that wraps lines and pushes later content to the next page.
  await step('type long', () => c.insertText(_long));
  // Typing in the middle of the paragraph.
  _at(c, p, (len(p) / 2).floor());
  await step('type middle', () => c.insertText('Mitte '));
  await step('backspace', () => c.deleteSelectionOr(backward: true));
  // Deleting the long text pulls later content back.
  final int end = len(p);
  _select(c, p, base, p, end);
  await step('delete selection', () => c.deleteSelectionOr(backward: true));
  // Split and join.
  _at(c, p, (len(p) / 2).floor());
  await step('enter (split)', () => c.insertParagraphBreak());
  await step('backspace (join)', () => c.deleteSelectionOr(backward: true));
  // Empty paragraphs shift everything below, both directions.
  _at(c, p, len(p));
  for (var i = 0; i < 3; i++) {
    await step('enter $i', () => c.insertParagraphBreak());
  }
  await step('type in empty', () => c.insertText('Neu'));
  for (var i = 0; i < 6; i++) {
    await step('backspace $i', () => c.deleteSelectionOr(backward: true));
  }
  // Forward delete joining the next paragraph, then restoring the break.
  if (p + 1 < _paras(c).length) {
    _at(c, p, len(p));
    await step(
      'delete (join next)',
      () => c.deleteSelectionOr(backward: false),
    );
    await step('enter (restore)', () => c.insertParagraphBreak());
  }
  // A selection across three paragraphs.
  if (p + 2 < _paras(c).length) {
    _select(c, p, (len(p) / 2).floor(), p + 2, (len(p + 2) / 3).floor());
    await step(
      'delete across paragraphs',
      () => c.deleteSelectionOr(backward: true),
    );
    await step('type after cross delete', () => c.insertText(' x'));
  }
  // Plain paste of several lines (local), then typing.
  _at(c, p, len(p));
  OfficeClipboard.instance
    ..useSystem = false
    ..writeLocal(
      OfficeClipboardPayload.fromPlain('Eins zwei drei\nvier fünf\n\nsechs'),
    );
  run.steps++;
  await c.pasteFromClipboard();
  _expectEquivalent(c, '$label: paste', run);
  await step('type after paste', () => c.insertText('!'));
  // Run formatting (a full relayout), then typing reuses fresh state.
  _select(c, p, 0, p, len(p));
  await step(
    'bold',
    () => c.applyRunFormat((WmlRunProps props) => props.bold = true),
    local: false,
  );
  _at(c, p, 0);
  await step('type after bold', () => c.insertText('Z'));
  await step('backspace after bold', () => c.deleteSelectionOr(backward: true));
  // Undo (a full relayout), then typing.
  await step('undo', () => c.undo(), local: false);
  _at(c, p.clamp(0, _paras(c).length - 1), 0);
  await step('type after undo', () => c.insertText('U'));
}

List<int> _targets(WordEditorController c) {
  final List<WmlParagraph> paras = _paras(c);
  if (paras.isEmpty) return const <int>[];
  final Set<WmlParagraph> inTables = <WmlParagraph>{
    for (final WmlSection s in c.document.sections)
      for (final WmlBlock b in WordTree.visibleBlocks(s.blocks))
        if (b is WmlTable) ...WordTree.paragraphs(<WmlBlock>[b]),
  };
  final List<int> body = <int>[
    for (int i = 0; i < paras.length; i++)
      if (!inTables.contains(paras[i]) && paras[i].text.trim().isNotEmpty) i,
  ];
  final List<int> cells = <int>[
    for (int i = 0; i < paras.length; i++)
      if (inTables.contains(paras[i])) i,
  ];
  return <int>{
    if (body.isNotEmpty) body.first,
    if (body.isNotEmpty) body[body.length ~/ 2],
    if (body.isNotEmpty) body.last,
    if (cells.isNotEmpty) cells[cells.length ~/ 2],
    if (body.isEmpty && cells.isEmpty) 0,
  }.toList()..sort((a, b) => b.compareTo(a)); // later first: earlier stay put
}

Future<_Run> _runDocument(String label, WordEditorController c) async {
  final _Run run = _Run();
  c.refresh();
  // The fingerprint itself is deterministic: two full layouts agree.
  expect(
    wordLayoutFingerprint(
      _freshEngine(c).layout(c.document, updateFields: false),
    ),
    wordLayoutFingerprint(
      _freshEngine(c).layout(c.document, updateFields: false),
    ),
    reason: '$label: full layouts differ from each other',
  );
  try {
    for (final int p in _targets(c)) {
      await _script(c, p, '$label ¶$p', run);
    }
  } on _StopDocument {
    // Cross-paragraph deletes keep paired markers consistent (bookmarks are
    // clamped or removed with their range), so no scripted edit may leave a
    // model a full relayout rejects.
    fail('EQUIVALENCE_MODEL_ERROR ${run.modelErrors.join('; ')}');
  }
  return run;
}

// ---------------------------------------------------------------------------
// Synthetic corpus

WmlParagraph _p(
  String text, {
  WmlRunProps? props,
  void Function(WmlParagraphProps p)? set,
}) {
  final WmlParagraph paragraph = WmlParagraph(
    inlines: <WmlInline>[
      WmlRun(text: text, properties: props ?? WmlRunProps()),
    ],
  );
  set?.call(paragraph.properties);
  return paragraph;
}

const List<String> _german = <String>[
  'Die Gemeinde hat im vergangenen Jahr einen neuen Haushaltsplan beschlossen, '
      'der die Sanierung der Schulen und den Ausbau der Radwege vorsieht.',
  'Das Projekt wird in drei Abschnitten umgesetzt; der erste Abschnitt '
      'beginnt im Frühjahr und soll bis zum Herbst abgeschlossen sein.',
];
const String _english =
    'The committee reviewed the proposal and agreed that the timeline is '
    'realistic, provided that the funding arrives before the summer.';
const String _arabic =
    'ناقشت اللجنة المقترح الجديد ووافقت على الجدول الزمني بشرط وصول التمويل قبل الصيف.';

WmlParagraph _mixed(int i) => switch (i % 4) {
  0 => _p('${_german[i % 2]} ($i)'),
  1 => _p('$_english ($i)', props: WmlRunProps(proofingLanguage: 'en-US')),
  2 => _p(
    _arabic,
    props: WmlRunProps(complexScript: true),
  )..properties.rightToLeft = true,
  _ => _p('${_german[0]} ${_german[1]}'),
};

WmlDocument _mixedLong() => WmlDocument(
  sections: <WmlSection>[
    WmlSection(blocks: <WmlBlock>[for (int i = 0; i < 120; i++) _mixed(i)]),
  ],
)..proofingLanguage = 'de-DE';

WmlTable _table(int rows, int cols) => WmlTable(
  rows: <WmlTableRow>[
    for (int r = 0; r < rows; r++)
      WmlTableRow(
        cells: <WmlTableCell>[
          for (int k = 0; k < cols; k++)
            WmlTableCell(
              blocks: <WmlBlock>[
                _p(r.isEven ? 'Zelle $r/$k ${_german[k % 2]}' : 'Cell $r/$k'),
              ],
            ),
        ],
      ),
  ],
);

WmlDocument _structured() {
  final List<WmlBlock> blocks = <WmlBlock>[
    _p('Inhalt', set: (p) => p.headingLevel = 1),
    WmlToc(),
    for (int h = 0; h < 3; h++) ...<WmlBlock>[
      _p('Kapitel ${h + 1}', set: (p) => p.headingLevel = 1),
      for (int i = 0; i < 6; i++) _mixed(i + h),
      for (int i = 0; i < 4; i++)
        _p('Punkt $i: ${_german[i % 2]}')
          ..properties.listLabel = '${i + 1}. '
          ..properties.indent = const WmlIndent(left: 18),
      _p('Absatz mit Bild ')
        ..inlines.add(
          WmlRun(
            text: '￼',
            inlineVisual: WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                width: 120,
                height: 80,
              ),
            ),
          ),
        ),
      _table(h == 1 ? 40 : 3, 3),
      _p('Neue Seite ${h + 1}', set: (p) => p.pageBreakBefore = true),
      for (int i = 0; i < 5; i++)
        _p(
          _german[i % 2],
          set: (p) => p
            ..justification = WmlJustification.justify
            ..shadingFill = i == 2 ? 'EEEEEE' : null,
        ),
    ],
  ];
  return WmlDocument(sections: <WmlSection>[WmlSection(blocks: blocks)]);
}

WmlDocument _sections() {
  WmlParagraph pageField() =>
      _p('Seite ', set: (p) => p.pageNumberField = true);
  return WmlDocument(
    sections: <WmlSection>[
      WmlSection(
        blocks: <WmlBlock>[for (int i = 0; i < 30; i++) _mixed(i)],
        header: <WmlParagraph>[_p('Kopfzeile')],
        footer: <WmlParagraph>[pageField()],
        lineNumbers: true,
      ),
      WmlSection(
        blocks: <WmlBlock>[for (int i = 0; i < 40; i++) _mixed(i + 1)],
        columnCount: 2,
        columnSep: true,
        breakKind: WmlSectionBreakKind.continuous,
        footer: <WmlParagraph>[pageField()],
      ),
      WmlSection(
        blocks: <WmlBlock>[
          for (int i = 0; i < 20; i++) _mixed(i + 2),
          _table(12, 2),
          for (int i = 0; i < 20; i++) _mixed(i + 3),
        ],
        breakKind: WmlSectionBreakKind.nextPage,
        differentFirstPage: true,
        firstHeader: <WmlParagraph>[_p('Erste Seite')],
        header: <WmlParagraph>[_p('Weitere Seiten')],
        footer: <WmlParagraph>[pageField()],
      ),
      WmlSection(
        blocks: <WmlBlock>[for (int i = 0; i < 15; i++) _mixed(i)],
        breakKind: WmlSectionBreakKind.oddPage,
        columnCount: 3,
      ),
    ],
  );
}

WmlDocument _footnotes() {
  final WmlDocument document = WmlDocument(
    sections: <WmlSection>[
      WmlSection(blocks: <WmlBlock>[for (int i = 0; i < 40; i++) _mixed(i)]),
    ],
  );
  return document;
}

// ---------------------------------------------------------------------------
// Fixture corpus

List<File> _fixtures() {
  final List<String> roots = <String>[
    '../legacy_doc_parser/test/fixtures/fidelity',
    '../legacy_doc_parser/test/fixtures/fidelity/semantic-contracts',
    '../legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored',
    '../legacy_doc_parser/test/fixtures/word_native',
    '../quds_office_engine/test/fixtures',
    '../quds_office_engine/test/fixtures/fidelity',
    '../quds_office_engine/test/fixtures/word-kerning',
    '../../docs/validation/word-native-layout-20261120/reference',
    'test/fixtures',
  ];
  final List<File> files = <File>[
    for (final String root in roots)
      if (Directory(root).existsSync())
        for (final FileSystemEntity e in Directory(root).listSync())
          if (e is File && e.path.endsWith('.docx')) e,
  ];
  // A few line-box references (paragraph wrapping, justify, mixed sizes).
  for (final String name in <String>[
    'wl2-justify-arial',
    'wl2-mixed-size-valid',
    'calibri-auto-360',
    'times-exact-360',
  ]) {
    final File f = File(
      '../../docs/validation/word-line-boxes-20261120/reference/$name.docx',
    );
    if (f.existsSync()) files.add(f);
  }
  if (Platform.environment['QUDS_EQUIVALENCE_POI'] == '1') {
    final Directory poi = Directory(
      '../legacy_doc_parser/test/fixtures/external/poi-20261114/poi/docx',
    );
    if (poi.existsSync()) {
      files.addAll(
        poi.listSync().whereType<File>().where((f) => f.path.endsWith('.docx')),
      );
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => WordLayoutEngine.incrementalLayout = true);

  group('incremental layout equals full layout', () {
    final Map<String, WmlDocument Function()> synthetic =
        <String, WmlDocument Function()>{
          'mixed German/English/Arabic, 120 paragraphs': _mixedLong,
          'headings, TOC, lists, image, tables, page breaks': _structured,
          'sections, columns, headers/footers, page numbers, line numbers':
              _sections,
        };
    for (final MapEntry<String, WmlDocument Function()> entry
        in synthetic.entries) {
      test(entry.key, () async {
        WordIncrementalLayoutStats.reset();
        final WordEditorController c = WordEditorController(
          document: entry.value(),
        );
        addTearDown(c.dispose);
        final _Run run = await _runDocument(entry.key, c);
        expect(run.checks, greaterThan(20));
        // The incremental path ran and met the old flow, not fallbacks.
        expect(WordIncrementalLayoutStats.incremental, greaterThan(20));
        expect(WordIncrementalLayoutStats.converged, greaterThan(5));
      });
    }

    // Notes are part of the incremental flow state: page reserves, note
    // continuations onto later pages, endnotes appended after the body.
    String longNote(int n) => List<String>.generate(
      n,
      (int i) =>
          'Fußnotentext $i mit einer längeren Erläuterung, '
          'which continues in English and ',
    ).join();
    final Map<String, void Function(WordEditorController)> noteSetups =
        <String, void Function(WordEditorController)>{
          'footnotes': (WordEditorController c) {
            _at(c, 3, 10);
            c.insertFootnote(text: 'Eine Fußnote mit etwas Text.');
            c.commitPendingEdits();
            _at(c, 20, 5);
            c.insertFootnote(text: 'A second note.');
            c.commitPendingEdits();
          },
          'footnotes continued onto the next page and endnotes':
              (WordEditorController c) {
                _at(c, 8, 4);
                c.insertFootnote(text: longNote(40));
                c.commitPendingEdits();
                _at(c, 9, 2);
                c.insertFootnote(text: 'Kurz.');
                c.commitPendingEdits();
                _at(c, 25, 6);
                c.insertFootnote(text: 'Endnote eins.', endnote: true);
                c.commitPendingEdits();
                _at(c, 33, 3);
                c.insertFootnote(text: longNote(6), endnote: true);
                c.commitPendingEdits();
              },
        };
    for (final MapEntry<String, void Function(WordEditorController)> entry
        in noteSetups.entries) {
      test('${entry.key} stay exact on the incremental path', () async {
        final WordEditorController c = WordEditorController(
          document: _footnotes(),
        );
        addTearDown(c.dispose);
        entry.value(c);
        WordIncrementalLayoutStats.reset();
        final _Run run = await _runDocument(entry.key, c);
        expect(run.checks, greaterThan(20));
        expect(WordIncrementalLayoutStats.incremental, greaterThan(20));
        expect(WordIncrementalLayoutStats.converged, greaterThan(5));
      });
    }

    for (final File file in _fixtures()) {
      final String name = file.path.split('/').skip(1).join('/');
      test('fixture $name', () async {
        final WordEditorController c;
        try {
          c = WordEditorController.fromBytes(file.readAsBytesSync());
        } on Object catch (error) {
          markTestSkipped('not loadable: $error');
          return;
        }
        addTearDown(c.dispose);
        if (!c.config.allowsMutation) {
          markTestSkipped('read-only');
          return;
        }
        if (_paras(c).isEmpty) {
          markTestSkipped('no paragraphs to edit');
          return;
        }
        final _Run run = await _runDocument(name, c);
        expect(run.checks, greaterThan(0));
      });
    }
  });

  test('switch off: local edits use the section path', () {
    WordIncrementalLayoutStats.reset();
    WordLayoutEngine.incrementalLayout = false;
    addTearDown(() => WordLayoutEngine.incrementalLayout = true);
    final WordEditorController c = WordEditorController(document: _mixedLong());
    addTearDown(c.dispose);
    _at(c, 40, 3);
    c.insertText('abc');
    expect(WordIncrementalLayoutStats.incremental, 0);
    expect(WordIncrementalLayoutStats.fallbacks, 0);
    expect(c.documentLaidOut.supportsIncrementalReuse, isTrue);
  });

  test('verify mode compares every incremental layout', () {
    WordLayoutEngine.verifyIncrementalLayout = true;
    addTearDown(() => WordLayoutEngine.verifyIncrementalLayout = false);
    final WordEditorController c = WordEditorController(document: _mixedLong());
    addTearDown(c.dispose);
    _at(c, 60, 10);
    for (final String ch in 'Verifiziert '.split('')) {
      c.insertText(ch);
    }
    c.insertParagraphBreak();
    c.deleteSelectionOr(backward: true);
  });

  test('Enter reflows the rest of the document from cached line breaks', () {
    final WordEditorController c = WordEditorController(document: _mixedLong());
    addTearDown(c.dispose);
    _at(c, 30, 5);
    c.insertText('x'); // seeds state after the constructor's full layout
    WordIncrementalLayoutStats.reset();
    final _Run run = _Run();
    // An empty paragraph moves everything below by a line. The flow meets
    // the old layout only where a page break absorbs the shift; until then
    // every unchanged paragraph reuses its line breaks instead of reshaping.
    for (final int p in <int>[100, 70, 40, 10]) {
      _at(c, p, _paras(c)[p].text.length);
      c.insertParagraphBreak();
      _expectEquivalent(c, 'enter after ¶$p', run);
    }
    expect(WordIncrementalLayoutStats.incremental, 4);
    expect(
      WordIncrementalLayoutStats.breaksReused,
      greaterThan(WordIncrementalLayoutStats.blocksLaidOut ~/ 2),
    );
  });

  test('typing in one paragraph lays out a handful of blocks', () {
    WordIncrementalLayoutStats.reset();
    final WordEditorController c = WordEditorController(document: _mixedLong());
    addTearDown(c.dispose);
    _at(c, 60, _paras(c)[60].text.length);
    c.insertText('x'); // seeds state after the constructor's full layout
    WordIncrementalLayoutStats.reset();
    for (var i = 0; i < 20; i++) {
      c.insertText('y');
    }
    expect(WordIncrementalLayoutStats.incremental, 20);
    // Unless a keystroke wraps a new line (then everything below moves),
    // the flow meets the old layout right after the edited paragraph:
    // resume one block early, the edited block, one block of margin.
    expect(WordIncrementalLayoutStats.converged, greaterThanOrEqualTo(18));
  });

  test('the first keystroke after paint fitting is incremental', () {
    final WordEditorController c = WordEditorController(document: _mixedLong());
    addTearDown(c.dispose);
    final _Run run = _Run();
    for (final int p in <int>[60, 10, 100]) {
      c.fitPaintMetrics(themeFamily: c.config.theme.fontFamily);
      WordIncrementalLayoutStats.reset();
      _at(c, p, _paras(c)[p].text.length);
      c.insertText('x');
      expect(WordIncrementalLayoutStats.incremental, 1, reason: '¶$p');
      expect(WordIncrementalLayoutStats.fallbacks, 0);
      _expectEquivalent(c, 'type after fit ¶$p', run);
      // A wrapped line moves everything below: still exact.
      c.insertText(_long);
      _expectEquivalent(c, 'long after fit ¶$p', run);
    }
  });

  test('the first keystroke after a formatting change is incremental', () {
    final WordEditorController c = WordEditorController(document: _mixedLong());
    addTearDown(c.dispose);
    final _Run run = _Run();
    _select(c, 30, 0, 30, 12);
    c.applyRunFormat((WmlRunProps props) => props.italic = true);
    WordIncrementalLayoutStats.reset();
    _at(c, 30, 5);
    c.insertText('y');
    expect(WordIncrementalLayoutStats.incremental, 1);
    _expectEquivalent(c, 'type after italic', run);
  });

  test('footnotes: typing converges right after the edited paragraph', () {
    final WordEditorController c = WordEditorController(document: _footnotes());
    addTearDown(c.dispose);
    _at(c, 3, 10);
    c.insertFootnote(text: 'Eine Fußnote.');
    c.commitPendingEdits();
    _at(c, 12, 4);
    c.insertFootnote(text: 'Endnote.', endnote: true);
    c.commitPendingEdits();
    final _Run run = _Run();
    _at(c, 5, _paras(c)[5].text.length);
    c.insertText('x');
    WordIncrementalLayoutStats.reset();
    for (var i = 0; i < 10; i++) {
      c.insertText('y');
      _expectEquivalent(c, 'type $i', run);
    }
    expect(WordIncrementalLayoutStats.incremental, 10);
    expect(WordIncrementalLayoutStats.converged, greaterThanOrEqualTo(8));
    expect(WordIncrementalLayoutStats.blocksLaidOut, lessThan(10 * 6));
  });
}

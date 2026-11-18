import 'dart:convert';
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _p(String text, {bool bold = false}) => WmlParagraph(
  inlines: <WmlInline>[
    WmlRun(
      text: text,
      properties: WmlRunProps(bold: bold),
    ),
  ],
);

WmlDocument _doc(List<String> lines) => WmlDocument(
  sections: <WmlSection>[WmlSection(blocks: lines.map<WmlBlock>(_p).toList())],
);

String _original(WordComparisonEntry entry) => entry.spans
    .where((span) => span.kind != WordComparisonSpanKind.insert)
    .map((span) => span.originalText)
    .join();
String _revised(WordComparisonEntry entry) => entry.spans
    .where((span) => span.kind != WordComparisonSpanKind.delete)
    .map((span) => span.text)
    .join();

void _reconstruct(WordComparisonResult result) {
  for (final entry in result.entries.where((e) => e.spans.isNotEmpty)) {
    expect(_original(entry), entry.originalText);
    expect(_revised(entry), entry.revisedText);
  }
}

void main() {
  test('middle paragraph insertion does not rewrite following paragraphs', () {
    final result = WordDocumentComparison.compare(
      _doc(<String>['Title', 'First', 'Last']),
      _doc(<String>['Title', 'First', 'New paragraph', 'Last']),
    );
    expect(result.insertedCount, 1);
    expect(result.modifiedCount, 0);
    expect(result.deletedCount, 0);
    expect(result.unchangedCount, 3);
    expect(result.changes.single.revisedText, 'New paragraph');
    expect(result.changes.single.revisedLocation!.paragraphIndex, 2);
    _reconstruct(result);
  });

  test('whole paragraph removal and empty paragraphs remain visible', () {
    final result = WordDocumentComparison.compare(
      _doc(<String>['Keep', '', 'Gone', 'End']),
      _doc(<String>['Keep', 'End']),
    );
    expect(result.deletedCount, 2);
    expect(result.changes.map((e) => e.originalText), <String>['', 'Gone']);
    expect(result.changes.first.spans, isEmpty);
    _reconstruct(result);
  });

  test(
    'word-level redline retains unchanged context and reconstructs both inputs',
    () {
      final result = WordDocumentComparison.compare(
        _doc(<String>['The quick brown fox.']),
        _doc(<String>['The slow brown fox.']),
      );
      final change = result.changes.single;
      expect(change.kind, WordComparisonKind.modified);
      expect(change.spans.map((e) => e.kind), <WordComparisonSpanKind>[
        WordComparisonSpanKind.equal,
        WordComparisonSpanKind.delete,
        WordComparisonSpanKind.insert,
        WordComparisonSpanKind.equal,
      ]);
      expect(change.spans.map((e) => e.text), <String>[
        'The ',
        'quick',
        'slow',
        ' brown fox.',
      ]);
      _reconstruct(result);
    },
  );

  test('repeated paragraphs align deterministically', () {
    final before = _doc(<String>['A', 'Repeat', 'Repeat', 'B', 'Repeat']);
    final after = _doc(<String>['A', 'Repeat', 'NEW', 'Repeat', 'B', 'Repeat']);
    final result = WordDocumentComparison.compare(before, after);
    expect(result.changeCount, 1);
    expect(result.insertedCount, 1);
    expect(result.changes.single.revisedText, 'NEW');
    expect(
      result.toJsonString(),
      WordDocumentComparison.compare(before, after).toJsonString(),
    );
  });

  test('Unicode, Arabic, combining marks and joined emoji are indivisible', () {
    const before = 'مرحبا 👩🏽‍💻 cafe\u0301 東京';
    const after = 'مرحبا 👨🏿‍💻 cafe\u0301 京都';
    final result = WordDocumentComparison.compare(
      _doc(<String>[before]),
      _doc(<String>[after]),
    );
    _reconstruct(result);
    final entry = result.changes.single;
    final originals = before.characters.toSet();
    final revisions = after.characters.toSet();
    for (final span in entry.spans) {
      final allowed = span.kind == WordComparisonSpanKind.delete
          ? originals
          : revisions;
      expect(span.text.characters.every(allowed.contains), isTrue);
      expect(span.text, isNot(contains('\uFFFD')));
    }
    expect(
      entry.spans.any(
        (s) => s.kind == WordComparisonSpanKind.delete && s.text == '👩🏽‍💻',
      ),
      isTrue,
    );
    expect(
      entry.spans.any(
        (s) => s.kind == WordComparisonSpanKind.insert && s.text == '👨🏿‍💻',
      ),
      isTrue,
    );
  });

  test(
    'normalization preserves source text and reports only requested differences',
    () {
      final before = _doc(<String>['  HELLO   World  ']);
      final after = _doc(<String>['hello World']);
      expect(WordCompare.diff(before, after).hasChanges, isTrue);
      final result = WordCompare.diff(
        before,
        after,
        options: const WordComparisonOptions(
          ignoreCase: true,
          ignoreWhitespace: true,
        ),
      );
      expect(result.hasChanges, isFalse);
      expect(result.entries.single.originalText, '  HELLO   World  ');
      expect(result.entries.single.revisedText, 'hello World');
      _reconstruct(result);
    },
  );

  test(
    'direct run formatting is detected but equivalent run splitting is not',
    () {
      final before = _doc(<String>['Word']);
      final after = _doc(<String>['Word']);
      after.paragraphs.single.inlines = <WmlInline>[
        WmlRun(text: 'Wo'),
        WmlRun(text: 'rd'),
      ];
      expect(WordCompare.diff(before, after).hasChanges, isFalse);
      (after.paragraphs.single.inlines.last as WmlRun).properties.bold = true;
      final result = WordCompare.diff(before, after);
      expect(result.formattingCount, 1);
      expect(
        result.changes.single.formattingChanges,
        contains('Direct character formatting changed.'),
      );
      expect(
        WordCompare.diff(
          before,
          after,
          options: const WordComparisonOptions(includeFormatting: false),
        ).hasChanges,
        isFalse,
      );
    },
  );

  test('paragraph and section formatting changes have readable details', () {
    final before = _doc(<String>['Text']);
    final after = _doc(<String>['Text']);
    after.paragraphs.single.properties.justification = WmlJustification.center;
    after.sections.single.columnCount = 2;
    final result = WordCompare.diff(before, after);
    expect(result.formattingCount, 2);
    expect(
      result.changes.expand((e) => e.formattingChanges).join(' '),
      contains('Columns: 1 → 2'),
    );
    expect(
      result.changes.expand((e) => e.formattingChanges).join(' '),
      contains('Alignment: left → center'),
    );
  });

  test(
    'projecting pending revisions never changes metadata or input identity',
    () {
      final document = _doc(<String>['oldnew tail']);
      final paragraph = document.paragraphs.single;
      final deletion = WmlRevision(
        id: 1,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 0,
        start: 0,
        end: 3,
        text: 'old',
        author: 'Ada',
      );
      final insertion = WmlRevision(
        id: 2,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        start: 3,
        end: 6,
        text: 'new',
        author: 'Bob',
      );
      document.revisions.addAll(<WmlRevision>[insertion, deletion]);
      expect(
        WordCompare.diff(document, _doc(<String>['new tail'])).hasChanges,
        isFalse,
      );
      expect(
        WordCompare.diff(
          document,
          _doc(<String>['old tail']),
          options: const WordComparisonOptions(
            revisionView: WordComparisonRevisionView.originalText,
          ),
        ).hasChanges,
        isFalse,
      );
      expect(
        WordCompare.diff(
          document,
          _doc(<String>['oldnew tail']),
          options: const WordComparisonOptions(
            revisionView: WordComparisonRevisionView.markup,
          ),
        ).hasChanges,
        isFalse,
      );
      expect(document.paragraphs.single, same(paragraph));
      expect(paragraph.text, 'oldnew tail');
      expect(document.trackRevisions, isFalse);
      expect(document.revisions, <WmlRevision>[insertion, deletion]);
      expect(insertion.targetParagraph, isNull);
      expect(deletion.targetParagraph, isNull);
      expect(insertion.accepted, isNull);
      expect(deletion.start, 0);
      expect(deletion.text, 'old');
    },
  );

  test('tracked deletion projection excludes deleted character formatting', () {
    final before = _doc(<String>['oldnew']);
    final paragraph = before.paragraphs.single;
    paragraph.inlines = <WmlInline>[
      WmlRun(text: 'old', properties: WmlRunProps(bold: true)),
      WmlRun(text: 'new'),
    ];
    before.revisions.add(
      WmlRevision(
        id: 1,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 0,
        start: 0,
        end: 3,
        text: 'old',
      ),
    );
    expect(WordCompare.diff(before, _doc(<String>['new'])).hasChanges, isFalse);
  });

  test(
    'invalid or overlapping revision ranges cannot silently project wrong text',
    () {
      final document = _doc(<String>['abcdef']);
      final revision = WmlRevision(
        id: 1,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 0,
        start: 1,
        end: 3,
        text: 'WRONG',
      );
      document.revisions.add(revision);
      expect(
        () => WordCompare.diff(document, _doc(<String>['abcdef'])),
        throwsStateError,
      );
      final markup = WordCompare.diff(
        document,
        _doc(<String>['abcdef']),
        options: const WordComparisonOptions(
          revisionView: WordComparisonRevisionView.markup,
        ),
      );
      expect(markup.hasChanges, isFalse);
      expect(markup.warnings.join(' '), contains('unresolved tracked changes'));
      expect(revision.targetParagraph, isNull);
      expect(revision.conflict, isNull);
      revision.text = 'bc';
      document.revisions.add(
        WmlRevision(
          id: 2,
          kind: WmlRevisionKind.insert,
          paragraphIndex: 0,
          start: 2,
          end: 4,
          text: 'cd',
        ),
      );
      expect(
        () => WordCompare.diff(document, _doc(<String>['abcdef'])),
        throwsStateError,
      );
    },
  );

  test('detached target is not redirected by a stale legacy index', () {
    final document = _doc(<String>['body']);
    document.revisions.add(
      WmlRevision(
        id: 8,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 0,
        targetParagraph: _p('body'),
        start: 0,
        end: 4,
        text: 'body',
      ),
    );
    expect(
      () => WordCompare.diff(document, _doc(<String>[''])),
      throwsStateError,
    );
    expect(document.paragraphs.single.text, 'body');
  });

  test(
    'captured-null target cannot be rebound after later paragraph insertion',
    () {
      final document = _doc(<String>[]);
      final revision = WmlRevision(
        id: 8,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 0,
        start: 0,
        end: 4,
        text: 'body',
      );
      document.revisions.add(revision);
      expect(WordRevisions.resolveParagraph(document, revision), isNull);
      expect(revision.hasCapturedTarget, isTrue);
      document.sections.single.blocks.add(_p('body'));
      expect(
        () => WordCompare.diff(document, _doc(<String>[''])),
        throwsStateError,
      );
      expect(revision.targetParagraph, isNull);
      expect(document.paragraphs.single.text, 'body');
    },
  );

  test(
    'table, frame, header and note changes retain their story locations',
    () {
      WmlDocument rich(String value) {
        final document = _doc(<String>['Body']);
        document.sections.single.header.add(_p('Header $value'));
        document.sections.single.blocks.add(
          WmlTable(
            rows: <WmlTableRow>[
              WmlTableRow(
                cells: <WmlTableCell>[
                  WmlTableCell(blocks: <WmlBlock>[_p('Cell $value')]),
                ],
              ),
            ],
          ),
        );
        document.sections.single.blocks.add(
          WmlFrame(blocks: <WmlBlock>[_p('Box $value')]),
        );
        document.footnotes.add(
          WmlNote(
            id: 4,
            endnote: false,
            paragraphs: <WmlParagraph>[_p('Note $value')],
          ),
        );
        document.endnotes.add(
          WmlNote(
            id: 9,
            endnote: true,
            paragraphs: <WmlParagraph>[_p('Endnote $value')],
          ),
        );
        document.comments.add(WmlComment(id: 10, text: 'Comment $value'));
        return document;
      }

      final result = WordCompare.diff(rich('before'), rich('after'));
      expect(result.modifiedCount, 6);
      expect(
        result.changes.map((e) => e.label).join(' '),
        contains('Table 1 · Row 1, Cell 1'),
      );
      expect(result.changes.map((e) => e.label).join(' '), contains('Frame 1'));
      expect(
        result.changes.map((e) => e.revisedLocation!.story).toSet(),
        containsAll(<String>[
          'body:0',
          'header:0',
          'footnote:0',
          'endnote:0',
          'comment:0',
        ]),
      );
      _reconstruct(result);
    },
  );

  test('empty table topology changes are not mistaken for equal documents', () {
    final before = _doc(<String>['Text']);
    final after = _doc(<String>['Text']);
    before.sections.single.blocks.add(
      WmlTable(rows: <WmlTableRow>[WmlTableRow()]),
    );
    after.sections.single.blocks.add(
      WmlTable(rows: <WmlTableRow>[WmlTableRow(), WmlTableRow()]),
    );
    final result = WordCompare.diff(before, after);
    expect(result.structureCount, 1);
    expect(result.changes.single.label, contains('Table 1'));
  });

  test(
    'same display text with a different hyperlink is a structural change',
    () {
      final before = _doc(<String>['Link']);
      final after = _doc(<String>['Link']);
      (before.paragraphs.single.inlines.single as WmlRun).hyperlink =
          const WmlHyperlink(url: 'https://example.com/a');
      (after.paragraphs.single.inlines.single as WmlRun).hyperlink =
          const WmlHyperlink(url: 'https://example.com/b');
      final result = WordCompare.diff(before, after);
      expect(result.structureCount, 1);
      expect(result.changes.single.details.join(' '), contains('links'));
    },
  );

  test('splitting a hyperlink across equal runs is not a document change', () {
    const link = WmlHyperlink(url: 'https://example.com/');
    final before = _doc(<String>['A link']);
    final after = _doc(<String>['A link']);
    (before.paragraphs.single.inlines.single as WmlRun).hyperlink = link;
    after.paragraphs.single.inlines = <WmlInline>[
      WmlRun(text: 'A ', hyperlink: link),
      WmlRun(text: 'link', hyperlink: link),
    ];
    expect(WordCompare.diff(before, after).hasChanges, isFalse);
  });

  test('coarse fallback is bounded, disclosed and does not truncate text', () {
    const before = 'one two three four five';
    const after = 'alpha beta gamma delta';
    final result = WordCompare.diff(
      _doc(<String>[before]),
      _doc(<String>[after]),
      options: const WordComparisonOptions(maxDiffWork: 1),
    );
    expect(result.usedCoarseDiff, isTrue);
    expect(result.warnings.join(' '), contains('coarser replacement'));
    _reconstruct(result);
    expect(result.changes.single.originalText, before);
    expect(result.changes.single.revisedText, after);
  });

  test('large mostly identical inputs use anchors without quadratic work', () {
    final lines = List<String>.generate(3000, (i) => 'Paragraph $i');
    final changed = lines.toList()..insert(1500, 'New paragraph');
    final result = WordCompare.diff(
      _doc(lines),
      _doc(changed),
      options: const WordComparisonOptions(maxDiffWork: 8),
    );
    expect(result.insertedCount, 1);
    expect(result.changeCount, 1);
    expect(result.usedCoarseDiff, isFalse);
  });

  test(
    'explicit input limits fail rather than return a partial equal result',
    () {
      final before = _doc(<String>['one', 'two']);
      final after = _doc(<String>['one', 'different']);
      expect(
        () => WordCompare.diff(
          before,
          after,
          options: const WordComparisonOptions(maxParagraphs: 1),
        ),
        throwsStateError,
      );
      expect(
        () => WordCompare.diff(
          before,
          after,
          options: const WordComparisonOptions(maxTextLength: 2),
        ),
        throwsStateError,
      );
      expect(
        () => WordCompare.diff(
          before,
          after,
          options: const WordComparisonOptions(maxDiffWork: 0),
        ),
        throwsArgumentError,
      );
      expect(before.paragraphs.map((p) => p.text), <String>['one', 'two']);
    },
  );

  test(
    'JSON report is deterministic, immutable and contains no model references',
    () {
      final result = WordCompare.diff(
        _doc(<String>['before']),
        _doc(<String>['after']),
      );
      final decoded = jsonDecode(result.toJsonString()) as Map<String, Object?>;
      expect(decoded['schemaVersion'], 1);
      expect((decoded['summary']! as Map<String, Object?>)['modified'], 1);
      expect(() => result.entries.clear(), throwsUnsupportedError);
      expect(() => result.entries.single.spans.clear(), throwsUnsupportedError);
      expect(() => result.warnings.clear(), throwsUnsupportedError);
    },
  );

  test('legacy unsafe mutation API fails before touching either input', () {
    final original = _doc(<String>['old', 'removed']);
    final revised = _doc(<String>['new']);
    // ignore: deprecated_member_use_from_same_package
    expect(
      () => WordCompare.compare(original, revised),
      throwsUnsupportedError,
    );
    expect(original.paragraphs.map((p) => p.text), <String>['old', 'removed']);
    expect(revised.paragraphs.single.text, 'new');
    expect(original.revisions, isEmpty);
    expect(revised.revisions, isEmpty);
    expect(revised.trackRevisions, isFalse);
  });

  test('independently authored native XML produces a readable comparison', () {
    WmlDocument native(String body) {
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            '<w:body>$body<w:sectPr/></w:body></w:document>',
          );
      return WordDeserializer().read(package);
    }

    final before = native('<w:p><w:r><w:t>The old clause.</w:t></w:r></w:p>');
    final after = native('<w:p><w:r><w:t>The new clause.</w:t></w:r></w:p>');
    final result = WordCompare.diff(before, after);
    expect(result.modifiedCount, 1);
    expect(result.changes.single.originalText, 'The old clause.');
    expect(result.changes.single.revisedText, 'The new clause.');
    _reconstruct(result);
  });

  test(
    'many independent edit sequences reconstruct both paragraph streams',
    () {
      final random = Random(7341);
      const vocabulary = <String>['A', 'B', 'same', '', 'مرحبا', '👩‍💻'];
      for (var trial = 0; trial < 100; trial++) {
        final before = List<String>.generate(
          random.nextInt(10),
          (_) => vocabulary[random.nextInt(vocabulary.length)],
        );
        final after = List<String>.generate(
          random.nextInt(10),
          (_) => vocabulary[random.nextInt(vocabulary.length)],
        );
        final result = WordCompare.diff(_doc(before), _doc(after));
        expect(
          result.entries
              .where((e) => e.originalLocation != null)
              .map((e) => e.originalText),
          before,
        );
        expect(
          result.entries
              .where((e) => e.revisedLocation != null)
              .map((e) => e.revisedText),
          after,
        );
        _reconstruct(result);
      }
    },
  );
}

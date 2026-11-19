import 'dart:convert';
import 'dart:math';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _p(String text) => WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _doc(List<WmlBlock> blocks) =>
    WmlDocument(sections: [WmlSection(blocks: blocks)]);

WmlOpaqueInline _opaque(String value) => WmlOpaqueInline(
  content: WmlOpaqueBlock(
    xml:
        '<w:pict xmlns:w="${OfficeNamespaces.w}"><value>$value</value></w:pict>',
    sourcePartUri: '/word/document.xml',
    relationships: const [],
  ),
);

void _reconstruct(WordComparisonResult report) {
  for (final entry in report.entries) {
    if ((entry.originalLocation?.paragraphIndex ?? -1) < 0 &&
        (entry.revisedLocation?.paragraphIndex ?? -1) < 0) {
      continue;
    }
    expect(
      entry.spans
          .where((span) => span.kind != WordComparisonSpanKind.insert)
          .map((span) => span.originalText)
          .join(),
      entry.originalText,
    );
    expect(
      entry.spans
          .where((span) => span.kind != WordComparisonSpanKind.delete)
          .map((span) => span.text)
          .join(),
      entry.revisedText,
    );
  }
}

void main() {
  test(
    'a previously captured missing target never binds a later paragraph',
    () {
      final document = _doc([]);
      final revision = WordRevisions.record(
        document,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 0,
        start: 0,
        end: 4,
        text: 'same',
      );
      expect(revision.targetParagraph, isNull);
      final later = _p('same');
      document.sections.single.blocks.add(later);
      expect(
        () => WordDocumentComparison.compare(document, _doc([_p('')])),
        throwsStateError,
        reason: 'Missing captured targets must not silently delete later text.',
      );
      expect(revision.targetParagraph, isNull);
      expect(revision.accepted, isNull);
      expect(later.text, 'same');
    },
  );

  test(
    'legacy body indices count TOC paragraphs without redirecting a change',
    () {
      WmlDocument fixture(String first) =>
          _doc([WmlToc(title: 'Contents'), _p(first), _p('same')]);
      final original = fixture('same');
      final revision = WmlRevision(
        id: 7,
        kind: WmlRevisionKind.delete,
        paragraphIndex: 1,
        start: 0,
        end: 4,
        text: 'same',
      );
      original.revisions.add(revision);
      expect(original.paragraphs.elementAt(1).text, 'same');
      final report = WordDocumentComparison.compare(original, fixture(''));
      expect(report.hasChanges, isFalse);
      expect(
        report.entries
            .where((entry) => entry.originalLocation?.story == 'body:0')
            .map((entry) => entry.originalText),
        ['Contents', '', 'same'],
      );
      expect(revision.targetParagraph, isNull);
      expect(original.paragraphs.map((p) => p.text), [
        'Contents',
        'same',
        'same',
      ]);
    },
  );

  test(
    'adjacent zero-width native inline nodes keep independent identities',
    () {
      WmlDocument fixture(String first) => _doc([
        WmlParagraph(
          inlines: [
            _opaque(first),
            _opaque('unchanged'),
            WmlRun(text: 'Body'),
          ],
        ),
      ]);
      final report = WordDocumentComparison.compare(
        fixture('before'),
        fixture('after'),
      );
      expect(report.hasChanges, isTrue);
      expect(report.structureCount, 1);
      expect(report.changes.single.details.join(' '), contains('digest'));
      expect(report.warnings.join(' '), contains('Preserved native XML'));
    },
  );

  test(
    'case normalization still detects moved direct character formatting',
    () {
      WmlDocument fixture(bool revised) => _doc([
        WmlParagraph(
          inlines: [
            WmlRun(
              text: revised ? 'one ' : 'One ',
              properties: WmlRunProps(bold: !revised),
            ),
            WmlRun(
              text: revised ? 'two' : 'Two',
              properties: WmlRunProps(bold: revised),
            ),
          ],
        ),
      ]);
      final report = WordDocumentComparison.compare(
        fixture(false),
        fixture(true),
        options: const WordComparisonOptions(ignoreCase: true),
      );
      expect(report.formattingCount, 1);
      expect(report.modifiedCount, 0);
      _reconstruct(report);
    },
  );

  test('ignored whitespace length does not invent a formatting change', () {
    WmlDocument fixture(String space) => _doc([
      WmlParagraph(
        inlines: [
          WmlRun(text: 'One$space', properties: WmlRunProps(bold: true)),
          WmlRun(text: 'Two'),
        ],
      ),
    ]);
    final report = WordDocumentComparison.compare(
      fixture('    '),
      fixture(' '),
      options: const WordComparisonOptions(ignoreWhitespace: true),
    );
    expect(report.hasChanges, isFalse);
    _reconstruct(report);
  });

  test('empty cached fields still compare their instructions', () {
    WmlDocument fixture(String instruction) => _doc([
      WmlParagraph(
        inlines: [WmlRun(text: '', fieldInstruction: instruction)],
      ),
    ]);
    final report = WordDocumentComparison.compare(
      fixture(' REF Alpha '),
      fixture(' REF Beta '),
    );
    expect(report.hasChanges, isTrue);
    expect(report.structureCount, 1);
  });

  test(
    'field locking is a semantic change with an unchanged displayed cache',
    () {
      WmlDocument fixture(bool locked) => _doc([
        WmlParagraph(
          inlines: [
            WmlRun(
              text: 'cache',
              fieldInstruction: ' REF Alpha ',
              fieldLocked: locked,
            ),
          ],
        ),
      ]);
      final report = WordDocumentComparison.compare(
        fixture(false),
        fixture(true),
      );
      expect(report.hasChanges, isTrue);
      expect(report.structureCount, 1);
    },
  );

  test(
    'changed bookmark endpoint pairing is visible even with identical text',
    () {
      WmlDocument fixture(bool swapped) => _doc([
        WmlParagraph(
          inlines: [
            WmlBookmarkBoundary(id: '1', name: 'Alpha', isStart: true),
            WmlRun(text: 'A'),
            WmlBookmarkBoundary(id: '2', name: 'Beta', isStart: true),
            WmlRun(text: 'B'),
            WmlBookmarkBoundary(id: swapped ? '2' : '1', isStart: false),
            WmlRun(text: 'C'),
            WmlBookmarkBoundary(id: swapped ? '1' : '2', isStart: false),
          ],
        ),
      ]);
      final report = WordDocumentComparison.compare(
        fixture(false),
        fixture(true),
      );
      expect(report.hasChanges, isTrue);
      expect(report.structureCount, 1);
      _reconstruct(report);
    },
  );

  test(
    'bounded dense inline reports reconstruct original and revised Unicode',
    () {
      final random = Random(28031);
      const words = [
        'same',
        'Same',
        ' Ω ',
        '\t',
        '👩🏽‍💻',
        'مرحبا',
        'e\u0301',
        '',
        '!!!',
      ];
      for (final budget in [1, 10, 2000]) {
        for (var trial = 0; trial < 60; trial++) {
          String sample() => List.generate(
            random.nextInt(25),
            (_) => words[random.nextInt(words.length)],
          ).join();
          final before = sample();
          final after = sample();
          final original = _doc([_p(before)]);
          final revised = _doc([_p(after)]);
          final report = WordDocumentComparison.compare(
            original,
            revised,
            options: WordComparisonOptions(
              maxDiffWork: budget,
              ignoreCase: trial.isEven,
              ignoreWhitespace: trial % 3 == 0,
            ),
          );
          _reconstruct(report);
          expect(original.paragraphs.single.text, before);
          expect(revised.paragraphs.single.text, after);
          expect(
            jsonDecode(report.toJsonString()),
            isA<Map<String, dynamic>>(),
          );
        }
      }
    },
  );

  test('cyclic block trees fail the explicit depth bound', () {
    final frame = WmlFrame(blocks: []);
    frame.blocks.add(frame);
    final original = _doc([frame]);
    expect(
      () => WordDocumentComparison.compare(original, _doc([])),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('nesting-depth'),
        ),
      ),
    );
    expect(frame.blocks.single, same(frame));
  });

  test('moving an unchanged comment to another text range is reported', () {
    WmlDocument fixture(bool moved) => _doc([
      WmlParagraph(
        inlines: [
          WmlRun(text: 'alpha ', commentIds: moved ? [] : [7]),
          WmlRun(text: 'beta', commentIds: moved ? [7] : []),
        ],
      ),
    ])..comments.add(WmlComment(id: 7, text: 'Keep this comment.'));
    final report = WordDocumentComparison.compare(
      fixture(false),
      fixture(true),
    );
    expect(report.structureCount, 1);
    expect(report.modifiedCount, 0);
    _reconstruct(report);
  });

  test('equivalent comment anchors ignore run splitting and native IDs', () {
    final original = _doc([
      WmlParagraph(
        inlines: [
          WmlRun(text: 'alpha beta', commentIds: [7]),
        ],
      ),
    ])..comments.add(WmlComment(id: 7, text: 'Same comment.'));
    final revised = _doc([
      WmlParagraph(
        inlines: [
          WmlRun(text: 'alpha ', commentIds: [88]),
          WmlRun(text: 'beta', commentIds: [88]),
        ],
      ),
    ])..comments.add(WmlComment(id: 88, text: 'Same comment.'));
    final report = WordDocumentComparison.compare(original, revised);
    expect(report.hasChanges, isFalse);
    _reconstruct(report);
  });

  for (final opaque in [false, true]) {
    test(
      '${opaque ? 'opaque' : 'visual'} block movement between paragraphs is reported',
      () {
        WmlBlock object() => opaque
            ? _opaque('same native content').content
            : WmlVisual(
                visual: OfficeVisual(
                  kind: OfficeVisualKind.picture,
                  title: 'Same visual',
                  width: 100,
                  height: 40,
                ),
              );
        final original = _doc([_p('A'), object(), _p('B')]);
        final revised = _doc([_p('A'), _p('B'), object()]);
        final report = WordDocumentComparison.compare(original, revised);
        expect(report.structureCount, 1);
        expect(report.modifiedCount, 0);
        expect(
          report.changes.single.details.join(' '),
          contains('After paragraph'),
        );
        _reconstruct(report);
      },
    );
  }

  test(
    'body and frame bookmark ID renumbering uses independent story scopes',
    () {
      WmlParagraph bookmarked(String id, String name, String text) =>
          WmlParagraph(
            inlines: [
              WmlBookmarkBoundary(id: id, name: name, isStart: true),
              WmlRun(text: text),
              WmlBookmarkBoundary(id: id, isStart: false),
            ],
          );
      WmlDocument fixture(String bodyId, String frameId) => _doc([
        bookmarked(bodyId, 'BodyBookmark', 'body text'),
        WmlFrame(blocks: [bookmarked(frameId, 'FrameBookmark', 'frame text')]),
      ]);
      final original = fixture('1', '2');
      // The same native ID is valid in the body's and frame's separate stories.
      final revised = fixture('9', '9');
      final report = WordDocumentComparison.compare(original, revised);
      expect(report.hasChanges, isFalse);
      _reconstruct(report);
    },
  );
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WordEditorController _controller({
  String text = 'aaXXbbYYccZZdd',
  String author = 'Quds Office',
  WmlDocument? document,
}) {
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: text),
    revisionAuthor: author,
  );
  addTearDown(controller.dispose);
  return controller;
}

WmlRevision _revision(
  WordEditorController controller,
  WmlParagraph paragraph,
  int start,
  int end, {
  WmlRevisionKind kind = WmlRevisionKind.insert,
  String author = 'Alice',
}) => WordRevisions.record(
  controller.document,
  kind: kind,
  paragraph: paragraph,
  // Deliberately use a body-like legacy index for auxiliary stories: the
  // captured paragraph identity must prevent redirecting to body text.
  paragraphIndex: 0,
  start: start,
  end: end,
  text: paragraph.text.substring(start, end),
  author: author,
);

void _at(WordEditorController controller, int offset, {int paragraph = 0}) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..collapseSelection();
}

class _ReviewProofingProvider extends OfficeProofingProvider {
  @override
  String get id => 'review-attribution-test';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final match in RegExp('Feler').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: 'spelling',
              message: 'Use Fehler.',
              category: OfficeProofingCategory.spelling,
              replacements: const ['Fehler'],
            ),
        ],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('author configuration trims names and rejects empty attribution', () {
    expect(_controller().revisionAuthor, 'Quds Office');
    final controller = _controller(author: '  Alice Example  ');
    expect(controller.revisionAuthor, 'Alice Example');
    controller.revisionAuthor = '  Bob Example\n';
    expect(controller.revisionAuthor, 'Bob Example');
    expect(() => controller.revisionAuthor = ' \t\n', throwsArgumentError);
    expect(controller.revisionAuthor, 'Bob Example');
    expect(
      () => WordEditorController(revisionAuthor: '\n'),
      throwsArgumentError,
    );
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
  });

  test('typing and deletion keep their original authors through history', () {
    final controller = _controller(text: 'Body', author: 'Alice');
    controller.document.trackRevisions = true;
    _at(controller, 4);
    controller.insertText(' added');
    final insertion = controller.document.revisions.single;
    expect(insertion.author, 'Alice');
    expect(insertion.text, ' added');

    controller.revisionAuthor = 'Bob';
    _at(controller, 0);
    controller.deleteSelectionOr(backward: false);
    final deletion = controller.document.revisions.last;
    expect(deletion.kind, WmlRevisionKind.delete);
    expect(deletion.author, 'Bob');
    expect(deletion.text, 'B');
    controller.revisionAuthor = 'Carol';
    controller.undo();
    expect(controller.document.revisions, [same(insertion)]);
    controller.redo();
    expect(controller.document.revisions, [same(insertion), same(deletion)]);
    expect(controller.document.revisions.map((r) => r.author), [
      'Alice',
      'Bob',
    ]);
    expect(controller.revisionAuthor, 'Carol');
  });

  test('hyperlink changes and fromBytes use the configured future author', () {
    final controller = _controller(text: 'Body', author: 'Alice');
    controller.document.trackRevisions = true;
    _at(controller, 4);
    controller.insertHyperlink(
      text: ' link',
      target: 'https://example.com/review',
    );
    expect(controller.document.revisions.single.author, 'Alice');
    final reopened = WordEditorController.fromBytes(
      controller.saveBytes(),
      revisionAuthor: ' Bob ',
    );
    addTearDown(reopened.dispose);
    expect(reopened.revisionAuthor, 'Bob');
    expect(reopened.document.revisions.single.author, 'Alice');
    _at(reopened, 0);
    reopened.insertText('New ');
    expect(reopened.document.revisions.map((r) => r.author), ['Alice', 'Bob']);
  });

  test(
    'proofing replacements attribute both tracked halves and redo',
    () async {
      final controller = _controller(text: 'A Feler.', author: 'Proofreader');
      controller.document.trackRevisions = true;
      controller.proofing.configure(
        OfficeProofingService(providers: [_ReviewProofingProvider()]),
      );
      final issue = (await controller.checkDocumentProofing()).issues.single;
      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
      final revisions = List<WmlRevision>.of(controller.document.revisions);
      expect(revisions.map((r) => r.kind), [
        WmlRevisionKind.delete,
        WmlRevisionKind.insert,
      ]);
      expect(revisions.map((r) => r.author), ['Proofreader', 'Proofreader']);
      expect(revisions.map((r) => r.text), ['Feler', 'Fehler']);
      controller.revisionAuthor = 'Next reviewer';
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'A Feler.');
      expect(controller.document.revisions, isEmpty);
      controller.redo();
      expect(controller.document.revisions, orderedEquals(revisions));
      expect(controller.document.revisions.map((r) => r.author), [
        'Proofreader',
        'Proofreader',
      ]);
    },
  );

  test(
    'accept filtered changes is one undo step and rebases the remainder',
    () {
      final controller = _controller();
      final paragraph = controller.document.paragraphs.single;
      final insertion = _revision(controller, paragraph, 2, 4);
      final deletion = _revision(
        controller,
        paragraph,
        6,
        8,
        kind: WmlRevisionKind.delete,
      );
      final remaining = _revision(controller, paragraph, 10, 12, author: 'Bob');
      controller.selectedRevisionIndex = 1;
      controller.acceptRevisions(
        controller.document.revisions.where((r) => r.author == 'Alice'),
      );
      expect(paragraph.text, 'aaXXbbccZZdd');
      expect(controller.document.revisions, [same(remaining)]);
      expect((remaining.start, remaining.end), (8, 10));
      expect(insertion.accepted, isTrue);
      expect(deletion.accepted, isTrue);
      expect(controller.selectedRevisionIndex, isNull);
      controller.undo();
      expect(paragraph.text, 'aaXXbbYYccZZdd');
      expect(controller.document.revisions, [
        same(insertion),
        same(deletion),
        same(remaining),
      ]);
      expect((remaining.start, remaining.end), (10, 12));
      expect(insertion.accepted, isNull);
      expect(deletion.accepted, isNull);
      expect(controller.selectedRevisionIndex, 1);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(paragraph.text, 'aaXXbbccZZdd');
      expect(controller.document.revisions, [same(remaining)]);
    },
  );

  test(
    'reject batch deduplicates targets and preserves a different author',
    () {
      final controller = _controller();
      final paragraph = controller.document.paragraphs.single;
      final first = _revision(controller, paragraph, 2, 4);
      final remaining = _revision(
        controller,
        paragraph,
        6,
        8,
        kind: WmlRevisionKind.delete,
        author: 'Bob',
      );
      final last = _revision(controller, paragraph, 10, 12);
      final foreign = _revision(
        _controller(text: 'Elsewhere'),
        _paragraph('Elsewhere'),
        0,
        4,
      );
      controller.rejectRevisions([first, foreign, last, first]);
      expect(paragraph.text, 'aabbYYccdd');
      expect(controller.document.revisions, [same(remaining)]);
      expect((remaining.start, remaining.end), (4, 6));
      controller.undo();
      expect(paragraph.text, 'aaXXbbYYccZZdd');
      expect(controller.document.revisions, [
        same(first),
        same(remaining),
        same(last),
      ]);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(paragraph.text, 'aabbYYccdd');
      final contentRevision = controller.contentRevision;
      controller.rejectRevisions([first, last, foreign]);
      controller.acceptRevisions(const []);
      expect(controller.contentRevision, contentRevision);
      expect(controller.document.revisions, [same(remaining)]);
    },
  );

  for (final accept in [true, false]) {
    test('${accept ? 'accept' : 'reject'} batch prevalidates every span', () {
      final controller = _controller(text: 'XX middle YY');
      final paragraph = controller.document.paragraphs.single;
      final stale = _revision(controller, paragraph, 0, 2);
      final valid = _revision(controller, paragraph, 10, 12);
      // An external model edit leaves a stale earlier span. The valid rightmost
      // change would be resolved first if the command skipped prevalidation.
      paragraph.inlines
        ..clear()
        ..add(WmlRun(text: 'XY middle YY'));
      controller.relayout();
      final contentRevision = controller.contentRevision;
      expect(
        () => accept
            ? controller.acceptRevisions([valid, stale])
            : controller.rejectRevisions([valid, stale]),
        throwsStateError,
      );
      expect(paragraph.text, 'XY middle YY');
      expect(controller.document.revisions, [same(stale), same(valid)]);
      expect(stale.accepted, isNull);
      expect(valid.accepted, isNull);
      expect(controller.contentRevision, contentRevision);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });
  }

  test('navigation starts at first or last pending and wraps exact spans', () {
    final firstParagraph = _paragraph('aaXXbb');
    final secondParagraph = _paragraph('ccYYdd');
    final resolvedParagraph = _paragraph('done');
    final controller = _controller(
      document: WmlDocument(
        sections: [
          WmlSection(
            blocks: [firstParagraph, secondParagraph, resolvedParagraph],
          ),
        ],
      ),
    );
    final first = _revision(controller, firstParagraph, 2, 4);
    final resolved = _revision(controller, resolvedParagraph, 0, 4)
      ..accepted = true;
    final last = _revision(controller, secondParagraph, 2, 4);
    expect(controller.selectedRevision, same(first));
    expect(controller.selectedRevisionIndex, isNull);
    controller.stepRevision(1);
    expect(controller.selectedRevision, same(first));
    expect(controller.selectedRevisionIndex, 0);
    expect(controller.caret.paragraphIndex, 0);
    expect(
      controller.input.value.selection,
      const TextSelection(baseOffset: 2, extentOffset: 4),
    );
    controller.stepRevision(1);
    expect(controller.selectedRevision, same(last));
    expect(controller.caret.paragraphIndex, 1);
    controller.stepRevision(1);
    expect(controller.selectedRevision, same(first));
    controller.stepRevision(-1);
    expect(controller.selectedRevision, same(last));
    controller.selectedRevisionIndex = null;
    controller.stepRevision(-1);
    expect(controller.selectedRevision, same(last));
    controller.stepRevision(0);
    expect(controller.selectedRevision, same(last));
    controller.selectedRevisionIndex = 99;
    controller.stepRevision(1);
    expect(controller.selectedRevision, same(first));
    controller.selectRevision(resolved);
    expect(controller.selectedRevisionIndex, isNull);
    expect(controller.canUndo, isFalse);
  });

  for (final story in ['header', 'footer', 'comment']) {
    test('$story revision selects the actual source and synchronizes IME', () {
      final body = _paragraph('same CHANGE body');
      final target = _paragraph('same CHANGE $story');
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [body]),
        ],
      );
      final paragraphs = [_paragraph('context'), target];
      if (story == 'comment') {
        document.comments.add(WmlComment(id: 7, paragraphs: paragraphs));
      } else if (story == 'footer') {
        document.sections.single.footer.addAll(paragraphs);
      } else {
        document.sections.single.header.addAll(paragraphs);
      }
      final controller = _controller(document: document);
      final revision = _revision(controller, target, 5, 11);
      expect(controller.revealRevision(revision), isTrue);
      expect(controller.selectedRevision, same(revision));
      expect(controller.caret.paragraphIndex, 1);
      expect(controller.caret.selectionAnchorParagraph, 1);
      expect(controller.caret.selectionAnchor, 5);
      expect(controller.caret.logicalIndex, 11);
      expect(controller.input.value.text, target.text);
      expect(
        controller.input.value.selection,
        const TextSelection(baseOffset: 5, extentOffset: 11),
      );
      if (story == 'comment') {
        expect(controller.isEditingComment, isTrue);
        expect(controller.selectedCommentId, 7);
      } else {
        expect(controller.isEditingHeaderFooter, isTrue);
        expect(controller.isEditingFooter, story == 'footer');
        expect(controller.headerFooterParagraphs[1], same(target));
      }
      expect(body.text, 'same CHANGE body');
      expect(controller.canUndo, isFalse);
    });
  }

  test(
    'notes and alternate headers never fall back to a matching body span',
    () {
      final controller = _controller(text: 'same CHANGE body');
      final section = controller.document.sections.single;
      final unsupported = [
        _paragraph('same CHANGE first header'),
        _paragraph('same CHANGE even header'),
        _paragraph('same CHANGE first footer'),
        _paragraph('same CHANGE even footer'),
        _paragraph('same CHANGE footnote'),
        _paragraph('same CHANGE endnote'),
      ];
      section.firstHeader.add(unsupported[0]);
      section.evenHeader.add(unsupported[1]);
      section.firstFooter.add(unsupported[2]);
      section.evenFooter.add(unsupported[3]);
      controller.document.footnotes.add(
        WmlNote(id: 1, endnote: false, paragraphs: [unsupported[4]]),
      );
      controller.document.endnotes.add(
        WmlNote(id: 2, endnote: true, paragraphs: [unsupported[5]]),
      );
      controller.relayout();
      _at(controller, 2);
      for (final paragraph in unsupported) {
        final revision = _revision(controller, paragraph, 5, 11);
        expect(controller.revealRevision(revision), isFalse);
        expect(controller.selectedRevision, same(revision));
        expect(controller.documentCaret.paragraphIndex, 0);
        expect(controller.documentCaret.logicalIndex, 2);
        expect(controller.documentCaret.selectionAnchor, 2);
        expect(controller.isEditingComment, isFalse);
        expect(controller.isEditingHeaderFooter, isFalse);
      }
      expect(controller.canUndo, isFalse);
    },
  );

  test('stale and detached targets do not move the body caret', () {
    final controller = _controller(text: 'same CHANGE body');
    final paragraph = controller.document.paragraphs.single;
    final revision = _revision(controller, paragraph, 5, 11);
    _at(controller, 2);
    revision.conflict = 'An overlapping edit changed attribution.';
    expect(controller.revealRevision(revision), isFalse);
    expect(controller.caret.logicalIndex, 2);
    revision.conflict = null;
    controller.document.sections.single.blocks
      ..clear()
      ..add(_paragraph('same CHANGE replacement'));
    controller.relayout();
    expect(controller.revealRevision(revision), isFalse);
    expect(controller.caret.logicalIndex, 2);
    expect(
      controller.document.paragraphs.single.text,
      'same CHANGE replacement',
    );
  });

  test('body revision navigation leaves object editing and another story', () {
    final body = _paragraph('same CHANGE body');
    final equation = WmlEquation(math: OmmlGallery.byId('quadratic').build());
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [body, equation], header: [_paragraph('header')]),
      ],
    );
    final controller = _controller(document: document);
    final revision = _revision(controller, body, 5, 11);
    controller.beginHeaderFooterEdit(0, footer: false);
    controller.selectRevision(revision);
    expect(controller.isEditingHeaderFooter, isFalse);
    expect(controller.input.value.text, body.text);
    controller.selectEquation(equation, caret: 1);
    expect(controller.revealRevision(revision), isTrue);
    expect(controller.selectedEquation, isNull);
    expect(controller.equationCaret, 0);
    expect(
      controller.input.value.selection,
      const TextSelection(baseOffset: 5, extentOffset: 11),
    );
    expect(controller.canUndo, isFalse);
  });

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test('$mode prevents review mutations and honors selection capability', () {
      final controller = _controller(text: 'Body');
      controller.document.trackRevisions = true;
      _at(controller, 4);
      controller.insertText(' added');
      final revision = controller.document.revisions.single;
      controller.setMode(mode);
      final contentRevision = controller.contentRevision;
      controller.setTrackRevisions(false);
      controller.acceptRevisions([revision]);
      controller.rejectRevisions([revision]);
      controller.acceptAllRevisions();
      controller.rejectAllRevisions();
      controller.undo();
      controller.redo();
      expect(controller.document.trackRevisions, isTrue);
      expect(controller.document.paragraphs.single.text, 'Body added');
      expect(controller.document.revisions, [same(revision)]);
      expect(controller.contentRevision, contentRevision);
      expect(controller.canUndo, isFalse);
      expect(
        controller.revealRevision(revision),
        mode == OfficeInteractionMode.selecting,
      );
      expect(controller.selectedRevision, same(revision));
      expect(controller.contentRevision, contentRevision);
    });
  }

  test(
    'comparison in viewing mode changes neither document nor controller state',
    () {
      final original = _controller(text: 'before');
      final originalParagraph = original.document.paragraphs.single;
      _revision(original, originalParagraph, 0, 6, author: 'Original');
      final controller = _controller(text: 'after plus');
      final paragraph = controller.document.paragraphs.single;
      final revision = _revision(controller, paragraph, 5, 10);
      controller.setMode(OfficeInteractionMode.viewing);
      final beforeOriginal = WordRevisions.capture(original.document);
      final beforeRevised = WordRevisions.capture(controller.document);
      final beforeContentRevision = controller.contentRevision;
      var notifications = 0;
      controller.addListener(() => notifications++);
      const options = WordComparisonOptions(
        revisionView: WordComparisonRevisionView.markup,
        ignoreCase: true,
      );
      final result = controller.compareWith(
        original.document,
        options: options,
      );
      expect(result.hasChanges, isTrue);
      expect(result.options, same(options));
      expect(original.document.paragraphs.single, same(originalParagraph));
      expect(controller.document.paragraphs.single, same(paragraph));
      expect(originalParagraph.text, 'before');
      expect(paragraph.text, 'after plus');
      expect(controller.document.revisions.single, same(revision));
      expect(beforeOriginal.matches(original.document), isTrue);
      expect(beforeRevised.matches(controller.document), isTrue);
      expect(controller.contentRevision, beforeContentRevision);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.selectedRevisionIndex, isNull);
      expect(notifications, 0);
    },
  );
}

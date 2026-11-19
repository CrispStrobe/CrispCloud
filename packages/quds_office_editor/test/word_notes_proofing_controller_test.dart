import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _NotesProvider extends OfficeProofingProvider {
  _NotesProvider(
    this.id, {
    this.findErrors = true,
    this.category = OfficeProofingCategory.spelling,
    this.originalText = 'Feler',
    this.replacement = 'Fehler',
  });

  @override
  final String id;
  final bool findErrors;
  final OfficeProofingCategory category;
  final String originalText;
  final String replacement;
  final requests = <OfficeProofingRequest>[];

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        if (findErrors)
          for (final match in RegExp(
            RegExp.escape(originalText),
          ).allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: '$id-rule',
              message: 'Use $replacement.',
              category: category,
              replacements: [replacement],
            ),
      ],
    );
  }
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

({WordEditorController controller, WmlNote note}) _fixture({
  bool endnote = false,
  bool hiddenReferenceSpace = true,
  String text = 'Feler',
  String body = 'Body text',
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
  bool protected = false,
  _NotesProvider? ordinary,
  _NotesProvider? manual,
}) {
  final lines = text.split('\n');
  final note = WmlNote(
    id: 1,
    endnote: endnote,
    addReference: hiddenReferenceSpace,
    addReferenceSpace: hiddenReferenceSpace,
    paragraphs: [
      for (var index = 0; index < lines.length; index++)
        _paragraph(
          '${index == 0 && hiddenReferenceSpace ? ' ' : ''}${lines[index]}',
        ),
    ],
  );
  final document = WmlDocument.empty(text: body)
    ..proofingLanguage = 'de-DE'
    ..restrictEditing = protected;
  (endnote ? document.endnotes : document.footnotes).add(note);
  final controller = WordEditorController(
    document: document,
    config: OfficeSurfaceConfig(mode: mode),
    proofingService: OfficeProofingService(
      providers: [ordinary ?? _NotesProvider('ordinary')],
    ),
    revisionAuthor: 'Notes reviewer',
  );
  if (manual != null) {
    controller.proofing.configureManual(
      OfficeProofingService(providers: [manual]),
    );
  }
  addTearDown(controller.dispose);
  return (controller: controller, note: note);
}

Future<WordProofingIssue> _issue(
  WordEditorController controller,
  WmlNote note,
) async {
  await controller.checkDocumentProofing();
  return controller.proofingIssuesForNote(note).single.issue;
}

void _bodyAt(WordEditorController controller, int offset, {int? anchor}) {
  controller.caret
    ..paragraphIndex = 0
    ..logicalIndex = offset
    ..selectionAnchor = anchor ?? offset
    ..selectionAnchorParagraph = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final endnote in [false, true]) {
    for (final hidden in [false, true]) {
      test('${endnote ? 'endnote' : 'footnote'} maps UTF-16 multiline findings '
          'with hidden reference space $hidden', () async {
        const text = '😀 Feler\nline Feler';
        final fixture = _fixture(
          endnote: endnote,
          hiddenReferenceSpace: hidden,
          text: text,
        );
        final controller = fixture.controller;
        final note = fixture.note;
        await controller.checkDocumentProofing();

        expect(controller.noteEditText(note), text);
        final entries = controller.proofingIssuesForNote(note);
        expect(entries.map((entry) => entry.range), [
          const TextRange(start: 3, end: 8),
          const TextRange(start: 14, end: 19),
        ]);
        expect(entries.first.issue.paragraph, same(note.paragraphs.first));
        expect(entries.last.issue.paragraph, same(note.paragraphs.last));
        expect(entries.first.issue.finding.start, hidden ? 4 : 3);
        for (final entry in entries) {
          expect(entry.range.textInside(text), 'Feler');
          expect(
            controller.currentNoteProofingIssue(note, entry.issue),
            same(entry.issue),
          );
        }
        final foreign = WmlNote(
          id: note.id,
          endnote: endnote,
          paragraphs: [_paragraph(text)],
        );
        expect(controller.proofingIssuesForNote(foreign), isEmpty);
        expect(
          controller.currentNoteProofingIssue(foreign, entries.first.issue),
          isNull,
        );
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
      });
    }

    test('${endnote ? 'endnote' : 'footnote'} reveal focuses the editable note '
        'without changing body selection or history', () async {
      final fixture = _fixture(endnote: endnote, text: 'First line\n😀 Feler');
      final controller = fixture.controller;
      final note = fixture.note;
      _bodyAt(controller, 4, anchor: 1);
      final issue = await _issue(controller, note);
      var bodyFocusRequests = 0;
      controller.onRequestFocus = () => bodyFocusRequests++;
      final revision = controller.contentRevision;
      final focusRequest = controller.noteFocusRequest;

      expect(controller.revealProofingIssue(issue), isTrue);
      expect(controller.noteEditingTarget?.note, same(note));
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection(baseOffset: 14, extentOffset: 19),
      );
      expect(controller.config.showNotesPane, isTrue);
      expect(controller.noteFocusRequest, focusRequest + 1);
      expect(bodyFocusRequests, 0);
      expect(controller.caret.logicalIndex, 4);
      expect(controller.caret.selectionAnchor, 1);
      expect(controller.selectedProofingIssue, same(issue));
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);

      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 15),
      );
      expect(controller.proofingIssuesAtCaret, [same(issue)]);
      controller.openReviewPane();
      controller.closeReviewPane();
      expect(controller.noteFocusRequest, focusRequest + 2);
      expect(bodyFocusRequests, 0);
    });

    test('${endnote ? 'endnote' : 'footnote'} correction restores actual note '
        'selection through undo and redo', () async {
      final fixture = _fixture(endnote: endnote, text: 'aFelerz');
      final controller = fixture.controller;
      final note = fixture.note;
      _bodyAt(controller, 3, anchor: 1);
      const before = TextSelection(baseOffset: 6, extentOffset: 1);
      controller.setNoteEditingTarget(note, before);
      final issue = await _issue(controller, note);

      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
      expect(controller.noteEditText(note), 'aFehlerz');
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection.collapsed(offset: 7),
      );
      expect(controller.caret.logicalIndex, 3);
      expect(controller.caret.selectionAnchor, 1);
      controller.undo();
      expect(controller.noteEditText(note), 'aFelerz');
      expect(controller.noteEditingTarget?.selection, before);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.noteEditText(note), 'aFehlerz');
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection.collapsed(offset: 7),
      );
      expect(controller.caret.logicalIndex, 3);
      expect(controller.caret.selectionAnchor, 1);
    });

    test('${endnote ? 'endnote' : 'footnote'} tracked corrections and change '
        'navigation use note ranges', () async {
      final fixture = _fixture(endnote: endnote, text: 'a Feler.');
      final controller = fixture.controller;
      final note = fixture.note;
      controller.document.trackRevisions = true;
      controller.setNoteEditingTarget(
        note,
        const TextSelection(baseOffset: 2, extentOffset: 7),
      );
      final issue = await _issue(controller, note);

      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
      expect(controller.noteEditText(note), 'a FelerFehler.');
      final revisions = List<WmlRevision>.of(controller.document.revisions);
      expect(revisions.map((revision) => revision.kind), [
        WmlRevisionKind.delete,
        WmlRevisionKind.insert,
      ]);
      expect(revisions.map((revision) => revision.author), [
        'Notes reviewer',
        'Notes reviewer',
      ]);
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection.collapsed(offset: 13),
      );
      controller.clearNoteEditingTarget();
      expect(controller.revealRevision(revisions.last), isTrue);
      expect(controller.noteEditingTarget?.note, same(note));
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection(baseOffset: 7, extentOffset: 13),
      );
      controller.undo();
      expect(controller.noteEditText(note), 'a Feler.');
      expect(controller.document.revisions, isEmpty);
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection(baseOffset: 2, extentOffset: 7),
      );
      controller.redo();
      expect(controller.noteEditText(note), 'a FelerFehler.');
      expect(controller.document.revisions, orderedEquals(revisions));
    });
  }

  test(
    'note tables remain checked but are not mapped to the plain editor',
    () async {
      final fixture = _fixture(text: 'Feler');
      final controller = fixture.controller;
      final note = fixture.note;
      final tableParagraph = _paragraph('Feler in a table');
      note.blocks.add(
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [tableParagraph]),
              ],
            ),
          ],
        ),
      );
      final summary = await controller.checkDocumentProofing();
      final tableIssue = summary.issues.singleWhere(
        (issue) => identical(issue.paragraph, tableParagraph),
      );
      expect(controller.proofingIssuesForNote(note), hasLength(1));
      expect(controller.noteEditText(note), 'Feler');
      expect(controller.currentNoteProofingIssue(note, tableIssue), isNull);
      expect(controller.revealProofingIssue(tableIssue), isFalse);
      expect(controller.noteEditingTarget, isNull);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'explicit note selection survives an adjacent finding endpoint',
    () async {
      final fixture = _fixture(text: 'FelerFeler');
      final controller = fixture.controller;
      final note = fixture.note;
      await controller.checkDocumentProofing();
      final entries = controller.proofingIssuesForNote(note);
      final first = entries.first.issue;
      final second = entries.last.issue;

      expect(controller.selectProofingIssue(first), isTrue);
      expect(controller.proofingIssuesAtCaret, [same(second)]);
      expect(controller.selectedProofingIssue, same(first));
      controller.refreshView();
      expect(controller.selectedProofingIssue, same(first));
      controller.stepProofingIssue(1);
      expect(controller.selectedProofingIssue, same(second));
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection(baseOffset: 5, extentOffset: 10),
      );
    },
  );

  for (final focusLossFirst in [false, true]) {
    test('typed note correction survives an unchanged history boundary '
        '(focus loss first: $focusLossFirst)', () async {
      final fixture = _fixture(text: 'Before');
      final controller = fixture.controller;
      final note = fixture.note;
      controller.setNoteText(note, 'Feler typed');
      controller.setNoteEditingTarget(
        note,
        const TextSelection(baseOffset: 5, extentOffset: 0),
      );
      final captured = await _issue(controller, note);
      expect(controller.canUndo, isFalse);
      if (focusLossFirst) {
        controller.commitNoteEdit(note);
        final current = controller.currentNoteProofingIssue(note, captured);
        expect(current, isNotNull);
        expect(current, isNot(same(captured)));
        expect(controller.proofing.isCurrent(captured), isFalse);
        expect(controller.proofing.isCurrent(current!), isTrue);
      }
      expect(controller.applyProofingSuggestion(captured, 'Fehler'), isTrue);
      expect(controller.noteEditText(note), 'Fehler typed');
      controller.undo();
      expect(controller.noteEditText(note), 'Feler typed');
      expect(
        controller.noteEditingTarget?.selection,
        const TextSelection(baseOffset: 5, extentOffset: 0),
      );
      controller.undo();
      expect(controller.noteEditText(note), 'Before');
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.noteEditText(note), 'Feler typed');
      controller.redo();
      expect(controller.noteEditText(note), 'Fehler typed');
    });

    test('manual findings survive only the unchanged note history boundary '
        'without provider calls (focus loss first: $focusLossFirst)', () async {
      final ordinary = _NotesProvider('ordinary', findErrors: false);
      final manual = _NotesProvider(
        'manual',
        category: OfficeProofingCategory.grammar,
      );
      final fixture = _fixture(
        text: 'Before',
        ordinary: ordinary,
        manual: manual,
      );
      final controller = fixture.controller;
      final note = fixture.note;
      controller.setNoteText(note, 'Feler typed');
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 3),
      );
      final captured = await _issue(controller, note);
      expect(captured.finding.providerId, 'manual');
      expect(controller.proofing.summary.complete, isTrue);
      final manualCalls = manual.requests.length;
      final ordinaryCalls = ordinary.requests.length;
      if (focusLossFirst) {
        controller.commitNoteEdit(note);
        expect(controller.currentNoteProofingIssue(note, captured), isNotNull);
        expect(controller.proofing.summary.complete, isTrue);
        expect(controller.proofing.summary.manualProvidersSkipped, isFalse);
      }
      expect(controller.applyProofingSuggestion(captured, 'Fehler'), isTrue);
      expect(controller.noteEditText(note), 'Fehler typed');
      expect(manual.requests, hasLength(manualCalls));
      expect(ordinary.requests, hasLength(ordinaryCalls));
      expect(controller.currentNoteProofingIssue(note, captured), isNull);
      controller.undo();
      expect(controller.noteEditText(note), 'Feler typed');
      expect(controller.currentNoteProofingIssue(note, captured), isNull);
      expect(manual.requests, hasLength(manualCalls));
    });
  }

  for (final correctedProvider in ['ordinary', 'manual']) {
    test('mixed provider history commit retains the ordinary issue identity '
        'before correcting the $correctedProvider finding', () async {
      final ordinary = _NotesProvider('ordinary');
      final manual = _NotesProvider(
        'manual',
        category: OfficeProofingCategory.grammar,
        originalText: 'Gramatik',
        replacement: 'Grammatik',
      );
      final fixture = _fixture(
        text: 'Before',
        ordinary: ordinary,
        manual: manual,
      );
      final controller = fixture.controller;
      final note = fixture.note;
      // Manual findings must be disjoint from ordinary findings: report
      // merging intentionally suppresses overlapping secondary proposals.
      controller.setNoteText(note, 'Feler Gramatik typed');
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 3),
      );
      await controller.checkDocumentProofing();
      final captured = controller
          .proofingIssuesForNote(note)
          .map((entry) => entry.issue)
          .toList();
      // Exercise the ordinary-first order: its alias is collected before
      // the manual finding causes cached manual reports to be republished.
      expect(captured.map((issue) => issue.finding.providerId), [
        'ordinary',
        'manual',
      ]);
      expect(captured.map((issue) => issue.finding.originalText), [
        'Feler',
        'Gramatik',
      ]);
      final ordinaryCalls = ordinary.requests.length;
      final manualCalls = manual.requests.length;
      final beforeCommit = controller.contentRevision;
      WordProofingIssue? ordinaryBeforeManual;
      controller.addListener(() {
        if (controller.contentRevision == beforeCommit + 1 &&
            controller.proofing.summary.manualProvidersSkipped) {
          ordinaryBeforeManual ??= controller.proofing.summary.issues
              .where((issue) => issue.finding.providerId == 'ordinary')
              .firstOrNull;
        }
      });

      controller.commitNoteEdit(note);
      expect(ordinaryBeforeManual, isNotNull);
      final rebound = [
        for (final issue in captured)
          controller.currentNoteProofingIssue(note, issue),
      ];
      expect(rebound, everyElement(isNotNull));
      expect(rebound.first, same(ordinaryBeforeManual));
      for (final issue in rebound) {
        expect(controller.proofing.isCurrent(issue!), isTrue);
      }
      expect(controller.proofing.summary.complete, isTrue);
      expect(ordinary.requests, hasLength(ordinaryCalls));
      expect(manual.requests, hasLength(manualCalls));

      final chosen = captured.singleWhere(
        (issue) => issue.finding.providerId == correctedProvider,
      );
      final replacement = correctedProvider == 'ordinary'
          ? 'Fehler'
          : 'Grammatik';
      expect(controller.applyProofingSuggestion(chosen, replacement), isTrue);
      expect(
        controller.noteEditText(note),
        correctedProvider == 'ordinary'
            ? 'Fehler Gramatik typed'
            : 'Feler Grammatik typed',
      );
      expect(ordinary.requests, hasLength(ordinaryCalls));
      expect(manual.requests, hasLength(manualCalls));
      expect(controller.currentNoteProofingIssue(note, chosen), isNull);
    });
  }

  for (final mutation in ['note', 'body', 'history', 'provider', 'detach']) {
    test('history aliases retire after a real $mutation change', () async {
      final fixture = _fixture(text: 'Before');
      final controller = fixture.controller;
      final note = fixture.note;
      controller.setNoteText(note, 'Feler typed');
      final captured = await _issue(controller, note);
      controller.commitNoteEdit(note);
      expect(controller.currentNoteProofingIssue(note, captured), isNotNull);
      switch (mutation) {
        case 'note':
          controller.setNoteText(note, 'Feler changed');
        case 'body':
          controller.clearNoteEditingTarget();
          _bodyAt(controller, 0);
          controller.insertText('New ');
        case 'history':
          controller.undo();
          controller.redo();
          expect(controller.noteEditText(note), 'Feler typed');
        case 'provider':
          controller.proofing.configure(
            OfficeProofingService(providers: [_NotesProvider('new-provider')]),
          );
        case 'detach':
          controller.document.footnotes.remove(note);
      }
      expect(controller.currentNoteProofingIssue(note, captured), isNull);
      expect(controller.applyProofingSuggestion(captured, 'Fehler'), isFalse);
    });
  }

  test(
    'unobserved note source changes cannot move focus or apply stale text',
    () async {
      final fixture = _fixture(text: 'Feler');
      final controller = fixture.controller;
      final note = fixture.note;
      final captured = await _issue(controller, note);
      note.paragraphs.single.inlines
        ..clear()
        ..add(WmlRun(text: ' Changed source'));
      final revision = controller.contentRevision;
      final focus = controller.noteFocusRequest;
      expect(controller.proofingIssuesForNote(note), isEmpty);
      expect(controller.currentNoteProofingIssue(note, captured), isNull);
      expect(controller.revealProofingIssue(captured), isFalse);
      expect(controller.applyProofingSuggestion(captured, 'Fehler'), isFalse);
      expect(controller.noteFocusRequest, focus);
      expect(controller.noteEditingTarget, isNull);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
    },
  );

  for (final mode in [
    OfficeInteractionMode.selecting,
    OfficeInteractionMode.viewing,
  ]) {
    test('$mode permits only its configured Notes review actions', () async {
      final fixture = _fixture(mode: mode);
      final controller = fixture.controller;
      final note = fixture.note;
      final issue = await _issue(controller, note);
      expect(
        controller.revealProofingIssue(issue),
        mode == OfficeInteractionMode.selecting,
      );
      expect(controller.canApplyProofingSuggestions, isFalse);
      expect(controller.canApplyProofingIssue(issue), isFalse);
      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isFalse);
      controller.setNoteText(note, 'Edited');
      expect(controller.noteEditText(note), 'Feler');
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });
  }

  test('document protection blocks note correction and navigation', () async {
    final fixture = _fixture(protected: true);
    final controller = fixture.controller;
    final note = fixture.note;
    final issue = await _issue(controller, note);
    expect(controller.mode, OfficeInteractionMode.viewing);
    expect(controller.revealProofingIssue(issue), isFalse);
    expect(controller.applyProofingSuggestion(issue, 'Fehler'), isFalse);
    expect(controller.noteEditingTarget, isNull);
    expect(controller.noteEditText(note), 'Feler');
    expect(controller.canUndo, isFalse);
  });

  for (final tracking in [false, true]) {
    test(
      'note IME blocks correction and reveals before committing pending text '
      'with tracking $tracking',
      () async {
        final fixture = _fixture(text: 'Before');
        final controller = fixture.controller;
        final note = fixture.note;
        final body = controller.document.paragraphs.single;
        final revision = WordRevisions.record(
          controller.document,
          kind: WmlRevisionKind.insert,
          paragraph: body,
          paragraphIndex: 0,
          start: 0,
          end: 4,
          text: 'Body',
          author: 'Reviewer',
        );
        // Seeding the navigation target enables tracking; exercise both normal
        // correction and preservation of tracked replacement spans after IME.
        controller.document.trackRevisions = tracking;
        controller.setNoteText(note, 'Feler typed');
        final issue = await _issue(controller, note);
        controller.setNoteEditingTarget(
          note,
          const TextSelection.collapsed(offset: 5),
          composing: const TextRange(start: 0, end: 5),
        );
        final contentRevision = controller.contentRevision;
        final target = controller.noteEditingTarget;
        final focus = controller.noteFocusRequest;
        expect(controller.canApplyProofingSuggestions, isFalse);
        expect(controller.applyProofingSuggestion(issue, 'Fehler'), isFalse);
        expect(controller.revealProofingIssue(issue), isFalse);
        expect(controller.revealRevision(revision), isFalse);
        expect(controller.noteEditingTarget, target);
        expect(controller.noteFocusRequest, focus);
        expect(controller.contentRevision, contentRevision);
        expect(controller.canUndo, isFalse);

        controller.setNoteEditingTarget(
          note,
          const TextSelection.collapsed(offset: 5),
        );
        expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
        expect(controller.document.trackRevisions, tracking);
        expect(
          controller.noteEditText(note),
          tracking ? 'FelerFehler typed' : 'Fehler typed',
        );
        final changes = controller.document.revisions
            .where(
              (change) => identical(
                WordRevisions.resolveParagraph(controller.document, change),
                note.paragraphs.single,
              ),
            )
            .toList();
        if (tracking) {
          // A tracked correction retains both deleted and inserted spans.
          expect(controller.document.revisions, hasLength(3));
          expect(controller.document.revisions.first, same(revision));
          expect(changes.map((change) => change.kind), [
            WmlRevisionKind.delete,
            WmlRevisionKind.insert,
          ]);
          expect(changes.map((change) => change.text), ['Feler', 'Fehler']);
        } else {
          expect(changes, isEmpty);
          expect(controller.document.revisions, [revision]);
        }
        controller.undo();
        expect(controller.noteEditText(note), 'Feler typed');
        expect(controller.document.revisions, [revision]);
        controller.undo();
        expect(controller.noteEditText(note), 'Before');
        expect(controller.document.revisions, [revision]);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test('canvas IME also prevents retargeting review into a note', () async {
    final fixture = _fixture();
    final controller = fixture.controller;
    final issue = await _issue(controller, fixture.note);
    controller.input.setValue(
      const TextEditingValue(
        text: 'Body text',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    expect(controller.canApplyProofingSuggestions, isFalse);
    expect(controller.revealProofingIssue(issue), isFalse);
    expect(controller.applyProofingSuggestion(issue, 'Fehler'), isFalse);
    expect(controller.noteEditingTarget, isNull);
    expect(controller.canUndo, isFalse);
  });

  for (final otherStory in ['body', 'other note']) {
    test(
      'note correction history preserves a later $otherStory selection',
      () async {
        final fixture = _fixture(text: 'Feler');
        final controller = fixture.controller;
        final note = fixture.note;
        final other = WmlNote(
          id: 2,
          endnote: true,
          addReference: false,
          paragraphs: [_paragraph('Another note')],
        );
        controller.document.endnotes.add(other);
        controller.setNoteEditingTarget(
          note,
          const TextSelection.collapsed(offset: 2),
        );
        final issue = await _issue(controller, note);
        expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
        const otherSelection = TextSelection(baseOffset: 7, extentOffset: 2);
        if (otherStory == 'body') {
          controller.clearNoteEditingTarget();
          _bodyAt(controller, 4, anchor: 1);
        } else {
          controller.setNoteEditingTarget(other, otherSelection);
        }
        controller.undo();
        expect(controller.noteEditText(note), 'Feler');
        if (otherStory == 'body') {
          expect(controller.noteEditingTarget, isNull);
          expect(controller.caret.logicalIndex, 4);
          expect(controller.caret.selectionAnchor, 1);
        } else {
          expect(controller.noteEditingTarget?.note, same(other));
          expect(controller.noteEditingTarget?.selection, otherSelection);
        }
        controller.redo();
        expect(controller.noteEditText(note), 'Fehler');
        if (otherStory == 'body') {
          expect(controller.noteEditingTarget, isNull);
          expect(controller.caret.logicalIndex, 4);
          expect(controller.caret.selectionAnchor, 1);
        } else {
          expect(controller.noteEditingTarget?.note, same(other));
          expect(controller.noteEditingTarget?.selection, otherSelection);
        }
      },
    );
  }

  test(
    'body corrections preserve a retained Notes selection through history',
    () async {
      final fixture = _fixture(text: 'A note', body: 'Body Feler');
      final controller = fixture.controller;
      final note = fixture.note;
      final summary = await controller.checkDocumentProofing();
      final issue = summary.issues.single;
      const selection = TextSelection(baseOffset: 5, extentOffset: 1);
      controller.setNoteEditingTarget(note, selection);
      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
      expect(controller.document.paragraphs.single.text, 'Body Fehler');
      expect(controller.noteEditingTarget?.selection, selection);
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Body Feler');
      expect(controller.noteEditingTarget?.selection, selection);
      controller.redo();
      expect(controller.document.paragraphs.single.text, 'Body Fehler');
      expect(controller.noteEditingTarget?.selection, selection);
    },
  );

  test('Notes proofing does not manufacture a body thesaurus target', () async {
    final fixture = _fixture(text: 'Feler', body: 'A useful word');
    final controller = fixture.controller;
    final note = fixture.note;
    _bodyAt(controller, 4);
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 2),
    );
    await controller.checkDocumentProofing();
    expect(controller.proofingIssuesAtCaret, hasLength(1));
    expect(
      controller.captureThesaurusTarget().status,
      WordThesaurusTargetStatus.unsupportedTarget,
    );
    expect(controller.noteEditingTarget?.note, same(note));
    expect(controller.document.paragraphs.single.text, 'A useful word');
    expect(controller.canUndo, isFalse);
  });

  for (final endnote in [false, true]) {
    for (final hidden in [false, true]) {
      test('Notes language maps reversed multiline UTF-16 selection '
          '(endnote: $endnote, hidden separator: $hidden)', () {
        final (:controller, :note) = _fixture(
          endnote: endnote,
          hiddenReferenceSpace: hidden,
          text: '😀 Feler\nSecond line',
        );
        _bodyAt(controller, 4, anchor: 1);
        const selection = TextSelection(baseOffset: 15, extentOffset: 3);
        controller.setNoteEditingTarget(note, selection);
        final target = controller.textProofingTarget!;
        expect(target.canEdit, isTrue);
        expect(target.isSelection, isTrue);
        expect(target.language, 'de-DE');
        expect(
          controller.setTextProofingLanguage('en-US', target: target),
          isTrue,
        );
        final first = note.paragraphs.first.inlines
            .whereType<WmlRun>()
            .toList();
        final second = note.paragraphs.last.inlines
            .whereType<WmlRun>()
            .toList();
        expect(first.map((run) => run.text), [
          hidden ? ' 😀 ' : '😀 ',
          'Feler',
        ]);
        expect(first.map((run) => run.properties.proofingLanguage), [
          null,
          'en-US',
        ]);
        expect(second.map((run) => run.text), ['Second', ' line']);
        expect(second.map((run) => run.properties.proofingLanguage), [
          'en-US',
          null,
        ]);
        expect(
          controller.document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .every((run) => run.properties.proofingLanguage == null),
          isTrue,
        );
        expect(controller.noteEditingTarget?.selection, selection);
        expect(controller.caret.logicalIndex, 4);
        expect(controller.caret.selectionAnchor, 1);
        controller.undo();
        expect(
          note.allParagraphs
              .expand((paragraph) => paragraph.inlines)
              .whereType<WmlRun>()
              .every((run) => run.properties.proofingLanguage == null),
          isTrue,
        );
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(controller.textProofingTarget?.language, 'en-US');
        expect(controller.noteEditingTarget?.selection, selection);
      });
    }
  }

  test(
    'Notes paragraph checking excludes hidden separator and nested table',
    () {
      final (:controller, :note) = _fixture(text: 'Feler');
      final tableParagraph = _paragraph('Table text');
      note.blocks.add(
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [tableParagraph]),
              ],
            ),
          ],
        ),
      );
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 2),
      );
      final target = controller.textProofingTarget!;
      expect(target.isSelection, isFalse);
      expect(controller.setTextProofingEnabled(false, target: target), isTrue);
      final runs = note.paragraphs.single.inlines.whereType<WmlRun>().toList();
      expect(runs.map((run) => run.text), [' ', 'Feler']);
      expect(runs.map((run) => run.properties.noProof), [null, true]);
      expect(
        tableParagraph.inlines.whereType<WmlRun>().single.properties.noProof,
        isNull,
      );
      expect(
        controller.document.paragraphs.single.inlines.whereType<WmlRun>().every(
          (run) => run.properties.noProof == null,
        ),
        isTrue,
      );
      controller.undo();
      expect(controller.textProofingTarget?.checkingEnabled, isTrue);
      controller.redo();
      expect(controller.textProofingTarget?.checkingEnabled, isFalse);
    },
  );

  test('Notes text options retain native block protection', () {
    final (:controller, :note) = _fixture();
    final paragraphs = List<WmlParagraph>.of(note.paragraphs);
    note.blocks
      ..clear()
      ..add(
        WmlContentControlBlock(
          control: WmlContentControlData(
            xml:
                '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
                '<w:id w:val="42"/><w:lock w:val="contentLocked"/>'
                '</w:sdtPr><w:sdtContent/></w:sdt>',
            sourcePartUri: '/word/footnotes.xml',
            relationships: const [],
          ),
          blocks: paragraphs,
        ),
      );
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 2),
    );
    final target = controller.textProofingTarget!;
    expect(target.canEdit, isFalse);
    expect(target.unavailableReason, contains('protected content control'));
    expect(
      controller.setTextProofingLanguage('en-US', target: target),
      isFalse,
    );
    expect(controller.setTextProofingEnabled(false, target: target), isFalse);
    expect(controller.canUndo, isFalse);
  });

  for (final change in ['selection', 'body', 'detach', 'composition']) {
    test(
      'retained Notes text options reject $change without changing the body',
      () {
        final (:controller, :note) = _fixture();
        controller.setNoteEditingTarget(
          note,
          const TextSelection.collapsed(offset: 2),
        );
        final target = controller.textProofingTarget!;
        switch (change) {
          case 'selection':
            controller.setNoteEditingTarget(
              note,
              const TextSelection.collapsed(offset: 3),
            );
          case 'body':
            controller.clearNoteEditingTarget();
          case 'detach':
            controller.document.footnotes.remove(note);
          case 'composition':
            controller.setNoteEditingTarget(
              note,
              const TextSelection.collapsed(offset: 2),
              composing: const TextRange(start: 0, end: 5),
            );
            expect(controller.textProofingTarget?.canEdit, isFalse);
        }
        expect(
          controller.setTextProofingLanguage('en-US', target: target),
          isFalse,
        );
        expect(
          controller.setTextProofingEnabled(false, target: target),
          isFalse,
        );
        expect(
          controller.document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .every(
                (run) =>
                    run.properties.proofingLanguage == null &&
                    run.properties.noProof == null,
              ),
          isTrue,
        );
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );
  }

  test(
    'committed Notes typing uses Notes text options instead of the body',
    () {
      final (:controller, :note) = _fixture(text: 'Before');
      controller.setNoteText(note, 'Typed note');
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 5),
      );
      expect(controller.textProofingTarget, isNull);
      controller.commitNoteEdit(note);
      final target = controller.textProofingTarget!;
      expect(
        controller.setTextProofingLanguage('en-US', target: target),
        isTrue,
      );
      expect(
        note.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((run) => run.text.trim().isNotEmpty)
            .every((run) => run.properties.proofingLanguage == 'en-US'),
        isTrue,
      );
      controller.undo();
      expect(controller.noteEditText(note), 'Typed note');
      controller.undo();
      expect(controller.noteEditText(note), 'Before');
      expect(
        controller.document.paragraphs.single.inlines.whereType<WmlRun>().every(
          (run) => run.properties.proofingLanguage == null,
        ),
        isTrue,
      );
    },
  );

  test(
    'clean manual coverage survives unchanged Notes history and debounce',
    () async {
      final ordinary = _NotesProvider('ordinary', findErrors: false);
      final manual = _NotesProvider('manual', findErrors: false);
      final (:controller, :note) = _fixture(
        text: 'Before',
        ordinary: ordinary,
        manual: manual,
      );
      controller.proofing.enabled = true;
      controller.setNoteText(note, 'A clean typed note');
      await controller.checkDocumentProofing();
      expect(controller.proofing.summary.complete, isTrue);
      expect(controller.proofing.summary.issues, isEmpty);
      final ordinaryCalls = ordinary.requests.length;
      final manualCalls = manual.requests.length;
      controller.commitNoteEdit(note);
      expect(controller.proofing.summary.complete, isTrue);
      expect(controller.proofing.summary.manualProvidersSkipped, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(controller.proofing.summary.complete, isTrue);
      expect(controller.proofing.summary.manualProvidersSkipped, isFalse);
      expect(ordinary.requests, hasLength(ordinaryCalls));
      expect(manual.requests, hasLength(manualCalls));
      controller.setNoteText(note, 'A changed note needs a fresh check');
      expect(controller.proofing.summary.complete, isFalse);
      expect(controller.proofing.summary.manualProvidersSkipped, isTrue);
      expect(manual.requests, hasLength(manualCalls));
    },
  );
}

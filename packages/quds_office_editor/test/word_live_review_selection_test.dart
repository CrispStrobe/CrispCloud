import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _ReviewProvider extends OfficeProofingProvider {
  _ReviewProvider(this.id, {this.findErrors = true});

  @override
  final String id;
  final bool findErrors;
  final requests = <OfficeProofingRequest>[];
  final started = Completer<void>();
  final secondStarted = Completer<void>();
  Completer<void>? gate;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    if (requests.length == 2) secondStarted.complete();
    await gate?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        if (findErrors)
          for (final match in RegExp('Feler').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: '$id-spelling',
              message: 'Use Fehler.',
              category: OfficeProofingCategory.spelling,
              replacements: const ['Fehler'],
            ),
      ],
    );
  }
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WordEditorController _controller(
  WmlDocument document, {
  _ReviewProvider? ordinary,
  _ReviewProvider? manual,
}) {
  final controller = WordEditorController(
    document: document,
    proofingService: OfficeProofingService(
      providers: [ordinary ?? _ReviewProvider('ordinary')],
    ),
  );
  if (manual != null) {
    controller.proofing.configureManual(
      OfficeProofingService(providers: [manual]),
    );
  }
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final story in ['first header', 'even footer']) {
    test(
      'explicit $story selection survives an unchanged body caret',
      () async {
        final document = WmlDocument.empty(text: 'Feler in body');
        final unsupported = _paragraph('Feler in $story');
        switch (story) {
          case 'footnote':
            document.footnotes.add(
              WmlNote(id: 1, endnote: false, paragraphs: [unsupported]),
            );
          case 'first header':
            document.sections.single.firstHeader.add(unsupported);
          case 'even footer':
            document.sections.single.evenFooter.add(unsupported);
        }
        final controller = _controller(document);
        controller.caret
          ..paragraphIndex = 0
          ..logicalIndex = 2
          ..collapseSelection();
        final summary = await controller.checkDocumentProofing();
        final body = summary.issues.singleWhere(
          (issue) => issue.story == 'Body',
        );
        final target = summary.issues.singleWhere(
          (issue) => identical(issue.paragraph, unsupported),
        );
        expect(controller.selectedProofingIssue, same(body));

        expect(controller.selectProofingIssue(target), isFalse);
        expect(controller.selectedProofingIssue, same(target));
        expect(controller.caret.paragraphIndex, 0);
        expect(controller.caret.logicalIndex, 2);
        expect(controller.caret.isCollapsed, isTrue);
        expect(controller.proofingIssuesAtCaret, [body]);
        controller.refreshView();
        expect(controller.selectedProofingIssue, same(target));
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test(
    'revealing a finding does not select an adjacent endpoint finding',
    () async {
      final controller = _controller(WmlDocument.empty(text: 'FelerFeler'));
      final summary = await controller.checkDocumentProofing();
      final first = summary.issues[0];
      final second = summary.issues[1];
      expect(first.finding.end, second.finding.start);

      expect(controller.selectProofingIssue(first), isTrue);
      expect(controller.caret.selectionAnchor, 0);
      expect(controller.caret.logicalIndex, 5);
      expect(controller.proofingIssuesAtCaret, [second]);
      expect(controller.selectedProofingIssue, same(first));
      controller.refreshView();
      expect(controller.selectedProofingIssue, same(first));

      controller.stepProofingIssue(1);
      expect(controller.selectedProofingIssue, same(second));
      controller.stepProofingIssue(-1);
      expect(controller.selectedProofingIssue, same(first));

      // Existing dialog callers reveal directly rather than selecting in a pane.
      expect(controller.revealProofingIssue(second), isTrue);
      expect(controller.revealProofingIssue(first), isTrue);
      expect(controller.selectedProofingIssue, same(first));
    },
  );

  test(
    'subsequent caret navigation follows a different current finding',
    () async {
      final controller = _controller(WmlDocument.empty(text: 'Feler Feler'));
      final summary = await controller.checkDocumentProofing();
      final first = summary.issues[0];
      final second = summary.issues[1];
      controller.selectProofingIssue(first);
      expect(controller.selectedProofingIssue, same(first));

      controller.caret
        ..logicalIndex = 7
        ..collapseSelection();
      controller.refreshView();
      expect(controller.selectedProofingIssue, same(second));
      expect(controller.proofing.summary, same(summary));
      expect(controller.proofing.isCurrent(first), isTrue);
      expect(controller.contentRevision, 0);
      expect(controller.isDirty, isFalse);
    },
  );

  test(
    'unchanged selected text rebinds after another paragraph is corrected',
    () async {
      final selectedParagraph = _paragraph('Feler selected');
      final otherParagraph = _paragraph('Feler elsewhere');
      final controller = _controller(
        WmlDocument(
          sections: [
            WmlSection(blocks: [selectedParagraph, otherParagraph]),
          ],
        ),
      );
      final original = await controller.checkDocumentProofing();
      final selected = original.issues.singleWhere(
        (issue) => identical(issue.paragraph, selectedParagraph),
      );
      final other = original.issues.singleWhere(
        (issue) => identical(issue.paragraph, otherParagraph),
      );
      controller.selectProofingIssue(selected);
      final oldRevision = controller.contentRevision;
      final selectedCaret = (
        paragraph: controller.caret.paragraphIndex,
        offset: controller.caret.logicalIndex,
        anchor: controller.caret.selectionAnchor,
        anchorParagraph: controller.caret.selectionAnchorParagraph,
      );

      expect(controller.applyProofingSuggestion(other, 'Fehler'), isTrue);
      expect(controller.contentRevision, greaterThan(oldRevision));
      expect(selectedParagraph.text, 'Feler selected');
      expect(otherParagraph.text, 'Fehler elsewhere');
      final retained = controller.selectedProofingIssue;
      expect(retained, isNotNull);
      expect(retained, isNot(same(selected)));
      expect(retained!.paragraph, same(selectedParagraph));
      expect(retained.finding.originalText, selected.finding.originalText);
      expect(retained.finding.start, selected.finding.start);
      expect(retained.finding.end, selected.finding.end);
      expect(retained.finding.revision, controller.contentRevision);
      expect(controller.proofing.isCurrent(retained), isTrue);
      expect(controller.proofing.isCurrent(selected), isFalse);
      expect(controller.applyProofingSuggestion(selected, 'Fehler'), isFalse);
      expect(selectedParagraph.text, 'Feler selected');
      expect((
        paragraph: controller.caret.paragraphIndex,
        offset: controller.caret.logicalIndex,
        anchor: controller.caret.selectionAnchor,
        anchorParagraph: controller.caret.selectionAnchorParagraph,
      ), selectedCaret);
      expect(controller.caret.paragraphIndex, 0);
      expect(controller.caret.selectionAnchor, 0);
      expect(controller.caret.logicalIndex, 5);

      final checked = await controller.checkDocumentProofing();
      final rebound = checked.issues.single;
      expect(rebound, isNot(same(selected)));
      expect(rebound.paragraph, same(selectedParagraph));
      expect(rebound.finding.revision, controller.contentRevision);
      expect(controller.selectedProofingIssue, same(rebound));
      expect(controller.proofing.isCurrent(rebound), isTrue);
      expect(controller.proofing.isCurrent(selected), isFalse);
      expect(controller.caret.paragraphIndex, 0);
      expect(controller.caret.selectionAnchor, 0);
      expect(controller.caret.logicalIndex, 5);
    },
  );

  test(
    'repeated current explicit checks share one manual-provider future',
    () async {
      final manual = _ReviewProvider('manual')..gate = Completer<void>();
      final controller = _controller(
        WmlDocument.empty(text: 'Feler'),
        ordinary: _ReviewProvider('ordinary', findErrors: false),
        manual: manual,
      );
      final first = controller.checkDocumentProofing();
      final second = controller.checkDocumentProofing();
      expect(second, same(first));
      await manual.started.future;
      final third = controller.checkDocumentProofing();
      expect(third, same(first));
      expect(manual.requests, hasLength(1));

      manual.gate!.complete();
      final completed = await first;
      expect(await second, same(completed));
      expect(await third, same(completed));
      expect(completed.complete, isTrue);
      expect(completed.issues.single.finding.providerId, 'manual');
      expect(controller.proofing.isCurrent(completed.issues.single), isTrue);
      expect(manual.requests, hasLength(1));

      final next = controller.checkDocumentProofing();
      expect(next, isNot(same(first)));
      expect((await next).complete, isTrue);
    },
  );

  for (final invalidation in ['text edit', 'provider configuration']) {
    test(
      'a $invalidation allows a new explicit check during an old pass',
      () async {
        final manual = _ReviewProvider('manual')..gate = Completer<void>();
        final controller = _controller(
          WmlDocument.empty(text: 'Feler'),
          ordinary: _ReviewProvider('ordinary', findErrors: false),
          manual: manual,
        );
        final first = controller.checkDocumentProofing();
        await manual.started.future;
        final revision = controller.contentRevision;
        if (invalidation == 'text edit') {
          controller.insertText('New ');
          expect(controller.contentRevision, greaterThan(revision));
        } else {
          controller.proofing.configure(
            OfficeProofingService(
              providers: [_ReviewProvider('ordinary', findErrors: false)],
            ),
          );
          expect(controller.contentRevision, revision);
        }

        final second = controller.checkDocumentProofing();
        expect(second, isNot(same(first)));
        await manual.secondStarted.future;
        expect(controller.checkDocumentProofing(), same(second));
        expect(manual.requests, hasLength(2));
        manual.gate!.complete();
        await first;
        final completed = await second;
        expect(controller.proofing.summary, same(completed));
        expect(completed.complete, isTrue);
        final issue = completed.issues.single;
        expect(issue.sourceText, controller.document.paragraphs.single.text);
        expect(issue.finding.revision, controller.contentRevision);
        expect(controller.proofing.isCurrent(issue), isTrue);
        expect(manual.requests, hasLength(2));
      },
    );
  }
}

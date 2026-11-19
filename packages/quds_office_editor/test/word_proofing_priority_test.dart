import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _Provider extends OfficeProofingProvider {
  @override
  String get id => 'priority-test';
  final requests = <OfficeProofingRequest>[];
  final gates = <String, Completer<void>>{};
  final starts = <String, Completer<void>>{};

  Future<void> started(String text) =>
      (starts[text] ??= Completer<void>()).future;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    final started = starts[request.text] ??= Completer<void>();
    if (!started.isCompleted) started.complete();
    await gates[request.text]?.future;
    return OfficeProofingResult(
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
            ruleId: 'priority-spelling',
            message: 'Check spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['Fehler'],
          ),
      ],
    );
  }
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WordEditorController _controller(WmlDocument document, _Provider provider) {
  final controller = WordEditorController(
    document: document,
    proofingService: OfficeProofingService(providers: [provider]),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active paragraph publishes first even in a long document', () async {
    final paragraphs = [
      for (var index = 0; index < 101; index++) _paragraph('Feler $index'),
    ];
    final provider = _Provider();
    final gate = provider.gates['Feler 0'] = Completer<void>();
    final controller = _controller(
      WmlDocument(sections: [WmlSection(blocks: paragraphs)]),
      provider,
    );
    controller.caret.paragraphIndex = 100;
    controller.caret.logicalIndex = 3;
    final check = controller.proofing.checkNow(includeManualProviders: false);
    await provider.started('Feler 0');

    expect(provider.requests.map((r) => r.text), ['Feler 100', 'Feler 0']);
    expect(
      controller.proofing.summary.issues.single.paragraph,
      same(paragraphs.last),
    );
    expect(controller.proofing.summary.checkedParagraphCount, 1);
    expect(controller.proofing.checking, isTrue);
    expect(controller.proofing.summary.complete, isFalse);

    // Moving the caret while another paragraph is pending does not restart
    // the pass or displace already published current findings.
    final generation = controller.proofing.checkGeneration;
    controller.caret.paragraphIndex = 50;
    controller.refreshView();
    expect(controller.proofing.checkGeneration, generation);
    gate.complete();
    final summary = await check;
    expect(summary.complete, isTrue);
    expect(summary.issues.map((issue) => issue.paragraph), paragraphs);
    expect(provider.requests, hasLength(101));
  });

  test(
    'current comment receives feedback before a slow body paragraph',
    () async {
      final comment = WmlComment(id: 8, text: 'Comment Feler');
      final document = WmlDocument.empty(text: 'Body Feler')
        ..comments.add(comment);
      final provider = _Provider();
      final gate = provider.gates['Body Feler'] = Completer<void>();
      final controller = _controller(document, provider);
      controller.beginCommentEdit(8);
      final check = controller.proofing.checkNow(includeManualProviders: false);
      await provider.started('Body Feler');

      expect(provider.requests.first.text, 'Comment Feler');
      expect(
        controller.proofing.summary.issues.single.paragraph,
        same(comment.paragraphs.single),
      );
      expect(controller.proofing.summary.issues.single.story, 'Comment 8');
      gate.complete();
      final summary = await check;
      expect(summary.issues.first.sourceText, 'Body Feler');
      expect(summary.issues.last.sourceText, 'Comment Feler');
      expect(controller.canUndo, isFalse);
    },
  );

  for (final footer in [false, true]) {
    test(
      'active ${footer ? 'footer' : 'header'} is prioritized without moving its caret',
      () async {
        final provider = _Provider();
        final document = WmlDocument.empty(text: 'Body Feler');
        (footer
                ? document.sections.single.footer
                : document.sections.single.header)
            .add(_paragraph('Margin Feler'));
        final controller = _controller(document, provider);
        controller.beginHeaderFooterEdit(0, footer: footer);
        controller.caret.logicalIndex = 3;
        await controller.proofing.checkNow(includeManualProviders: false);
        expect(provider.requests.first.text, 'Margin Feler');
        expect(controller.caret.logicalIndex, 3);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );
  }

  test(
    'selected Notes text is prioritized using its actual paragraph',
    () async {
      final note = WmlNote(
        id: 1,
        endnote: false,
        addReference: false,
        addReferenceSpace: false,
        paragraphs: [_paragraph('First note'), _paragraph('Note Feler')],
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [_paragraph('Body Feler')]),
        ],
        footnotes: [note],
      );
      final provider = _Provider();
      final controller = _controller(document, provider);
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 15),
      );
      await controller.proofing.checkNow(includeManualProviders: false);
      expect(provider.requests.first.text, 'Note Feler');
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'selecting an empty story never materializes text for priority',
    () async {
      final provider = _Provider();
      final document = WmlDocument.empty(text: 'Body Feler');
      final comment = WmlComment(id: 8, text: 'Comment');
      document.comments.add(comment);
      final controller = _controller(document, provider);
      final revision = controller.contentRevision;
      controller.beginCommentEdit(8);
      comment.paragraphs.clear();
      await controller.proofing.checkNow(includeManualProviders: false);
      expect(comment.paragraphs, isEmpty);
      controller.endCommentEdit();
      controller.beginHeaderFooterEdit(0, footer: false);
      document.sections.single.header.clear();
      await controller.proofing.checkNow(includeManualProviders: false);
      expect(document.sections.single.header, isEmpty);
      controller.endHeaderFooterEdit();
      document.sections.clear();
      await controller.proofing.checkNow(includeManualProviders: false);
      expect(document.sections, isEmpty);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    },
  );

  test(
    'detached priority is ignored and cached paragraphs stay reusable',
    () async {
      final paragraphs = [
        _paragraph('Feler first'),
        _paragraph('Feler second'),
      ];
      final document = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
      var priority = _paragraph('Detached Feler');
      final provider = _Provider();
      final session = WordProofingSession(
        document: () => document,
        revision: () => 0,
        priorityParagraph: () => priority,
        service: OfficeProofingService(providers: [provider]),
      );
      addTearDown(session.dispose);
      await session.checkNow(includeManualProviders: false);
      expect(provider.requests.map((r) => r.text), [
        'Feler first',
        'Feler second',
      ]);
      priority = paragraphs.last;
      await session.checkNow(includeManualProviders: false);
      expect(provider.requests, hasLength(2));
      expect(
        session.summary.issues.map((issue) => issue.paragraph),
        paragraphs,
      );
    },
  );
}

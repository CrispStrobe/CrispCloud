import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Flags `Feler` (spelling) and doubled words (grammar) and records requests.
final class _Provider extends OfficeProofingProvider {
  final requests = <String>[];
  Completer<void>? gate;

  @override
  String get id => 'schedule-test';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request.text);
    await gate?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        for (final match in RegExp(r'\bFeler\b').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: match.start,
            end: match.end,
            ruleId: 'spelling',
            message: 'Check spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['Fehler'],
          ),
        for (final match in RegExp(r'\b(\w+) \1\b').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: match.start,
            end: match.end,
            ruleId: 'repeat',
            message: 'Repeated word.',
            category: OfficeProofingCategory.grammar,
          ),
      ],
    );
  }
}

WmlDocument _document() => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        for (var index = 0; index < 40; index++)
          WmlParagraph(
            inlines: [
              WmlRun(
                text: index.isEven
                    ? 'Absatz $index hat einen Feler und und mehr.'
                    : 'Paragraph $index is clean.',
              ),
            ],
          ),
      ],
    ),
  ],
);

({WordEditorController controller, _Provider provider}) _setup({
  WmlDocument? document,
}) {
  final provider = _Provider();
  final controller = WordEditorController(
    document: document ?? _document(),
    proofingService: OfficeProofingService(providers: [provider]),
  );
  addTearDown(controller.dispose);
  controller.proofing.enabled = true;
  return (controller: controller, provider: provider);
}

void _caret(WordEditorController controller, int paragraph, int offset) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..selectionAnchorParagraph = paragraph
    ..selectionAnchor = offset;
  controller.refreshView();
}

Future<void> _settle(WidgetTester tester, WordEditorController c) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!c.proofing.checking && !c.proofing.summary.scheduled) return;
  }
  fail('proofing did not settle');
}

/// Fake-async passes yield through zero timers; pump until [future] ends.
Future<void> _complete(WidgetTester tester, Future<Object?> future) async {
  var done = false;
  unawaited(future.whenComplete(() => done = true));
  for (var i = 0; i < 1000 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(done, isTrue);
}

List<String> _findings(WordEditorController controller) {
  final paragraphs = controller.document.paragraphs.toList();
  return [
    for (final issue in controller.proofing.summary.issues)
      '${paragraphs.indexOf(issue.paragraph)}:${issue.finding.start}-'
          '${issue.finding.end}:${issue.finding.ruleId}:'
          '${issue.finding.originalText}',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typing defers checks to a pause and rechecks only edits', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    final passes = h.controller.proofing.passCount;
    h.provider.requests.clear();
    _caret(h.controller, 10, 'Absatz 10 hat'.length);
    for (final char in ' etwas'.split('')) {
      h.controller.insertText(char);
      await tester.pump(const Duration(milliseconds: 100));
    }
    // No pass while the gaps stay below the idle pause.
    expect(h.controller.proofing.passCount, passes);
    expect(h.provider.requests, isEmpty);
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    expect(h.controller.proofing.passCount, passes + 1);
    expect(h.provider.requests, [
      'Absatz 10 hat etwas einen Feler und und mehr.',
    ]);
  });

  testWidgets('continuous typing is still checked by the deadline', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    final passes = h.controller.proofing.passCount;
    _caret(h.controller, 1, 'Paragraph 1 is clean.'.length);
    // 4 s of typing at 10 characters per second, never pausing.
    for (var i = 0; i < 40; i++) {
      h.controller.insertText(i % 5 == 4 ? ' ' : 'a');
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.controller.proofing.passCount, greaterThan(passes));
    expect(
      h.controller.proofing.passCount,
      lessThanOrEqualTo(passes + 2),
      reason: 'one pass per deadline, not per keystroke',
    );
    await _settle(tester, h.controller);
  });

  testWidgets('a deadline pass defers the unfinished word at the caret', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    final paragraph = h.controller.document.paragraphs.elementAt(1);
    _caret(h.controller, 1, 'Paragraph 1 is clean.'.length);
    for (final char in ' Feler'.split('')) {
      h.controller.insertText(char);
    }
    await _complete(
      tester,
      h.controller.proofing.checkNow(
        includeManualProviders: false,
        deferCaretWord: true,
      ),
    );
    bool flagged() => h.controller.proofing.summary.issues.any(
      (issue) =>
          identical(issue.paragraph, paragraph) &&
          issue.finding.ruleId == 'spelling',
    );
    expect(flagged(), isFalse);
    // Moving the caret away publishes it without another provider call.
    final requests = h.provider.requests.length;
    _caret(h.controller, 1, 0);
    expect(flagged(), isTrue);
    expect(h.provider.requests, hasLength(requests));
  });

  testWidgets('status keeps settled results while typing and delays checking', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    final session = h.controller.proofing;
    final settled = session.status.value;
    expect(settled.phase, WordProofingPhase.complete);
    expect(settled.issueCount, 40);
    final changes = <WordProofingStatus>[];
    void record() => changes.add(session.status.value);
    session.status.addListener(record);
    addTearDown(() => session.status.removeListener(record));

    _caret(h.controller, 2, 0);
    h.controller.insertText('X');
    await tester.pump(const Duration(milliseconds: 50));
    expect(session.summary.scheduled, isTrue);
    expect(session.status.value, settled);

    final gate = h.provider.gate = Completer<void>();
    await tester.pump(WordProofingTiming.idle);
    expect(session.checking, isTrue);
    expect(session.status.value, settled);
    await tester.pump(WordProofingTiming.checkingIndicatorDelay);
    expect(session.status.value.phase, WordProofingPhase.checking);
    gate.complete();
    h.provider.gate = null;
    await _settle(tester, h.controller);
    expect(session.status.value.phase, WordProofingPhase.complete);
    expect(changes.map((status) => status.phase), [
      WordProofingPhase.checking,
      WordProofingPhase.complete,
    ]);
  });

  testWidgets('background scheduling settles to the findings of a full check', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    const script = [
      (paragraph: 3, text: ' Ein Feler hier'),
      (paragraph: 20, text: ' mehr mehr Text'),
      (paragraph: 7, text: ' noch noch ein Feler'),
      (paragraph: 39, text: ' Ende'),
    ];
    for (final step in script) {
      final text = h.controller.document.paragraphs
          .elementAt(step.paragraph)
          .text;
      _caret(h.controller, step.paragraph, text.length);
      for (final char in step.text.split('')) {
        h.controller.insertText(char);
        await tester.pump(const Duration(milliseconds: 90));
      }
    }
    // Leave the caret elsewhere, then let checking settle.
    _caret(h.controller, 0, 0);
    await _settle(tester, h.controller);
    final background = _findings(h.controller);

    // The previous scheduler's result: one explicit pass over a copy.
    final reference = _setup(
      document: WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              for (final paragraph in h.controller.document.paragraphs)
                WmlParagraph(inlines: [WmlRun(text: paragraph.text)]),
            ],
          ),
        ],
      ),
    );
    reference.controller.proofing.enabled = false;
    await _complete(tester, reference.controller.proofing.checkNow());
    expect(background, _findings(reference.controller));
    expect(background, hasLength(44));
    expect(h.controller.proofing.summary.complete, isTrue);
  });
}

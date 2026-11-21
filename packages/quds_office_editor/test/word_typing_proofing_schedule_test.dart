import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Records requests; findings come from [find]. A [gate] holds every check.
final class _Provider extends OfficeProofingProvider {
  _Provider(this.id, this.categories, this.find);

  @override
  final String id;

  @override
  final Set<OfficeProofingCategory> categories;

  final List<OfficeProofingFinding> Function(OfficeProofingRequest, String id)
  find;
  final requests = <String>[];
  Completer<void>? gate;

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
      findings: find(request, id),
    );
  }
}

/// Flags `Feler`.
_Provider _spelling() => _Provider(
  'spelling-test',
  const {OfficeProofingCategory.spelling},
  (request, id) => [
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
  ],
);

/// Flags doubled words.
_Provider _grammar() => _Provider(
  'grammar-test',
  const {OfficeProofingCategory.grammar, OfficeProofingCategory.style},
  (request, id) => [
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

WmlDocument _document({int paragraphs = 40}) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        for (var index = 0; index < paragraphs; index++)
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

final class _Harness {
  _Harness(this.controller, this.spelling, this.grammar);
  final WordEditorController controller;
  final _Provider spelling;
  final _Provider grammar;

  WordProofingSession get session => controller.proofing;
  List<String> get spellingCalls => spelling.requests;
  List<String> get grammarCalls => grammar.requests;
  int get calls => spelling.requests.length + grammar.requests.length;

  void clearCalls() {
    spelling.requests.clear();
    grammar.requests.clear();
  }

  WmlParagraph paragraph(int index) =>
      controller.document.paragraphs.elementAt(index);

  void caret(int paragraph, int offset) {
    controller.caret
      ..paragraphIndex = paragraph
      ..logicalIndex = offset
      ..selectionAnchorParagraph = paragraph
      ..selectionAnchor = offset;
    controller.refreshView();
  }

  void caretAtEnd(int paragraph) =>
      caret(paragraph, this.paragraph(paragraph).text.length);

  bool flagged(int paragraph, String ruleId) => session.summary.issues.any(
    (issue) =>
        identical(issue.paragraph, this.paragraph(paragraph)) &&
        issue.finding.ruleId == ruleId,
  );

  /// Underlines painted right now (no lazy capture).
  bool painted(int paragraph, String ruleId) =>
      (session.findingsByParagraph[this.paragraph(paragraph)] ?? const []).any(
        (finding) => finding.ruleId == ruleId,
      );

  Future<void> type(
    WidgetTester tester,
    String text, {
    Duration gap = const Duration(milliseconds: 100),
  }) async {
    for (final char in text.split('')) {
      controller.insertText(char);
      await tester.pump(gap);
    }
  }
}

_Harness _setup({
  WmlDocument? document,
  WordProofingSchedule schedule = const WordProofingSchedule(),
}) {
  final spelling = _spelling();
  final grammar = _grammar();
  final controller = WordEditorController(
    document: document ?? _document(),
    proofingService: OfficeProofingService(providers: [spelling, grammar]),
  );
  addTearDown(controller.dispose);
  controller.proofing
    ..schedule = schedule
    ..enabled = true;
  return _Harness(controller, spelling, grammar);
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

const _afterWord = Duration(milliseconds: 200);

/// Lets pending pause and idle-time checks finish before teardown.
Future<void> _drain(WidgetTester tester, _Harness h) async {
  await tester.pump(WordProofingTiming.backgroundIdle);
  await _settle(tester, h.controller);
  await tester.pump(WordProofingTiming.backgroundIdle);
  await _settle(tester, h.controller);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a loaded document is checked once, after the pause', (
    tester,
  ) async {
    final h = _setup();
    await tester.pump(WordProofingTiming.idle - _afterWord);
    expect(h.calls, 0);
    await _settle(tester, h.controller);
    expect(h.spellingCalls, hasLength(40));
    expect(h.grammarCalls, hasLength(40));
    expect(h.session.summary.complete, isTrue);
    expect(h.session.passCountsByTrigger, {'pause': 1});
  });

  testWidgets(
    'no provider call while a word is typed, one per completed word',
    (tester) async {
      final h = _setup();
      await _settle(tester, h.controller);
      h.clearCalls();
      h.caretAtEnd(1);
      // Ten characters per second, no space or punctuation: no completion.
      await h.type(tester, ' Langeswort'.substring(1));
      expect(h.calls, 0);
      // A space completes the word: spelling of this paragraph only.
      await h.type(tester, ' ');
      await tester.pump(_afterWord);
      expect(h.spellingCalls, ['Paragraph 1 is clean.Langeswort ']);
      expect(h.grammarCalls, isEmpty);
      // The next word again waits for its completion.
      h.clearCalls();
      await h.type(tester, 'zwei');
      expect(h.calls, 0);
      await h.type(tester, ',');
      await tester.pump(_afterWord);
      expect(h.spellingCalls, hasLength(1));
      expect(h.grammarCalls, isEmpty);
      await _drain(tester, h);
    },
  );

  testWidgets('without a spelling-only provider words wait for the pause', (
    tester,
  ) async {
    // A provider declaring every category runs on the grammar schedule.
    final rules = _Provider(
      'rules-test',
      OfficeProofingCategory.values.toSet(),
      (request, id) => _spelling().find(request, id),
    );
    final controller = WordEditorController(
      document: _document(),
      proofingService: OfficeProofingService(providers: [rules]),
    );
    addTearDown(controller.dispose);
    controller.proofing.enabled = true;
    final h = _Harness(controller, rules, _grammar());
    await _settle(tester, controller);
    expect(h.session.summary.complete, isTrue);
    rules.requests.clear();
    h.caretAtEnd(1);
    await h.type(tester, ' ein Feler ');
    expect(rules.requests, isEmpty);
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, controller);
    expect(rules.requests, ['Paragraph 1 is clean. ein Feler ']);
    expect(h.flagged(1, 'spelling'), isTrue);
    expect(h.session.summary.complete, isTrue);
  });

  testWidgets('a word check that changes no mark does not notify', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    h.caret(1, 0);
    var notifications = 0;
    void count() => notifications++;
    h.session.addListener(count);
    addTearDown(() => h.session.removeListener(count));
    await h.type(tester, 'Gut ');
    await tester.pump(_afterWord);
    expect(h.session.passCountsByTrigger['word'], 1);
    expect(h.session.silentPassCount, 1);
    expect(notifications, 0);
    // A new mark notifies.
    await h.type(tester, 'Feler ');
    await tester.pump(_afterWord);
    expect(h.flagged(1, 'spelling'), isTrue);
    expect(notifications, 1);
    await _drain(tester, h);
  });

  testWidgets('other marks in the paragraph being typed do not blink', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    // Paragraph 0: "Absatz 0 hat einen Feler und und mehr."
    expect(h.painted(0, 'spelling'), isTrue);
    expect(h.painted(0, 'repeat'), isTrue);
    h.caret(0, 0);
    var notifications = 0;
    void count() => notifications++;
    h.session.addListener(count);
    addTearDown(() => h.session.removeListener(count));
    // Typing before the marks moves them; they stay painted throughout.
    for (final char in 'Neu '.split('')) {
      h.controller.insertText(char);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.painted(0, 'spelling'), isTrue);
      expect(h.painted(0, 'repeat'), isTrue);
    }
    final marks = h.session.findingsByParagraph[h.paragraph(0)]!;
    expect(
      marks.map((m) => h.paragraph(0).text.substring(m.start, m.end)),
      containsAll(<String>['Feler', 'und und']),
    );
    await tester.pump(_afterWord);
    expect(h.session.passCountsByTrigger['word'], 1);
    expect(notifications, 0, reason: 'the word check changed no mark');
    // Extending a flagged word drops its mark until it is checked again.
    h.caret(0, 'Neu Absatz 0 hat einen Feler'.length);
    h.controller.insertText('n');
    await tester.pump();
    expect(h.painted(0, 'spelling'), isFalse);
    expect(h.painted(0, 'repeat'), isTrue);
    await _drain(tester, h);
  });

  testWidgets('continuous typing never forces a pass', (tester) async {
    final h = _setup();
    await _settle(tester, h.controller);
    h.clearCalls();
    final passes = h.session.passCount;
    h.caretAtEnd(1);
    // Six seconds of letters at ten per second, never pausing.
    for (var i = 0; i < 60; i++) {
      h.controller.insertText('a');
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.calls, 0);
    expect(h.session.passCount, passes);
    await _drain(tester, h);
  });

  testWidgets('the word under the caret is never flagged while typing', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    h.caretAtEnd(1);
    await h.type(tester, ' Feler');
    // Even the pause pass, which checks spelling, keeps it hidden.
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    expect(h.spellingCalls.last, 'Paragraph 1 is clean. Feler');
    expect(h.flagged(1, 'spelling'), isFalse);
    expect(h.painted(1, 'spelling'), isFalse);
    // Completing the word shows it.
    await h.type(tester, ' ');
    await tester.pump(_afterWord);
    await _settle(tester, h.controller);
    expect(h.flagged(1, 'spelling'), isTrue);
    expect(h.painted(1, 'spelling'), isTrue);
    await _drain(tester, h);
  });

  testWidgets('an existing flag stays hidden until the caret leaves', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    // Paragraph 0 has a settled "Feler" finding at 21-26.
    expect(h.flagged(0, 'spelling'), isTrue);
    h.caret(0, 'Absatz 0 hat einen Fel'.length);
    await h.type(tester, 'l');
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    // "Feller" is not "Feler" any more; delete back to it.
    h.controller.deleteSelectionOr(backward: true);
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    expect(h.paragraph(0).text, startsWith('Absatz 0 hat einen Feler'));
    expect(h.flagged(0, 'spelling'), isFalse);
    final calls = h.calls;
    h.caret(0, 0);
    expect(h.flagged(0, 'spelling'), isTrue);
    expect(h.calls, calls, reason: 'shown from the cache');
  });

  testWidgets('the typing word is shown when hiding is turned off', (
    tester,
  ) async {
    final h = _setup(
      schedule: const WordProofingSchedule(hideTypingErrors: false),
    );
    await _settle(tester, h.controller);
    h.caretAtEnd(1);
    await h.type(tester, ' Feler');
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    expect(h.flagged(1, 'spelling'), isTrue);
  });

  testWidgets('grammar runs at sentence end, not at word completion', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    h.clearCalls();
    h.caretAtEnd(1);
    await h.type(tester, ' und und ', gap: const Duration(milliseconds: 250));
    expect(h.grammarCalls, isEmpty);
    expect(h.spellingCalls, isNotEmpty);
    expect(h.flagged(1, 'repeat'), isFalse);
    await h.type(tester, 'Ende.');
    await tester.pump(_afterWord);
    expect(h.grammarCalls, ['Paragraph 1 is clean. und und Ende.']);
    expect(h.flagged(1, 'repeat'), isTrue);
    await _drain(tester, h);
  });

  testWidgets('grammar runs after the pause without sentence end', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    h.clearCalls();
    h.caretAtEnd(1);
    await h.type(tester, ' und und');
    expect(h.grammarCalls, isEmpty);
    await tester.pump(WordProofingTiming.idle - _afterWord);
    expect(h.grammarCalls, isEmpty);
    await tester.pump(_afterWord * 2);
    await _settle(tester, h.controller);
    expect(h.grammarCalls, ['Paragraph 1 is clean. und und']);
    // The doubled word ends at the caret: hidden while typing.
    expect(h.flagged(1, 'repeat'), isFalse);
    h.caret(1, 0);
    expect(h.flagged(1, 'repeat'), isTrue);
  });

  testWidgets('Enter completes the paragraph and checks its grammar', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    h.clearCalls();
    h.caretAtEnd(1);
    await h.type(tester, ' mehr mehr');
    h.controller.insertParagraphBreak();
    await tester.pump(_afterWord);
    expect(h.grammarCalls, contains('Paragraph 1 is clean. mehr mehr'));
    expect(h.flagged(1, 'repeat'), isTrue);
    await _drain(tester, h);
  });

  testWidgets('"When I pause" checks nothing until typing pauses', (
    tester,
  ) async {
    final h = _setup(
      schedule: const WordProofingSchedule(mode: WordProofingMode.onPause),
    );
    await _settle(tester, h.controller);
    h.clearCalls();
    h.caretAtEnd(1);
    await h.type(tester, ' ein zwei drei. vier ');
    expect(h.calls, 0);
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    expect(h.spellingCalls, hasLength(1));
    expect(h.grammarCalls, hasLength(1));
  });

  testWidgets('the pause is adjustable and takes effect immediately', (
    tester,
  ) async {
    final h = _setup(
      schedule: const WordProofingSchedule(mode: WordProofingMode.onPause),
    );
    await _settle(tester, h.controller);
    h.clearCalls();
    h.session.schedule = h.session.schedule.copyWith(
      pause: const Duration(seconds: 4),
    );
    expect(h.session.debounce, const Duration(seconds: 4));
    h.caretAtEnd(1);
    await h.type(tester, ' x');
    await tester.pump(const Duration(seconds: 3));
    expect(h.calls, 0);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester, h.controller);
    expect(h.spellingCalls, hasLength(1));
  });

  testWidgets('"Only when I click Check document" makes no automatic calls', (
    tester,
  ) async {
    final h = _setup(
      schedule: const WordProofingSchedule(mode: WordProofingMode.manual),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(h.calls, 0);
    h.caretAtEnd(1);
    await h.type(tester, ' Feler und und. ');
    await tester.pump(const Duration(seconds: 10));
    expect(h.calls, 0);
    expect(h.session.summary.scheduled, isFalse);
    await _complete(tester, h.session.checkNow());
    expect(h.spellingCalls, hasLength(40));
    expect(h.grammarCalls, hasLength(40));
    expect(h.flagged(1, 'spelling'), isTrue);
    expect(h.flagged(1, 'repeat'), isTrue);
  });

  testWidgets('spelling and grammar while typing can be turned off', (
    tester,
  ) async {
    final h = _setup(schedule: const WordProofingSchedule(checkGrammar: false));
    await _settle(tester, h.controller);
    expect(h.grammarCalls, isEmpty);
    expect(h.spellingCalls, hasLength(40));
    expect(h.session.summary.complete, isFalse, reason: 'grammar unchecked');
    h.clearCalls();
    h.session.schedule = const WordProofingSchedule(checkSpelling: false);
    await _settle(tester, h.controller);
    await tester.pump(WordProofingTiming.backgroundIdle);
    await _settle(tester, h.controller);
    // Grammar is added to the cached spelling results; spelling is not rerun.
    expect(h.spellingCalls, isEmpty);
    expect(h.grammarCalls, hasLength(40));
    expect(h.session.summary.complete, isTrue);
  });

  testWidgets('without background checking only edited text is checked', (
    tester,
  ) async {
    final h = _setup(
      schedule: const WordProofingSchedule(backgroundCheck: false),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(h.calls, 0);
    h.caretAtEnd(3);
    await h.type(tester, ' x');
    await tester.pump(const Duration(seconds: 10));
    // The word check after the space ran 150 ms later, on the same text the
    // pause pass saw: the pause pass only added grammar.
    expect(h.spellingCalls, ['Paragraph 3 is clean. x']);
    expect(h.grammarCalls, ['Paragraph 3 is clean. x']);
  });

  testWidgets('background passes wait for idle time and yield to input', (
    tester,
  ) async {
    final h = _setup(
      schedule: const WordProofingSchedule(backgroundCheck: false),
    );
    // Check one paragraph by editing it; the rest stays unchecked.
    h.caretAtEnd(3);
    await h.type(tester, ' x');
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    h.clearCalls();
    // Turning background checking on arms it after the pause.
    h.session.schedule = const WordProofingSchedule();
    await tester.pump(WordProofingTiming.idle);
    await _settle(tester, h.controller);
    expect(h.calls, 0, reason: 'nothing edited; idle time not reached');
    final gate = h.spelling.gate = Completer<void>();
    await tester.pump(
      WordProofingTiming.backgroundIdle - WordProofingTiming.idle,
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(h.session.passCountsByTrigger['background'], 1);
    // The background pass starts next to the caret (visible text first).
    expect(h.spellingCalls, ['Absatz 2 hat einen Feler und und mehr.']);
    // Typing aborts it: no further paragraph is sent once the check returns.
    await h.type(tester, 'y', gap: Duration.zero);
    gate.complete();
    h.spelling.gate = null;
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.spellingCalls, hasLength(1));
    // It resumes after the next idle period and finishes the document.
    await tester.pump(WordProofingTiming.backgroundIdle);
    await _settle(tester, h.controller);
    await tester.pump(WordProofingTiming.backgroundIdle);
    await _settle(tester, h.controller);
    expect(h.session.summary.complete, isTrue);
    expect(h.session.summary.checkedParagraphCount, 40);
  });

  testWidgets('typing checks never show "Checking…" or flicker the status', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    final session = h.session;
    final settled = session.status.value;
    expect(settled.phase, WordProofingPhase.complete);
    final changes = <WordProofingStatus>[];
    void record() => changes.add(session.status.value);
    session.status.addListener(record);
    addTearDown(() => session.status.removeListener(record));
    h.caretAtEnd(1);
    // Slow providers: each check of the typed text takes 2 s.
    final gate = h.spelling.gate = Completer<void>();
    await h.type(tester, ' gut gut. ');
    await tester.pump(WordProofingTiming.idle);
    await tester.pump(const Duration(seconds: 2));
    expect(session.status.value, settled);
    gate.complete();
    h.spelling.gate = null;
    await _settle(tester, h.controller);
    expect(
      changes.map((status) => status.phase),
      isNot(contains(WordProofingPhase.checking)),
    );
    expect(changes.map((status) => status.phase), [WordProofingPhase.complete]);
  });

  testWidgets('explicit checks still show progress after the delay', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    final gate = Completer<void>();
    h.session.configure(
      OfficeProofingService(providers: [_spelling()..gate = gate]),
    );
    unawaited(h.session.checkNow());
    await tester.pump(const Duration(milliseconds: 10));
    expect(h.session.status.value.phase, isNot(WordProofingPhase.checking));
    await tester.pump(WordProofingTiming.checkingIndicatorDelay);
    expect(h.session.status.value.phase, WordProofingPhase.checking);
    gate.complete();
    await _drain(tester, h);
  });

  testWidgets('scheduled checking settles to the findings of a full check', (
    tester,
  ) async {
    final h = _setup();
    await _settle(tester, h.controller);
    const script = [
      (paragraph: 3, text: ' Ein Feler hier'),
      (paragraph: 20, text: ' mehr mehr Text.'),
      (paragraph: 7, text: ' noch noch ein Feler'),
      (paragraph: 39, text: ' Ende'),
    ];
    for (final step in script) {
      h.caretAtEnd(step.paragraph);
      await h.type(tester, step.text, gap: const Duration(milliseconds: 90));
    }
    // Leave the caret elsewhere, then let checking settle.
    h.caret(0, 0);
    await tester.pump(WordProofingTiming.backgroundIdle);
    await _settle(tester, h.controller);
    final scheduled = _findings(h.controller);

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
      schedule: const WordProofingSchedule(mode: WordProofingMode.manual),
    );
    await _complete(tester, reference.session.checkNow());
    expect(scheduled, _findings(reference.controller));
    expect(scheduled, hasLength(44));
    expect(h.session.summary.complete, isTrue);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _Provider extends OfficeProofingProvider {
  _Provider(this.id, {this.status = OfficeProofingStatus.success});

  @override
  final String id;
  OfficeProofingStatus status;
  int version = 0;
  int categoryReads = 0;

  @override
  Set<OfficeProofingCategory> get categories {
    categoryReads++;
    return super.categories;
  }

  final requests = <OfficeProofingRequest>[];
  final gates = <String, Completer<void>>{};
  final starts = <String, Completer<void>>{};

  @override
  int get configurationRevision => version;

  @override
  bool supportsLanguage(String language) => true;

  Future<void> started(String text) =>
      (starts[text] ??= Completer<void>()).future;

  Completer<void> gate(String text) => gates[text] = Completer<void>();

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    final start = starts[request.text] ??= Completer<void>();
    if (!start.isCompleted) start.complete();
    await gates[request.text]?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.success
          ? null
          : '$id unavailable',
      findings: [
        if (status == OfficeProofingStatus.success)
          for (final match in RegExp('Feler').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: '$id-spelling',
              message: 'Check spelling.',
              category: OfficeProofingCategory.spelling,
              replacements: const ['Fehler'],
            ),
      ],
    );
  }
}

class _CountedParagraph extends WmlParagraph {
  _CountedParagraph(String text) : super(inlines: [WmlRun(text: text)]);

  int reads = 0;

  @override
  String get text {
    reads++;
    return super.text;
  }
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document(List<String> texts) =>
    WmlDocument(sections: [WmlSection(blocks: texts.map(_paragraph).toList())]);

class _Harness {
  _Harness(List<String> texts) : document = _document(texts) {
    session = WordProofingSession(
      document: () => document,
      revision: () => revision,
      service: OfficeProofingService(providers: [provider]),
      // Tests start passes explicitly; this timer only represents the pending
      // typing window and is canceled on disposal.
      debounce: const Duration(days: 1),
    );
    addTearDown(session.dispose);
  }

  WmlDocument document;
  final provider = _Provider('ordinary');
  late final WordProofingSession session;
  int revision = 0;

  List<WmlParagraph> get paragraphs => document.paragraphs.toList();

  void changed() {
    revision++;
    session.observeDocument();
  }

  void edit(int index, String text) {
    paragraphs[index].inlines = [WmlRun(text: text)];
    changed();
  }
}

void main() {
  test('planning a settled pass reads provider groups once per scan', () async {
    final h = _Harness(List.generate(100, (index) => 'Feler $index'));
    final initial = await h.session.checkNow();
    expect(initial.checkedParagraphCount, 100);

    h.provider.categoryReads = 0;
    final warm = await h.session.checkNow();
    expect(warm.checkedParagraphCount, 100);
    expect(warm.issues, initial.issues);
    expect(h.provider.requests, hasLength(100));
    expect(h.provider.categoryReads, inInclusiveRange(1, 8));
  });

  test(
    'progress reuses reports rebound to the current document revision',
    () async {
      final dense = List.filled(10, 'Feler').join(' ');
      final h = _Harness(['Feler stable', dense, 'Feler initial']);
      final initial = await h.session.checkNow();
      var previous = initial.reports.first;

      for (final text in ['Feler edited', 'Feler edited again']) {
        h.edit(2, text);
        final gate = h.provider.gate(text);
        final pending = h.session.checkNow();
        await h.provider.started(text);
        final partial = h.session.summary;
        final rebound = partial.reports.first;
        expect(partial.checking, isTrue);
        expect(rebound, isNot(same(previous)));
        expect(rebound.request.revision, h.revision);
        expect(rebound.results.single.request, same(rebound.request));
        expect(rebound.findings.single.revision, h.revision);

        gate.complete();
        final finished = await pending;
        expect(finished.reports.first, same(rebound));
        expect(partial.issues, hasLength(11));
        expect(finished.issues.take(11), orderedEquals(partial.issues));
        expect(h.session.canCorrect(finished.issues.first), isTrue);
        previous = rebound;
      }

      expect(h.provider.requests.map((request) => request.text), [
        'Feler stable',
        dense,
        'Feler initial',
        'Feler edited',
        'Feler edited again',
      ]);
    },
  );

  test(
    'local issue lookups follow edits, ignore and document replacement',
    () async {
      final h = _Harness(['Feler first', 'Feler and Feler', 'Feler last']);
      final [first, middle, last] = h.paragraphs;
      final initial = await h.session.checkNow();
      expect(h.session.issuesAt(middle, 1), [initial.issues[1]]);
      expect(h.session.issuesAt(middle, 11), [initial.issues[2]]);

      h.edit(0, 'Fehler first');
      expect(h.session.issuesAt(first, 1), isEmpty);
      final retained = h.session.issuesAt(middle, 11).single;
      expect(retained.finding.revision, h.revision);
      expect(h.session.isCurrent(initial.issues[2]), isFalse);
      expect(h.session.isCurrent(retained), isTrue);

      h.session.ignoreOnce(retained);
      expect(h.session.issuesAt(middle, 11), isEmpty);
      expect(h.session.issuesAt(middle, 1).single.paragraph, same(middle));
      expect(h.session.issuesAt(last, 1).single.paragraph, same(last));
      expect(h.session.isCurrent(retained), isFalse);

      h.document = _document(['Feler replacement']);
      h.changed();
      expect(h.session.issuesAt(middle, 1), isEmpty);
      final replacement = (await h.session.checkNow()).issues.single;
      expect(h.session.issuesAt(h.paragraphs.single, 1), [replacement]);
    },
  );

  test(
    'target validation reads only its paragraph and tracks earlier fields',
    () async {
      final preceding = _CountedParagraph('Field heading');
      final target = _CountedParagraph('Feler target');
      final following = _CountedParagraph('Later paragraph');
      final h = _Harness([]);
      h.document.sections.single.blocks.add(preceding);
      h.document.sections.add(WmlSection(blocks: [target, following]));
      final issue = (await h.session.checkNow()).issues.single;

      preceding.reads = 0;
      target.reads = 0;
      following.reads = 0;
      expect(h.session.isCurrent(issue), isTrue);
      expect(target.reads, 1);
      final capture = h.session.captureTextRange(target, 0, 5);
      expect(capture.status, WordTextRangeStatus.ready);
      expect(h.session.isTextRangeCurrent(capture.target!), isTrue);
      expect([preceding.reads, following.reads], [0, 0]);

      preceding.inlines.add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin));
      expect(h.session.isCurrent(issue), isFalse);
      expect(h.session.isTextRangeCurrent(capture.target!), isFalse);
      expect(
        h.session.captureTextRange(target, 0, 5).status,
        WordTextRangeStatus.protectedContent,
      );

      preceding.inlines.add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
      expect(h.session.isCurrent(issue), isTrue);
      expect(h.session.isTextRangeCurrent(capture.target!), isTrue);
      expect([preceding.reads, following.reads], [0, 0]);
    },
  );

  test(
    'paint resolves only requested paragraphs during a pending edit',
    () async {
      final changed = _CountedParagraph('Feler first Feler');
      final offscreen = _CountedParagraph('Feler second');
      final h = _Harness([]);
      h.document.sections.single.blocks.addAll(<WmlParagraph>[
        changed,
        offscreen,
      ]);
      await h.session.checkNow();

      h.edit(0, 'Fehler first Feler');
      changed.reads = 0;
      offscreen.reads = 0;
      final paint = h.session.paintFindingsLookup!;
      expect(paint(changed)?.single.start, 13);
      expect(paint(changed)?.single.originalText, 'Feler');
      expect(changed.reads, 1);
      expect(offscreen.reads, 0);

      h.edit(0, 'Fehler first completely correct');
      expect(h.session.paintFindingsLookup!(changed), isNull);
      expect(offscreen.reads, 0);

      // Whole-map readers still see the unchanged paragraph and the same
      // read-only map contract while the next provider check is pending.
      final snapshot = h.session.findingsByParagraph;
      expect(snapshot.keys, [offscreen]);
      expect(offscreen.reads, 1);
      expect(() => snapshot.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unchanged findings survive typing and the next in-flight check',
    () async {
      final h = _Harness(['Feler first', 'Feler second']);
      await h.session.checkNow(includeManualProviders: false);
      h.session.enabled = true;
      final old = h.session.summary.issues.last;
      final unchanged = h.paragraphs.last;

      h.edit(0, 'Correct first');
      final retained = h.session.summary.issues.single;
      expect(retained.paragraph, same(unchanged));
      expect(retained.finding.revision, h.revision);
      expect(h.session.isCurrent(retained), isTrue);
      expect(h.session.isCurrent(old), isFalse);
      expect(h.session.summary.scheduled, isTrue);
      expect(h.session.summary.checkedParagraphCount, 1);
      expect(h.session.summary.paragraphCount, 2);
      expect(h.session.summary.complete, isFalse);
      expect(h.session.findingsByParagraph.keys, [unchanged]);

      final gate = h.provider.gate('Correct first');
      final pending = h.session.checkNow(includeManualProviders: false);
      await h.provider.started('Correct first');
      expect(h.session.checking, isTrue);
      expect(h.session.summary.issues.single, same(retained));
      expect(h.session.canCorrect(retained), isTrue);
      gate.complete();
      final result = await pending;

      expect(result.complete, isTrue);
      expect(result.issues.single, same(retained));
      expect(h.provider.requests.map((request) => request.text), [
        'Feler first',
        'Feler second',
        'Correct first',
      ]);
    },
  );

  test(
    'paused partial results never claim a clean whole-document check',
    () async {
      final h = _Harness(['Correct first', 'Correct second']);
      await h.session.checkNow();
      h.edit(0, 'Unchecked Feler');
      expect(h.session.enabled, isFalse);
      expect(h.session.summary.hasResults, isTrue);
      expect(h.session.summary.checkedParagraphCount, 1);
      expect(h.session.summary.paragraphCount, 2);
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.summary.complete, isFalse);
      expect(
        h.session.summary.statusMessage,
        contains('coverage is incomplete'),
      );
    },
  );

  test(
    'new findings are published before the whole document finishes',
    () async {
      final h = _Harness(['Feler ' * 20, 'Feler second', 'Feler third']);
      final second = h.provider.gate('Feler second');
      final third = h.provider.gate('Feler third');
      final pending = h.session.checkNow();
      await h.provider.started('Feler second');

      final firstIssue = h.session.summary.issues.first;
      expect(firstIssue.paragraph, same(h.paragraphs.first));
      final firstMarks = h.session.paintFindingsLookup!(firstIssue.paragraph);
      expect(firstMarks, hasLength(20));
      expect(h.session.checking, isTrue);
      expect(h.session.summary.hasResults, isTrue);
      expect(h.session.summary.checkedParagraphCount, 1);
      expect(h.session.summary.complete, isFalse);
      expect(h.session.isCurrent(firstIssue), isTrue);
      final generation = h.session.checkGeneration;

      second.complete();
      await h.provider.started('Feler third');
      expect(h.session.summary.issues, hasLength(21));
      expect(
        h.session.paintFindingsLookup!(firstIssue.paragraph),
        same(firstMarks),
      );
      expect(h.session.summary.issues.first, same(firstIssue));
      expect(h.session.isCurrent(firstIssue), isTrue);
      expect(h.session.checkGeneration, generation);

      third.complete();
      final complete = await pending;
      expect(complete.complete, isTrue);
      expect(complete.checkedParagraphCount, 3);
      expect(complete.issues, hasLength(22));
      expect(complete.issues.first, same(firstIssue));
      expect(
        h.session.paintFindingsLookup!(firstIssue.paragraph),
        same(firstMarks),
      );
      expect(h.session.checkGeneration, generation);
    },
  );

  test(
    'editing after partial progress discards a late result generation',
    () async {
      final h = _Harness(['Feler first', 'Feler second']);
      h.session.enabled = true;
      final gate = h.provider.gate('Feler second');
      final pending = h.session.checkNow();
      await h.provider.started('Feler second');
      final old = h.session.summary.issues.single;
      final generation = h.session.checkGeneration;
      h.edit(0, 'Correct first');

      expect(h.session.checkGeneration, greaterThan(generation));
      expect(h.session.summary.scheduled, isTrue);
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.isCurrent(old), isFalse);
      gate.complete();
      await pending;
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.summary.scheduled, isTrue);

      await h.session.checkNow(includeManualProviders: false);
      expect(
        h.session.summary.issues.single.paragraph,
        same(h.paragraphs.last),
      );
      expect(h.session.summary.issues.single.finding.revision, h.revision);
    },
  );

  test(
    'cached single-run snapshots check live language and no-proof changes',
    () async {
      final h = _Harness(['Feler single run']);
      final german = (await h.session.checkNow()).issues.single;
      expect(h.session.isCurrent(german), isTrue);

      h.document.proofingLanguage = 'en-GB';
      expect(h.session.isCurrent(german), isFalse);
      final english = (await h.session.checkNow()).issues.single;
      expect(h.provider.requests.last.language, 'en-GB');
      expect(h.session.isCurrent(english), isTrue);

      final run = h.paragraphs.single.inlines.single as WmlRun;
      run.properties = WmlRunProps(noProof: true);
      expect(h.session.isCurrent(english), isFalse);
      expect((await h.session.checkNow()).issues, isEmpty);
    },
  );

  test(
    'warm single-run snapshots track complex-script language inputs',
    () async {
      final h = _Harness(['Feler']);
      h.document.complexScriptLanguage = 'ar-SA';
      final paragraph = h.paragraphs.single;
      final run = paragraph.inlines.single as WmlRun;
      final latin = (await h.session.checkNow()).issues.single;
      expect(latin.language, 'de-DE');

      run.properties.complexScriptLanguage = 'he-IL';
      expect(h.session.isCurrent(latin), isTrue);
      run.properties.complexScript = true;
      expect(h.session.isCurrent(latin), isFalse);
      final hebrew = (await h.session.checkNow()).issues.single;
      expect(hebrew.language, 'he-IL');

      run.properties.complexScriptLanguage = null;
      expect(h.session.isCurrent(hebrew), isFalse);
      final inherited = (await h.session.checkNow()).issues.single;
      expect(inherited.language, 'ar-SA');
      expect(h.session.isCurrent(inherited), isTrue);

      run.properties.complexScript = false;
      expect(h.session.isCurrent(inherited), isFalse);
      expect((await h.session.checkNow()).issues.single.language, 'de-DE');
    },
  );

  test(
    'direct structural edits are validated before intermediate publication',
    () async {
      final h = _Harness(['Feler first', 'Feler second']);
      final offscreen = _CountedParagraph('Feler third');
      h.document.sections.single.blocks.add(offscreen);
      final gate = h.provider.gate('Feler first');
      final pending = h.session.checkNow();
      await h.provider.started('Feler first');
      offscreen.reads = 0;
      // The host forgot refresh/revision; pending results must still not expose
      // generated field content at the next progress publication.
      h.paragraphs.first.properties.pageNumberField = true;
      gate.complete();
      await pending;
      expect(h.session.checking, isFalse);
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.findingsByParagraph, isEmpty);
      expect(h.session.summary.hasResults, isFalse);
      expect(h.provider.requests, hasLength(1));
      // The replacement summary reads later paragraphs once. Validation of
      // the rejected publication stops at the first changed paragraph.
      expect(offscreen.reads, 1);
    },
  );

  test('a detach during progress prunes the paragraph before reuse', () async {
    final h = _Harness(['Feler first', 'Feler second', 'Feler third']);
    final [first, detached, third] = h.paragraphs;
    final gate = h.provider.gate('Feler third');
    final pending = h.session.checkNow();
    await h.provider.started('Feler third');
    expect(h.session.summary.issues.map((issue) => issue.paragraph), [
      first,
      detached,
    ]);

    final blocks = h.document.sections.single.blocks;
    blocks.remove(detached);
    gate.complete();
    final updated = await pending;
    expect(updated.issues.map((issue) => issue.paragraph), [first, third]);

    blocks.insert(1, detached);
    h.changed();
    expect((await h.session.checkNow()).issues, hasLength(3));
    expect(h.provider.requests.map((request) => request.text), [
      'Feler first',
      'Feler second',
      'Feler third',
      'Feler second',
    ]);
  });

  for (final change in ['detach', 'story', 'noProof', 'language']) {
    test(
      '$change invalidates affected findings and preserves other paragraphs',
      () async {
        final h = _Harness(['Feler first', 'Feler second']);
        await h.session.checkNow();
        final first = h.paragraphs.first;
        final second = h.paragraphs.last;
        final old = h.session.summary.issues.first;
        switch (change) {
          case 'detach':
            h.document.sections.first.blocks.remove(first);
          case 'story':
            h.document.sections.first.blocks.remove(first);
            h.document.sections.first.header.add(first);
          case 'noProof':
            (first.inlines.first as WmlRun).properties.noProof = true;
          case 'language':
            first.properties.proofingLanguage = 'en-GB';
        }
        h.changed();
        expect(h.session.isCurrent(old), isFalse);
        expect(h.session.summary.issues.single.paragraph, same(second));
        expect(h.session.isCurrent(h.session.summary.issues.single), isTrue);
        await h.session.checkNow();
        if (change == 'story') {
          final moved = h.session.summary.issues.firstWhere(
            (issue) => identical(issue.paragraph, first),
          );
          expect(moved.story, 'Header · section 1');
          expect(h.session.isCurrent(moved), isTrue);
        } else if (change == 'language') {
          final changed = h.session.summary.issues.firstWhere(
            (issue) => identical(issue.paragraph, first),
          );
          expect(changed.language, 'en-GB');
        } else {
          expect(h.session.summary.issues.single.paragraph, same(second));
        }
      },
    );
  }

  test(
    'provider and document-language changes invalidate cached findings immediately',
    () async {
      final h = _Harness(['Feler first', 'Feler second']);
      await h.session.checkNow();
      final old = h.session.summary.issues.first;
      h.provider.version++;
      h.session.observeDocument();
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.isCurrent(old), isFalse);
      await h.session.checkNow();
      expect(h.provider.requests, hasLength(4));
      h.document.proofingLanguage = 'en-US';
      h.session.observeDocument();
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.summary.hasResults, isFalse);
    },
  );

  test(
    'new documents cannot inherit cached results even when paragraphs are reused',
    () async {
      final h = _Harness(['Feler first', 'Feler second']);
      await h.session.checkNow();
      final old = h.session.summary.issues.first;
      final paragraphs = h.paragraphs;
      h.document = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
      h.changed();
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.summary.hasResults, isFalse);
      await h.session.checkNow();
      expect(h.provider.requests, hasLength(4));
      expect(
        h.session.summary.issues.first.finding.documentId,
        isNot(old.finding.documentId),
      );
    },
  );

  test(
    'background retains ordinary results from failed full checks without invoking manual providers',
    () async {
      final h = _Harness(['Feler first', 'Feler second']);
      final manual = _Provider(
        'manual',
        status: OfficeProofingStatus.unavailable,
      );
      h.session.configureManual(OfficeProofingService(providers: [manual]));
      final explicit = await h.session.checkNow();
      expect(explicit.complete, isFalse);
      expect(explicit.issues, hasLength(2));
      expect(manual.requests, hasLength(2));

      h.edit(0, 'Correct first');
      expect(
        h.session.summary.issues.single.paragraph,
        same(h.paragraphs.last),
      );
      expect(
        h.session.summary.reports.single.results.map(
          (result) => result.providerId,
        ),
        ['ordinary'],
      );
      expect(h.session.summary.manualProvidersSkipped, isTrue);
      expect(manual.requests, hasLength(2));
      final background = await h.session.checkNow(
        includeManualProviders: false,
      );
      expect(background.issues.single.finding.providerId, 'ordinary');
      expect(background.manualProvidersSkipped, isTrue);
      expect(background.complete, isFalse);
      expect(manual.requests, hasLength(2));
      expect(h.provider.requests, hasLength(3));

      manual.status = OfficeProofingStatus.success;
      final retried = await h.session.checkNow();
      expect(retried.complete, isTrue);
      expect(manual.requests, hasLength(4));
    },
  );

  test(
    'ordinary previews stay actionable but do not count as full manual coverage',
    () async {
      final h = _Harness(['Feler first']);
      final manual = _Provider('manual');
      h.session.configureManual(OfficeProofingService(providers: [manual]));
      await h.session.checkNow(includeManualProviders: false);
      final existing = h.session.summary.issues.single;
      final gate = manual.gate('Feler first');
      final pending = h.session.checkNow();
      await manual.started('Feler first');
      expect(h.session.summary.issues.single, same(existing));
      expect(h.session.canCorrect(existing), isTrue);
      expect(h.session.summary.checkedParagraphCount, 0);
      expect(h.session.summary.complete, isFalse);
      gate.complete();
      expect((await pending).complete, isTrue);
    },
  );

  test(
    'explicit checks share their future after progress and invalidate it after edits',
    () async {
      final ordinary = _Provider('ordinary');
      final manual = _Provider('manual');
      final controller = WordEditorController(
        document: _document(['Feler first', 'Feler second']),
        proofingService: OfficeProofingService(providers: [ordinary]),
      );
      addTearDown(controller.dispose);
      controller.proofing.configureManual(
        OfficeProofingService(providers: [manual]),
      );
      final gate = manual.gate('Feler second');
      final first = controller.checkDocumentProofing();
      final initialSummary = controller.proofing.summary;
      await manual.started('Feler second');
      expect(controller.proofing.summary, isNot(same(initialSummary)));
      expect(controller.proofing.summary.checkedParagraphCount, 1);
      expect(controller.checkDocumentProofing(), same(first));
      expect(manual.requests, hasLength(2));

      controller.document.paragraphs.first.inlines = [
        WmlRun(text: 'Correct first'),
      ];
      controller.refresh();
      final fresh = controller.checkDocumentProofing();
      expect(fresh, isNot(same(first)));
      gate.complete();
      await Future.wait([first, fresh]);
      expect(controller.proofing.summary.complete, isTrue);
      expect(
        controller.proofing.summary.issues.single.paragraph,
        same(controller.document.paragraphs.last),
      );
    },
  );

  test(
    'a retained finding remains an undoable controller correction while another check waits',
    () async {
      final provider = _Provider('ordinary');
      final controller = WordEditorController(
        document: _document(['Feler first', 'Feler second']),
        proofingService: OfficeProofingService(providers: [provider]),
      );
      addTearDown(controller.dispose);
      await controller.proofing.checkNow();
      final first = controller.document.paragraphs.first;
      controller.document.paragraphs.last.inlines = [
        WmlRun(text: 'Wait second'),
      ];
      controller.refresh();
      final retained = controller.proofing.summary.issues.single;
      final gate = provider.gate('Wait second');
      final pending = controller.proofing.checkNow(
        includeManualProviders: false,
      );
      await provider.started('Wait second');
      expect(controller.proofing.canCorrect(retained), isTrue);
      expect(controller.applyProofingSuggestion(retained, 'Fehler'), isTrue);
      expect(first.text, 'Fehler first');
      expect(controller.proofing.isCurrent(retained), isFalse);
      gate.complete();
      await pending;
      controller.undo();
      expect(first.text, 'Feler first');
      expect(controller.document.paragraphs.last.text, 'Wait second');
    },
  );
}

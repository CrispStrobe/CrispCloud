import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _Provider extends OfficeProofingProvider {
  _Provider(this.id, {this.status = OfficeProofingStatus.success});

  @override
  final String id;
  OfficeProofingStatus status;
  int version = 0;
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
      final h = _Harness(['Feler first', 'Feler second', 'Feler third']);
      final second = h.provider.gate('Feler second');
      final third = h.provider.gate('Feler third');
      final pending = h.session.checkNow();
      await h.provider.started('Feler second');

      final firstIssue = h.session.summary.issues.single;
      expect(firstIssue.paragraph, same(h.paragraphs.first));
      expect(h.session.checking, isTrue);
      expect(h.session.summary.hasResults, isTrue);
      expect(h.session.summary.checkedParagraphCount, 1);
      expect(h.session.summary.complete, isFalse);
      expect(h.session.isCurrent(firstIssue), isTrue);
      final generation = h.session.checkGeneration;

      second.complete();
      await h.provider.started('Feler third');
      expect(h.session.summary.issues, hasLength(2));
      expect(h.session.summary.issues.first, same(firstIssue));
      expect(h.session.isCurrent(firstIssue), isTrue);
      expect(h.session.checkGeneration, generation);

      third.complete();
      final complete = await pending;
      expect(complete.complete, isTrue);
      expect(complete.checkedParagraphCount, 3);
      expect(complete.issues.first, same(firstIssue));
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
    'direct structural edits are validated before intermediate publication',
    () async {
      final h = _Harness(['Feler first', 'Feler second', 'Feler third']);
      final gate = h.provider.gate('Feler first');
      final pending = h.session.checkNow();
      await h.provider.started('Feler first');
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
    },
  );

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

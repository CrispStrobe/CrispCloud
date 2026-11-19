import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _Provider extends OfficeProofingProvider {
  _Provider(this.id);

  @override
  final String id;
  int version = 0;
  bool supported = true;
  bool disposed = false;
  bool invalidRange = false;
  OfficeProofingStatus status = OfficeProofingStatus.success;
  final requests = <OfficeProofingRequest>[];
  final gates = <String, Completer<void>>{};
  final starts = <String, Completer<void>>{};

  @override
  int get configurationRevision => version;

  @override
  bool supportsLanguage(String language) => supported;

  Future<void> started(String text) =>
      (starts[text] ??= Completer<void>()).future;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    final started = starts[request.text] ??= Completer<void>();
    if (!started.isCompleted) started.complete();
    await gates[request.text]?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.success ? null : 'Unavailable.',
      findings: [
        if (status == OfficeProofingStatus.success)
          for (final match in RegExp('Feler').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: 'draft-spelling',
              message: 'Check spelling.',
              category: OfficeProofingCategory.spelling,
              replacements: const ['Fehler'],
            ),
        if (invalidRange)
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: 1,
            end: 2,
            ruleId: 'split-grapheme',
            message: 'Invalid provider range.',
            category: OfficeProofingCategory.grammar,
          ),
      ],
    );
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Harness {
  _Harness() {
    session = WordProofingSession(
      document: () => document,
      revision: () => revision,
      service: OfficeProofingService(providers: [ordinary]),
      debounce: const Duration(days: 1),
    );
    session.enabled = true;
    addTearDown(close);
  }

  WmlDocument document = WmlDocument.empty(text: 'Body Feler');
  int revision = 0;
  final ordinary = _Provider('ordinary');
  late final WordProofingSession session;
  bool closed = false;

  void close() {
    if (closed) return;
    closed = true;
    session.dispose();
  }
}

void main() {
  test(
    'drafts use ordinary providers without changing document coverage',
    () async {
      final h = _Harness();
      final manual = _Provider('manual');
      h.session.configureManual(OfficeProofingService(providers: [manual]));
      final summary = h.session.summary;
      final generation = h.session.checkGeneration;

      final result = (await h.session.checkDraft('Draft Feler'))!;

      expect(result.sourceText, 'Draft Feler');
      expect(result.language, 'de-DE');
      expect(result.report.complete, isTrue);
      expect(result.report.findings.single.originalText, 'Feler');
      expect(
        h.session.isDraftResultCurrent(result, text: 'Draft Feler'),
        isTrue,
      );
      expect(h.session.summary, same(summary));
      expect(h.session.checkGeneration, generation);
      expect(h.session.findingsByParagraph, isEmpty);
      expect(h.document.paragraphs.single.text, 'Body Feler');
      expect(manual.requests, isEmpty);
      expect(h.ordinary.disposed, isFalse);
    },
  );

  test(
    'draft and document checks keep independent result identities',
    () async {
      final h = _Harness();
      final gate = h.ordinary.gates['Body Feler'] = Completer<void>();
      final body = h.session.checkNow(includeManualProviders: false);
      await h.ordinary.started('Body Feler');
      final summary = h.session.summary;
      final generation = h.session.checkGeneration;

      final draft = (await h.session.checkDraft('Draft Feler'))!;
      expect(h.session.summary, same(summary));
      expect(h.session.checkGeneration, generation);
      expect(h.session.checking, isTrue);
      expect(
        draft.report.request.blockId,
        isNot(h.ordinary.requests.first.blockId),
      );

      gate.complete();
      final completed = await body;
      expect(completed.issues.single.sourceText, 'Body Feler');
      expect(completed.paragraphCount, 1);
      expect(completed.complete, isTrue);
      expect(
        h.session.isDraftResultCurrent(draft, text: 'Draft Feler'),
        isTrue,
      );
    },
  );

  test('unrelated body edits retain a current detached draft', () async {
    final h = _Harness();
    final result = (await h.session.checkDraft('Draft Feler'))!;
    final configuration = h.session.draftConfigurationKey;
    h.document.paragraphs.single.inlines = [WmlRun(text: 'Changed body')];
    h.revision++;
    h.session.observeDocument();

    expect(h.session.draftConfigurationKey, configuration);
    expect(h.session.isDraftResultCurrent(result, text: 'Draft Feler'), isTrue);
    expect(h.session.isDraftResultCurrent(result, text: 'New Feler'), isFalse);
    final other = _Harness();
    expect(
      other.session.isDraftResultCurrent(result, text: 'Draft Feler'),
      isFalse,
    );
  });

  final invalidations = <String, void Function(_Harness)>{
    'document replacement': (h) {
      h.document = WmlDocument.empty(text: 'Body Feler');
      h.session.observeDocument();
    },
    'language': (h) {
      h.document.proofingLanguage = 'en-GB';
      h.session.refresh();
    },
    'personal vocabulary': (h) {
      h.session.vocabulary.addWord('Feler');
      h.session.refresh();
    },
    'ignored rule': (h) => h.session.ignoreRule('draft-spelling'),
    'provider configuration revision': (h) {
      h.ordinary.version++;
      h.session.refresh();
    },
    'provider replacement': (h) => h.session.configure(
      OfficeProofingService(providers: [_Provider('replacement')]),
    ),
    'checking paused': (h) => h.session.enabled = false,
    'checking paused and resumed': (h) {
      h.session.enabled = false;
      h.session.enabled = true;
    },
    'disposal': (h) => h.close(),
  };
  for (final invalidation in invalidations.entries) {
    test(
      '${invalidation.key} rejects existing and late draft results',
      () async {
        final h = _Harness();
        final current = (await h.session.checkDraft('Current Feler'))!;
        final gate = h.ordinary.gates['Pending Feler'] = Completer<void>();
        final pending = h.session.checkDraft('Pending Feler');
        await h.ordinary.started('Pending Feler');

        invalidation.value(h);

        expect(
          h.session.isDraftResultCurrent(current, text: 'Current Feler'),
          isFalse,
        );
        gate.complete();
        expect(await pending, isNull);
      },
    );
  }

  test('draft results share language-scoped words and ignored rules', () async {
    final h = _Harness();
    h.session.vocabulary.ignoreWord('Feler', language: 'en-US');
    expect(
      (await h.session.checkDraft('Feler'))!.report.findings,
      hasLength(1),
    );
    h.document.proofingLanguage = 'en-US';
    final ignoredWord = (await h.session.checkDraft('Feler'))!;
    expect(ignoredWord.report.findings, isEmpty);
    expect(ignoredWord.report.complete, isTrue);
    h.document.proofingLanguage = 'de-DE';
    h.session.ignoreRule('draft-spelling');
    expect((await h.session.checkDraft('Feler'))!.report.findings, isEmpty);
  });

  test('paused checking does not call a draft provider', () async {
    final h = _Harness();
    h.session.enabled = false;
    expect(await h.session.checkDraft('Feler'), isNull);
    expect(h.ordinary.requests, isEmpty);
  });

  test(
    'multiple composers share one running check and only the latest pending draft',
    () async {
      final h = _Harness();
      final gate = h.ordinary.gates['First Feler'] = Completer<void>();
      final first = h.session.checkDraft('First Feler');
      await h.ordinary.started('First Feler');
      final superseded = h.session.checkDraft('Second Feler');
      final last = h.session.checkDraft('Latest Feler');
      expect(await superseded, isNull);
      expect(h.ordinary.requests.map((r) => r.text), ['First Feler']);
      gate.complete();
      expect((await first)!.sourceText, 'First Feler');
      expect((await last)!.sourceText, 'Latest Feler');
      expect(h.ordinary.requests.map((r) => r.text), [
        'First Feler',
        'Latest Feler',
      ]);
    },
  );

  test('obsolete queued configuration never reaches a provider', () async {
    final h = _Harness();
    final gate = h.ordinary.gates['First Feler'] = Completer<void>();
    final first = h.session.checkDraft('First Feler');
    await h.ordinary.started('First Feler');
    final queued = h.session.checkDraft('Queued Feler');
    h.session.enabled = false;
    h.session.enabled = true;
    gate.complete();
    expect(await first, isNull);
    expect(await queued, isNull);
    expect(h.ordinary.requests.map((r) => r.text), ['First Feler']);
  });

  test(
    'empty and over-limit drafts retain honest incomplete coverage',
    () async {
      final h = _Harness();
      final empty = (await h.session.checkDraft(' \n\t'))!;
      final long = (await h.session.checkDraft(
        'a' * (WordProofingSession.maxDraftLength + 1),
      ))!;
      expect(empty.report.complete, isFalse);
      expect(long.report.complete, isFalse);
      expect(long.report.results.single.message, contains('too long'));
      expect(h.ordinary.requests, isEmpty);
      final boundary = (await h.session.checkDraft(
        'a' * WordProofingSession.maxDraftLength,
      ))!;
      expect(boundary.report.complete, isTrue);
      expect(h.ordinary.requests, hasLength(1));
    },
  );

  test(
    'unavailable and unsupported providers never imply a clean draft',
    () async {
      final h = _Harness();
      h.ordinary.status = OfficeProofingStatus.unavailable;
      final unavailable = (await h.session.checkDraft('Feler'))!;
      expect(unavailable.report.isClean, isFalse);
      expect(unavailable.report.findings, isEmpty);
      h.ordinary.supported = false;
      final unsupported = (await h.session.checkDraft('Feler'))!;
      expect(unsupported.report.complete, isFalse);
      expect(
        unsupported.report.results.single.status,
        OfficeProofingStatus.unsupported,
      );
    },
  );

  test('drafts keep the service grapheme-boundary validation', () async {
    final h = _Harness();
    h.ordinary.invalidRange = true;
    final result = (await h.session.checkDraft('😀 Feler'))!;
    expect(result.report.complete, isFalse);
    expect(result.report.findings, isEmpty);
    expect(result.report.results.single.status, OfficeProofingStatus.failed);
  });
}

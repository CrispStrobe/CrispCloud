import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _ManualProbe extends OfficeProofingProvider {
  _ManualProbe(
    this.id, {
    this.range,
    this.status = OfficeProofingStatus.success,
    this.languages = const {'de-DE'},
  });
  @override
  final String id;
  final ({int start, int end})? range;
  final OfficeProofingStatus status;
  final Set<String> languages;
  final started = Completer<void>();
  Completer<void>? gate;
  int calls = 0;
  int disposals = 0;

  @override
  bool supportsLanguage(String language) => languages.contains(language);

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.success
          ? null
          : 'Model unavailable.',
      findings: [
        if (range case final bounds?
            when status == OfficeProofingStatus.success)
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: bounds.start,
            end: bounds.end,
            ruleId: '$id-rule',
            category: OfficeProofingCategory.grammar,
            message: 'Review this word.',
            replacements: const ['bist'],
          ),
      ],
    );
  }

  @override
  Future<void> dispose() async => disposals++;
}

final class _RecordingService extends OfficeProofingService {
  _RecordingService(OfficeProofingProvider provider)
    : super(providers: [provider]);

  final reports = <OfficeProofingReport>[];

  @override
  Future<OfficeProofingReport> check(
    OfficeProofingRequest request, {
    bool Function(OfficeProofingProvider provider)? only,
  }) async {
    final report = await super.check(request, only: only);
    reports.add(report);
    return report;
  }
}

void main() {
  late WmlDocument document;
  late int revision;
  late _ManualProbe ordinary;
  late _RecordingService ordinaryService;
  late _ManualProbe manual;
  late WordProofingSession session;

  setUp(() {
    document = WmlDocument.empty(text: 'Du ist hier.');
    document.proofingLanguage = 'de-DE';
    revision = 0;
    ordinary = _ManualProbe('rules');
    ordinaryService = _RecordingService(ordinary);
    manual = _ManualProbe('model', range: (start: 3, end: 6));
    session = WordProofingSession(
      document: () => document,
      revision: () => revision,
      service: ordinaryService,
      debounce: Duration.zero,
    );
    addTearDown(session.dispose);
  });

  test(
    'typing never invokes the manual model and reports omitted coverage',
    () async {
      session.configureManual(OfficeProofingService(providers: [manual]));
      final finished = Completer<WordProofingSummary>();
      session.addListener(() {
        if (session.summary.hasResults &&
            !session.checking &&
            !finished.isCompleted) {
          finished.complete(session.summary);
        }
      });
      session.enabled = true;
      final background = await finished.future.timeout(
        const Duration(seconds: 2),
      );
      expect(ordinary.calls, 1);
      expect(manual.calls, 0);
      expect(background.manualProvidersSkipped, isTrue);
      expect(background.complete, isFalse);
      expect(background.statusMessage, contains('manual grammar check'));
      session.enabled = false;
      final explicit = await session.checkNow();
      expect(manual.calls, 1);
      expect(explicit.complete, isTrue);
      expect(explicit.issues.single.finding.providerId, 'model');
    },
  );

  test('manual and background caches cannot stand in for each other', () async {
    session.configureManual(OfficeProofingService(providers: [manual]));
    await session.checkNow(includeManualProviders: false);
    expect(manual.calls, 0);
    await session.checkNow();
    expect(manual.calls, 1);
    await session.checkNow();
    expect(manual.calls, 1);
    final original = ordinaryService.reports.last;
    final background = await session.checkNow(includeManualProviders: false);
    expect(background.reports.single, same(original));
    expect(ordinary.calls, 2);
    expect(background.issues, isEmpty);
    expect(background.manualProvidersSkipped, isTrue);
    await session.checkNow();
    expect(manual.calls, 2);
  });

  test(
    'an unsupported manual locale does not reduce background coverage',
    () async {
      document = WmlDocument.empty(text: 'This text is correct.');
      document.proofingLanguage = 'en-US';
      final english = _ManualProbe('english', languages: const {'en-US'});
      session.configure(OfficeProofingService(providers: [english]));
      session.configureManual(OfficeProofingService(providers: [manual]));

      final background = await session.checkNow(includeManualProviders: false);
      expect(background.complete, isTrue);
      expect(background.manualProvidersSkipped, isFalse);
      expect(background.statusMessage, isNot(contains('manual grammar check')));
      expect(english.calls, 1);
      expect(manual.calls, 0);

      final explicit = await session.checkNow();
      expect(explicit.complete, isTrue);
      expect(
        explicit.reports.single.results.last.status,
        OfficeProofingStatus.unsupported,
      );
      expect(manual.calls, 0);
    },
  );

  test(
    'a supported run still reports omitted manual coverage in a mixed document',
    () async {
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'This is English. '),
          WmlRun(
            text: 'Du ist hier.',
            properties: WmlRunProps(proofingLanguage: 'de_DE'),
          ),
        ],
      );
      document = WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      document.proofingLanguage = 'en-US';
      final bilingual = _ManualProbe(
        'bilingual',
        languages: const {'en-US', 'de-DE'},
      );
      session.configure(OfficeProofingService(providers: [bilingual]));
      session.configureManual(OfficeProofingService(providers: [manual]));

      final background = await session.checkNow(includeManualProviders: false);
      expect(background.checkedParagraphCount, 1);
      expect(background.manualProvidersSkipped, isTrue);
      expect(background.complete, isFalse);
      expect(bilingual.calls, 2);
      expect(manual.calls, 0);

      final explicit = await session.checkNow();
      expect(explicit.complete, isTrue);
      expect(manual.calls, 1);
      expect(explicit.issues.single.finding.start, 20);
      expect(explicit.issues.single.finding.end, 23);
      expect(explicit.issues.single.finding.originalText, 'ist');
    },
  );

  test(
    'manual failure stays visible alongside successful ordinary checking',
    () async {
      final failed = _ManualProbe(
        'missing-model',
        status: OfficeProofingStatus.unavailable,
      );
      session.configureManual(OfficeProofingService(providers: [failed]));
      final summary = await session.checkNow();
      expect(summary.complete, isFalse);
      expect(summary.statusMessage, contains('Model unavailable'));
      expect(summary.reports.single.results.map((result) => result.status), [
        OfficeProofingStatus.success,
        OfficeProofingStatus.unavailable,
      ]);
    },
  );

  test(
    'deterministic findings take precedence over competing model proposals',
    () async {
      final deterministic = _ManualProbe(
        'deterministic',
        range: (start: 3, end: 6),
      );
      session.configure(OfficeProofingService(providers: [deterministic]));
      session.configureManual(OfficeProofingService(providers: [manual]));
      final summary = await session.checkNow();
      expect(summary.complete, isTrue);
      expect(summary.issues.single.finding.providerId, 'deterministic');
      expect(summary.reports.single.results, hasLength(2));
      expect(summary.reports.single.results.last.findings, isEmpty);
    },
  );

  test('configuration refuses shared ownership and duplicate provider IDs', () {
    expect(
      () =>
          session.configureManual(OfficeProofingService(providers: [ordinary])),
      throwsArgumentError,
    );
    expect(
      () => session.configureManual(
        OfficeProofingService(providers: [_ManualProbe('rules')]),
      ),
      throwsArgumentError,
    );
    session.configureManual(OfficeProofingService(providers: [manual]));
    expect(
      () => session.configure(
        OfficeProofingService(providers: [_ManualProbe('model')]),
      ),
      throwsArgumentError,
    );
  });

  test(
    'replacing a service cannot dispose providers still in the replacement',
    () {
      session.configureManual(OfficeProofingService(providers: [manual]));
      expect(
        () =>
            session.configureManual(OfficeProofingService(providers: [manual])),
        throwsArgumentError,
      );
      expect(
        () => session.configure(OfficeProofingService(providers: [ordinary])),
        throwsArgumentError,
      );
      expect(manual.disposals, 0);
      expect(ordinary.disposals, 0);
      final replacement = _ManualProbe('model');
      session.configureManual(OfficeProofingService(providers: [replacement]));
      expect(manual.disposals, 1);
      expect(replacement.disposals, 0);
    },
  );

  test(
    'replacing or clearing manual service disposes it and invalidates results',
    () async {
      session.configureManual(OfficeProofingService(providers: [manual]));
      await session.checkNow();
      expect(session.summary.issues, hasLength(1));
      session.configureManual(null);
      expect(manual.disposals, 1);
      expect(session.hasManualProviders, isFalse);
      expect(session.summary.hasResults, isFalse);
      expect((await session.checkNow()).issues, isEmpty);
    },
  );

  test('changed document rejects an in-flight manual result', () async {
    manual.gate = Completer<void>();
    session.configureManual(OfficeProofingService(providers: [manual]));
    final pending = session.checkNow();
    await manual.started.future;
    document = WmlDocument.empty(text: 'Alles stimmt.');
    revision++;
    session.observeDocument();
    manual.gate!.complete();
    await pending;
    expect(session.summary.hasResults, isFalse);
    expect(session.summary.issues, isEmpty);
  });

  test('session disposal owns both services exactly once', () async {
    session.configureManual(OfficeProofingService(providers: [manual]));
    session.dispose();
    session.dispose();
    expect(ordinary.disposals, 1);
    expect(manual.disposals, 1);
    expect(() => session.configureManual(null), throwsStateError);
    expect(
      () => session.configure(OfficeProofingService(providers: [])),
      throwsStateError,
    );
  });
}

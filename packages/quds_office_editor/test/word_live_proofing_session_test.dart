import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _LiveProvider extends OfficeProofingProvider {
  _LiveProvider(this.id);

  @override
  final String id;
  final List<OfficeProofingRequest> requests = [];
  Completer<void>? gate;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    await gate?.future;
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
            ruleId: '$id-spelling',
            message: 'Check spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['Fehler'],
          ),
      ],
    );
  }
}

final class _LiveSession {
  _LiveSession() {
    session = WordProofingSession(
      document: () => document,
      revision: () => revision,
      service: OfficeProofingService(providers: [provider]),
      debounce: const Duration(milliseconds: 100),
    );
    addTearDown(session.dispose);
  }

  final document = WmlDocument.empty(text: 'Ein Feler.');
  final provider = _LiveProvider('ordinary');
  int revision = 0;
  late final WordProofingSession session;

  void edit(String text) {
    document.paragraphs.single.inlines = [WmlRun(text: text)];
    revision++;
    session.observeDocument();
  }
}

void main() {
  testWidgets('standalone sessions do not start background checks', (
    tester,
  ) async {
    final h = _LiveSession();
    h.session.observeDocument();
    h.edit('Another Feler.');
    await tester.pump(const Duration(seconds: 1));

    expect(h.session.enabled, isFalse);
    expect(h.session.summary.scheduled, isFalse);
    expect(h.session.checking, isFalse);
    expect(h.session.summary.hasResults, isFalse);
    expect(h.provider.requests, isEmpty);
  });

  testWidgets(
    'default checking distinguishes debounce from running and repeated attachment does not restart it',
    (tester) async {
      final h = _LiveSession();
      final gate = Completer<void>();
      h.provider.gate = gate;
      h.session.enableBackgroundByDefault();

      expect(h.session.enabled, isTrue);
      expect(h.session.summary.scheduled, isTrue);
      expect(h.session.checking, isFalse);
      expect(h.session.summary.complete, isFalse);
      expect(h.session.summary.statusMessage, 'Waiting for a pause in typing…');
      await tester.pump(const Duration(milliseconds: 99));
      expect(h.provider.requests, isEmpty);

      h.session.enableBackgroundByDefault();
      await tester.pump(const Duration(milliseconds: 1));
      expect(h.provider.requests, hasLength(1));
      expect(h.session.summary.scheduled, isFalse);
      expect(h.session.checking, isTrue);
      expect(h.session.summary.statusMessage, 'Checking document…');

      gate.complete();
      await tester.pump();
      expect(h.session.summary.scheduled, isFalse);
      expect(h.session.checking, isFalse);
      expect(h.session.summary.complete, isTrue);
      expect(h.session.summary.issues, hasLength(1));
      final completed = h.session.summary;

      h.session.enableBackgroundByDefault();
      await tester.pump(const Duration(seconds: 1));
      expect(h.provider.requests, hasLength(1));
      expect(h.session.summary, same(completed));
    },
  );

  for (final chooseBeforeAttachment in [true, false]) {
    testWidgets(
      'explicit false ${chooseBeforeAttachment ? 'before' : 'after'} attachment survives repeated attachment and edits',
      (tester) async {
        final h = _LiveSession();
        if (!chooseBeforeAttachment) h.session.enableBackgroundByDefault();
        h.session.enabled = false;
        h.session.enableBackgroundByDefault();
        h.session.enableBackgroundByDefault();
        h.edit('Another Feler.');
        h.session.enableBackgroundByDefault();
        await tester.pump(const Duration(seconds: 1));

        expect(h.session.enabled, isFalse);
        expect(h.session.summary.scheduled, isFalse);
        expect(h.session.checking, isFalse);
        expect(h.provider.requests, isEmpty);

        h.session.enabled = true;
        expect(h.session.summary.scheduled, isTrue);
        await tester.pump(const Duration(milliseconds: 100));
        expect(h.provider.requests, hasLength(1));
        expect(h.session.summary.issues, hasLength(1));
      },
    );
  }

  testWidgets('editing rejects late replies while the new pass is scheduled', (
    tester,
  ) async {
    final h = _LiveSession();
    final gate = Completer<void>();
    h.provider.gate = gate;
    h.session.enableBackgroundByDefault();
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.provider.requests, hasLength(1));
    expect(h.session.checking, isTrue);

    h.edit('Correct now.');
    expect(h.session.summary.scheduled, isTrue);
    expect(h.session.checking, isFalse);
    expect(h.session.summary.hasResults, isFalse);
    h.provider.gate = null;
    gate.complete();
    await tester.pump(const Duration(milliseconds: 10));

    expect(h.session.summary.scheduled, isTrue);
    expect(h.session.summary.hasResults, isFalse);
    expect(h.session.summary.issues, isEmpty);
    expect(h.session.findingsByParagraph, isEmpty);
    await tester.pump(const Duration(milliseconds: 90));
    expect(h.provider.requests.map((request) => request.text), [
      'Ein Feler.',
      'Correct now.',
    ]);
    expect(h.session.summary.scheduled, isFalse);
    expect(h.session.summary.complete, isTrue);
    expect(h.session.summary.issues, isEmpty);
  });

  testWidgets('typing removes old findings and restarts the debounce', (
    tester,
  ) async {
    final h = _LiveSession();
    h.session.enableBackgroundByDefault();
    await tester.pump(const Duration(milliseconds: 100));
    final old = h.session.summary.issues.single;
    expect(h.session.isCurrent(old), isTrue);
    expect(h.session.findingsByParagraph, isNotEmpty);

    h.edit('Correct');
    expect(h.session.isCurrent(old), isFalse);
    expect(h.session.findingsByParagraph, isEmpty);
    expect(h.session.summary.scheduled, isTrue);
    await tester.pump(const Duration(milliseconds: 60));
    h.edit('Correct now.');
    await tester.pump(const Duration(milliseconds: 60));
    expect(h.provider.requests, hasLength(1));
    expect(h.session.summary.scheduled, isTrue);

    await tester.pump(const Duration(milliseconds: 40));
    expect(h.provider.requests, hasLength(2));
    expect(h.provider.requests.last.text, 'Correct now.');
    expect(h.session.summary.complete, isTrue);
    expect(h.session.summary.issues, isEmpty);
  });

  testWidgets('default background passes never invoke manual providers', (
    tester,
  ) async {
    final h = _LiveSession();
    final manual = _LiveProvider('manual');
    h.session.configureManual(OfficeProofingService(providers: [manual]));
    h.session.enableBackgroundByDefault();
    await tester.pump(const Duration(milliseconds: 100));

    expect(manual.requests, isEmpty);
    expect(h.session.summary.manualProvidersSkipped, isTrue);
    expect(h.session.summary.complete, isFalse);
    expect(h.session.summary.statusMessage, contains('manual grammar check'));
    h.edit('Another Feler.');
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.provider.requests, hasLength(2));
    expect(manual.requests, isEmpty);

    final explicit = h.session.checkNow();
    await tester.pump(Duration.zero);
    final summary = await explicit;
    expect(manual.requests, hasLength(1));
    expect(summary.manualProvidersSkipped, isFalse);
    expect(summary.complete, isTrue);
  });

  testWidgets(
    'disabling a running pass rejects its late results and stays off',
    (tester) async {
      final h = _LiveSession();
      final gate = Completer<void>();
      h.provider.gate = gate;
      h.session.enableBackgroundByDefault();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.session.checking, isTrue);

      h.session.enabled = false;
      h.session.enableBackgroundByDefault();
      gate.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(h.session.enabled, isFalse);
      expect(h.session.summary.scheduled, isFalse);
      expect(h.session.checking, isFalse);
      expect(h.session.summary.hasResults, isFalse);
      expect(h.session.summary.issues, isEmpty);
      expect(h.provider.requests, hasLength(1));
    },
  );

  testWidgets('undo schedules a fresh pass and rebinds restored findings', (
    tester,
  ) async {
    final provider = _LiveProvider('undo');
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Ein Feler.'),
      proofingService: OfficeProofingService(providers: [provider]),
    );
    addTearDown(controller.dispose);
    final session = controller.proofing;
    session.enableBackgroundByDefault();
    await tester.pump(session.debounce);
    final old = session.summary.issues.single;

    expect(controller.applyProofingSuggestion(old, 'Fehler'), isTrue);
    expect(session.summary.scheduled, isTrue);
    expect(session.summary.issues, isEmpty);
    expect(session.isCurrent(old), isFalse);
    await tester.pump(session.debounce);
    expect(session.summary.complete, isTrue);
    expect(session.summary.issues, isEmpty);

    controller.undo();
    expect(controller.document.paragraphs.single.text, 'Ein Feler.');
    expect(session.summary.scheduled, isTrue);
    expect(session.checking, isFalse);
    await tester.pump(session.debounce);
    final restored = session.summary.issues.single;
    expect(session.summary.scheduled, isFalse);
    expect(session.isCurrent(restored), isTrue);
    expect(restored.finding.revision, controller.contentRevision);
    expect(session.isCurrent(old), isFalse);
    expect(provider.requests.map((request) => request.text), [
      'Ein Feler.',
      'Ein Fehler.',
      'Ein Feler.',
    ]);
  });
}

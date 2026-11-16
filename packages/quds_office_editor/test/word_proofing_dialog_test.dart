import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _DialogProvider extends OfficeProofingProvider {
  _DialogProvider({
    this.status = OfficeProofingStatus.success,
    this.beforeResult,
  });

  final OfficeProofingStatus status;
  final Future<void>? beforeResult;
  final List<OfficeProofingRequest> requests = <OfficeProofingRequest>[];

  @override
  String get id => 'dialog-test';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    if (beforeResult != null) await beforeResult;
    final int start = request.text.indexOf('Feler');
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.success
          ? null
          : 'Test checker is ${status.name}.',
      findings: <OfficeProofingFinding>[
        if (status == OfficeProofingStatus.success && start >= 0)
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: start,
            end: start + 'Feler'.length,
            ruleId: 'test-spelling',
            message: 'Check this spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: const <String>['Fehler'],
          ),
      ],
    );
  }
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  OfficeProofingProvider? provider,
  WmlDocument? document,
  OfficeSurfaceConfig? config,
  Size size = const Size(1000, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final WordEditorController controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Ein Feler.'),
    config: config,
  );
  controller.proofing.configure(
    OfficeProofingService(
      providers: <OfficeProofingProvider>[provider ?? _DialogProvider()],
    ),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () =>
                showWordProofingDialog(context, controller: controller),
            child: const Text('Open proofing'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open proofing'));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  for (final scenario in <({String source, String label})>[
    (source: 'Hallo,Welt.', label: 'Insert space'),
    (source: 'Hallo  Welt.', label: 'Use space'),
  ]) {
    testWidgets(
      'spacing correction ${scenario.label} is visible and undoable',
      (WidgetTester tester) async {
        final controller = await _open(
          tester,
          document: WmlDocument.empty(text: scenario.source),
          provider: GermanWritingRulesProvider(),
        );
        final correction = find.widgetWithText(OutlinedButton, scenario.label);
        expect(correction, findsOneWidget);
        await _tap(tester, correction);
        await tester.pumpAndSettle();
        expect(
          controller.document.paragraphs.first.text,
          scenario.source.contains(',') ? 'Hallo, Welt.' : 'Hallo Welt.',
        );
        expect(controller.proofing.summary.issues, isEmpty);
        controller.undo();
        expect(controller.document.paragraphs.first.text, scenario.source);
      },
    );
  }

  testWidgets(
    'ignored words can be restored in their run language without clearing other preferences',
    (WidgetTester tester) async {
      final document = WmlDocument.empty(text: 'Feler');
      document.proofingLanguage = 'de-DE';
      document.paragraphs.first.inlines
              .whereType<WmlRun>()
              .first
              .properties
              .proofingLanguage =
          'de-CH';
      final controller = await _open(tester, document: document);
      final session = controller.proofing;
      session.vocabulary
        ..addWord('Quds', language: 'de-DE')
        ..ignoreWord('Feler', language: 'de-DE');
      session.refresh();
      unawaited(session.checkNow());
      await tester.pumpAndSettle();
      final snapshots = <Map<String, Object?>>[];
      session.onVocabularyChanged = snapshots.add;

      await _tap(tester, find.text('Ignore word'));
      await tester.pumpAndSettle();
      expect(session.summary.issues, isEmpty);
      await _tap(tester, find.text('Ignored checks'));
      await tester.pumpAndSettle();
      final restore = find.byTooltip('Check Feler again (de-CH)');
      expect(restore, findsOneWidget);
      await _tap(tester, restore);
      await tester.pumpAndSettle();

      expect(session.summary.issues.single.language, 'de-CH');
      expect(session.vocabulary.ignoredWordsFor('de-CH'), isEmpty);
      expect(session.vocabulary.ignoredWordsFor('de-DE'), <String>{'Feler'});
      expect(session.vocabulary.wordsFor('de-DE'), <String>{'Quds'});
      expect(snapshots, hasLength(2));
      expect(
        (snapshots.last['ignoredWords']! as Map<String, Object?>)['de-CH'],
        isEmpty,
      );
      expect(document.proofingLanguage, 'de-DE');
      expect(document.paragraphs.first.text, 'Feler');
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('an ignored writing rule can be restored from review', (
    WidgetTester tester,
  ) async {
    final controller = await _open(
      tester,
      document: WmlDocument.empty(text: 'ich bist.'),
      provider: GermanWritingRulesProvider(),
    );
    await _tap(tester, find.text('Ignore rule'));
    await tester.pumpAndSettle();
    expect(controller.proofing.summary.issues, isEmpty);
    await _tap(tester, find.text('Ignored checks'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Restore Pronoun and verb agreement'));
    await tester.pumpAndSettle();
    expect(
      controller.proofing.summary.issues.single.finding.ruleId,
      'de.grammar.pronoun-verb',
    );
    expect(controller.proofing.ignoredRuleIds, isEmpty);
    expect(controller.document.paragraphs.first.text, 'ich bist.');
    expect(controller.canUndo, isFalse);
  });

  testWidgets(
    'ignored occurrences can be reviewed again in a read-only document',
    (WidgetTester tester) async {
      final controller = await _open(
        tester,
        config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
      );
      await _tap(tester, find.text('Ignore once'));
      await tester.pumpAndSettle();
      expect(controller.proofing.summary.issues, isEmpty);
      await _tap(tester, find.text('Ignored checks'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Review ignored occurrences again'));
      await tester.pumpAndSettle();
      expect(controller.proofing.summary.issues, hasLength(1));
      expect(controller.proofing.hasIgnoredOccurrences, isFalse);
      expect(controller.document.paragraphs.first.text, 'Ein Feler.');
      expect(controller.canUndo, isFalse);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Fehler'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'swapping the dialog controller checks its document and clears old notices',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final _DialogProvider firstProvider = _DialogProvider();
      final _DialogProvider secondProvider = _DialogProvider();
      final WordEditorController first = WordEditorController(
        document: WmlDocument.empty(text: 'Ein Feler.'),
        proofingService: OfficeProofingService(providers: [firstProvider]),
      );
      final WordEditorController second = WordEditorController(
        document: WmlDocument.empty(text: 'Ein sauberer Text.'),
        proofingService: OfficeProofingService(providers: [secondProvider]),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget dialog(WordEditorController controller) => MaterialApp(
        home: Scaffold(body: WordProofingDialog(controller: controller)),
      );

      await tester.pumpWidget(dialog(first));
      await tester.pumpAndSettle();
      expect(firstProvider.requests, hasLength(1));
      expect(find.text('Check this spelling.'), findsOneWidget);
      await _tap(tester, find.text('Add to dictionary'));
      await tester.pumpAndSettle();
      expect(
        find.text('Word added to your personal dictionary.'),
        findsOneWidget,
      );
      final State<StatefulWidget> previousState = tester.state(
        find.byType(WordProofingDialog),
      );

      await tester.pumpWidget(dialog(second));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(WordProofingDialog)),
        same(previousState),
      );
      expect(secondProvider.requests, hasLength(1));
      expect(secondProvider.requests.single.text, 'Ein sauberer Text.');
      expect(second.proofing.summary.complete, isTrue);
      expect(find.text('No issues found in the checked text.'), findsOneWidget);
      expect(
        find.text('Word added to your personal dictionary.'),
        findsNothing,
      );

      await tester.pumpWidget(dialog(second));
      await tester.pumpAndSettle();
      expect(secondProvider.requests, hasLength(1));
      first.insertText('Changed ');
      await tester.pumpAndSettle();
      expect(find.text('No issues found in the checked text.'), findsOneWidget);
      expect(secondProvider.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a previous controller completing its check cannot replace the new results',
    (WidgetTester tester) async {
      final Completer<void> pending = Completer<void>();
      final _DialogProvider firstProvider = _DialogProvider(
        beforeResult: pending.future,
      );
      final _DialogProvider secondProvider = _DialogProvider();
      final WordEditorController first = WordEditorController(
        document: WmlDocument.empty(text: 'Ein Feler.'),
        proofingService: OfficeProofingService(providers: [firstProvider]),
      );
      final WordEditorController second = WordEditorController(
        document: WmlDocument.empty(text: 'Ein sauberer Text.'),
        proofingService: OfficeProofingService(providers: [secondProvider]),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget dialog(WordEditorController controller) => MaterialApp(
        home: Scaffold(body: WordProofingDialog(controller: controller)),
      );

      await tester.pumpWidget(dialog(first));
      await tester.pump(const Duration(milliseconds: 1));
      expect(firstProvider.requests, hasLength(1));
      expect(first.proofing.checking, isTrue);
      await tester.pumpWidget(dialog(second));
      await tester.pumpAndSettle();
      expect(secondProvider.requests, hasLength(1));
      expect(find.text('No issues found in the checked text.'), findsOneWidget);

      pending.complete();
      await tester.pumpAndSettle();
      expect(first.proofing.summary.issues, hasLength(1));
      expect(second.proofing.summary.issues, isEmpty);
      expect(find.text('Check this spelling.'), findsNothing);
      expect(find.text('No issues found in the checked text.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ignore once dismisses a finding without adding or ignoring its word',
    (WidgetTester tester) async {
      final WordEditorController controller = await _open(tester);
      await _tap(tester, find.text('Ignore once'));
      await tester.pumpAndSettle();
      expect(controller.proofing.summary.issues, isEmpty);
      expect(controller.proofing.vocabulary.wordsFor('de-DE'), isEmpty);
      expect(controller.proofing.vocabulary.ignoredWordsFor('de-DE'), isEmpty);
    },
  );

  testWidgets(
    'opening proofing checks the document and offers undoable corrections',
    (WidgetTester tester) async {
      final _DialogProvider provider = _DialogProvider();
      final WordEditorController controller = await _open(
        tester,
        provider: provider,
      );
      expect(provider.requests, isNotEmpty);
      expect(find.text('Check this spelling.'), findsOneWidget);
      expect(find.text('Feler'), findsOneWidget);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Fehler'));
      await tester.pumpAndSettle();
      expect(
        controller.document.sections.first.blocks
            .whereType<WmlParagraph>()
            .first
            .text,
        'Ein Fehler.',
      );
      expect(
        find.text('Correction applied. You can undo this change.'),
        findsOneWidget,
      );
      expect(find.text('No issues found in the checked text.'), findsOneWidget);
      controller.undo();
      expect(
        controller.document.sections.first.blocks
            .whereType<WmlParagraph>()
            .first
            .text,
        'Ein Feler.',
      );
    },
  );

  for (final OfficeProofingStatus status in <OfficeProofingStatus>[
    OfficeProofingStatus.unavailable,
    OfficeProofingStatus.unsupported,
    OfficeProofingStatus.failed,
  ]) {
    testWidgets(
      '${status.name} provider never produces a clean-document message',
      (WidgetTester tester) async {
        await _open(tester, provider: _DialogProvider(status: status));
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('proofing-status')),
              )
              .data,
          contains('Test checker is ${status.name}.'),
        );
        expect(find.textContaining('No issues found'), findsNothing);
        expect(
          find.text('Results are incomplete. Review the checker status above.'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'read-only documents retain review but disable correction and formatting',
    (WidgetTester tester) async {
      final WordEditorController controller = await _open(
        tester,
        config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
      );
      final OutlinedButton correction = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Fehler'),
      );
      expect(correction.onPressed, isNull);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey<String>('proofing-language')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey<String>('proofing-hyphenation')),
            )
            .onChanged,
        isNull,
      );
      expect(controller.proofing.summary.issues, hasLength(1));
    },
  );

  testWidgets(
    'adding a personal word dismisses its finding without changing document text',
    (WidgetTester tester) async {
      final WordEditorController controller = await _open(tester);
      final snapshots = <Map<String, Object?>>[];
      controller.proofing.onVocabularyChanged = snapshots.add;
      await _tap(tester, find.text('Add to dictionary'));
      await tester.pumpAndSettle();
      expect(
        controller.proofing.vocabulary.wordsFor('de-DE'),
        contains('Feler'),
      );
      expect(controller.proofing.summary.issues, isEmpty);
      expect(
        controller.document.sections.first.blocks
            .whereType<WmlParagraph>()
            .first
            .text,
        'Ein Feler.',
      );
      expect(controller.canUndo, isFalse);
      final Finder personal = find.byKey(
        const ValueKey<String>('proofing-personal-words'),
      );
      await tester.ensureVisible(personal);
      await _tap(tester, personal);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Keeping them between sessions depends'),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove Feler from dictionary'), findsOneWidget);
      await _tap(tester, find.byTooltip('Remove Feler from dictionary'));
      await tester.pumpAndSettle();
      expect(controller.proofing.vocabulary.wordsFor('de-DE'), isEmpty);
      expect(controller.proofing.summary.issues, hasLength(1));
      expect(snapshots, hasLength(2));
      expect(
        (snapshots.first['words']! as Map<String, Object?>)['de-DE'],
        <String>['Feler'],
      );
      expect(
        (snapshots.last['words']! as Map<String, Object?>)['de-DE'],
        isEmpty,
      );
    },
  );

  testWidgets(
    'ignore word applies to the session and leaves personal words unchanged',
    (WidgetTester tester) async {
      final WordEditorController controller = await _open(tester);
      await _tap(tester, find.text('Ignore word'));
      await tester.pumpAndSettle();
      expect(
        controller.proofing.vocabulary.ignoredWordsFor('de-DE'),
        contains('Feler'),
      );
      expect(controller.proofing.vocabulary.wordsFor('de-DE'), isEmpty);
      expect(controller.proofing.summary.issues, isEmpty);
    },
  );

  testWidgets(
    'language and hyphenation controls save source settings with undo',
    (WidgetTester tester) async {
      final WordEditorController controller = await _open(tester);
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('proofing-language')),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Deutsch (Schweiz)').last);
      await tester.pumpAndSettle();
      expect(controller.document.proofingLanguage, 'de-CH');
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('proofing-hyphenation')),
      );
      await tester.pumpAndSettle();
      expect(controller.document.autoHyphenation, isTrue);
      controller.undo();
      expect(controller.document.autoHyphenation, isFalse);
      expect(controller.document.proofingLanguage, 'de-CH');
      controller.undo();
      expect(controller.document.proofingLanguage, isNull);
    },
  );

  testWidgets(
    'unsupported existing language and a narrow viewport remain reviewable',
    (WidgetTester tester) async {
      final WmlDocument document = WmlDocument.empty(text: 'Un texte.');
      document.proofingLanguage = 'fr-FR';
      await _open(
        tester,
        document: document,
        config: const OfficeSurfaceConfig(textDirection: TextDirection.rtl),
        size: const Size(360, 600),
      );
      expect(
        Directionality.of(
          tester.element(
            find.byKey(const ValueKey<String>('proofing-language')),
          ),
        ),
        TextDirection.rtl,
      );
      expect(find.text('fr-FR'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final Finder check = find.byKey(
        const ValueKey<String>('proofing-check-document'),
      );
      expect(check, findsOneWidget);
      await _tap(tester, check);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'show in document selects the current finding and closes review',
    (WidgetTester tester) async {
      final WordEditorController controller = await _open(tester);
      await _tap(tester, find.text('Show in document'));
      await tester.pumpAndSettle();
      expect(find.byType(WordProofingDialog), findsNothing);
      expect(controller.caret.selectionAnchor, 4);
      expect(controller.caret.logicalIndex, 9);
    },
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'support/thesaurus_fixture.dart';

Future<WordEditorController> _open(
  WidgetTester tester, {
  String text = 'bank',
  String language = 'en-US',
  OfficeThesaurusService? service,
  Size size = const Size(1000, 850),
  double scale = 1,
  bool wait = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final document = WmlDocument.empty(text: text)..proofingLanguage = language;
  final controller = WordEditorController(document: document);
  controller.caret
    ..selectionAnchor = 0
    ..logicalIndex = text.length;
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWordThesaurusDialog(
              context,
              controller: controller,
              service: service ?? testThesaurusService(),
            ),
            child: const Text('Open thesaurus'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open thesaurus'));
  if (wait) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  return controller;
}

Future<void> _choose(WidgetTester tester, String label) async {
  final chips = find.widgetWithText(ChoiceChip, label);
  if (chips.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      chips,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('thesaurus-content')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  final chip = chips.first;
  await Scrollable.ensureVisible(tester.element(chip), alignment: 0.35);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

// A live Word canvas deliberately keeps its caret ticker running.
Future<void> _pumpSurface(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets(
    'lookup is nonmutating, preserves meanings and requires explicit Replace',
    (tester) async {
      final controller = await _open(tester);
      expect(controller.document.paragraphs.first.text, 'bank');
      expect(controller.commands.canUndo, isFalse);
      expect(find.text('A financial business.'), findsOneWidget);
      expect(find.text('depository · formal'), findsOneWidget);
      expect(find.text('Related concepts (not replacements)'), findsWidgets);
      final replace = find.byKey(const ValueKey('thesaurus-replace'));
      expect(tester.widget<FilledButton>(replace).onPressed, isNull);
      await _choose(tester, 'financial institution');
      expect(controller.document.paragraphs.first.text, 'bank');
      expect(tester.widget<FilledButton>(replace).onPressed, isNotNull);
      await tester.tap(replace);
      await tester.pumpAndSettle();
      expect(
        controller.document.paragraphs.first.text,
        'financial institution',
      );
      expect(find.textContaining('You can undo this change.'), findsOneWidget);
      expect(tester.widget<FilledButton>(replace).onPressed, isNull);
      controller.undo();
      expect(controller.document.paragraphs.first.text, 'bank');
      expect(controller.commands.canUndo, isFalse);
      controller.redo();
      expect(
        controller.document.paragraphs.first.text,
        'financial institution',
      );
    },
  );

  testWidgets('closing lookup adds no undo entry', (tester) async {
    final controller = await _open(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(WordThesaurusDialog), findsNothing);
    expect(controller.document.paragraphs.first.text, 'bank');
    expect(controller.commands.canUndo, isFalse);
  });

  testWidgets(
    'a changed selection disables Replace and explains how to refresh',
    (tester) async {
      final controller = await _open(tester);
      await _choose(tester, 'depository · formal');
      controller.caret
        ..logicalIndex = 2
        ..collapseSelection();
      controller.refreshView();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('thesaurus-replace')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('selection or thesaurus has changed'),
        findsOneWidget,
      );
      expect(controller.document.paragraphs.first.text, 'bank');
    },
  );

  testWidgets('an invalidated pack refuses a previously selected candidate', (
    tester,
  ) async {
    final service = testThesaurusService();
    final controller = await _open(tester, service: service);
    await _choose(tester, 'depository · formal');
    service.clear();
    // No controller notification is required for the final validation gate.
    await tester.tap(find.byKey(const ValueKey('thesaurus-replace')));
    await tester.pumpAndSettle();
    expect(controller.document.paragraphs.first.text, 'bank');
    expect(
      find.textContaining('selection or thesaurus has changed'),
      findsWidgets,
    );
  });

  testWidgets(
    'language override uses another pack without changing document language',
    (tester) async {
      final service = testThesaurusService(
        assets: {
          ...thesaurusFixtureAssets(),
          ...thesaurusFixtureAssets(locale: 'de'),
        },
      );
      final controller = await _open(tester, text: 'Bank', service: service);
      await tester.tap(find.byKey(const ValueKey('thesaurus-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deutsch (Deutschland)').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Geldinstitut'), findsOneWidget);
      expect(controller.document.proofingLanguage, 'en-US');
      await _choose(tester, 'Geldinstitut');
      await tester.tap(find.byKey(const ValueKey('thesaurus-replace')));
      await tester.pumpAndSettle();
      expect(controller.document.paragraphs.first.text, 'Geldinstitut');
      expect(controller.document.proofingLanguage, 'en-US');
    },
  );

  for (final scenario in [
    (
      name: 'noEntry',
      text: 'zzzzunlisted',
      language: 'en-US',
      assets: (null as Map<String, String>?),
    ),
    (
      name: 'unsupportedLanguage',
      text: 'bank',
      language: 'fr-FR',
      assets: (null as Map<String, String>?),
    ),
    (
      name: 'missingPack',
      text: 'bank',
      language: 'en-US',
      assets: <String, String>{},
    ),
    (
      name: 'failedPack',
      text: 'bank',
      language: 'en-US',
      assets: <String, String>{'en/manifest.json': 'damaged'},
    ),
  ]) {
    testWidgets('shows distinct ${scenario.name} outcome', (tester) async {
      final controller = await _open(
        tester,
        text: scenario.text,
        language: scenario.language,
        service: testThesaurusService(assets: scenario.assets),
      );
      expect(
        find.byKey(ValueKey('thesaurus-${scenario.name}')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('thesaurus-replace')),
            )
            .onPressed,
        isNull,
      );
      expect(controller.commands.canUndo, isFalse);
    });
  }

  testWidgets('empty caret target explains how to select text', (tester) async {
    await _open(tester, text: '');
    expect(find.byKey(const ValueKey('thesaurus-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('thesaurus-progress')), findsNothing);
  });

  testWidgets(
    'explicit retry reloads a repaired pack after a failed manifest',
    (tester) async {
      final assets = <String, String>{'en/manifest.json': 'damaged'};
      await _open(tester, service: testThesaurusService(assets: assets));
      expect(
        find.byKey(const ValueKey('thesaurus-failedPack')),
        findsOneWidget,
      );
      assets
        ..clear()
        ..addAll(thesaurusFixtureAssets());
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thesaurus-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('thesaurus-failedPack')), findsNothing);
    },
  );

  testWidgets('late lookup completion after closing is ignored safely', (
    tester,
  ) async {
    final gate = Completer<void>();
    final controller = await _open(
      tester,
      service: testThesaurusService(gate: gate.future),
      wait: false,
    );
    expect(find.byKey(const ValueKey('thesaurus-progress')), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.document.paragraphs.first.text, 'bank');
  });

  testWidgets('source view displays verified notices', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('thesaurus-sources')));
    await tester.pumpAndSettle();
    expect(find.text('Thesaurus sources and licenses'), findsOneWidget);
    expect(find.text('Synthetic editor test fixtures.'), findsOneWidget);
    await tester.tap(find.text('LICENSE.txt'));
    await tester.pumpAndSettle();
    expect(
      find.text('Synthetic fixture data, CC0. Not a lexical corpus.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close sources'));
    await tester.pumpAndSettle();
    expect(find.byType(WordThesaurusDialog), findsOneWidget);
  });

  testWidgets(
    'source view reports a damaged notice without an uncaught error',
    (tester) async {
      final assets = thesaurusFixtureAssets();
      await _open(tester, service: testThesaurusService(assets: assets));
      assets['en/notices/LICENSE.txt'] = 'changed after manifest';
      await tester.tap(find.byKey(const ValueKey('thesaurus-sources')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('notices could not be verified'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow screen and large text keep alternatives and actions usable',
    (tester) async {
      final controller = await _open(
        tester,
        size: const Size(360, 720),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      await _choose(tester, 'financial institution');
      await tester.ensureVisible(
        find.byKey(const ValueKey('thesaurus-replace')),
      );
      await tester.tap(find.byKey(const ValueKey('thesaurus-replace')));
      await tester.pumpAndSettle();
      expect(
        controller.document.paragraphs.first.text,
        'financial institution',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Shift F7 opens thesaurus while F7 keeps the writing review action',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'bank')..proofingLanguage = 'en-US',
      );
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QudsWordEditor(
              controller: controller,
              focusNode: focus,
              enableLiveProofing: false,
              thesaurusService: testThesaurusService(),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _pumpSurface(tester);
      expect(find.byType(WordThesaurusDialog), findsOneWidget);
      expect(controller.reviewPaneVisible, isFalse);
      await tester.tap(find.text('Close'));
      await _pumpSurface(tester);
      var requested = false;
      controller.onSpellCheckRequested = () => requested = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      expect(requested, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
    },
  );

  for (final scenario in [
    (name: 'Shift F7', shortcut: true, scaffold: true),
    (name: 'an earlier ready capture', shortcut: false, scaffold: true),
    (name: 'a host without Scaffold', shortcut: false, scaffold: false),
  ]) {
    testWidgets(
      '${scenario.name} refuses thesaurus without interrupting active IME',
      (tester) async {
        final controller = WordEditorController(
          document: WmlDocument.empty(text: 'bank')..proofingLanguage = 'en-US',
        );
        final focus = FocusNode();
        final editorKey = GlobalKey();
        final reads = <String>[];
        final service = testThesaurusService(onRead: reads.add);
        controller.caret
          ..selectionAnchor = 2
          ..logicalIndex = 2;
        final editor = QudsWordEditor(
          key: editorKey,
          controller: controller,
          focusNode: focus,
          enableLiveProofing: false,
          thesaurusService: service,
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: scenario.scaffold
                  ? Scaffold(body: editor)
                  : Material(child: editor),
            ),
          );
          focus.requestFocus();
          await _pumpSurface(tester);
          expect(focus.hasPrimaryFocus, isTrue);
          expect(controller.input.isAttached, isTrue);
          // The helper must recheck live composition even when a menu captured
          // a valid selection before the IME started.
          final capture = controller.captureThesaurusTarget();
          expect(capture.status, WordThesaurusTargetStatus.ready);
          const composing = TextEditingValue(
            text: 'bank',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 0, end: 4),
          );
          controller.input.setValue(composing);
          final selection = (
            controller.caret.paragraphIndex,
            controller.caret.logicalIndex,
            controller.caret.selectionAnchorParagraph,
            controller.caret.selectionAnchor,
          );
          final revision = controller.contentRevision;
          var focusChanges = 0;
          void recordFocusChange() => focusChanges++;
          focus.addListener(recordFocusChange);
          if (scenario.shortcut) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.f7);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          } else {
            await showWordThesaurusDialog(
              editorKey.currentContext!,
              controller: controller,
              service: service,
              capture: capture,
            );
          }
          await _pumpSurface(tester);
          expect(find.byType(WordThesaurusDialog), findsNothing);
          expect(
            find.text(
              'Finish the current text composition before using Thesaurus.',
            ),
            scenario.scaffold ? findsOneWidget : findsNothing,
          );
          if (scenario.scaffold) {
            ScaffoldMessenger.of(
              editorKey.currentContext!,
            ).removeCurrentSnackBar();
            await _pumpSurface(tester);
          }
          expect(controller.input.value, composing);
          expect(controller.input.composing, composing.composing);
          expect(controller.input.isAttached, isTrue);
          expect(focus.hasPrimaryFocus, isTrue);
          expect(focusChanges, 0);
          expect((
            controller.caret.paragraphIndex,
            controller.caret.logicalIndex,
            controller.caret.selectionAnchorParagraph,
            controller.caret.selectionAnchor,
          ), selection);
          expect(controller.document.paragraphs.single.text, 'bank');
          expect(controller.contentRevision, revision);
          expect(controller.canUndo, isFalse);
          expect(controller.reviewPaneVisible, isFalse);
          expect(reads, isEmpty);
          expect(tester.takeException(), isNull);
          focus.removeListener(recordFocusChange);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          focus.dispose();
        }
      },
    );
  }

  testWidgets('review status action opens the selected text', (tester) async {
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'bank')..proofingLanguage = 'en-US',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QudsWordEditor(
            controller: controller,
            enableLiveProofing: false,
            thesaurusService: testThesaurusService(),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('word-review-thesaurus')));
    await _pumpSurface(tester);
    expect(find.byKey(const ValueKey('thesaurus-query')), findsOneWidget);
    expect(find.text('bank'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'context menu retains the captured selection through focus transfer',
    (tester) async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'bank here')
          ..proofingLanguage = 'en-US',
      );
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QudsWordEditor(
              controller: controller,
              enableLiveProofing: false,
              thesaurusService: testThesaurusService(),
            ),
          ),
        ),
      );
      final canvas = tester.widget<WordCanvas>(find.byType(WordCanvas));
      canvas.onContextMenu!(
        OfficeContextHit(
          kind: OfficeContextKind.document,
          globalPosition: const Offset(160, 120),
          paragraph: controller.document.paragraphs.first,
          proofingOffset: 2,
        ),
      );
      await _pumpSurface(tester);
      final action = find.text('Thesaurus…');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await _pumpSurface(tester);
      expect(find.byType(WordThesaurusDialog), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('thesaurus-query')),
            )
            .data,
        'bank',
      );
      await _choose(tester, 'depository · formal');
      await tester.tap(find.byKey(const ValueKey('thesaurus-replace')));
      await _pumpSurface(tester);
      expect(controller.document.paragraphs.first.text, 'depository here');
      controller.undo();
      expect(controller.document.paragraphs.first.text, 'bank here');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}

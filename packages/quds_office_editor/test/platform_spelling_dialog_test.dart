import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Future<WordEditorController> _openNativeReview(
  WidgetTester tester, {
  required String source,
  required String unknown,
  required List<String> suggestions,
  List<String>? nativeRequests,
  OfficeProofingVocabulary? vocabulary,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.spellCheck, (call) async {
    expect(call.method, 'SpellCheck.initiateSpellCheck');
    final arguments = call.arguments as List<Object?>;
    expect(arguments.first, 'en-US');
    final text = arguments[1]! as String;
    nativeRequests?.add(text);
    final start = text.indexOf(unknown);
    return <Map<String, Object>>[
      if (start >= 0)
        <String, Object>{
          'startIndex': start,
          'endIndex': start + unknown.length,
          'suggestions': suggestions,
        },
    ];
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.spellCheck, null),
  );
  final document = WmlDocument.empty(text: source)..proofingLanguage = 'en-US';
  final controller = WordEditorController(
    document: document,
    proofingVocabulary: vocabulary,
    proofingService: OfficeProofingService(
      providers: <OfficeProofingProvider>[
        OfficePlatformSpellingProvider(
          supportedLanguages: <String>['en-US'],
          isAvailable: () => true,
        ),
      ],
    ),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: WordProofingDialog(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  expect(controller.proofing.summary.complete, isTrue);
  expect(tester.takeException(), isNull);
  return controller;
}

void main() {
  testWidgets(
    'native review maps a soft-hyphen correction to its original text and undo',
    (tester) async {
      const source = '🙂 a\u00adlot.';
      final nativeRequests = <String>[];
      final controller = await _openNativeReview(
        tester,
        source: source,
        unknown: 'alot',
        suggestions: <String>['alot', 'a\u00adlot', 'a lot'],
        nativeRequests: nativeRequests,
      );
      expect(nativeRequests, <String>['🙂 alot.']);
      expect(controller.document.paragraphs.first.text, source);
      expect(controller.canUndo, isFalse);
      final finding = controller.proofing.summary.issues.single.finding;
      expect(
        (finding.start, finding.end, finding.originalText),
        (3, 8, 'a\u00adlot'),
      );
      expect(finding.replacements, <String>['a lot']);
      expect(find.widgetWithText(OutlinedButton, 'alot'), findsNothing);
      final correction = find.widgetWithText(OutlinedButton, 'a lot');
      expect(correction, findsOneWidget);
      await tester.ensureVisible(correction);
      await tester.pump();
      await tester.tap(correction);
      await tester.pumpAndSettle();
      expect(controller.document.paragraphs.first.text, '🙂 a lot.');
      expect(controller.proofing.summary.issues, isEmpty);
      expect(controller.proofing.summary.complete, isTrue);
      expect(nativeRequests.last, '🙂 a lot.');
      controller.undo();
      expect(controller.document.paragraphs.first.text, source);
      controller.redo();
      expect(controller.document.paragraphs.first.text, '🙂 a lot.');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native soft-hyphen personal spelling is normalized and owner scoped',
    (tester) async {
      const source = '🙂 quds\u00adcloud.';
      final vocabulary = OfficeProofingVocabulary(ownerId: 'owner-a');
      final nativeRequests = <String>[];
      final controller = await _openNativeReview(
        tester,
        source: source,
        unknown: 'qudscloud',
        suggestions: <String>[],
        nativeRequests: nativeRequests,
        vocabulary: vocabulary,
      );
      expect(nativeRequests, <String>['🙂 qudscloud.']);
      expect(
        controller.proofing.summary.issues.single.finding.originalText,
        'quds\u00adcloud',
      );
      final addWord = find.text('Add to dictionary');
      await tester.ensureVisible(addWord);
      await tester.pump();
      await tester.tap(addWord);
      await tester.pumpAndSettle();
      expect(controller.proofing.summary.issues, isEmpty);
      expect(vocabulary.wordsFor('en-US'), <String>{'qudscloud'});
      expect(vocabulary.wordsFor('de-DE'), isEmpty);
      expect(vocabulary.contains('quds\u00adcloud', language: 'en-US'), isTrue);
      expect(controller.document.paragraphs.first.text, source);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());

      final sameOwner = await _openNativeReview(
        tester,
        source: '🙂 qudscloud.',
        unknown: 'qudscloud',
        suggestions: <String>[],
        vocabulary: vocabulary,
      );
      expect(sameOwner.proofing.summary.issues, isEmpty);
      expect(sameOwner.document.paragraphs.first.text, '🙂 qudscloud.');
      expect(sameOwner.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());

      final otherVocabulary = OfficeProofingVocabulary(ownerId: 'owner-b');
      final otherOwner = await _openNativeReview(
        tester,
        source: source,
        unknown: 'qudscloud',
        suggestions: <String>[],
        vocabulary: otherVocabulary,
      );
      expect(
        otherOwner.proofing.summary.issues.single.finding.originalText,
        'quds\u00adcloud',
      );
      expect(otherVocabulary.wordsFor('en-US'), isEmpty);
      expect(vocabulary.wordsFor('en-US'), <String>{'qudscloud'});
      expect(otherOwner.document.paragraphs.first.text, source);
      expect(otherOwner.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native review exposes a usable multiword correction after invalid suggestions',
    (tester) async {
      const source = '🙂 alot.';
      final controller = await _openNativeReview(
        tester,
        source: source,
        unknown: 'alot',
        suggestions: <String>[
          '',
          ' ',
          'alot',
          'alot',
          '\t',
          'bad\ntext',
          'bad\u0000text',
          '',
          'a lot',
          'a lot',
        ],
      );
      final finding = controller.proofing.summary.issues.single.finding;
      expect(
        (finding.start, finding.end, finding.originalText),
        (3, 7, 'alot'),
      );
      expect(finding.replacements, <String>['a lot']);
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Use space'), findsNothing);
      final correction = find.widgetWithText(OutlinedButton, 'a lot');
      expect(correction, findsOneWidget);
      await tester.ensureVisible(correction);
      await tester.pump();
      await tester.tap(correction);
      await tester.pumpAndSettle();
      expect(controller.document.paragraphs.first.text, '🙂 a lot.');
      expect(controller.proofing.summary.issues, isEmpty);
      expect(controller.proofing.summary.complete, isTrue);
      controller.undo();
      expect(controller.document.paragraphs.first.text, source);
      controller.redo();
      expect(controller.document.paragraphs.first.text, '🙂 a lot.');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a native unknown word without usable replacements remains reviewable',
    (tester) async {
      const source = '🙂 qudscloud.';
      final controller = await _openNativeReview(
        tester,
        source: source,
        unknown: 'qudscloud',
        suggestions: <String>['', 'qudscloud', '\n', '\t'],
      );
      expect(controller.proofing.summary.issues, hasLength(1));
      expect(
        controller.proofing.summary.issues.single.finding.replacements,
        isEmpty,
      );
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsNothing);
      expect(find.text('No issues found in the checked text.'), findsNothing);
      expect(controller.document.paragraphs.first.text, source);
      expect(controller.canUndo, isFalse);
      final addWord = find.text('Add to dictionary');
      await tester.ensureVisible(addWord);
      await tester.pump();
      await tester.tap(addWord);
      await tester.pumpAndSettle();
      expect(controller.proofing.summary.issues, isEmpty);
      expect(controller.proofing.vocabulary.wordsFor('en-US'), <String>{
        'qudscloud',
      });
      expect(controller.document.paragraphs.first.text, source);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

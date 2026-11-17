import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller(WmlDocument document) {
  final WordEditorController controller = WordEditorController(
    document: document,
    proofingService: OfficeProofingService(
      providers: <OfficeProofingProvider>[GermanWritingRulesProvider()],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario
      in <({String source, String corrected, String rule, String replacement})>[
        (
          source: 'Ich spreche mit mich.',
          corrected: 'Ich spreche mit mir.',
          rule: 'preposition-pronoun',
          replacement: 'mir',
        ),
        (
          source: 'Das ist für ihm.',
          corrected: 'Das ist für ihn.',
          rule: 'preposition-pronoun',
          replacement: 'ihn',
        ),
        (
          source: 'Ich spreche mit den Mann.',
          corrected: 'Ich spreche mit dem Mann.',
          rule: 'preposition-case',
          replacement: 'dem',
        ),
        (
          source: 'Wir spielen mit den Kinder.',
          corrected: 'Wir spielen mit den Kindern.',
          rule: 'dative-plural',
          replacement: 'Kindern',
        ),
        (
          source: 'Ich lese ein gute Buch.',
          corrected: 'Ich lese ein gutes Buch.',
          rule: 'adjective-ending',
          replacement: 'gutes',
        ),
        (
          source: 'Ich arbeite mit einem gutem Buch.',
          corrected: 'Ich arbeite mit einem guten Buch.',
          rule: 'adjective-ending',
          replacement: 'guten',
        ),
        (
          source: 'Ich denke, das du kommst.',
          corrected: 'Ich denke, dass du kommst.',
          rule: 'das-dass',
          replacement: 'dass',
        ),
        (
          source: 'Ich glaube dass du kommst.',
          corrected: 'Ich glaube, dass du kommst.',
          rule: 'subordinate-comma',
          replacement: ',',
        ),
        (
          source: 'Das Haus ist größer wie das Büro.',
          corrected: 'Das Haus ist größer als das Büro.',
          rule: 'comparison',
          replacement: 'als',
        ),
        (
          source: 'Das Haus ist so groß als das Büro.',
          corrected: 'Das Haus ist so groß wie das Büro.',
          rule: 'comparison',
          replacement: 'wie',
        ),
      ]) {
    test(
      'real German ${scenario.rule} correction and undo: ${scenario.source}',
      () async {
        final WordEditorController controller = _controller(
          WmlDocument.empty(text: scenario.source),
        );
        final WordProofingSummary summary = await controller
            .checkDocumentProofing();
        final WordProofingIssue issue = summary.issues.singleWhere(
          (WordProofingIssue issue) =>
              issue.finding.ruleId == 'de.grammar.${scenario.rule}',
        );
        expect(summary.complete, isTrue);
        expect(issue.finding.replacements, contains(scenario.replacement));
        expect(
          controller.applyProofingSuggestion(issue, scenario.replacement),
          isTrue,
        );
        expect(controller.document.paragraphs.first.text, scenario.corrected);
        expect((await controller.checkDocumentProofing()).issues, isEmpty);
        controller.undo();
        expect(controller.document.paragraphs.first.text, scenario.source);
        controller.redo();
        expect(controller.document.paragraphs.first.text, scenario.corrected);
      },
    );
  }

  test(
    'grammar spans equivalent German run tags and soft hyphens safely',
    () async {
      final WmlParagraph paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(
            text: 'English 👩‍🔬. ',
            properties: WmlRunProps(noProof: true, proofingLanguage: 'en-US'),
          ),
          WmlRun(
            text: 'Ich arbeite mit einem gu\u00ad',
            properties: WmlRunProps(bold: true, proofingLanguage: 'de-1996'),
          ),
          WmlRun(
            text: 'tem Buch.',
            properties: WmlRunProps(italic: true, proofingLanguage: 'de-DE'),
          ),
        ],
      );
      final WmlDocument document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(blocks: <WmlBlock>[paragraph]),
        ],
      )..proofingLanguage = 'en-US';
      final WordEditorController controller = _controller(document);
      final String original = paragraph.text;
      final WordProofingSummary summary = await controller
          .checkDocumentProofing();
      final WordProofingIssue issue = summary.issues.single;
      expect(issue.language, 'de-DE');
      expect(issue.finding.ruleId, 'de.grammar.adjective-ending');
      expect(issue.finding.originalText, 'gu\u00adtem');
      expect(issue.finding.start, original.indexOf('gu\u00adtem'));
      expect(controller.applyProofingSuggestion(issue, 'guten'), isTrue);
      expect(
        paragraph.text,
        'English 👩‍🔬. Ich arbeite mit einem guten Buch.',
      );
      controller.undo();
      expect(paragraph.text, original);
      final List<WmlRun> runs = paragraph.inlines.whereType<WmlRun>().toList();
      expect(runs[0].properties.noProof, isTrue);
      expect(runs[1].properties.bold, isTrue);
      expect(runs[1].properties.proofingLanguage, 'de-1996');
      expect(runs[2].properties.italic, isTrue);
      expect(document.proofingLanguage, 'en-US');
    },
  );

  test('new grammar findings retain stale-source correction guards', () async {
    final WordEditorController controller = _controller(
      WmlDocument.empty(text: 'Ich spreche mit mich.'),
    );
    final WordProofingIssue issue =
        (await controller.checkDocumentProofing()).issues.single;
    controller.insertText('Heute: ');
    final String edited = controller.document.paragraphs.first.text;
    expect(controller.applyProofingSuggestion(issue, 'mir'), isFalse);
    expect(controller.document.paragraphs.first.text, edited);
    controller.undo();
    expect(controller.document.paragraphs.first.text, 'Ich spreche mit mich.');
  });

  for (final entry in <String, String>{
    'preposition-pronoun': 'Pronoun case after prepositions',
    'preposition-case': 'Article case after prepositions',
    'dative-plural': 'Dative plural endings',
    'adjective-ending': 'Adjective agreement',
    'das-dass': 'Das and dass usage',
    'subordinate-comma': 'Commas before subordinate clauses',
    'comparison': 'Als and wie in comparisons',
  }.entries) {
    testWidgets('new ${entry.key} rule has a reviewable restore label', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final WordEditorController controller = _controller(
        WmlDocument.empty(text: 'Ein guter Satz.'),
      );
      controller.proofing.ignoreRule('de.grammar.${entry.key}');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WordProofingDialog(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final Finder ignored = find.text('Ignored checks');
      await tester.ensureVisible(ignored);
      await tester.pumpAndSettle();
      await tester.tap(ignored);
      await tester.pumpAndSettle();
      final Finder restore = find.byTooltip('Restore ${entry.value}');
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(controller.proofing.ignoredRuleIds, isEmpty);
      expect(controller.document.paragraphs.first.text, 'Ein guter Satz.');
      expect(controller.canUndo, isFalse);
    });
  }
}

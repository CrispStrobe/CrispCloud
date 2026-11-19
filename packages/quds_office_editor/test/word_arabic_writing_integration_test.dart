import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default review checks Arabic runs with the Arabic rules', () async {
    final document = WmlDocument.empty();
    document.paragraphs.first.inlines
      ..clear()
      ..add(
        WmlRun(
          text: 'ذهب الولد الى المدرسه.',
          properties: WmlRunProps(proofingLanguage: 'ar-SA'),
        ),
      );
    final controller = WordEditorController(document: document);
    addTearDown(controller.dispose);
    final summary = await controller.checkDocumentProofing();
    expect(summary.complete, isTrue);
    final arabic = summary.issues
        .where((i) => i.finding.providerId == 'arabic-writing')
        .map((i) => i.finding.ruleId)
        .toList();
    expect(arabic, ['ar.hamza.initial', 'ar.ta-marbuta.final']);
    final hamza = summary.issues.firstWhere(
      (i) => i.finding.ruleId == 'ar.hamza.initial',
    );
    expect(controller.applyProofingSuggestion(hamza, 'إلى'), isTrue);
    expect(controller.document.paragraphs.first.text, 'ذهب الولد إلى المدرسه.');
  });

  test('Arabic rules stay silent for German text', () async {
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Das ist ein Test.'),
    );
    addTearDown(controller.dispose);
    final summary = await controller.checkDocumentProofing();
    expect(
      summary.issues.where((i) => i.finding.providerId == 'arabic-writing'),
      isEmpty,
    );
  });
}

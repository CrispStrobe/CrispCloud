import 'dart:convert';

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

  wordAuthoredArabicTests();
}

WmlDocument _wordAuthoredArabic() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:pPr><w:bidi/></w:pPr>
<w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space="preserve">ذهب الولد الى المدرسه. </w:t></w:r>
<w:r><w:rPr><w:lang w:val="de-DE" w:bidi="ar-SA"/></w:rPr><w:t xml:space="preserve">Das ist gut. </w:t></w:r>
<w:r><w:rPr><w:lang w:val="de-DE" w:bidi="ar-SA"/></w:rPr><w:t>وصل اليه</w:t></w:r>
</w:p><w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault></w:docDefaults>
</w:styles>''');
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

void wordAuthoredArabicTests() {
  test('Word complex-script language (w:bidi) routes Arabic runs', () async {
    final document = _wordAuthoredArabic();
    expect(document.complexScriptLanguage, 'ar-SA');
    final runs = document.paragraphs.single.inlines
        .whereType<WmlRun>()
        .toList();
    expect(runs.first.properties.complexScript, isTrue);
    expect(
      runs
          .map(
            (run) => wordRunProofingLanguage(
              run,
              document.paragraphs.single,
              documentLanguage: document.proofingLanguage,
              documentComplexScriptLanguage: document.complexScriptLanguage,
            ),
          )
          .toList(),
      ['ar-SA', 'de-DE', 'ar-SA'],
    );
    final controller = WordEditorController(document: document);
    addTearDown(controller.dispose);
    final summary = await controller.checkDocumentProofing();
    expect(summary.complete, isTrue);
    final arabic = summary.issues
        .where((i) => i.finding.providerId == 'arabic-writing')
        .map((i) => (i.finding.ruleId, i.finding.originalText, i.language))
        .toList();
    expect(arabic, [
      ('ar.hamza.initial', 'الى', 'ar-SA'),
      ('ar.ta-marbuta.final', 'المدرسه', 'ar-SA'),
      ('ar.hamza.initial', 'اليه', 'ar-SA'),
    ]);
    // Round trip keeps Word's language attributes and the rtl marker.
    final saved = utf8.decode(
      WordDeserializer()
          .readBytes(controller.saveBytes())
          .package!
          .getPart('/word/document.xml')!
          .readBytes(),
    );
    expect(saved, contains('w:bidi="ar-SA"'));
    expect(saved, contains('<w:rtl/>'));
    expect(saved, contains('w:val="de-DE"'));
  });
}

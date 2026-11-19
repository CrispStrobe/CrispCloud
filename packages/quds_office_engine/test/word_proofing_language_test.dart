import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final (String name, String text) in <(String, String)>[
    ('plain Latin', 'Plain English'),
    ('Arabic comma', 'English،'),
    ('Arabic-Indic digit', 'Invoice ١'),
    ('extended Arabic-Indic digit', 'Invoice ۱'),
    ('byte-order mark', '\uFEFFEnglish'),
    ('isolated Arabic combining mark', 'English\u0651'),
    ('Hebrew punctuation', 'English\u05BE'),
  ]) {
    test('$name keeps the Latin proofing-language chain', () {
      final WmlRun run = WmlRun(text: text);
      final WmlParagraph paragraph = WmlParagraph(inlines: <WmlInline>[run]);
      expect(wordTextHasComplexScriptLetter(text), isFalse);
      expect(
        wordRunProofingLanguage(
          run,
          paragraph,
          documentLanguage: 'en-US',
          documentComplexScriptLanguage: 'ar-SA',
        ),
        'en-US',
      );
      run.properties.proofingLanguage = 'de-DE';
      expect(
        wordRunProofingLanguage(
          run,
          paragraph,
          documentLanguage: 'en-US',
          documentComplexScriptLanguage: 'ar-SA',
        ),
        'de-DE',
      );
    });
  }

  for (final (String name, String text) in <(String, String)>[
    ('Arabic', 'مرحبا'),
    ('Hebrew', 'שלום'),
    ('Arabic presentation form', '\uFEE1'),
  ]) {
    test('$name letters select the complex-script language', () {
      expect(wordTextHasComplexScriptLetter(text), isTrue);
      expect(
        wordRunProofingLanguage(
          WmlRun(text: text),
          WmlParagraph(),
          documentLanguage: 'en-US',
          documentComplexScriptLanguage: 'ar-SA',
        ),
        'ar-SA',
      );
    });
  }

  test('explicit complex-script formatting still routes Latin text', () {
    final WmlRun run = WmlRun(
      text: 'English',
      properties: WmlRunProps(complexScript: true),
    );
    expect(
      wordRunProofingLanguage(
        run,
        WmlParagraph(),
        documentLanguage: 'en-US',
        documentComplexScriptLanguage: 'ar-SA',
      ),
      'ar-SA',
    );
  });

  test('no complex-script language preserves the usual inheritance', () {
    final WmlRun run = WmlRun(text: 'مرحبا');
    final WmlParagraph paragraph = WmlParagraph(
      properties: WmlParagraphProps(proofingLanguage: 'de-DE'),
    );
    expect(
      wordRunProofingLanguage(run, paragraph, documentLanguage: 'en-US'),
      'de-DE',
    );
    run.properties.proofingLanguage = 'en-GB';
    expect(
      wordRunProofingLanguage(run, paragraph, documentLanguage: 'en-US'),
      'en-GB',
    );
  });

  test('a run complex-script language takes priority over the document', () {
    final WmlRun run = WmlRun(
      text: 'שלום',
      properties: WmlRunProps(complexScriptLanguage: 'he-IL'),
    );
    expect(
      wordRunProofingLanguage(
        run,
        WmlParagraph(),
        documentLanguage: 'en-US',
        documentComplexScriptLanguage: 'ar-SA',
      ),
      'he-IL',
    );
  });
}

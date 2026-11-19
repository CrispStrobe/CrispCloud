import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final (name, text) in [
    ('Arabic letters', 'مرحبا'),
    ('Hebrew letters', 'שָׁלוֹם'),
    ('decomposed Arabic hamza', 'ا\u0654هلا'),
    ('Arabic supplement letter', '\u0750'),
    ('Arabic presentation letter', '\uFB8E'),
    ('Hebrew presentation letter', '\uFB2A'),
  ]) {
    test('$name use the complex-script language', () {
      final run = WmlRun(
        text: text,
        properties: WmlRunProps(
          proofingLanguage: 'de-DE',
          complexScriptLanguage: 'ar-SA',
        ),
      );
      expect(wordTextHasComplexScriptLetter(text), isTrue);
      expect(wordRunProofingLanguage(run, WmlParagraph()), 'ar-SA');
    });
  }

  for (final (name, text) in [
    ('Arabic comma', 'Preis،'),
    ('Arabic decimal digits', 'Total ١٢٣'),
    ('Persian decimal digits', 'Total ۱۲۳'),
    ('Arabic percent sign', 'Total ٪'),
    ('Hebrew punctuation', 'Preis\u05BE'),
    ('Arabic combining marks alone', '\u064B\u0654'),
    ('Hebrew combining marks alone', '\u05B0\u05B1'),
    ('BOM before Latin letters', '\uFEFFPreis'),
    ('plain Latin letters', 'Preis'),
  ]) {
    test('$name do not select the complex-script language', () {
      final run = WmlRun(
        text: text,
        properties: WmlRunProps(proofingLanguage: 'de-DE'),
      );
      expect(wordTextHasComplexScriptLetter(text), isFalse);
      expect(
        wordRunProofingLanguage(
          run,
          WmlParagraph(),
          documentLanguage: 'en-US',
          documentComplexScriptLanguage: 'ar-SA',
        ),
        'de-DE',
      );
      run.properties.complexScriptLanguage = 'he-IL';
      expect(wordRunProofingLanguage(run, WmlParagraph()), 'de-DE');
    });
  }

  test('explicit complex-script formatting still routes Latin text', () {
    final run = WmlRun(
      text: 'Text 123',
      properties: WmlRunProps(
        proofingLanguage: 'en-US',
        complexScriptLanguage: 'ar-SA',
        complexScript: true,
      ),
    );
    expect(wordRunProofingLanguage(run, WmlParagraph()), 'ar-SA');
  });

  test('complex-script text without a bidi language retains fallback', () {
    final paragraph = WmlParagraph(
      properties: WmlParagraphProps(proofingLanguage: 'de-AT'),
    );
    expect(wordRunProofingLanguage(WmlRun(text: 'مرحبا'), paragraph), 'de-AT');
  });
}

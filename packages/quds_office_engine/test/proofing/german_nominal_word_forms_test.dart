import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

void main() {
  late GermanSpellingProvider provider;
  late OfficeProofingService service;

  setUp(() {
    provider = GermanSpellingProvider();
    service = OfficeProofingService(providers: [provider]);
  });
  tearDown(() => service.dispose());

  Future<OfficeProofingReport> check(String text, {String locale = 'de-DE'}) =>
      service.check(
        OfficeProofingRequest(
          documentId: 'nominal-word-forms',
          blockId: 'paragraph',
          revision: 1,
          text: text,
          language: locale,
          startOffset: 37,
        ),
      );

  for (final locale in ['de-DE', 'de-AT', 'de-CH']) {
    test('finite nouns retain their case in $locale', () async {
      final report = await check(
        'Die Leiter steht im Schuppen. Ich mag das Lernen. '
        'Das Lernen macht Freude. Das Wissen hilft.',
        locale: locale,
      );
      expect(report.complete, isTrue);
      expect(report.findings, isEmpty);
      for (final word in [
        'Schuppen',
        'Schuppens',
        'Lernen',
        'Lernens',
        'Wissen',
        'Wissens',
      ]) {
        expect(
          await provider.isKnownWord(word, language: locale),
          isTrue,
          reason: word,
        );
      }
    });
  }

  test(
    'ordinary lowercase verb forms keep their existing acceptance',
    () async {
      final report = await check('Wir lernen heute.');
      expect(report.complete, isTrue);
      expect(report.findings, isEmpty);
      expect(await provider.isKnownWord('lernen'), isTrue);
      expect(await provider.isKnownWord('schuppen'), isTrue);
    },
  );

  test('finite entries support all-caps and authored genitive forms', () async {
    for (final word in ['SCHUPPEN', 'SCHUPPENS', 'LERNEN', 'LERNENS']) {
      expect(await provider.isKnownWord(word), isTrue, reason: word);
    }
    final report = await check('Die Freude des Lernens ist groß.');
    expect(report.findings, isEmpty);
  });

  test(
    'new nouns do not accept neighboring typos or arbitrary inflections',
    () async {
      for (final word in ['Schuppenn', 'Lernenn', 'Lernensx', 'Schuppensx']) {
        expect(await provider.isKnownWord(word), isFalse, reason: word);
      }
      const text = '🙂 Im Schuppenn steht die Leiter.';
      final report = await check(text);
      final finding = report.findings.single;
      expect(finding.originalText, 'Schuppenn');
      expect(finding.start, 37 + text.indexOf('Schuppenn'));
      expect(finding.end, finding.start + 'Schuppenn'.length);
      expect(finding.replacements, contains('Schuppen'));
    },
  );

  test('source normalization preserves original nominalized text', () async {
    final report = await check('🙂 Das Ler\u00adnen macht Freude.');
    expect(report.complete, isTrue);
    expect(report.findings, isEmpty);
  });
}

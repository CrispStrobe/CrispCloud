import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

void main() {
  late GermanSpellingProvider provider;
  late OfficeProofingService service;

  setUp(() {
    provider = GermanSpellingProvider();
    service = OfficeProofingService(
      providers: <OfficeProofingProvider>[provider],
    );
  });
  tearDown(() => service.dispose());

  Future<OfficeProofingReport> check(
    String text, {
    String language = 'de-DE',
  }) => service.check(
    OfficeProofingRequest(
      documentId: 'lexical-gaps',
      blockId: 'paragraph',
      revision: 1,
      text: text,
      language: language,
      startOffset: 37,
    ),
  );

  test(
    'courtyard lemma remains valid beside its recorded inflections',
    () async {
      final OfficeProofingReport report = await check(
        'Der Hof ist groß. Die Höfe sind groß. Wir stehen im Hof.',
      );
      expect(report.complete, isTrue);
      expect(report.findings, isEmpty);
      for (final String word in <String>[
        'Hof',
        'Hofe',
        'Hofes',
        'Hofs',
        'Höfe',
        'Höfen',
        'HOF',
      ]) {
        expect(await provider.isKnownWord(word), isTrue, reason: word);
      }
    },
  );

  test('Swiss greeting is not replaced with an unrelated noun', () async {
    final OfficeProofingReport report = await check(
      'Grüezi, ich heisse André.',
      language: 'de-CH',
    );
    expect(report.complete, isTrue);
    expect(report.findings, isEmpty);
    for (final String word in <String>['Grüezi', 'grüezi', 'GRÜEZI']) {
      expect(
        await provider.isKnownWord(word, language: 'de-CH'),
        isTrue,
        reason: word,
      );
    }
  });

  test('known finite nouns retain lowercase and typo checks', () async {
    final OfficeProofingReport report = await check('Wir stehen im hof.');
    expect(report.findings, hasLength(1));
    expect(report.findings.single.originalText, 'hof');
    expect(report.findings.single.replacements, contains('Hof'));
    expect(report.findings.single.start, 37 + 'Wir stehen im '.length);
    expect(await provider.isKnownWord('Hofr'), isFalse);
    expect(await provider.isKnownWord('Grüezix'), isFalse);
  });

  test(
    'source normalization retains decomposed accents and soft hyphens',
    () async {
      final OfficeProofingReport report = await check(
        'Gru\u0308ezi, ich stehe im Ho\u00adf.',
        language: 'de-CH',
      );
      expect(report.complete, isTrue);
      expect(report.findings, isEmpty);
    },
  );

  test(
    'valid alternative dative and explicit joined words stay accepted',
    () async {
      final OfficeProofingReport report = await check(
        'Wir stehen im Hofe. Die Hof-Tür ist offen.',
      );
      expect(report.complete, isTrue);
      expect(report.findings, isEmpty);
    },
  );

  test('Swiss sharp-s policy still applies beside the new greeting', () async {
    final OfficeProofingReport report = await check(
      'Grüezi, die Straße ist lang.',
      language: 'de-CH',
    );
    expect(report.findings, hasLength(1));
    expect(report.findings.single.originalText, 'Straße');
    expect(report.findings.single.replacements, contains('Strasse'));
  });
}

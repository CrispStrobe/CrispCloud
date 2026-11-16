import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest input(
  String text, {
  Set<String> ignored = const <String>{},
  String language = 'de-DE',
}) => OfficeProofingRequest(
  documentId: 'doc',
  blockId: 'p',
  revision: 1,
  text: text,
  language: language,
  ignoredRuleIds: ignored,
);

void main() {
  test(
    'ordinary German, valid repetitions and regional quotes stay clean',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String text in <String>[
        'Ist das das Haus?',
        'Sie sagte, dass sie sie kennt.',
        'Ich bin hier. Du bist dort. Wir sind froh.',
        '„Guten Tag“, sagte er.',
        '«Grüezi», sagte sie.',
        '»Hallo«, sagte er.',
        'Er sagt “hello”.',
        'Wir sehen d’Artagnan.',
        'Er liest Hans’ Buch.',
        'Es sind 1,25 Euro; z. B. für 3 Stück.',
        '  eingerückt\n  weiterhin eingerückt',
      ]) {
        expect(
          (await provider.check(input(text))).findings,
          isEmpty,
          reason: text,
        );
      }
    },
  );
  test('spacing checks return precise reviewable replacements', () async {
    final OfficeProofingResult result = await GermanWritingRulesProvider()
        .check(input('Hallo  Welt ,weiter'));
    expect(
      result.findings.map((OfficeProofingFinding f) => f.ruleId),
      containsAll(<String>[
        'de.spacing.repeated',
        'de.spacing.before-punctuation',
        'de.spacing.after-punctuation',
      ]),
    );
    expect(result.findings.first.replacements, <String>[' ']);
    final OfficeProofingFinding insertion = result.findings.firstWhere(
      (OfficeProofingFinding f) => f.ruleId == 'de.spacing.after-punctuation',
    );
    expect(insertion.start, insertion.end);
    expect(insertion.originalText, isEmpty);
  });
  test('only conservative repeated conjunctions are flagged', () async {
    final OfficeProofingResult result = await GermanWritingRulesProvider()
        .check(input('🙂 und und weiter'));
    expect(result.findings.single.originalText, 'und und');
    expect(result.findings.single.start, 3);
    expect(result.findings.single.replacements, <String>['und']);
  });
  test(
    'selected pronoun-verb disagreement is grammar, not a broad parser claim',
    () async {
      final OfficeProofingResult result = await GermanWritingRulesProvider()
          .check(input('Ich bist hier. Wir ist dort.'));
      expect(
        result.findings.map((OfficeProofingFinding f) => f.category),
        everyElement(OfficeProofingCategory.grammar),
      );
      expect(
        result.findings.map((OfficeProofingFinding f) => f.replacements.single),
        <String>['bin', 'sind'],
      );
    },
  );
  test(
    'unmatched delimiters and quotes remain advisory with no guessed correction',
    () async {
      final OfficeProofingResult result = await GermanWritingRulesProvider()
          .check(input('Das (offene [Zitat] lautet „Hallo.'));
      expect(
        result.findings.map((OfficeProofingFinding f) => f.ruleId),
        containsAll(<String>['de.delimiter.balance', 'de.quote.balance']),
      );
      expect(
        result.findings.map((OfficeProofingFinding f) => f.replacements),
        everyElement(isEmpty),
      );
    },
  );
  test('URLs, inline code and rule opt-outs remain untouched', () async {
    final OfficeProofingResult result = await GermanWritingRulesProvider()
        .check(
          input(
            'https://example.invalid/a,b `x ,y` Hallo  Welt',
            ignored: <String>{'de.spacing.repeated'},
          ),
        );
    expect(result.findings, isEmpty);
  });
  test('language and disposed availability are explicit', () async {
    final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
    expect(
      (await provider.check(input('hello', language: 'en-US'))).status,
      OfficeProofingStatus.unsupported,
    );
    await provider.dispose();
    expect(
      (await provider.check(input('Hallo'))).status,
      OfficeProofingStatus.unavailable,
    );
  });
  test(
    'terminology uses literal terms, Unicode word boundaries and correct offsets',
    () async {
      final OfficeTerminologyProvider provider = OfficeTerminologyProvider(
        rules: <OfficeTerminologyRule>[
          OfficeTerminologyRule(
            id: 'brand',
            term: 'Quds+',
            message: 'Use the preferred product name.',
            replacements: <String>['Quds Office'],
            languages: <String>{'de-DE'},
          ),
        ],
      );
      final OfficeProofingResult result = await provider.check(
        input('🙂 Quds+ und XQuds+ und Quds+X'),
      );
      expect(result.findings, hasLength(1));
      expect(result.findings.single.start, 3);
      expect(result.findings.single.originalText, 'Quds+');
      expect(result.findings.single.replacements, <String>['Quds Office']);
      expect(
        (await provider.check(
          input('Quds+', ignored: <String>{'brand'}),
        )).findings,
        isEmpty,
      );
      expect(
        (await provider.check(input('Quds+', language: 'en-US'))).status,
        OfficeProofingStatus.unsupported,
      );
    },
  );
}

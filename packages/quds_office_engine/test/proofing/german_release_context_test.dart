import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

// Gold sentences frozen at 8325c7b8 before implementation or provider inference.
void main() {
  const cases = <(String, String)>[
    ("Wir helfen die Freundin.", "Wir helfen der Freundin."),
    ("Wir helfen der Freundin.", "Wir helfen der Freundin."),
    ("Wir helfen die Freundinnen.", "Wir helfen den Freundinnen."),
    ("Wir helfen den Freundinnen.", "Wir helfen den Freundinnen."),
    ("Wir stehen bei jenes Gebäude.", "Wir stehen bei jenem Gebäude."),
    ("Wir stehen bei jenem Gebäude.", "Wir stehen bei jenem Gebäude."),
    ("Wir stehen bei dieses Gebäude.", "Wir stehen bei diesem Gebäude."),
    ("Wir stehen bei diesem Gebäude.", "Wir stehen bei diesem Gebäude."),
    ("Wir sprechen mit jenes Fenster.", "Wir sprechen mit jenem Fenster."),
    ("Wir sprechen mit jenem Fenster.", "Wir sprechen mit jenem Fenster."),
    (
      "Wir sprechen mit dem Straßenpolizist.",
      "Wir sprechen mit dem Straßenpolizisten.",
    ),
    (
      "Wir sprechen mit dem Straßenpolizisten.",
      "Wir sprechen mit dem Straßenpolizisten.",
    ),
    ("Wir sehen den Straßenpolizist.", "Wir sehen den Straßenpolizisten."),
    ("Wir sehen den Straßenpolizisten.", "Wir sehen den Straßenpolizisten."),
    ("Wir helfen dem Straßenpolizist.", "Wir helfen dem Straßenpolizisten."),
    ("Wir helfen dem Straßenpolizisten.", "Wir helfen dem Straßenpolizisten."),
    (
      "Wir sprechen mit dem Strassenpolizist.",
      "Wir sprechen mit dem Strassenpolizisten.",
    ),
    (
      "Wir sprechen mit dem Strassenpolizisten.",
      "Wir sprechen mit dem Strassenpolizisten.",
    ),
    ("Wir helfen der Freundin.", "Wir helfen der Freundin."),
    ("Wir helfen den Freundinnen.", "Wir helfen den Freundinnen."),
    ("Wir sprechen mit dem Mensch.", "Wir sprechen mit dem Mensch."),
    ("Wir sprechen mit den Menschen.", "Wir sprechen mit den Menschen."),
    ("Wir stehen bei den Computern.", "Wir stehen bei den Computern."),
    ("Wir sprechen mit der Kunde.", "Wir sprechen mit der Kunde."),
    ("Wir stehen bei diesem Gebäude.", "Wir stehen bei diesem Gebäude."),
    ("Wir stehen bei diesen Gebäuden.", "Wir stehen bei diesen Gebäuden."),
    ("Wir sprechen mit diesem Leiter.", "Wir sprechen mit diesem Leiter."),
    ("Wir sprechen mit dieser Leiter.", "Wir sprechen mit dieser Leiter."),
    ("Der Straßenpolizist hilft.", "Der Straßenpolizist hilft."),
    ("Die Straßenpolizisten helfen.", "Die Straßenpolizisten helfen."),
    (
      "Wir sprechen mit dem Straßenpolizisten.",
      "Wir sprechen mit dem Straßenpolizisten.",
    ),
    ("Wir sehen den Straßenpolizisten.", "Wir sehen den Straßenpolizisten."),
    (
      "Das Wort Straßenpolizist ist richtig.",
      "Das Wort Straßenpolizist ist richtig.",
    ),
    ("Das ist dieses Gebäude.", "Das ist dieses Gebäude."),
    ("Wir sehen dieses Gebäude.", "Wir sehen dieses Gebäude."),
    ("Wir helfen der Frau.", "Wir helfen der Frau."),
    ("Sie antwortet den Lehrern.", "Sie antwortet den Lehrern."),
    ("Das ist das Auto des Studenten.", "Das ist das Auto des Studenten."),
  ];
  for (final (source, expected) in cases) {
    test('context: $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      OfficeProofingRequest request(
        String text, {
        Set<String> ignored = const {},
      }) => OfficeProofingRequest(
        documentId: 'context',
        blockId: 'p',
        revision: 1,
        text: text,
        language: source.contains('Strassen') ? 'de-CH' : 'de-DE',
        startOffset: 23,
        ignoredRuleIds: ignored,
      );
      final result = await provider.check(request(source));
      expect(result.status, OfficeProofingStatus.success);
      var actual = source;
      final findings = result.findings.toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      var edge = source.length;
      for (final finding in findings) {
        expect(finding.end - 23, lessThanOrEqualTo(edge));
        expect(
          source.substring(finding.start - 23, finding.end - 23),
          finding.originalText,
        );
        actual = actual.replaceRange(
          finding.start - 23,
          finding.end - 23,
          finding.replacements.single,
        );
        edge = finding.start - 23;
      }
      final qualified = expected;
      expect(actual, qualified);
      expect((await provider.check(request(qualified))).findings, isEmpty);
      final ignored = {for (final f in findings) f.ruleId};
      if (ignored.isNotEmpty) {
        expect(
          (await provider.check(request(source, ignored: ignored))).findings,
          isEmpty,
        );
      }
    });
  }
}

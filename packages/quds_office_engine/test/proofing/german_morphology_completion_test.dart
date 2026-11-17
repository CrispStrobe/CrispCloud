import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

// First-party follow-up cases frozen before the completion implementation.
void main() {
  const cases = <(String, String)>[
    ("Das ist für diesem Schlüssel.", "Das ist für diesen Schlüssel."),
    ("Wir suchen nach dieses Schlüssel.", "Wir suchen nach diesem Schlüssel."),
    ("Sie kommt ohne jenem Schlüssel.", "Sie kommt ohne jenen Schlüssel."),
    ("Er arbeitet mit diesen Schlüssel.", "Er arbeitet mit diesen Schlüsseln."),
    ("Das ist das Auto der Student.", "Das ist das Auto des Studenten."),
    (
      "Dies ist der Mantel der Journalist.",
      "Dies ist der Mantel des Journalisten.",
    ),
    ("Es ist die Tasche der Kollege.", "Es ist die Tasche des Kollegen."),
    (
      "Das ist das Buch der neuen Student.",
      "Das ist das Buch des neuen Studenten.",
    ),
    ("Ich sehe der neue Kunde.", "Ich sehe den neuen Kunden."),
    ("Wir kennen der alte Kunde.", "Wir kennen den alten Kunden."),
    ("Ich habe ein schönen Tag.", "Ich habe einen schönen Tag."),
    ("Du hast ein langen Tag.", "Du hast einen langen Tag."),
    ("Er ist stolz auf dem Ergebnis.", "Er ist stolz auf das Ergebnis."),
    ("Wir sind stolz auf diesem Erfolg.", "Wir sind stolz auf diesen Erfolg."),
    (
      "Sie ist stolz auf der guten Leistung.",
      "Sie ist stolz auf die gute Leistung.",
    ),
    ("Ich warte auf dem Ergebnis.", "Ich warte auf das Ergebnis."),
    (
      "Sie wartet auf der neuen Nachricht.",
      "Sie wartet auf die neue Nachricht.",
    ),
    ("Wir warten auf diesem Anruf.", "Wir warten auf diesen Anruf."),
    ("Wir sprechen mit dem Mensch.", "Wir sprechen mit dem Mensch."),
    ("Wir sprechen mit dem Menschen.", "Wir sprechen mit dem Menschen."),
    ("Wir helfen der Kunde.", "Wir helfen der Kunde."),
    ('Ihr antwortet der Lehrer.', 'Ihr antwortet der Lehrer.'),
    ('Sie liebt der alte Mann.', 'Sie liebt der alte Mann.'),
    ("Wir helfen dem Kunden.", "Wir helfen dem Kunden."),
    ("Wir stehen bei den Computern.", "Wir stehen bei den Computern."),
    ("Sie antwortet den Lehrern.", "Sie antwortet den Lehrern."),
    ("Ich sehe die neue Kunde.", "Ich sehe die neue Kunde."),
    ("Ich sehe den neuen Kunden.", "Ich sehe den neuen Kunden."),
    ("Ich habe ein schönes Tag.", "Ich habe ein schönes Tag."),
    ("Ich habe einen schönen Tag.", "Ich habe einen schönen Tag."),
    ("Das ist das Auto der Studenten.", "Das ist das Auto der Studenten."),
    ("Das ist das Auto des Studenten.", "Das ist das Auto des Studenten."),
    ("Das ist das Auto der Lehrerin.", "Das ist das Auto der Lehrerin."),
    ("Das ist das Auto der Lehrer.", "Das ist das Auto der Lehrer."),
    ("Das ist der Frau ihr Auto.", "Das ist der Frau ihr Auto."),
    (
      "Das ist das Auto, der Student kommt.",
      "Das ist das Auto, der Student kommt.",
    ),
    ("Das ist das Auto der Qudsbrand.", "Das ist das Auto der Qudsbrand."),
    (
      "Das ist das Auto der Student und das Fahrrad der Frau.",
      "Das ist das Auto der Student und das Fahrrad der Frau.",
    ),
    ("Die Stimme der Student zählt.", "Die Stimme der Student zählt."),
    ("Er ist stolz auf dem Dach.", "Er ist stolz auf dem Dach."),
    ("Sie ist stolz auf dem neuen Bus.", "Sie ist stolz auf dem neuen Bus."),
    ("Sie wartet auf dem neuen Bus.", "Sie wartet auf dem neuen Bus."),
    ("Wir warten auf der Bank.", "Wir warten auf der Bank."),
    ("Ich warte auf dem Bahnsteig.", "Ich warte auf dem Bahnsteig."),
    ("Er ist stolz auf der Arbeit.", "Er ist stolz auf der Arbeit."),
    ("Er arbeitet auf dem Ergebnis.", "Er arbeitet auf dem Ergebnis."),
    ("Er steht auf dem Ergebnis.", "Er steht auf dem Ergebnis."),
    ("Ich sehe der neue Kunde kommen.", "Ich sehe der neue Kunde kommen."),
    (
      "„Für diesem Schlüssel“ steht hier als Zitat.",
      "„Für diesem Schlüssel“ steht hier als Zitat.",
    ),
    ("`Das ist für diesem Schlüssel.`", "`Das ist für diesem Schlüssel.`"),
    (
      "Er ist stolz, auf dem Ergebnis steht sein Name.",
      "Er ist stolz, auf dem Ergebnis steht sein Name.",
    ),
    (
      "Sie wartet auf dem Ergebnis und geht danach.",
      "Sie wartet auf dem Ergebnis und geht danach.",
    ),
  ];
  for (final (source, options) in <(String, List<String>)>[
    ('Ich habe ein schönen Tag.', ['einen schönen Tag', 'ein schönes Tag']),
    ('Ich sehe der neue Kunde.', ['den neuen Kunden', 'die neue Kunde']),
    ('Das ist für dem Leiter.', ['den Leiter', 'die Leiter']),
    ('Ich sehe dieser Leiter.', ['diesen Leiter', 'diese Leiter']),
    ('Ich sehe einem Mensch.', ['einen Menschen', 'ein Mensch']),
    ('Sie kommt mit das Band.', ['dem Band', 'der Band']),
  ]) {
    test('complete agreeing choices retain meanings: $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      OfficeProofingRequest request(String text) => OfficeProofingRequest(
        documentId: 'choices',
        blockId: 'p',
        revision: 1,
        text: text,
        language: 'de-DE',
        startOffset: 11,
      );
      final result = await provider.check(request(source));
      expect(result.findings, hasLength(1));
      final finding = result.findings.single;
      expect(finding.ruleId, 'de.grammar.phrase-agreement');
      expect(finding.replacements, containsAll(options));
      for (final choice in finding.replacements) {
        final text = source.replaceRange(
          finding.start - 11,
          finding.end - 11,
          choice,
        );
        expect(
          (await provider.check(request(text))).findings,
          isEmpty,
          reason: choice,
        );
      }
    });
  }
  test(
    'wrong finite agreement does not license a simultaneous case guess',
    () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      const source = 'Ich antwortet der Lehrer.';
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'agreement',
          blockId: 'p',
          revision: 1,
          text: source,
          language: 'de-DE',
        ),
      );
      expect(result.findings, isNotEmpty);
      expect(
        result.findings.every((f) => f.originalText == 'antwortet'),
        isTrue,
      );
      expect(result.findings.single.replacements, ['antworte']);
    },
  );
  for (final (source, expected) in cases) {
    test('bounded phrase: $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      OfficeProofingRequest request(
        String text, {
        Set<String> ignored = const {},
      }) => OfficeProofingRequest(
        documentId: 'completion',
        blockId: 'p',
        revision: 1,
        text: text,
        language: 'de-DE',
        startOffset: 37,
        ignoredRuleIds: ignored,
      );
      final result = await provider.check(request(source));
      expect(result.status, OfficeProofingStatus.success);
      var actual = source;
      final findings = result.findings.toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      var edge = source.length;
      for (final finding in findings) {
        expect(finding.end - 37, lessThanOrEqualTo(edge));
        expect(
          source.substring(finding.start - 37, finding.end - 37),
          finding.originalText,
        );
        expect(finding.replacements, isNotEmpty);
        // Every offered complete-phrase alternative must recheck clean.
        if (finding.ruleId == 'de.grammar.phrase-agreement') {
          for (final replacement in finding.replacements) {
            final alternate = source.replaceRange(
              finding.start - 37,
              finding.end - 37,
              replacement,
            );
            expect(
              (await provider.check(request(alternate))).findings,
              isEmpty,
              reason: alternate,
            );
          }
        }
        actual = actual.replaceRange(
          finding.start - 37,
          finding.end - 37,
          finding.replacements.first,
        );
        edge = finding.start - 37;
      }
      expect(actual, expected);
      expect((await provider.check(request(expected))).findings, isEmpty);
      if (findings.isNotEmpty) {
        expect(
          (await provider.check(
            request(source, ignored: {for (final f in findings) f.ruleId}),
          )).findings,
          isEmpty,
        );
      }
    });
  }
}

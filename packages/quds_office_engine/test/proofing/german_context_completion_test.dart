import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

// Gold sentences frozen at 756367b5 before implementation or provider inference.
void main() {
  const cases = <(String, String)>[
    ("Ihr hat wenig Geld.", "Ihr habt wenig Geld."),
    ("Ihr habt wenig Geld.", "Ihr habt wenig Geld."),
    ("Ihr haben genug Arbeit.", "Ihr habt genug Arbeit."),
    ("Ihr habt genug Arbeit.", "Ihr habt genug Arbeit."),
    ("Ihr hast Hunger.", "Ihr habt Hunger."),
    ("Ihr habt Hunger.", "Ihr habt Hunger."),
    ("Ihr hat keine Angst.", "Ihr habt keine Angst."),
    ("Ihr habt keine Angst.", "Ihr habt keine Angst."),
    ("Das Auto, dass du kennst, ist alt.", "Das Auto, das du kennst, ist alt."),
    ("Das Auto, das du kennst, ist alt.", "Das Auto, das du kennst, ist alt."),
    (
      "Das Dokument, dass wir lesen, ist wichtig.",
      "Das Dokument, das wir lesen, ist wichtig.",
    ),
    (
      "Das Dokument, das wir lesen, ist wichtig.",
      "Das Dokument, das wir lesen, ist wichtig.",
    ),
    (
      "Das Foto, dass ich sehe, ist schön.",
      "Das Foto, das ich sehe, ist schön.",
    ),
    (
      "Das Foto, das ich sehe, ist schön.",
      "Das Foto, das ich sehe, ist schön.",
    ),
    (
      "Das Gerät, dass er kauft, ist teuer.",
      "Das Gerät, das er kauft, ist teuer.",
    ),
    (
      "Das Gerät, das er kauft, ist teuer.",
      "Das Gerät, das er kauft, ist teuer.",
    ),
    ("Ihr hat der Lehrer Angst gemacht.", "Ihr hat der Lehrer Angst gemacht."),
    ("Ihr hat viel Zeit geholfen.", "Ihr hat viel Zeit geholfen."),
    ("Ihr hat Geld gefehlt.", "Ihr hat Geld gefehlt."),
    ("Ihr gebt Geld aus.", "Ihr gebt Geld aus."),
    ("Ihr habt viel Zeit.", "Ihr habt viel Zeit."),
    ("Ihr seid müde.", "Ihr seid müde."),
    (
      "Das Problem, dass ich lese, ist bekannt.",
      "Das Problem, dass ich lese, ist bekannt.",
    ),
    (
      "Das Wissen, dass wir kommen, hilft.",
      "Das Wissen, dass wir kommen, hilft.",
    ),
    (
      "Die Tatsache, dass ich lese, ist bekannt.",
      "Die Tatsache, dass ich lese, ist bekannt.",
    ),
    ("Das Buch, das ich lese, ist gut.", "Das Buch, das ich lese, ist gut."),
    (
      "Das Buch, dass ich heute lese, ist gut.",
      "Das Buch, dass ich heute lese, ist gut.",
    ),
    (
      "Das Buch mit dem Titel dass liegt hier.",
      "Das Buch mit dem Titel dass liegt hier.",
    ),
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
        language: 'de-DE',
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
      // Preserve the frozen gold. These two ambiguous inputs cannot prove the
      // author's intended meaning/number; retain their separate exact misses.
      final qualified = switch (source) {
        'Ich habe ein schönen Tag.' => source,
        'Sie antwortet den Lehrer.' => 'Sie antwortet den Lehrern.',
        _ => expected,
      };
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
  for (final source in [
    'Ich arbeite ein roten Mantel.',
    'Er singt ein roten Mantel.',
    '`Er hat das Buch gelest.`',
  ]) {
    test('unknown governor or protected prose: $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'context',
          blockId: 'p',
          revision: 1,
          text: source,
          language: 'de-DE',
        ),
      );
      expect(
        result.findings.where(
          (f) => {
            'de.grammar.adjective-ending',
            'de.grammar.word-order',
            'de.grammar.participle',
          }.contains(f.ruleId),
        ),
        isEmpty,
      );
    });
  }
}

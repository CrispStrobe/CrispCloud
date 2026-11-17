import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

const _rule = 'de.grammar.verb-object-case';
const _adjectiveRule = 'de.grammar.adjective-ending';

OfficeProofingRequest _request(
  String text, {
  String language = 'de-DE',
  int offset = 0,
  Set<String> ignored = const {},
}) => OfficeProofingRequest(
  documentId: 'bounded-object-case',
  blockId: 'paragraph',
  revision: 1,
  text: text,
  language: language,
  startOffset: offset,
  ignoredRuleIds: ignored,
);

String _apply(String source, List<OfficeProofingFinding> findings, int offset) {
  var result = source;
  var previousStart = source.length;
  final ordered = [...findings]..sort((a, b) => b.start.compareTo(a.start));
  for (final finding in ordered) {
    final start = finding.start - offset;
    final end = finding.end - offset;
    expect(end, lessThanOrEqualTo(previousStart));
    expect(source.substring(start, end), finding.originalText);
    result = result.replaceRange(start, end, finding.replacements.single);
    previousStart = start;
  }
  return result;
}

void main() {
  // These are independently authored regression examples, not changes to the
  // frozen development or prospective evaluation corpora.
  const corrections = <(String, String)>[
    ('Sie hat ein roten Mantel.', 'Sie hat einen roten Mantel.'),
    ('Ich sehe ein kleinen Hund.', 'Ich sehe einen kleinen Hund.'),
    ('Du brauchst ein neuer Tisch.', 'Du brauchst einen neuen Tisch.'),
    ('Er findet der alte Brief.', 'Er findet den alten Brief.'),
    ('Wir nehmen ein großer Stuhl.', 'Wir nehmen einen großen Stuhl.'),
    ('Ihr habt ein guter Plan.', 'Ihr habt einen guten Plan.'),
    ('Man liest ein langer Bericht.', 'Man liest einen langen Bericht.'),
    ('Ich esse ein grüner Apfel.', 'Ich esse einen grünen Apfel.'),
    ('Du kennst ein freundlicher Mann.', 'Du kennst einen freundlichen Mann.'),
    ('Er versteht dieser kurze Text.', 'Er versteht diesen kurzen Text.'),
    ('Wir kaufen ein neuer Mantel.', 'Wir kaufen einen neuen Mantel.'),
    ('Ich höre ein neuer Ton.', 'Ich höre einen neuen Ton.'),
    ('Du suchst ein kleine Hund.', 'Du suchst einen kleinen Hund.'),
    ('Er trägt ein roter Mantel.', 'Er trägt einen roten Mantel.'),
    ('Wir treffen ein alter Freund.', 'Wir treffen einen alten Freund.'),
    (
      'Man vergisst ein wichtige Termin.',
      'Man vergisst einen wichtigen Termin.',
    ),
    ('Ich trinke ein grüner Tee.', 'Ich trinke einen grünen Tee.'),
    ('Sie sehen ein neuer Hund.', 'Sie sehen einen neuen Hund.'),
    ('Es braucht ein neuen Plan.', 'Es braucht einen neuen Plan.'),
    ('Ich sehe ein kleine roter Hund.', 'Ich sehe einen kleinen roten Hund.'),
    ('Ich sehe einen kleine Hund.', 'Ich sehe einen kleinen Hund.'),
    ('Ich habe ein schöne Haus.', 'Ich habe ein schönes Haus.'),
    ('Ich sehe ein großen Ka\u0308fig.', 'Ich sehe einen großen Ka\u0308fig.'),
    ('Ich ho\u0308re ein neuen Ton.', 'Ich ho\u0308re einen neuen Ton.'),
    (
      'Ich se\u00adhe ei\u00adn kleinen Hund.',
      'Ich se\u00adhe einen kleinen Hund.',
    ),
    ('Ich sehe ein kleinen Hund!', 'Ich sehe einen kleinen Hund!'),
    ('Ich sehe ein kleinen Hund?', 'Ich sehe einen kleinen Hund?'),
  ];
  for (final (source, expected) in corrections) {
    test('correct together and recheck: $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      // The paragraph starts after an astral character elsewhere in the story.
      const prefix = '🙂 davor: ';
      final result = await provider.check(
        _request(source, offset: prefix.length),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isNotEmpty);
      expect(_apply(source, result.findings, prefix.length), expected);
      expect((await provider.check(_request(expected))).findings, isEmpty);
      for (final finding in result.findings) {
        expect(
          (prefix + source).substring(finding.start, finding.end),
          finding.originalText,
        );
        expect(finding.ruleId, anyOf(_rule, _adjectiveRule));
      }
    });
  }

  const unchanged = <String>[
    'Ich sehe einen kleinen Hund.',
    'Du brauchst einen neuen Tisch.',
    'Er findet den alten Brief.',
    'Wir nehmen einen großen Stuhl.',
    'Ihr habt einen guten Plan.',
    'Man liest einen langen Bericht.',
    'Sie hat einen roten Mantel.',
    'Sie sehen einen kleinen Hund.',
    'Es braucht einen neuen Plan.',
    // These pronouns can themselves be fronted objects. The following valid
    // nominative phrase and its matching finite verb must remain possible.
    'Sie sieht ein kleiner Hund.',
    'Sie sieht ein alter Mann.',
    'Sie sieht der alte Mann.',
    'Es sieht der alte Mann.',
    'Sie sieht der Junge.',
    'Sie sehen die alten Männer.',
    'Ihr kauft ein alter Mann.',
    'Ich sehe einen Alten.',
    'Ich sehe die Junge.',
    'Ich sehe die Leiter.',
    'Ich sehe dieser Leiter.',
    'Ich sehe einem Mensch.',
    'Ich sehe ein kleiner Hund.', // Positive/comparative stem ambiguity.
    'Man vergisst ein wichtiger Termin.',
    'Ich sehe ein kleiner roter Hund.',
    'Ich sehe ein kleinen Qudsbrand.',
    'Ich sehe ein gru\u0308nen Hund.', // Unmodeled decomposed adjective.
    'Ich sehe ein\u0301 kleinen Hund.', // No partial grapheme replacement.
    'Ich sehe ein\u200d kleinen Hund.',
    'Sie hat ein roter Mantel begeistert.',
    'Sie hat ein roten Mantel gehabt.',
    'Ich habe ein kleinen Hund gesehen.',
    'Sie hat ein roten Mantel', // A truncated request cannot establish case.
    'Ich sehe ein kleinen Hund',
    'Ich sehe ein kleinen Hund,',
    'Ich sehe ein kleinen Hund; er kommt.',
    'Ich sehe ein kleinen Hund und eine Katze.',
    'Ich sehe ein kleinen Hund, der spielt.',
    'Ich sehe ein kleinen Hund. Er kommt.',
    'Ich und sie sehen ein kleinen Hund.',
    'Heute sehe ich ein kleinen Hund.',
    'Ein kleinen Hund sehe ich.',
    'Wenn ich ein kleinen Hund sehe.',
    'Ich sehe ein kleinen Hund heute.',
    'Ich sehe ein ganz kleinen Hund.',
    'Ich sehe ein kleiner roter guter Hund.',
    'Ich bin ein guter Mann.',
    'Er wird ein guter Mann.',
    'Ich helfe einem kleinen Kind.',
    'Ich antworte einem alten Mann.',
    'Ich gebe einem alten Mann ein Buch.',
    '`Ich` sehe ein kleinen Hund.',
    'Ich `sehe` ein kleinen Hund.',
    'Ich sehe `ein` kleinen Hund.',
    'Ich sehe ein `kleinen` Hund.',
    'Ich sehe ein kleinen `Hund`.',
    '`Ich sehe ein kleinen Hund.`',
    'Ich sehe ein kleinen Hund. `Anhang`',
    'Ich sehe ein kleinen Hund. https://example.org/',
    'https://example.org/sehe ein kleinen Hund.',
  ];
  for (final source in unchanged) {
    test('preserve or abstain without nominative fallback: $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final result = await provider.check(_request(source));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isEmpty);
    });
  }

  test(
    'the case rule has its own metadata and independent ignore control',
    () async {
      expect(GermanWritingRulesProvider.ruleIds, contains(_rule));
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final result = await provider.check(
        _request('Sie hat ein roten Mantel.'),
      );
      final finding = result.findings.single;
      expect(finding.ruleId, _rule);
      expect(finding.originalText, 'ein');
      expect(finding.replacements, ['einen']);
      expect(finding.message, contains('Akkusativ'));
      expect(finding.message, isNot(contains('Präposition')));
      expect(
        (await provider.check(
          _request('Sie hat ein roten Mantel.', ignored: {_rule}),
        )).findings,
        isEmpty,
      );
      final pair = await provider.check(_request('Ich sehe ein kleine Hund.'));
      expect(pair.findings.map((finding) => finding.ruleId).toSet(), {
        _rule,
        _adjectiveRule,
      });
      final ignoredArticle = await provider.check(
        _request('Ich sehe ein kleine Hund.', ignored: {_rule}),
      );
      expect(ignoredArticle.findings.single.ruleId, _adjectiveRule);
      expect(ignoredArticle.findings.single.replacements, ['kleinen']);
      expect(
        (await provider.check(
          _request(
            'Ich sehe ein kleine Hund.',
            ignored: {_rule, _adjectiveRule},
          ),
        )).findings,
        isEmpty,
      );
    },
  );

  test('preposition rules keep their identifiers and messages', () async {
    final provider = GermanWritingRulesProvider();
    addTearDown(provider.dispose);
    final result = await provider.check(_request('Ich komme mit den Mann.'));
    expect(result.findings.single.ruleId, 'de.grammar.preposition-case');
    expect(result.findings.single.message, contains('Präposition'));
    expect(result.findings.single.replacements, ['dem']);
  });

  test('finite agreement is required before case inference', () async {
    final provider = GermanWritingRulesProvider();
    addTearDown(provider.dispose);
    for (final source in [
      'Ich sieht ein kleinen Hund.',
      'Du sehen ein kleinen Hund.',
    ]) {
      final result = await provider.check(_request(source));
      expect(
        result.findings.where((finding) => finding.ruleId == _rule),
        isEmpty,
      );
      expect(
        result.findings.where((finding) => finding.ruleId == _adjectiveRule),
        isEmpty,
      );
    }
  });

  test(
    'bounded gate never treats a clipped lookahead as clause completion',
    () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      for (final source in [
        'Ich sehe ein kleinen Hund${List.filled(1024, ' ').join()}.',
        'Ich sehe ein kleinen Hund${List.filled(1024, ' ').join()}gesehen.',
      ]) {
        final result = await provider.check(_request(source));
        expect(
          result.findings.where(
            (finding) => finding.category == OfficeProofingCategory.grammar,
          ),
          isEmpty,
        );
      }
    },
  );

  test('regional locales retain the same finite clause checks', () async {
    final provider = GermanWritingRulesProvider();
    addTearDown(provider.dispose);
    for (final language in ['de-DE', 'de-AT', 'de-CH']) {
      final result = await provider.check(
        _request('Ich sehe ein kleinen Hund.', language: language),
      );
      expect(result.findings.single.ruleId, _rule);
      expect(result.findings.single.replacements, ['einen']);
    }
  });

  test(
    'personal spelling vocabulary does not invent noun morphology',
    () async {
      final vocabulary = OfficeProofingVocabulary()..addWord('Qudsbrand');
      final service = OfficeProofingService(
        providers: [
          GermanSpellingProvider(vocabulary: vocabulary),
          GermanWritingRulesProvider(),
        ],
      );
      addTearDown(service.dispose);
      final result = await service.check(
        _request('Ich sehe ein kleinen Qudsbrand.'),
      );
      expect(result.findings, isEmpty);
      expect(vocabulary.contains('Qudsbrand'), isTrue);
    },
  );
}

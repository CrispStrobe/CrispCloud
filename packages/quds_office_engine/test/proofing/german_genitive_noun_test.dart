import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(
  String text, {
  String language = 'de-DE',
  int offset = 0,
  Set<String> ignored = const <String>{},
}) => OfficeProofingRequest(
  documentId: 'explicit-genitive',
  blockId: 'paragraph',
  revision: 3,
  text: text,
  language: language,
  startOffset: offset,
  ignoredRuleIds: ignored,
);

String _apply(String source, List<OfficeProofingFinding> findings, int offset) {
  final List<OfficeProofingFinding> ordered =
      List<OfficeProofingFinding>.of(findings)..sort(
        (OfficeProofingFinding a, OfficeProofingFinding b) =>
            b.start.compareTo(a.start),
      );
  int edge = source.length;
  String result = source;
  for (final OfficeProofingFinding finding in ordered) {
    final int start = finding.start - offset;
    final int end = finding.end - offset;
    expect(end, lessThanOrEqualTo(edge));
    expect(source.substring(start, end), finding.originalText);
    expect(finding.replacements, hasLength(1));
    result = result.replaceRange(start, end, finding.replacements.single);
    edge = start;
  }
  return result;
}

void main() {
  // Independently authored sentences exercise case signals in actual prose.
  // The governor is the unambiguous article, including when no preposition
  // exists; no case policy is imposed on variable-case prepositions.
  const List<(String, String)> corrections = <(String, String)>[
    (
      'Das ist wegen des schlimmen Fehler.',
      'Das ist wegen des schlimmen Fehlers.',
    ),
    ('Das ist das Auto des Student.', 'Das ist das Auto des Studenten.'),
    ('Die Frage eines Kunde bleibt.', 'Die Frage eines Kunden bleibt.'),
    ('Die Antwort meines Lehrer fehlt.', 'Die Antwort meines Lehrers fehlt.'),
    ('Die Antwort deines Kollege fehlt.', 'Die Antwort deines Kollegen fehlt.'),
    (
      'Die Stimme seines Präsident fehlt.',
      'Die Stimme seines Präsidenten fehlt.',
    ),
    ('Das ist die Folge ihres Fehler.', 'Das ist die Folge ihres Fehlers.'),
    (
      'Das ist die Aufgabe unseres Kollege.',
      'Das ist die Aufgabe unseres Kollegen.',
    ),
    ('Der Erfolg eures Lehrer zählt.', 'Der Erfolg eures Lehrers zählt.'),
    ('Der Fehler keines Student zählt.', 'Der Fehler keines Studenten zählt.'),
    ('Die Bedeutung des Name bleibt.', 'Die Bedeutung des Namens bleibt.'),
    ('Die Stimme des Herz zählt.', 'Die Stimme des Herzens zählt.'),
    ('Die Farbe des Bonbon bleibt.', 'Die Farbe des Bonbons bleibt.'),
    ('Die Folge des Ergebnis bleibt.', 'Die Folge des Ergebnisses bleibt.'),
  ];
  for (final (String source, String expected) in corrections) {
    test('genitive correction and recheck: $source', () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final OfficeProofingRequest request = _request(source);
      final OfficeProofingResult result = await provider.check(request);
      expect(result.request, same(request));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, hasLength(1));
      expect(result.findings.single.ruleId, 'de.grammar.noun-case');
      expect(_apply(source, result.findings, 0), expected);

      final OfficeProofingResult recheck = await provider.check(
        _request(expected),
      );
      expect(recheck.status, OfficeProofingStatus.success);
      expect(recheck.findings, isEmpty);
    });
  }

  const List<String> controls = <String>[
    // Valid alternatives and invariant genitives must not be normalized.
    'Das ist wegen des schlimmen Fehlers.',
    'Das ist das Auto des Studenten.',
    'Die Stimme des Kindes zählt.',
    'Die Stimme des Kinds zählt.',
    'Die Farbe des Teiles bleibt.',
    'Die Farbe des Teils bleibt.',
    'Die Stimme des Nachbarn zählt.',
    'Die Stimme des Nachbars zählt.',
    'Die Höhe des Gewinnes zählt.',
    'Die Höhe des Gewinns zählt.',
    'Die Bedeutung des Euro bleibt.',
    'Die Bedeutung des Euros bleibt.',
    'Die Bedeutung des Status bleibt.',
    'Die Bedeutung des Modus bleibt.',
    // More than one replacement remains an abstention, not a chosen variant.
    'Die Farbe des Teil bleibt.',
    'Die Stimme des Nachbar zählt.',
    'Die Höhe des Gewinn zählt.',
    // These article forms do not establish a unique case.
    'Dieses Leben zählt.',
    'Jenes Ergebnis zählt.',
    'Der Student arbeitet.',
    'Dieser Fehler zählt.',
    'Unser Lehrer arbeitet.',
    'Das ist das Auto der Student.',
    // Keep nominalized and unresolved analyses, and unknown nouns, untouched.
    'Die Stimme des Jungen zählt.',
    'Die Stimme des Armen zählt.',
    'Die Stimme eines Bekannten zählt.',
    'Die Stimme eines Deutschen zählt.',
    'Die Folgen des Schlimmen bleiben.',
    'Das Schlimme bleibt.',
    'Die Stimme des Qudsbrand zählt.',
    'Die Stimme des qudsartigen Student zählt.',
    // Do not choose a different article for an incompatible noun reading.
    'Die Stimme des Frau zählt.',
    'Die Stimme eines Frauen zählt.',
    // Variable-case prepositions still accept their existing dative phrases.
    'Das ist wegen dem schlimmen Fehler.',
    'Das ist trotz dem schlimmen Fehler.',
  ];
  for (final String source in controls) {
    test('preserve valid or undecided genitive: $source', () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final OfficeProofingResult result = await provider.check(
        _request(source),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isEmpty);
    });
  }

  test(
    'noun and adjective repairs remain disjoint and independently ignored',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      const String source = 'Das ist wegen des schlimme Fehler.';
      final OfficeProofingResult result = await provider.check(
        _request(source),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(
        result.findings.map((OfficeProofingFinding finding) => finding.ruleId),
        unorderedEquals(<String>[
          'de.grammar.noun-case',
          'de.grammar.adjective-ending',
        ]),
      );
      expect(
        _apply(source, result.findings, 0),
        'Das ist wegen des schlimmen Fehlers.',
      );
      final OfficeProofingResult ignored = await provider.check(
        _request(source, ignored: <String>{'de.grammar.noun-case'}),
      );
      expect(ignored.status, OfficeProofingStatus.success);
      expect(ignored.findings, hasLength(1));
      expect(ignored.findings.single.ruleId, 'de.grammar.adjective-ending');
      expect(
        _apply(source, ignored.findings, 0),
        'Das ist wegen des schlimmen Fehler.',
      );
    },
  );

  test(
    'Swiss aliases preserve orthography and original UTF-16 ownership',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      for (final String language in <String>[
        'de-CH',
        'de_CH',
        'de-Latn-CH-1996-u-co-phonebk',
      ]) {
        const String source = '👩🏽‍💻 Die Farbe des Stra\u00aduss bleibt.';
        final OfficeProofingResult result = await provider.check(
          _request(source, language: language, offset: 37),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, hasLength(1));
        expect(result.findings.single.ruleId, 'de.grammar.noun-case');
        expect(result.findings.single.originalText, 'Stra\u00aduss');
        expect(result.findings.single.replacements, <String>['Strausses']);
        expect(
          _apply(source, result.findings, 37),
          '👩🏽‍💻 Die Farbe des Strausses bleibt.',
        );
        final OfficeProofingResult recheck = await provider.check(
          _request('Die Farbe des Strausses bleibt.', language: language),
        );
        expect(recheck.status, OfficeProofingStatus.success);
        expect(recheck.findings, isEmpty);
      }
    },
  );

  test(
    'standard and Austrian German retain sharp-s in genitive replacements',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      for (final String language in <String>['de-DE', 'de-AT', 'de_AT']) {
        const String source = 'Die Farbe des Strauß bleibt.';
        final OfficeProofingResult result = await provider.check(
          _request(source, language: language),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, hasLength(1));
        expect(result.findings.single.replacements, <String>['Straußes']);
        expect(
          _apply(source, result.findings, 0),
          'Die Farbe des Straußes bleibt.',
        );
      }
    },
  );

  test(
    'explicit genitive respects protected text and whole source graphemes',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      for (final String source in <String>[
        '`des Student`',
        '``eines Kunde``',
        '```de\ndes Student\n```',
        '`des` Student',
        'des `Student`',
        'https://example.invalid/des/Student',
        'name@Student.example',
        'Die Stimme des Stu\u0301dent zählt.',
        'Die Stimme des Student\u200d zählt.',
        'Die Stimme des Student\ufe0f zählt.',
        'Die Stimme des\n Student zählt.',
      ]) {
        final OfficeProofingResult result = await provider.check(
          _request(source),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty, reason: source);
      }
    },
  );
}

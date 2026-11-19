import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Small source-bound smoke panel for the shipped dictionary, including native
/// AOT and JavaScript builds. It needs no model, network, daemon or Flutter UI.
/// This checks these explicit examples, not general German spelling accuracy.
final class _SpellingCase {
  const _SpellingCase(
    this.id,
    this.text, {
    this.language = 'de-DE',
    this.maximumSuggestions = 5,
    this.personal = const <String>[],
    this.expected = const <(String, String?)>[],
    this.finalFindingAtEnd = false,
  });

  final String id;
  final String text;
  final String language;
  final int maximumSuggestions;
  final List<String> personal;
  final List<(String, String?)> expected;
  // Distinguishes the final prose word from identically spelled protected text.
  final bool finalFindingAtEnd;
}

const _cases = <_SpellingCase>[
  _SpellingCase('ordinary-clean', 'Das Haus ist schön.'),
  _SpellingCase('ascii-apostrophe-clean', "Er darf's."),
  _SpellingCase('curly-apostrophe-clean', 'Er darf’s.'),
  _SpellingCase('austrian-apostrophe-clean', 'Er darf’s.', language: 'de-AT'),
  _SpellingCase('swiss-apostrophe-clean', 'Er darf’s.', language: 'de-CH'),
  _SpellingCase('uppercase-apostrophe-clean', 'ER DARF’S.'),
  _SpellingCase(
    'ascii-apostrophe-typo',
    "Er draf's.",
    expected: <(String, String?)>[("draf's", "darf's")],
  ),
  _SpellingCase(
    'curly-apostrophe-typo',
    'Er draf’s.',
    expected: <(String, String?)>[('draf’s', 'darf’s')],
  ),
  _SpellingCase(
    'source-coordinates-and-cache',
    "🙂 Gru\u0308ße draf's draf’s",
    expected: <(String, String?)>[("draf's", "darf's"), ('draf’s', 'darf’s')],
  ),
  _SpellingCase(
    'personal-apostrophe-clean',
    'O’Connor',
    personal: <String>["O'Connor"],
  ),
  _SpellingCase(
    'personal-separators',
    'O’Connor\u2011Huas',
    personal: <String>["O'Connor"],
    expected: <(String, String?)>[('O’Connor\u2011Huas', 'O’Connor\u2011Haus')],
  ),
  _SpellingCase(
    'two-constituent-repair',
    'Ein Huas-Türr.',
    expected: <(String, String?)>[('Huas-Türr', 'Haus-Tür')],
  ),
  _SpellingCase(
    'nonbreaking-hyphen-repair',
    'Ein Huas\u2011Türr.',
    expected: <(String, String?)>[('Huas\u2011Türr', 'Haus\u2011Tür')],
  ),
  _SpellingCase(
    'known-personal-constituent',
    'Qudsmarke-Huas-Türr',
    personal: <String>['Qudsmarke'],
    expected: <(String, String?)>[
      ('Qudsmarke-Huas-Türr', 'Qudsmarke-Haus-Tür'),
    ],
  ),
  _SpellingCase(
    'protected-text-clean',
    '`draf’s Huas-Türr` https://example.com/Feler userFeler@example.com',
  ),
  _SpellingCase(
    'arbitrary-apostrophe-still-unknown',
    'Ha’us',
    expected: <(String, String?)>[('Ha’us', null)],
  ),
  _SpellingCase('known-compound-clean', 'Eine Haus-Tür.'),
  _SpellingCase('swiss-clean', 'Ein Gruss.', language: 'de-CH'),
  _SpellingCase(
    'swiss-sharp-s-correction',
    'Ein Gruß.',
    language: 'de-CH',
    expected: <(String, String?)>[('Gruß', 'Gruss')],
  ),
  _SpellingCase(
    'ordinary-typo',
    'Ein Feler.',
    expected: <(String, String?)>[('Feler', 'Fehler')],
  ),
  _SpellingCase(
    'whole-word-suggestion-retained',
    'Make-up',
    expected: <(String, String?)>[('Make-up', 'Makeup')],
  ),
  _SpellingCase(
    'uppercase-distinct-shortlist',
    'LERNNEN',
    maximumSuggestions: 2,
    expected: <(String, String?)>[('LERNNEN', 'LERNTEN')],
  ),
  _SpellingCase(
    'sentence-initial-distinct-shortlist',
    'Lernnen',
    maximumSuggestions: 2,
    expected: <(String, String?)>[('Lernnen', 'Lernten')],
  ),
  _SpellingCase(
    'uppercase-full-shortlist',
    'LERNNEN',
    expected: <(String, String?)>[('LERNNEN', 'LEHNTEN')],
  ),
  _SpellingCase(
    'sentence-initial-full-shortlist',
    'Lernnen',
    expected: <(String, String?)>[('Lernnen', 'Lehnten')],
  ),
  _SpellingCase('marked-numeric-prefixes', '1\u0301Huas 𝟘\u0308Huas'),
  _SpellingCase('marked-connector-prefixes', '_\u0301Huas ‿\u0308Huas'),
  _SpellingCase(
    'prose-next-to-marked-identifiers',
    '_\u0301 Huas',
    expected: <(String, String?)>[('Huas', 'Haus')],
  ),
  _SpellingCase(
    'short-accent-noun',
    'Cafè',
    expected: <(String, String?)>[('Cafè', 'Café')],
  ),
  _SpellingCase(
    'short-accent-name',
    'Joêl',
    expected: <(String, String?)>[('Joêl', 'Joël')],
  ),
  _SpellingCase(
    'short-accent-adjective',
    'hier rosè',
    expected: <(String, String?)>[('rosè', 'rosé')],
  ),
  _SpellingCase(
    'short-accent-uppercase',
    'CAFÈ',
    expected: <(String, String?)>[('CAFÈ', 'CAFÉ')],
  ),
  _SpellingCase(
    'short-accent-decomposed',
    '🙂 Cafe\u0300',
    expected: <(String, String?)>[('Cafe\u0300', 'Café')],
  ),
  _SpellingCase(
    'short-accent-compound',
    'Joêl\u2011Huas',
    expected: <(String, String?)>[('Joêl\u2011Huas', 'Joël\u2011Haus')],
  ),
  _SpellingCase(
    'short-accent-swiss',
    'Cafè',
    language: 'de-CH',
    expected: <(String, String?)>[('Cafè', 'Café')],
  ),
  _SpellingCase(
    'decomposed-shipped-names',
    'Joe\u0308l Citroe\u0308n Bronte\u0308 Danae\u0308 S\u030ckoda S\u030ckodas',
  ),
  _SpellingCase(
    'decomposed-austrian-names',
    'Joe\u0308l S\u030ckoda',
    language: 'de-AT',
  ),
  _SpellingCase(
    'decomposed-swiss-names',
    'Joe\u0308l S\u030ckoda',
    language: 'de-CH',
  ),
  _SpellingCase(
    'decomposed-uppercase-names',
    'JOE\u0308L CITROE\u0308N S\u030cKODA',
  ),
  _SpellingCase(
    'soft-hyphen-accent-composition',
    'Ha\u00ad\u0308user Gru\u00ad\u0308ße Joe\u00ad\u0308l',
  ),
  _SpellingCase(
    'decomposed-name-repair',
    '🙂 Joe\u0308ll S\u030ckodaa',
    expected: <(String, String?)>[
      ('Joe\u0308ll', 'Joël'),
      ('S\u030ckodaa', 'Škoda'),
    ],
  ),
  _SpellingCase(
    'decomposed-compound-repair',
    '🙂 Joe\u0308l\u2011Huas',
    expected: <(String, String?)>[('Joe\u0308l\u2011Huas', 'Joël\u2011Haus')],
  ),
  _SpellingCase(
    'personal-canonical-alias',
    'QudsJoe\u0308l QudsS\u030c',
    personal: <String>['QudsJoël', 'QudsŠ'],
  ),
  _SpellingCase(
    'soft-hyphen-identifier-prefixes',
    '42\u00adHuas _\u00adHuas 𝟘\u00ad\u0301Huas Huas',
    expected: <(String, String?)>[('Huas', 'Haus')],
    finalFindingAtEnd: true,
  ),
  _SpellingCase(
    'soft-hyphen-protected-text',
    'ht\u00adtps://example.invalid/Huas Huas@exam\u00adple.invalid `\u00ad`Huas`` Huas',
    expected: <(String, String?)>[('Huas', 'Haus')],
    finalFindingAtEnd: true,
  ),
  _SpellingCase(
    'source-protected-code',
    '`Huas`\u00ad` Huas',
    expected: <(String, String?)>[('Huas', 'Haus')],
    finalFindingAtEnd: true,
  ),
  _SpellingCase(
    'prepended-identifier-edges',
    '\u06004\u0301\u00adHuas Huas\u{110bd}𝟘 Huas',
    expected: <(String, String?)>[('Huas', 'Haus')],
    finalFindingAtEnd: true,
  ),
  _SpellingCase(
    'projected-joiner-boundary',
    'Huas\u00ad\u200d Huas',
    expected: <(String, String?)>[('Huas', 'Haus')],
    finalFindingAtEnd: true,
  ),
];

Future<void> main() async {
  const origin = 17;
  final results = <Map<String, Object?>>[];
  for (final sample in _cases) {
    final provider = GermanSpellingProvider(
      maximumSuggestions: sample.maximumSuggestions,
    );
    try {
      for (final word in sample.personal) {
        provider.vocabulary.addWord(word, language: sample.language);
      }
      final request = OfficeProofingRequest(
        documentId: 'native-spelling-smoke',
        blockId: sample.id,
        revision: 1,
        text: sample.text,
        language: sample.language,
        startOffset: origin,
      );
      final report = await provider.check(request);
      var accepted =
          report.status == OfficeProofingStatus.success &&
          report.findings.length == sample.expected.length;
      for (var i = 0; i < report.findings.length; i++) {
        final finding = report.findings[i];
        final start = finding.start - origin;
        final end = finding.end - origin;
        accepted =
            accepted &&
            start >= 0 &&
            end <= sample.text.length &&
            end > start &&
            sample.text.substring(start, end) == finding.originalText &&
            finding.replacements.length <= provider.maximumSuggestions;
        if (i < sample.expected.length) {
          final (source, replacement) = sample.expected[i];
          accepted =
              accepted &&
              finding.originalText == source &&
              (replacement == null ||
                  finding.replacements.contains(replacement));
        }
      }
      if (sample.finalFindingAtEnd) {
        accepted =
            accepted &&
            report.findings.isNotEmpty &&
            report.findings.last.end == origin + sample.text.length;
      }
      results.add(<String, Object?>{
        'id': sample.id,
        'text': sample.text,
        'language': sample.language,
        'maximumSuggestions': sample.maximumSuggestions,
        'finalFindingAtEnd': sample.finalFindingAtEnd,
        'status': report.status.name,
        'accepted': accepted,
        'findings': <Map<String, Object?>>[
          for (final finding in report.findings)
            <String, Object?>{
              'start': finding.start,
              'end': finding.end,
              'source': finding.originalText,
              'replacements': finding.replacements,
            },
        ],
      });
    } finally {
      await provider.dispose();
    }
  }
  final failed = results.where((result) => result['accepted'] != true).length;
  print(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'caseCount': results.length,
      'failed': failed,
      'cases': results,
    }),
  );
  if (failed != 0) {
    throw StateError('$failed native spelling smoke cases failed.');
  }
}

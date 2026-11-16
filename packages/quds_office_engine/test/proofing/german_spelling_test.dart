import 'dart:convert';

import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest input(String text, {String language = 'de-DE'}) =>
    OfficeProofingRequest(
      documentId: 'doc',
      blockId: 'p',
      revision: 1,
      text: text,
      language: language,
    );

void main() {
  late GermanSpellingProvider provider;
  setUp(() {
    provider = GermanSpellingProvider();
  });
  tearDown(() async {
    await provider.dispose();
  });

  test('real shipped dictionary accepts ordinary modern German', () async {
    final OfficeProofingResult result = await provider.check(
      input('🙂 Das ist ein schöner Text. Wir sind hier.'),
    );
    expect(result.status, OfficeProofingStatus.success);
    expect(
      result.findings.map((OfficeProofingFinding f) => f.originalText),
      isEmpty,
    );
  });
  test('transposed letters receive a useful bounded suggestion', () async {
    final OfficeProofingResult result = await provider.check(
      input('Das Huas ist schön.'),
    );
    final OfficeProofingFinding finding = result.findings.single;
    expect(finding.originalText, 'Huas');
    expect(finding.replacements, contains('Haus'));
    expect(finding.replacements.length, lessThanOrEqualTo(5));
  });
  test('offsets preserve emoji and decomposed source characters', () async {
    const String text = '🙂 Gru\u0308ße Huas';
    final OfficeProofingResult result = await provider.check(input(text));
    expect(result.findings, hasLength(1));
    expect(result.findings.single.start, text.indexOf('Huas'));
    expect(result.findings.single.originalText, 'Huas');
  });
  test('explicit soft hyphens do not split logical spelling tokens', () async {
    final OfficeProofingResult result = await provider.check(
      input('Recht\u00adschreibung'),
    );
    expect(result.findings, isEmpty);
  });
  test('standalone soft hyphens and combining marks are not words', () async {
    final OfficeProofingService service = OfficeProofingService(
      providers: <OfficeProofingProvider>[provider],
    );
    for (final String text in <String>[
      '\u00ad',
      '\u00ad \u00ad\u00ad \u0308',
      '.\u0308 !\u0301',
      '\u00adRecht\u00adschreibung\u00ad',
    ]) {
      final OfficeProofingReport report = await service.check(input(text));
      expect(report.results.single.status, OfficeProofingStatus.success);
      expect(report.isClean, isTrue, reason: text);
    }
  });
  test('ignored nonwords retain subsequent spelling source offsets', () async {
    const String text = '\u00ad .\u0308 🙂 Huas';
    final OfficeProofingRequest request = OfficeProofingRequest(
      documentId: 'doc',
      blockId: 'p',
      revision: 1,
      text: text,
      startOffset: 20,
    );
    final OfficeProofingReport report = await OfficeProofingService(
      providers: <OfficeProofingProvider>[provider],
    ).check(request);
    expect(report.complete, isTrue);
    final OfficeProofingFinding finding = report.findings.single;
    expect(finding.originalText, 'Huas');
    expect(finding.start, 20 + text.indexOf('Huas'));
    expect(finding.end, 20 + text.length);
    expect(finding.replacements, contains('Haus'));
  });
  test(
    'joiner-adjacent spelling fragments do not fail the paragraph',
    () async {
      final OfficeProofingService service = OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      );
      for (final String joiner in <String>['\u200d', '\u200c']) {
        for (final String word in <String>['Haus', 'Huas']) {
          final String text = '$word$joiner Haus Huas';
          final OfficeProofingReport report = await service.check(
            OfficeProofingRequest(
              documentId: 'doc',
              blockId: 'p',
              revision: 1,
              text: text,
              startOffset: 20,
            ),
          );
          expect(report.results.single.status, OfficeProofingStatus.success);
          expect(report.complete, isTrue);
          final OfficeProofingFinding finding = report.findings.single;
          expect(finding.originalText, 'Huas');
          expect(finding.start, 20 + text.lastIndexOf('Huas'));
          expect(finding.end, 20 + text.length);
          expect(finding.replacements, contains('Haus'));
        }
      }
    },
  );
  test(
    'all-capitals sharp-s words are valid in German and Swiss forms',
    () async {
      expect((await provider.check(input('STRASSE GRÜSSE'))).findings, isEmpty);
      expect(
        (await provider.check(
          input('STRASSE GRÜSSE', language: 'de-CH'),
        )).findings,
        isEmpty,
      );
    },
  );
  test('obsolete source variants are excluded from modern spelling', () async {
    final OfficeProofingResult modern = await provider.check(
      input('dass Fluss muss'),
    );
    expect(modern.findings, isEmpty);
    final OfficeProofingResult obsolete = await provider.check(
      input('daß Fluß muß'),
    );
    expect(obsolete.findings.first.replacements, contains('dass'));
    expect(
      obsolete.findings.map((OfficeProofingFinding f) => f.originalText),
      containsAll(<String>['daß', 'Fluß', 'muß']),
    );
  });
  test(
    'Swiss spellings are locale-scoped and sharp-s receives ss suggestion',
    () async {
      expect(
        (await provider.check(
          input('Strasse Grüsse', language: 'de-CH'),
        )).findings,
        isEmpty,
      );
      final OfficeProofingResult swiss = await provider.check(
        input('Straße', language: 'de-CH'),
      );
      expect(swiss.findings.single.replacements, contains('Strasse'));
      final OfficeProofingResult german = await provider.check(
        input('Strasse'),
      );
      expect(german.findings.single.replacements, contains('Straße'));
    },
  );
  test(
    'Austrian source forms and canonical locale tags are supported',
    () async {
      expect(
        (await provider.check(input('Jänner', language: 'de_AT'))).findings,
        isEmpty,
      );
      expect(input('Text', language: 'de').language, 'de-DE');
    },
  );
  test('Swiss capital sharp-s offers the matching SS replacement', () async {
    const String text = '🙂 STRAẞE GRÜẞE';
    final OfficeProofingResult result = await provider.check(
      input(text, language: 'de-CH'),
    );
    expect(result.status, OfficeProofingStatus.success);
    expect(
      result.findings.map((OfficeProofingFinding f) => f.originalText),
      <String>['STRAẞE', 'GRÜẞE'],
    );
    expect(result.findings[0].start, text.indexOf('STRAẞE'));
    expect(result.findings[0].replacements, contains('STRASSE'));
    expect(result.findings[1].replacements, contains('GRÜSSE'));
    expect(
      result.findings.map((OfficeProofingFinding f) => f.message),
      everyElement('Die Schweizer Schreibweise verwendet ss statt ß.'),
    );
    expect((await provider.check(input('STRAẞE GRÜẞE'))).findings, isEmpty);
  });
  test('unsupported languages and disposed backend are explicit', () async {
    expect(
      (await provider.check(input('bonjour', language: 'fr-FR'))).status,
      OfficeProofingStatus.unsupported,
    );
    await provider.dispose();
    expect(
      (await provider.check(input('Hallo'))).status,
      OfficeProofingStatus.unavailable,
    );
  });
  test(
    'noun casing remains meaningful; all-capitals remain accepted',
    () async {
      expect((await provider.check(input('HAUS'))).findings, isEmpty);
      final OfficeProofingResult result = await provider.check(
        input('ein haus'),
      );
      expect(result.findings.single.originalText, 'haus');
      expect(result.findings.single.replacements, contains('Haus'));
    },
  );
  test('explicit compounds keep German noun case significant', () async {
    expect(
      (await provider.check(input('haus-tür'))).findings.single.originalText,
      'haus-tür',
    );
    expect((await provider.check(input('HAUS-TÜR'))).findings, isEmpty);
  });
  test(
    'explicit compound suggestions preserve other nouns and hyphen styles',
    () async {
      const List<(String, String)> cases = <(String, String)>[
        ('Huas-Tür', 'Haus-Tür'),
        ('Haus-Tür-Huas', 'Haus-Tür-Haus'),
        ('HUAS-TÜR', 'HAUS-TÜR'),
        ('Huas\u2010Tür', 'Haus\u2010Tür'),
        ('Huas\u2011Tür', 'Haus\u2011Tür'),
        ('Huas-Tür\u2011Haus', 'Haus-Tür\u2011Haus'),
      ];
      for (final (String, String) entry in cases) {
        final String text = '🙂 ${entry.$1}';
        final OfficeProofingResult result = await provider.check(input(text));
        expect(result.findings, hasLength(1), reason: text);
        final OfficeProofingFinding finding = result.findings.single;
        expect(finding.originalText, entry.$1);
        expect(finding.start, 3);
        expect(finding.end, text.length);
        expect(finding.replacements, contains(entry.$2));
        expect(finding.replacements.length, lessThanOrEqualTo(5));
      }
    },
  );
  test(
    'explicit compound repair honors the ordinary candidate budget',
    () async {
      final GermanSpellingProvider bounded = GermanSpellingProvider(
        maximumSuggestions: 1,
        maximumCandidateChecks: 100,
      );
      final OfficeProofingResult result = await bounded.check(
        input('Huas-Tür'),
      );
      expect(result.findings.single.replacements, <String>['Haus-Tür']);
      await bounded.dispose();
    },
  );
  test(
    'compound suggestions keep per-occurrence separators and Swiss forms',
    () async {
      final OfficeProofingResult mixed = await provider.check(
        input('Huas-Tür Huas\u2011Tür'),
      );
      expect(mixed.findings, hasLength(2));
      expect(mixed.findings[0].replacements, contains('Haus-Tür'));
      expect(mixed.findings[1].replacements, contains('Haus\u2011Tür'));
      final OfficeProofingResult swiss = await provider.check(
        input('Straße-Tür STRAẞE-TÜR', language: 'de-CH'),
      );
      expect(swiss.findings, hasLength(2));
      expect(swiss.findings[0].replacements, contains('Strasse-Tür'));
      expect(swiss.findings[1].replacements, contains('STRASSE-TÜR'));
    },
  );
  test(
    'known explicit compounds and URL/email tokens avoid spurious findings',
    () async {
      final OfficeProofingResult result = await provider.check(
        input('Haus-Tür https://example.invalid/Huas test@example.invalid'),
      );
      expect(result.findings, isEmpty);
    },
  );
  test(
    'URL schemes and www prefixes are protected without case folding text',
    () async {
      const String text =
          'HTTPS://example.invalid/Huas WWW.example.invalid/Huas Huas';
      final OfficeProofingResult result = await provider.check(input(text));
      expect(result.findings.single.originalText, 'Huas');
      expect(result.findings.single.start, text.lastIndexOf('Huas'));
      expect(result.findings.single.replacements, contains('Haus'));
    },
  );
  test(
    'matching backtick spans protect code without hiding following prose',
    () async {
      for (final String code in <String>[
        '`Huas`',
        '``Huas ` inner``',
        '```dart\nHuas\n```',
        '`HTTPS://example.invalid/Huas Huas`',
      ]) {
        final String text = '🙂 $code Huas';
        final OfficeProofingReport report =
            await OfficeProofingService(
              providers: <OfficeProofingProvider>[provider],
            ).check(
              OfficeProofingRequest(
                documentId: 'doc',
                blockId: 'p',
                revision: 1,
                text: text,
                startOffset: 20,
              ),
            );
        expect(report.complete, isTrue, reason: code);
        expect(report.findings, hasLength(1), reason: code);
        expect(report.findings.single.originalText, 'Huas');
        expect(report.findings.single.start, 20 + text.lastIndexOf('Huas'));
        expect(report.findings.single.replacements, contains('Haus'));
      }
    },
  );
  test(
    'unmatched backtick delimiters do not suppress the remaining paragraph',
    () async {
      for (final String text in <String>['`Huas', '``Huas`', '```Huas``']) {
        final OfficeProofingResult result = await provider.check(input(text));
        expect(result.findings.single.originalText, 'Huas', reason: text);
      }
    },
  );
  test(
    'personal words and ignores stay owned, reversible and language-scoped',
    () async {
      provider.vocabulary.addWord('Qudsmarke', language: 'de-CH');
      expect((await provider.check(input('Qudsmarke'))).findings, hasLength(1));
      expect(
        (await provider.check(input('Qudsmarke', language: 'de-CH'))).findings,
        isEmpty,
      );
      provider.vocabulary.ignoreWord('Qudsmarke');
      expect((await provider.check(input('Qudsmarke'))).findings, isEmpty);
      provider.vocabulary.unignoreWord('Qudsmarke');
      expect((await provider.check(input('Qudsmarke'))).findings, hasLength(1));
      provider.vocabulary.addWord('Qudsmarke');
      provider.vocabulary.removeWord('Qudsmarke');
      expect((await provider.check(input('Qudsmarke'))).findings, hasLength(1));
    },
  );
  test('vocabulary snapshots round-trip with revision notification', () {
    int changed = 0;
    final OfficeProofingVocabulary vocabulary = OfficeProofingVocabulary(
      ownerId: 'profile-a',
      onChanged: () {
        changed++;
      },
    );
    vocabulary.addWord('Qudsmarke');
    vocabulary.addWord('Qudsmarke');
    vocabulary.ignoreWord('Fachname', language: 'de-AT');
    expect(changed, 2);
    expect(vocabulary.revision, 2);
    final OfficeProofingVocabulary restored = OfficeProofingVocabulary.fromJson(
      jsonDecode(jsonEncode(vocabulary.toJson())) as Map<String, Object?>,
    );
    expect(restored.ownerId, 'profile-a');
    expect(restored.contains('Qudsmarke'), isTrue);
    expect(restored.contains('Fachname', language: 'de-AT'), isTrue);
    restored.clearIgnoredWords();
    expect(restored.contains('Fachname', language: 'de-AT'), isFalse);
    expect(() => restored.wordsFor('de-DE').add('bad'), throwsUnsupportedError);
  });
  test('vocabulary parser rejects corrupt or mismatched data', () {
    expect(
      () => OfficeProofingVocabulary.fromJson(<String, Object?>{
        'schemaVersion': 99,
      }),
      throwsFormatException,
    );
    expect(
      () => OfficeProofingVocabulary.fromJson(<String, Object?>{
        'schemaVersion': 1,
        'ownerId': 'local',
        'words': <String, Object?>{
          'de-DE': <Object?>[3],
        },
        'ignoredWords': <String, Object?>{},
      }),
      throwsFormatException,
    );
  });
  test('suggestions and long unknown tokens remain bounded', () async {
    final GermanSpellingProvider bounded = GermanSpellingProvider(
      maximumSuggestions: 2,
      maximumCandidateChecks: 1000,
    );
    final OfficeProofingResult result = await bounded.check(
      input('Huas ${'x' * 100}'),
    );
    expect(result.findings, hasLength(2));
    expect(result.findings.first.replacements.length, lessThanOrEqualTo(2));
    expect(result.findings.last.replacements, isEmpty);
    await bounded.dispose();
  });
}

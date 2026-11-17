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
  test('basic noun supplement preserves ordinary inflected forms', () async {
    const String text =
        'Band Junge Jungen Glaube Glauben Glaubens '
        'Amt Amtes Amts Ämter Ämtern Vogel Vögel Vögeln';
    for (final String language in <String>['de-DE', 'de-AT', 'de-CH']) {
      final OfficeProofingResult result = await provider.check(
        input(text, language: language),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isEmpty, reason: language);
    }
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

  test(
    'combined keyboard transliterations offer dictionary-backed words',
    () async {
      const Map<String, String> cases = <String, String>{
        'uebermaessig': 'übermäßig',
        'aeusserst': 'äußerst',
        'Aeusserung': 'Äußerung',
        'grosszuegig': 'großzügig',
        'Abenteuerbuecher': 'Abenteuerbücher',
        'UEBERMAESSIG': 'ÜBERMÄSSIG',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        final OfficeProofingResult result = await provider.check(
          input(entry.key),
        );
        expect(result.findings, hasLength(1), reason: entry.key);
        expect(result.findings.single.replacements, contains(entry.value));
        expect(
          result.findings.single.replacements.length,
          lessThanOrEqualTo(5),
        );
        expect((await provider.check(input(entry.value))).findings, isEmpty);
      }
    },
  );

  test(
    'combined orthography respects Swiss spelling and source capitals',
    () async {
      const Map<String, String> cases = <String, String>{
        'uebermaessig': 'übermässig',
        'Uebermäßig': 'Übermässig',
        'UEBERMÄẞIG': 'ÜBERMÄSSIG',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        final OfficeProofingResult result = await provider.check(
          input(entry.key, language: 'de-CH'),
        );
        expect(result.findings.single.replacements, contains(entry.value));
        expect(
          result.findings.single.replacements.any(
            (String value) => value.contains('ß') || value.contains('ẞ'),
          ),
          isFalse,
        );
        expect(
          (await provider.check(
            input(entry.value, language: 'de-CH'),
          )).findings,
          isEmpty,
        );
      }
    },
  );

  test(
    'orthographic suggestions share the configured search and result caps',
    () async {
      final GermanSpellingProvider bounded = GermanSpellingProvider(
        maximumSuggestions: 1,
        maximumCandidateChecks: 16,
      );
      addTearDown(bounded.dispose);
      expect(
        (await bounded.check(
          input('uebermaessig'),
        )).findings.single.replacements,
        <String>['übermäßig'],
      );
      final GermanSpellingProvider minimal = GermanSpellingProvider(
        maximumSuggestions: 1,
        maximumCandidateChecks: 1,
      );
      addTearDown(minimal.dispose);
      expect(
        (await minimal.check(
          input('uebermaessig'),
        )).findings.single.replacements,
        isEmpty,
      );
      final GermanSpellingProvider noSuggestions = GermanSpellingProvider(
        maximumSuggestions: 0,
      );
      addTearDown(noSuggestions.dispose);
      expect(
        (await noSuggestions.check(
          input('uebermaessig'),
        )).findings.single.replacements,
        isEmpty,
      );
    },
  );

  test(
    'suggestion cache preserves sentence-initial adjective capitals',
    () async {
      const String text = 'Schönn ist es, aber Schönn ist es nicht.';
      final OfficeProofingResult result = await provider.check(input(text));
      expect(result.findings, hasLength(2));
      expect(result.findings.first.originalText, 'Schönn');
      expect(result.findings.first.replacements, contains('Schön'));
      expect(result.findings.last.replacements, contains('schön'));
      expect(result.findings.last.replacements, isNot(contains('Schön')));
    },
  );

  test(
    'personal words compose explicit compounds in their declared locale',
    () async {
      provider.vocabulary.addWord('Qudsmarke');
      for (final String text in <String>[
        'Qudsmarke-Tür',
        'Haus-Qudsmarke-Tür',
        'Qudsmarke\u2011Tür',
        'Qud\u00adsmarke-Tür',
      ]) {
        expect(
          (await provider.check(input(text))).findings,
          isEmpty,
          reason: text,
        );
      }
      for (final String text in <String>[
        'qudsmarke-Tür',
        'Qudsmarkehaus-Tür',
      ]) {
        expect((await provider.check(input(text))).findings, hasLength(1));
      }
      expect(
        (await provider.check(
          input('Qudsmarke-Tür', language: 'de-CH'),
        )).findings,
        hasLength(1),
      );
      provider.vocabulary.removeWord('Qudsmarke');
      expect(
        (await provider.check(input('Qudsmarke-Tür'))).findings,
        hasLength(1),
      );
    },
  );

  test(
    'compound correction preserves personal components and source ranges',
    () async {
      provider.vocabulary.addWord('Qudsmarke');
      const String text = '🙂 Qudsmarke-Huas Qudsmarke\u2011Huas';
      final OfficeProofingResult result = await provider.check(
        OfficeProofingRequest(
          documentId: 'doc',
          blockId: 'p',
          revision: 4,
          startOffset: 20,
          text: text,
        ),
      );
      expect(result.findings, hasLength(2));
      expect(result.findings.first.start, 23);
      expect(result.findings.first.originalText, 'Qudsmarke-Huas');
      expect(result.findings.first.replacements, contains('Qudsmarke-Haus'));
      expect(
        result.findings.last.replacements,
        contains('Qudsmarke\u2011Haus'),
      );
      expect(result.findings.last.end, 20 + text.length);
      final OfficeProofingResult twoErrors = await provider.check(
        input('Qudsmarke-Huas-Türr'),
      );
      expect(twoErrors.findings.single.replacements, isEmpty);
    },
  );

  test(
    'ignored tokens do not turn into declared compound vocabulary',
    () async {
      provider.vocabulary.ignoreWord('Qudsmarke');
      expect((await provider.check(input('Qudsmarke'))).findings, isEmpty);
      expect(
        (await provider.check(input('Qudsmarke-Tür'))).findings,
        hasLength(1),
      );
      provider.vocabulary.ignoreWord('Qudsmarke-Tür');
      expect((await provider.check(input('Qudsmarke-Tür'))).findings, isEmpty);
    },
  );

  test('a vocabulary edit invalidates an in-flight compound check', () async {
    await provider.warmUp();
    final Future<OfficeProofingResult> pending = provider.check(
      input('Qudsmarke-Tür'),
    );
    provider.vocabulary.addWord('Qudsmarke');
    final OfficeProofingResult stale = await pending;
    expect(stale.status, OfficeProofingStatus.failed);
    expect(stale.findings, isEmpty);
    expect((await provider.check(input('Qudsmarke-Tür'))).findings, isEmpty);
  });

  test(
    'identifier fragments are protected while separate prose is checked',
    () async {
      const String text =
          'Huas42 42Huas Huas_name Huas\u203fFeler Huas𝟘 𝟘Huas 30 Huas 20';
      final OfficeProofingResult result = await provider.check(input(text));
      expect(result.findings, hasLength(1));
      expect(result.findings.single.originalText, 'Huas');
      expect(result.findings.single.start, text.lastIndexOf('Huas'));
      expect(result.findings.single.replacements, contains('Haus'));
    },
  );

  test(
    'Unicode email and delimited URLs preserve following spelling checks',
    () async {
      const String text =
          'Jörg@beispiel.invalid (https://example.invalid/(Huas)). Huas';
      final OfficeProofingResult result = await provider.check(input(text));
      expect(result.findings, hasLength(1));
      expect(result.findings.single.start, text.lastIndexOf('Huas'));
      expect(result.findings.single.replacements, contains('Haus'));
    },
  );

  test(
    'vocabulary restore merges aliases and canonicalizes like live edits',
    () {
      final OfficeProofingVocabulary restored =
          OfficeProofingVocabulary.fromJson(<String, Object?>{
            'schemaVersion': 1,
            'ownerId': 'profile-a',
            'words': <String, Object?>{
              'de': <String>[' Qud\u00adsmarke ', 'A\u0308rger'],
              'de_DE': <String>['Fachwort'],
              'DE-de': <String>['Zweitwort', 'Ärger'],
              'de-CH': <String>['Schweizwort'],
              'en': <String>['EnglishBrand'],
              'en_US': <String>['SecondBrand'],
            },
            'ignoredWords': <String, Object?>{
              'de': <String>['Erstwort'],
              'de_DE': <String>[' Zweitwort '],
            },
          });
      expect(restored.wordsFor('de-DE'), <String>{
        'Qudsmarke',
        'Ärger',
        'Fachwort',
        'Zweitwort',
      });
      expect(restored.ignoredWordsFor('de'), <String>{'Erstwort', 'Zweitwort'});
      expect(restored.wordsFor('de-CH'), <String>{'Schweizwort'});
      expect(restored.wordsFor('en-US'), <String>{
        'EnglishBrand',
        'SecondBrand',
      });
      expect(restored.revision, 0);
      restored.addWord('\u00ad Qudsmarke \u00ad');
      expect(restored.revision, 0);
      restored.removeWord(' Qudsmarke ');
      expect(restored.contains('Qudsmarke'), isFalse);
      final OfficeProofingVocabulary roundTrip =
          OfficeProofingVocabulary.fromJson(
            jsonDecode(jsonEncode(restored.toJson())) as Map<String, Object?>,
          );
      expect(roundTrip.toJson(), restored.toJson());
    },
  );

  test(
    'vocabulary restore rejects empty normalized words and empty languages',
    () {
      for (final String field in <String>['words', 'ignoredWords']) {
        for (final String word in <String>[
          '\u00ad',
          '\u00ad \u00ad',
          '\n\u00ad\t',
        ]) {
          final Map<String, Object?> snapshot = <String, Object?>{
            'schemaVersion': 1,
            'ownerId': 'local',
            'words': <String, Object?>{},
            'ignoredWords': <String, Object?>{},
            field: <String, Object?>{
              'de-DE': <String>[word],
            },
          };
          expect(
            () => OfficeProofingVocabulary.fromJson(snapshot),
            throwsFormatException,
          );
        }
      }
      expect(
        () => OfficeProofingVocabulary.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'ownerId': 'local',
          'words': <String, Object?>{
            '  ': <String>['Haus'],
          },
          'ignoredWords': <String, Object?>{},
        }),
        throwsFormatException,
      );
      final OfficeProofingVocabulary vocabulary = OfficeProofingVocabulary();
      expect(() => vocabulary.addWord('\u00ad \u00ad'), throwsArgumentError);
      expect(
        () => vocabulary.addWord('Haus', language: ' '),
        throwsArgumentError,
      );
    },
  );
}

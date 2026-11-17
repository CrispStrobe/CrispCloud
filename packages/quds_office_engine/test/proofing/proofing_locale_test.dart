import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  const Map<String, String> aliases = <String, String>{
    'de': 'de-DE',
    'de-1996': 'de-DE',
    'de-DE-1996': 'de-DE',
    'de-Latn': 'de-DE',
    'de-Latn-DE-1996': 'de-DE',
    ' DE_latn_AT_1996 ': 'de-AT',
    'de-Latn-CH-1996': 'de-CH',
    'de-DE-u-co-phonebk': 'de-DE',
    'de-Latn-CH-u-co-phonebk-nu-latn': 'de-CH',
    'en': 'en-US',
    'en-Latn': 'en-US',
    'EN_latn_US': 'en-US',
    'en-Latn-GB': 'en-GB',
    'en-GB-u-nu-latn': 'en-GB',
    'en-AU-u-ca-gregory': 'en-AU',
  };
  test('proofing aliases retain region and modern orthography', () {
    for (final MapEntry<String, String> alias in aliases.entries) {
      expect(
        normalizeProofingLanguage(alias.key),
        alias.value,
        reason: alias.key,
      );
      expect(normalizeProofingLanguage(alias.value), alias.value);
      final OfficeProofingRequest request = OfficeProofingRequest(
        documentId: 'd',
        blockId: 'p',
        revision: 1,
        text: 'Text',
        language: alias.key,
      );
      expect(request.language, alias.value);
    }
  });

  test('hyphenators use the same aliases without adding dialect promises', () {
    for (final MapEntry<String, String> alias in aliases.entries) {
      final String word = alias.value.startsWith('de-')
          ? 'Silbentrennung'
          : 'dictionary';
      expect(
        OfficeHyphenator.wordOffsets(word, language: alias.key),
        OfficeHyphenator.wordOffsets(word, language: alias.value),
        reason: alias.key,
      );
      expect(
        OfficeHyphenator.supports(alias.key),
        OfficeHyphenator.supports(alias.value),
        reason: alias.key,
      );
    }
    expect(OfficeHyphenator.supports('en-Latn-AU'), isFalse);
    expect(OfficeHyphenator.supports('en-Latn-CA'), isFalse);
    expect(OfficeHyphenator.supports('en-Latn-IN'), isFalse);
  });

  test('equivalent locale tags across styled runs retain word candidates', () {
    for (final (String word, String left, String right)
        in <(String, String, String)>[
          ('dictionary', 'en-Latn-GB', 'en-GB-u-nu-latn'),
          ('dictionary', 'en-Latn', 'en-US'),
          ('Silbentrennung', 'de-Latn-DE-1996', 'de'),
          ('Silbentrennung', 'de-Latn-CH', 'de-CH-u-co-phonebk'),
        ]) {
      expect(
        OfficeHyphenator.breakOffsets(
          word,
          languageAt: (int offset) => offset < 4 ? left : right,
        ),
        OfficeHyphenator.wordOffsets(word, language: left),
      );
    }
    expect(
      OfficeHyphenator.breakOffsets(
        'dictionary',
        languageAt: (int offset) => offset < 4 ? 'en-Latn-US' : 'en-Latn-GB',
      ),
      isEmpty,
    );
  });

  test(
    'historical orthography, other scripts and invalid tags remain unsupported',
    () {
      final GermanSpellingProvider spelling = GermanSpellingProvider();
      final GermanWritingRulesProvider grammar = GermanWritingRulesProvider();
      for (final String tag in <String>[
        'de-1901',
        'de-DE-1901',
        'de-Latn-DE-1901',
        'de-Cyrl-DE',
        'de-CH-unknown',
        'de-DE-x-private',
        'de-DD',
        'de--DE',
        'de-DE-u',
        'de-DE-u-12',
        'de-DE-u-co-phonebk-co-dict',
        'de-DE-u-attr-attr',
        'de-DE-u-co-phonebk-x-private',
      ]) {
        expect(spelling.supportsLanguage(tag), isFalse, reason: tag);
        expect(grammar.supportsLanguage(tag), isFalse, reason: tag);
        expect(OfficeHyphenator.supports(tag), isFalse, reason: tag);
      }
      for (final String tag in <String>[
        'en-Cyrl-US',
        'en-NZ',
        'en-ZZ',
        'en-US-1901',
        'en-GB-oxendict',
        'en-US-u',
        'en-US-u-12',
        'en-US-x-private',
        'en--US',
      ]) {
        expect(OfficeHyphenator.supports(tag), isFalse, reason: tag);
      }
    },
  );

  test(
    'vocabulary aliases share their region without losing snapshot terms',
    () {
      final OfficeProofingVocabulary words = OfficeProofingVocabulary.fromJson(
        <String, Object?>{
          'schemaVersion': 1,
          'ownerId': 'locale-owner',
          'words': <String, Object?>{
            'de-DE': <String>['QudsMarke'],
            'de-Latn-DE-1996': <String>['QudsCloud'],
            'en-Latn-GB-u-nu-latn': <String>['QudsOffice'],
          },
          'ignoredWords': <String, Object?>{},
        },
      );
      expect(words.wordsFor('de-1996'), <String>{'QudsMarke', 'QudsCloud'});
      expect(words.contains('QudsCloud', language: 'de-CH'), isFalse);
      expect(words.contains('QudsOffice', language: 'en-GB'), isTrue);
      expect(words.contains('QudsOffice', language: 'en-US'), isFalse);
    },
  );

  test(
    'modern German aliases run spelling and preserve Swiss sharp-s policy',
    () async {
      final GermanSpellingProvider provider = GermanSpellingProvider();
      addTearDown(provider.dispose);
      Future<OfficeProofingResult> check(String language) => provider.check(
        OfficeProofingRequest(
          documentId: 'd',
          blockId: 'p',
          revision: 1,
          text: 'Straße',
          language: language,
        ),
      );
      for (final String tag in <String>[
        'de-1996',
        'de-Latn-DE-1996',
        'de-AT-u-co-phonebk',
      ]) {
        final OfficeProofingResult result = await check(tag);
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty);
      }
      final OfficeProofingResult swiss = await check(
        'de-Latn-CH-1996-u-co-phonebk',
      );
      expect(swiss.status, OfficeProofingStatus.success);
      expect(swiss.findings.single.replacements, contains('Strasse'));
    },
  );
}

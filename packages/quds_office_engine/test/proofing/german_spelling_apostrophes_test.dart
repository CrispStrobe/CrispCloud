import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest input(String text, {String language = 'de-DE'}) =>
    OfficeProofingRequest(
      documentId: 'apostrophe-document',
      blockId: 'paragraph',
      revision: 1,
      startOffset: 20,
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

  test(
    'typographic apostrophes share exact dictionary word knowledge',
    () async {
      for (final language in ['de-DE', 'de-AT', 'de-CH']) {
        final result = await provider.check(
          input("Er darf's. Er darf’s.", language: language),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty, reason: language);
        expect(
          await provider.isKnownWord('darf’s', language: language),
          isTrue,
        );
      }
    },
  );

  test('apostrophe comparison retains ordinary lexical case rules', () async {
    expect(await provider.isKnownWord('Darf’s'), isFalse);
    expect(await provider.isKnownWord('Darf’s', sentenceInitial: true), isTrue);
    expect(await provider.isKnownWord('DARF’S'), isTrue);
    final result = await provider.check(input('Draf’s sein?'));
    expect(result.findings.single.replacements, contains('Darf’s'));
  });

  test(
    'cached corrections preserve each occurrence and source offsets',
    () async {
      const text = "🙂 Gru\u0308ße draf's draf’s";
      final result = await provider.check(input(text));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, hasLength(2));
      expect(result.findings[0].originalText, "draf's");
      expect(result.findings[0].replacements, contains("darf's"));
      expect(result.findings[1].originalText, 'draf’s');
      expect(result.findings[1].replacements, contains('darf’s'));
      expect(result.findings[0].start, 20 + text.indexOf("draf's"));
      expect(result.findings[1].start, 20 + text.indexOf('draf’s'));
      expect(result.findings[1].end, 20 + text.length);
      for (final finding in result.findings) {
        expect(finding.replacements.length, lessThanOrEqualTo(5));
      }
    },
  );

  test('personal apostrophes remain reversible and locale scoped', () async {
    provider.vocabulary.addWord('O’Connor', language: 'de-CH');
    for (final name in ["O'Connor", 'O’Connor']) {
      expect(
        (await provider.check(input(name, language: 'de-CH'))).findings,
        isEmpty,
      );
      expect(await provider.isKnownWord(name, language: 'de-CH'), isTrue);
      expect((await provider.check(input(name))).findings, hasLength(1));
    }
    expect(
      (await provider.check(input('o’connor', language: 'de-CH'))).findings,
      hasLength(1),
    );
    final restored = OfficeProofingVocabulary.fromJson(
      provider.vocabulary.toJson(),
    );
    expect(restored.contains("O'Connor", language: 'de-CH'), isTrue);
    restored.removeWord("O'Connor", language: 'de-CH');
    expect(restored.contains('O’Connor', language: 'de-CH'), isFalse);
    provider.vocabulary.ignoreWord('Quds’typo');
    expect((await provider.check(input("Quds'typo"))).findings, isEmpty);
    provider.vocabulary.unignoreWord("Quds'typo");
    expect((await provider.check(input('Quds’typo'))).findings, hasLength(1));
  });

  test(
    'compound repairs preserve independent apostrophe and hyphen styles',
    () async {
      provider.vocabulary.addWord("O'Connor");
      const text = '🙂 O’Connor\u2011Huas';
      final result = await provider.check(input(text));
      final finding = result.findings.single;
      expect(finding.originalText, 'O’Connor\u2011Huas');
      expect(finding.start, 23);
      expect(finding.end, 20 + text.length);
      expect(finding.replacements, contains('O’Connor\u2011Haus'));
    },
  );

  test(
    'each apostrophe retains its source style in personal corrections',
    () async {
      provider.vocabulary.addWord("Quds'Brand's");
      final result = await provider.check(input("Quds'Brnad’s"));
      expect(result.findings.single.replacements, contains("Quds'Brand’s"));
    },
  );

  test(
    'apostrophes are not removed or generalized from arbitrary words',
    () async {
      for (final word in ['dar’fs', 'Hau’s', 'Ha’us']) {
        expect(await provider.isKnownWord(word), isFalse, reason: word);
        expect((await provider.check(input(word))).findings, hasLength(1));
      }
      expect(normalizeGermanWord('’darf’'), '’darf’');
      expect(normalizeGermanWord('darf‘s'), 'darf‘s');
    },
  );

  test(
    'quoted typo remains checkable without consuming the quotation marks',
    () async {
      const text = '🙂 „draf’s“';
      final result = await provider.check(input(text));
      final finding = result.findings.single;
      expect(finding.originalText, 'draf’s');
      expect(finding.start, 20 + text.indexOf('draf’s'));
      expect(finding.end, 20 + text.indexOf('“'));
      expect(finding.replacements, contains('darf’s'));
    },
  );

  test('apostrophe corrections obey disabled suggestions', () async {
    final noSuggestions = GermanSpellingProvider(maximumSuggestions: 0);
    addTearDown(noSuggestions.dispose);
    expect(
      (await noSuggestions.check(input('draf’s'))).findings.single.replacements,
      isEmpty,
    );
  });
}

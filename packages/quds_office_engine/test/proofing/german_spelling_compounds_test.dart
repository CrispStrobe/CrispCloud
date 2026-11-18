import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest input(String text, {String language = 'de-DE'}) =>
    OfficeProofingRequest(
      documentId: 'compound-document',
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
    'multiple component typos receive a complete dictionary-backed repair',
    () async {
      for (final text in ['Huas-Türr', 'Huas-Türr-Huas']) {
        final result = await provider.check(input(text));
        expect(result.status, OfficeProofingStatus.success);
        final finding = result.findings.single;
        expect(finding.originalText, text);
        expect(finding.replacements, isNotEmpty);
        expect(
          finding.replacements.first,
          text.replaceAll('Huas', 'Haus').replaceAll('Türr', 'Tür'),
        );
        expect(finding.replacements.length, lessThanOrEqualTo(5));
        for (final replacement in finding.replacements) {
          expect(await provider.isKnownWord(replacement), isTrue);
        }
      }
    },
  );

  test(
    'known middle components and all-capitals retain their authored case',
    () async {
      for (final entry in <String, String>{
        'Huas-Tür-Huas': 'Haus-Tür-Haus',
        'HUAS-TÜRR': 'HAUS-TÜR',
        'Huas-Türr-Haus': 'Haus-Tür-Haus',
      }.entries) {
        final finding = (await provider.check(
          input(entry.key),
        )).findings.single;
        expect(finding.replacements, contains(entry.value));
      }
    },
  );

  test(
    'cached compound repairs retain separators and original UTF-16 ranges',
    () async {
      const text = '🙂 Huas-Türr Huas\u2010Türr Huas\u2011Türr';
      final result = await provider.check(input(text));
      expect(result.findings, hasLength(3));
      for (final (index, separator) in ['-', '\u2010', '\u2011'].indexed) {
        final original = 'Huas${separator}Türr';
        final finding = result.findings[index];
        expect(finding.originalText, original);
        expect(finding.start, 20 + text.indexOf(original));
        expect(finding.end, finding.start + original.length);
        expect(finding.replacements, isNotEmpty);
        expect(finding.replacements.first, 'Haus${separator}Tür');
      }
    },
  );

  test(
    'multiple repairs respect Swiss and standard spelling independently',
    () async {
      for (final (source, expected, language) in [
        ('Straße-Huas', 'Strasse-Haus', 'de-CH'),
        ('Strasse-Huas', 'Straße-Haus', 'de-DE'),
        ('STRAẞE-HUAS', 'STRASSE-HAUS', 'de-CH'),
        ('Huas-Türr', 'Haus-Tür', 'de-AT'),
      ]) {
        final finding = (await provider.check(
          input(source, language: language),
        )).findings.single;
        expect(finding.replacements, isNotEmpty);
        expect(finding.replacements.first, expected);
        for (final replacement in finding.replacements) {
          expect(
            await provider.isKnownWord(replacement, language: language),
            isTrue,
          );
        }
      }
    },
  );

  test(
    'declared known components survive several other component repairs',
    () async {
      provider.vocabulary.addWord('Qudsmarke');
      final result = await provider.check(input('Qudsmarke-Huas-Türr'));
      expect(result.findings.single.replacements, isNotEmpty);
      expect(result.findings.single.replacements.first, 'Qudsmarke-Haus-Tür');
      expect(
        (await provider.check(
          input('Qudsmarke-Huas-Türr', language: 'de-CH'),
        )).findings.single.replacements,
        isEmpty,
      );
    },
  );

  test(
    'complete personal compounds do not require declared components',
    () async {
      provider.vocabulary.addWord('Quds-Brand');
      expect(await provider.isKnownWord('Quds'), isFalse);
      for (final source in ['Quds-Brnad', 'Qdus-Brnad']) {
        final finding = (await provider.check(input(source))).findings.single;
        expect(finding.replacements, contains('Quds-Brand'));
      }
      expect(
        (await provider.check(
          input('Qdus-Brnad', language: 'de-CH'),
        )).findings.single.replacements,
        isNot(contains('Quds-Brand')),
      );
    },
  );

  test(
    'whole-word dictionary corrections can remove an erroneous separator',
    () async {
      for (final entry in <String, String>{
        'Make-up': 'Makeup',
        'Make\u2011up': 'Makeup',
        'Arbeits-zimmer': 'Arbeitszimmer',
        'Regierungs-zeit': 'Regierungszeit',
        'Bür-ger': 'Bürger',
        'On-line': 'Online',
      }.entries) {
        final result = await provider.check(input(entry.key));
        expect(
          result.findings.single.replacements,
          contains(entry.value),
          reason: entry.key,
        );
        expect(await provider.isKnownWord(entry.value), isTrue);
      }
      provider.vocabulary.addWord('QudsBrand');
      expect(
        (await provider.check(
          input('Quds-Brnad'),
        )).findings.single.replacements,
        contains('QudsBrand'),
      );
    },
  );

  test(
    'ignored unknown constituents cannot validate a partial compound repair',
    () async {
      provider.vocabulary.ignoreWord('Xqyzqyz');
      final result = await provider.check(input('Huas-Xqyzqyz'));
      expect(result.findings.single.replacements, isEmpty);
      expect(await provider.isKnownWord('Haus-Xqyzqyz'), isFalse);
    },
  );

  test(
    'suggestion limits and one shared small search budget remain bounded',
    () async {
      final one = GermanSpellingProvider(maximumSuggestions: 1);
      final tiny = GermanSpellingProvider(
        maximumSuggestions: 1,
        maximumCandidateChecks: 1,
      );
      final none = GermanSpellingProvider(maximumSuggestions: 0);
      addTearDown(one.dispose);
      addTearDown(tiny.dispose);
      addTearDown(none.dispose);
      expect(
        (await one.check(input('Huas-Türr'))).findings.single.replacements,
        ['Haus-Tür'],
      );
      expect(
        (await tiny.check(input('Huas-Türr'))).findings.single.replacements,
        isEmpty,
      );
      expect(
        (await none.check(input('Huas-Türr'))).findings.single.replacements,
        isEmpty,
      );
    },
  );

  test(
    'compound work remains bounded by component count and token length',
    () async {
      final eight = List.filled(8, 'Huas').join('-');
      final result = await provider.check(input(eight));
      expect(result.findings.single.replacements, isNotEmpty);
      expect(
        result.findings.single.replacements.first,
        List.filled(8, 'Haus').join('-'),
      );
      for (final source in [
        List.filled(9, 'Huas').join('-'),
        '${'x' * 65}-Huas',
      ]) {
        final finding = (await provider.check(input(source))).findings.single;
        expect(finding.replacements, isEmpty);
      }
    },
  );

  test(
    'separate punctuation and protected tokens do not become compounds',
    () async {
      const text = '`Huas-Türr` https://example.invalid/Huas-Türr Huas--Türr';
      final result = await provider.check(input(text));
      expect(result.findings.map((finding) => finding.originalText), [
        'Huas',
        'Türr',
      ]);
      expect(
        result.findings.expand((finding) => finding.replacements),
        isNot(contains('Haus-Tür')),
      );
    },
  );
}

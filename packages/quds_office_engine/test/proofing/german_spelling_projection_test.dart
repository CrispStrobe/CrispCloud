import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(String text, {String language = 'de-DE'}) =>
    OfficeProofingRequest(
      documentId: 'german-spelling-projection',
      blockId: 'paragraph',
      revision: 1,
      startOffset: 29,
      text: text,
      language: language,
    );

void main() {
  late GermanSpellingProvider provider;
  setUp(() => provider = GermanSpellingProvider());
  tearDown(() => provider.dispose());

  const decomposedNames =
      'Joe\u0308l Citroe\u0308n Bronte\u0308 Danae\u0308 '
      'S\u030ckoda S\u030ckodas';
  for (final language in ['de-DE', 'de-AT', 'de-CH']) {
    test('decomposed shipped names stay known in $language', () async {
      final result = await provider.check(
        _request(decomposedNames, language: language),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isEmpty);
      for (final word in decomposedNames.split(' ')) {
        expect(await provider.isKnownWord(word, language: language), isTrue);
      }
    });
  }

  test('decomposed names retain uppercase dictionary acceptance', () async {
    final result = await provider.check(
      _request('JOE\u0308L CITROE\u0308N S\u030cKODA S\u030cKODAS'),
    );
    expect(result.findings, isEmpty);
  });

  test('soft hyphens do not interrupt canonical accent composition', () async {
    final result = await provider.check(
      _request('Ha\u00ad\u0308user Gru\u00ad\u0308ße Joe\u00ad\u0308l'),
    );
    expect(result.findings, isEmpty);
    expect(await provider.isKnownWord('Ha\u00ad\u0308user'), isTrue);
  });

  test('canonical comparison preserves case and additional marks', () async {
    final result = await provider.check(
      _request('hier joe\u0308l s\u030ckoda Joe\u0308\u0301l'),
    );
    expect(result.findings.map((finding) => finding.originalText), [
      'joe\u0308l',
      's\u030ckoda',
      'Joe\u0308\u0301l',
    ]);
    expect(result.findings[0].replacements, contains('Joël'));
    expect(result.findings[1].replacements, contains('Škoda'));
    expect(await provider.isKnownWord('Joe\u0308\u0301l'), isFalse);
  });

  test('unknown decomposed words retain exact source ranges', () async {
    const text = '🙂 Joe\u0308ll S\u030ckodaa';
    final result = await provider.check(_request(text));
    expect(result.findings, hasLength(2));
    expect(result.findings.first.replacements, contains('Joël'));
    expect(result.findings.last.replacements, contains('Škoda'));
    expect(result.findings.first.start, 32);
    expect(result.findings.last.end, 29 + text.length);
    for (final finding in result.findings) {
      expect(
        text.substring(finding.start - 29, finding.end - 29),
        finding.originalText,
      );
    }
  });

  test('decomposed compounds retain their authored hyphen style', () async {
    const text = '🙂 Joe\u0308l\u2011Huas';
    final finding = (await provider.check(_request(text))).findings.single;
    expect(finding.originalText, 'Joe\u0308l\u2011Huas');
    expect(finding.start, 32);
    expect(finding.end, 29 + text.length);
    expect(finding.replacements, contains('Joël\u2011Haus'));
  });

  test('personal canonical aliases share one reversible membership', () {
    final vocabulary = OfficeProofingVocabulary(ownerId: 'alice');
    vocabulary.addWord('QudsJoël');
    vocabulary.addWord('QudsJoe\u0308l');
    expect(vocabulary.revision, 1);
    expect(vocabulary.wordsFor('de-DE'), {'QudsJoël'});
    expect(vocabulary.contains('QudsJoe\u0308l'), isTrue);
    expect(vocabulary.contains('QudsJoe\u0308l', language: 'de-CH'), isFalse);
    expect(vocabulary.contains('qudsjoe\u0308l'), isFalse);
    expect(
      OfficeProofingVocabulary(ownerId: 'bob').contains('QudsJoël'),
      isFalse,
    );
    vocabulary.removeWord('QudsJoe\u0308l');
    expect(vocabulary.revision, 2);
    expect(vocabulary.contains('QudsJoël'), isFalse);
  });

  test(
    'ignored canonical aliases can be restored in their exact locale',
    () async {
      provider.vocabulary.ignoreWord('QudsŠ', language: 'de-CH');
      expect(
        (await provider.check(
          _request('QudsS\u030c', language: 'de-CH'),
        )).findings,
        isEmpty,
      );
      expect(
        (await provider.check(_request('QudsS\u030c'))).findings,
        hasLength(1),
      );
      provider.vocabulary.unignoreWord('QudsS\u030c', language: 'de-CH');
      expect(
        (await provider.check(
          _request('QudsS\u030c', language: 'de-CH'),
        )).findings,
        hasLength(1),
      );
    },
  );

  test('restored vocabulary unifies canonical aliases and split accents', () {
    final vocabulary = OfficeProofingVocabulary.fromJson({
      'schemaVersion': 1,
      'ownerId': 'alice',
      'words': {
        'de': ['QudsJoël', 'QudsS\u030c'],
        'de_DE': ['QudsJoe\u0308l', 'Qudsa\u00ad\u0308'],
      },
      'ignoredWords': {
        'en': ['QudsE\u0308'],
        'en-US': ['QudsË'],
      },
    });
    expect(vocabulary.wordsFor('de-DE'), {'QudsJoël', 'QudsŠ', 'Qudsä'});
    expect(vocabulary.ignoredWordsFor('en-US'), {'QudsË'});
    expect(vocabulary.revision, 0);
    final restored = OfficeProofingVocabulary.fromJson(
      jsonDecode(jsonEncode(vocabulary.toJson())) as Map<String, Object?>,
    );
    expect(restored.toJson(), vocabulary.toJson());
    expect(restored.ownerId, 'alice');
  });

  test('soft hyphens cannot hide numeric or connector prefixes', () async {
    const text = '42\u00adHuas _\u00adHuas 𝟘\u0308\u00adHuas Huas';
    final result = await provider.check(_request(text));
    final finding = result.findings.single;
    expect(finding.originalText, 'Huas');
    expect(finding.start, 29 + text.lastIndexOf('Huas'));
    expect(finding.end, 29 + text.length);
    expect(finding.replacements.first, 'Haus');
  });

  test('projection regroups marks and joiners with identifier edges', () async {
    const text =
        '1\u00ad\u0301Huas 𝟘\u00ad\u0308Huas _\u00ad\u0308Huas '
        '1\u00ad\u200dHuas Huas';
    final result = await provider.check(_request(text));
    expect(result.findings.single.start, 29 + text.lastIndexOf('Huas'));
    expect(result.findings.single.replacements.first, 'Haus');
  });

  test('projected identifier edges are not limited by mark count', () async {
    final text = '𝟘\u00ad${'\u0308' * 2048}Huas _${'\u00ad' * 2048}Huas Huas';
    final result = await provider.check(_request(text));
    expect(result.findings.single.start, 29 + text.lastIndexOf('Huas'));
  });

  test('Unicode Prepend characters cannot hide identifier prefixes', () async {
    for (final prefix in [
      '\u06004\u0301',
      '\u{110bd}𝟘\u0308',
      '\u0600_\u0308',
      '\u{110bd}\u203f',
    ]) {
      for (final control in ['', '\u00ad']) {
        final text = '$prefix${control}Huas Huas';
        final result = await provider.check(_request(text));
        expect(result.findings.single.start, 29 + text.lastIndexOf('Huas'));
        expect(result.findings.single.replacements.first, 'Haus');
      }
    }
  });

  test('Unicode Prepend characters cannot hide identifier suffixes', () async {
    for (final suffix in ['\u06004\u0301', '\u{110bd}_\u0308']) {
      for (final control in ['', '\u00ad']) {
        final text = 'Huas$control$suffix Huas';
        final result = await provider.check(_request(text));
        expect(result.findings.single.start, 29 + text.lastIndexOf('Huas'));
      }
    }
  });

  test('soft hyphen identifier suffixes remain protected', () async {
    final result = await provider.check(
      _request('Huas\u00ad42 Huas\u00ad𝟘 Huas\u00ad_\u0308'),
    );
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings, isEmpty);
  });

  test('separated prose and marked punctuation remain checkable', () async {
    const text = '1\u00ad Huas _\u00ad. Huas (\u00ad\u0308Huas 🙂 Huas-Türr';
    final result = await provider.check(_request(text));
    expect(result.findings.map((finding) => finding.originalText), [
      'Huas',
      'Huas',
      'Huas',
      'Huas-Türr',
    ]);
    for (final finding in result.findings) {
      expect(
        text.substring(finding.start - 29, finding.end - 29),
        finding.originalText,
      );
    }
    expect(result.findings.last.replacements.first, 'Haus-Tür');
  });

  for (final protected in [
    'ht\u00adtps://example.invalid/Huas',
    'w\u00adww.example.invalid/Huas',
    'Huas@exam\u00adple.invalid',
    'Hu\u00adas@example.invalid',
    '`\u00ad`Huas``',
  ]) {
    test('projected protected text stays intact: $protected', () async {
      final text = '🙂 $protected Huas';
      final result = await provider.check(_request(text));
      final finding = result.findings.single;
      expect(finding.originalText, 'Huas');
      expect(finding.start, 29 + text.lastIndexOf('Huas'));
      expect(finding.replacements.first, 'Haus');
    });
  }

  test('source-only links and backtick spans remain protected', () async {
    for (final protected in ['wWw.\u00ad', '`Huas`\u00ad`']) {
      final text = '🙂 $protected Huas';
      final result = await provider.check(_request(text));
      expect(result.findings.single.start, 29 + text.lastIndexOf('Huas'));
      expect(result.findings.single.replacements.first, 'Haus');
    }
  });

  test('projected joiner boundaries prevent partial grapheme edits', () async {
    for (final joiner in ['\u200d', '\u200c']) {
      final text = 'Huas\u00ad$joiner Huas';
      final result = await provider.check(_request(text));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.start, 29 + text.lastIndexOf('Huas'));
      expect(result.findings.single.replacements.first, 'Haus');
    }
  });
}

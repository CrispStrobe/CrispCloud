import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(
  String text, {
  String language = 'de-DE',
  int startOffset = 0,
}) => OfficeProofingRequest(
  documentId: 'participle-suggestions',
  blockId: 'paragraph',
  revision: 1,
  text: text,
  language: language,
  startOffset: startOffset,
);

void main() {
  late GermanSpellingProvider provider;
  setUp(() => provider = GermanSpellingProvider());
  tearDown(() => provider.dispose());

  Future<OfficeProofingFinding> finding(String text, String word) async {
    final OfficeProofingResult result = await provider.check(_request(text));
    expect(result.status, OfficeProofingStatus.success);
    return result.findings.singleWhere(
      (OfficeProofingFinding value) => value.originalText == word,
    );
  }

  for (final (String, String, String) example in <(String, String, String)>[
    ('Er hat das Buch gelest.', 'gelest', 'gelesen'),
    ('Sie hat den Brief geschreibt.', 'geschreibt', 'geschrieben'),
    ('Wir haben den Fehler gefindet.', 'gefindet', 'gefunden'),
    ('Ich habe den Stift genehmt.', 'genehmt', 'genommen'),
    ('Du hast ihr das Buch gegebt.', 'gegebt', 'gegeben'),
    ('Ihr habt die Suppe geesst.', 'geesst', 'gegessen'),
    ('Sie haben den Tee getrinkt.', 'getrinkt', 'getrunken'),
    ('Er hat den Film geseht.', 'geseht', 'gesehen'),
    ('Ich habe ihm gehelft.', 'gehelft', 'geholfen'),
    ('Du hast mit ihr gesprecht.', 'gesprecht', 'gesprochen'),
    ('Wir haben den Mann getrefft.', 'getrefft', 'getroffen'),
    ('Ihr habt laut geruft.', 'geruft', 'gerufen'),
    ('Sie hat gut geschlaft.', 'geschlaft', 'geschlafen'),
    ('Er hat am Seil gezieht.', 'gezieht', 'gezogen'),
    ('Ich habe den Ball gefangt.', 'gefangt', 'gefangen'),
    ('Du hast das Kind gehaltet.', 'gehaltet', 'gehalten'),
    ('Wir haben den Wagen geladet.', 'geladet', 'geladen'),
    ('Ihr habt ihn gelasst.', 'gelasst', 'gelassen'),
    ('Sie hat das Hemd gewascht.', 'gewascht', 'gewaschen'),
    ('Er hat den Ball gewerft.', 'gewerft', 'geworfen'),
  ]) {
    test('finite perfect preference: ${example.$2}', () async {
      final OfficeProofingFinding value = await finding(example.$1, example.$2);
      expect(value.replacements.first, example.$3);
      expect(value.replacements.length, lessThanOrEqualTo(5));
      expect(await provider.isKnownWord(example.$3), isTrue);
      expect(
        (await provider.check(
          _request(example.$1.replaceFirst(example.$2, example.$3)),
        )).findings.where(
          (OfficeProofingFinding item) => item.originalText == example.$3,
        ),
        isEmpty,
      );
    });
  }

  test('present and past finite auxiliaries keep pronoun agreement', () async {
    for (final String prefix in <String>[
      'Ich habe',
      'Du hast',
      'Er hat',
      'Sie hat',
      'Es hat',
      'Wir haben',
      'Ihr habt',
      'Sie haben',
      'Ich hatte',
      'Du hattest',
      'Er hatte',
      'Wir hatten',
      'Ihr hattet',
      'Sie hatten',
    ]) {
      expect(
        (await finding(
          '$prefix das Buch gelest.',
          'gelest',
        )).replacements.first,
        'gelesen',
        reason: prefix,
      );
    }
  });

  test(
    'finite preferences work in supported locales and direct speech',
    () async {
      for (final String language in <String>['de-DE', 'de-AT', 'de-CH']) {
        final OfficeProofingResult result = await provider.check(
          _request(
            'Er sagte: „Sie hat den Brief geschreibt.“',
            language: language,
          ),
        );
        expect(result.findings.single.originalText, 'geschreibt');
        expect(result.findings.single.replacements.first, 'geschrieben');
      }
    },
  );

  test(
    'already accepted verbs and valid participle alternatives stay accepted',
    () async {
      for (final String text in <String>[
        'Er hat das Buch gelesen.',
        'Sie hat den Brief geschrieben.',
        'Wir haben den Fehler gefunden.',
        'Er beschreibt den Brief.',
        'Sie befindet sich im Haus.',
        'Er hat das Blatt gewendet.',
        'Er hat sich an sie gewandt.',
        'Sie hat den Brief gesendet.',
        'Sie hat den Brief gesandt.',
        'Er hat den Mantel gehängt.',
        'Der Mantel hat dort gehangen.',
        'Sie hat die Arbeit geschafft.',
        'Sie hat das Bild geschaffen.',
        'Er hat das Holz gewachst.',
      ]) {
        final OfficeProofingResult result = await provider.check(
          _request(text),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty, reason: text);
      }
    },
  );

  test(
    'unknown words outside the declared perfect frame keep ordinary ranking',
    () async {
      final List<String> ordinary = (await finding(
        'hier gelest',
        'gelest',
      )).replacements;
      for (final String text in <String>[
        'gelest',
        'Hier steht gelest.',
        'Gestern hat er gelest.',
        'Der Mann hat gelest.',
        'Er ist gelest.',
        'Ich hat gelest.',
        'Er habe gelest.',
        'Er hat gelest gesagt.',
        'Er hat gelest und gesprochen.',
        'Er hat gedacht und gelest.',
        'Er hat gefragt ob sie gelest.',
        'Er hat sie haben gelest.',
        'Er hat sehr sehr sehr sehr sehr sehr sehr sehr sehr gelest.',
        'Er hat ${'sehr ' * 40}gelest.',
        'Er hat${' ' * 200}gelest.',
        'Er hat gelest${' ' * 65}.',
      ]) {
        expect(
          (await finding(text, 'gelest')).replacements,
          ordinary,
          reason: text,
        );
      }
    },
  );

  test('context does not cross clause punctuation or protected text', () async {
    final List<String> ordinary = (await finding(
      'hier gelest',
      'gelest',
    )).replacements;
    for (final String text in <String>[
      'Er hat. gelest.',
      'Er hat! gelest.',
      'Er hat? gelest.',
      'Er hat; gelest.',
      'Er hat: gelest.',
      'Er hat, gelest.',
      'Er hat\ngelest.',
      'Er hat\rgelest.',
      'Er hat (das Buch) gelest.',
      'Er hat „das Buch“ gelest.',
      'Er `hat` das Buch gelest.',
      '`Er hat` das Buch gelest.',
      'Er hat `das Buch` gelest.',
      'Er hat https://example.invalid gelest.',
      'Er hat www.example.invalid gelest.',
      'Er hat name@example.invalid gelest.',
    ]) {
      expect(
        (await finding(text, 'gelest')).replacements,
        ordinary,
        reason: text,
      );
    }
    final OfficeProofingResult protected = await provider.check(
      _request('Er hat das Buch `gelest`.'),
    );
    expect(protected.findings, isEmpty);
  });

  test(
    'cache separates preferred and ordinary occurrences in both orders',
    () async {
      final List<String> ordinary = (await finding(
        'hier gelest',
        'gelest',
      )).replacements;
      for (final bool preferredFirst in <bool>[false, true]) {
        final String text = preferredFirst
            ? 'Er hat gelest. hier gelest.'
            : 'hier gelest. Er hat gelest.';
        final OfficeProofingResult result = await provider.check(
          _request(text),
        );
        expect(result.findings, hasLength(2));
        expect(
          result.findings[preferredFirst ? 0 : 1].replacements.first,
          'gelesen',
        );
        expect(result.findings[preferredFirst ? 1 : 0].replacements, ordinary);
      }
    },
  );

  test(
    'personal and ignored words remain authoritative for their locale',
    () async {
      provider.vocabulary.addWord('gelest', language: 'de-DE');
      provider.vocabulary.ignoreWord('geschreibt', language: 'de-DE');
      const String text = 'Er hat gelest. Sie hat geschreibt.';
      expect((await provider.check(_request(text))).findings, isEmpty);
      final OfficeProofingResult swiss = await provider.check(
        _request(text, language: 'de-CH'),
      );
      expect(swiss.findings, hasLength(2));
      expect(swiss.findings[0].replacements.first, 'gelesen');
      expect(swiss.findings[1].replacements.first, 'geschrieben');
      provider.vocabulary.removeWord('gelest', language: 'de-DE');
      expect((await finding(text, 'gelest')).replacements.first, 'gelesen');
    },
  );

  test('normalization and offsets refer to the original source', () async {
    const String text = '🙂 Text. Er\u00a0hat\tge\u00adlest.';
    final OfficeProofingResult result = await provider.check(
      _request(text, startOffset: 37),
    );
    expect(result.findings, hasLength(1));
    final OfficeProofingFinding value = result.findings.single;
    expect(value.originalText, 'ge\u00adlest');
    expect(value.start, 37 + text.indexOf('ge\u00adlest'));
    expect(value.end, value.start + 'ge\u00adlest'.length);
    expect(value.replacements.first, 'gelesen');
    expect(text, '🙂 Text. Er\u00a0hat\tge\u00adlest.');
  });

  test(
    'all capitals retain case but titlecase names receive ordinary ranking',
    () async {
      expect(
        (await finding('ER HAT GELEST.', 'GELEST')).replacements.first,
        'GELESEN',
      );
      final List<String> ordinary = (await finding(
        'hier Gelest',
        'Gelest',
      )).replacements;
      expect(
        (await finding('Er hat Gelest.', 'Gelest')).replacements,
        ordinary,
      );
    },
  );

  test(
    'candidate budget includes the dictionary-backed preferred candidate',
    () async {
      final GermanSpellingProvider one = GermanSpellingProvider(
        maximumCandidateChecks: 1,
        maximumSuggestions: 1,
      );
      addTearDown(one.dispose);
      final OfficeProofingResult result = await one.check(
        _request('Er hat gelest.'),
      );
      expect(result.findings.single.replacements, <String>['gelesen']);
      final GermanSpellingProvider none = GermanSpellingProvider(
        maximumSuggestions: 0,
      );
      addTearDown(none.dispose);
      expect(
        (await none.check(
          _request('Er hat gelest.'),
        )).findings.single.replacements,
        isEmpty,
      );
    },
  );

  test(
    'fast contextual suggestions still yield and reject cancellation',
    () async {
      await provider.warmUp();
      Future<void> cancel() async {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await provider.dispose();
      }

      final Future<void> cancellation = cancel();
      final OfficeProofingResult result = await provider.check(
        _request('Er hat gelest. Sie hat geschreibt.'),
      );
      await cancellation;
      expect(result.status, OfficeProofingStatus.unavailable);
      expect(result.findings, isEmpty);
    },
  );
}

import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
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

  group('reviewed sein participles', () {
    const examples = <(String, String, String)>[
      ('Er ist nach Hause gegangt.', 'gegangt', 'gegangen'),
      ('Du bist zu uns gekommt.', 'gekommt', 'gekommen'),
      ('Ich bin hier gebleibt.', 'gebleibt', 'geblieben'),
      ('Wir sind nach Berlin gefahrt.', 'gefahrt', 'gefahren'),
      ('Ihr seid nach Berlin gefliegt.', 'gefliegt', 'geflogen'),
      ('Sie ist zum Haus gelauft.', 'gelauft', 'gelaufen'),
      ('Er ist auf den Berg gesteigt.', 'gesteigt', 'gestiegen'),
      ('Es ist ins Wasser gespringt.', 'gespringt', 'gesprungen'),
      ('Sie war im Winter gestirbt.', 'gestirbt', 'gestorben'),
    ];
    for (final example in examples) {
      test('prefers the licensed form for ${example.$2}', () async {
        final value = await finding(example.$1, example.$2);
        expect(value.replacements.first, example.$3);
        expect(value.replacements.length, lessThanOrEqualTo(5));
        expect(await provider.isKnownWord(example.$2), isFalse);
        expect(await provider.isKnownWord(example.$3), isTrue);
        expect(
          (await provider.check(
            _request(example.$1.replaceFirst(example.$2, example.$3)),
          )).findings,
          isEmpty,
        );
      });
    }

    test('requires an agreeing present or past finite sein', () async {
      for (final prefix in [
        'Ich bin',
        'Du bist',
        'Er ist',
        'Sie ist',
        'Es ist',
        'Wir sind',
        'Ihr seid',
        'Sie sind',
        'Ich war',
        'Du warst',
        'Er war',
        'Sie war',
        'Es war',
        'Wir waren',
        'Ihr wart',
        'Sie waren',
      ]) {
        expect(
          (await finding('$prefix gegangt.', 'gegangt')).replacements.first,
          'gegangen',
          reason: prefix,
        );
      }
    });

    test('keeps ordinary ranking outside the licensed bounded frame', () async {
      final ordinary = (await finding('hier gegangt', 'gegangt')).replacements;
      for (final text in [
        'gegangt',
        'Hier steht gegangt.',
        'Er hat gegangt.',
        'Ich ist gegangt.',
        'Du war gegangt.',
        'Wir warst gegangt.',
        'Er sei gegangt.',
        'Er wäre gegangt.',
        'Gestern ist er gegangt.',
        'Der Mann ist gegangt.',
        'Weil er ist gegangt.',
        'Er ist gegangt gewesen.',
        'Er ist gegangt und geblieben.',
        'Er ist geblieben und gegangt.',
        'Er ist gefragt ob sie gegangt.',
        'Er ist sie sind gegangt.',
        'Er ist sie kann gegangt.',
        'Er ist sehr sehr sehr sehr sehr sehr sehr sehr sehr gegangt.',
        'Er ist ${'sehr ' * 40}gegangt.',
        'Er ist${' ' * 200}gegangt.',
        'Er ist gegangt${' ' * 65}.',
      ]) {
        expect(
          (await finding(text, 'gegangt')).replacements,
          ordinary,
          reason: text,
        );
      }
      final habenOrdinary = (await finding(
        'hier gelest',
        'gelest',
      )).replacements;
      expect(
        (await finding('Er ist gelest.', 'gelest')).replacements,
        habenOrdinary,
      );
    });

    test(
      'does not cross punctuation, protected spans or quoted fragments',
      () async {
        final ordinary = (await finding(
          'hier gegangt',
          'gegangt',
        )).replacements;
        for (final text in [
          'Er ist. gegangt.',
          'Er ist! gegangt.',
          'Er ist? gegangt.',
          'Er ist; gegangt.',
          'Er ist: gegangt.',
          'Er ist, gegangt.',
          'Er ist\ngegangt.',
          'Er ist\rgegangt.',
          'Er ist (nach Hause) gegangt.',
          'Er ist „nach Hause“ gegangt.',
          'Er `ist` nach Hause gegangt.',
          '`Er ist` nach Hause gegangt.',
          'Er ist `nach Hause` gegangt.',
          'Er ist https://example.invalid gegangt.',
        ]) {
          expect(
            (await finding(text, 'gegangt')).replacements,
            ordinary,
            reason: text,
          );
        }
        for (final text in [
          'Er ist `gegangt`.',
          'Das Wort „gegangt“ steht hier.',
          '„Er ist gegangt“ steht im Text.',
        ]) {
          expect((await provider.check(_request(text))).findings, isEmpty);
        }
      },
    );

    test('preserves accepted participles and ambiguous finite forms', () async {
      for (final text in [
        'Er ist nach Hause gegangen.',
        'Wir sind hier geblieben.',
        'Du bist gekommen.',
        'Sie ist gefahren.',
        'Ihr seid geflogen.',
        'Er ist gelaufen.',
        'Sie ist gestiegen.',
        'Es ist gesprungen.',
        'Er ist gestorben.',
        'Ihr gefallt mir.',
        'Wir sind gewachsen.',
        'Er hat das Holz gewachst.',
      ]) {
        expect(
          (await provider.check(_request(text))).findings,
          isEmpty,
          reason: text,
        );
      }
    });

    test(
      'separates preferred and ordinary cache entries in either order',
      () async {
        final ordinary = (await finding(
          'hier gegangt',
          'gegangt',
        )).replacements;
        for (final preferredFirst in [false, true]) {
          final text = preferredFirst
              ? 'Er ist gegangt. hier gegangt.'
              : 'hier gegangt. Er ist gegangt.';
          final result = await provider.check(_request(text));
          expect(result.findings, hasLength(2));
          expect(
            result.findings[preferredFirst ? 0 : 1].replacements.first,
            'gegangen',
          );
          expect(
            result.findings[preferredFirst ? 1 : 0].replacements,
            ordinary,
          );
        }
      },
    );

    test('keeps source offsets, normalization and case', () async {
      const text = '🙂 Text. Er\u00a0ist\tge\u00adgangt.';
      final result = await provider.check(_request(text, startOffset: 71));
      expect(result.findings, hasLength(1));
      final value = result.findings.single;
      expect(value.originalText, 'ge\u00adgangt');
      expect(value.start, 71 + text.indexOf('ge\u00adgangt'));
      expect(value.end, value.start + 'ge\u00adgangt'.length);
      expect(value.replacements.first, 'gegangen');
      expect(
        (await finding('ER IST GEGANGT.', 'GEGANGT')).replacements.first,
        'GEGANGEN',
      );
      final titleOrdinary = (await finding(
        'hier Gegangt',
        'Gegangt',
      )).replacements;
      expect(
        (await finding('Er ist Gegangt.', 'Gegangt')).replacements,
        titleOrdinary,
      );
    });

    test('supports regional dictionaries and direct speech', () async {
      for (final language in ['de-DE', 'de-AT', 'de-CH']) {
        final result = await provider.check(
          _request(
            'Er sagte: „Sie ist nach Hause gegangt.“',
            language: language,
          ),
        );
        expect(result.findings.single.originalText, 'gegangt');
        expect(result.findings.single.replacements.first, 'gegangen');
      }
    });

    test(
      'respects personal words and the existing suggestion budget',
      () async {
        provider.vocabulary.addWord('gegangt', language: 'de-DE');
        provider.vocabulary.ignoreWord('gekommt', language: 'de-DE');
        const text = 'Er ist gegangt. Sie ist gekommt.';
        expect((await provider.check(_request(text))).findings, isEmpty);
        final swiss = await provider.check(_request(text, language: 'de-CH'));
        expect(swiss.findings[0].replacements.first, 'gegangen');
        expect(swiss.findings[1].replacements.first, 'gekommen');
        final one = GermanSpellingProvider(
          maximumCandidateChecks: 1,
          maximumSuggestions: 1,
        );
        addTearDown(one.dispose);
        expect(
          (await one.check(
            _request('Er ist gegangt.'),
          )).findings.single.replacements,
          ['gegangen'],
        );
        final none = GermanSpellingProvider(maximumSuggestions: 0);
        addTearDown(none.dispose);
        expect(
          (await none.check(
            _request('Er ist gegangt.'),
          )).findings.single.replacements,
          isEmpty,
        );
      },
    );

    test(
      'agrees with the incoming grammar provider on the retained failure',
      () async {
        final grammar = GermanWritingRulesProvider();
        final service = OfficeProofingService(providers: [provider, grammar]);
        addTearDown(grammar.dispose);
        const text = 'Er ist nach Hause gegangt.';
        final report = await service.check(_request(text));
        expect(report.complete, isTrue);
        final occurrences = report.findings
            .where((item) => item.originalText == 'gegangt')
            .toList();
        expect(occurrences, hasLength(2));
        expect(occurrences.map((item) => item.category), [
          OfficeProofingCategory.grammar,
          OfficeProofingCategory.spelling,
        ]);
        expect(
          occurrences.every((item) => item.replacements.first == 'gegangen'),
          isTrue,
        );
        expect(
          (await service.check(
            _request('Er ist nach Hause gegangen.'),
          )).findings,
          isEmpty,
        );
      },
    );
  });
}

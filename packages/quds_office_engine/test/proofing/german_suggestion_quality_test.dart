import 'dart:async';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(
  String text, {
  String language = 'de-DE',
  int startOffset = 0,
}) => OfficeProofingRequest(
  documentId: 'd',
  blockId: 'p',
  revision: 1,
  text: text,
  language: language,
  startOffset: startOffset,
);

void main() {
  late GermanSpellingProvider provider;
  setUp(() => provider = GermanSpellingProvider());
  tearDown(() => provider.dispose());

  test(
    'two independent mistakes receive dictionary-backed corrections',
    () async {
      const Map<String, String> cases = <String, String>{
        'interresant': 'interessant',
        'Komunikazion': 'Kommunikation',
        'Kommunkationn': 'Kommunikation',
        'Rechschreibugn': 'Rechtschreibung',
        'Rehtschreibugn': 'Rechtschreibung',
        'Wissenscahflt': 'Wissenschaft',
        'Scmetterlng': 'Schmetterling',
        'Strasenbahnn': 'Straßenbahn',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        final OfficeProofingResult result = await provider.check(
          _request('hier ${entry.key}'),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, hasLength(1), reason: entry.key);
        final OfficeProofingFinding finding = result.findings.single;
        expect(finding.originalText, entry.key);
        expect(finding.replacements, contains(entry.value), reason: entry.key);
        expect(finding.replacements.length, lessThanOrEqualTo(5));
        for (final String replacement in finding.replacements) {
          expect(
            (await provider.check(_request('hier $replacement'))).findings,
            isEmpty,
            reason: '${entry.key} -> $replacement',
          );
        }
      }
    },
  );

  test(
    'changed first letter plus an internal error is not prefix-gated',
    () async {
      final OfficeProofingResult result = await provider.check(
        _request('wir xnternehemen etwas'),
      );
      expect(result.findings.single.originalText, 'xnternehemen');
      expect(result.findings.single.replacements, contains('unternehmen'));
    },
  );

  test(
    'ranking retains direct corrections before more distant alternatives',
    () async {
      final OfficeProofingResult result = await provider.check(
        _request('hier wunderbarr'),
      );
      expect(result.findings.single.replacements.first, 'wunderbar');
      expect(result.findings.single.replacements, contains('wunderbare'));
    },
  );

  test(
    'two-edit corrections preserve original ranges, emoji and source casing',
    () async {
      const String text = '🙂 Rech\u00adschreibugn STRASENBAHNN';
      final OfficeProofingReport report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      ).check(_request(text, startOffset: 40));
      expect(report.complete, isTrue);
      expect(report.findings, hasLength(2));
      expect(report.findings[0].start, 43);
      expect(report.findings[0].originalText, 'Rech\u00adschreibugn');
      expect(report.findings[0].replacements, contains('Rechtschreibung'));
      expect(report.findings[1].end, 40 + text.length);
      expect(report.findings[1].replacements, contains('STRASSENBAHN'));
      expect(text, '🙂 Rech\u00adschreibugn STRASENBAHNN');
    },
  );

  test(
    'Swiss two-edit suggestions never reintroduce dictionary sharp-s',
    () async {
      for (final String word in <String>['Strasenbahnn', 'STRASENBAHNN']) {
        final OfficeProofingResult result = await provider.check(
          _request('hier $word', language: 'de-CH'),
        );
        expect(result.findings, hasLength(1));
        expect(
          result.findings.single.replacements,
          contains(
            word == word.toUpperCase() ? 'STRASSENBAHN' : 'Strassenbahn',
          ),
        );
        for (final String replacement in result.findings.single.replacements) {
          expect(replacement, isNot(contains('ß')));
          expect(replacement, isNot(contains('ẞ')));
          expect(
            (await provider.check(
              _request('hier $replacement', language: 'de-CH'),
            )).findings,
            isEmpty,
          );
        }
      }
    },
  );

  test(
    'mixed-case personal corrections preserve exact user spelling and locale',
    () async {
      provider.vocabulary.addWord('QudsCloud', language: 'de-CH');
      for (final String word in <String>[
        'QudsClodu',
        'qudsclodu',
        'QUDSCLODU',
      ]) {
        final OfficeProofingResult result = await provider.check(
          _request(word, language: 'de-Latn-CH'),
        );
        expect(result.findings.single.replacements, contains('QudsCloud'));
        expect(
          result.findings.single.replacements,
          isNot(contains('QUDSCLOUD')),
        );
        expect(
          result.findings.single.replacements,
          isNot(contains('Qudscloud')),
        );
      }
      expect(
        (await provider.check(
          _request('QudsCloud', language: 'de-CH'),
        )).findings,
        isEmpty,
      );
      expect(
        (await provider.check(
          _request('QudsClodu'),
        )).findings.single.replacements,
        isNot(contains('QudsCloud')),
      );
      provider.vocabulary.removeWord('QudsCloud', language: 'de-CH');
      expect(
        (await provider.check(
          _request('QudsClodu', language: 'de-CH'),
        )).findings.single.replacements,
        isNot(contains('QudsCloud')),
      );
    },
  );

  test('ignored text never becomes a spelling correction candidate', () async {
    provider.vocabulary.ignoreWord('QudsCloud');
    expect((await provider.check(_request('QudsCloud'))).findings, isEmpty);
    expect(
      (await provider.check(
        _request('QudsClodu'),
      )).findings.single.replacements,
      isNot(contains('QudsCloud')),
    );
  });

  test(
    'personal phrases and controls are not offered as single-word corrections',
    () async {
      provider.vocabulary.addWord('Quds Cloud');
      provider.vocabulary.addWord('Quds\u200dCloud');
      provider.vocabulary.addWord('QudsCloud' * 1000);
      final OfficeProofingResult result = await provider.check(
        _request('QudsClodu'),
      );
      expect(result.findings.single.replacements, isEmpty);
    },
  );

  test(
    'personal corrections also repair an explicit compound component',
    () async {
      provider.vocabulary.addWord('QudsCloud');
      final OfficeProofingResult result = await provider.check(
        _request('QudsClodu\u2011Haus'),
      );
      expect(result.findings.single.originalText, 'QudsClodu\u2011Haus');
      expect(
        result.findings.single.replacements,
        contains('QudsCloud\u2011Haus'),
      );
      expect(
        (await provider.check(_request('QudsCloud\u2011Haus'))).findings,
        isEmpty,
      );
    },
  );

  test(
    'bounded fallback obeys candidate and result caps and skips long tokens',
    () async {
      final GermanSpellingProvider small = GermanSpellingProvider(
        maximumCandidateChecks: 16,
        maximumSuggestions: 1,
      );
      addTearDown(small.dispose);
      expect(
        (await small.check(
          _request('Komunikazion'),
        )).findings.single.replacements,
        isEmpty,
      );
      final GermanSpellingProvider one = GermanSpellingProvider(
        maximumSuggestions: 1,
      );
      addTearDown(one.dispose);
      expect(
        (await one.check(
          _request('Komunikazion'),
        )).findings.single.replacements,
        <String>['Kommunikation'],
      );
      for (final String word in <String>['qzxvtrplmn', 'x' * 65]) {
        final OfficeProofingResult result = await provider.check(
          _request(word),
        );
        expect(result.findings, hasLength(1));
        expect(result.findings.single.replacements, isEmpty);
      }
      final GermanSpellingProvider none = GermanSpellingProvider(
        maximumSuggestions: 0,
      );
      addTearDown(none.dispose);
      expect(
        (await none.check(
          _request('Komunikazion'),
        )).findings.single.replacements,
        isEmpty,
      );
    },
  );

  test(
    'repeated prose uses stable suggestions while protected text stays intact',
    () async {
      const String text =
          'Komunikazion `Komunikazion` https://example.invalid/Komunikazion Komunikazion';
      final OfficeProofingResult result = await provider.check(_request(text));
      expect(result.findings, hasLength(2));
      expect(result.findings[0].replacements, result.findings[1].replacements);
      expect(result.findings[1].start, text.lastIndexOf('Komunikazion'));
      expect(result.findings[0].replacements, contains('Kommunikation'));
    },
  );

  test('distinct expensive suggestions yield between searches', () async {
    await provider.warmUp();
    bool running = true;
    int turns = 0;
    Future<void> heartbeat() async {
      while (running) {
        await Future<void>.delayed(Duration.zero);
        turns++;
      }
    }

    final Future<void> progress = heartbeat();
    final OfficeProofingResult result = await provider.check(
      _request('Komunikazion Rechschreibugn Wissenscahflt'),
    );
    running = false;
    expect(result.findings, hasLength(3));
    // This asserts scheduler progress, not elapsed wall time. One initial
    // batch yield cannot satisfy the three independently computed searches.
    expect(turns, greaterThanOrEqualTo(3));
    await progress;
  });

  test('disposal during suggestion work rejects partial findings', () async {
    await provider.warmUp();
    Future<void> cancelAfterInitialTurn() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await provider.dispose();
    }

    final Future<void> cancellation = cancelAfterInitialTurn();
    final OfficeProofingResult result = await provider.check(
      _request('Komunikazion Rechschreibugn Wissenscahflt'),
    );
    await cancellation;
    expect(result.status, OfficeProofingStatus.unavailable);
    expect(result.findings, isEmpty);
  });

  test(
    'vocabulary changes during suggestion work reject partial findings',
    () async {
      await provider.warmUp();
      Future<void> editAfterInitialTurn() async {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        provider.vocabulary.addWord('QudsCloud');
      }

      final Future<void> edit = editAfterInitialTurn();
      final OfficeProofingResult result = await provider.check(
        _request('Komunikazion Rechschreibugn Wissenscahflt'),
      );
      await edit;
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
    },
  );
}

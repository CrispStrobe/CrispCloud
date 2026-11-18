import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(String text, {String language = 'de-DE'}) =>
    OfficeProofingRequest(
      documentId: 'german-spelling-continuation',
      blockId: 'paragraph',
      revision: 1,
      startOffset: 20,
      text: text,
      language: language,
    );

void main() {
  late GermanSpellingProvider provider;
  setUp(() => provider = GermanSpellingProvider());
  tearDown(() => provider.dispose());

  test('marked numeric prefixes remain complete identifiers', () async {
    const text = '1\u0301Huas 𝟘\u0308Huas ٤\u0301\u0308Huas Huas';
    final result = await provider.check(_request(text));
    expect(result.status, OfficeProofingStatus.success);
    final finding = result.findings.single;
    expect(finding.originalText, 'Huas');
    expect(finding.start, 20 + text.lastIndexOf('Huas'));
    expect(finding.end, 20 + text.length);
    expect(finding.replacements.first, 'Haus');
  });

  test('marked connectors protect following identifier fragments', () async {
    const text = '_\u0301Huas ‿\u0308Huas ⁀\u0301\u0308Huas Huas';
    final result = await provider.check(_request(text));
    final finding = result.findings.single;
    expect(finding.originalText, 'Huas');
    expect(finding.start, 20 + text.lastIndexOf('Huas'));
    expect(finding.replacements.first, 'Haus');
  });

  test('identifier guards cover arbitrarily long grapheme edges', () async {
    final text = '𝟘${'\u0308' * 4096}Huas _${'\u0301' * 4096}Huas Huas';
    final result = await provider.check(_request(text));
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings.single.start, 20 + text.lastIndexOf('Huas'));
    expect(result.findings.single.replacements.first, 'Haus');
  });

  test('marked identifier suffixes and both sides remain protected', () async {
    const text = 'Huas1\u0301 Huas𝟘\u0308 Huas_\u0301 1\u0301Huas_\u0308';
    final result = await provider.check(_request(text));
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings, isEmpty);
  });

  test('marked punctuation and separate prose keep spelling checks', () async {
    const text = '1\u0301 Huas _\u0308 Huas .\u0301Huas 🙂 Huas-Türr';
    final result = await provider.check(_request(text));
    expect(result.findings.map((finding) => finding.originalText), [
      'Huas',
      'Huas',
      'Huas',
      'Huas-Türr',
    ]);
    for (final finding in result.findings) {
      expect(
        text.substring(finding.start - 20, finding.end - 20),
        finding.originalText,
      );
    }
    expect(result.findings.last.replacements.first, 'Haus-Tür');
  });

  for (final entry in <String, String>{
    'Cafè': 'Café',
    'Abbè': 'Abbé',
    'Renè': 'René',
    'rosè': 'rosé',
    'Joêl': 'Joël',
  }.entries) {
    test('short accented corrections include ${entry.value}', () async {
      final result = await provider.check(_request('hier ${entry.key}'));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.originalText, entry.key);
      expect(result.findings.single.replacements, contains(entry.value));
      for (final replacement in result.findings.single.replacements) {
        expect(await provider.isKnownWord(replacement), isTrue);
      }
    });
  }

  test('short fallback can restore a missing accented character', () async {
    final result = await provider.check(_request('hier Caf'));
    expect(result.findings.single.replacements, contains('Café'));
    expect(result.findings.single.replacements.first, 'Cafe');
  });

  test(
    'accented corrections retain source ranges and uppercase style',
    () async {
      const text = '🙂 Cafe\u0300 CAFÈ';
      final result = await provider.check(_request(text));
      expect(result.findings, hasLength(2));
      expect(result.findings[0].originalText, 'Cafe\u0300');
      expect(result.findings[0].start, 23);
      expect(result.findings[0].end, 28);
      expect(result.findings[0].replacements, contains('Café'));
      expect(result.findings[1].start, 20 + text.indexOf('CAFÈ'));
      expect(result.findings[1].replacements, contains('CAFÉ'));
    },
  );

  test('short accented words stay known in each supported locale', () async {
    for (final language in ['de-DE', 'de-AT', 'de-CH']) {
      expect(
        (await provider.check(
          _request('Café Abbé René Joël rosé', language: language),
        )).findings,
        isEmpty,
      );
      final result = await provider.check(
        _request('hier Cafè', language: language),
      );
      expect(result.findings.single.replacements, contains('Café'));
    }
  });

  test('short fallback rejects candidates needing two edits', () async {
    for (final source in ['Caxè', 'Rqè']) {
      final result = await provider.check(_request('hier $source'));
      expect(result.findings.single.replacements, isNot(contains('Café')));
      expect(result.findings.single.replacements, isNot(contains('René')));
    }
  });

  test('direct short-word corrections retain precedence', () async {
    for (final entry in <String, List<String>>{
      'Huas': ['Haus', 'Hubs', 'Hufs', 'Huts'],
      'Türr': ['Tür', 'dürr', 'Türe'],
      'Fahl': ['fahl', 'kahl', 'Mahl', 'Pfahl', 'Wahl'],
    }.entries) {
      final result = await provider.check(_request('hier ${entry.key}'));
      expect(
        result.findings.single.replacements.take(entry.value.length),
        entry.value,
      );
    }
  });

  test(
    'short fallback respects suggestion and shared candidate limits',
    () async {
      final one = GermanSpellingProvider(maximumSuggestions: 1);
      final tiny = GermanSpellingProvider(maximumCandidateChecks: 1);
      final none = GermanSpellingProvider(maximumSuggestions: 0);
      addTearDown(one.dispose);
      addTearDown(tiny.dispose);
      addTearDown(none.dispose);
      expect(
        (await one.check(_request('hier Joêl'))).findings.single.replacements,
        ['Joël'],
      );
      expect(
        (await one.check(_request('hier Cafè'))).findings.single.replacements,
        ['Cafe'],
      );
      for (final limited in [tiny, none]) {
        expect(
          (await limited.check(
            _request('hier Joêl'),
          )).findings.single.replacements,
          isEmpty,
        );
      }
    },
  );

  test('explicit compounds can repair a short accented constituent', () async {
    final result = await provider.check(_request('hier Joêl-Huas'));
    expect(result.findings.single.replacements, contains('Joël-Haus'));
    for (final replacement in result.findings.single.replacements) {
      expect(await provider.isKnownWord(replacement), isTrue);
    }
  });
}

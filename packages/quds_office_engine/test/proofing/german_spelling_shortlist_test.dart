import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

Future<List<String>> suggestions(
  String text, {
  int maximum = 5,
  int budget = 6000,
  String language = 'de-DE',
  OfficeProofingVocabulary? vocabulary,
}) async {
  final provider = GermanSpellingProvider(
    maximumSuggestions: maximum,
    maximumCandidateChecks: budget,
    vocabulary: vocabulary,
  );
  try {
    final result = await provider.check(
      OfficeProofingRequest(
        documentId: 'shortlist',
        blockId: 'paragraph',
        revision: 1,
        text: text,
        language: language,
      ),
    );
    expect(result.status, OfficeProofingStatus.success);
    return result.findings.single.replacements;
  } finally {
    await provider.dispose();
  }
}

void main() {
  for (final word in <String>['HALTT', 'Haltt']) {
    final first = word == 'HALTT' ? 'HALT' : 'Halt';
    final second = word == 'HALTT' ? 'HALFT' : 'Halft';
    test('$word fills two slots with distinct visible corrections', () async {
      expect(await suggestions(word, maximum: 2), <String>[first, second]);
    });
  }

  for (final word in <String>['LERNNEN', 'Lernnen']) {
    final upper = word == 'LERNNEN';
    test('$word retains its first correction with a one-item cap', () async {
      expect(await suggestions(word, maximum: 1), <String>[
        upper ? 'LERNEN' : 'Lernen',
      ]);
    });
    test('$word fills two slots after merging lexical case variants', () async {
      expect(await suggestions(word, maximum: 2), <String>[
        upper ? 'LERNEN' : 'Lernen',
        upper ? 'LERNTEN' : 'Lernten',
      ]);
    });
    test('$word fills five slots in stable order', () async {
      final values = await suggestions(word);
      expect(values, <String>[
        upper ? 'LERNEN' : 'Lernen',
        upper ? 'LERNTEN' : 'Lernten',
        upper ? 'LERCHEN' : 'Lerchen',
        upper ? 'LERNENS' : 'Lernens',
        upper ? 'LEHNTEN' : 'Lehnten',
      ]);
      expect(await suggestions(word), values);
      expect(values, isNot(contains(word)));
    });
  }

  test('ordinary mid-sentence noun and verb case remains distinct', () async {
    expect(await suggestions('Wir sehen Haltt.', maximum: 2), <String>[
      'Halt',
      'halt',
    ]);
  });

  test('declared mixed-case names retain their exact spelling', () async {
    final vocabulary = OfficeProofingVocabulary()..addWord('QudsCloud');
    for (final word in <String>['QUDSCLUOD', 'QudsCluod', 'qudscluod']) {
      expect(
        await suggestions(word, maximum: 1, vocabulary: vocabulary),
        <String>['QudsCloud'],
      );
    }
  });

  test(
    'personal and dictionary forms remain distinct visible choices',
    () async {
      final vocabulary = OfficeProofingVocabulary()..addWord('SuperNova');
      expect(
        await suggestions('Supernvoa', maximum: 2, vocabulary: vocabulary),
        <String>['Supernova', 'SuperNova'],
      );
    },
  );

  test('a tiny candidate budget never expands to fill the shortlist', () async {
    expect(await suggestions('LERNNEN', budget: 1), isEmpty);
    expect(await suggestions('LERNNEN', maximum: 0), isEmpty);
  });

  test('Swiss corrections retain locale and uppercase spelling', () async {
    final values = await suggestions('HEIẞT', language: 'de-CH');
    expect(values, contains('HEISST'));
    expect(values.length, lessThanOrEqualTo(5));
    expect(values.toSet(), hasLength(values.length));
    expect(
      values.every((value) => !value.contains('ß') && !value.contains('ẞ')),
      isTrue,
    );
  });

  test('compound reconstruction keeps authored separators', () async {
    final values = await suggestions('HALTT‑LERNNEN');
    expect(values, contains('HALT‑LERNEN'));
    expect(values.length, lessThanOrEqualTo(5));
    expect(values.toSet(), hasLength(values.length));
    expect(values.every((value) => !value.contains('-')), isTrue);
  });
}

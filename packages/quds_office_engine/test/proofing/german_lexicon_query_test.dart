import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'read-only word query uses existing dictionary and exact token scope',
    () async {
      final provider = GermanSpellingProvider();
      addTearDown(provider.dispose);
      await provider.warmUp();
      expect(await provider.isKnownWord('Haus'), isTrue);
      expect(await provider.isKnownWord('bist'), isTrue);
      expect(await provider.isKnownWord('qzxvbnm'), isFalse);
      expect(await provider.isKnownWord('ein Haus'), isFalse);
      expect(await provider.isKnownWord('Haus!'), isFalse);
      expect(await provider.isKnownWord(''), isFalse);
      expect(await provider.isKnownWord('Haus', language: 'en-US'), isFalse);
      expect(await provider.isKnownWord('Straße', language: 'de-CH'), isFalse);
    },
  );

  test(
    'owner words remain language scoped and disposal fails explicitly',
    () async {
      final vocabulary = OfficeProofingVocabulary();
      vocabulary.addWord('QudsMarke', language: 'de-DE');
      final provider = GermanSpellingProvider(vocabulary: vocabulary);
      expect(await provider.isKnownWord('QudsMarke'), isTrue);
      expect(
        await provider.isKnownWord('QudsMarke', language: 'de-CH'),
        isFalse,
      );
      await provider.dispose();
      await expectLater(provider.isKnownWord('Haus'), throwsStateError);
    },
  );
}

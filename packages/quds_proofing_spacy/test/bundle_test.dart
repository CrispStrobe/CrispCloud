import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';
import 'package:test/test.dart';

void main() {
  test(
    'closed bundle includes exact source notices and never accepts path input',
    () {
      const bundle = SpacyBundle.germanF32();
      expect(bundle.modelName, 'de_core_news_sm');
      expect(bundle.modelVersion, '3.8.0');
      expect(bundle.formatVersion, 1);
      expect(SpacyBundle.files.map((file) => file.file), [
        'model.gguf',
        'resources.json',
        'LICENSE',
        'LICENSES_SOURCES',
      ]);
      expect(SpacyBundle.model.bytes, 7383104);
      expect(SpacyBundle.resources.bytes, 1404948);
      expect(() => SpacyBundle.files.clear(), throwsUnsupportedError);
    },
  );

  test('native configuration rejects ambiguous hashes and NUL paths', () {
    for (final hash in ['', 'z' * 64, 'A' * 64, 'a' * 63]) {
      expect(
        () => SpacyNativeBackendFactory(
          bundleDirectory: 'bundle',
          libraryPath: 'lib.so',
          librarySha256: hash,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => SpacyNativeBackendFactory(
        bundleDirectory: 'bad\u0000path',
        libraryPath: 'lib.so',
        librarySha256: 'a' * 64,
      ),
      throwsArgumentError,
    );
  });

  test(
    'missing explicit assets fail startup rather than produce empty success',
    () async {
      final factory = SpacyNativeBackendFactory(
        bundleDirectory: 'missing-spacy-bundle',
        libraryPath: 'missing-spacy-library',
        librarySha256: 'a' * 64,
      );
      await expectLater(
        factory.open(const SpacyBundle.germanF32()),
        throwsA(isA<SpacyUnavailableException>()),
      );
    },
  );
}

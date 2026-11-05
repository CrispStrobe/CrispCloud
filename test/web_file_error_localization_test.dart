import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/services/web_file_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'web errors preserve subtype, external details and localize across supported languages',
    () {
      final unsupported = WebFileUnsupportedError(
        WebFileFailureCode.extractUnsupported,
        'Archive extraction not supported on Web',
      );
      final browser = StateError('browser error {path}');
      final failure = WebFileException(
        WebFileFailureCode.deleteFailed,
        'Delete failed: $browser',
        {'error': browser, 'path': '/changed'},
      );
      expect(unsupported, isA<UnsupportedError>());
      expect(
        unsupported.toString(),
        UnsupportedError('Archive extraction not supported on Web').toString(),
      );
      expect(failure.toString(), 'Exception: Delete failed: $browser');
      for (final language in [
        'en',
        'de',
        'fr',
        'es',
        'pt',
        'zh',
        'ja',
        'ko',
        'ar',
      ]) {
        expect(
          localizedProviderErrorForLanguage(language, failure),
          contains('browser error {path}'),
        );
        for (final code in WebFileFailureCode.values) {
          final error = WebFileException(code, 'legacy', {
            'path': '/file',
            'error': browser,
          });
          expect(
            localizedProviderErrorForLanguage(language, error),
            isNot('Exception: legacy'),
            reason: '$language $code',
          );
        }
      }
    },
  );
}

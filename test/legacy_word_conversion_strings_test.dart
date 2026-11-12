import 'dart:ui' show Locale;

import 'package:crisp_cloud/l10n/legacy_word_conversion_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  test('conversion disclosures and failures are localized in all locales', () {
    final english = LegacyWordConversionStrings(const Locale('en'));
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
      final strings = LegacyWordConversionStrings(Locale(language));
      expect(strings.title, contains('DOCX'));
      expect(strings.lossNotice, contains('LibreOffice'));
      expect(strings.create, contains('DOCX'));
      expect(strings.fileName, isNotEmpty);
      expect(strings.cancel, isNotEmpty);
      expect(strings.converting, isNotEmpty);
      expect(strings.saving, isNotEmpty);
      for (final issue in LegacyWordConversionIssue.values) {
        final error = LegacyWordConversionException(issue);
        expect(strings.error(error), isNotEmpty);
        if (language != 'en') {
          expect(strings.error(error), isNot(english.error(error)));
        }
      }
      if (language != 'en') {
        expect(strings.lossNotice, isNot(english.lossNotice));
      }
    }
  });
}

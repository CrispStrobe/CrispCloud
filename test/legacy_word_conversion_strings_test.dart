import 'dart:ui' show Locale;

import 'package:crisp_cloud/l10n/legacy_word_conversion_strings.dart';
import 'package:crisp_cloud/services/legacy_word_conversion.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _structuredLabels(LegacyWordConversionStrings strings) => [
  strings.structuredMethod,
  strings.structuredNotice,
  strings.structuredMacroNotice,
  strings.builtInName,
  strings.structuredAcceptLoss,
  strings.unavailable,
  strings.limitationsTitle,
  for (final limitation in LegacyWordConversionLimitation.values)
    strings.limitation(limitation),
];

void main() {
  test('structured conversion controls and every limitation are localized', () {
    final english = _structuredLabels(
      LegacyWordConversionStrings(const Locale('en')),
    );
    expect(english, everyElement(isNotEmpty));
    for (final code in LocalePreference.supported.difference({'en'})) {
      final translated = _structuredLabels(
        LegacyWordConversionStrings(Locale(code)),
      );
      expect(translated.length, english.length);
      for (var index = 0; index < english.length; index++) {
        expect(translated[index], isNotEmpty, reason: '$code $index');
        expect(
          translated[index],
          isNot(english[index]),
          reason: '$code $index',
        );
      }
    }
  });

  test(
    'unsupported locales retain English and the explicit text-only option',
    () {
      final fallback = LegacyWordConversionStrings(const Locale('xx'));
      final english = LegacyWordConversionStrings(const Locale('en'));
      expect(_structuredLabels(fallback), _structuredLabels(english));
      expect(fallback.create, 'Create text-only DOCX');
      expect(fallback.lossNotice, contains('extracted main body text'));
      expect(fallback.structuredNotice, contains('Support is partial'));
      expect(fallback.structuredNotice, contains('original file is kept'));
      expect(fallback.structuredMacroNotice, contains('no active VBA'));
      expect(
        fallback.structuredMacroNotice,
        contains('original VBA project bytes may remain as inert evidence'),
      );
      expect(fallback.structuredMacroNotice, contains('never runs macros'));
    },
  );
}

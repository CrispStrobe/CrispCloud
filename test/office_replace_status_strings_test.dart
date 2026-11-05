import 'dart:ui';

import 'package:crisp_cloud/l10n/office_replace_status_strings.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replacement status contains the count in all supported languages', () {
    for (final language in LocalePreference.supported) {
      for (final count in [0, 1, 2, 3, 11, 100]) {
        expect(officeReplaceStatus(Locale(language), count), contains('$count'),
            reason: '$language $count');
      }
    }
  });

  test('plural forms reflect the language and count', () {
    expect(officeReplaceStatus(const Locale('en'), 1), 'Replaced 1 occurrence.');
    expect(officeReplaceStatus(const Locale('en'), 2), 'Replaced 2 occurrences.');
    expect(officeReplaceStatus(const Locale('fr'), 0), contains('occurrence remplacée'));
    expect(officeReplaceStatus(const Locale('fr'), 2), contains('occurrences remplacées'));
    expect(officeReplaceStatus(const Locale('ar'), 2), contains('نتيجتين'));
    expect(officeReplaceStatus(const Locale('ar'), 3), contains('نتائج'));
    expect(officeReplaceStatus(const Locale('ar'), 11), contains('نتيجةً'));
  });
}

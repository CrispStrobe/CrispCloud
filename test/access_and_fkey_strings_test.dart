import 'dart:ui';

import 'package:crisp_cloud/l10n/access_and_fkey_strings.dart';
import 'package:crisp_cloud/services/fkey_action_service.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all supported languages supply every action and access label', () {
    final english = AccessAndFKeyStrings(const Locale('en'));
    for (final language in LocalePreference.supported) {
      final strings = AccessAndFKeyStrings(Locale(language));
      for (final action in FKeyAction.values) {
        expect(strings.action(action.index), isNotEmpty, reason: '$language $action');
      }
      expect(strings.grantAccess, isNotEmpty);
      expect(strings.remotePathHint, contains('/Documents'));
      expect(strings.mnemonicHint, contains('24'));
      if (language != 'en') {
        expect(strings.grantAccess, isNot(english.grantAccess), reason: language);
      }
    }
    expect(AccessAndFKeyStrings(const Locale('xx')).grantAccess, english.grantAccess);
  });
}

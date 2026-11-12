import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/keepass_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KeePass chrome and safe errors cover every supported language', () {
    const english = KeePassStrings.forLanguage('en');
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = KeePassStrings.forLanguage(locale.languageCode);
      for (final key in KeePassStrings.keys) {
        expect(
          strings.text(key),
          isNotEmpty,
          reason: '${locale.languageCode}/$key',
        );
        expect(strings.text(key), isNot(key));
      }
      if (locale.languageCode != 'en') {
        for (final key in [
          'locked',
          'unlock',
          'invalidCredentials',
          'sourceChanged',
          'saveError',
          'pendingLocked',
        ]) {
          expect(
            strings.text(key),
            isNot(english.text(key)),
            reason: '${locale.languageCode}/$key',
          );
        }
      }
    }
  });
}

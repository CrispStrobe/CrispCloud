import 'package:crisp_cloud/l10n/connection_strings.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nextcloud guidance is translated for every supported language', () {
    final english = ConnectionStrings.forLanguage('en');
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = ConnectionStrings.forLanguage(locale.languageCode);
      final values = [
        strings.serverAddress,
        strings.passwordOrAppPassword,
        strings.appPasswordHelp,
        strings.authenticationFailed,
        strings.browserLogin,
        strings.browserLoginHelp,
        strings.waitingForBrowser,
        strings.browserLoginExpired,
      ];
      expect(values.every((value) => value.isNotEmpty), isTrue);
      if (locale.languageCode != 'en') {
        expect(values[0], isNot(english.serverAddress));
        expect(values[1], isNot(english.passwordOrAppPassword));
        expect(values[2], isNot(english.appPasswordHelp));
        expect(values[3], isNot(english.authenticationFailed));
        expect(values[4], isNot(english.browserLogin));
        expect(values[5], isNot(english.browserLoginHelp));
        expect(values[6], isNot(english.waitingForBrowser));
        expect(values[7], isNot(english.browserLoginExpired));
      }
    }
  });
}

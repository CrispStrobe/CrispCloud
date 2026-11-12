import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/installed_office_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> _placeholders(String value) =>
    RegExp(r'\{([^{}]+)\}')
        .allMatches(value)
        .map((match) => match.group(1)!)
        .toSet();

void main() {
  const english = InstalledOfficeStrings(Locale('en'));

  test('conversion controls and evidence cover every supported language', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = InstalledOfficeStrings(locale);
      for (final key in InstalledOfficeStrings.supportedKeys) {
        final value = strings.text(key);
        final reason = '${locale.languageCode}/$key';
        expect(value, isNotEmpty, reason: reason);
        expect(value, isNot(key), reason: reason);
        expect(
          _placeholders(value),
          _placeholders(english.text(key)),
          reason: reason,
        );
        // "Images" has the same spelling in French and English. Other values
        // differ, so this also detects an accidentally missing translation
        // hidden by the English fallback.
        if (locale.languageCode != 'en' &&
            !(locale.languageCode == 'fr' && key == 'images')) {
          expect(value, isNot(english.text(key)), reason: reason);
        }
      }
    }
  });

  test('application and extension placeholders work in every language', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = InstalledOfficeStrings(locale);
      final installed = strings.text(
        'installed',
        arguments: {'app': 'LibreOffice'},
      );
      expect(installed, contains('LibreOffice'));
      expect(_placeholders(installed), isEmpty);

      final filename = strings.text(
        'filename',
        arguments: {'extension': 'docm'},
      );
      expect(filename, contains('.docm'));
      expect(_placeholders(filename), isEmpty);
    }
  });

  test(
    'unknown locales use English and region variants retain the language',
    () {
      const unsupported = InstalledOfficeStrings(Locale('zz'));
      const regional = InstalledOfficeStrings(Locale('de', 'CH'));
      const german = InstalledOfficeStrings(Locale('de'));
      for (final key in InstalledOfficeStrings.supportedKeys) {
        expect(unsupported.text(key), english.text(key));
        expect(regional.text(key), german.text(key));
      }
      expect(unsupported.text('unknown-key'), 'unknown-key');
    },
  );
}

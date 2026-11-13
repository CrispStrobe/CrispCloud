import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/installed_office_preview_strings.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/widgets/installed_office_preview_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> _placeholders(String value) =>
    RegExp(r'\{([^{}]+)\}')
        .allMatches(value)
        .map((match) => match.group(1)!)
        .toSet();

void main() {
  const english = InstalledOfficePreviewStrings(Locale('en'));

  test('preview controls and errors have all nine translations', () {
    expect(AppLocalizations.supportedLocales, hasLength(9));
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = InstalledOfficePreviewStrings(locale);
      for (final key in InstalledOfficePreviewStrings.supportedKeys) {
        final value = strings.text(key);
        expect(value, isNotEmpty, reason: '${locale.languageCode}/$key');
        expect(value, isNot(key));
        expect(_placeholders(value), _placeholders(english.text(key)));
        if (locale.languageCode != 'en') {
          expect(
            value,
            isNot(english.text(key)),
            reason: '${locale.languageCode}/$key cannot use English fallback',
          );
        }
      }
      for (final key in ['installed', 'completed']) {
        final value = strings.text(key, arguments: {'app': 'LibreOffice'});
        expect(value, contains('LibreOffice'));
        expect(_placeholders(value), isEmpty);
      }
      for (final code in InstalledOfficeConversionErrorCode.values) {
        expect(
          strings.error(InstalledOfficeConversionException(code)),
          isNot(contains('InstalledOfficeConversionException')),
        );
      }
      expect(
        strings.error(StateError('/private/file')),
        isNot(contains('/private')),
      );
    }
  });

  test('region and unsupported locale behavior is predictable', () {
    const regional = InstalledOfficePreviewStrings(Locale('de', 'CH'));
    const german = InstalledOfficePreviewStrings(Locale('de'));
    const fallback = InstalledOfficePreviewStrings(Locale('zz'));
    for (final key in InstalledOfficePreviewStrings.supportedKeys) {
      expect(regional.text(key), german.text(key));
      expect(fallback.text(key), english.text(key));
    }
  });

  test(
    'only formats inspected by the installed PDF service are advertised',
    () {
      for (final name in ['a.doc', 'a.DOT', 'a.docx', 'a.DOCM']) {
        expect(isInstalledOfficePreviewFileName(name), isTrue);
      }
      for (final name in [
        'a.dotx',
        'a.dotm',
        'a.ppt',
        'a.xml',
        'a.doc.exe',
        'doc',
      ]) {
        expect(isInstalledOfficePreviewFileName(name), isFalse);
      }
    },
  );
}

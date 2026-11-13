import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_pdf_font_notice_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('font notice has all nine translations and safe locale fallback', () {
    const english = OfficePdfFontNoticeStrings(Locale('en'));
    expect(AppLocalizations.supportedLocales, hasLength(9));
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = OfficePdfFontNoticeStrings(locale);
      for (final key in OfficePdfFontNoticeStrings.supportedKeys) {
        final value = strings.text(key);
        expect(value, isNotEmpty, reason: '${locale.languageCode}/$key');
        expect(value, isNot(key));
        if (locale.languageCode != 'en') {
          expect(
            value,
            isNot(english.text(key)),
            reason: '${locale.languageCode}/$key',
          );
        }
      }
    }
    const regional = OfficePdfFontNoticeStrings(Locale('pt', 'PT'));
    const portuguese = OfficePdfFontNoticeStrings(Locale('pt'));
    const unknown = OfficePdfFontNoticeStrings(Locale('zz'));
    for (final key in OfficePdfFontNoticeStrings.supportedKeys) {
      expect(regional.text(key), portuguese.text(key));
      expect(unknown.text(key), english.text(key));
    }
  });
}

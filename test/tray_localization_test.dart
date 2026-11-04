import 'package:crisp_cloud/l10n/tray_strings.dart';
import 'package:crisp_cloud/services/tray_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray follows app override, system language and English fallback', () {
    expect(TrayService.resolveLocale(const Locale('de'), [const Locale('fr')]), const Locale('de'));
    expect(TrayService.resolveLocale(null, [const Locale('fr', 'CA')]), const Locale('fr'));
    expect(TrayService.resolveLocale(null, [const Locale('it')]), const Locale('en'));
  });
  test('tray status translations retain sync counts in every language', () {
    for (final language in ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = TrayStrings(Locale(language));
      final status = strings.text('last', {'up': 12, 'down': 34});
      expect(status, contains('12'));
      expect(status, contains('34'));
      expect(status, isNot(contains('{')));
    }
  });
}

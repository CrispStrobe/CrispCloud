import 'package:crisp_cloud/l10n/background_notification_strings.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('explicit locale persists and reaches background notification text', () async {
    await LocalePreference.write(const Locale('es'));
    expect(await LocalePreference.read(), const Locale('es'));
    expect((await BackgroundNotificationStrings.fromPreferences()).text('title'),
        'Sincronización de CrispCloud');
  });
  test('system and invalid locale restore default; writes retain latest choice', () async {
    await Future.wait([
      LocalePreference.write(const Locale('de')),
      LocalePreference.write(const Locale('fr')),
    ]);
    expect(await LocalePreference.read(), const Locale('fr'));
    await LocalePreference.write(null);
    expect(await LocalePreference.read(), isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalePreference.key, 'invalid');
    expect(await LocalePreference.read(), isNull);
  });
  test('migrates the previous locale and respects a later system choice', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'de-DE'});
    expect(await LocalePreference.read(), const Locale('de'));
    await LocalePreference.write(null);
    expect(await LocalePreference.read(), isNull);
  });
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:crisp_cloud/services/oauth_callback_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('callback pages have translations for every supported language', () {
    final english = OAuthCallbackPage(const Locale('en'));
    for (final language in LocalePreference.supported.difference({'en'})) {
      final page = OAuthCallbackPage(Locale(language));
      expect(page.successHtml(), isNot(english.successHtml()), reason: language);
      expect(page.deniedHtml('access_denied'), isNot(english.deniedHtml('access_denied')), reason: language);
      expect(page.notFound, isNot(english.notFound), reason: language);
    }
    expect(OAuthCallbackPage(const Locale('xx')).successHtml(), english.successHtml());
  });

  test('untrusted provider errors cannot inject markup', () {
    final html = OAuthCallbackPage(const Locale('en'))
        .deniedHtml('<script>alert("x")</script>&');
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('&amp;'));
    expect(html, isNot(contains('<script>')));
  });

  test('effective page honors saved language', () async {
    SharedPreferences.setMockInitialValues({LocalePreference.key: 'es'});
    final page = await OAuthCallbackPage.effective();
    expect(page.successHtml(), contains('Autorización'));
  });
}

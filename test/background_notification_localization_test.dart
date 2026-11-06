import 'package:crisp_cloud/l10n/background_notification_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification counts and external details survive every locale', () {
    for (final language in ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = BackgroundNotificationStrings(Locale(language));
      final body = strings.body(conflicts: 2, errors: 3, details: ['provider: denied']);
      expect(body, contains('2'));
      expect(body, contains('3'));
      expect(body, contains('provider: denied'));
      expect(strings.failure('network detail'), contains('network detail'));
      expect(body, isNot(contains('{n}')));
    }
  });
  test('English singular and unsupported locale preserve fallback', () {
    final strings = BackgroundNotificationStrings(const Locale('it'));
    expect(strings.body(conflicts: 1, errors: 1, details: []), '1 conflict — 1 error');
    expect(strings.text('channel'), 'Sync Notifications');
  });
}

import 'package:crisp_cloud/l10n/nextcloud_operation_strings.dart';
import 'package:crisp_cloud/services/nextcloud_browser_failure.dart';
import 'package:crisp_cloud/services/nextcloud_operation_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opaque browser failures report endpoint, app origin and actionable limits',
    () {
      final failure = nextcloudBrowserFailure(
        Uri.parse(
          'https://cloud.example/nextcloud/remote.php/dav/files/alice/',
        ),
        Uri.parse('https://app.example/browser?state=private#fragment'),
        Exception('Load failed'),
      );
      expect(failure.code, NextcloudOperationCode.browserConnectionFailed);
      expect(failure.arguments['origin'], 'https://app.example');
      for (final language in [
        'en',
        'de',
        'fr',
        'es',
        'pt',
        'zh',
        'ja',
        'ko',
        'ar',
      ]) {
        final text = localizedNextcloudErrorForLanguage(language, failure);
        expect(
          text,
          contains(
            'https://cloud.example/nextcloud/remote.php/dav/files/alice/',
          ),
        );
        expect(text, contains('https://app.example'));
        expect(text, contains('PROPFIND'));
        expect(text, contains('Authorization'));
        expect(text, contains('Depth'));
        expect(text, contains('Content-Type'));
        expect(text, contains('CORS'));
        expect(text, contains('Load failed'));
        expect(text, isNot(contains('state=private')));
        expect(text, isNot(contains('{')));
      }
    },
  );
}

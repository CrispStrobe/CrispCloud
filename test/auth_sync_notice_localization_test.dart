import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/auth_sync_notice.dart';
import 'package:crisp_cloud/services/web_file_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every auth/sync notice localizes while preserving literal data', () {
    const pair = '資料 {error} "backup"';
    const detail = 'request-482 {pair}: /資料/file';
    for (final code in AuthSyncNoticeCode.values) {
      final messages = <String>{};
      for (final locale in AppLocalizations.supportedLocales) {
        final notice = AuthSyncNotice(code, pairName: pair, cause: detail);
        final text = localizedProviderErrorForLanguage(
          locale.languageCode,
          notice,
        );
        if (code != AuthSyncNoticeCode.sessionExpired) {
          expect(text, contains(detail));
        }
        if (code == AuthSyncNoticeCode.syncPair) expect(text, contains(pair));
        expect(text, isNot(contains('Instance of')));
        messages.add(text);
      }
      expect(messages, hasLength(9));
    }
  });

  test('nested provider failures use the same locale and unknown locale falls back', () {
    final cause = WebFileException(
      WebFileFailureCode.permission,
      'legacy permission detail',
    );
    final notice = AuthSyncNotice(AuthSyncNoticeCode.download, cause: cause);
    for (final locale in AppLocalizations.supportedLocales) {
      final nested = localizedProviderErrorForLanguage(
        locale.languageCode,
        cause,
      );
      final message = localizedProviderErrorForLanguage(
        locale.languageCode,
        notice,
      );
      expect(message, contains(nested));
      expect(message, isNot(contains('legacy permission detail')));
    }
    expect(
      localizedProviderErrorForLanguage(
        'xx',
        const AuthSyncNotice(AuthSyncNoticeCode.sessionExpired),
      ),
      'Session expired. Please log in again.',
    );
  });

  testWidgets(
    'queued notices localize at presentation without changing diagnostics',
    (tester) async {
      final queue = ErrorNotifier();
      addTearDown(queue.dispose);
      const original = 'Sync failed for "資料": network-482';
      const notice = AuthSyncNotice(
        AuthSyncNoticeCode.syncPair,
        pairName: '資料',
        cause: 'network-482',
      );
      queue.addError(original, cause: notice);
      for (final locale in AppLocalizations.supportedLocales) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) =>
                  Text(localizedPanelError(context, queue.lastAppError!)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            localizedProviderErrorForLanguage(locale.languageCode, notice),
          ),
          findsOneWidget,
        );
        expect(queue.lastError, original);
        expect(queue.lastAppError!.cause, same(notice));
      }
    },
  );
}

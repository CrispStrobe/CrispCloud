import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/dropbox_operation_strings.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unauthenticated adapter error retains legacy text', () async {
    final adapter = DropboxClientAdapter(config: null);
    await expectLater(adapter.downloadFileBytes('/report.pdf'), throwsA(
      isA<DropboxOperationFailure>()
          .having((e) => e.code, 'code', DropboxOperationCode.unauthenticated)
          .having((e) => e.toString(), 'legacy text', 'Exception: Not authenticated'),
    ));
  });
  testWidgets('localized HTTP errors retain remote details in every locale', (tester) async {
    final failure = DropboxOperationFailure(DropboxOperationCode.download,
        'Dropbox download failed (403): denied', {'status': 403, 'body': 'denied'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedDropboxError(context, failure))),
      ));
      expect(find.textContaining('403'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(find.textContaining('{status}'), findsNothing);
    }
  });
}

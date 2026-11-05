import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/gdrive_operation_strings.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unauthenticated adapter errors retain their legacy message', () async {
    final adapter = GDriveClientAdapter(config: null);
    await expectLater(adapter.downloadFileBytes('/report.pdf'), throwsA(
      isA<GDriveOperationFailure>()
          .having((e) => e.code, 'code', GDriveOperationCode.unauthenticated)
          .having((e) => e.toString(), 'legacy text', 'Exception: Not authenticated'),
    ));
  });

  testWidgets('localized HTTP errors keep server status and body', (tester) async {
    final failure = GDriveOperationFailure(GDriveOperationCode.download,
        'GDrive download failed (403): denied', {'status': 403, 'body': 'denied'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedGDriveError(context, failure))),
      ));
      expect(find.textContaining('403'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(find.textContaining('{status}'), findsNothing);
    }
  });
}

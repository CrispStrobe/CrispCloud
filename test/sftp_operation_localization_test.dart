import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/sftp_operation_strings.dart';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid SFTP identity retains legacy exception text', () async {
    final adapter = SFTPClientAdapter(config: null);
    await expectLater(adapter.login('invalid', 'password'), throwsA(
      isA<SftpOperationException>()
          .having((e) => e.code, 'code', SftpOperationCode.invalidIdentity)
          .having((e) => e.toString(), 'legacy text',
              'Exception: Format must be user@host (e.g. u12345@u123.your-storagebox.de)'),
    ));
    expect(SftpOperationFormatException(SftpOperationCode.invalidAddress,
        'Invalid SFTP server address'), isA<FormatException>());
  });
  testWidgets('list errors retain path and external detail in every locale', (tester) async {
    final failure = SftpOperationException(SftpOperationCode.listFailed,
        'Failed to list path /docs: denied', {'path': '/docs', 'error': 'denied'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedSftpOperationError(context, failure))),
      ));
      expect(find.textContaining('/docs'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(find.textContaining('{path}'), findsNothing);
    }
  });
}

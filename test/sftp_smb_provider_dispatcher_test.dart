import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/sftp_operation_failure.dart';
import 'package:crisp_cloud/services/smb_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SFTP and SMB failures dispatch through nested panel errors',
      (tester) async {
    final sftp = SftpOperationException(
        SftpOperationCode.listFailed,
        'Failed to list path /example: server detail',
        {'path': '/example', 'error': 'server detail'});
    const smb = SmbFormatFailure(SmbOperationCode.invalidName,
        'Enter a file name without path separators.');
    final errors = <Object>[
      sftp,
      smb,
      SftpOperationFormatException(
          SftpOperationCode.invalidAddress, 'Invalid SFTP server address'),
      SmbStateFailure(
          SmbOperationCode.notFound, 'File or folder was not found.'),
      SmbUnsupportedFailure(
          SmbOperationCode.unsupported, 'SMB requires the installed app.'),
    ];
    expect(smb, isA<FormatException>());
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      for (final cause in errors) {
        final direct = localizedKnownProviderError(context, cause);
        expect(direct, isNotNull, reason: '${locale.languageCode}: $cause');
        final wrapped = AppError('legacy outer',
            code: PanelErrorCode.archiveRead, arguments: {'error': cause});
        expect(localizedPanelError(context, wrapped), contains(direct));
        expect(
            localizedPanelError(
                context, AppError(cause.toString(), cause: cause)),
            direct);
      }
      final sftpText = localizedProviderError(context, sftp);
      expect(sftpText, contains('/example'));
      expect(sftpText, contains('server detail'));
      expect(tester.takeException(), isNull);
    }
  });
}

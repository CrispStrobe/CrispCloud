import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/ftp_operation_failure.dart';
import 'package:crisp_cloud/services/webdav_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'FTP and WebDAV causes dispatch inside panel errors in all locales',
      (tester) async {
    final ftpInner =
        FtpOperationFailure(FtpOperationCode.notLoggedIn, 'Not logged in');
    final errors = <Object>[
      FtpOperationFailure(FtpOperationCode.list, 'legacy FTP list error', {
        'path': '/example',
        'error': ftpInner,
      }),
      WebDavException(
          WebDavOperationCode.listFailed, 'legacy WebDAV list error', {
        'path': '/example',
        'error': 'external detail',
      }),
      FtpWebUnsupportedFailure(),
      WebDavUnsupportedError(
          WebDavOperationCode.webDownload, 'legacy web unsupported'),
    ];
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
        expect(direct, isNotNull);
        expect(direct, isNot(cause.toString()),
            reason: '${locale.languageCode}: $cause');
        final wrapped = AppError('legacy outer',
            code: PanelErrorCode.archiveRead, arguments: {'error': cause});
        expect(localizedPanelError(context, wrapped), contains(direct));
        expect(
            localizedPanelError(
                context, AppError(cause.toString(), cause: cause)),
            direct);
      }
      final webdav = localizedProviderError(context, errors[1]);
      expect(webdav, contains('/example'));
      expect(webdav, contains('external detail'));
      final ftp = localizedProviderError(context, errors.first);
      expect(ftp, contains(localizedProviderError(context, ftpInner)));
      expect(tester.takeException(), isNull);
    }
  });
}

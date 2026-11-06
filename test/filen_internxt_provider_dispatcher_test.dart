import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/filen_operation_failure.dart';
import 'package:crisp_cloud/services/internxt_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Filen and Internxt errors dispatch through nested panel errors',
      (tester) async {
    final filen = FilenOperationFailure(FilenOperationCode.unresolvedPath,
        'Could not resolve path: /example', {'path': '/example'});
    const internxt = InternxtFormatFailure(InternxtOperationCode.invalidName,
        'The server returned an invalid file name');
    final errors = <Object>[
      filen,
      internxt,
      InternxtStateFailure(InternxtOperationCode.notSignedIn, 'Not signed in'),
      InternxtUnsupportedFailure(
          InternxtOperationCode.webDownload, 'Use browser download'),
    ];
    expect(internxt, isA<FormatException>());
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
      expect(localizedProviderError(context, filen), contains('/example'));
      expect(tester.takeException(), isNull);
    }
  });
}

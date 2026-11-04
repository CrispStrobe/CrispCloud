import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/azure_hetzner_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'adapter failures localize through panel boundaries and preserve server details',
      (tester) async {
    final http = AzureHetznerException(
        AzureHetznerErrorCode.azureHttp,
        'Azure Blob error 403: Forbidden\nserver {status}',
        {'status': 403, 'reason': 'Forbidden', 'body': 'server {status}'});
    final argument = AzureHetznerArgumentError(
        AzureHetznerErrorCode.azureConnectionString,
        'Invalid Azure connection string');
    final state = AzureHetznerStateError(AzureHetznerErrorCode.azureContainer,
        'No container specified and no default container configured');
    expect(http.toString(),
        'Exception: Azure Blob error 403: Forbidden\nserver {status}');
    expect(argument, isA<ArgumentError>());
    expect(argument.toString(),
        ArgumentError('Invalid Azure connection string').toString());
    expect(state, isA<StateError>());
    expect(
        state.toString(),
        StateError('No container specified and no default container configured')
            .toString());
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
      final text = localizedProviderError(context, http);
      expect(text, contains('403'));
      expect(text, contains('Forbidden'));
      expect(text, contains('server {status}'));
      final panel = AppError('legacy outer',
          code: PanelErrorCode.archiveRead, arguments: {'error': http});
      expect(localizedPanelError(context, panel), contains(text));
      for (final code in AzureHetznerErrorCode.values) {
        final failure = AzureHetznerException(code, 'legacy', {
          'status': 503,
          'reason': 'external reason',
          'body': 'external body'
        });
        expect(localizedProviderError(context, failure),
            isNot('Exception: legacy'),
            reason: '${locale.languageCode} $code');
      }
    }
  });
}

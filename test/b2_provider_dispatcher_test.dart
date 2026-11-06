import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/b2_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'B2 errors render through dispatcher and nested panel errors in every locale',
      (tester) async {
    final cause = B2StateFailure(B2OperationCode.api, 'legacy text', {
      'operation': 'b2_list_file_names',
      'status': 403,
      'body': 'server detail',
    });
    expect(cause, isA<StateError>());
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
      final direct = localizedKnownProviderError(context, cause);
      expect(direct, isNotNull);
      expect(direct, contains('b2_list_file_names'));
      expect(direct, contains('403'));
      expect(direct, contains('server detail'));
      final wrapped = AppError('legacy outer',
          code: PanelErrorCode.archiveRead, arguments: {'error': cause});
      expect(localizedPanelError(context, wrapped), contains(direct));
      expect(
          localizedPanelError(
              context, AppError(cause.toString(), cause: cause)),
          direct);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('unknown provider failures keep fallback behavior',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    expect(localizedKnownProviderError(context, Exception('external')), isNull);
    expect(localizedProviderError(context, Exception('external')),
        'Exception: external');
  });
}

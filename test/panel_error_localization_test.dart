import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('typed panel errors localize without altering queue messages',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    final errors = ErrorNotifier();
    addTearDown(errors.dispose);
    errors.addError('Delete failed: remote detail',
        code: PanelErrorCode.deleteFailed,
        arguments: {'error': 'remote detail'});
    expect(errors.lastError, 'Delete failed: remote detail');
    expect(localizedPanelError(context, errors.lastAppError!),
        'Löschen fehlgeschlagen: remote detail');
    errors.addError('unrecognized external error');
    expect(localizedPanelError(context, errors.lastAppError!),
        'unrecognized external error');
    errors.clearLastError();
    expect(errors.lastError, 'Delete failed: remote detail');
  });

  testWidgets('panel errors retain supplied path and cause in all locales',
      (tester) async {
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
      final denied = AppError('fallback',
          code: PanelErrorCode.accessParent,
          arguments: {'path': '/example/folder'});
      final failed = AppError('fallback',
          code: PanelErrorCode.archiveRead,
          arguments: {'error': 'external-detail-42'});
      expect(localizedPanelError(context, denied), contains('/example/folder'));
      expect(
          localizedPanelError(context, failed), contains('external-detail-42'));
      for (final code in [
        PanelErrorCode.cloudTransferFailed,
        PanelErrorCode.cloudCompareFailed,
        PanelErrorCode.cloudSearchFailed
      ]) {
        final cloudError = AppError('fallback',
            code: code, arguments: {'error': 'external-detail-42'});
        expect(localizedPanelError(context, cloudError),
            contains('external-detail-42'));
        expect(localizedPanelError(context, cloudError),
            isNot(contains('fallback')));
      }
      expect(tester.takeException(), isNull);
    }
  });
}

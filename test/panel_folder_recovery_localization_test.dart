import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('queued missing-folder recovery is localized at presentation', (
    tester,
  ) async {
    final errors = ErrorNotifier();
    addTearDown(errors.dispose);
    const original = 'Folder not found. Returned to your Home folder.';
    errors.addError(original, code: PanelErrorCode.homeFallback);
    final messages = <String>{};
    for (final locale in AppLocalizations.supportedLocales) {
      late String message;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              message = localizedPanelError(context, errors.lastAppError!);
              return Text(message);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(message, isNotEmpty);
      if (locale.languageCode != 'en') expect(message, isNot(original));
      messages.add(message);
      // Localization must not mutate the shared queued error.
      expect(errors.lastError, original);
      expect(errors.lastAppError!.code, PanelErrorCode.homeFallback);
    }
    expect(messages, hasLength(9));
  });

  testWidgets('unclassified external errors retain their details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Text(
            localizedPanelError(
              context,
              AppError('server-request-482: custom failure'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('server-request-482: custom failure'), findsOneWidget);
  });
}

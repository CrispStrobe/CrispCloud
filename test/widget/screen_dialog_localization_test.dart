import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keyboard shortcut descriptions follow the selected locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKeyboardShortcutsHelp(context),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Esta ayuda'), findsOneWidget);
    expect(find.text('Renombrar en el lugar'), findsOneWidget);
  });

  testWidgets('received-files confirmation follows the selected locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showReceivedFilesDialog(context, ['a.txt', 'b.txt']),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Archivos recibidos'), findsOneWidget);
    expect(find.text('¿Subir 2 archivo(s) a Cloud?'), findsOneWidget);
  });
}

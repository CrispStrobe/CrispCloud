import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('keyboard shortcut descriptions follow the selected locale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
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

  testWidgets('shortcut help omits aliases disabled by customization', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'keyboard_shortcuts': '{"newFolder":{"key":"F9"},"delete":{"key":"F10"},"goToFolder":{"key":"F11"},"toggleHidden":{"key":"F12"}}',
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
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
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    for (final key in ['F9', 'F10', 'F11', 'F12']) {
      expect(find.text(key), findsOneWidget);
    }
    expect(find.textContaining(' / Ctrl+N'), findsNothing);
    expect(find.textContaining(' / Ctrl+L'), findsNothing);
    expect(find.textContaining(' / Ctrl+H'), findsNothing);
    expect(find.textContaining(' / F8'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

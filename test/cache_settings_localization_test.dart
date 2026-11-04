import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/cache_settings_strings.dart';
import 'package:crisp_cloud/widgets/cache_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('German cache dialog localizes controls and confirmation',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
          body: Consumer(
              builder: (context, ref, _) => TextButton(
                    onPressed: () => showCacheSettingsDialog(context, ref),
                    child: const Text('Open'),
                  ))),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Cache-Einstellungen'), findsOneWidget);
    expect(find.text('Unbegrenzt'), findsOneWidget);
    await tester.tap(find.text('Cache leeren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alle zwischengespeicherten Dateien entfernen?'),
        findsOneWidget);
  });

  testWidgets('Arabic cache counts use the appropriate plural forms',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        final strings = CacheSettingsStrings(context);
        return Column(children: [
          for (final count in [0, 1, 2, 3, 11]) Text(strings.files(count))
        ]);
      }),
    ));
    for (final expected in [
      'لا ملفات',
      'ملف واحد',
      'ملفان',
      '3 ملفات',
      '11 ملفًا'
    ]) {
      expect(find.text(expected), findsOneWidget);
    }
  });
}

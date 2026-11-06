import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/browser_drawer_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser drawer translations retain messages and parameters', () {
    final translations = BrowserDrawerStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    expect(keys, containsAll(['Diagnostics', '{count} operation(s)']));
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
  });

  testWidgets('drawer labels and operation counts use selected language',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ja'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        final strings = BrowserDrawerStrings(context);
        return Column(children: [
          Text(strings.text('Diagnostics')),
          Text(strings.operations(3)),
        ]);
      }),
    ));
    expect(find.text('診断'), findsOneWidget);
    expect(find.text('3 件の操作'), findsOneWidget);
  });
}

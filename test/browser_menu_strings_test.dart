import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/browser_menu_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native browser menus have a complete set of nonempty translations', () {
    final translations = BrowserMenuStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    expect(keys, containsAll(['Language', 'Go', 'Toggle Preview']));
    for (final entry in translations.entries) {
      expect(entry.value.keys.toSet(), keys, reason: entry.key);
      expect(entry.value.values.every((s) => s.isNotEmpty), isTrue,
          reason: entry.key);
    }
  });

  testWidgets('browser menu labels use selected locale', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        final strings = BrowserMenuStrings(context);
        return Text(strings.text('Language'));
      }),
    ));
    expect(find.text('اللغة'), findsOneWidget);
  });
}

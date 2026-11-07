import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/settings_strings.dart';
import 'package:crisp_cloud/widgets/settings_dialog.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final expectedTitles = {
    'en': 'Settings',
    'de': 'Einstellungen',
    'fr': 'Paramètres',
    'es': 'Ajustes',
    'pt': 'Definições',
    'zh': '设置',
    'ja': '設定',
    'ko': '설정',
    'ar': 'الإعدادات',
  };

  test('settings translations cover the same messages and placeholders', () {
    final translations = SettingsStrings.translations;
    final keys = translations['de']!.keys.toSet();
    expect(
        translations.keys.toSet(), expectedTitles.keys.toSet()..remove('en'));
    for (final locale in translations.keys) {
      final values = translations[locale]!;
      expect(values.keys.toSet(), keys, reason: locale);
      for (final entry in values.entries) {
        expect(entry.value, isNotEmpty, reason: '$locale: ${entry.key}');
        for (final placeholder in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(placeholder.group(0)),
              reason: '$locale: ${entry.key}');
        }
      }
    }
  });

  for (final entry in expectedTitles.entries) {
    testWidgets('settings title follows ${entry.key} locale', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(InMemorySecureStorage())],
        child: MaterialApp(
          locale: Locale(entry.key),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SettingsDialog(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == 'de') {
        expect(find.text('Schnellsuche'), findsOneWidget);
        expect(find.text('Groß-/Kleinschreibung beachten'), findsOneWidget);
      }
      if (entry.key == 'ar') {
        expect(find.text('البحث السريع'), findsOneWidget);
        expect(Directionality.of(tester.element(find.text(entry.value))),
            TextDirection.rtl);
      }
    });
  }
}

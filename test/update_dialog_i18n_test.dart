import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/update_dialog_strings.dart';
import 'package:crisp_cloud/providers/update_provider.dart';
import 'package:crisp_cloud/services/auto_update_service.dart';
import 'package:crisp_cloud/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('update strings cover all locales and preserve parameters', () {
    final translations = UpdateDialogStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
    expect(UpdateDialogStrings.forLanguage('de').available('1.2.3'),
        'Update verfügbar — 1.2.3');
  });

  final titles = {
    'en': 'Check for Updates',
    'de': 'Nach Updates suchen',
    'fr': 'Rechercher des mises à jour',
    'es': 'Buscar actualizaciones',
    'pt': 'Procurar atualizações',
    'zh': '检查更新',
    'ja': '更新を確認',
    'ko': '업데이트 확인',
    'ar': 'التحقق من التحديثات',
  };
  for (final entry in titles.entries) {
    testWidgets('update dialog renders in ${entry.key}', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          updateCheckProvider.overrideWith((ref) async => null),
          updateChannelProvider.overrideWith(
              (ref) => UpdateChannelNotifier.withValue(UpdateChannel.stable)),
          autoUpdateEnabledProvider
              .overrideWith((ref) => AutoUpdateEnabledNotifier.withValue(true)),
        ],
        child: MaterialApp(
          locale: Locale(entry.key),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: UpdateDialog()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == 'ar') {
        expect(Directionality.of(tester.element(find.text(entry.value))),
            TextDirection.rtl);
      }
    });
  }
}

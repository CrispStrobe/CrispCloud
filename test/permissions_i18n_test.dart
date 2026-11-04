import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/permissions_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/permissions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('permissions translations preserve keys and placeholders', () {
    final translations = PermissionsStrings.translations;
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
    expect(
        PermissionsStrings.forLanguage('de').format('Permissions — {name}',
            {'name': '{error}.txt', 'error': 'not a replacement'}),
        'Berechtigungen — {error}.txt');
  });

  testWidgets('unsupported-provider error is shown in the selected language',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = InMemorySecureStorage();
    final config = FilenConfigService(
        configPath: Directory.systemTemp.path, secureStorage: storage);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => AuthNotifier(ref,
            initialProvider: CloudProvider.filen,
            config: config,
            configPath: Directory.systemTemp.path,
            secureStorage: storage)),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: Consumer(builder: (context, ref, child) {
          return TextButton(
            onPressed: () => showPermissionsDialog(
                context, ref, FileItem(name: 'a.txt', isFolder: false)),
            child: const Text('Open'),
          );
        })),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Berechtigungen — a.txt'), findsOneWidget);
    expect(find.text('Berechtigungen sind nur für SFTP-Verbindungen verfügbar'),
        findsOneWidget);
  });
}

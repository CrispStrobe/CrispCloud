import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_header_strings.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:crisp_cloud/widgets/panel_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('all panel header messages exist for each language', () {
    final translations = PanelHeaderStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    for (final entry in translations.entries) {
      expect(entry.value.keys.toSet(), keys, reason: entry.key);
      expect(entry.value.values.every((s) => s.isNotEmpty), isTrue,
          reason: entry.key);
    }
  });

  testWidgets('German panel controls and commands are localized',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = InMemorySecureStorage();
    final config = FilenConfigService(
        configPath: Directory.systemTemp.path, secureStorage: storage);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        drivesProvider.overrideWith((ref) async => []),
        authProvider.overrideWith((ref) => AuthNotifier(ref,
            initialProvider: CloudProvider.filen,
            config: config,
            configPath: Directory.systemTemp.path,
            secureStorage: storage)),
      ],
      child: const MaterialApp(
        locale: Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: PanelHeader(
              side: PanelSide.local, isActive: true, showSource: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zurück'), findsOneWidget);
    expect(find.byTooltip('Pfad bearbeiten'), findsOneWidget);
    await tester.tap(find.byTooltip('Weitere Befehle'));
    await tester.pumpAndSettle();
    expect(find.text('Auswahl umkehren'), findsOneWidget);
  });
}

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/key_management_strings.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/key_management_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('German import button enables when bundle text changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final secure = InMemorySecureStorage();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => AuthNotifier(ref,
            initialProvider: CloudProvider.filen,
            config: FilenConfigService(
                configPath: '/tmp/key-i18n', secureStorage: secure),
            configPath: '/tmp/key-i18n',
            secureStorage: secure))
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
            body: Consumer(
                builder: (context, ref, _) => TextButton(
                      onPressed: () => showKeyManagementDialog(context, ref),
                      child: const Text('Open'),
                    ))),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Schlüsselverwaltung'), findsOneWidget);
    await tester.tap(find.text('Import / Wiederherstellen'));
    await tester.pumpAndSettle();
    final button =
        find.widgetWithText(ElevatedButton, 'Aus Paket wiederherstellen');
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '{}');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
  });

  testWidgets('copy feedback interpolates its label in all locales',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) => Text(KeyManagementStrings(context)
                .text('copied', {'label': 'example-key'}))),
      ));
      expect(find.textContaining('example-key'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

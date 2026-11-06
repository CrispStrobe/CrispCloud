import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/provider_settings_strings.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/provider_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('German provider settings localizes the certificate guidance',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final secure = InMemorySecureStorage();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => AuthNotifier(
              ref,
              initialProvider: CloudProvider.filen,
              config: FilenConfigService(
                  configPath: '/tmp/provider-i18n', secureStorage: secure),
              configPath: '/tmp/provider-i18n',
              secureStorage: secure,
            ))
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
            body: Consumer(
                builder: (context, ref, _) => TextButton(
                      onPressed: () => showProviderSettingsDialog(context, ref),
                      child: const Text('Open'),
                    ))),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Filen-Einstellungen'), findsOneWidget);
    expect(find.text('SSL-Zertifikate überprüfen'), findsOneWidget);
    expect(find.text('Nur bei selbstsignierten Zertifikaten deaktivieren'),
        findsOneWidget);
  });

  testWidgets('provider name is preserved across all locales', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) => Text(ProviderSettingsStrings(context).text(
                  'settings',
                  {'provider': 'ExampleProvider'},
                ))),
      ));
      expect(find.textContaining('ExampleProvider'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

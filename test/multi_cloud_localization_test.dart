import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/multi_cloud_strings.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/multi_cloud_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('German multi-cloud dialog localizes transfer guidance',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final secure = InMemorySecureStorage();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => AuthNotifier(ref,
            initialProvider: CloudProvider.filen,
            config: FilenConfigService(
                configPath: '/tmp/i18n-test', secureStorage: secure),
            configPath: '/tmp/i18n-test',
            secureStorage: secure))
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showMultiCloudDialog(context),
                      child: const Text('Open'),
                    ))),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Verbindungen'), findsOneWidget);
    await tester.tap(find.text('Übertragen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mindestens zwei Verbindungen'), findsOneWidget);
  });

  testWidgets(
      'difference descriptions interpolate both values in all languages',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) => Text(MultiCloudStrings(context).text(
                  'sizeDiff',
                  {'a': 42, 'b': 93},
                ))),
      ));
      expect(find.textContaining('42'), findsOneWidget);
      expect(find.textContaining('93'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

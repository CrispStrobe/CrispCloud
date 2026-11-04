import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/cloud_setup_strings.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/azure_connection_dialog.dart';
import 'package:crisp_cloud/widgets/b2_connection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget dialog, String language) => ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage())
      ],
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: dialog),
      ),
    );

void main() {
  testWidgets('Azure dialog shows translated validation in German',
      (tester) async {
    await tester.pumpWidget(wrap(const AzureConnectionDialog(), 'de'));
    await tester.pumpAndSettle();
    expect(find.text('Mit Azure Blob Storage verbinden'), findsOneWidget);
    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    expect(find.text('Kontoname ist erforderlich'), findsOneWidget);
  });

  testWidgets('B2 dialog shows translated validation in Arabic',
      (tester) async {
    await tester.pumpWidget(wrap(const B2ConnectionDialog(), 'ar'));
    await tester.pumpAndSettle();
    expect(find.text('الاتصال بـ Backblaze B2'), findsOneWidget);
    await tester.tap(find.text('اتصال'));
    await tester.pumpAndSettle();
    expect(find.text('معرّف مفتاح التطبيق مطلوب'), findsOneWidget);
  });

  testWidgets('result messages retain endpoint and bucket in each locale',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          final strings = CloudSetupStrings(context);
          return Column(children: [
            Text(strings.text('connected', {'endpoint': 'storage.example'})),
            Text(strings
                .text('credentialsBucket', {'bucket': 'example-bucket'})),
          ]);
        }),
      ));
      expect(find.textContaining('storage.example'), findsOneWidget);
      expect(find.textContaining('example-bucket'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

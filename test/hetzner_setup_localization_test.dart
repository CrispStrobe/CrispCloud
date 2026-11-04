import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/hetzner_setup_strings.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/hetzner_connection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(String language) => ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage())
      ],
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: HetznerConnectionDialog()),
      ),
    );

void main() {
  testWidgets('German dialog localizes username validation', (tester) async {
    await tester.pumpWidget(wrap('de'));
    await tester.pumpAndSettle();
    expect(find.text('Mit Hetzner Storage Box verbinden'), findsOneWidget);
    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    expect(find.text('Benutzername ist erforderlich (z. B. u123456)'),
        findsOneWidget);
  });

  testWidgets('Arabic dialog localizes username validation', (tester) async {
    await tester.pumpWidget(wrap('ar'));
    await tester.pumpAndSettle();
    expect(find.text('الاتصال بـ Hetzner Storage Box'), findsOneWidget);
    await tester.tap(find.text('اتصال'));
    await tester.pumpAndSettle();
    expect(find.text('اسم المستخدم مطلوب (مثل u123456)'), findsOneWidget);
  });

  testWidgets('latency appears in success message for every locale',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) => Text(
                  HetznerSetupStrings(context)
                      .text('success', {'latency': 123}),
                )),
      ));
      expect(find.textContaining('123'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

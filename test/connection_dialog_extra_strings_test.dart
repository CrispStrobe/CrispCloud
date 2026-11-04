import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/connection_dialog_extra_strings.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const titles = {
    'en': 'Verify SSH server',
    'de': 'SSH-Server überprüfen',
    'fr': 'Vérifier le serveur SSH',
    'es': 'Verificar servidor SSH',
    'pt': 'Verificar servidor SSH',
    'zh': '验证 SSH 服务器',
    'ja': 'SSH サーバーを確認',
    'ko': 'SSH 서버 확인',
    'ar': 'التحقق من خادم SSH',
  };
  for (final entry in titles.entries) {
    testWidgets('SSH verification is localized for ${entry.key}',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(entry.key),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          final strings = ConnectionDialogExtraStrings(context);
          return Scaffold(
              body: SingleChildScrollView(
                  child: Column(children: [
            Text(strings.text('verifySsh')),
            Text(strings.text('sshFingerprint', {
              'endpoint': 'example:22',
              'fingerprint': 'SHA256:abcdef',
            })),
          ])));
        }),
      ));
      expect(find.text(entry.value), findsOneWidget);
      final instructions =
          tester.widgetList<Text>(find.byType(Text)).last.data!;
      expect(instructions, contains('example:22'));
      expect(instructions, contains('SHA256:abcdef'));
      expect(instructions, isNot(contains('{')));
    });
  }
  testWidgets('every provider has localized onboarding for every locale',
      (tester) async {
    for (final language in titles.keys) {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          final strings = ConnectionDialogExtraStrings(context);
          return SingleChildScrollView(
              child: Column(children: [
            for (final provider in CloudProvider.values)
              Text(strings.text(
                  'provider${provider.name[0].toUpperCase()}${provider.name.substring(1)}')),
          ]));
        }),
      ));
      expect(find.byType(Text), findsNWidgets(CloudProvider.values.length));
      expect(tester.takeException(), isNull);
    }
  });
}

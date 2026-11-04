import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/connection_dialog_extra_strings.dart';
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
          return Scaffold(body: SingleChildScrollView(child: Column(children: [
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
}

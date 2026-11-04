import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/terminal_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SSH host trust message retains host and fingerprint', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(
          TerminalStrings(context).trust('example.test:22', 'SHA256:abc'),
        )),
      ));
      expect(find.textContaining('example.test:22'), findsOneWidget);
      expect(find.textContaining('SHA256:abc'), findsOneWidget);
      expect(find.textContaining('{fingerprint}'), findsNothing);
    }
  });
}

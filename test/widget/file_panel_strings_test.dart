import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_panel_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('file panel result counts are interpolated in every locale', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(
          FilePanelStrings(context).value('results', 42),
        )),
      ));
      expect(find.textContaining('42'), findsOneWidget);
      expect(find.textContaining('{n}'), findsNothing);
    }
  });
}

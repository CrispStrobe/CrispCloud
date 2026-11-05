import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_editor_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editor save errors preserve details in each locale', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(
          FileEditorStrings(context).value('saveError', 'disk-full'),
        )),
      ));
      expect(find.textContaining('disk-full'), findsOneWidget);
      expect(find.textContaining('{n}'), findsNothing);
    }
  });
}

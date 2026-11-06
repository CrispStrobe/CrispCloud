import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_operations_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('archive errors interpolate details for supported languages',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(
          FileOperationsStrings(context).value('zipError', 'disk-full'),
        )),
      ));
      expect(find.textContaining('disk-full'), findsOneWidget);
      expect(find.textContaining('{n}'), findsNothing);
    }
  });

  testWidgets('wipe warning includes the item count in the selected language',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Text(
        FileOperationsStrings(context).value('wipeWarning', 2),
      )),
    ));
    expect(find.textContaining('2 Elemente'), findsOneWidget);
    expect(find.textContaining('nicht rückgängig'), findsOneWidget);
  });
}

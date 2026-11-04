import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/batch_rename_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/batch_rename_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('German batch rename updates its preview', (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
          body: Consumer(
              builder: (context, ref, _) => BatchRenameDialog(
                    parentRef: ref,
                    side: PanelSide.local,
                    files: [
                      FileItem(name: 'one.txt', isFolder: false),
                      FileItem(name: 'two.txt', isFolder: false)
                    ],
                  ))),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Stapelumbenennung (2 Dateien)'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Suchen'), 'one');
    await tester.enterText(
        find.widgetWithText(TextField, 'Ersetzen durch'), 'new');
    await tester.pump();
    expect(find.text('new.txt'), findsOneWidget);
  });

  testWidgets('file counts interpolate in all locales', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) =>
                Text(BatchRenameStrings(context).text('title', {'count': 42}))),
      ));
      expect(find.textContaining('42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/duplicate_finder_strings.dart';
import 'package:crisp_cloud/widgets/duplicate_finder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('German duplicate finder explains local scans', (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
          body: Consumer(
              builder: (context, ref, _) => TextButton(
                    onPressed: () => showDuplicateFinderDialog(context, ref),
                    child: const Text('Open'),
                  ))),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Duplikatfinder'), findsOneWidget);
    expect(find.textContaining('MD5-Prüfsummen'), findsOneWidget);
  });

  testWidgets('duplicate summaries retain counts and sizes in all locales',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
            builder: (context) => Text(DuplicateFinderStrings(context).text(
                  'summary',
                  {'count': 12, 'groups': 34, 'size': '56 MB'},
                ))),
      ));
      for (final value in ['12', '34', '56 MB']) {
        expect(find.textContaining(value), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });
}

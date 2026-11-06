import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/page_navigation_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page controls have localized labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => IconButton(
        tooltip: PageNavigationStrings(context).text('next'),
        icon: const Icon(Icons.chevron_right),
        onPressed: () {},
      )),
    ));
    expect(find.byTooltip('Página siguiente'), findsOneWidget);
  });
}

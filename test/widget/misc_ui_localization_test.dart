import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/misc_ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy score and accessibility labels use locale', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Column(children: [
        Text(MiscUiStrings(context).privacyLevel(85)),
        IconButton(
          tooltip: MiscUiStrings(context).text('forward'),
          icon: const Icon(Icons.arrow_forward),
          onPressed: () {},
        ),
      ])),
    ));
    expect(find.text('Buena'), findsOneWidget);
    expect(find.byTooltip('Adelante'), findsOneWidget);
  });
}

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/streaming_view_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('streaming index limit is localized without losing its size',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Text(
        StreamingViewStrings(context).indexed(64),
      )),
    ));
    expect(find.textContaining('indexado hasta 64 MB'), findsOneWidget);
  });
}

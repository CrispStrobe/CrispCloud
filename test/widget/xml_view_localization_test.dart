import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/widgets/xml_tree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('invalid XML reports an error in the selected language', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: XmlTreeView(xml: '<broken>')),
    ));
    expect(find.textContaining('Error de análisis XML:'), findsOneWidget);
    expect(find.textContaining('Código fuente'), findsOneWidget);
  });
}

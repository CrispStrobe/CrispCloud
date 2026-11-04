import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/widgets/internal_viewer_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty text viewer follows the selected locale', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MonoLineListView(lines: [], fontScale: 1),
    ));
    expect(find.text('Archivo vacío'), findsOneWidget);
  });
}

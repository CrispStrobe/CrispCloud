import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/widgets/diff_viewer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('version comparison uses the selected locale', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showDiffViewerFromContent(context,
            leftContent: 'one', rightContent: 'two'),
        child: const Text('Show'),
      ))),
    ));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Comparación de versiones'), findsOneWidget);
    expect(find.text('Izquierda'), findsOneWidget);
    expect(find.text('Derecha'), findsOneWidget);
  });
}

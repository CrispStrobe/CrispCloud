import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/widgets/panel_tab_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tab context menu follows the selected language', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: PanelTabBar(
            tabs: [
              PanelTab(id: 'a', path: '/one'),
              PanelTab(id: 'b', path: '/two'),
            ],
            activeTabId: 'a',
            onTabSelected: (_) {},
            onTabClosed: (_) {},
            onNewTab: () {},
            onTabRenamed: (_, __) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('one'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Renombrar pestaña…'), findsOneWidget);
    await tester.tap(find.text('Renombrar pestaña…'));
    await tester.pumpAndSettle();
    expect(find.text('Renombrar pestaña'), findsOneWidget);
    expect(find.text('Título de pestaña'), findsOneWidget);
    expect(find.text('Usar nombre de carpeta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

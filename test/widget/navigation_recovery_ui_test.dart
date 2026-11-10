import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/navigation_strings.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/widgets/panel_history_button.dart';
import 'package:crisp_cloud/widgets/panel_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workspace_fixture.dart';

void main() {
  testWidgets('history menu labels the source and opens the selected route', (tester) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await panel.navigateToPath('/one');
    await panel.navigateToPath('/two');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: PanelHistoryButton(panel: panel),
    )));
    await tester.tap(find.byTooltip('Location history'));
    await tester.pumpAndSettle();
    expect(find.text('/one'), findsOneWidget);
    expect(find.textContaining('Memory'), findsWidgets);
    await tester.tap(find.text('/one'));
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/one');
    expect(panel.canNavigateForward, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a history menu cannot act on a tab selected after it opened', (tester) async {
    final harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await panel.navigateToPath('/one');
    final saved = await panel.exportTabs();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: PanelHistoryButton(panel: panel),
    )));
    await tester.tap(find.byTooltip('Location history'));
    await tester.pumpAndSettle();
    await panel.restoreTabs([{...saved.single, 'path': '/other', 'navigation': null}]);
    final secondTab = panel.activeTabId;
    await tester.tap(find.text('/'));
    await tester.pumpAndSettle();
    expect(panel.activeTabId, secondTab);
    expect(panel.currentPath, '/other');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab menu exposes enabled and disabled recovery without closing the current tab', (tester) async {
    var reopened = 0;
    Widget app(bool available) => MaterialApp(home: Scaffold(body: Column(children: [
      PanelTabBar(
        tabs: [PanelTab(id: 'first', path: '/documents')],
        activeTabId: 'first', onTabSelected: (_) {}, onTabClosed: (_) {}, onNewTab: () {},
        onReopenClosedTab: () => reopened++, canReopenClosedTab: available,
      ),
    ])));
    await tester.pumpWidget(app(false));
    await tester.longPress(find.text('documents'));
    await tester.pumpAndSettle();
    final disabled = tester.widget<PopupMenuItem<String>>(
      find.ancestor(of: find.text('Reopen closed tab'), matching: find.byType(PopupMenuItem<String>)),
    );
    expect(disabled.enabled, isFalse);
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(true));
    await tester.longPress(find.text('documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen closed tab'));
    await tester.pumpAndSettle();
    expect(reopened, 1);
    expect(find.text('documents'), findsOneWidget);
  });

  testWidgets('navigation controls and recovery failures are localized in every app language', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      final strings = NavigationStrings(context);
      for (final key in ['history', 'reopen', 'older', 'unavailable']) {
        expect(strings.text(key), isNotEmpty);
        expect(strings.text(key), isNot(key));
      }
      expect(localizedPanelError(context, AppError('fallback', code: PanelErrorCode.navigationUnavailable)),
          strings.text('unavailable'));
      expect(localizedPanelError(context, AppError('fallback', code: PanelErrorCode.navigationFailed,
        arguments: {'error': 'provider-detail-42'})), contains('provider-detail-42'));
      if (locale.languageCode != 'en') {
        expect(strings.text('history'), isNot('Location history'));
        expect(strings.text('reopen'), isNot('Reopen closed tab'));
      }
    }
  });
}

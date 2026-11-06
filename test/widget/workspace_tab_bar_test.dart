import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/widgets/panel_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(WidgetTester tester, PanelTabBar bar) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Column(children: [bar])),
    ),
  );

  testWidgets('one tab still exposes new-tab and workspace actions', (
    tester,
  ) async {
    var added = 0;
    var openedWorkspace = 0;
    await mount(
      tester,
      PanelTabBar(
        tabs: [PanelTab(id: 'first', path: '/documents')],
        activeTabId: 'first',
        onTabSelected: (_) {},
        onTabClosed: (_) {},
        onNewTab: () => added++,
        onWorkspace: () => openedWorkspace++,
      ),
    );
    expect(find.text('documents'), findsOneWidget);
    await tester.tap(find.byTooltip('New tab'));
    await tester.tap(find.byTooltip('Workspaces, bookmarks and views'));
    expect(added, 1);
    expect(openedWorkspace, 1);
  });

  testWidgets('touch context menu applies a lock to the chosen inactive tab', (
    tester,
  ) async {
    (String, TabLockMode)? changed;
    await mount(
      tester,
      PanelTabBar(
        tabs: [
          PanelTab(id: 'first', path: '/documents'),
          PanelTab(id: 'second', path: '/photos'),
        ],
        activeTabId: 'first',
        onTabSelected: (_) {},
        onTabClosed: (_) {},
        onNewTab: () {},
        onTabLockChanged: (id, mode) => changed = (id, mode),
      ),
    );
    await tester.longPress(find.text('photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open other locations in new tabs'));
    await tester.pumpAndSettle();
    expect(changed, ('second', TabLockMode.newTab));
  });

  testWidgets(
    'duplicate action passes the clicked tab instead of adding the active path',
    (tester) async {
      String? duplicated;
      var added = false;
      await mount(
        tester,
        PanelTabBar(
          tabs: [
            PanelTab(id: 'first', path: '/documents'),
            PanelTab(id: 'second', path: '/photos'),
          ],
          activeTabId: 'first',
          onTabSelected: (_) {},
          onTabClosed: (_) {},
          onNewTab: () => added = true,
          onTabDuplicated: (id) => duplicated = id,
        ),
      );
      await tester.longPress(find.text('photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate this tab'));
      await tester.pumpAndSettle();
      expect(duplicated, 'second');
      expect(added, isFalse);
    },
  );

  testWidgets(
    'tab title editor supports persistent custom and automatic names',
    (tester) async {
      (String, String)? renamed;
      await mount(
        tester,
        PanelTabBar(
          tabs: [PanelTab(id: 'first', path: '/documents')],
          activeTabId: 'first',
          onTabSelected: (_) {},
          onTabClosed: (_) {},
          onNewTab: () {},
          onTabRenamed: (id, name) => renamed = (id, name),
        ),
      );
      await tester.longPress(find.text('documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename tab…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Project files');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(renamed, ('first', 'Project files'));
      expect(tester.takeException(), isNull);
      await tester.longPress(find.text('documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename tab…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use folder name'));
      await tester.pumpAndSettle();
      expect(renamed, ('first', ''));
    },
  );

  testWidgets('protected tab closure requires the displayed confirmation', (
    tester,
  ) async {
    var forced = false;
    await mount(
      tester,
      PanelTabBar(
        tabs: [
          PanelTab(id: 'first', path: '/documents', isPinned: true),
          PanelTab(id: 'second', path: '/photos'),
        ],
        activeTabId: 'first',
        onTabSelected: (_) {},
        onTabClosed: (_) {},
        onNewTab: () {},
        onTabForceClosed: (_) => forced = true,
      ),
    );
    await tester.longPress(find.text('documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close protected tab…'));
    await tester.pumpAndSettle();
    expect(find.text('Close "documents" at /documents?'), findsOneWidget);
    expect(forced, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(forced, isFalse);
    await tester.longPress(find.text('documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close protected tab…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close tab'));
    await tester.pumpAndSettle();
    expect(forced, isTrue);
  });

  testWidgets('long titles and controls fit a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(
      tester,
      PanelTabBar(
        tabs: [
          PanelTab(
            id: 'first',
            path: '/documents',
            customLabel: 'A very long project title with many words',
            lockMode: TabLockMode.newTab,
          ),
          PanelTab(id: 'second', path: '/photos'),
        ],
        activeTabId: 'first',
        activeSelectionCount: 100,
        onTabSelected: (_) {},
        onTabClosed: (_) {},
        onNewTab: () {},
        onTabReordered: (_, _) {},
        onWorkspace: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('New tab'), findsOneWidget);
    expect(find.byTooltip('Workspaces, bookmarks and views'), findsOneWidget);
  });
}

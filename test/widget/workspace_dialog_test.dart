import 'package:crisp_cloud/models/file_view_configuration.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_provider.dart';
import 'package:crisp_cloud/providers/bookmarks_provider.dart';
import 'package:crisp_cloud/providers/workspace_provider.dart';
import 'package:crisp_cloud/widgets/file_view_editor_dialog.dart';
import 'package:crisp_cloud/widgets/workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workspace_fixture.dart';

void main() {
  late WorkspaceTestHarness harness;
  setUp(() async {
    harness = await WorkspaceTestHarness.create();
  });
  tearDown(() => harness.dispose());

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'legacy bookmark requires explicit account binding before it can open',
    (tester) async {
      final bookmarks = harness.container.read(bookmarksProvider);
      await bookmarks.add('Older reports', '/one', PanelSide.remote);
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      final storage = panel.captureCurrentOrigin().storageReference;
      await mount(
        tester,
        const WorkspaceDialog(side: PanelSide.remote, initialSection: 1),
      );
      await reveal(tester, find.text('Bind original source…'));
      expect(find.text('Open in this pane'), findsNothing);
      await tester.tap(find.text('Bind original source…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('/one'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(bookmarks.bookmarks.single.isBound, isFalse);
      await tester.tap(find.text('Bind original source…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bind to this source'));
      await tester.pumpAndSettle();
      expect(bookmarks.bookmarks.single.storage, storage);
      await reveal(tester, find.text('Open in this pane'));
      await tester.tap(find.text('Open in this pane'));
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/one');
      expect(panel.captureCurrentOrigin().storageReference, storage);
    },
  );

  testWidgets(
    'disconnect while confirming an older bookmark cannot bind a replacement source',
    (tester) async {
      final bookmarks = harness.container.read(bookmarksProvider);
      await bookmarks.add('Older reports', '/one', PanelSide.remote);
      await mount(
        tester,
        const WorkspaceDialog(side: PanelSide.remote, initialSection: 1),
      );
      await reveal(tester, find.text('Bind original source…'));
      await tester.tap(find.text('Bind original source…'));
      await tester.pumpAndSettle();
      harness.cloud.current = false;
      await tester.tap(find.text('Bind to this source'));
      await tester.pumpAndSettle();
      expect(bookmarks.bookmarks.single.isBound, isFalse);
      expect(
        find.textContaining('chosen account disconnected'),
        findsOneWidget,
      );
      expect(
        harness.container.read(panelProvider(PanelSide.remote)).currentPath,
        '/',
      );
    },
  );

  testWidgets(
    'manager saves and reopens both pane locations by a named group',
    (tester) async {
      final remote = harness.container.read(panelProvider(PanelSide.remote));
      await remote.navigateToPath('/one');
      await mount(tester, const WorkspaceDialog(side: PanelSide.remote));
      await tester.tap(find.text('Save current tab group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-name')),
        'Project work',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final catalog = await harness.container
          .read(workspaceStoreProvider)
          .load();
      expect(catalog.groups.single.right.tabs.single.path, '/one');
      expect(find.text('Project work'), findsOneWidget);
      await remote.navigateToPath('/');
      await tester.ensureVisible(find.text('Append tabs'));
      await tester.tap(find.text('Append tabs'));
      await tester.pumpAndSettle();
      expect(remote.currentPath, '/one');
      expect(remote.tabs, hasLength(2));
    },
  );

  testWidgets(
    'profile editor blocks invalid widths and returns ordered metadata columns',
    (tester) async {
      FileViewConfiguration? result;
      await mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<FileViewConfiguration>(
                context: context,
                builder: (_) =>
                    FileViewEditorDialog(initial: FileViewConfiguration()),
              );
            },
            child: const Text('Edit'),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add column'));
      await tester.tap(find.text('Add column'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Column title'),
        'Rating',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Metadata field'),
        'rating',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      final width = find.byKey(const ValueKey('column-width-metadata'));
      await tester.ensureVisible(width);
      await tester.enterText(width, 'invalid');
      await tester.tap(find.byKey(const ValueKey('apply-view')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('24–600'), findsOneWidget);
      await tester.enterText(width, '84');
      await tester.ensureVisible(find.byTooltip('Move Rating up'));
      await tester.tap(find.byTooltip('Move Rating up'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('apply-view')));
      await tester.pumpAndSettle();
      expect(result!.columns.map((column) => column.label), [
        'Size',
        'Date',
        'Rating',
        'Ext',
      ]);
      expect(result!.columns[2].metadataKey, 'rating');
      expect(result!.widths['metadata'], 84);
    },
  );

  testWidgets('view profile creation persists and applies to the active tab', (
    tester,
  ) async {
    await mount(
      tester,
      const WorkspaceDialog(side: PanelSide.remote, initialSection: 2),
    );
    await tester.tap(find.text('Create view profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-view')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workspace-name')),
      'Detailed',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final profile =
        (await harness.container.read(workspaceStoreProvider).load())
            .profiles
            .single;
    expect(profile.name, 'Detailed');
    expect(
      harness.container
          .read(panelProvider(PanelSide.remote))
          .activeTab!
          .viewProfileId,
      profile.id,
    );
    expect(find.text('Apply to this pane'), findsOneWidget);
  });

  testWidgets(
    'invalid import stays in review and leaves stored settings intact',
    (tester) async {
      await mount(tester, const WorkspaceDialog(side: PanelSide.remote));
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-import-text')),
        '{"format":"other"}',
      );
      await tester.tap(find.byKey(const ValueKey('rename-import-apply')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unsupported workspace exchange format'),
        findsOneWidget,
      );
      expect(
        (await harness.container.read(workspaceStoreProvider).load()).groups,
        isEmpty,
      );
    },
  );

  testWidgets(
    'workspace and editor remain usable on narrow screens with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(340, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(
        tester,
        const WorkspaceDialog(side: PanelSide.remote, initialSection: 2),
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Create view profile'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(TabBarView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create view profile'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('column-width-size')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('column-width-size')),
        '80',
      );
      await tester.tap(find.byKey(const ValueKey('apply-view')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

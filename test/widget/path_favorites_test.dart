import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/widgets/path_favorites.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workspace_fixture.dart';

void main() {
  late WorkspaceTestHarness harness;
  late BookmarksNotifier bookmarks;

  Future<void> prepare(WidgetTester tester) async {
    // Initialize preferences and providers inside the widget test's async zone.
    // A global setUp leaves cached preference Futures in a different zone.
    harness = await WorkspaceTestHarness.create();
    bookmarks = harness.container.read(bookmarksProvider);
    await bookmarks.ready;
  }

  tearDown(() => harness.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: PathFavoritesButton(side: PanelSide.local),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: PathFavoritesButton(side: PanelSide.remote),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, PanelSide side) async {
    await tester.tap(find.byKey(ValueKey('path-favorites-${side.name}')));
    await tester.pumpAndSettle();
  }

  Future<void> editor(WidgetTester tester) async {
    await menu(tester, PanelSide.remote);
    await tester.tap(find.text('Edit path favorites…'));
    await tester.pumpAndSettle();
  }

  Future<void> add(
    String name,
    String path, {
    PanelSide side = PanelSide.remote,
  }) => bookmarks.add(
    name,
    path,
    side,
    storage: harness.container
        .read(panelProvider(PanelSide.remote))
        .captureCurrentOrigin()
        .storageReference,
  );

  Finder card(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(Card));

  testWidgets(
    'both star menus open a favorite in the pane that owns the menu',
    (tester) async {
      await prepare(tester);
      final left = harness.container.read(panelProvider(PanelSide.local));
      final right = harness.container.read(panelProvider(PanelSide.remote));
      await add('Cloud reports', '/one', side: PanelSide.local);
      final source = bookmarks.bookmarks.single.storage;
      await mount(tester);
      expect(find.text('*'), findsNWidgets(2));
      await menu(tester, PanelSide.remote);
      expect(find.text('/one'), findsOneWidget);
      expect(find.textContaining('workspace@example.test'), findsOneWidget);
      await tester.tap(find.text('Cloud reports'));
      await tester.pumpAndSettle();
      expect(right.currentPath, '/one');
      expect(left.currentPath, '/');
      expect(right.captureCurrentOrigin().storageReference, source);
      expect(harness.container.read(activePanelProvider), PanelSide.remote);

      await menu(tester, PanelSide.local);
      await tester.tap(find.text('Cloud reports'));
      await tester.pumpAndSettle();
      expect(left.currentPath, '/one');
      expect(left.captureCurrentOrigin().storageReference, source);
      expect(harness.container.read(activePanelProvider), PanelSide.local);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an open menu cannot navigate a pane that has since changed', (
    tester,
  ) async {
    await prepare(tester);
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await add('Reports', '/one');
    await mount(tester);
    await menu(tester, PanelSide.remote);
    await panel.navigateToPath('/other');
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/other');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adding a favorite captures the source and supports a custom path',
    (tester) async {
      await prepare(tester);
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      await panel.navigateToPath('/one');
      final original = panel.captureCurrentOrigin().storageReference;
      await mount(tester);
      await menu(tester, PanelSide.remote);
      await tester.tap(find.text('Add current path…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('path-favorite-name')),
        'Archive copies',
      );
      await tester.enterText(
        find.byKey(const ValueKey('path-favorite-path')),
        '/backup',
      );
      // The form has its own captured source; later navigation must not retarget it.
      await panel.navigateToPath('/other');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(bookmarks.bookmarks.single.name, 'Archive copies');
      expect(bookmarks.bookmarks.single.path, '/backup');
      expect(bookmarks.bookmarks.single.storage, original);
      final restored = BookmarksNotifier();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(
        restored.bookmarks.single.toJson(),
        bookmarks.bookmarks.single.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor validates paths and never overwrites a duplicate on retry',
    (tester) async {
      await prepare(tester);
      await add('One', '/one');
      await add('Two', '/two');
      final originalSource = bookmarks.bookmarks.first.storage;
      await mount(tester);
      await editor(tester);
      await tester.tap(
        find.descendant(
          of: card('One'),
          matching: find.byTooltip('Edit favorite'),
        ),
      );
      await tester.pumpAndSettle();
      final path = find.byKey(const ValueKey('path-favorite-path'));
      await tester.enterText(path, 'relative');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an absolute path without null characters.'),
        findsOneWidget,
      );
      expect(bookmarks.bookmarks.first.path, '/one');

      await tester.enterText(path, '/two');
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(bookmarks.bookmarks.map((item) => item.name), ['One', 'Two']);
        expect(bookmarks.bookmarks.map((item) => item.path), ['/one', '/two']);
      }
      await tester.enterText(
        find.byKey(const ValueKey('path-favorite-name')),
        'Renamed',
      );
      await tester.enterText(path, '/three');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(bookmarks.bookmarks.first.name, 'Renamed');
      expect(bookmarks.bookmarks.first.path, '/three');
      expect(bookmarks.bookmarks.first.storage, originalSource);
      expect(bookmarks.bookmarks.last.name, 'Two');
      expect(bookmarks.bookmarks.last.path, '/two');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor reorders, filters and removes saved favorites', (
    tester,
  ) async {
    await prepare(tester);
    await add('Alpha', '/one');
    await add('Beta', '/two');
    await mount(tester);
    await editor(tester);
    final moveUp = find.descendant(
      of: card('Beta'),
      matching: find.byTooltip('Move up'),
    );
    await tester.ensureVisible(moveUp);
    await tester.tap(moveUp);
    await tester.pumpAndSettle();
    expect(bookmarks.bookmarks.map((item) => item.name), ['Beta', 'Alpha']);
    await tester.enterText(
      find.byKey(const ValueKey('path-favorites-filter')),
      'Alpha',
    );
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    final remove = find.descendant(
      of: card('Alpha'),
      matching: find.byTooltip('Remove'),
    );
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(bookmarks.bookmarks.single.name, 'Beta');
    expect(find.text('No matching favorites.'), findsOneWidget);
    final restored = BookmarksNotifier();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.bookmarks.single.name, 'Beta');
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy bookmarks require explicit binding and remain editable', (
    tester,
  ) async {
    await prepare(tester);
    await bookmarks.add('Legacy', '/one', PanelSide.remote);
    await mount(tester);
    await menu(tester, PanelSide.remote);
    final item = tester.widget<PopupMenuItem<Object>>(
      find.ancestor(
        of: find.text('Legacy'),
        matching: find.byType(PopupMenuItem<Object>),
      ),
    );
    expect(item.enabled, isFalse);
    expect(find.text('Original source not set'), findsOneWidget);
    await tester.tap(find.text('Edit path favorites…'));
    await tester.pumpAndSettle();
    expect(find.text('Bind original source…'), findsOneWidget);
    expect(find.byTooltip('Edit favorite'), findsOneWidget);
    expect(bookmarks.bookmarks.single.isBound, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'archives retain the menu without saving virtual paths as favorites',
    (tester) async {
      await prepare(tester);
      final bytes = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('item.txt', 1, [65])),
      );
      harness.cloud.put('/bundle.zip', bytes);
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      await tester.runAsync(
        () => panel.enterArchive(
          panel.filteredFiles!.firstWhere((file) => file.name == 'bundle.zip'),
        ),
      );
      expect(panel.isInArchive, isTrue);
      await mount(tester);
      await menu(tester, PanelSide.remote);
      final item = tester.widget<PopupMenuItem<Object>>(
        find.ancestor(
          of: find.text('Add current path…'),
          matching: find.byType(PopupMenuItem<Object>),
        ),
      );
      expect(item.enabled, isFalse);
      expect(find.text('Edit path favorites…'), findsOneWidget);
      expect(bookmarks.bookmarks, isEmpty);
      await tester.runAsync(panel.navigateUpArchive);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:convert';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/widgets/path_favorites.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workspace_fixture.dart';

void main() {
  late WorkspaceTestHarness harness;
  late BookmarksNotifier store;
  late StorageReference source;

  Future<void> prepare(WidgetTester tester) async {
    harness = await WorkspaceTestHarness.create();
    addTearDown(harness.dispose);
    store = harness.container.read(bookmarksProvider);
    await store.ready;
    source = harness.container
        .read(panelProvider(PanelSide.remote))
        .captureCurrentOrigin()
        .storageReference;
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> add(String name, String path, {String group = ''}) =>
      store.add(name, path, PanelSide.remote, storage: source, group: group);

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: PathFavoritesButton(side: PanelSide.remote)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('path-favorites-remote')));
    await tester.pumpAndSettle();
  }

  Future<void> editor(WidgetTester tester) async {
    await menu(tester);
    await tester.tap(find.text('Edit path favorites…'));
    await tester.pumpAndSettle();
  }

  Future<void> group(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> importPreview(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(const ValueKey('path-favorites-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-import-text')),
      text,
    );
    await tester.tap(find.byKey(const ValueKey('rename-import-apply')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'picker combines group and word search; Enter opens its pane only',
    (tester) async {
      await prepare(tester);
      await add('Reports', '/one', group: 'Work');
      await add('Archive', '/two', group: 'Work');
      await add('Photos', '/home', group: 'Personal');
      await mount(tester);
      await menu(tester);
      await group(tester, 'Work');
      expect(find.text('Photos'), findsNothing);
      expect(find.text('Reports'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('path-favorites-search')),
        'work /one',
      );
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Reports'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        harness.container.read(panelProvider(PanelSide.remote)).currentPath,
        '/one',
      );
      expect(
        harness.container.read(panelProvider(PanelSide.local)).currentPath,
        '/',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renaming and removing a group keeps its favorites and sources', (
    tester,
  ) async {
    await prepare(tester);
    await add('Reports', '/one', group: 'Work');
    await add('Archive', '/two', group: 'Work');
    final identities = store.bookmarks.map((item) => item.identity).toList();
    await mount(tester);
    await editor(tester);
    await group(tester, 'Work');
    for (final name in ['Projects', '']) {
      await tester.tap(find.byTooltip('Rename or remove group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('path-favorites-rename-group')),
        name,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.bookmarks.map((item) => item.group), [name, name]);
    }
    expect(store.bookmarks.map((item) => item.identity), identities);
    expect(store.bookmarks.map((item) => item.storage), [source, source]);
    expect(store.bookmarks, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'import preview can be cancelled; merge preserves unknown accounts and skips duplicates',
    (tester) async {
      await prepare(tester);
      await add('Keep this name', '/one', group: 'Original');
      final foreign = StorageReference(
        kind: source.kind,
        provider: source.provider,
        accountKey: 'different-account',
        root: source.root,
      );
      final text = jsonEncode({
        'format': 'crispcloud.bookmarks',
        'version': 3,
        'bookmarks': [
          Bookmark(
            name: 'Do not overwrite',
            path: '/one',
            side: PanelSide.local,
            storage: source,
            group: 'Imported',
          ).toJson(),
          Bookmark(
            name: 'Unavailable account',
            path: '/one',
            side: PanelSide.remote,
            storage: foreign,
            group: 'Imported',
          ).toJson(),
        ],
      });
      await mount(tester);
      await editor(tester);
      await importPreview(tester, text);
      expect(find.text('Review favorites import'), findsOneWidget);
      expect(find.text('New: 1'), findsOneWidget);
      expect(find.text('Duplicates skipped: 1'), findsOneWidget);
      expect(find.text('Unavailable sources: 1'), findsOneWidget);
      expect(store.bookmarks, hasLength(1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.bookmarks, hasLength(1));
      await importPreview(tester, text);
      await tester.tap(find.byKey(const ValueKey('path-favorites-merge')));
      await tester.pumpAndSettle();
      expect(store.bookmarks, hasLength(2));
      expect(store.bookmarks.first.name, 'Keep this name');
      expect(store.bookmarks.first.group, 'Original');
      expect(store.bookmarks.last.storage, foreign);
      expect(store.bookmarks.last.group, 'Imported');
      expect(
        harness.container.read(panelProvider(PanelSide.remote)).currentPath,
        '/',
      );
      expect(harness.cloud.downloads, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await menu(tester);
      final unavailable = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Unavailable account'),
          matching: find.byType(ListTile),
        ),
      );
      expect(unavailable.onTap, isNull);
      expect(unavailable.enabled, isFalse);
      expect(
        find.text(
          'Connect the original storage account to open this favorite.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid import never opens merge and export waits for explicit copy',
    (tester) async {
      await prepare(tester);
      await add('Reports', '/one', group: 'Work');
      final copies = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await mount(tester);
      await editor(tester);
      await importPreview(tester, '{"password":"not-a-favorites-export"}');
      expect(find.text('Review favorites import'), findsNothing);
      expect(find.byKey(const ValueKey('path-favorites-merge')), findsNothing);
      expect(store.bookmarks, hasLength(1));
      expect(copies, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('path-favorites-export')));
      await tester.pumpAndSettle();
      final jsonText = tester
          .widget<TextField>(find.byKey(const ValueKey('rename-import-text')))
          .controller!
          .text;
      final decoded = jsonDecode(jsonText) as Map;
      expect(decoded['version'], 3);
      expect(
        (decoded['bookmarks'] as List).single,
        store.bookmarks.single.toJson(),
      );
      expect(copies, isEmpty);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copies, [jsonText]);
      expect(tester.takeException(), isNull);
    },
  );
}

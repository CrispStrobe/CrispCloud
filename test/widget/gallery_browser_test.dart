import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/gallery_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/file_grid_view.dart';
import 'package:crisp_cloud/widgets/file_view_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/gallery-test';
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Cloud extends Fake implements CloudStorageClient {
  @override
  bool get isAuthenticated => false;
  @override
  String get providerName => 'Test';
  @override
  String? get userId => null;
  @override
  String? get bucketId => null;
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final CloudStorageClient client = _Cloud();
  @override
  bool get isConnected => false;
  @override
  String? get userEmail => null;
  @override
  String get providerName => 'Test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late PanelNotifier panel;
  late List<FileItem> files;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        localFileServiceProvider.overrideWithValue(_Local()),
        authProvider.overrideWith((_) => _Auth()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.local));
    await panel.refresh();
    files = [
      FileItem(name: '..', path: '/', isFolder: true),
      FileItem(
        name: 'photo10.raw',
        path: '/gallery-test/photo10.raw',
        isFolder: false,
      ),
      FileItem(
        name: 'notes.txt',
        path: '/gallery-test/notes.txt',
        isFolder: false,
      ),
      FileItem(
        name: 'photo2.raw',
        path: '/gallery-test/photo2.raw',
        isFolder: false,
      ),
      FileItem(
        name: 'photo3.raw',
        path: '/gallery-test/photo3.raw',
        isFolder: false,
      ),
    ];
    panel.showSearchResults(files);
    // File-list ingestion binds fresh rendered rows to their original source.
    // Commands accept those exact rows rather than the pre-ingestion fixtures.
    files = [FileItem(name: '..', path: '/', isFolder: true), ...panel.files!];
  });
  tearDown(() => container.dispose());

  Future<void> mount(
    WidgetTester tester, {
    bool tiles = false,
    double width = 700,
  }) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: Consumer(
                builder: (context, ref, _) => FileGridView(
                  side: PanelSide.local,
                  files:
                      ref.watch(panelProvider(PanelSide.local)).filteredFiles ??
                      [],
                  scrollController: scroll,
                  galleryOnly: !tiles,
                  tileLayout: tiles,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'gallery hides documents and Select all selects only visible images',
    (tester) async {
      await mount(tester);
      expect(find.text('notes.txt'), findsNothing);
      await tester.tap(find.text('photo2.raw'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(panel.selection.map((f) => f.name).toSet(), {
        'photo2.raw',
        'photo3.raw',
        'photo10.raw',
      });
      expect(panel.selection.any((f) => f.name == '..'), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'shift range follows natural visual order, excluding hidden files',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('photo2.raw'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('photo3.raw'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(panel.selection.map((f) => f.name).toSet(), {
        'photo2.raw',
        'photo3.raw',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'custom filter keys do not retain an unavailable file action guard',
    (tester) async {
      await mount(tester);
      // Search rows cannot use side-routed file operations. Rebinding their
      // former keys must still allow commands that do not mutate files.
      expect(panel.showingSearchResults, isTrue);
      for (final key in [LogicalKeyboardKey.f2, LogicalKeyboardKey.f5]) {
        await container
            .read(shortcutBindingsProvider.notifier)
            .setBinding(
              ShortcutAction.filter,
              ShortcutBinding(key: key.keyLabel),
            );
        await tester.tap(find.text('photo2.raw'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(panel.listFocusNode.hasFocus, isTrue);
        await tester.sendKeyEvent(key);
        await tester.pump();
        final input = tester.widget<TextField>(
          find.byKey(const ValueKey('gallery-search-local')),
        );
        expect(input.focusNode!.hasFocus, isTrue);
        expect(find.byType(SnackBar), findsNothing);
        expect(panel.renamingItem, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('held gallery Select All runs only on its initial press', (
    tester,
  ) async {
    await container
        .read(shortcutBindingsProvider.notifier)
        .setBinding(ShortcutAction.selectAll, const ShortcutBinding(key: 'F9'));
    await mount(tester);
    await tester.tap(find.text('photo2.raw'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    expect(panel.selection, hasLength(3));
    // A later selection update must not be overwritten by OS key repeats.
    panel.clearSelection();
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(panel.selection, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('gallery keys respect terminal focus ownership', (tester) async {
    await mount(tester);
    await tester.tap(find.text('photo2.raw'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final cursor = panel.cursorItem;
    final selected = panel.selection.toSet();
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(panel.cursorItem, same(cursor));
    expect(panel.selection, selected);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'filtering removes hidden selections and does not hijack typing',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('photo2.raw'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gallery-search-local')),
        'photo10',
      );
      await tester.pumpAndSettle();
      expect(panel.selection, isEmpty);
      expect(find.text('photo2.raw'), findsNothing);
      expect(find.text('photo10.raw'), findsOneWidget);
      expect(
        container.read(galleryQueryProvider(PanelSide.local)).text,
        'photo10',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tiles show mixed files in a narrow panel without overflow', (
    tester,
  ) async {
    await mount(tester, tiles: true, width: 240);
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'explicit projection ignores forged same-path objects and parent entries',
    () {
      final rows = panel.files!;
      panel.selectVisibleItems([
        files[0],
        rows[1].copyWith(),
        rows[2],
      ], cursor: rows[2]);
      expect(panel.selection, {rows[2]});
      expect(panel.cursorItem, same(rows[2]));
    },
  );

  testWidgets(
    'view selector exposes Gallery and Tiles without changing selection',
    (tester) async {
      final row = panel.files![1];
      panel.selectVisibleItems([row], cursor: row);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: FileViewSelector(side: PanelSide.local)),
          ),
        ),
      );
      await tester.tap(find.byTooltip('View'));
      await tester.pumpAndSettle();
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Tiles'), findsOneWidget);
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      expect(container.read(localViewModeProvider), ViewMode.gallery);
      expect(panel.selection, {row});
      // The fixture created its preference futures before entering the widget
      // test's fake clock; let that real microtask queue finish persistence.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(
        (await SharedPreferences.getInstance()).getString(
          'file_layout_local_v1',
        ),
        'gallery',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/keyboard_shortcuts.dart';
import 'package:crisp_cloud/providers/toolbar_provider.dart'
    show panelViewModeProvider;
import 'package:crisp_cloud/services/panel_view_mode_service.dart'
    show PanelViewMode;
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
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

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final WorkflowFakeClient client = WorkflowFakeClient()..current = false;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail;
  @override
  String get providerName => client.providerName;
  void connect() {
    client.current = true;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        localFileServiceProvider.overrideWithValue(_Local()),
        authProvider.overrideWith((_) => _Auth()),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester, {bool editing = false}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Focus(
                autofocus: !editing,
                onKeyEvent: (_, event) => handleKeyEvent(context, ref, event),
                child: editing
                    ? const TextField(autofocus: true)
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container.read(activePanelProvider.notifier).state = PanelSide.local;
    container.read(focusAreaProvider.notifier).state = FocusArea.local;
  }

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('modified function keys sort without opening file operations', (
    tester,
  ) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    for (final entry in {
      LogicalKeyboardKey.f4: SortBy.extension,
      LogicalKeyboardKey.f6: SortBy.size,
      LogicalKeyboardKey.f5: SortBy.date,
      LogicalKeyboardKey.f3: SortBy.name,
    }.entries) {
      await chord(tester, entry.key);
      expect(panel.sortBy, entry.value);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom binding executes and disables its old default', (
    tester,
  ) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    final before = panel.showHiddenFiles;
    await container
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          ShortcutAction.toggleHidden,
          const ShortcutBinding(key: 'F9'),
        );
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    expect(panel.showHiddenFiles, !before);
    await chord(tester, LogicalKeyboardKey.period);
    expect(panel.showHiddenFiles, !before);
    await container
        .read(shortcutBindingsProvider.notifier)
        .resetBinding(ShortcutAction.toggleHidden);
    await chord(tester, LogicalKeyboardKey.period);
    expect(panel.showHiddenFiles, before);
  });

  testWidgets('text fields retain custom function keys and sorting keys', (
    tester,
  ) async {
    await mount(tester, editing: true);
    await container
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          ShortcutAction.toggleHidden,
          const ShortcutBinding(key: 'F9'),
        );
    final panel = container.read(panelProvider(PanelSide.local));
    final hidden = panel.showHiddenFiles;
    final sort = panel.sortBy;
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await chord(tester, LogicalKeyboardKey.f6);
    await tester.enterText(find.byType(TextField), 'draft.txt');
    expect(panel.showHiddenFiles, hidden);
    expect(panel.sortBy, sort);
    expect(find.text('draft.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal focus retains function keys', (tester) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    final sort = panel.sortBy;
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    await chord(tester, LogicalKeyboardKey.f6);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(panel.sortBy, sort);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final editing in [false, true]) {
    testWidgets(
      'keypad restore respects ${editing ? 'text input' : 'browser'} ownership',
      (tester) async {
        await mount(tester, editing: editing);
        final auth = container.read(authProvider) as _Auth;
        auth.client.put('/remember.txt', [1]);
        auth.connect();
        final panel = container.read(panelProvider(PanelSide.remote));
        await panel.refresh();
        panel.selectAll();
        expect(panel.rememberSelection(), 1);
        panel.clearSelection();
        container.read(activePanelProvider.notifier).state = PanelSide.remote;
        container.read(focusAreaProvider.notifier).state = FocusArea.remote;
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadDivide);
        await tester.pumpAndSettle();
        expect(panel.selection.length, editing ? 0 : 1);
        if (!editing) expect(panel.selection.single.path, '/remember.txt');
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('saved bindings hydrate observable provider state', () async {
    SharedPreferences.setMockInitialValues({
      'keyboard_shortcuts': '{"refresh":{"key":"F9","ctrl":false,"shift":false,"alt":false,"meta":false}}',
    });
    container.read(shortcutBindingsProvider);
    await container.read(keyboardShortcutServiceProvider).load();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(shortcutBindingsProvider)[ShortcutAction.refresh]!.key,
      'F9',
    );
  });

  test(
    'Command defaults and explicit Control overrides remain distinct',
    () async {
      final service = KeyboardShortcutService();
      final event = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.keyT,
        physicalKey: PhysicalKeyboardKey.keyT,
        timeStamp: Duration.zero,
      );
      expect(
        service.resolveBrowser(
          event,
          isCtrl: false,
          isMeta: true,
          isShift: false,
          isAlt: false,
        ),
        ShortcutAction.newTab,
      );
      await service.setBinding(
        ShortcutAction.newTab,
        const ShortcutBinding(key: 'T', ctrl: true),
      );
      expect(
        service.resolveBrowser(
          event,
          isCtrl: false,
          isMeta: true,
          isShift: false,
          isAlt: false,
        ),
        isNull,
      );
      expect(
        service.suppressesDefault(
          event,
          isCtrl: false,
          isMeta: true,
          isShift: false,
          isAlt: false,
        ),
        isTrue,
      );
    },
  );

  testWidgets('extra modifiers never fall through into a browser operation', (
    tester,
  ) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    panel.showSearchResults([
      FileItem(name: 'draft.txt', path: '/landing/draft.txt', isFolder: false),
    ]);
    await tester.pumpAndSettle();
    final tabs = panel.tabs.length;
    for (final chord in <(List<LogicalKeyboardKey>, LogicalKeyboardKey)>[
      // Alt+F1/F2/F5/F9 are commander commands now; these stay unbound.
      ([LogicalKeyboardKey.altLeft], LogicalKeyboardKey.f6),
      ([LogicalKeyboardKey.altLeft], LogicalKeyboardKey.f4),
      (
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft],
        LogicalKeyboardKey.keyT,
      ),
      (
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft],
        LogicalKeyboardKey.keyW,
      ),
      (
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.metaLeft],
        LogicalKeyboardKey.keyT,
      ),
      ([LogicalKeyboardKey.altLeft], LogicalKeyboardKey.tab),
    ]) {
      for (final modifier in chord.$1) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyEvent(chord.$2);
      for (final modifier in chord.$1.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pump();
      expect(panel.tabs, hasLength(tabs));
      expect(panel.renamingItem, isNull);
      expect(container.read(activePanelProvider), PanelSide.local);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a held custom Space shortcut runs once without changing selection',
    (tester) async {
      await mount(tester);
      final panel = container.read(panelProvider(PanelSide.local));
      final before = panel.showHiddenFiles;
      await container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            ShortcutAction.toggleHidden,
            const ShortcutBinding(key: ' '),
          );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(panel.showHiddenFiles, !before);
      expect(panel.selection, isEmpty);
      expect(panel.filterQuery, isEmpty);
    },
  );

  testWidgets('switching panes transfers keyboard focus ownership', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(container.read(activePanelProvider), PanelSide.remote);
    expect(container.read(focusAreaProvider), FocusArea.remote);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(container.read(activePanelProvider), PanelSide.local);
    expect(container.read(focusAreaProvider), FocusArea.local);
  });

  testWidgets(
    'opening the cursor in the other pane transfers focus ownership',
    (tester) async {
      final auth = container.read(authProvider) as _Auth;
      auth.client.put('/pictures/photo.txt', [1, 2, 3]);
      auth.connect();
      final source = container.read(panelProvider(PanelSide.remote));
      await source.navigateToPath('/pictures');
      final file = source.files!.singleWhere(
        (file) => file.name == 'photo.txt',
      );
      final origin = source.captureOperationOrigin([file]);
      source.setCursorToItem(file);
      await mount(tester);
      container.read(activePanelProvider.notifier).state = PanelSide.remote;
      container.read(focusAreaProvider.notifier).state = FocusArea.remote;
      await chord(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final destination = container.read(panelProvider(PanelSide.local));
      expect(destination.currentPath, '/pictures');
      expect(destination.cursorItem?.name, 'photo.txt');
      expect(
        destination.captureCurrentOrigin().storageReference,
        origin.storageReference,
      );
      expect(container.read(activePanelProvider), PanelSide.local);
      expect(container.read(focusAreaProvider), FocusArea.local);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a rebound action suppresses its alternate default chord', (
    tester,
  ) async {
    await mount(tester);
    final panel = container.read(panelProvider(PanelSide.local));
    final before = panel.showHiddenFiles;
    await container
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          ShortcutAction.toggleHidden,
          const ShortcutBinding(key: 'F9'),
        );
    // Ctrl+Shift+. is the default alias (Ctrl+H is directory history now).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await chord(tester, LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(panel.showHiddenFiles, before);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    expect(panel.showHiddenFiles, !before);
  });

  testWidgets(
    'background listing refresh does not take focus from a filter field',
    (tester) async {
      final fieldFocus = FocusNode();
      final scroll = ScrollController();
      addTearDown(fieldFocus.dispose);
      addTearDown(scroll.dispose);
      final file = FileItem(
        name: 'visible.txt',
        path: '/landing/visible.txt',
        isFolder: false,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  TextField(
                    key: const ValueKey('filter-input'),
                    focusNode: fieldFocus,
                  ),
                  Expanded(
                    child: FileListView(
                      side: PanelSide.local,
                      files: [file],
                      scrollController: scroll,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-input')));
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue);
      await container.read(panelProvider(PanelSide.local)).refresh();
      await tester.pumpAndSettle();
      expect(fieldFocus.hasFocus, isTrue);
      expect(
        container.read(panelProvider(PanelSide.local)).listFocusNode.hasFocus,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  group('Total Commander / Double Commander keys', () {
    Future<PanelNotifier> remote(
      WidgetTester tester,
      Map<String, List<int>> files, {
      String path = '/',
    }) async {
      final auth = container.read(authProvider) as _Auth;
      for (final entry in files.entries) {
        auth.client.put(entry.key, entry.value);
      }
      auth.connect();
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.navigateToPath(path);
      await mount(tester);
      container.read(activePanelProvider.notifier).state = PanelSide.remote;
      container.read(focusAreaProvider.notifier).state = FocusArea.remote;
      return panel;
    }

    Future<void> keys(
      WidgetTester tester,
      List<LogicalKeyboardKey> modifiers,
      LogicalKeyboardKey key,
    ) async {
      for (final modifier in modifiers) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyEvent(key);
      for (final modifier in modifiers.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pumpAndSettle();
    }

    FileItem row(PanelNotifier panel, String name) =>
        panel.files!.singleWhere((file) => file.name == name);

    testWidgets('Shift+F5 copies the cursor file in its folder under a new '
        'name', (tester) async {
      final panel = await remote(tester, {
        '/docs/report.txt': [1, 2, 3],
      }, path: '/docs');
      panel.setCursorToItem(row(panel, 'report.txt'));
      await keys(tester, [LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.f5);
      expect(find.text('Copy in this folder'), findsOneWidget);
      expect(find.text('report copy.txt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('file-name-submit')));
      await tester.pumpAndSettle();
      final auth = container.read(authProvider) as _Auth;
      expect(auth.client.files['/docs/report copy.txt'], [1, 2, 3]);
      expect(auth.client.files['/docs/report.txt'], [1, 2, 3]);
      expect(panel.cursorItem?.name, 'report copy.txt');
      // Shift+F5 is no longer the copy-to-other-panel dialog.
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shift+F4 asks for a name and creates the new file', (
      tester,
    ) async {
      final panel = await remote(tester, {
        '/docs/keep.bin': [9],
      }, path: '/docs');
      panel.setCursorToItem(panel.files!.firstWhere((f) => f.isFolder));
      await keys(tester, [LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.f4);
      expect(find.text('New text file'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('file-name-input')),
        'notes.txt',
      );
      await tester.tap(find.byKey(const ValueKey('file-name-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final auth = container.read(authProvider) as _Auth;
      expect(auth.client.files['/docs/notes.txt'], isEmpty);
      expect(panel.cursorItem?.name, 'notes.txt');
      // An existing name is returned for editing, not overwritten.
      final existing = await panel.createEmptyFile('keep.bin');
      expect(existing?.name, 'keep.bin');
      expect(auth.client.files['/docs/keep.bin'], [9]);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Ctrl+PgUp opens the parent and Ctrl+PgDn the cursor folder', (
      tester,
    ) async {
      final panel = await remote(tester, {
        '/pictures/2025/a.jpg': [1],
      }, path: '/pictures');
      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.pageUp);
      expect(panel.currentPath, '/');
      panel.setCursorToItem(row(panel, 'pictures'));
      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.pageDown);
      expect(panel.currentPath, '/pictures');
      expect(panel.tabs, hasLength(1));
    });

    testWidgets('Ctrl+H and Alt+Down list visited folders to jump to', (
      tester,
    ) async {
      final panel = await remote(tester, {
        '/alpha/one.txt': [1],
        '/beta/two.txt': [2],
      }, path: '/alpha');
      await panel.navigateToPath('/beta');
      await tester.pumpAndSettle();
      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyH);
      expect(find.text('Directory history'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('directory-history-0')));
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/alpha');
      await keys(tester, [
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.arrowDown);
      expect(find.text('Directory history'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Hidden files are no longer toggled by Ctrl+H.
      expect(tester.takeException(), isNull);
    });

    testWidgets('Alt+N activates tab N, Alt+0 the last tab, Ctrl+Shift+A '
        'lists tabs and Ctrl+Shift+W keeps protected tabs', (tester) async {
      final panel = await remote(tester, {
        '/a/1.txt': [1],
        '/b/2.txt': [2],
        '/c/3.txt': [3],
      }, path: '/a');
      panel.addTab(path: '/b');
      await tester.pumpAndSettle();
      panel.addTab(path: '/c');
      await tester.pumpAndSettle();
      expect(panel.tabs, hasLength(3));
      await keys(tester, [
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.digit1);
      expect(panel.activeTabId, panel.tabs.first.id);
      await keys(tester, [
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.digit0);
      expect(panel.activeTabId, panel.tabs.last.id);
      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyA);
      expect(find.text('Open tabs'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('open-tab-${panel.tabs[1].id}')));
      await tester.pumpAndSettle();
      expect(panel.activeTabId, panel.tabs[1].id);
      panel.toggleTabPin(panel.tabs.first.id);
      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyW);
      expect(panel.tabs, hasLength(2));
      expect(panel.tabs.first.isPinned, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl+Num± and Alt+Num± change the selection', (tester) async {
      final panel = await remote(tester, {
        '/m/a.txt': [1],
        '/m/b.txt': [2],
        '/m/c.jpg': [3],
      }, path: '/m');
      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.numpadAdd);
      expect(panel.selection, hasLength(3));
      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.numpadSubtract);
      expect(panel.selection, isEmpty);
      panel.setCursorToItem(row(panel, 'a.txt'));
      await keys(tester, [
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.numpadAdd);
      expect(panel.selection.map((f) => f.name).toSet(), {'a.txt', 'b.txt'});
      await keys(tester, [
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.numpadSubtract);
      expect(panel.selection, isEmpty);
    });

    testWidgets('Ctrl+1/2/3 and Ctrl+F1/F2/F8 switch the view mode', (
      tester,
    ) async {
      await mount(tester);
      for (final (key, mode) in <(LogicalKeyboardKey, PanelViewMode)>[
        (LogicalKeyboardKey.f8, PanelViewMode.tree),
        (LogicalKeyboardKey.f1, PanelViewMode.brief),
        (LogicalKeyboardKey.digit2, PanelViewMode.full),
        (LogicalKeyboardKey.f2, PanelViewMode.full),
        (LogicalKeyboardKey.digit3, PanelViewMode.tree),
        (LogicalKeyboardKey.digit1, PanelViewMode.brief),
      ]) {
        await chord(tester, key);
        await tester.pumpAndSettle();
        expect(
          container.read(panelViewModeProvider(PanelSide.local)),
          mode,
          reason: key.keyLabel,
        );
      }
    });
  });
}

import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/keyboard_shortcuts.dart';
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
      ([LogicalKeyboardKey.altLeft], LogicalKeyboardKey.f2),
      ([LogicalKeyboardKey.altLeft], LogicalKeyboardKey.f5),
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
    await chord(tester, LogicalKeyboardKey.keyH);
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
}

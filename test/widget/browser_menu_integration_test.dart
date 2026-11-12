import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/browser_menu_layout.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/browser_menu_provider.dart';
import 'package:crisp_cloud/providers/custom_command_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/file_browser_screen.dart';
import 'package:crisp_cloud/services/browser_menu_store.dart';
import 'package:crisp_cloud/services/code_editor_menu.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/services/terminal_menu.dart';
import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/configurable_browser_menu.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/browser_menu_storage.dart';
import '../support/external_drop_fixture.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String get grantedBasePath => '/landing';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<void> refresh() async {}
}

class _Auth extends DropTestAuth {
  _Auth() : super(DropTestCloud('menu-account'));
  @override
  bool get isEncryptionEnabled => false;
}

class _Sync extends SyncNotifier {
  _Sync(super.ref, super.database) : super.forTesting();
  @override
  bool get isSyncing => false;
  @override
  SyncResult? get lastResult => null;
  @override
  List<SyncPair> get pairs => const [];
  @override
  String? get currentPairName => null;
}

void main() {
  late ProviderContainer container;
  late BrowserMenuStore menus;
  late SyncDatabase database;
  late ThemeService theme;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    menus = BrowserMenuStore(storage: MemoryBrowserMenuStorage());
    await menus.ready;
    final commands = CustomToolbarCommandService();
    await commands.load();
    database = SyncDatabase.forTesting(NativeDatabase.memory());
    theme = ThemeService();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth()),
        localFileServiceProvider.overrideWithValue(_Local()),
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        browserMenuStoreProvider.overrideWith((_) => menus),
        customToolbarCommandServiceProvider.overrideWith((_) => commands),
        transferJournalProvider.overrideWithValue(
          TransferJournal(MemoryTransferJournalStorage()),
        ),
        syncProvider.overrideWith((ref) => _Sync(ref, database)),
        drivesProvider.overrideWith((_) async => const <DriveEntry>[]),
      ],
    );
    await container.read(transferProvider).ready;
    await container.read(panelProvider(PanelSide.local)).refresh();
    await container.read(panelProvider(PanelSide.remote)).refresh();
  });
  tearDown(() {
    container.dispose();
    theme.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1250, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: legacy.ChangeNotifierProvider<ThemeService>.value(
          value: theme,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FileBrowserScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'every default menu command resolves to the real screen registry',
    (tester) async {
      await mount(tester);
      final widget = tester.widget<ConfigurableBrowserMenu>(
        find.byType(ConfigurableBrowserMenu),
      );
      final unknown = widget.layout.nodes.where(
        (node) =>
            node.commandId != null &&
            !widget.commands.containsKey(node.commandId),
      );
      expect(unknown.map((node) => node.commandId), isEmpty);
      expect(
        widget.fixedCommands.map((entry) => entry.id),
        containsAll([
          'settings',
          'transferRecovery',
          'trashRecovery',
          'renameRecovery',
          'integrityRecovery',
          'customize',
          'reset',
        ]),
      );
      final panel = container.read(panelProvider(PanelSide.local));
      final before = panel.tabs.length;
      final captured = widget.commands['action:newTab']!.onSelected!;
      captured();
      await tester.pumpAndSettle();
      expect(panel.tabs.length, before + 1);
      final context = tester.element(find.byType(FileBrowserScreen));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
      );
      await tester.pumpAndSettle();
      captured();
      expect(
        panel.tabs.length,
        before + 1,
        reason: 'An already captured menu callback cannot steal a modal editor key.',
      );
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'native code-editor and terminal menus keep ownership over a configured browser layout',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.menu,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.menu,
          null,
        ),
      );
      await tester.runAsync(
        () => menus.save(
          BrowserMenuLayout([
            BrowserMenuNode(
              id: 'custom',
              kind: BrowserMenuNodeKind.submenu,
              label: 'Configured browser',
              children: [
                BrowserMenuNode(
                  id: 'copy',
                  kind: BrowserMenuNodeKind.command,
                  commandId: 'action:copy',
                ),
              ],
            ),
          ]),
        ),
      );
      await mount(tester);
      List<PlatformMenuItem> native() =>
          tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus;
      expect(
        native().any((menu) => menu.label == 'Configured browser'),
        isTrue,
      );
      CodeEditorMenuAction? editorAction;
      container
          .read(codeEditorMenuProvider.notifier)
          .state = CodeEditorMenuActions(
        perform: (action) => editorAction = action,
        canSave: true,
        canUndo: true,
        canRedo: true,
        hasSelection: true,
        canReload: true,
        canHighlight: true,
      );
      await tester.pumpAndSettle();
      expect(
        native().any((menu) => menu.label == 'Configured browser'),
        isFalse,
      );
      final editorItems = menuEntries(native());
      editorItems.firstWhere((item) => item.label == 'Save').onSelected!();
      expect(editorAction, CodeEditorMenuAction.save);
      expect(
        editorItems.any((item) => item.label == 'Customize menus'),
        isTrue,
      );
      container.read(codeEditorMenuProvider.notifier).state = null;
      TerminalMenuAction? terminalAction;
      container.read(terminalMenuProvider.notifier).state = TerminalMenuActions(
        owner: Object(),
        perform: (action) => terminalAction = action,
        canCopy: true,
        canPaste: true,
        canDisconnect: true,
      );
      await tester.pumpAndSettle();
      expect(
        native().any((menu) => menu.label == 'Configured browser'),
        isFalse,
      );
      menuEntries(native())
          .firstWhere((item) => item.label == 'Paste')
          .onSelected!();
      expect(terminalAction, TerminalMenuAction.paste);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Iterable<PlatformMenuItem> menuEntries(List<PlatformMenuItem> entries) sync* {
  for (final entry in entries) {
    yield entry;
    if (entry is PlatformMenu) yield* menuEntries(entry.menus);
    if (entry is PlatformMenuItemGroup) yield* menuEntries(entry.members);
  }
}

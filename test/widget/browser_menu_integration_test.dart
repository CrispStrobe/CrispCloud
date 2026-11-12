import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/browser_menu_layout.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/browser_menu_provider.dart';
import 'package:crisp_cloud/providers/custom_command_provider.dart';
import 'package:crisp_cloud/providers/external_comparison_provider.dart';
import 'package:crisp_cloud/providers/external_remote_editing_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/file_browser_screen.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart';
import 'package:crisp_cloud/services/browser_menu_store.dart';
import 'package:crisp_cloud/services/code_editor_menu.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';
import 'package:crisp_cloud/services/external_comparison_service.dart';
import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/services/terminal_menu.dart';
import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/configurable_browser_menu.dart';
import 'package:crisp_cloud/widgets/help_guide_dialog.dart';
import 'package:crisp_cloud/widgets/external_comparison_dialog.dart';
import 'package:crisp_cloud/widgets/external_editing_dialog.dart';
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
import '../support/external_comparison_fixture.dart';
import '../support/external_edit_fakes.dart';

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
        externalComparisonServiceProvider.overrideWith(
          (_) => ExternalComparisonService(
            host: ComparisonHost(),
            staging: ComparisonMemoryStages(),
          ),
        ),
        externalRemoteEditingServiceProvider.overrideWith(
          (_) => ExternalRemoteEditingService(staging: FakeEditStagingStore()),
        ),
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
          'userGuide',
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
      widget.fixedCommands
          .firstWhere((entry) => entry.id == 'userGuide')
          .onSelected!();
      await tester.pumpAndSettle();
      expect(find.byType(HelpGuideDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('help-content-en-getting-started')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('help-close')));
      await tester.pumpAndSettle();
      showKeyboardShortcutsHelp(context);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('keyboard-help-user-guide')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-content-en-keyboard-shortcuts')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('help-close')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'external comparison routes open settings and preserve modal ownership',
    (tester) async {
      final service = container.read(externalComparisonServiceProvider);
      await service.ready;
      await mount(tester);
      final menu = tester.widget<ConfigurableBrowserMenu>(
        find.byType(ConfigurableBrowserMenu),
      );
      final openSettings =
          menu.commands['workflow:externalComparisonTools']!.onSelected!;
      openSettings();
      await tester.pumpAndSettle();
      expect(find.byType(ExternalComparisonDialog), findsOneWidget);
      expect(
        tester
            .widget<ExternalComparisonDialog>(
              find.byType(ExternalComparisonDialog),
            )
            .pair,
        isNull,
      );
      openSettings();
      await tester.pumpAndSettle();
      expect(find.byType(ExternalComparisonDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Close').last);
      await tester.pumpAndSettle();
      final refreshed = tester.widget<ConfigurableBrowserMenu>(
        find.byType(ConfigurableBrowserMenu),
      );
      refreshed.commands['workflow:externalCompare']!.onSelected!();
      await tester.pumpAndSettle();
      final dialog = tester.widget<ExternalComparisonDialog>(
        find.byType(ExternalComparisonDialog),
      );
      expect(dialog.pair, isNull);
      expect(dialog.initialError, isA<ExternalComparisonException>());
      expect((service.host as ComparisonHost).launches, isEmpty);
      expect(service.sessions, isEmpty);
    },
  );

  testWidgets(
    'external editing settings own the modal and missing sources cannot stage or publish',
    (tester) async {
      final service = container.read(externalRemoteEditingServiceProvider);
      await mount(tester);
      final menu = tester.widget<ConfigurableBrowserMenu>(
        find.byType(ConfigurableBrowserMenu),
      );
      final openSettings =
          menu.commands['workflow:externalEditingSessions']!.onSelected!;
      openSettings();
      await tester.pumpAndSettle();
      expect(find.byType(ExternalEditingDialog), findsOneWidget);
      expect(
        tester
            .widget<ExternalEditingDialog>(find.byType(ExternalEditingDialog))
            .source,
        isNull,
      );
      openSettings();
      await tester.pumpAndSettle();
      expect(find.byType(ExternalEditingDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('external-editing-close')));
      await tester.pumpAndSettle();
      final refreshed = tester.widget<ConfigurableBrowserMenu>(
        find.byType(ConfigurableBrowserMenu),
      );
      refreshed.commands['workflow:externalEdit']!.onSelected!();
      await tester.pumpAndSettle();
      final dialog = tester.widget<ExternalEditingDialog>(
        find.byType(ExternalEditingDialog),
      );
      expect(dialog.source, isNull);
      expect(dialog.initialError, isA<ExternalEditException>());
      expect(service.sessions, isEmpty);
      expect((service.staging as FakeEditStagingStore).bundles, isEmpty);
    },
  );

  testWidgets(
    'archive recovery is reachable from an ordinary folder and keeps modal input ownership',
    (tester) async {
      await mount(tester);
      final menu = tester.widget<ConfigurableBrowserMenu>(
        find.byType(ConfigurableBrowserMenu),
      );
      final openRecovery =
          menu.commands['workflow:archiveRecovery']!.onSelected!;
      openRecovery();
      await tester.pumpAndSettle();
      expect(find.text('Archive publication recovery'), findsOneWidget);
      expect(
        find.text('No unfinished archive publication for this account.'),
        findsOneWidget,
      );
      openRecovery();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Close').last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
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

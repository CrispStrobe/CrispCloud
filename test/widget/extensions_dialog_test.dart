import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/extension_translations.dart';
import 'package:crisp_cloud/models/command_extension.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/providers/command_extension_provider.dart';
import 'package:crisp_cloud/providers/custom_command_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/command_extension_store.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/plugin_workspace.dart';
import 'package:crisp_cloud/widgets/command_extension_actions.dart';
import 'package:crisp_cloud/widgets/custom_command_dialog.dart';
import 'package:crisp_cloud/widgets/extensions_dialog.dart';
import 'package:crisp_cloud/widgets/file_command_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart' show WorkspaceTestAuth;

class _Local extends Fake implements LocalFileService {
  _Local(this.currentPath);
  @override
  String currentPath;
  @override
  String get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) =>
      Directory(path).list().toList();
  @override
  Future<void> refresh() async {}
}

class _Process extends Fake implements Process {
  final out = StreamController<List<int>>(),
      err = StreamController<List<int>>();
  final exit = Completer<int>();
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    finish(143);
    return true;
  }

  void finish([int code = 0]) {
    if (exit.isCompleted) return;
    out.close();
    err.close();
    exit.complete(code);
  }
}

class _Plugin extends CrispCloudPlugin {
  int menuBuilds = 0;
  int initializes = 0;
  bool fail = false;
  Map<String, dynamic>? initializedSettings;
  List<String>? selected;
  @override
  String get id => 'test.compiled';
  @override
  String get name => 'Compiled action';
  @override
  String get version => '1.0.0';
  @override
  String get description => 'A trusted test plugin';
  @override
  String? get author => null;
  @override
  String? get homepage => null;
  @override
  List<PluginCapability> get capabilities => [
    PluginCapability.toolbar,
    PluginCapability.contextMenu,
    PluginCapability.settings,
  ];
  @override
  Future<void> initialize(PluginContext context) async {
    initializes++;
    initializedSettings = await context.getSettings();
    if (fail) throw StateError('Initialization deliberately failed');
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> onFileAction(FileAction action, List<String> files) async {}
  @override
  Map<String, dynamic> getDefaultSettings() => {};
  @override
  List<PluginToolbarButton> getToolbarButtons() => [
    PluginToolbarButton(
      id: 'compiled',
      label: 'Compiled action',
      tooltip: 'Compiled action',
      icon: 'extension',
      onPressed: (files) => selected = files,
    ),
  ];
  @override
  List<PluginMenuItem> getContextMenuItems(List<String> paths) {
    menuBuilds++;
    return [
      PluginMenuItem(
        id: 'compiled',
        label: 'Compiled action',
        icon: 'extension',
        onSelected: (files) => selected = files,
      ),
    ];
  }
}

const command = CustomToolbarCommand(
  id: 'inspect',
  label: 'Inspect files',
  executable: '/tools/inspect',
  arguments: ['--', '{SELECTED}'],
  timeoutSeconds: 10,
);
CommandExtensionManifest manifest() => CommandExtensionManifest(
  id: 'test.inspector',
  name: 'Inspector',
  version: '1.0.0',
  description: 'Inspect selected local files.',
  commands: [command],
);

void main() {
  late Directory directory;
  late ProviderContainer container;
  late CommandExtensionStore store;
  late CustomToolbarCommandService service;
  late PluginRegistryNotifier plugins;
  late WorkflowFakeClient cloud;
  late List<List<String>> launched;
  late List<_Process> processes;
  late FileItem selected, clicked;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.current.createTemp('extension_widget_');
    await File('${directory.path}/marked.txt').writeAsString('marked');
    await File('${directory.path}/clicked \$(literal).txt')
        .writeAsString('clicked');
    launched = [];
    processes = [];
    service = CustomToolbarCommandService(
      processStarter: (exe, args, cwd) async {
        launched.add([exe, ...args, cwd]);
        final process = _Process();
        processes.add(process);
        return process;
      },
    );
    store = CommandExtensionStore();
    await store.ready;
    plugins = PluginRegistryNotifier(
      registry: PluginRegistry(
        workspaceFactory: (id) async =>
            PluginWorkspace('memory:/$id', () async {}),
      ),
    );
    cloud = WorkflowFakeClient()..put('/cloud.txt', [1]);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local(directory.path)),
        customToolbarCommandServiceProvider.overrideWith((_) => service),
        commandExtensionStoreProvider.overrideWith((_) => store),
        pluginRegistryProvider.overrideWith((_) => plugins),
      ],
    );
    final panel = container.read(panelProvider(PanelSide.local));
    await panel.refresh();
    container
        .read(panelSourceProvider(PanelSide.local).notifier)
        .setSource(LocalPanelSource(directory.path));
    await panel.refresh();
    await container.read(panelProvider(PanelSide.remote)).refresh();
    selected = panel.files!.firstWhere((file) => file.name == 'marked.txt');
    clicked = panel.files!.firstWhere(
      (file) => file.name.startsWith('clicked'),
    );
    panel.toggleSelection(selected);
  });
  tearDown(() async {
    for (final process in processes) {
      process.finish();
    }
    container.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  }

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> installEnabled(WidgetTester tester) async {
    await tester.runAsync(() async {
      await store.install(manifest());
      await store.setEnabled('test.inspector', true);
    });
  }

  Future<void> openReview(WidgetTester tester) async {
    await mount(tester, const FileCommandToolbar(side: PanelSide.local));
    await tester.tap(
      find.byKey(const ValueKey('extension-toolbar-test.inspector-inspect')),
    );
    await settle(tester);
    expect(find.byType(CommandRunDialog), findsOneWidget);
    expect(find.text(directory.path), findsOneWidget);
    expect(find.text('Timeout (seconds): 10'), findsOneWidget);
    expect(launched, isEmpty);
  }

  Future<void> runReview(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
  }

  testWidgets(
    'import requires full review and installs disabled without launching',
    (tester) async {
      await mount(tester, const ExtensionsDialog(side: PanelSide.local));
      await tester.tap(find.text('Import manifest'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-import-text')),
        manifest().exportText(),
      );
      await tester.ensureVisible(find.text('Review extension'));
      await tester.tap(find.text('Review extension'));
      await settle(tester);
      expect(find.byType(ExtensionReviewDialog), findsOneWidget);
      expect(find.text('/tools/inspect'), findsOneWidget);
      expect(find.text('[1] "{SELECTED}"'), findsOneWidget);
      expect(store.installed, isEmpty);
      expect(launched, isEmpty);
      await tester.ensureVisible(
        find.byKey(const ValueKey('extension-install-reviewed')),
      );
      await tester.tap(
        find.byKey(const ValueKey('extension-install-reviewed')),
      );
      await settle(tester);
      expect(store.installed.single.enabled, isFalse);
      expect(store.actions(CommandExtensionCapability.toolbar), isEmpty);
      expect(launched, isEmpty);
    },
  );

  testWidgets(
    'toolbar hosts custom commands and extension actions and passes literal argv',
    (tester) async {
      await installEnabled(tester);
      await tester.runAsync(
        () => service.addCommand(
          const CustomToolbarCommand(
            id: 'custom',
            label: 'Custom program',
            executable: '/tools/custom',
            arguments: ['{SELECTED}'],
          ),
        ),
      );
      await openReview(tester);
      expect(find.text('Custom program'), findsOneWidget);
      await runReview(tester);
      expect(launched.single, [
        '/tools/inspect',
        '--',
        selected.path!,
        directory.path,
      ]);
      processes.single.out.add('finished'.codeUnits);
      processes.single.finish();
      await settle(tester);
      expect(find.textContaining('finished'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mutation in ['disable', 'configure', 'remove']) {
    testWidgets(
      '$mutation while review is open prevents starting an old action',
      (tester) async {
        await installEnabled(tester);
        await openReview(tester);
        if (mutation == 'disable') {
          await tester.runAsync(
            () => store.setEnabled('test.inspector', false),
          );
        } else if (mutation == 'remove') {
          await tester.runAsync(() => store.remove('test.inspector'));
        } else {
          await tester.runAsync(
            () => store.configure(
              'test.inspector',
              const CustomToolbarCommand(
                id: 'inspect',
                label: 'Inspect files',
                executable: '/tools/changed',
                arguments: ['{SELECTED}'],
              ),
            ),
          );
        }
        await runReview(tester);
        expect(launched, isEmpty);
        expect(
          find.textContaining('current, verified local source'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'command settings change the next reviewed executable and arguments',
    (tester) async {
      await installEnabled(tester);
      await mount(tester, const ExtensionsDialog(side: PanelSide.local));
      await tester.ensureVisible(
        find.byKey(const ValueKey('extension-settings-test.inspector-inspect')),
      );
      await tester.tap(
        find.byKey(const ValueKey('extension-settings-test.inspector-inspect')),
      );
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Executable'),
        '/tools/configured',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Arguments (one per line)'),
        '--verbose\n{SELECTED}',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(
        store.installed.single.commands.single.executable,
        '/tools/configured',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('extension-run-test.inspector-inspect')),
      );
      await tester.tap(
        find.byKey(const ValueKey('extension-run-test.inspector-inspect')),
      );
      await settle(tester);
      await runReview(tester);
      expect(launched.single.take(3), [
        '/tools/configured',
        '--verbose',
        selected.path!,
      ]);
      processes.single.finish();
      await settle(tester);
    },
  );

  testWidgets(
    'context menu captures clicked row independently of marked selection',
    (tester) async {
      await installEnabled(tester);
      await mount(
        tester,
        Consumer(
          builder: (context, ref, _) => TextButton(
            child: const Text('Menu'),
            onPressed: () => showMenu<void>(
              context: context,
              position: const RelativeRect.fromLTRB(10, 10, 11, 11),
              items: buildCommandExtensionMenuItems(
                context,
                ref,
                PanelSide.local,
                [clicked],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Menu'));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('extension-menu-test.inspector-inspect')),
      );
      await settle(tester);
      await runReview(tester);
      expect(launched.single, [
        '/tools/inspect',
        '--',
        clicked.path!,
        directory.path,
      ]);
      processes.single.finish();
      await settle(tester);
    },
  );

  testWidgets(
    'cloud and unverified list rows reach neither commands nor compiled path hooks',
    (tester) async {
      await installEnabled(tester);
      final plugin = _Plugin();
      plugins.registerPlugin(plugin);
      await tester.runAsync(plugins.initializeAll);
      final remote = container.read(panelProvider(PanelSide.remote));
      final remoteFiles = remote.files!
          .where((file) => !file.isFolder)
          .toList();
      List<PopupMenuEntry<void>>? remoteActions, unverified;
      await mount(
        tester,
        Consumer(
          builder: (context, ref, _) {
            remoteActions = buildCommandExtensionMenuItems(
              context,
              ref,
              PanelSide.remote,
              remoteFiles,
            );
            unverified = buildCommandExtensionMenuItems(
              context,
              ref,
              PanelSide.local,
              [
                FileItem(
                  uuid: '/untrusted',
                  name: 'untrusted',
                  path: '/untrusted',
                  isFolder: false,
                ),
              ],
            );
            return const FileCommandToolbar(side: PanelSide.remote);
          },
        ),
      );
      expect(remoteActions, isEmpty);
      expect(unverified, isEmpty);
      expect(plugin.menuBuilds, 0);
      expect(find.byKey(const ValueKey('file-command-toolbar')), findsNothing);
      expect(launched, isEmpty);
    },
  );

  testWidgets('compiled toolbar callback is live and source-bound', (
    tester,
  ) async {
    final plugin = _Plugin();
    plugins.registerPlugin(plugin);
    await tester.runAsync(plugins.initializeAll);
    await mount(tester, const FileCommandToolbar(side: PanelSide.local));
    await tester.tap(
      find.byKey(const ValueKey('compiled-extension-toolbar-compiled')),
    );
    expect(plugin.selected, [selected.path]);
    await tester.runAsync(() => plugins.setEnabled(plugin.id, false));
    await settle(tester);
    expect(find.byKey(const ValueKey('file-command-toolbar')), findsNothing);
  });

  testWidgets(
    'first-party manager exposes failure, retry and effective settings restart',
    (tester) async {
      final plugin = _Plugin()..fail = true;
      plugins.registerPlugin(plugin);
      await mount(tester, const ExtensionsDialog(side: PanelSide.local));
      await tester.ensureVisible(find.text('Retry'));
      await settle(tester);
      expect(
        find.textContaining('Initialization deliberately failed'),
        findsOneWidget,
      );
      expect(plugins.getEnabledPlugins(), isEmpty);
      plugin.fail = false;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(plugins.registry.isReady(plugin.id), isTrue);
      await tester.ensureVisible(find.text('Plugin settings'));
      await settle(tester);
      await tester.tap(find.text('Plugin settings'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-import-text')),
        '{"mode":"detailed"}',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(plugin.initializes, 3);
      expect(plugin.initializedSettings, {'mode': 'detailed'});
      expect(plugins.registry.isReady(plugin.id), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['de', 'ar']) {
    testWidgets(
      'manager and manifest review fit narrow large-text $language layout',
      (tester) async {
        tester.view.physicalSize = const Size(340, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await installEnabled(tester);
        await mount(
          tester,
          const ExtensionsDialog(side: PanelSide.local),
          locale: language,
          scale: 1.4,
        );
        expect(tester.takeException(), isNull);
        await mount(
          tester,
          ExtensionReviewDialog(manifest: manifest(), replacing: true),
          locale: language,
          scale: 1.4,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(extensionText(language, 'Review extension')),
          findsOneWidget,
        );
      },
    );
  }

  test(
    'extension catalog covers all supported translations and placeholders',
    () {
      for (final entry in extensionTranslations.entries) {
        expect(entry.value, hasLength(8), reason: entry.key);
        final expected = RegExp(r'\{\d+\}')
            .allMatches(entry.key)
            .map((m) => m[0])
            .toSet();
        for (final value in entry.value) {
          expect(value.trim(), isNotEmpty);
          expect(
            RegExp(r'\{\d+\}').allMatches(value).map((m) => m[0]).toSet(),
            expected,
            reason: entry.key,
          );
        }
      }
    },
  );
}

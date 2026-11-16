import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/macos_application_launcher.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart';
import 'package:crisp_cloud/widgets/file_column_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';
import 'support/workspace_fixture.dart';

class _Local extends Fake
    implements
        LocalFileService,
        LocalDirectorySnapshotReader,
        ScopedLocalFileOperations {
  _Local(this.currentPath);
  @override
  String currentPath;
  bool allowed = true;
  String? activeScope;
  Completer<void>? waitForScope;
  @override
  String get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) async => allowed;
  @override
  Future<bool> ensureAccess(String path) async => allowed;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) =>
      Directory(path).list(followLinks: false).toList();
  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) =>
      listDirectory(path);
  @override
  Future<void> refresh() async {}
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() operation,
  ) async {
    if (!allowed) throw const FileSystemException('No access');
    activeScope = path;
    try {
      await waitForScope?.future;
      return await operation();
    } finally {
      activeScope = null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Local local;
  late WorkflowFakeClient cloud;
  late ProviderContainer container;
  late PanelNotifier panel;
  late List<String> launches;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('application-navigation-');
    Directory('${root.path}/Viewer.app/Contents').createSync(recursive: true);
    Directory('${root.path}/ordinary').createSync();
    local = _Local(root.path);
    launches = [];
    cloud = WorkflowFakeClient()..directories.add('/Remote.app');
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
        localFileServiceProvider.overrideWithValue(local),
        macApplicationLauncherProvider.overrideWithValue(
          MacApplicationLauncher(
            supported: true,
            run: (executable, arguments) async {
              expect(executable, '/usr/bin/open');
              expect(arguments.first, '-a');
              expect(local.activeScope, arguments.last);
              launches.add(arguments.last);
              return ProcessResult(1, 0, '', '');
            },
          ),
        ),
      ],
    );
    panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await panel.navigateToPath(
      root.path,
      origin: panel.captureLocalClipboardOrigin(root.path),
    );
  });
  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });

  test(
    'default opening launches a verified local app and keeps the folder view',
    () async {
      final app = panel.files!.singleWhere((file) => file.name == 'Viewer.app');
      expect(panel.canLaunchApplication(app), isTrue);
      await panel.navigateInto(app);
      expect(launches, ['${root.path}/Viewer.app']);
      expect(panel.currentPath, root.path);
      expect(local.activeScope, isNull);
      await panel.navigateInto(app, browseApplicationBundle: true);
      expect(panel.currentPath, '${root.path}/Viewer.app');
      expect(panel.files!.any((file) => file.name == 'Contents'), isTrue);
      expect(launches, hasLength(1));
    },
  );
  test(
    'navigation during access keeps the captured original application target',
    () async {
      final app = panel.files!.singleWhere((file) => file.name == 'Viewer.app');
      final gate = Completer<void>();
      local.waitForScope = gate;
      final launching = panel.launchApplication(app);
      await Future<void>.delayed(Duration.zero);
      await panel.navigateToPath('${root.path}/ordinary');
      gate.complete();
      await launching;
      expect(launches, ['${root.path}/Viewer.app']);
      expect(panel.currentPath, '${root.path}/ordinary');
    },
  );
  test('remote application folders stay browsable without launching or downloading', () async {
    final remote = container.read(panelProvider(PanelSide.remote));
    await remote.refresh();
    final app = remote.files!.singleWhere((file) => file.name == 'Remote.app');
    expect(remote.canLaunchApplication(app), isFalse);
    await remote.navigateInto(app);
    expect(remote.currentPath, '/Remote.app');
    expect(launches, isEmpty);
    expect(cloud.downloads, isEmpty);
  });
  test('an unverified replacement row cannot launch an application', () async {
    final app = FileItem(
      name: 'Viewer.app',
      path: '${root.path}/Viewer.app',
      isFolder: true,
    );
    expect(panel.canLaunchApplication(app), isFalse);
    await panel.launchApplication(app);
    expect(launches, isEmpty);
    expect(panel.currentPath, root.path);
  });
  test(
    'denied filesystem access does not launch or enter the bundle',
    () async {
      final app = panel.files!.singleWhere((file) => file.name == 'Viewer.app');
      local.allowed = false;
      await panel.launchApplication(app);
      expect(launches, isEmpty);
      expect(local.activeScope, isNull);
      expect(panel.currentPath, root.path);
    },
  );
  testWidgets(
    'column selection and Right never launch; Enter and double click do',
    (tester) async {
      await tester.runAsync(() async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  final current = ref.watch(panelProvider(PanelSide.local));
                  return Scaffold(
                    body: FileColumnView(
                      side: PanelSide.local,
                      files: current.displayedFiles ?? const [],
                      scrollController: scroll,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final row = find.byKey(
          ValueKey('column-item:${root.path}:${root.path}/Viewer.app'),
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(launches, isEmpty);
        expect(panel.currentPath, root.path);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(launches, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(launches, hasLength(1));
        await tester.tap(row);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(row);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
        expect(launches, hasLength(2));
        expect(panel.currentPath, root.path);
        await tester.pumpWidget(const SizedBox.shrink());
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'context menu offers Launch and Browse package contents separately',
    (tester) async {
      final app = panel.files!.singleWhere((file) => file.name == 'Viewer.app');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => showFileContextMenu(
                    context,
                    ref,
                    PanelSide.local,
                    app,
                    const Offset(40, 40),
                  ),
                  child: const Text('Menu'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Launch application'), findsOneWidget);
      expect(find.text('Browse package contents'), findsOneWidget);
      await tester.tap(find.text('Launch application'));
      await tester.pumpAndSettle();
      expect(launches, ['${root.path}/Viewer.app']);
      expect(panel.currentPath, root.path);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/folder_size_measurement.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart';
import 'package:crisp_cloud/widgets/storage_analysis_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart';

class _Cloud extends WorkflowFakeClient implements FreshCloudDirectoryReader {
  final scans = <String>[];
  final blocked = <String, Completer<void>>{};
  final entered = <String, Completer<void>>{};

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    scans.add(path);
    final signal = entered[path];
    if (signal != null && !signal.isCompleted) signal.complete();
    await blocked[path]?.future;
    return super.listPath(path);
  }
}

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Cloud cloud;
  late PanelNotifier panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud()
      ..put('/a/one.bin', [1])
      ..put('/b/two.bin', [1, 2])
      ..put('/c/three.bin', [1, 2, 3]);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await Future<void>.delayed(Duration.zero);
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(
          RemotePanelSource(
            client: cloud,
            providerName: cloud.providerName,
            path: '/',
          ),
        );
    await panel.refresh();
    panel.showSearchResults(
      panel.files!.where((file) => file.isFolder).toList(),
      origin: panel.captureCurrentOrigin(),
    );
  });

  tearDown(() {
    for (final gate in cloud.blocked.values) {
      if (!gate.isCompleted) gate.complete();
    }
    container.dispose();
  });

  FileItem folder(String name) =>
      panel.files!.singleWhere((file) => file.isFolder && file.name == name);

  Future<void> mountMenu(WidgetTester tester, FileItem row) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showFileContextMenu(
                  context,
                  ref,
                  PanelSide.remote,
                  row,
                  const Offset(24, 24),
                ),
                child: const Text('Open folder menu'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open folder menu'));
    await tester.pumpAndSettle();
  }

  testWidgets('result-list menu cancels the original queued folder scan', (
    tester,
  ) async {
    final row = folder('c');
    for (final name in ['a', 'b']) {
      cloud.blocked['/$name'] = Completer<void>();
      cloud.entered['/$name'] = Completer<void>();
    }
    final pending = [
      for (final name in ['a', 'b', 'c'])
        panel.calculateFolderSize(folder(name)),
    ];
    for (
      var attempt = 0;
      attempt < 20 &&
          (!cloud.entered['/a']!.isCompleted ||
              !cloud.entered['/b']!.isCompleted);
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(cloud.entered['/a']!.isCompleted, isTrue);
    expect(cloud.entered['/b']!.isCompleted, isTrue);
    expect(panel.folderSizeFor(row)?.phase, FolderSizePhase.queued);
    await mountMenu(tester, row);
    expect(find.text('Stop scan'), findsOneWidget);
    await tester.tap(find.text('Stop scan'));
    await tester.pumpAndSettle();
    expect((await pending[2])?.phase, FolderSizePhase.cancelled);
    expect(panel.folderSizeFor(row)?.isActive, isFalse);
    expect(cloud.scans, isNot(contains('/c')));
    expect(row.calculatedSize, isNull);
    cloud.blocked['/a']!.complete();
    cloud.blocked['/b']!.complete();
    await tester.pumpAndSettle();
    await Future.wait(pending);
    expect(cloud.scans, isNot(contains('/c')));
    expect(cloud.writes, isEmpty);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets(
    'result-list report retains the verified folder after navigation',
    (tester) async {
      final row = folder('c');
      await mountMenu(tester, row);
      expect(find.text('Calculate Size'), findsOneWidget);
      await tester.runAsync(() => panel.navigateToPath('/elsewhere'));
      await tester.tap(find.text('Calculate Size'));
      await tester.pumpAndSettle();
      final view = tester.widget<StorageAnalysisView>(
        find.byType(StorageAnalysisView),
      );
      expect(view.analysis.isComplete, isTrue);
      expect(view.analysis.root.path, '/c');
      expect(view.analysis.root.bytes, 3);
      expect(panel.currentPath, '/elsewhere');
      expect(cloud.scans, contains('/c'));
      expect(cloud.scans, isNot(contains('/elsewhere')));
      expect(cloud.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('unverified result folders cannot open a storage report', (
    tester,
  ) async {
    panel.showSearchResults([FileItem(name: 'c', path: '/c', isFolder: true)]);
    await mountMenu(tester, folder('c'));
    expect(find.text('Calculate Size'), findsNothing);
    expect(find.text('Stop scan'), findsNothing);
    expect(cloud.scans, isEmpty);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

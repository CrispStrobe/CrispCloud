import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/folder_size_measurement.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/storage_analysis_view.dart';
import 'package:crisp_cloud/widgets/storage_analyzer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';
import 'support/workspace_fixture.dart';

class _Cloud extends WorkflowFakeClient implements FreshCloudDirectoryReader {
  _Cloud([this.account = 'original']);
  final String account;
  @override
  String get userId => account;
  final scans = <String>[];
  final blocked = <String, Completer<void>>{};
  final entered = <String, Completer<void>>{};
  final denied = <String>{};
  final scanListings = <String, Map<String, dynamic>>{};
  int downloaded = 0;

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    scans.add(path);
    final signal = entered[path];
    if (signal != null && !signal.isCompleted) signal.complete();
    await blocked[path]?.future;
    if (denied.contains(path)) throw StateError('Permission denied');
    return scanListings[path] ?? super.listPath(path);
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    downloaded++;
    throw StateError('Measuring folders must not download contents');
  }
}

class _Local extends Fake
    implements
        LocalFileService,
        ScopedLocalFileOperations,
        LocalFileSourceIdentity {
  _Local(this.root) : currentPath = root;
  final String root;
  Object token = Object();
  final listed = <String>[];
  int activeScopes = 0;
  int scopes = 0;
  int released = 0;
  bool deny = false;
  Completer<void>? waitForAccess;
  Completer<void>? accessStarted;
  @override
  String currentPath;
  @override
  String get grantedBasePath => root;
  @override
  Object? sourceIdentityForPath(String path) =>
      p.equals(root, path) || p.isWithin(root, path) ? token : null;
  @override
  Future<String> getInitialPath() async => root;
  @override
  Future<String> getSafeFallbackDirectory() async => root;
  @override
  Future<bool> hasAccessToPath(String path) async => !deny;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    listed.add(path);
    return Directory(path).list(followLinks: false).toList();
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    scopes++;
    if (deny) throw FileSystemException('Access denied', path);
    activeScopes++;
    try {
      if (accessStarted?.isCompleted == false) accessStarted!.complete();
      await waitForAccess?.future;
      return await action();
    } finally {
      activeScopes--;
      released++;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Local local;
  late _Cloud cloud;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('folder-size-');
    local = _Local(root.path);
    cloud = _Cloud()..put('/box/file.bin', [1, 2, 3]);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    // Finish asynchronous provider restoration before widget tests enter their
    // fake clock. Individual scenarios still choose their explicit endpoint.
    final initial = container.read(panelProvider(PanelSide.remote));
    await Future<void>.delayed(Duration.zero);
    await initial.refresh();
  });

  tearDown(() async {
    for (final gate in cloud.blocked.values) {
      if (!gate.isCompleted) gate.complete();
    }
    if (local.waitForAccess?.isCompleted == false)
      local.waitForAccess!.complete();
    container.dispose();
    await root.delete(recursive: true);
  });

  Future<PanelNotifier> remote({
    PanelSide side = PanelSide.remote,
    String path = '/',
  }) async {
    final panel = container.read(panelProvider(side));
    await Future<void>.delayed(Duration.zero);
    container
        .read(panelSourceProvider(side).notifier)
        .setSource(
          RemotePanelSource(
            client: cloud,
            providerName: cloud.providerName,
            path: path,
          ),
        );
    await panel.refresh();
    return panel;
  }

  Future<PanelNotifier> native({PanelSide side = PanelSide.remote}) async {
    final panel = container.read(panelProvider(side));
    await Future<void>.delayed(Duration.zero);
    final origin = panel.resolveStorageReference(
      storageReferenceForSource(LocalPanelSource(root.path)),
      root.path,
    )!;
    await panel.navigateToPath(root.path, origin: origin);
    expect(panel.captureCurrentOrigin().source, isA<LocalPanelSource>());
    return panel;
  }

  FileItem folder(PanelNotifier panel, [String name = 'box']) =>
      panel.files!.firstWhere((file) => file.isFolder && file.name == name);

  test(
    'a remote folder with a real local alias measures only its captured cloud',
    () async {
      final physical = await Directory(p.join(root.path, 'box')).create();
      await File(p.join(physical.path, 'local.bin'))
          .writeAsBytes(List.filled(900, 1));
      cloud.put('${physical.path}/cloud.bin', List.filled(17, 2));
      final panel = await remote(side: PanelSide.local, path: root.path);
      final reads = local.listed.length;
      final result = await panel.calculateFolderSize(folder(panel));
      expect(result?.phase, FolderSizePhase.complete);
      expect(result?.bytes, 17);
      expect(folder(panel).calculatedSize, 17);
      expect(local.listed.length, reads);
      expect(local.scopes, 0);
      expect(cloud.downloaded, 0);
      expect(cloud.writes, isEmpty);
    },
  );

  test(
    'Space marks a verified folder and deduplicates its pending measurement',
    () async {
      final panel = await remote();
      final row = folder(panel);
      cloud.blocked['/box'] = Completer<void>();
      cloud.entered['/box'] = Completer<void>();
      panel.setCursorToItem(row);
      panel.spaceSelectAndAdvance();
      await cloud.entered['/box']!.future;
      final same = panel.calculateFolderSize(row);
      expect(panel.selection, contains(row));
      expect(panel.folderSizeFor(row)?.phase, FolderSizePhase.scanning);
      cloud.blocked['/box']!.complete();
      expect((await same)?.bytes, 3);
      expect(cloud.scans.where((path) => path == '/box'), hasLength(1));
      expect(panel.selection.single.calculatedSize, 3);
      expect(panel.originForFile(panel.selection.single)?.isCurrent, isTrue);
    },
  );

  test('partial provider pages never publish an exact folder size', () async {
    final panel = await remote();
    cloud.scanListings['/box'] = {
      'files': [
        {'name': 'known.bin', 'size': 9},
      ],
      'folders': [],
      'complete': false,
    };
    final row = folder(panel);
    final result = await panel.calculateFolderSize(row);
    expect(result?.phase, FolderSizePhase.partial);
    expect(result?.bytes, 9);
    expect(result?.issueCount, greaterThan(0));
    expect(folder(panel).calculatedSize, isNull);
    expect(panel.folderSizeFor(row)?.phase, FolderSizePhase.partial);
  });

  test(
    'unreadable directories remain failed and can be explicitly retried',
    () async {
      final panel = await remote();
      final row = folder(panel);
      cloud.denied.add('/');
      final failed = await panel.calculateFolderSize(row);
      expect(failed?.phase, FolderSizePhase.failed);
      expect(folder(panel).calculatedSize, isNull);
      cloud.denied.clear();
      final retried = await panel.calculateFolderSize(row);
      expect(retried?.phase, FolderSizePhase.complete);
      expect(folder(panel).calculatedSize, 3);
    },
  );

  test(
    'unknown sizes and skipped links remain explicit without following a link',
    () async {
      final panel = await remote();
      cloud.scanListings['/box'] = {
        'files': [
          {'name': 'known.bin', 'size': 4},
          {'name': 'unknown.bin'},
        ],
        'folders': [],
      };
      final result = await panel.calculateFolderSize(folder(panel));
      expect(result?.phase, FolderSizePhase.partial);
      expect(result?.bytes, 4);
      expect(result?.unknownSizes, 1);
      expect(folder(panel).calculatedSize, isNull);
    },
  );

  test(
    'inline entry limit produces a lower bound instead of an exact total',
    () async {
      final panel = await remote();
      cloud.scanListings['/box'] = {
        'files': [
          for (var i = 0; i <= PanelNotifier.maxInlineFolderSizeEntries; i++)
            {'name': '$i.bin', 'size': 1},
        ],
        'folders': [],
      };
      final result = await panel.calculateFolderSize(folder(panel));
      expect(result?.phase, FolderSizePhase.partial);
      expect(result?.limited, isTrue);
      expect(result?.bytes, PanelNotifier.maxInlineFolderSizeEntries);
      expect(folder(panel).calculatedSize, isNull);
    },
  );

  test(
    'only two scans run and queued cancellation never opens the folder',
    () async {
      for (final name in ['a', 'b', 'c', 'd']) {
        cloud.put('/$name/file.bin', [1]);
        cloud.blocked['/$name'] = Completer<void>();
        cloud.entered['/$name'] = Completer<void>();
      }
      final panel = await remote();
      final requests = [
        for (final name in ['a', 'b', 'c', 'd'])
          panel.calculateFolderSize(folder(panel, name)),
      ];
      await Future.wait([
        cloud.entered['/a']!.future,
        cloud.entered['/b']!.future,
      ]);
      expect(
        panel.folderSizeFor(folder(panel, 'c'))?.phase,
        FolderSizePhase.queued,
      );
      expect(cloud.scans, isNot(contains('/c')));
      expect(cloud.scans, isNot(contains('/d')));
      panel.cancelFolderSize(folder(panel, 'c'));
      expect((await requests[2])?.phase, FolderSizePhase.cancelled);
      cloud.blocked['/a']!.complete();
      await cloud.entered['/d']!.future;
      cloud.blocked['/b']!.complete();
      cloud.blocked['/d']!.complete();
      await Future.wait(requests);
      expect(cloud.scans, isNot(contains('/c')));
    },
  );

  test('running cancellation discards the late folder listing', () async {
    final panel = await remote();
    final row = folder(panel);
    cloud.blocked['/box'] = Completer<void>();
    cloud.entered['/box'] = Completer<void>();
    final pending = panel.calculateFolderSize(row);
    await cloud.entered['/box']!.future;
    panel.cancelFolderSize(row);
    expect(panel.folderSizeFor(row)?.phase, FolderSizePhase.stopping);
    cloud.blocked['/box']!.complete();
    expect((await pending)?.phase, FolderSizePhase.cancelled);
    expect(folder(panel).calculatedSize, isNull);
  });

  test(
    'sorting during a scan follows the original row at its new index',
    () async {
      cloud.put('/aaa/other.bin', [9, 9]);
      final panel = await remote();
      final row = folder(panel);
      panel.selectVisibleItems([row], cursor: row);
      final oldIndex = panel.files!.indexWhere((file) => identical(file, row));
      cloud.blocked['/box'] = Completer<void>();
      cloud.entered['/box'] = Completer<void>();
      final pending = panel.calculateFolderSize(row);
      await cloud.entered['/box']!.future;

      panel.toggleSortOrder();
      final newIndex = panel.files!.indexWhere((file) => identical(file, row));
      expect(newIndex, isNot(oldIndex));
      expect(panel.folderSizeFor(row)?.phase, FolderSizePhase.scanning);
      cloud.blocked['/box']!.complete();

      expect((await pending)?.phase, FolderSizePhase.complete);
      final measured = folder(panel);
      expect(measured.calculatedSize, 3);
      expect(identical(panel.files![newIndex], measured), isTrue);
      expect(identical(panel.selection.single, measured), isTrue);
      expect(panel.originForFile(measured)?.isCurrent, isTrue);
      expect(folder(panel, 'aaa').calculatedSize, isNull);
      expect(cloud.scans.where((path) => path == '/box'), hasLength(1));
    },
  );

  test(
    'removing a row from the current list invalidates its cached index',
    () async {
      cloud.put('/aaa/other.bin', [9]);
      final panel = await remote();
      final row = folder(panel);
      expect(identical(panel.files!.last, row), isTrue);
      cloud.blocked['/box'] = Completer<void>();
      cloud.entered['/box'] = Completer<void>();
      final pending = panel.calculateFolderSize(row);
      await cloud.entered['/box']!.future;

      // Change membership without changing the listing generation. The index
      // hint must prove continued object identity on every authority check.
      panel.files!.removeWhere((file) => identical(file, row));
      cloud.blocked['/box']!.complete();

      expect(await pending, isNull);
      expect(row.calculatedSize, isNull);
      expect(folder(panel, 'aaa').calculatedSize, isNull);
      expect(await panel.calculateFolderSize(row), isNull);
      expect(cloud.scans.where((path) => path == '/box'), hasLength(1));
    },
  );

  test(
    'an equal-path replacement at the hinted index cannot inherit a scan',
    () async {
      final panel = await remote();
      final row = folder(panel);
      final index = panel.files!.indexWhere((file) => identical(file, row));
      cloud.blocked['/box'] = Completer<void>();
      cloud.entered['/box'] = Completer<void>();
      final pending = panel.calculateFolderSize(row);
      await cloud.entered['/box']!.future;

      final replacement = row.copyWith();
      expect(replacement, row);
      expect(identical(replacement, row), isFalse);
      panel.files![index] = replacement;
      cloud.blocked['/box']!.complete();

      expect(await pending, isNull);
      expect(replacement.calculatedSize, isNull);
      expect(panel.folderSizeFor(replacement), isNull);
      expect(panel.originForFile(replacement), isNull);
      expect(await panel.calculateFolderSize(replacement), isNull);
      expect(cloud.scans.where((path) => path == '/box'), hasLength(1));
    },
  );

  test(
    'unchanged progress preserves one scanning transition and the final result',
    () async {
      final panel = await remote();
      cloud.scanListings['/box'] = {'files': [], 'folders': []};
      final phases = <FolderSizePhase?>[];
      void changed() => phases.add(panel.folderSizeFor(folder(panel))?.phase);
      panel.addListener(changed);
      try {
        final result = await panel.calculateFolderSize(folder(panel));
        expect(result?.bytes, 0);
        expect(result?.phase, FolderSizePhase.complete);
        expect(folder(panel).calculatedSize, 0);
        expect(phases, [
          FolderSizePhase.queued,
          FolderSizePhase.scanning,
          FolderSizePhase.complete,
        ]);
      } finally {
        panel.removeListener(changed);
      }
    },
  );

  test('a refreshed same-path row cannot inherit a late measurement', () async {
    final panel = await remote();
    final row = folder(panel);
    cloud.blocked['/box'] = Completer<void>();
    cloud.entered['/box'] = Completer<void>();
    final pending = panel.calculateFolderSize(row);
    await cloud.entered['/box']!.future;
    await panel.refresh();
    final replacement = folder(panel);
    expect(identical(row, replacement), isFalse);
    cloud.blocked['/box']!.complete();
    expect(await pending, isNull);
    expect(replacement.calculatedSize, isNull);
    expect(panel.folderSizeFor(replacement), isNull);
    expect(await panel.calculateFolderSize(row), isNull);
  });

  test(
    'restored file-list rows stop showing an invalidated measurement',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        folder(panel),
      ], origin: panel.captureCurrentOrigin());
      final resultsTab = panel.activeTabId;
      final row = folder(panel);
      cloud.blocked['/box'] = Completer<void>();
      cloud.entered['/box'] = Completer<void>();
      final pending = panel.calculateFolderSize(row);
      await cloud.entered['/box']!.future;
      expect(panel.folderSizeFor(row)?.phase, FolderSizePhase.scanning);

      final other = PanelTab(
        id: 'other-directory',
        path: '/elsewhere',
        storage: panel.activeTab!.storage,
      );
      panel.tabs.add(other);
      await panel.selectTab(other.id);
      cloud.blocked['/box']!.complete();
      expect(await pending, isNull);

      await panel.selectTab(resultsTab);
      final restored = folder(panel);
      expect(identical(restored, row), isTrue);
      expect(panel.originForFile(restored)?.isCurrent, isTrue);
      expect(panel.folderSizeFor(restored)?.phase, FolderSizePhase.cancelled);
      expect(panel.folderSizeFor(restored)?.isActive, isFalse);
      expect(panel.folderSizeFor(restored)?.bytes, 0);
      expect(restored.calculatedSize, isNull);
      expect(cloud.scans.where((path) => path == '/box'), hasLength(1));

      expect((await panel.calculateFolderSize(restored))?.bytes, 3);
      expect(folder(panel).calculatedSize, 3);
    },
  );

  test(
    'changing accounts during a scan cannot attach bytes to a same-path row',
    () async {
      final panel = await remote();
      final original = folder(panel);
      cloud.blocked['/box'] = Completer<void>();
      cloud.entered['/box'] = Completer<void>();
      final pending = panel.calculateFolderSize(original);
      await cloud.entered['/box']!.future;
      final other = _Cloud('other')..put('/box/other.bin', List.filled(19, 0));
      container
          .read(multiCloudProvider)
          .addConnection(
            id: 'other',
            label: 'Other',
            provider: CloudProvider.s3,
            client: other,
          );
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(
            RemotePanelSource(
              client: other,
              providerName: other.providerName,
              path: '/',
            ),
          );
      await panel.refresh();
      cloud.blocked['/box']!.complete();
      expect(await pending, isNull);
      expect(folder(panel).calculatedSize, isNull);
      expect((await panel.calculateFolderSize(folder(panel)))?.bytes, 19);
      expect(other.downloaded, 0);
    },
  );

  test(
    'native scans use scoped access on the right and skip outside symlinks',
    () async {
      final box = await Directory(p.join(root.path, 'box')).create();
      await File(p.join(box.path, 'inside.bin')).writeAsBytes([1, 2, 3, 4]);
      final outside = await Directory(p.join(root.path, 'outside')).create();
      await File(p.join(outside.path, 'unrelated.bin'))
          .writeAsBytes(List.filled(100, 1));
      if (!Platform.isWindows)
        await Link(p.join(box.path, 'link')).create(outside.path);
      final panel = await native();
      final result = await panel.calculateFolderSize(folder(panel));
      expect(result?.phase, FolderSizePhase.complete);
      expect(result?.bytes, 4);
      if (!Platform.isWindows) expect(result?.skippedLinks, 1);
      expect(local.scopes, greaterThan(0));
      expect(local.released, local.scopes);
      expect(local.activeScopes, 0);
      expect(panel.freeBytes, isNotNull);
      expect(cloud.scans, isEmpty);
    },
  );

  test(
    'replacing a local grant invalidates a scan before scoped work returns',
    () async {
      await Directory(p.join(root.path, 'box')).create();
      await File(p.join(root.path, 'box/file.bin')).writeAsBytes([1, 2, 3]);
      final panel = await native();
      final row = folder(panel);
      local.waitForAccess = Completer<void>();
      local.accessStarted = Completer<void>();
      final pending = panel.calculateFolderSize(row);
      await local.accessStarted!.future;
      local.token = Object();
      local.waitForAccess!.complete();
      expect(await pending, isNull);
      expect(row.calculatedSize, isNull);
      expect(panel.folderSizeFor(row)?.sourceChanged, isTrue);
      expect(local.activeScopes, 0);
    },
  );

  test(
    'detached and unverified rows cannot authorize a folder measurement',
    () async {
      final panel = await remote();
      final row = folder(panel);
      cloud.scans.clear();
      expect(await panel.calculateFolderSize(row.copyWith()), isNull);
      panel.showSearchResults([row.copyWith()]);
      expect(await panel.calculateFolderSize(panel.files!.single), isNull);
      expect(cloud.scans, isEmpty);
    },
  );

  testWidgets(
    'folder report keeps its captured remote endpoint after pane navigation',
    (tester) async {
      final panel = container.read(panelProvider(PanelSide.remote));
      final row = folder(panel);
      final origin = panel.originForFile(row)!;
      cloud.blocked['/box'] = Completer<void>();
      cloud.entered['/box'] = Completer<void>();
      tester.view.physicalSize = const Size(1100, 800);
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
                  onPressed: () =>
                      showFolderSizeDialog(context, ref, row, origin),
                  child: const Text('Measure folder'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Measure folder'));
      for (var i = 0; i < 20 && !cloud.entered['/box']!.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(cloud.entered['/box']!.isCompleted, isTrue);
      await tester.runAsync(() async {
        await panel.navigateToPath('/elsewhere');
        cloud.blocked['/box']!.complete();
      });
      await tester.pumpAndSettle();
      final view = tester.widget<StorageAnalysisView>(
        find.byType(StorageAnalysisView),
      );
      expect(view.analysis.isComplete, isTrue);
      expect(view.analysis.root.path, '/box');
      expect(view.analysis.root.bytes, 3);
      expect(panel.currentPath, '/elsewhere');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

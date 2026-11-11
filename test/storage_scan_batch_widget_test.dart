import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/storage_analyzer_strings.dart';
import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_batch_service.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:crisp_cloud/services/storage_scan_snapshot_store.dart';
import 'package:crisp_cloud/widgets/storage_analysis_view.dart';
import 'package:crisp_cloud/widgets/storage_scan_batch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';
import 'support/workspace_fixture.dart';

class _Cloud extends WorkflowFakeClient implements FreshCloudDirectoryReader {
  _Cloud(this.account);

  final String account;
  @override
  String? get userId => account;
  final reads = <String>[];
  String? heldPath;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    reads.add(path);
    if (path == heldPath) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
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

class _UnconfirmedStore extends StorageScanSnapshotStore {
  _UnconfirmedStore() : super(storage: MemoryFileCollectionStorage());

  int saveCalls = 0;

  @override
  Future<StorageScanSnapshotSummary> save({
    required StorageScanResult result,
    required String storageId,
    required String sourceLabel,
    p.Style? pathStyle,
    bool Function()? isCancelled,
  }) async {
    saveCalls++;
    final saved = await super.save(
      result: result,
      storageId: storageId,
      sourceLabel: sourceLabel,
      pathStyle: pathStyle,
      isCancelled: isCancelled,
    );
    // Model a committed report whose acknowledgement/readback failed. History
    // has recovered by the time the user explicitly opens it for inspection.
    throw StorageScanSnapshotCommitUnconfirmed(
      snapshotId: saved.id,
      cause: StateError('Acknowledgement lost'),
      recoveryCause: StateError('History unavailable during recovery'),
    );
  }
}

StorageScanBatchRoot _root(_Cloud cloud, String path) => StorageScanBatchRoot(
  source: CloudStorageScanBackend(cloud, isCurrent: () => cloud.current),
  rootPath: path,
  storage: storageReferenceForClient(cloud),
  sourceLabel: cloud.account,
  serialReadKey: cloud,
);

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void _viewport(
  WidgetTester tester, [
  Size size = const Size(1100, 900),
]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'verified mixed-source result folders keep their captured roots after navigation',
    () async {
      final harness = await WorkspaceTestHarness.create();
      addTearDown(harness.dispose);
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      final original = panel.files!.firstWhere((file) => file.isFolder);
      final firstOrigin = panel.originForFile(original)!;
      final other = _Cloud('other')
        ..put('/one/other.bin', List.filled(19, 1));
      harness.container.read(multiCloudProvider).addConnection(
        id: 'other',
        label: 'Other original',
        provider: CloudProvider.s3,
        client: other,
      );
      final otherOrigin = panel.resolveStorageReference(
        storageReferenceForClient(other),
        '/',
      )!;
      final otherRow = FileItem(name: 'one', path: '/one', isFolder: true);
      panel.showSearchResults(
        [original, otherRow],
        originForFile: (file) =>
            identical(file, original) ? firstOrigin : otherOrigin,
      );
      panel.selectVisibleItems(panel.files!);
      final roots = captureMarkedStorageScanRoots(
        panel,
        harness.container.read(localFileServiceProvider),
      );
      expect(roots, hasLength(2));
      expect(roots.map((root) => root.rootPath), ['/one', '/one']);
      expect(roots.map((root) => root.storage.id).toSet(), hasLength(2));
      harness.cloud.put('/elsewhere/large.bin', List.filled(700, 1));
      await panel.navigateToPath('/elsewhere', origin: firstOrigin);
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      final batch = StorageScanBatchService(roots: roots, snapshots: store);
      addTearDown(batch.dispose);
      await batch.start();
      expect(batch.jobs.map((job) => job.snapshot!.bytes), [3, 19]);
      expect(panel.currentPath, '/elsewhere');
      expect(
        batch.jobs.map((job) => job.snapshot!.rootPath),
        ['/one', '/one'],
      );
    },
  );

  test(
    'unverified result rows explain unavailability without source fallback',
    () async {
      final harness = await WorkspaceTestHarness.create();
      addTearDown(harness.dispose);
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      final original = panel.files!.firstWhere((file) => file.isFolder);
      panel.showSearchResults([original.copyWith()]);
      panel.selectVisibleItems(panel.files!);
      expect(
        () => captureMarkedStorageScanRoots(
          panel,
          harness.container.read(localFileServiceProvider),
        ),
        throwsA(
          isA<StorageScanBatchCaptureFailure>()
              .having((error) => error.key, 'key', 'batchUnavailable')
              .having(
                (error) => error.values['path'],
                'original path',
                original.path,
              ),
        ),
      );
    },
  );

  test(
    'paged collection marks outside the verified window receive an explicit explanation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = _Cloud('collection');
      for (var i = 0; i < 501; i++) {
        cloud.put('/folder-${i.toString().padLeft(4, '0')}/file.bin', [1]);
      }
      final local = _Local();
      final store = FileCollectionStore(
        storage: MemoryFileCollectionStorage(),
      );
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
          localFileServiceProvider.overrideWithValue(local),
          fileCollectionStoreProvider.overrideWith((_) => store),
        ],
      );
      addTearDown(container.dispose);
      final panel = container.read(panelProvider(PanelSide.remote));
      await Future<void>.delayed(Duration.zero);
      await panel.refresh();
      final entries = [
        for (final file in panel.files!)
          if (file.isFolder && file.name != '..')
            FileCollectionService.capture(
              file,
              storageReferenceForClient(cloud),
            ),
      ];
      await store.save(
        FileCollection(id: 'folders', name: 'Folders', entries: entries),
      );
      await panel.openCollection('folders');
      final selected = panel.files!.first;
      panel.toggleSelection(selected);
      expect(
        captureMarkedStorageScanRoots(panel, local).single.rootPath,
        selected.path,
      );
      await panel.loadCollectionPage(1);
      expect(panel.selection.single.path, selected.path);
      expect(panel.originForFile(panel.selection.single), isNull);
      final oldReads = cloud.reads.length;
      expect(
        () => captureMarkedStorageScanRoots(panel, local),
        throwsA(
          isA<StorageScanBatchCaptureFailure>()
              .having((error) => error.key, 'key', 'batchUnverified')
              .having(
                (error) => error.values['path'],
                'original path',
                selected.path,
              ),
        ),
      );
      expect(cloud.reads.length, oldReads);
    },
  );

  testWidgets(
    'batch review keeps the captured session label when another session shares its account',
    (tester) async {
      _viewport(tester);
      final harness = await WorkspaceTestHarness.create();
      addTearDown(harness.dispose);
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      final other = _Cloud(harness.cloud.userId!)
        ..put('/one/other.bin', List.filled(99, 1));
      expect(
        storageReferenceForClient(other),
        storageReferenceForClient(harness.cloud),
      );
      harness.container.read(multiCloudProvider).addConnection(
        id: 'duplicate-session',
        label: 'Other session',
        provider: CloudProvider.s3,
        client: other,
      );
      await panel.refresh();
      final selected = panel.files!.firstWhere((file) => file.isFolder);
      final origin = panel.originForFile(selected)!;
      panel.toggleSelection(selected);
      final captured = captureMarkedStorageScanRoots(
        panel,
        harness.container.read(localFileServiceProvider),
      ).single;
      final account = origin.storageReference.accountKey;
      expect(
        captured.sourceLabel,
        'Memory · ${account.substring(0, 8)}',
      );
      expect(captured.storage.id, origin.storageId);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: _app(
            Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showStorageScanBatchDialog(context, ref),
                child: const Text('Review marked folders'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review marked folders'));
      await tester.pumpAndSettle();
      final batch = tester.widget<StorageScanBatchDialog>(
        find.byType(StorageScanBatchDialog),
      ).batch;
      expect(batch.hasStarted, isFalse);
      expect(
        batch.jobs.single.root.sourceLabel,
        'Memory · workspace@example.test',
      );
      expect(batch.jobs.single.root.storage.id, origin.storageId);
      expect(find.text('Other session (Memory)'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('scan-batch-start')));
      await tester.pumpAndSettle();
      final saved = batch.jobs.single.snapshot!;
      expect(saved.sourceLabel, 'Memory · workspace@example.test');
      expect(saved.storageId, origin.storageId);
      expect(saved.bytes, 3);
      expect(other.reads, isEmpty);
      harness.cloud.current = false;
      expect(batch.jobs.single.root.isCurrent, isFalse);
      expect(other.current, isTrue);
      expect(batch.jobs.single.phase, StorageScanBatchPhase.saved);
      await tester.tap(find.byKey(const ValueKey('scan-batch-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review starts only on request and opens the exact committed report offline',
    (tester) async {
      _viewport(tester);
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      final first = _Cloud('First account')
        ..put('/data/first.bin', List.filled(3, 1));
      final second = _Cloud('Second account')
        ..put('/data/second.bin', List.filled(19, 1));
      final batch = StorageScanBatchService(
        roots: [_root(first, '/data'), _root(second, '/data')],
        snapshots: store,
      );
      await tester.pumpWidget(_app(StorageScanBatchDialog(batch: batch)));
      expect(first.reads, isEmpty);
      expect(second.reads, isEmpty);
      expect(find.text('Ready to scan'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('scan-batch-start')));
      await tester.pumpAndSettle();
      expect(batch.jobs.every((job) => job.snapshot != null), isTrue);
      expect(await store.list(), hasLength(2));
      first.current = false;
      second.current = false;
      final firstReads = first.reads.length;
      final secondReads = second.reads.length;
      await tester.tap(find.byKey(const ValueKey('scan-batch-open-0')));
      await tester.pumpAndSettle();
      final report = tester.widget<StorageAnalysisView>(
        find.byType(StorageAnalysisView),
      ).analysis;
      expect(report.root.bytes, 3);
      expect(report.root.children.single.name, 'first.bin');
      expect(find.text('Show in file panel'), findsNothing);
      expect(find.text('Rescan original folder'), findsNothing);
      expect(first.reads.length, firstReads);
      expect(second.reads.length, secondReads);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Stop shows unsaved state after a blocked scan releases',
    (tester) async {
      _viewport(tester);
      final cloud = _Cloud('Original account')
        ..put('/data/late.bin', List.filled(99, 1))
        ..heldPath = '/data';
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      final batch = StorageScanBatchService(
        roots: [_root(cloud, '/data')],
        snapshots: store,
      );
      await tester.pumpWidget(_app(StorageScanBatchDialog(batch: batch)));
      await tester.tap(find.byKey(const ValueKey('scan-batch-start')));
      await tester.pump();
      expect(cloud.entered.isCompleted, isTrue);
      await tester.tap(find.byKey(const ValueKey('scan-batch-stop')));
      await tester.pump();
      expect(batch.isStopping, isTrue);
      cloud.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Stopped · Report not saved'), findsOneWidget);
      expect(find.byKey(const ValueKey('scan-batch-open-0')), findsNothing);
      expect(await store.list(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing a running batch cancels late data without losing committed history',
    (tester) async {
      _viewport(tester);
      final first = _Cloud('Saved')..put('/saved/file', [1]);
      final pending = _Cloud('Pending')
        ..put('/pending/file', List.filled(9, 1))
        ..heldPath = '/pending';
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      final batch = StorageScanBatchService(
        roots: [_root(first, '/saved'), _root(pending, '/pending')],
        snapshots: store,
      );
      await tester.pumpWidget(_app(StorageScanBatchDialog(batch: batch)));
      await tester.tap(find.byKey(const ValueKey('scan-batch-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(batch.jobs.first.snapshot, isNotNull);
      expect(pending.entered.isCompleted, isTrue);
      await tester.pumpWidget(_app(const Text('Closed')));
      pending.release.complete();
      await tester.pumpAndSettle();
      expect(batch.jobs.last.phase, StorageScanBatchPhase.cancelled);
      expect(await store.list(), hasLength(1));
      expect(find.text('Closed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unconfirmed saves offer history inspection in a compact Arabic layout',
    (tester) async {
      _viewport(tester, const Size(390, 780));
      final cloud = _Cloud('Original account')
        ..put('/data/file', List.filled(13, 1));
      final store = _UnconfirmedStore();
      final batch = StorageScanBatchService(
        roots: [_root(cloud, '/data')],
        snapshots: store,
      );
      final strings = StorageAnalyzerStrings.forLanguage('ar');
      await tester.pumpWidget(
        _app(
          StorageScanBatchDialog(batch: batch),
          locale: const Locale('ar'),
          scale: 1.5,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('scan-batch-start')));
      await tester.pumpAndSettle();
      expect(batch.jobs.single.phase, StorageScanBatchPhase.unconfirmed);
      expect(find.text(strings.text('batchUnconfirmed')), findsOneWidget);
      expect(
        find.text(
          strings.text('batchUnconfirmedHint', {
            'history': strings.text('savedScans'),
          }),
        ),
        findsOneWidget,
      );
      expect(
        find.text(strings.text('batchUnconfirmedCount', {'count': 1})),
        findsOneWidget,
      );
      expect(find.text(strings.text('batchStopped')), findsNothing);
      expect(find.byKey(const ValueKey('scan-batch-start')), findsNothing);
      expect(find.byKey(const ValueKey('scan-batch-open-0')), findsNothing);
      expect(tester.takeException(), isNull);
      cloud.current = false;
      final reads = cloud.reads.length;
      final historyButton = find.byKey(
        const ValueKey('scan-batch-history-0'),
      );
      await tester.ensureVisible(historyButton);
      await tester.pumpAndSettle();
      expect(historyButton.hitTestable(), findsOneWidget);
      await tester.tap(historyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Original account'));
      await tester.pumpAndSettle();
      final report = tester.widget<StorageAnalysisView>(
        find.byType(StorageAnalysisView),
      ).analysis;
      expect(report.root.bytes, 13);
      expect(report.root.children.single.path, '/data/file');
      expect(cloud.reads.length, reads);
      expect(store.saveCalls, 1);
      expect(find.text(strings.text('reveal')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact Arabic review and running controls preserve literal LTR paths',
    (tester) async {
      _viewport(tester, const Size(390, 780));
      const path = '/بيانات/{files}/original';
      final cloud = _Cloud('المصدر الأصلي')
        ..put('$path/file', [1])
        ..heldPath = path;
      final batch = StorageScanBatchService(
        roots: [_root(cloud, path)],
        snapshots: StorageScanSnapshotStore(
          storage: MemoryFileCollectionStorage(),
        ),
      );
      final strings = StorageAnalyzerStrings.forLanguage('ar');
      await tester.pumpWidget(
        _app(
          StorageScanBatchDialog(batch: batch),
          locale: const Locale('ar'),
          scale: 1.5,
        ),
      );
      final pathText = tester.widget<Text>(
        find.byKey(const ValueKey('scan-batch-path-0')),
      );
      expect(pathText.data, path);
      expect(pathText.textDirection, TextDirection.ltr);
      expect(find.text(strings.text('batchStart')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scan-batch-start')));
      await tester.pump();
      expect(find.text(strings.text('batchStopAndClose')), findsOneWidget);
      expect(tester.takeException(), isNull);
      batch.cancel();
      cloud.release.complete();
      await tester.pumpAndSettle();
      expect(find.text(strings.text('batchStopped')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

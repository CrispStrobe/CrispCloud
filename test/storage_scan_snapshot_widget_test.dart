import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:crisp_cloud/services/storage_scan_snapshot_store.dart';
import 'package:crisp_cloud/widgets/storage_analysis_view.dart';
import 'package:crisp_cloud/widgets/storage_analyzer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/workflow_fake_client.dart';

StorageScanResult _report(String name, int bytes) => StorageScanResult(
  root: StorageNode(
    item: FileItem(name: '/', path: '/', isFolder: true),
    bytes: bytes,
    fileCount: 1,
    folderCount: 0,
    children: [
      StorageNode(
        item: FileItem(
          name: name,
          path: '/$name',
          isFolder: false,
          size: bytes,
        ),
        bytes: bytes,
        fileCount: 1,
        folderCount: 0,
      ),
    ],
  ),
  cancelled: false,
  limited: false,
  sourceChanged: false,
  startedAt: DateTime.utc(2026, 1, 1),
  completedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
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
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void _viewport(WidgetTester tester, {Size size = const Size(1200, 900)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _PendingScan extends StorageScanService {
  final release = Completer<StorageScanResult>();
  bool Function()? cancelled;
  void Function(StorageScanProgress)? progress;
  int calls = 0;

  @override
  Future<StorageScanResult> scan(
    FileOperationBackend source,
    String rootPath, {
    bool Function()? isCancelled,
    void Function(StorageScanProgress)? onProgress,
    int maxEntries = 200000,
    int maxDepth = 200,
    int maxIssues = 1000,
    Duration progressInterval = const Duration(milliseconds: 100),
  }) {
    calls++;
    cancelled = isCancelled;
    progress = onProgress;
    return release.future;
  }
}

void main() {
  testWidgets('saved reports browse offline without a source or live actions', (
    tester,
  ) async {
    _viewport(tester);
    final store = StorageScanSnapshotStore(
      storage: MemoryFileCollectionStorage(),
    );
    await store.save(
      result: _report('historical.txt', 123),
      storageId: 'disconnected-account',
      sourceLabel: 'Offline archive',
    );
    await tester.pumpWidget(
      _app(StorageAnalyzerDialog(snapshotStore: store, historyOnly: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline archive'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Offline archive'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StorageAnalysisView>(find.byType(StorageAnalysisView))
          .analysis
          .root
          .bytes,
      123,
    );
    expect(find.textContaining('Historical scan'), findsOneWidget);
    expect(find.text('Show in file panel'), findsNothing);
    expect(find.text('Rescan original folder'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening history cancels old scan generation and cannot enable a different account',
    (tester) async {
      _viewport(tester);
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      await store.save(
        result: _report('saved.txt', 123),
        storageId: 'old-account',
        sourceLabel: 'Old account',
      );
      final pending = _PendingScan();
      final client = WorkflowFakeClient();
      var reveals = 0;
      await tester.pumpWidget(
        _app(
          StorageAnalyzerDialog(
            source: CloudStorageScanBackend(
              client,
              isCurrent: () => client.current,
            ),
            rootPath: '/',
            sourceLabel: 'New account',
            storageId: 'new-account',
            service: pending,
            snapshotStore: store,
            onReveal: (_) async {
              reveals++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Saved scans'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(ListTile, 'Old account'));
      await tester.pumpAndSettle();
      expect(pending.cancelled!(), isTrue);
      expect(find.text('Show in file panel'), findsNothing);
      final rescan = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Rescan original folder'),
      );
      expect(rescan.onPressed, isNull);
      pending.progress?.call(
        const StorageScanProgress(
          files: 999,
          folders: 99,
          bytes: 999,
          currentPath: '/old-progress',
        ),
      );
      pending.release.complete(_report('late.txt', 999));
      await tester.pumpAndSettle();
      final report = tester
          .widget<StorageAnalysisView>(find.byType(StorageAnalysisView))
          .analysis;
      expect(report.root.bytes, 123);
      expect(report.root.children.single.name, 'saved.txt');
      expect(reveals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit save and full rescan preserve both historical versions',
    (tester) async {
      _viewport(tester);
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      final client = WorkflowFakeClient()..put('/a.txt', [1]);
      await tester.pumpWidget(
        _app(
          StorageAnalyzerDialog(
            source: CloudStorageScanBackend(
              client,
              isCurrent: () => client.current,
            ),
            rootPath: '/',
            sourceLabel: 'Connected account',
            storageId: 'account',
            snapshotStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scan'));
      await tester.pumpAndSettle();
      expect((await store.list()).length, 1);
      client.put('/a.txt', [1, 2, 3]);
      await tester.tap(find.text('Rescan original folder'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StorageAnalysisView>(find.byType(StorageAnalysisView))
            .analysis
            .root
            .bytes,
        3,
      );
      await tester.tap(find.text('Save scan'));
      await tester.pumpAndSettle();
      final history = await store.list();
      expect(history.length, 2);
      expect(history.map((entry) => entry.bytes).toSet(), {1, 3});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a different selected root cannot activate historical live actions',
    (tester) async {
      _viewport(tester);
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      await store.save(
        result: _report('saved.txt', 1),
        storageId: 'same-account',
        sourceLabel: 'Root history',
      );
      final client = WorkflowFakeClient()..put('/other/live.txt', [1]);
      await tester.pumpWidget(
        _app(
          StorageAnalyzerDialog(
            source: CloudStorageScanBackend(
              client,
              isCurrent: () => client.current,
            ),
            rootPath: '/other',
            sourceLabel: 'Same account',
            storageId: 'same-account',
            snapshotStore: store,
            historyOnly: true,
            onReveal: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Root history'));
      await tester.pumpAndSettle();
      expect(find.text('Show in file panel'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Rescan original folder'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history and snapshot controls fit compact German text', (
    tester,
  ) async {
    _viewport(tester, size: const Size(360, 640));
    final store = StorageScanSnapshotStore(
      storage: MemoryFileCollectionStorage(),
    );
    await store.save(
      result: _report('klein.txt', 1),
      storageId: 'offline',
      sourceLabel: 'Archiv',
    );
    await tester.pumpWidget(
      _app(
        StorageAnalyzerDialog(snapshotStore: store, historyOnly: true),
        locale: const Locale('de'),
        scale: 1.8,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Archiv'));
    await tester.pumpAndSettle();
    expect(find.byType(StorageAnalysisView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

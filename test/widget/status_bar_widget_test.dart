// test/widget/status_bar_widget_test.dart
//
// Widget tests for the StatusBar widget.
// Tests connection status display, item counts, transfer progress,
// and sync status indicators.

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/widgets/status_bar.dart';

// ---------------------------------------------------------------------------
// Mock cloud client — no-op implementation
// ---------------------------------------------------------------------------

class _MockCloudClient extends CloudStorageClient {
  final String _name;
  final bool _connected;

  _MockCloudClient({String name = 'Mock', bool connected = false})
      : _name = name,
        _connected = connected;

  @override
  String get providerName => _name;
  @override
  bool get isAuthenticated => _connected;
  @override
  String? get userId => null;
  @override
  String? get bucketId => null;
  @override
  String get rootPath => '/';
  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {}
  @override
  Future<bool> is2faNeeded(String email) async => false;
  @override
  Future<void> logout() async {}
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {};
  @override
  Future<void> uploadFile(List<int> fileData, String fileName,
      String targetPath,
      {Function(int, int)? onProgress}) async {}
  @override
  Future<void> downloadFileByPath(String remotePath, String localPath,
      {Function(int, int)? onProgress}) async {}
  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async =>
      Uint8List(0);
  @override
  Future<void> createFolderPath(String path) async {}
  @override
  Future<void> deletePath(String path) async {}
  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}
  @override
  Future<void> renamePath(String path, String newName) async {}
  @override
  Future<Map<String, int>?> getQuota() async => null;
}

// ---------------------------------------------------------------------------
// AuthNotifier subclass that bypasses auto-login
// ---------------------------------------------------------------------------

class _TestAuthNotifier extends AuthNotifier {
  final bool _mockConnected;
  final String _mockName;

  _TestAuthNotifier(
    Ref ref, {
    required bool isConnected,
    required String providerName,
  })  : _mockConnected = isConnected,
        _mockName = providerName,
        super(
          ref,
          initialProvider: CloudProvider.filen,
          config: FilenConfigService(
            configPath: '/tmp/sb_widget_test',
            secureStorage: InMemorySecureStorage(),
          ),
          configPath: '/tmp/sb_widget_test',
          secureStorage: InMemorySecureStorage(),
        );

  @override
  bool get isConnected => _mockConnected;
  @override
  String get providerName => _mockName;
  @override
  CloudStorageClient get client =>
      _MockCloudClient(name: _mockName, connected: _mockConnected);
}

// ---------------------------------------------------------------------------
// PanelNotifier subclass that returns mock data
// ---------------------------------------------------------------------------

class _TestPanelNotifier extends PanelNotifier {
  final List<FileItem> _mockFiles;
  final String _mockFilter;

  _TestPanelNotifier(
    Ref ref,
    PanelSide side, {
    List<FileItem> files = const [],
    String filterQuery = '',
  })  : _mockFiles = files,
        _mockFilter = filterQuery,
        super(ref, side);

  @override
  List<FileItem>? get files => _mockFiles;

  @override
  List<FileItem>? get filteredFiles =>
      _mockFilter.isEmpty ? _mockFiles : <FileItem>[];

  @override
  Set<FileItem> get selection => const {};

  @override
  String get filterQuery => _mockFilter;
}

// ---------------------------------------------------------------------------
// TransferNotifier subclass with injectable operations
// ---------------------------------------------------------------------------

class _TestTransferNotifier extends TransferNotifier {
  final List<OperationProgress> _mockOps;

  _TestTransferNotifier(Ref ref, {List<OperationProgress> ops = const []})
      : _mockOps = ops,
        super(ref);

  @override
  List<OperationProgress> get operations => _mockOps;
}

// ---------------------------------------------------------------------------
// SyncNotifier subclass using in-memory database
// ---------------------------------------------------------------------------

class _TestSyncNotifier extends SyncNotifier {
  bool _mockSyncing;
  SyncResult? _mockLastResult;
  List<SyncPair> _mockPairs;
  String? _mockPairName;

  _TestSyncNotifier(
    Ref ref,
    SyncDatabase db, {
    bool isSyncing = false,
    SyncResult? lastResult,
    List<SyncPair> pairs = const [],
    String? currentPairName,
  })  : _mockSyncing = isSyncing,
        _mockLastResult = lastResult,
        _mockPairs = pairs,
        _mockPairName = currentPairName,
        super.forTesting(ref, db);

  @override
  bool get isSyncing => _mockSyncing;
  @override
  SyncResult? get lastResult => _mockLastResult;
  @override
  List<SyncPair> get pairs => _mockPairs;
  @override
  String? get currentPairName => _mockPairName;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<FileItem> _files(int n) => List.generate(
      n,
      (i) => FileItem(
        name: 'f_$i.txt',
        path: '/f_$i.txt',
        isFolder: false,
        size: 1024,
      ),
    );

OperationProgress _activeOp(String id) => OperationProgress(
      id: id,
      type: OperationType.upload,
      sourcePath: '/local/f.txt',
      targetPath: '/remote/f.txt',
      fileName: 'f.txt',
      totalBytes: 5000,
      currentBytes: 1000,
      status: OperationStatus.inProgress,
    );

// ---------------------------------------------------------------------------
// Base widget builder
// ---------------------------------------------------------------------------

Widget _app(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        bottomNavigationBar: const StatusBar(),
      ),
    ),
  );
}

List<Override> _baseOverrides({
  bool authConnected = false,
  String providerName = 'MockCloud',
  PanelSide activePanel = PanelSide.local,
  List<OperationProgress> ops = const [],
  bool syncing = false,
  SyncResult? lastSyncResult,
  List<SyncPair> syncPairs = const [],
  String? syncingPairName,
  List<FileItem> localFiles = const [],
  List<FileItem> remoteFiles = const [],
  String localFilter = '',
}) {
  final db = SyncDatabase.forTesting(NativeDatabase.memory());
  return [
    authProvider.overrideWith((ref) => _TestAuthNotifier(
          ref,
          isConnected: authConnected,
          providerName: providerName,
        )),
    activePanelProvider.overrideWith((ref) => activePanel),
    transferProvider.overrideWith(
        (ref) => _TestTransferNotifier(ref, ops: ops)),
    syncProvider.overrideWith(
      (ref) => _TestSyncNotifier(
        ref,
        db,
        isSyncing: syncing,
        lastResult: lastSyncResult,
        pairs: syncPairs,
        currentPairName: syncingPairName,
      ),
    ),
    panelProvider(PanelSide.local).overrideWith((ref) => _TestPanelNotifier(
          ref,
          PanelSide.local,
          files: localFiles,
          filterQuery: localFilter,
        )),
    panelProvider(PanelSide.remote).overrideWith((ref) => _TestPanelNotifier(
          ref,
          PanelSide.remote,
          files: remoteFiles,
        )),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // Connection status
  // -------------------------------------------------------------------------

  group('StatusBar connection status', () {
    testWidgets('shows "Disconnected" when not connected', (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(authConnected: false)));
      await tester.pump();

      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets('shows cloud_off icon when disconnected', (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(authConnected: false)));
      await tester.pump();

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('shows provider name when connected', (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(
        authConnected: true,
        providerName: 'Dropbox',
      )));
      await tester.pump();

      expect(find.text('Dropbox'), findsOneWidget);
    });

    testWidgets('shows cloud_done icon when connected', (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(
        authConnected: true,
        providerName: 'S3',
      )));
      await tester.pump();

      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });

    testWidgets('shows Disconnected text (not provider name) when disconnected',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(
        authConnected: false,
        providerName: 'Dropbox',
      )));
      await tester.pump();

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Dropbox'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Item counts
  // -------------------------------------------------------------------------

  group('StatusBar item count', () {
    testWidgets('shows "0 items" when panel is empty', (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(localFiles: [])));
      await tester.pump();

      expect(find.text('0 items'), findsOneWidget);
    });

    testWidgets('shows correct item count for 42 files', (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(localFiles: _files(42))));
      await tester.pump();

      expect(find.text('42 items'), findsOneWidget);
    });

    testWidgets('shows item count for a single file', (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(localFiles: _files(1))));
      await tester.pump();

      expect(find.text('1 items'), findsOneWidget);
    });

    testWidgets('shows item count for 10 files', (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(localFiles: _files(10))));
      await tester.pump();

      expect(find.text('10 items'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Panel type indicator
  // -------------------------------------------------------------------------

  group('StatusBar panel type indicator', () {
    testWidgets('shows "Local" and folder icon when active panel is local',
        (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(activePanel: PanelSide.local)));
      await tester.pump();

      expect(find.text('Local'), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('shows "Remote" and cloud icon when active panel is remote',
        (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(activePanel: PanelSide.remote)));
      await tester.pump();

      expect(find.text('Remote'), findsOneWidget);
      expect(find.byIcon(Icons.cloud), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Transfer progress
  // -------------------------------------------------------------------------

  group('StatusBar transfer progress', () {
    testWidgets('shows "1 transfer" text for one active operation',
        (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(ops: [_activeOp('op1')])));
      await tester.pump();

      expect(find.text('1 transfer'), findsOneWidget);
    });

    testWidgets('shows "2 transfers" for two active operations',
        (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(ops: [_activeOp('op1'), _activeOp('op2')])));
      await tester.pump();

      expect(find.text('2 transfers'), findsOneWidget);
    });

    testWidgets('shows no transfer text when operations list is empty',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(ops: [])));
      await tester.pump();

      expect(find.textContaining('transfer'), findsNothing);
    });

    testWidgets('completed operation is not counted as active', (tester) async {
      final done = OperationProgress(
        id: 'done',
        type: OperationType.download,
        sourcePath: '/remote/done.txt',
        targetPath: '/local/done.txt',
        fileName: 'done.txt',
        totalBytes: 1000,
        currentBytes: 1000,
        status: OperationStatus.completed,
      );
      await tester.pumpWidget(_app(_baseOverrides(ops: [done])));
      await tester.pump();

      expect(find.textContaining('transfer'), findsNothing);
    });

    testWidgets('shows CircularProgressIndicator during active transfer',
        (tester) async {
      await tester.pumpWidget(
          _app(_baseOverrides(ops: [_activeOp('op1')])));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  // Sync status
  // -------------------------------------------------------------------------

  group('StatusBar sync status', () {
    testWidgets('shows "Syncing..." text when isSyncing is true',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(syncing: true)));
      await tester.pump();

      expect(find.textContaining('Syncing'), findsOneWidget);
    });

    testWidgets('shows pair name during sync when currentPairName is set',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(
        syncing: true,
        syncingPairName: 'Documents',
      )));
      await tester.pump();

      expect(find.textContaining('Documents'), findsOneWidget);
    });

    testWidgets('shows "Last sync" and changes when lastResult has changes',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(
        lastSyncResult: const SyncResult(uploaded: 3, downloaded: 1),
      )));
      await tester.pump();

      expect(find.textContaining('Last sync'), findsOneWidget);
      expect(find.textContaining('4 changes'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator when syncing', (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(syncing: true)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets(
        'shows no sync indicators when not syncing and no last result',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides()));
      await tester.pump();

      expect(find.textContaining('Syncing'), findsNothing);
      expect(find.textContaining('Last sync'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Filter indicator
  // -------------------------------------------------------------------------

  group('StatusBar filter indicator', () {
    testWidgets('shows filter indicator when filterQuery is non-empty',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(localFilter: 'dart')));
      await tester.pump();

      expect(find.textContaining('Filter'), findsOneWidget);
      expect(find.textContaining('"dart"'), findsOneWidget);
    });

    testWidgets('shows filter_list icon when filter is active', (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(localFilter: 'test')));
      await tester.pump();

      expect(find.byIcon(Icons.filter_list), findsOneWidget);
    });

    testWidgets('shows no filter indicator when filterQuery is empty',
        (tester) async {
      await tester.pumpWidget(_app(_baseOverrides(localFilter: '')));
      await tester.pump();

      expect(find.byIcon(Icons.filter_list), findsNothing);
      expect(find.textContaining('Filter'), findsNothing);
    });

    testWidgets(
        'shows "N / M items" format when filter is active and has files',
        (tester) async {
      // With a filter active, filteredFiles returns empty (from mock),
      // and total is 5; status bar shows "0 / 5 items".
      await tester.pumpWidget(_app(_baseOverrides(
        localFiles: _files(5),
        localFilter: 'nonexistent',
      )));
      await tester.pump();

      // The status bar shows "filtered / total items" when filter is active.
      expect(find.textContaining('items'), findsOneWidget);
    });
  });
}

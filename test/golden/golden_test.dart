// test/golden/golden_test.dart
//
// Golden (screenshot) regression tests for key CrispCloud widgets.
//
// Run to generate / update baseline images:
//   flutter test test/golden/golden_test.dart --update-goldens
//
// Run to compare against saved baselines:
//   flutter test test/golden/golden_test.dart
//
// Note: golden tests are platform-sensitive (font rendering differs between
// Linux, macOS, Windows).  Tag them as 'golden' so they can be run
// independently and skipped in cross-platform CI:
//   flutter test --tags golden
//   flutter test --exclude-tags golden
//
// Golden files are stored at:   test/golden/goldens/*.png

@Tags(['golden'])

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
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/fkey_action_service.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/widgets/fkey_bar.dart';
import 'package:crisp_cloud/widgets/panel_source_selector.dart';
import 'package:crisp_cloud/widgets/status_bar.dart';
import 'package:crisp_cloud/widgets/theme_picker.dart';

// =============================================================================
// Mock helpers
// =============================================================================

// ---------------------------------------------------------------------------
// Mock cloud client — no-op
// ---------------------------------------------------------------------------

class _MockCloudClient extends CloudStorageClient {
  final String _name;
  final bool _connected;

  _MockCloudClient({String name = 'MockCloud', bool connected = false})
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
// Test AuthNotifier — bypasses auto-login and configures mock state
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
            configPath: '/tmp/golden_test',
            secureStorage: InMemorySecureStorage(),
          ),
          configPath: '/tmp/golden_test',
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
// Test PanelNotifier — returns fixed file list
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
// Test TransferNotifier — returns fixed operations
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
// Test SyncNotifier — in-memory database, fully controlled state
// ---------------------------------------------------------------------------

class _TestSyncNotifier extends SyncNotifier {
  final bool _mockSyncing;
  final SyncResult? _mockLastResult;
  final List<SyncPair> _mockPairs;
  final String? _mockPairName;

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

// =============================================================================
// wrapForGolden — standard harness for golden tests
// =============================================================================

/// Wraps [child] in a minimal, fully deterministic widget tree suitable for
/// golden comparisons.
///
/// - [size]      : logical pixel dimensions of the rendered surface.
/// - [theme]     : [ThemeData] to apply; defaults to a fixed light theme so
///                 results are platform-independent.
/// - [overrides] : Riverpod provider overrides injected into [ProviderScope].
Widget wrapForGolden(
  Widget child, {
  Size size = const Size(800, 200),
  ThemeData? theme,
  List<Override> overrides = const [],
}) {
  final effectiveTheme = theme ??
      ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: effectiveTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Convenience: build the standard set of StatusBar provider overrides
// ---------------------------------------------------------------------------

List<Override> _statusBarOverrides({
  bool authConnected = false,
  String providerName = 'MockCloud',
  PanelSide activePanel = PanelSide.local,
  List<OperationProgress> ops = const [],
  bool syncing = false,
  List<FileItem> localFiles = const [],
  List<FileItem> remoteFiles = const [],
}) {
  final db = SyncDatabase.forTesting(NativeDatabase.memory());
  return [
    authProvider.overrideWith((ref) => _TestAuthNotifier(
          ref,
          isConnected: authConnected,
          providerName: providerName,
        )),
    activePanelProvider.overrideWith((ref) => activePanel),
    transferProvider
        .overrideWith((ref) => _TestTransferNotifier(ref, ops: ops)),
    syncProvider.overrideWith((ref) => _TestSyncNotifier(ref, db,
        isSyncing: syncing)),
    panelProvider(PanelSide.local).overrideWith((ref) => _TestPanelNotifier(
          ref,
          PanelSide.local,
          files: localFiles,
        )),
    panelProvider(PanelSide.remote).overrideWith((ref) => _TestPanelNotifier(
          ref,
          PanelSide.remote,
          files: remoteFiles,
        )),
  ];
}

// ---------------------------------------------------------------------------
// Convenience: FKeyContext factories
// ---------------------------------------------------------------------------

FKeyContext _emptyFKeyContext() => FKeyContext(
      activePanel: const LocalPanelSource('/'),
      oppositePanel: const LocalPanelSource('/tmp'),
      selectedFiles: [],
    );

FKeyContext _selectionFKeyContext() => FKeyContext(
      activePanel: const LocalPanelSource('/'),
      oppositePanel: const LocalPanelSource('/tmp'),
      selectedFiles: [
        FileItem(name: 'report.pdf', path: '/report.pdf', isFolder: false, size: 204800),
        FileItem(name: 'notes.txt', path: '/notes.txt', isFolder: false, size: 1024),
      ],
    );

// =============================================================================
// Tests
// =============================================================================

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // FKeyBar — default state (no selection)
  // fkeyBarVisibleProvider reads SharedPreferences; setUp sets mock values
  // to ensure the bar is visible (default key absent → defaults to true).
  // ---------------------------------------------------------------------------

  group('FKeyBar golden', () {
    testWidgets('FKeyBar default state', (tester) async {
      // Empty SharedPreferences → fkeyBarVisibleProvider defaults to true.
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        wrapForGolden(
          FKeyBar(overrideContext: _emptyFKeyContext()),
          size: const Size(800, 60),
        ),
      );
      // Allow the async SharedPreferences load inside the notifier to complete.
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(FKeyBar),
        matchesGoldenFile('goldens/fkey_bar_default.png'),
      );
    });

    // -------------------------------------------------------------------------
    // FKeyBar — with selection (Copy / Move / Delete / View / Edit enabled)
    // -------------------------------------------------------------------------

    testWidgets('FKeyBar with selection', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        wrapForGolden(
          FKeyBar(overrideContext: _selectionFKeyContext()),
          size: const Size(800, 60),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(FKeyBar),
        matchesGoldenFile('goldens/fkey_bar_with_selection.png'),
      );
    });

    // -------------------------------------------------------------------------
    // FKeyBar — narrow screen (icon-only mode, width < 480)
    // -------------------------------------------------------------------------

    testWidgets('FKeyBar narrow screen icon mode', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        wrapForGolden(
          FKeyBar(overrideContext: _emptyFKeyContext()),
          size: const Size(400, 60),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(FKeyBar),
        matchesGoldenFile('goldens/fkey_bar_narrow.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // StatusBar golden tests
  // ---------------------------------------------------------------------------

  group('StatusBar golden', () {
    testWidgets('StatusBar disconnected state', (tester) async {
      await tester.pumpWidget(
        wrapForGolden(
          const StatusBar(),
          size: const Size(1024, 40),
          overrides: _statusBarOverrides(
            authConnected: false,
            localFiles: _demoFiles(5),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byType(StatusBar),
        matchesGoldenFile('goldens/status_bar_disconnected.png'),
      );
    });

    testWidgets('StatusBar connected state', (tester) async {
      await tester.pumpWidget(
        wrapForGolden(
          const StatusBar(),
          size: const Size(1024, 40),
          overrides: _statusBarOverrides(
            authConnected: true,
            providerName: 'Dropbox',
            localFiles: _demoFiles(12),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byType(StatusBar),
        matchesGoldenFile('goldens/status_bar_connected.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // PanelSourceSelector golden tests
  // ---------------------------------------------------------------------------

  group('PanelSourceSelector golden', () {
    testWidgets('PanelSourceSelector with Local selected', (tester) async {
      final sources = [
        const AvailableSource(
          key: 'local',
          label: 'Local',
          source: LocalPanelSource('/'),
        ),
        AvailableSource(
          key: 'remote:Dropbox',
          label: 'Dropbox',
          source: RemotePanelSource(
            providerName: 'Dropbox',
            client: _MockCloudClient(name: 'Dropbox', connected: false),
            path: '/',
          ),
        ),
      ];

      await tester.pumpWidget(
        wrapForGolden(
          const PanelSourceSelector(side: PanelSide.local),
          size: const Size(400, 60),
          overrides: [
            availableSourcesProvider.overrideWithValue(sources),
            panelSourceProvider(PanelSide.local).overrideWith(
              (ref) => PanelSourceNotifier(PanelSide.local),
            ),
          ],
        ),
      );
      await tester.pump();

      await expectLater(
        find.byType(PanelSourceSelector),
        matchesGoldenFile('goldens/panel_source_selector_local.png'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ThemePickerDialog golden tests
  // ---------------------------------------------------------------------------

  group('ThemePickerDialog golden', () {
    testWidgets('ThemePickerDialog light theme selected', (tester) async {
      final themeService = ThemeService();
      await themeService.setTheme(AppThemeMode.light);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600, 700)),
            child: Scaffold(
              body: Center(
                child: ThemePickerDialog(themeService: themeService),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byType(ThemePickerDialog),
        matchesGoldenFile('goldens/theme_picker_light.png'),
      );
    });

    testWidgets('ThemePickerDialog dark theme selected', (tester) async {
      final themeService = ThemeService();
      await themeService.setTheme(AppThemeMode.dark);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600, 700)),
            child: Scaffold(
              body: Center(
                child: ThemePickerDialog(themeService: themeService),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byType(ThemePickerDialog),
        matchesGoldenFile('goldens/theme_picker_dark.png'),
      );
    });
  });
}

// =============================================================================
// Helpers
// =============================================================================

/// Generate [n] demo FileItems for testing.
List<FileItem> _demoFiles(int n) => List.generate(
      n,
      (i) => FileItem(
        name: 'file_${i + 1}.txt',
        path: '/file_${i + 1}.txt',
        isFolder: false,
        size: (i + 1) * 1024,
      ),
    );

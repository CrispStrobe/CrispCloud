// test/widget/responsive_toolbar_widget_test.dart
//
// Widget tests for responsive toolbar behaviour.
// Verifies that the AppBar actions adapt to screen width, that
// platform-inappropriate buttons are hidden, and that the file
// toolbar scrolls horizontally instead of overflowing.

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
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
import 'package:crisp_cloud/services/theme_service.dart';
import 'package:crisp_cloud/screens/file_browser_screen.dart';
import 'package:crisp_cloud/widgets/file_toolbar.dart';

// ---------------------------------------------------------------------------
// Mock cloud client
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
// Test notifiers
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
            configPath: '/tmp/rt_widget_test',
            secureStorage: InMemorySecureStorage(),
          ),
          configPath: '/tmp/rt_widget_test',
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

class _TestPanelNotifier extends PanelNotifier {
  final List<FileItem> _mockFiles;

  _TestPanelNotifier(Ref ref, PanelSide side,
      {List<FileItem> files = const []})
      : _mockFiles = files,
        super(ref, side);

  @override
  List<FileItem>? get files => _mockFiles;
  @override
  List<FileItem>? get filteredFiles => _mockFiles;
  @override
  Set<FileItem> get selection => const {};
  @override
  String get filterQuery => '';
}

class _TestTransferNotifier extends TransferNotifier {
  _TestTransferNotifier(Ref ref) : super(ref);

  @override
  List<OperationProgress> get operations => const [];
}

class _TestSyncNotifier extends SyncNotifier {
  _TestSyncNotifier(Ref ref, SyncDatabase db) : super.forTesting(ref, db);

  @override
  bool get isSyncing => false;
  @override
  SyncResult? get lastResult => null;
  @override
  List<SyncPair> get pairs => const [];
  @override
  String? get currentPairName => null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<Override> _baseOverrides({
  bool authConnected = false,
  String providerName = 'MockCloud',
}) {
  final db = SyncDatabase.forTesting(NativeDatabase.memory());
  return [
    secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
    authProvider.overrideWith((ref) => _TestAuthNotifier(ref,
        isConnected: authConnected, providerName: providerName)),
    activePanelProvider.overrideWith((ref) => PanelSide.local),
    transferProvider.overrideWith((ref) => _TestTransferNotifier(ref)),
    panelProvider(PanelSide.local)
        .overrideWith((ref) => _TestPanelNotifier(ref, PanelSide.local)),
    panelProvider(PanelSide.remote)
        .overrideWith((ref) => _TestPanelNotifier(ref, PanelSide.remote)),
    syncProvider.overrideWith((ref) => _TestSyncNotifier(ref, db)),
  ];
}

/// Wraps FileBrowserScreen at a given width/height.
/// Must call debugDefaultTargetPlatformOverride before using this
/// if you need a non-default platform (default in tests is android).
Widget _wrapScreen({
  double width = 1200,
  double height = 800,
  List<Override> overrides = const [],
}) {
  final themeService = ThemeService();
  return ProviderScope(
    overrides: overrides,
    child: legacy.ChangeNotifierProvider<ThemeService>.value(
      value: themeService,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: const FileBrowserScreen(),
        ),
      ),
    ),
  );
}

/// Wraps FileToolbar at a given width.
Widget _wrapToolbar({
  double width = 600,
  PanelSide side = PanelSide.local,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: FileToolbar(side: side, currentPath: '/home/test'),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // AppBar responsive behaviour
  // =========================================================================

  group('AppBar on wide screen (>800px)', () {
    testWidgets('shows scrollable toolbar with action buttons',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 1200,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // The wide layout wraps toolbar buttons in a horizontal SingleChildScrollView.
      final scrollViews = tester.widgetList<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final hasHorizontal = scrollViews.any(
        (sv) => sv.scrollDirection == Axis.horizontal,
      );
      expect(hasHorizontal, isTrue,
          reason: 'Wide AppBar should have a horizontal SingleChildScrollView');

      // Core buttons always visible in the scrollable row.
      expect(find.byTooltip('Swap Panels (Ctrl+U)'), findsOneWidget);

      // Overflow menu is present on both wide and narrow screens.
      expect(find.byTooltip('More actions'), findsOneWidget);
    });

    testWidgets('shows "CrispCloud" title text in scrollable row',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 1200,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // The wide layout embeds the app title as a Text widget inside the
      // scrollable toolbar row (AppBar.title is null on wide screens).
      expect(find.text('CrispCloud'), findsOneWidget);
    });

    testWidgets('shows Connect button when not authenticated',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 1200,
        overrides: _baseOverrides(authConnected: false),
      ));
      await tester.pump();

      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('overflow menu contains secondary actions on wide screen',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 1200,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // Tap the overflow (more) menu.
      await tester.tap(find.byTooltip('More actions'));
      // Use pump with a finite duration to avoid pumpAndSettle timeout caused
      // by background async operations (SharedPreferences, providers).
      await tester.pump(const Duration(milliseconds: 300));

      // Secondary actions appear in the popup on both wide and narrow screens.
      expect(find.text('Multi-Cloud Manager'), findsOneWidget);
      expect(find.text('Sync Manager'), findsOneWidget);
      expect(find.text('Find Duplicates'), findsOneWidget);
      expect(find.text('Audit Log'), findsOneWidget);
      expect(find.text('Cache Settings'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });
  });

  group('AppBar on narrow screen (<=800px)', () {
    testWidgets('shows overflow menu instead of all buttons',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 600,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // Overflow popup menu is present.
      expect(find.byTooltip('More actions'), findsOneWidget);
    });

    testWidgets('overflow menu opens and shows all secondary actions',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 600,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // Tap the overflow menu.
      await tester.tap(find.byTooltip('More actions'));
      // Use pump with a finite duration to avoid pumpAndSettle timeout caused
      // by background async operations.
      await tester.pump(const Duration(milliseconds: 300));

      // Should show secondary actions in the popup.
      expect(find.text('Multi-Cloud Manager'), findsOneWidget);
      expect(find.text('Sync Manager'), findsOneWidget);
      expect(find.text('Find Duplicates'), findsOneWidget);
      expect(find.text('Audit Log'), findsOneWidget);
      expect(find.text('Cache Settings'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('keeps swap panels button visible on narrow screen',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 600,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // Swap panels is an essential button that stays directly in the AppBar.
      expect(find.byTooltip('Swap Panels (Ctrl+U)'), findsOneWidget);
    });

    testWidgets('shows title text in AppBar on narrow screen',
        (tester) async {
      await tester.pumpWidget(_wrapScreen(
        width: 600,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // On narrow screens the AppBar.title shows the app name.
      expect(find.text('CrispCloud'), findsOneWidget);
    });
  });

  // =========================================================================
  // Platform-specific button visibility
  // =========================================================================

  group('Platform-specific actions', () {
    // In flutter_test, defaultTargetPlatform defaults to android.
    // We use debugDefaultTargetPlatformOverride to simulate platforms.
    // IMPORTANT: Must reset debugDefaultTargetPlatformOverride inside the test
    // body using try/finally, because _verifyInvariants() runs INSIDE
    // binding.runTest() — before any tearDown callbacks.

    testWidgets('shows terminal toggle on desktop platform', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.pumpWidget(_wrapScreen(
          width: 1200,
          overrides: _baseOverrides(),
        ));
        await tester.pump();

        // On desktop, a terminal toggle button is shown directly in the wide toolbar.
        expect(find.byTooltip('Show Terminal'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('shows mount button in overflow menu on desktop platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.pumpWidget(_wrapScreen(
          width: 1200,
          overrides: _baseOverrides(),
        ));
        await tester.pump();

        // Open the overflow menu to see desktop-only items.
        await tester.tap(find.byTooltip('More actions'));
        // Use pump with a finite duration to avoid pumpAndSettle timeout caused
        // by background async operations (SharedPreferences, providers).
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Mount as Drive'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('hides terminal button on mobile platform',
        (tester) async {
      // android is the default in flutter_test, but be explicit.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(_wrapScreen(
          width: 1200,
          overrides: _baseOverrides(),
        ));
        await tester.pump();

        // No terminal toggle icon button in the wide toolbar on mobile.
        expect(find.byTooltip('Show Terminal'), findsNothing);
        expect(find.byTooltip('Hide Terminal'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('hides terminal and mount in overflow menu on mobile',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(_wrapScreen(
          width: 600,
          overrides: _baseOverrides(),
        ));
        await tester.pump();

        await tester.tap(find.byTooltip('More actions'));
        await tester.pump(const Duration(milliseconds: 300));

        // Desktop-only entries must not appear in the overflow menu on mobile.
        expect(find.text('Show Terminal'), findsNothing);
        expect(find.text('Hide Terminal'), findsNothing);
        expect(find.text('Mount as Drive'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // =========================================================================
  // FileToolbar scrollability
  // =========================================================================

  group('FileToolbar responsive', () {
    testWidgets('wraps action buttons in a horizontal ScrollView',
        (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        width: 300,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      // The FileToolbar should contain a SingleChildScrollView for
      // horizontally scrolling the action buttons.
      final scrollViews = tester.widgetList<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final hasHorizontal = scrollViews.any(
        (sv) => sv.scrollDirection == Axis.horizontal,
      );
      expect(hasHorizontal, isTrue,
          reason: 'FileToolbar should have a horizontal SingleChildScrollView');
    });

    testWidgets('shows core navigation buttons', (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        width: 800,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      expect(find.byTooltip('Up (Backspace)'), findsOneWidget);
      expect(find.byTooltip('Refresh (F5)'), findsOneWidget);
      expect(find.byTooltip('New Folder (Ctrl+N)'), findsOneWidget);
      expect(find.byTooltip('Sort'), findsOneWidget);
    });

    testWidgets('shows path text', (tester) async {
      await tester.pumpWidget(_wrapToolbar(
        width: 800,
        overrides: _baseOverrides(),
      ));
      await tester.pump();

      expect(find.text('/home/test'), findsOneWidget);
    });
  });

  // =========================================================================
  // Layout preset selector
  // =========================================================================

  group('Layout preset selector', () {
    testWidgets('layout presets enum contains Commander, Explorer, Gallery',
        (tester) async {
      // The LayoutPreset enum drives the layout but the selector UI is
      // accessed via the overflow menu rather than a dedicated toolbar button.
      // Verify the enum values exist so the persistence layer is intact.
      expect(LayoutPreset.values, containsAll([
        LayoutPreset.commander,
        LayoutPreset.explorer,
        LayoutPreset.gallery,
      ]));
    });

    testWidgets('dual panel toggle is accessible on wide screen',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.pumpWidget(_wrapScreen(
          width: 1200,
          overrides: _baseOverrides(),
        ));
        await tester.pump();

        // The dual-panel toggle is always visible in the wide toolbar row.
        // Its tooltip is either 'Single Panel' or 'Dual Panel' depending on state.
        // Default state is dual panel enabled (showDualPanelProvider defaults true).
        expect(find.byTooltip('Single Panel'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('tree sidebar toggle is accessible on wide screen',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.pumpWidget(_wrapScreen(
          width: 1200,
          overrides: _baseOverrides(),
        ));
        await tester.pump();

        // Tree sidebar toggle is always in the wide toolbar.
        // Default state is hidden, so tooltip is 'Show Tree Sidebar'.
        expect(find.byTooltip('Show Tree Sidebar'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

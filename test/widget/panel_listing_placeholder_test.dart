import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:crisp_cloud/widgets/file_column_view.dart';
import 'package:crisp_cloud/widgets/file_grid_view.dart';
import 'package:crisp_cloud/widgets/file_panel.dart';
import 'package:crisp_cloud/widgets/panel_listing_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends CloudStorageClient {
  bool authenticated = true;
  bool fail = false;
  String configuredRoot = '/';
  final reads = <String>[];
  @override
  String get providerName => 'Listing cloud';
  @override
  String get rootPath => configuredRoot;
  @override
  String get userId => 'listing-account';
  @override
  String? get bucketId => null;
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    reads.add(path);
    if (fail) throw StateError('This folder could not be read');
    return {
      'folders': [
        if (path == '/') {'name': 'docs', 'uuid': 'docs'},
      ],
      'files': [
        if (path == '/docs')
          {'name': 'report.txt', 'uuid': 'report', 'size': 12},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => client.authenticated;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => 'listing@example.test';
  void disconnect() {
    client.authenticated = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService {
  bool denied = false;
  final grants = <String?>[];
  @override
  String currentPath = '/opened';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => '/opened';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<bool> ensureAccess(String path) async => false;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    if (denied)
      throw PathAccessException(path, const OSError('Access denied', 13));
    return [];
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    grants.add(initialDirectory);
    denied = false;
    return initialDirectory;
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Cloud cloud;
  late _Auth auth;
  late _Local local;
  late PanelNotifier panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('desktop_drop'),
          (_) async => null,
        );
    cloud = _Cloud();
    auth = _Auth(cloud);
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
        drivesProvider.overrideWith((_) async => const <DriveEntry>[]),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final origin = panel.resolveStorageReference(
      storageReferenceForClient(cloud),
      '/',
    );
    expect(origin, isNotNull);
    await panel.navigateToPath('/', origin: origin!);
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), null);
  });

  Future<void> mount(
    WidgetTester tester, {
    ViewMode mode = ViewMode.list,
  }) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(remoteViewModeProvider.notifier).state = mode;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FilePanel(
              side: PanelSide.remote,
              isActive: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder state(PanelListingState value) =>
      find.byKey(ValueKey('panel-listing-${value.name}'));

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  for (final mode in [ViewMode.list, ViewMode.column]) {
    testWidgets(
      '${mode.name} explains a parent-only filtered listing and clears the filter',
      (tester) async {
        await mount(tester, mode: mode);
        await panel.navigateToPath(
          '/docs',
          origin: panel.captureCurrentOrigin(),
        );
        await tester.pumpAndSettle();
        panel.setFilter('absent');
        await tester.pumpAndSettle();
        expect(panel.filteredFiles!.map((file) => file.name), ['..']);
        expect(state(PanelListingState.filtered), findsOneWidget);
        expect(find.text('No results found'), findsOneWidget);
        if (mode == ViewMode.column) {
          expect(find.byKey(const ValueKey('file-column:/')), findsOneWidget);
          expect(find.byType(FileColumnView), findsOneWidget);
        }
        await tester.tap(find.widgetWithText(TextButton, 'Clear filter'));
        await tester.pumpAndSettle();
        expect(panel.filterQuery, isEmpty);
        expect(find.text('report.txt'), findsOneWidget);
        expect(state(PanelListingState.filtered), findsNothing);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }

  for (final mode in [ViewMode.grid, ViewMode.column]) {
    testWidgets(
      '${mode.name} keeps a failed listing visible until its own retry succeeds',
      (tester) async {
        await mount(tester, mode: mode);
        cloud.fail = true;
        await panel.refresh();
        await tester.pumpAndSettle();
        container.read(errorProvider).clearErrors();
        await tester.pumpAndSettle();
        expect(state(PanelListingState.failed), findsOneWidget);
        expect(
          find.descendant(
            of: state(PanelListingState.failed),
            matching: find.textContaining('This folder could not be read'),
          ),
          findsOneWidget,
        );
        expect(find.text('Empty folder'), findsNothing);
        cloud.fail = false;
        await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
        await tester.pumpAndSettle();
        expect(state(PanelListingState.failed), findsNothing);
        expect(panel.hasVerifiedDirectoryListing, isTrue);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'a disconnected selected source shows recovery even in a visual layout',
    (tester) async {
      await mount(tester, mode: ViewMode.grid);
      expect(find.byType(FileGridView), findsOneWidget);
      auth.disconnect();
      await tester.pumpAndSettle();
      expect(state(PanelListingState.disconnected), findsOneWidget);
      expect(find.byType(FileGridView), findsNothing);
      expect(
        find.text('Reconnect the original storage for this location.'),
        findsOneWidget,
      );
      expect(local.grants, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('right-pane local permission recovery grants its own folder', (
    tester,
  ) async {
    final origin = panel.resolveStorageReference(
      storageReferenceForSource(const LocalPanelSource('/locked')),
      '/locked',
    );
    expect(origin, isNotNull);
    local.denied = true;
    await panel.navigateToPath('/locked', origin: origin!);
    await mount(tester, mode: ViewMode.column);
    expect(state(PanelListingState.failed), findsOneWidget);
    expect(find.text('Grant Access'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Grant Access'));
    await tester.pumpAndSettle();
    expect(local.grants, ['/locked']);
    expect(panel.currentPath, '/locked');
    expect(panel.directoryListingError, isNull);
    expect(state(PanelListingState.failed), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  test('browser synthetic root differs from a selected empty folder and cloud root', () async {
    final storage = storageReferenceForSource(const LocalPanelSource('/'));
    await panel.navigateToPath(
      '/',
      origin: panel.resolveStorageReference(storage, '/')!,
    );
    expect(
      panelListingState(panel, isWeb: true),
      PanelListingState.chooseFolder,
    );
    await panel.navigateToPath(
      '/opened',
      origin: panel.resolveStorageReference(storage, '/opened')!,
    );
    expect(panelListingState(panel, isWeb: true), PanelListingState.empty);
    await panel.navigateToPath(
      '/empty',
      origin: panel.resolveStorageReference(
        storageReferenceForClient(cloud),
        '/empty',
      )!,
    );
    expect(panelListingState(panel, isWeb: true), PanelListingState.empty);
  });

  testWidgets('browser welcome action opens the captured provider root', (
    tester,
  ) async {
    final storage = storageReferenceForSource(const LocalPanelSource('/'));
    await panel.navigateToPath(
      '/',
      origin: panel.resolveStorageReference(storage, '/')!,
    );
    cloud.configuredRoot = '/tenant';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: PanelListingPlaceholder(
              side: PanelSide.remote,
              state: PanelListingState.chooseFolder,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/tenant');
    expect(cloud.reads.last, '/tenant');
    expect(panel.directoryStorage!.root, '/tenant');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}

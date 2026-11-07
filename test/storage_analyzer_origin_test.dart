import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/models/storage_analysis.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/widgets/storage_analysis_view.dart';
import 'package:crisp_cloud/widgets/storage_analyzer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';
import 'support/workspace_fixture.dart';

class _Local extends Fake implements LocalFileService {
  final listed = <String>[];

  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    listed.add(path);
    return [];
  }

  @override
  Future<void> refresh() async {}
}

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account);

  final String account;
  final listed = <String>[];
  final deniedDirectories = <String>{};
  final downloaded = <String>[];

  @override
  String get userId => account;

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    listed.add(path);
    if (deniedDirectories.contains(path)) {
      throw StateError('Directory permission denied: $path');
    }
    return super.listPath(path);
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    downloaded.add(path);
    throw StateError('The analyzer must not download file contents.');
  }
}

void main() {
  late _Cloud primary;
  late _Local local;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    primary = _Cloud('primary-account')
      ..put('/primary.bin', [1, 2, 3])
      ..put('/nested/large.bin', List.filled(32, 7));
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => WorkspaceTestAuth(primary)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    // Initialize both real panel notifiers before opening the modal. The
    // right pane deliberately retains its legacy Local dropdown label.
    final left = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await left.refresh();
    await container.read(panelProvider(PanelSide.remote)).refresh();
  });

  tearDown(() => container.dispose());

  Future<void> open(WidgetTester tester, PanelSide side) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(activePanelProvider.notifier).state = side;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showStorageAnalyzerDialog(context, ref),
                child: const Text('Analyze current folder'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze current folder'));
    await tester.pumpAndSettle();
    expect(find.byType(StorageAnalyzerDialog), findsOneWidget);
    expect(find.byType(StorageAnalysisView), findsOneWidget);
  }

  StorageScanResult report(WidgetTester tester) => tester
      .widget<StorageAnalysisView>(find.byType(StorageAnalysisView))
      .analysis;

  Future<void> reveal(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(ListTile, name));
    await tester.pump();
    await tester.tap(find.text('Show in file panel'));
    await tester.pumpAndSettle();
  }

  Future<void> closeFixture(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'analyzer uses the verified remote endpoint despite its Local dropdown label',
    (tester) async {
      expect(
        container.read(panelSourceProvider(PanelSide.remote)),
        isA<LocalPanelSource>(),
      );
      final localReadCount = local.listed.length;
      primary.listed.clear();

      await open(tester, PanelSide.remote);

      final dialog = tester.widget<StorageAnalyzerDialog>(
        find.byType(StorageAnalyzerDialog),
      );
      expect((dialog.source as CloudStorageScanBackend).client, same(primary));
      expect(dialog.rootPath, '/');
      expect(report(tester).isComplete, isTrue);
      expect(report(tester).root.bytes, 35);
      expect(report(tester).root.fileCount, 2);
      expect(primary.listed, containsAll(['/', '/nested']));
      expect(local.listed, hasLength(localReadCount));
      expect(primary.downloaded, isEmpty);
      expect(primary.writes, isEmpty);
      await closeFixture(tester);
    },
  );

  testWidgets(
    'scan and reveal keep the left secondary account after focus and source change',
    (tester) async {
      final secondary = _Cloud('secondary-account')
        ..put('/photos/image.jpg', List.filled(11, 1))
        ..put('/photos/nested/movie.mp4', List.filled(30, 2));
      container
          .read(multiCloudProvider)
          .addConnection(
            id: 'secondary',
            label: 'Second account',
            provider: CloudProvider.s3,
            client: secondary,
          );
      final left = container.read(panelProvider(PanelSide.local));
      final right = container.read(panelProvider(PanelSide.remote));
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(
            RemotePanelSource(
              providerName: secondary.providerName,
              client: secondary,
              path: '/photos',
            ),
          );
      await left.refresh();
      primary.listed.clear();

      await open(tester, PanelSide.local);

      final dialog = tester.widget<StorageAnalyzerDialog>(
        find.byType(StorageAnalyzerDialog),
      );
      expect(
        (dialog.source as CloudStorageScanBackend).client,
        same(secondary),
      );
      expect(dialog.rootPath, '/photos');
      expect(report(tester).isComplete, isTrue);
      expect(report(tester).root.bytes, 41);
      expect(primary.listed, isEmpty);

      // While the report is open, neither another active pane nor a new
      // dropdown source may redirect Show in file panel to that account.
      container.read(activePanelProvider.notifier).state = PanelSide.remote;
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(
            RemotePanelSource(
              providerName: primary.providerName,
              client: primary,
              path: '/',
            ),
          );
      await left.refresh();
      primary.listed.clear();
      secondary.listed.clear();

      await reveal(tester, 'image.jpg');

      expect(find.byType(StorageAnalyzerDialog), findsNothing);
      expect(left.currentPath, '/photos');
      expect(left.selection.single.path, '/photos/image.jpg');
      expect(
        (left.captureCurrentOrigin().source as RemotePanelSource).client,
        same(secondary),
      );
      expect(right.currentPath, '/');
      expect(primary.listed, isEmpty);
      expect(secondary.listed, contains('/photos'));
      expect(primary.downloaded, isEmpty);
      expect(secondary.downloaded, isEmpty);
      await closeFixture(tester);
    },
  );

  testWidgets('locked tab keeps the report open when reveal is declined', (
    tester,
  ) async {
    final panel = container.read(panelProvider(PanelSide.remote));
    panel.setTabLock(panel.activeTab!.id, TabLockMode.locked);
    await open(tester, PanelSide.remote);
    primary.listed.clear();

    await reveal(tester, 'nested');

    expect(find.byType(StorageAnalyzerDialog), findsOneWidget);
    expect(panel.currentPath, '/');
    expect(panel.captureCurrentOrigin().source.currentPath, '/');
    expect(container.read(errorProvider).lastError, contains('locked'));
    expect(
      find.textContaining('Could not open the original item.'),
      findsOneWidget,
    );
    expect(primary.listed, isEmpty);
    await closeFixture(tester);
  });

  testWidgets('permission-denied reveal keeps the analyzed snapshot open', (
    tester,
  ) async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await open(tester, PanelSide.remote);
    final originalReport = report(tester);
    primary.deniedDirectories.add('/nested');

    await reveal(tester, 'nested');

    expect(find.byType(StorageAnalyzerDialog), findsOneWidget);
    expect(report(tester), same(originalReport));
    expect(() => panel.captureCurrentOrigin(), throwsStateError);
    expect(
      container.read(errorProvider).lastError,
      contains('permission denied'),
    );
    expect(
      find.textContaining('Could not open the original item.'),
      findsOneWidget,
    );
    await closeFixture(tester);
  });

  testWidgets(
    'a file removed after scanning does not count as a successful reveal',
    (tester) async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await open(tester, PanelSide.remote);
      primary.files.remove('/primary.bin');

      await reveal(tester, 'primary.bin');

      expect(find.byType(StorageAnalyzerDialog), findsOneWidget);
      expect(panel.captureCurrentOrigin().source.currentPath, '/');
      expect(panel.selection, isEmpty);
      expect(
        find.textContaining('Could not open the original item.'),
        findsOneWidget,
      );
      await closeFixture(tester);
    },
  );
}

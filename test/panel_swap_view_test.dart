import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';

import 'support/workflow_fake_client.dart';

import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

class _Local extends Fake implements LocalFileService {
  final blocked = <String, Completer<List<FileSystemEntity>>>{};
  final requests = <String>[];
  @override
  String currentPath = '/';
  @override
  String? get grantedBasePath => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<bool> ensureAccess(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    requests.add(path);
    return await blocked[path]?.future ?? [];
  }

  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async =>
      initialDirectory;
  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async =>
      Uint8List(0);
  @override
  Future<void> saveFile(String path, Uint8List data) async {}
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<void> deleteEntry(String path, bool isFolder) async {}
  @override
  Future<void> refresh() async {}
  @override
  Map<String, dynamic> getWebMetadata(String path) => {};
  @override
  Object? getWebFileRef(String path) => null;
  @override
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) async => const <FileItem>[];
}

class _Cloud extends Fake implements CloudStorageClient {
  @override
  bool get isAuthenticated => false;
  @override
  String get providerName => 'Test';
  @override
  String? get userId => null;
  @override
  String? get bucketId => null;
}

class _PendingCloud extends WorkflowFakeClient {
  Completer<void>? pending;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await pending?.future;
    return super.listPath(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth([CloudStorageClient? client]) : client = client ?? _Cloud();
  @override
  final CloudStorageClient client;
  @override
  bool get isConnected => client.isAuthenticated;
  @override
  String? get userEmail => null;
  @override
  String get providerName => 'Test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('swapping pane views exchanges both directions', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        localFileServiceProvider.overrideWithValue(_Local()),
        authProvider.overrideWith((_) => _Auth()),
      ],
    );
    addTearDown(container.dispose);
    final left = container.read(panelProvider(PanelSide.local));
    final right = container.read(panelProvider(PanelSide.remote));

    await left.navigateToPath('/alpha');
    await right.navigateToPath('/beta');
    expect(left.currentPath, '/alpha');
    expect(right.currentPath, '/beta');

    await left.swapViewWith(right);

    expect(left.currentPath, '/beta');
    expect(right.currentPath, '/alpha');
  });
  testWidgets('public source swap uses visible paths and bypasses locks once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFileServiceProvider.overrideWithValue(_Local()),
          authProvider.overrideWith((_) => _Auth()),
        ],
        child: Consumer(
          builder: (context, value, child) {
            ref = value;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final left = ref.read(panelProvider(PanelSide.local));
    final right = ref.read(panelProvider(PanelSide.remote));
    await left.navigateToPath('/alpha');
    await right.navigateToPath('/beta');
    left.setTabLock(left.activeTab!.id, TabLockMode.locked);
    right.setTabLock(right.activeTab!.id, TabLockMode.newTab);
    final leftTabs = left.tabs.length;
    final rightTabs = right.tabs.length;
    await swapPanelSources(ref);
    expect(left.currentPath, '/beta');
    expect(right.currentPath, '/alpha');
    expect(ref.read(panelSourceProvider(PanelSide.local)).currentPath, '/beta');
    expect(
      ref.read(panelSourceProvider(PanelSide.remote)).currentPath,
      '/alpha',
    );
    expect(left.captureCurrentOrigin().source.currentPath, '/beta');
    expect(right.captureCurrentOrigin().source.currentPath, '/alpha');
    expect(left.tabs, hasLength(leftTabs));
    expect(right.tabs, hasLength(rightTabs));
    expect(ref.read(activePanelProvider), PanelSide.remote);
    await swapPanelSources(ref);
    expect(left.currentPath, '/alpha');
    expect(right.currentPath, '/beta');
    expect(ref.read(activePanelProvider), PanelSide.local);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'swap invalidates an earlier listing while the new listing is pending',
    () async {
      SharedPreferences.setMockInitialValues({});
      final local = _Local();
      final container = ProviderContainer(
        overrides: [
          localFileServiceProvider.overrideWithValue(local),
          authProvider.overrideWith((_) => _Auth()),
        ],
      );
      addTearDown(container.dispose);
      final left = container.read(panelProvider(PanelSide.local));
      final right = container.read(panelProvider(PanelSide.remote));
      await left.navigateToPath('/alpha');
      await right.navigateToPath('/beta');
      final old = local.blocked['/alpha'] = Completer<List<FileSystemEntity>>();
      final oldRefresh = left.refresh();
      await Future<void>.delayed(Duration.zero);
      final newListing = local.blocked['/alpha'] =
          Completer<List<FileSystemEntity>>();
      final swapping = left.swapViewWith(right);
      await Future<void>.delayed(Duration.zero);
      expect(right.isLoading, isTrue);
      expect(() => right.captureCurrentOrigin(), throwsStateError);
      old.complete([]);
      await oldRefresh;
      expect(left.currentPath, '/beta');
      newListing.complete([]);
      expect(await swapping, isTrue);
      expect(right.currentPath, '/alpha');
      expect(right.captureCurrentOrigin().source.currentPath, '/alpha');
    },
  );

  test('mixed file lists preserve each row source after swapping', () async {
    SharedPreferences.setMockInitialValues({});
    final cloud = WorkflowFakeClient()..put('/cloud/remote.txt', [1, 2]);
    final container = ProviderContainer(
      overrides: [
        localFileServiceProvider.overrideWithValue(_Local()),
        authProvider.overrideWith((_) => _Auth(cloud)),
      ],
    );
    addTearDown(container.dispose);
    final left = container.read(panelProvider(PanelSide.local));
    final right = container.read(panelProvider(PanelSide.remote));
    await left.navigateToPath('/alpha');
    final localOrigin = left.captureCurrentOrigin();
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(
          RemotePanelSource(
            providerName: cloud.providerName,
            client: cloud,
            path: '/cloud',
          ),
        );
    await right.refresh();
    final remoteOrigin = right.captureCurrentOrigin();
    final localRow = FileItem(
      name: 'local.txt',
      path: '/alpha/local.txt',
      isFolder: false,
    );
    final remoteRow = right.files!.singleWhere(
      (file) => file.name == 'remote.txt',
    );
    left.showSearchResults(
      [localRow, remoteRow],
      originForFile: (row) =>
          identical(row, localRow) ? localOrigin : remoteOrigin,
      title: 'Both sources',
    );
    expect(await left.swapViewWith(right), isTrue);
    expect(right.showingSearchResults, isTrue);
    final localResult = right.files!.singleWhere(
      (row) => row.name == 'local.txt',
    );
    final remoteResult = right.files!.singleWhere(
      (row) => row.name == 'remote.txt',
    );
    expect(
      right.originForOperation(localResult)!.source,
      isA<LocalPanelSource>(),
    );
    expect(
      (right.originForOperation(remoteResult)!.source as RemotePanelSource)
          .client,
      same(cloud),
    );
    expect(right.originForOperation(remoteResult.copyWith()), isNull);
    cloud.current = false;
    expect(right.originForOperation(remoteResult), isNull);
    expect(right.originForOperation(localResult), isNotNull);
  });
  test(
    'leaving a branch view before swapping restores a verified folder',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = WorkflowFakeClient()
        ..put('/cloud/remote.txt', [1])
        ..put('/other/next.txt', [2]);
      final container = ProviderContainer(
        overrides: [
          localFileServiceProvider.overrideWithValue(_Local()),
          authProvider.overrideWith((_) => _Auth(cloud)),
        ],
      );
      addTearDown(container.dispose);
      final left = container.read(panelProvider(PanelSide.local));
      final right = container.read(panelProvider(PanelSide.remote));
      await left.navigateToPath('/alpha');
      await right.navigateToPath('/cloud');
      await right.toggleFlatView();
      expect(right.isFlatView, isTrue);
      await right.navigateToPath('/other');
      expect(right.isFlatView, isFalse);
      expect(await left.swapViewWith(right), isTrue);
      expect(left.isLoading, isFalse);
      expect(left.currentPath, '/other');
      expect(left.captureCurrentOrigin().source.currentPath, '/other');
      expect(left.files!.any((row) => row.name == 'next.txt'), isTrue);
    },
  );

  testWidgets('a slow swap respects a newer active-pane choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final local = _Local();
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFileServiceProvider.overrideWithValue(local),
          authProvider.overrideWith((_) => _Auth()),
        ],
        child: Consumer(
          builder: (context, value, child) {
            ref = value;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final left = ref.read(panelProvider(PanelSide.local));
    final right = ref.read(panelProvider(PanelSide.remote));
    await left.navigateToPath('/alpha');
    await right.navigateToPath('/beta');
    final pending = local.blocked['/beta'] =
        Completer<List<FileSystemEntity>>();
    final swapping = swapPanelSources(ref);
    await tester.pump();
    ref.read(activePanelProvider.notifier).state = PanelSide.remote;
    ref.read(focusAreaProvider.notifier).state = FocusArea.remote;
    pending.complete([]);
    await swapping;
    expect(ref.read(activePanelProvider), PanelSide.remote);
    expect(ref.read(focusAreaProvider), FocusArea.remote);
    expect(left.currentPath, '/beta');
    expect(right.currentPath, '/alpha');
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'swap during a legacy cloud refresh retains the actual endpoint',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = _PendingCloud()..put('/cloud/remote.txt', [1]);
      final container = ProviderContainer(
        overrides: [
          localFileServiceProvider.overrideWithValue(_Local()),
          authProvider.overrideWith((_) => _Auth(cloud)),
        ],
      );
      addTearDown(container.dispose);
      final left = container.read(panelProvider(PanelSide.local));
      final right = container.read(panelProvider(PanelSide.remote));
      await left.navigateToPath('/alpha');
      await right.navigateToPath('/cloud');
      expect(
        container.read(panelSourceProvider(PanelSide.remote)),
        isA<LocalPanelSource>(),
      );
      cloud.pending = Completer<void>();
      final refresh = right.refresh();
      await Future<void>.delayed(Duration.zero);
      final swapping = left.swapViewWith(right);
      await Future<void>.delayed(Duration.zero);
      cloud.pending!.complete();
      await refresh;
      expect(await swapping, isTrue);
      expect(left.currentPath, '/cloud');
      expect(
        (left.captureCurrentOrigin().source as RemotePanelSource).client,
        same(cloud),
      );
      expect(right.captureCurrentOrigin().source, isA<LocalPanelSource>());
      expect(right.currentPath, '/alpha');
    },
  );
}

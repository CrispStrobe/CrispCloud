import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:crisp_cloud/widgets/file_collections_dialog.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/widgets/pattern_selection_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends Fake implements CloudStorageClient {
  _Cloud({this.account = 'account-a'});
  final String account;
  @override
  String get providerName => 'Test cloud';
  @override
  String? get userId => account;
  @override
  String? get bucketId => 'bucket-a';
  @override
  String get rootPath => '/';
  bool authenticated = true;
  @override
  bool get isAuthenticated => authenticated;
  final paths = <String>[];
  final objectIds = <String, String>{};
  final listings = <String, List<String>>{
    '/': ['a.txt', 'b.txt'],
    '/one': ['same.txt'],
    '/two': ['same.txt'],
  };
  Completer<void>? delay;
  Completer<Uint8List>? pendingDownload;
  final downloads = <String>[];
  Uint8List archiveBytes = Uint8List.fromList(
    ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('hello.txt', 5, [72, 101, 108, 108, 111])),
    ),
  );

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    downloads.add(remotePath);
    return pendingDownload == null
        ? archiveBytes
        : await pendingDownload!.future;
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    paths.add(path);
    await delay?.future;
    return {
      'files': [
        for (final name in listings[path] ?? const <String>[])
          {
            'name': name,
            'size': 10,
            'uuid': objectIds['${path == '/' ? '' : path}/$name'],
          },
      ],
      'folders': <Map<String, dynamic>>[],
    };
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool isConnected = true;
  @override
  String? userEmail = 'a@example.test';
  @override
  String get providerName => client.providerName;
  void connection(bool connected) {
    isConnected = connected;
    client.authenticated = connected;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  @override
  String currentPath = '/';
  String? directory;
  @override
  String? get grantedBasePath => directory ?? '/';
  @override
  Future<String> getInitialPath() async => directory ?? '/';
  @override
  Future<String> getSafeFallbackDirectory() async => directory ?? '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  final paths = <String>[];
  Future<void> Function()? onRefresh;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    paths.add(path);
    return directory == null
        ? []
        : Directory(path).list(followLinks: false).toList();
  }
  @override
  Future<void> refresh() async {
    await onRefresh?.call();
  }
  Future<void> Function(String)? onAccess;
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() operation,
  ) async {
    await onAccess?.call(path);
    return operation();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late _Auth auth;
  late _Local local;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    auth = _Auth(cloud);
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
  });

  tearDown(() => container.dispose());

  FileItem item(String path) =>
      FileItem(name: path.split('/').last, path: path, isFolder: false);

  Future<PanelNotifier> remote() async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    return panel;
  }

  test(
    'path-based cloud providers have distinct full-path selection identities',
    () async {
      final panel = await remote();
      panel.selectAll();
      expect(panel.selection.map((file) => file.path).toSet(), {
        '/a.txt',
        '/b.txt',
      });
      expect(panel.captureCurrentOrigin().source, isA<RemotePanelSource>());
      expect(
        container.read(panelSourceProvider(PanelSide.remote)),
        isA<LocalPanelSource>(),
      );
    },
  );

  test(
    'pattern actions mark visible matches and preserve unmatching marks',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/a.jpg'),
        item('/b.png'),
        item('/thumb.jpg'),
        item('/c.txt'),
      ]);
      panel.applyPatternSelection(FileSelectionPattern('*.jpg;*.png|thumb*'));
      expect(panel.selection.map((file) => file.name).toSet(), {
        'a.jpg',
        'b.png',
      });
      panel.applyPatternSelection(
        FileSelectionPattern('*.png'),
        action: SelectionAction.deselect,
      );
      expect(panel.selection.single.name, 'a.jpg');
      panel.applyPatternSelection(
        FileSelectionPattern('*.jpg'),
        action: SelectionAction.invert,
      );
      expect(panel.selection.single.name, 'thumb.jpg');
      panel.setFilter('b');
      panel.applyPatternSelection(
        FileSelectionPattern('*'),
        action: SelectionAction.replace,
      );
      expect(panel.selection.single.name, 'b.png');
      expect(panel.filterQuery, 'b');
      expect(() => panel.selectByPattern('*|'), throwsFormatException);
      expect(panel.selection.single.name, 'b.png');
    },
  );

  test(
    'unverified same-path objects do not gain operation permission',
    () async {
      final panel = await remote();
      final listed = panel.files!.first;
      expect(panel.captureOperationOrigin([listed]).isCurrent, isTrue);
      expect(
        () => panel.captureOperationOrigin([listed.copyWith()]),
        throwsStateError,
      );
      panel.showSearchResults([listed.copyWith()]);
      expect(
        () => panel.captureOperationOrigin(panel.files!),
        throwsStateError,
      );
    },
  );

  test('select all, invert and shift-click change only visible rows', () async {
    final panel = await remote();
    // Extension filtering uses substring matching; the app defaults to prefix
    // matching, which correctly would not match ".txt" against "a.txt".
    await container
        .read(quickSearchSettingsProvider.notifier)
        .setMatchFromStart(false);
    panel.showSearchResults([
      item('/a.txt'),
      item('/b.png'),
      item('/c.txt'),
      item('/d.png'),
    ], origin: panel.captureRemoteSearchOrigin());
    final rows = {for (final file in panel.files!) file.name: file};
    panel.setFilter('.txt');
    expect(panel.displayedFiles!.map((file) => file.name), ['a.txt', 'c.txt']);
    panel.selectAll();
    expect(panel.selection.map((file) => file.name).toSet(), {
      'a.txt',
      'c.txt',
    });
    panel.clearFilter();
    panel.toggleSelection(rows['b.png']!, ctrlKey: true);
    panel.setFilter('.txt');
    panel.invertSelection();
    expect(panel.selection.single.name, 'b.png');
    panel.clearSelection();
    panel.toggleSelection(rows['a.txt']!);
    panel.toggleSelection(rows['c.txt']!, shiftKey: true);
    expect(panel.selection.map((file) => file.name).toSet(), {
      'a.txt',
      'c.txt',
    });
  });

  test(
    'selection memory resolves fresh rows by original source and path',
    () async {
      final panel = await remote();
      final origin = panel.captureRemoteSearchOrigin();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: origin);
      panel.applyPatternSelection(
        FileSelectionPattern('/two/*', matchFullPath: true),
      );
      final old = panel.selection.single;
      expect(panel.rememberSelection(), 1);
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: origin);
      expect(panel.restoreSelection(), 1);
      expect(panel.selection.single.path, '/two/same.txt');
      expect(identical(panel.selection.single, old), isFalse);
      expect(
        panel.captureOperationOrigin(panel.selection.toList()).isCurrent,
        isTrue,
      );
      panel.setFilter('no visible matches');
      expect(panel.restorableSelectionCount, 0);
    },
  );

  test(
    'selection memory does not select a replacement object or another account',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt').copyWith(uuid: 'original-object'),
      ], origin: panel.captureRemoteSearchOrigin());
      panel.selectAll();
      expect(panel.rememberSelection(), 1);
      panel.showSearchResults([
        item('/one/same.txt').copyWith(uuid: 'replacement-object'),
      ], origin: panel.captureRemoteSearchOrigin());
      expect(panel.restoreSelection(), 0);
      expect(panel.selection, isEmpty);

      auth.connection(false);
      auth.connection(true);
      panel.showSearchResults([
        item('/one/same.txt').copyWith(uuid: 'original-object'),
      ], origin: panel.captureRemoteSearchOrigin());
      expect(panel.restorableSelectionCount, 0);
      expect(panel.restoreSelection(), 0);
      expect(panel.selection, isEmpty);
    },
  );

  test('selection memories stay with their original tabs', () async {
    final panel = await remote();
    panel.showSearchResults([
      item('/one/same.txt'),
    ], origin: panel.captureRemoteSearchOrigin());
    final firstTab = panel.activeTabId;
    panel.selectAll();
    panel.rememberSelection();
    panel.addTab(path: '/two');
    await panel.refresh();
    expect(panel.rememberedSelectionCount, 0);
    panel.selectAll();
    panel.rememberSelection();
    panel.selectTab(firstTab);
    panel.clearSelection();
    expect(panel.restoreSelection(), 1);
    expect(panel.selection.single.path, '/one/same.txt');
  });

  test(
    'mixed-storage same-path results retain distinct verified account groups',
    () async {
      final remotePanel = await remote();
      final localPanel = container.read(panelProvider(PanelSide.local));
      await localPanel.refresh();
      final cloudOrigin = remotePanel.captureRemoteSearchOrigin();
      final localOrigin = localPanel.captureCurrentOrigin();
      final cloudFile = item('/one/same.txt');
      final localFile = item('/one/same.txt');
      remotePanel.showSearchResults(
        [cloudFile, localFile],
        originForFile: (file) =>
            identical(file, cloudFile) ? cloudOrigin : localOrigin,
      );
      expect(remotePanel.files!.toSet().length, 2);
      remotePanel.selectAll();
      final groups = remotePanel.captureOperationGroups(
        remotePanel.selection.toList(),
      );
      expect(groups.length, 2);
      expect(groups.keys.map((origin) => origin.storageId).toSet().length, 2);
      expect(
        () => remotePanel.captureOperationOrigin(remotePanel.files!),
        throwsStateError,
      );
      expect(remotePanel.showingSearchResults, isTrue);
    },
  );

  test('verified result rows retain original editor targets and reject copied stale objects', () async {
    final panel = await remote();
    final listed = panel.files!.first;
    panel.showSearchResults([listed]);
    final result = panel.files!.single;
    expect(result.path, '/a.txt');
    expect(panel.captureOperationOrigin([result]).isCurrent, isTrue);
    expect(panel.originForFile(result)!.isCurrent, isTrue);
    expect(panel.originForFile(result.copyWith()), isNull);
    expect(panel.originForFile(listed), isNull);
  });

  test(
    'result snapshot survives refresh and duplicate basenames remain distinct',
    () async {
      final panel = await remote();
      final origin = panel.captureRemoteSearchOrigin();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: origin);
      final requests = cloud.paths.length;
      panel.selectAll();
      expect(panel.selection.length, 2);
      await panel.refresh();
      expect(cloud.paths.length, requests + 2);
      expect(panel.files!.length, 2);
      expect(panel.exportFileListPaths().split('\n').toSet(), {
        '/one/same.txt',
        '/two/same.txt',
      });
    },
  );

  test(
    'saved collection reopens after restart with marks and missing rows intact',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      panel.toggleSelection(panel.files!.first);
      final id = await panel.saveCurrentCollection('Named results');
      container.dispose();
      cloud = _Cloud();
      cloud.listings['/two'] = [];
      auth = _Auth(cloud);
      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => auth),
          localFileServiceProvider.overrideWithValue(local),
        ],
      );
      final reopened = await remote();
      await reopened.openCollection(id);
      expect(reopened.activeCollectionId, id);
      expect(reopened.files!.length, 2);
      expect(reopened.selection.single.path, '/one/same.txt');
      final missing = reopened.files!.singleWhere(
        (file) => file.path == '/two/same.txt',
      );
      expect(missing.metadata?['collectionState'], 'missing');
      expect(reopened.originForOperation(missing), isNull);
      final ready = reopened.files!.singleWhere(
        (file) => file.path == '/one/same.txt',
      );
      expect(reopened.originForOperation(ready), isNotNull);
    },
  );

  test(
    'reopening a collection never substitutes the currently connected account',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      final id = await panel.saveCurrentCollection('Original account');
      container.dispose();
      cloud = _Cloud(account: 'different-account');
      auth = _Auth(cloud);
      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => auth),
          localFileServiceProvider.overrideWithValue(local),
        ],
      );
      final reopened = await remote();
      final before = cloud.paths.length;
      await reopened.openCollection(id);
      expect(cloud.paths.length, before);
      expect(reopened.files!.single.metadata?['collectionState'], 'offline');
      expect(reopened.originForOperation(reopened.files!.single), isNull);
    },
  );

  test(
    'collection replacement approval is limited to the exact reviewed rows',
    () async {
      cloud.objectIds.addAll({
        '/a.txt': 'original-a',
        '/b.txt': 'original-b',
      });
      final panel = await remote();
      panel.showSearchResults(
        panel.files!,
        origin: panel.captureCurrentOrigin(),
      );
      panel.selectAll();
      cloud.objectIds['/a.txt'] = 'replacement-a';
      await panel.refreshCollectionItems();
      final reviewed = panel.collectionReplacements;
      expect(reviewed.single.path, '/a.txt');

      // This replacement was absent from the review the user approved.
      cloud.objectIds['/b.txt'] = 'unreviewed-replacement-b';
      await panel.acceptCollectionReplacements(reviewed);
      final rows = {for (final file in panel.files!) file.path: file};
      expect(rows['/a.txt']!.uuid, 'replacement-a');
      expect(panel.originForOperation(rows['/a.txt']!), isNotNull);
      expect(rows['/b.txt']!.uuid, 'original-b');
      expect(rows['/b.txt']!.metadata?['collectionReplacement'], isTrue);
      expect(panel.originForOperation(rows['/b.txt']!), isNull);
      expect(panel.selection.map((file) => file.path).toSet(), {
        '/a.txt',
        '/b.txt',
      });
      expect(
        () => panel.captureOperationGroups(panel.selection.toList()),
        throwsStateError,
      );
      await expectLater(
        panel.acceptCollectionReplacements([rows['/b.txt']!.copyWith()]),
        throwsStateError,
      );
      await expectLater(
        panel.acceptCollectionReplacements(reviewed),
        throwsStateError,
      );
    },
  );

  test(
    'return from a refreshed collection uses its cloud parent in the local pane',
    () async {
      final remotePanel = await remote();
      final original = remotePanel.captureRemoteSearchOrigin();
      final panel = container.read(panelProvider(PanelSide.local));
      await panel.refresh();
      panel.showSearchResults([item('/one/same.txt')], origin: original);
      await panel.refreshCollectionItems();
      await panel.clearSearchResults();
      expect(panel.showingSearchResults, isFalse);
      expect(panel.currentPath, '/one');
      expect(cloud.paths.last, '/one');
      expect(cloud.paths, isNot(contains('/one/same.txt')));
      final reopened = panel.captureCurrentOrigin();
      expect((reopened.source as RemotePanelSource).client, same(cloud));
      expect(reopened.storageReference, original.storageReference);
    },
  );

  test(
    'collection manager changes survive open tabs and automatic persistence',
    () async {
      container.dispose();
      auth = _Auth(cloud);
      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => auth),
          localFileServiceProvider.overrideWithValue(local),
          panelProvider(PanelSide.remote).overrideWith(
            (ref) => PanelNotifier(ref, PanelSide.remote, persistTabs: true),
          ),
        ],
      );
      final panel = container.read(panelProvider(PanelSide.remote));
      await Future<void>.delayed(Duration.zero);
      await panel.refresh();
      final original = panel.captureCurrentOrigin();
      panel.toggleSelection(
        panel.files!.singleWhere((file) => file.path == '/a.txt'),
      );
      final id = await panel.saveCurrentCollection(
        'Original name',
        selectedOnly: true,
      );
      await panel.openCollection(id);
      final firstTab = panel.activeTabId;
      await panel.openCollection(id, newTab: true);
      final secondTab = panel.activeTabId;
      expect(secondTab, isNot(firstTab));
      final otherPanel = container.read(panelProvider(PanelSide.local));
      await otherPanel.refresh();
      await otherPanel.openCollection(id);
      final store = container.read(fileCollectionStoreProvider);
      final prefs = await SharedPreferences.getInstance();
      await Future<void>.delayed(Duration.zero);
      final savedTabs = jsonDecode(prefs.getString('panel_tabs_remote')!) as List;
      expect(
        savedTabs.where((tab) => (tab as Map)['collectionId'] == id).length,
        2,
      );

      Future<void> selectAndSave(String tabId) async {
        panel.selectTab(tabId);
        await Future<void>.delayed(Duration.zero);
      }

      await panel.renameSavedCollection(id, 'Renamed collection');
      expect(otherPanel.fileListTitle, 'Renamed collection');
      await selectAndSave(firstTab);
      expect(panel.fileListTitle, 'Renamed collection');
      expect(store.get(id)!.name, 'Renamed collection');
      expect(
        (jsonDecode(prefs.getString('commander_collection_v1_$id')!)
            as Map<String, dynamic>)['name'],
        'Renamed collection',
      );

      // Append from an ordinary directory while this collection remains open
      // in the other pane and in two inactive tabs of this pane.
      panel.addTab(path: '/two');
      expect(panel.activeTab!.storage, original.storageReference);
      expect(
        container.read(panelSourceProvider(PanelSide.remote)),
        isA<RemotePanelSource>().having(
          (source) => source.client,
          'captured client',
          same(cloud),
        ),
      );
      await panel.navigateToPath('/two', origin: original);
      panel.toggleSelection(
        panel.files!.singleWhere((file) => file.path == '/two/same.txt'),
      );
      await panel.appendToCollection(id);
      expect(otherPanel.files!.map((file) => file.path).toSet(), {
        '/a.txt',
        '/two/same.txt',
      });
      for (final tabId in [firstTab, secondTab]) {
        await selectAndSave(tabId);
        expect(panel.activeCollectionId, id);
        expect(panel.fileListTitle, 'Renamed collection');
        expect(panel.files!.map((file) => file.path).toSet(), {
          '/a.txt',
          '/two/same.txt',
        });
      }
      expect(store.get(id)!.entries.map((entry) => entry.reference.path).toSet(), {
        '/a.txt',
        '/two/same.txt',
      });
      expect(store.get(id)!.name, 'Renamed collection');

      // Manager actions can originate from either visual pane. Rename and
      // Add above use the right pane; removal exercises the left pane.
      await otherPanel.removeSavedCollection(id);
      expect(panel.activeCollectionId, isNull);
      expect(otherPanel.activeCollectionId, isNull);
      expect(panel.tabs.any((tab) => tab.collectionId == id), isFalse);
      expect(otherPanel.tabs.any((tab) => tab.collectionId == id), isFalse);
      // Saving every formerly linked tab must not recreate the removed record.
      for (final tabId in [firstTab, secondTab]) {
        if (panel.tabs.any((tab) => tab.id == tabId)) {
          await selectAndSave(tabId);
        }
      }
      otherPanel.selectTab(otherPanel.activeTabId);
      await Future<void>.delayed(Duration.zero);
      expect(store.collections, isEmpty);
      expect(prefs.getString('commander_collection_v1_$id'), isNull);
      expect(prefs.getStringList('commander_collections_v1'), isEmpty);
    },
  );

  test(
    'a delayed local refresh cannot replace a newer captured cloud navigation',
    () async {
      final panel = await remote();
      final original = panel.captureCurrentOrigin();
      container.read(panelSourceProvider(PanelSide.remote).notifier).setSource(
        const LocalPanelSource('/local'),
      );
      await panel.refresh();
      final localReads = local.paths.length;
      final preparationStarted = Completer<void>();
      final releasePreparation = Completer<void>();
      addTearDown(() {
        if (!releasePreparation.isCompleted) releasePreparation.complete();
      });
      local.onRefresh = () {
        preparationStarted.complete();
        return releasePreparation.future;
      };

      final staleRefresh = panel.refresh();
      await preparationStarted.future;
      await panel.navigateToPath('/two', origin: original);
      expect(panel.files!.any((file) => file.path == '/two/same.txt'), isTrue);
      releasePreparation.complete();
      await staleRefresh;

      expect(local.paths.length, localReads);
      expect(panel.currentPath, '/two');
      expect(panel.files!.any((file) => file.path == '/two/same.txt'), isTrue);
      expect(panel.captureCurrentOrigin().storageReference, original.storageReference);
    },
  );

  test('opening a collection in a new tab skips its interim directory load', () async {
    final panel = await remote();
    panel.showSearchResults(
      [item('/two/same.txt')],
      origin: panel.captureCurrentOrigin(),
    );
    final id = await panel.saveCurrentCollection('Nested item');
    await panel.clearSearchResults();
    final previousTab = panel.activeTabId;
    cloud.paths.clear();
    local.paths.clear();

    await panel.openCollection(id, newTab: true);

    expect(panel.activeTabId, isNot(previousTab));
    expect(panel.activeCollectionId, id);
    expect(panel.files!.single.path, '/two/same.txt');
    expect(panel.captureOperationOrigin(panel.files!).source, isA<RemotePanelSource>());
    expect(cloud.paths, contains('/two'));
    expect(cloud.paths, isNot(contains('/')));
    expect(local.paths, isEmpty);
  });

  test('a new tab keeps the cloud namespace and default path during a later refresh', () async {
    final panel = await remote();
    final original = panel.captureCurrentOrigin();
    final path = panel.currentPath;
    expect(
      container.read(panelSourceProvider(PanelSide.remote)),
      isA<LocalPanelSource>(),
    );
    final releaseCloud = Completer<void>();
    cloud.delay = releaseCloud;
    addTearDown(() {
      if (!releaseCloud.isCompleted) releaseCloud.complete();
    });
    final refreshing = panel.refresh();
    expect(panel.isLoading, isTrue);

    panel.addTab();

    final source = container.read(panelSourceProvider(PanelSide.remote));
    expect(source, isA<RemotePanelSource>());
    expect((source as RemotePanelSource).client, same(cloud));
    expect(source.currentPath, path);
    expect(panel.activeTab!.storage, original.storageReference);
    releaseCloud.complete();
    await refreshing;
    await panel.refresh();
    expect(panel.currentPath, path);
    expect(panel.captureCurrentOrigin().storageReference, original.storageReference);
    expect(panel.files!.map((file) => file.name).toSet(), {'a.txt', 'b.txt'});
  });

  for (final chooseLocal in [false, true]) {
    test(
      chooseLocal
          ? 'a new tab during initial loading honors an explicit local source'
          : 'a new tab during initial loading retains the legacy cloud source',
      () async {
        final panel = container.read(panelProvider(PanelSide.remote));
        final releaseCloud = Completer<void>();
        cloud.delay = releaseCloud;
        addTearDown(() {
          if (!releaseCloud.isCompleted) releaseCloud.complete();
        });
        final initialListing = panel.refresh();
        expect(cloud.paths, contains('/'));
        if (chooseLocal) {
          container.read(panelSourceProvider(PanelSide.remote).notifier).setSource(
            const LocalPanelSource('/local'),
          );
        }

        panel.addTab(path: '/two');
        final source = container.read(panelSourceProvider(PanelSide.remote));
        expect(source.currentPath, '/two');
        expect(source.isLocal, chooseLocal);
        expect(panel.activeTab!.storage!.isLocal, chooseLocal);
        releaseCloud.complete();
        await initialListing;
        await panel.refresh();

        expect(panel.currentPath, '/two');
        expect(panel.captureCurrentOrigin().source.isLocal, chooseLocal);
        expect(
          panel.files!.any((file) => file.path == '/two/same.txt'),
          !chooseLocal,
        );
        if (chooseLocal) expect(cloud.paths, isNot(contains('/two')));
      },
    );
  }

  test(
    'queued local autosaves preserve the later collection marks',
    () async {
      container.dispose();
      auth = _Auth(cloud);
      final prefs = await SharedPreferences.getInstance();
      final firstSaveStarted = Completer<void>();
      final releaseFirstSave = Completer<SharedPreferences>();
      var pauseNextSave = false;
      final store = FileCollectionStore(
        preferences: () {
          if (pauseNextSave) {
            pauseNextSave = false;
            firstSaveStarted.complete();
            return releaseFirstSave.future;
          }
          return Future.value(prefs);
        },
      );
      addTearDown(() {
        if (!releaseFirstSave.isCompleted) releaseFirstSave.complete(prefs);
      });
      await store.ready;
      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => auth),
          localFileServiceProvider.overrideWithValue(local),
          fileCollectionStoreProvider.overrideWith((_) => store),
          panelProvider(PanelSide.remote).overrideWith(
            (ref) => PanelNotifier(ref, PanelSide.remote, persistTabs: true),
          ),
        ],
      );
      final panel = container.read(panelProvider(PanelSide.remote));
      await Future<void>.delayed(Duration.zero);
      await panel.refresh();
      final id = await panel.saveCurrentCollection('Rapid marks');
      await panel.openCollection(id);
      await Future<void>.delayed(Duration.zero);
      final a = panel.files!.singleWhere((file) => file.path == '/a.txt');
      final b = panel.files!.singleWhere((file) => file.path == '/b.txt');
      final keyB = store
          .get(id)!
          .entries
          .singleWhere((entry) => entry.reference.path == '/b.txt')
          .key;

      panel.toggleSelection(a);
      pauseNextSave = true;
      panel.toggleTabPin(panel.activeTabId);
      await Future<void>.delayed(Duration.zero);
      expect(firstSaveStarted.isCompleted, isTrue);
      await firstSaveStarted.future;

      // The first save has captured A and is waiting for persistence. B must
      // survive when its queued save follows the first save's new baseline.
      panel.toggleSelection(b);
      panel.toggleTabPin(panel.activeTabId);
      expect(panel.selection.single, same(b));
      releaseFirstSave.complete(prefs);
      await Future<void>.delayed(Duration.zero);

      expect(store.get(id)!.selectedKeys, {keyB});
      final persisted =
          jsonDecode(prefs.getString('commander_collection_v1_$id')!)
              as Map<String, dynamic>;
      expect(Set<String>.from(persisted['selectedKeys'] as List), {keyB});
    },
  );

  test(
    'result operations fail closed after disconnect and reconnect',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      final pinned = panel.captureOperationOrigin(panel.files!);
      auth.connection(false);
      auth.connection(true);
      expect(pinned.isCurrent, isFalse);
      expect(panel.canOperateOnFileList, isFalse);
      expect(
        () => panel.captureOperationOrigin(panel.files!),
        throwsStateError,
      );
    },
  );

  test(
    'operation sibling preview follows the captured source after navigation',
    () async {
      final panel = await remote();
      final origin = panel.captureCurrentOrigin();
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(const LocalPanelSource('/local'));
      await panel.refresh();

      final siblings = await panel.listOperationDirectory('/two', origin);
      expect(siblings.single.path, '/two/same.txt');
      expect(cloud.paths.last, '/two');
      expect(panel.captureCurrentOrigin().source, isA<LocalPanelSource>());
    },
  );

  test(
    'operation sibling preview rejects an account changed during listing',
    () async {
      final panel = await remote();
      final origin = panel.captureCurrentOrigin();
      cloud.delay = Completer<void>();
      final listing = panel.listOperationDirectory('/one', origin);
      await Future<void>.delayed(Duration.zero);
      auth.connection(false);
      auth.connection(true);
      cloud.delay!.complete();
      await expectLater(listing, throwsStateError);
    },
  );

  test('operation metadata stays source-bound and rejects relative or stale lookups', () async {
    final panel = await remote();
    final origin = panel.captureCurrentOrigin();
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(const LocalPanelSource('/local'));
    await panel.refresh();

    final info = await panel.operationFileInfo('/a.txt', origin);
    expect(info?.path, '/a.txt');
    expect(info?.size, 10);
    expect(panel.captureCurrentOrigin().source, isA<LocalPanelSource>());
    expect(await panel.operationFileInfo('/missing.txt', origin), isNull);
    expect(await panel.operationPathExists('/missing.txt', origin), isFalse);
    final requests = cloud.paths.length;
    await expectLater(
      panel.operationFileInfo('a.txt', origin),
      throwsFormatException,
    );
    expect(cloud.paths.length, requests);

    cloud.delay = Completer<void>();
    final pending = panel.operationFileInfo('/b.txt', origin);
    await Future<void>.delayed(Duration.zero);
    auth.connection(false);
    auth.connection(true);
    cloud.delay!.complete();
    await expectLater(pending, throwsStateError);
  });

  test(
    'native panel rename cannot replace a target created after preview',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'commander-rename-race-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = await File('${root.path}/source.txt')
          .writeAsString('source');
      final target = File('${root.path}/target.txt');
      local.directory = root.path;
      final panel = container.read(panelProvider(PanelSide.local));
      await panel.navigateToPath(root.path);
      final file = panel.files!.singleWhere((item) => item.path == source.path);
      local.onAccess = (path) async {
        if (path == source.path) {
          await target.writeAsString('concurrent target');
        }
      };

      await expectLater(
        panel.renameFile(
          file,
          'target.txt',
          refreshAfter: false,
          rethrowErrors: true,
          recordHistory: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await source.readAsString(), 'source');
      expect(await target.readAsString(), 'concurrent target');
    },
    skip: !supportsNativeExclusiveRename,
  );

  test('remove-from-list never deletes underlying local files', () async {
    final root = await Directory.systemTemp.createTemp('commander-list-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/one').create();
    await Directory('${root.path}/two').create();
    final a = await File('${root.path}/one/same.txt').writeAsString('one');
    final b = await File('${root.path}/two/same.txt').writeAsString('two');
    local.directory = root.path;
    final panel = container.read(panelProvider(PanelSide.local));
    await panel.navigateToPath(root.path);
    final result = await panel.importFileListPaths('${a.path}\n${b.path}');
    expect(result.loaded, 2);
    final row = panel.files!.firstWhere((file) => file.path == a.path);
    panel.removeFromFileList([row]);
    expect(panel.files!.single.path, b.path);
    expect(await a.readAsString(), 'one');
    expect(await b.readAsString(), 'two');
    expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
  });

  test('import verifies remote paths and reports missing rows', () async {
    final panel = await remote();
    final result = await panel.importFileListPaths(
      '/one/same.txt\n/two/same.txt\n/two/missing.txt',
    );
    expect(result.loaded, 2);
    expect(result.failures.keys, ['/two/missing.txt']);
    expect(panel.files!.map((item) => item.name), ['same.txt', 'same.txt']);
    expect(
      panel.captureOperationOrigin(panel.files!).source,
      isA<RemotePanelSource>(),
    );
  });

  test(
    'account change during import cannot publish an actionable list',
    () async {
      final panel = await remote();
      cloud.delay = Completer<void>();
      final import = panel.importFileListPaths('/one/same.txt');
      await Future<void>.delayed(Duration.zero);
      auth.connection(false);
      auth.connection(true);
      cloud.delay!.complete();
      await expectLater(import, throwsStateError);
      expect(panel.showingSearchResults, isFalse);
    },
  );

  test(
    'list updates are keyed by full source paths, retaining provenance',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      panel.applyFileListChanges({'/one/same.txt': item('/one/new.txt')});
      expect(panel.files!.map((item) => item.path).toSet(), {
        '/one/new.txt',
        '/two/same.txt',
      });
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
      panel.applyFileListChanges({'/one/new.txt': null});
      expect(panel.files!.single.path, '/two/same.txt');
    },
  );

  test('completion updates the saved source list without changing same-path rows in another storage', () async {
    final panel = await remote();
    panel.showSearchResults([
      item('/one/same.txt'),
      item('/two/same.txt'),
    ], origin: panel.captureRemoteSearchOrigin());
    panel.selectAll();
    final originalTab = panel.activeTabId;
    final operationOrigin = panel.captureOperationOrigin(panel.files!);
    panel.addTab(path: '/two');
    await panel.refresh();
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(const LocalPanelSource('/local'));
    await panel.refresh();
    final localOrigin = panel.captureCurrentOrigin();
    expect(localOrigin.source, isA<LocalPanelSource>());
    panel.showSearchResults([
      item('/one/same.txt'),
      item('/two/same.txt'),
    ], origin: localOrigin);
    panel.selectAll();
    final localTab = panel.activeTabId;
    final localRows = List<FileItem>.of(panel.files!);

    expect(operationOrigin.isCurrent, isTrue);
    panel.applyFileListChanges({
      '/one/same.txt': null,
      '/two/same.txt': item('/two/renamed.txt'),
    }, origin: operationOrigin);

    expect(panel.files, localRows);
    expect(panel.selection.length, 2);
    panel.selectTab(originalTab);
    expect(panel.files!.single.path, '/two/renamed.txt');
    expect(panel.selection.single.path, '/two/renamed.txt');
    expect(
      panel.captureOperationOrigin(panel.files!).source,
      isA<RemotePanelSource>(),
    );
    panel.selectTab(localTab);
    expect(panel.files, localRows);
    expect(panel.selection.length, 2);
  });

  test(
    'completion updates an inactive list while a directory tab is active',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      final originalTab = panel.activeTabId;
      final operationOrigin = panel.captureOperationOrigin(panel.files!);
      panel.addTab(path: '/two');
      await panel.refresh();
      expect(panel.showingSearchResults, isFalse);
      final activeDirectory = panel.currentPath;
      final directoryRows = List<FileItem>.of(panel.files!);

      panel.applyFileListChanges({
        '/one/same.txt': null,
      }, origin: operationOrigin);

      expect(panel.showingSearchResults, isFalse);
      expect(panel.currentPath, activeDirectory);
      expect(panel.files, directoryRows);
      panel.selectTab(originalTab);
      expect(panel.files!.single.path, '/two/same.txt');
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
    },
  );

  test(
    'captured source updates remain applicable after same-storage navigation',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      final operationOrigin = panel.captureOperationOrigin(panel.files!);
      await panel.navigateToPath('/two');
      final currentOrigin = panel.captureCurrentOrigin();
      expect(operationOrigin.source.currentPath, '/');
      expect(currentOrigin.source.currentPath, '/two');
      panel.showSearchResults([item('/one/same.txt')], origin: currentOrigin);

      panel.applyFileListChanges({
        '/one/same.txt': item('/one/renamed.txt'),
      }, origin: operationOrigin);

      expect(panel.files!.single.path, '/one/renamed.txt');
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
    },
  );

  test('old-account completion cannot change a new session list on the same client', () async {
    final panel = await remote();
    panel.showSearchResults([
      item('/one/same.txt'),
    ], origin: panel.captureRemoteSearchOrigin());
    final operationOrigin = panel.captureOperationOrigin(panel.files!);
    auth.connection(false);
    auth.connection(true);
    panel.showSearchResults([
      item('/one/same.txt'),
    ], origin: panel.captureRemoteSearchOrigin());

    panel.applyFileListChanges({
      '/one/same.txt': null,
    }, origin: operationOrigin);

    expect(panel.files!.single.path, '/one/same.txt');
    expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
  });

  test(
    'open containing folder uses the result path and selects that exact file',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      await panel.openContainingFolder(
        panel.files!.firstWhere((file) => file.path == '/two/same.txt'),
      );
      expect(panel.showingSearchResults, isFalse);
      expect(cloud.paths.last, '/two');
      expect(panel.currentPath, '/two');
      expect(panel.selection.single.path, '/two/same.txt');
    },
  );

  test(
    'tabs retain virtual lists and their selection in this session',
    () async {
      final panel = await remote();
      panel.showSearchResults(
        [item('/one/same.txt'), item('/two/same.txt')],
        origin: panel.captureRemoteSearchOrigin(),
        title: 'Search: same',
      );
      final listTab = panel.activeTabId;
      panel.toggleSelection(panel.files!.first);
      panel.addTab(path: '/two');
      await panel.refresh();
      expect(panel.showingSearchResults, isFalse);
      panel.selectTab(listTab);
      expect(panel.showingSearchResults, isTrue);
      expect(panel.fileListTitle, 'Search: same');
      expect(panel.files!.length, 2);
      expect(panel.selection.length, 1);
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
    },
  );

  testWidgets('pattern dialog validates regex and applies visible matches', (
    tester,
  ) async {
    final panel = await remote();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return TextButton(
                  onPressed: () => showPatternSelectionDialog(
                    context,
                    ref,
                    PanelSide.remote,
                  ),
                  child: const Text('Open selection tool'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open selection tool'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regular expression'));
    await tester.enterText(
      find.byKey(const ValueKey('selection-pattern')),
      '[',
    );
    await tester.pump();
    final invalid = tester.widget<FilledButton>(
      find.byKey(const ValueKey('apply-pattern-selection')),
    );
    expect(invalid.onPressed, isNull);
    expect(panel.selection, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('selection-pattern')),
      r'^[ab]\.txt$',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('apply-pattern-selection')));
    await tester.pumpAndSettle();
    expect(panel.selection.map((item) => item.path).toSet(), {
      '/a.txt',
      '/b.txt',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('numpad plus opens selection instead of entering quick search', (
    tester,
  ) async {
    final panel = await remote();
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: FileListView(
              side: PanelSide.remote,
              files: panel.files!,
              scrollController: scroll,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    panel.focusList();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await tester.pumpAndSettle();
    expect(find.text('Select by pattern'), findsOneWidget);
    expect(panel.filterQuery, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadSubtract);
    await tester.pumpAndSettle();
    expect(find.text('Select by pattern'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test(
    'remote archives in a left-pane result list use captured cloud storage',
    () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future<void>.delayed(Duration.zero);
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(
            RemotePanelSource(
              providerName: cloud.providerName,
              client: cloud,
              path: '/',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      panel.showSearchResults([
        item('/two/archive.zip'),
      ], origin: panel.captureRemoteSearchOrigin());
      await panel.navigateInto(panel.files!.single);
      expect(cloud.downloads, ['/two/archive.zip']);
      expect(panel.isInArchive, isTrue);
      expect(panel.archiveSource!.parent, isA<RemotePanelSource>());
      final member = panel.files!.single;
      expect(panel.originForFile(member), isNull);
      expect(
        String.fromCharCodes(await panel.readArchiveMember(member)),
        'Hello',
      );
      panel.exitArchive();
      await Future<void>.delayed(Duration.zero);
      expect(panel.isInArchive, isFalse);
      expect(cloud.paths.last, '/two');
      expect(panel.currentPath, '/two');
    },
  );

  test(
    'account change during archive download cannot publish old-account members',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/two/archive.zip'),
      ], origin: panel.captureRemoteSearchOrigin());
      cloud.pendingDownload = Completer<Uint8List>();
      final opening = panel.enterArchive(panel.files!.single);
      await Future<void>.delayed(Duration.zero);
      auth.connection(false);
      auth.connection(true);
      cloud.pendingDownload!.complete(cloud.archiveBytes);
      await opening;
      expect(panel.isInArchive, isFalse);
      expect(cloud.downloads, ['/two/archive.zip']);
    },
  );

  test('refresh follows actual storage in either pane', () async {
    final left = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    container
        .read(panelSourceProvider(PanelSide.local).notifier)
        .setSource(
          RemotePanelSource(
            providerName: cloud.providerName,
            client: cloud,
            path: '/two',
          ),
        );
    await Future<void>.delayed(Duration.zero);
    await left.refresh();
    expect(left.captureCurrentOrigin().source, isA<RemotePanelSource>());
    expect(
      left.files!.where((file) => file.name != '..').single.path,
      '/two/same.txt',
    );

    final right = await remote();
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(const LocalPanelSource('/tmp'));
    await Future<void>.delayed(Duration.zero);
    final requests = cloud.paths.length;
    await right.refresh();
    expect(right.captureCurrentOrigin().source, isA<LocalPanelSource>());
    expect(cloud.paths.length, requests);
    expect(right.currentPath, '/tmp');
  });
  test('saved tab JSON preserves source namespace and collection labels', () {
    const storage = StorageReference(
      kind: 'remote',
      provider: 'Cloud',
      accountKey: 'original-account',
      root: '/',
    );
    final tab = PanelTab(
      id: 'tab-a',
      path: '/same',
      label: 'Review set',
      isPinned: true,
      storage: storage,
      collectionId: 'saved-collection',
    );
    final restored = PanelTab.fromJson('tab-b', tab.toJson());
    expect(restored.storage, storage);
    expect(restored.collectionId, 'saved-collection');
    expect(restored.isPinned, isTrue);
    expect(restored.copyWith().label, 'Review set');
  });

  testWidgets(
    'collections remain scrollable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await remote();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const Scaffold(
              body: FileCollectionsDialog(side: PanelSide.remote),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('collection-save')));
      expect(tester.takeException(), isNull);
      expect(find.text('Close'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

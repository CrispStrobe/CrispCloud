import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/file_grid_view.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends Fake implements CloudStorageClient {
  int count = 1800;
  final removed = <int>{};
  final replacements = <int, String>{};
  bool connected = true;
  Completer<void>? delay;
  Completer<void>? entered;
  @override
  String get providerName => 'Paging fixture';
  @override
  String get userId => 'original-account';
  @override
  String get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => connected;
  @override
  bool get supportsThumbnails => false;
  String name(int index) => 'file-${index.toString().padLeft(5, '0')}.txt';
  FileItem file(int index) => FileItem(
    name: name(index),
    path: '/${name(index)}',
    uuid: 'object-$index',
    isFolder: false,
    size: index + 1,
    updatedAt: DateTime.utc(2024, 1, 1),
  );
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    if (entered != null && !entered!.isCompleted) entered!.complete();
    await delay?.future;
    return {
      'files': [
        if (path == '/')
          for (var index = 0; index < count; index++)
            if (!removed.contains(index))
              {
                'name': name(index),
                'uuid': replacements[index] ?? 'object-$index',
                'size': index + 1,
                'lastModified': DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
              },
      ],
      'folders': [],
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
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  void disconnect() {
    isConnected = false;
    client.connected = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  Future<List<FileSystemEntity>> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _PausingStorage extends MemoryFileCollectionStorage {
  String? pausePrefix;
  Completer<void>? entered;
  Completer<void>? release;
  @override
  Future<void> write(String key, String value) async {
    if (pausePrefix != null && key.startsWith(pausePrefix!)) {
      pausePrefix = null;
      entered!.complete();
      await release!.future;
    }
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late _Auth auth;
  late FileCollectionStore store;
  late _PausingStorage storage;
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    auth = _Auth(cloud);
    storage = _PausingStorage();
    store = FileCollectionStore(
      storage: storage,
      cacheEntryLimit: 1000,
      cacheByteLimit: 1024 * 1024,
    );
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
        fileCollectionStoreProvider.overrideWith((_) => store),
      ],
    );
  });
  tearDown(() => container.dispose());

  FileCollection fixture(
    String id, {
    int count = 1800,
    Set<int> marks = const {0, 700, 1799},
    bool search = false,
  }) {
    final reference = storageReferenceForClient(cloud);
    final entries = [
      for (var index = count - 1; index >= 0; index--)
        FileCollectionService.capture(cloud.file(index), reference),
    ];
    return FileCollection(
      id: id,
      name: 'Collection $id',
      entries: entries,
      selectedKeys: {
        for (final index in marks)
          FileCollectionService.capture(cloud.file(index), reference).key,
      },
      search: search
          ? CollectionSearch(
              storage: reference,
              directory: '/',
              query: const FileSearchQuery(includeFolders: false),
            )
          : null,
    );
  }

  Future<PanelNotifier> open({
    String id = 'large',
    int count = 1800,
    Set<int> marks = const {0, 700, 1799},
    bool search = false,
  }) async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    await store.save(fixture(id, count: count, marks: marks, search: search));
    await panel.openCollection(id);
    return panel;
  }

  test(
    'bounded windows retain all off-page marks and prepare every original',
    () async {
      final panel = await open();
      expect(panel.files, hasLength(500));
      expect(panel.files!.first.path, '/file-00000.txt');
      expect(panel.collectionTotalCount, 1800);
      expect(panel.collectionPageCount, 4);
      expect(panel.selection, hasLength(3));
      expect(
        panel.originForOperation(
          panel.selection.singleWhere((row) => row.path == '/file-00700.txt'),
        ),
        isNull,
      );
      panel.toggleSelection(panel.files![1], ctrlKey: true);
      await panel.loadCollectionPage(2);
      expect(panel.collectionPageStart, 1000);
      expect(panel.files!.first.path, '/file-01000.txt');
      expect(panel.selection, hasLength(4));
      final captured = await panel.prepareOperationFiles(panel.selection);
      expect(captured.map((file) => file.path).toSet(), {
        '/file-00000.txt',
        '/file-00001.txt',
        '/file-00700.txt',
        '/file-01799.txt',
      });
      expect(
        captured.every((file) => panel.originForOperation(file) != null),
        isTrue,
      );
      final groups = panel.captureOperationGroups(captured);
      expect(groups, hasLength(1));
      expect(
        groups.keys.single.storageReference,
        storageReferenceForClient(cloud),
      );
      expect(store.get('large')!.selectedCount, 4);
      await panel.openCollection('large');
      expect(panel.selection, hasLength(4));
      expect(store.residentEntryCount, lessThanOrEqualTo(1000));
    },
  );

  test(
    'filter, sort, criteria, and path marks cover every physical page',
    () async {
      final panel = await open(marks: {});
      panel.setFilter('file-017');
      await panel.reloadCollectionQuery();
      expect(panel.collectionMatchingCount, 100);
      expect(panel.files, hasLength(100));
      expect(panel.files!.first.path, '/file-01700.txt');
      panel.toggleSortOrder();
      await panel.reloadCollectionQuery();
      expect(panel.files!.first.path, '/file-01799.txt');
      await panel.selectWholeCollection();
      expect(panel.selection, hasLength(100));
      panel.clearFilter();
      await panel.reloadCollectionQuery();
      final count = await panel.applyCollectionCriteriaSelection(
        const FileSearchQuery(namePattern: 'file-00*.txt', minSize: 501),
        action: SelectionAction.replace,
      );
      expect(count, 500);
      expect(panel.selection, hasLength(500));
      final source = panel.pathSelectionSources.single;
      final result = await panel.selectPathsFromListAsync(
        '/file-00000.txt\n/file-01799.txt',
        source: source,
        action: SelectionAction.replace,
      );
      expect(result.loaded, 2);
      expect(result.failures, isEmpty);
      expect(panel.selection.map((file) => file.path).toSet(), {
        '/file-00000.txt',
        '/file-01799.txt',
      });
    },
  );

  test('collection copies, append, export, and row removal preserve unseen originals', () async {
    final panel = await open();
    final id = await panel.saveCurrentCollection('Copy', createNew: true);
    expect(store.get(id)!.itemCount, 1800);
    final all = await panel.exportAllFileListPaths();
    expect(all.split('\n'), hasLength(1800));
    expect(all, contains('/file-01799.txt'));
    await store.save(fixture('destination', count: 2, marks: {}));
    await panel.appendToCollection('destination');
    expect(store.get('destination')!.itemCount, 4);
    await panel.removeFromFileList(panel.selection.toList());
    expect(store.get(id)!.itemCount, 1797);
    expect(store.get(id)!.selectedCount, 0);
    expect(cloud.removed, isEmpty);
  });

  test('one unavailable off-page original rejects the complete requested operation', () async {
    final panel = await open();
    cloud.removed.add(700);
    await expectLater(
      panel.prepareOperationFiles(panel.selection),
      throwsStateError,
    );
    expect(panel.selection, hasLength(3));
    cloud.removed.clear();
    cloud.replacements[700] = 'replacement-object';
    await expectLater(
      panel.prepareOperationFiles(panel.selection),
      throwsStateError,
    );
    expect(store.get('large')!.itemCount, 1800);
  });

  test('preparation progress is cancellable and never returns partial capabilities', () async {
    final panel = await open();
    cloud.delay = Completer<void>();
    cloud.entered = Completer<void>();
    final operation = panel.prepareOperationFiles(panel.selection);
    final expectation = expectLater(operation, throwsStateError);
    await cloud.entered!.future;
    expect(panel.collectionBusy, isTrue);
    panel.cancelCollectionRefresh();
    cloud.delay!.complete();
    await expectation;
    expect(panel.collectionBusy, isFalse);
    expect(panel.selection, hasLength(3));
  });

  test(
    'account disconnect during off-page preparation cannot rebind originals',
    () async {
      final panel = await open();
      cloud.delay = Completer<void>();
      cloud.entered = Completer<void>();
      final operation = panel.prepareOperationFiles(panel.selection);
      final expectation = expectLater(operation, throwsStateError);
      await cloud.entered!.future;
      auth.disconnect();
      cloud.delay!.complete();
      await expectation;
      expect(store.get('large')!.selectedCount, 3);
    },
  );

  test(
    'refresh keeps saved paths while rerun explicitly changes query membership',
    () async {
      final panel = await open(count: 3, marks: {0}, search: true);
      cloud.removed.add(1);
      await panel.refreshCollectionItems();
      expect(store.get('large')!.itemCount, 3);
      expect(
        panel.files!
            .singleWhere((file) => file.path == '/file-00001.txt')
            .metadata?['collectionState'],
        'missing',
      );
      await panel.refreshCollectionItems(rerunSearch: true);
      expect(store.get('large')!.itemCount, 1799);
      expect(panel.files, hasLength(500));
      expect(panel.selection.single.path, '/file-00000.txt');
    },
  );

  test(
    'inactive saved tabs retain metadata rather than collection payloads',
    () async {
      final panel = await open();
      final firstTab = panel.activeTabId;
      for (var index = 0; index < 7; index++) {
        await store.save(fixture('tab-$index'));
        await panel.openCollection('tab-$index', newTab: true);
        await panel.loadCollectionPage(3);
        expect(panel.retainedSavedCollectionRows, lessThanOrEqualTo(500));
        expect(store.residentEntryCount, lessThanOrEqualTo(1000));
      }
      await panel.selectTab(firstTab);
      expect(panel.activeCollectionId, 'large');
      expect(panel.selection, hasLength(3));
      expect(panel.retainedSavedCollectionRows, 500);
    },
  );

  test(
    'cancelling a collection-wide selection retains the previous marks',
    () async {
      final panel = await open();
      void cancel() {
        if (panel.collectionBusy &&
            panel.collectionProgress.startsWith('500 /')) {
          panel.cancelCollectionRefresh();
        }
      }

      panel.addListener(cancel);
      await expectLater(
        panel.applyCollectionCriteriaSelection(
          const FileSearchQuery(namePattern: '*'),
          action: SelectionAction.replace,
        ),
        throwsStateError,
      );
      panel.removeListener(cancel);
      expect(panel.selection, hasLength(3));
      expect(store.get('large')!.selectedCount, 3);
    },
  );

  test('replacement review accepts only its exact visible rows', () async {
    final panel = await open();
    cloud.replacements[0] = 'replacement-0';
    cloud.replacements[1799] = 'replacement-1799';
    await panel.refreshCollectionItems();
    expect(panel.collectionReplacements.map((file) => file.path), [
      '/file-00000.txt',
    ]);
    await panel.refreshCollectionItems(acceptReplacements: true);
    final saved = await store.load('large');
    expect(
      saved.entries
          .singleWhere((entry) => entry.reference.path == '/file-00000.txt')
          .reference
          .objectId,
      'replacement-0',
    );
    final unseen = saved.entries.singleWhere(
      (entry) => entry.reference.path == '/file-01799.txt',
    );
    expect(unseen.reference.objectId, 'object-1799');
    expect(unseen.replacement, isTrue);
    await expectLater(
      panel.prepareOperationFiles(panel.selection),
      throwsStateError,
    );
  });

  for (final grid in [false, true]) {
    testWidgets(
      '${grid ? 'grid' : 'list'} view keeps off-page marks through rebuilds and paging',
      (tester) async {
        final panel = (await tester.runAsync(() => open()))!;
        final controller = ScrollController();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final current = ref.watch(panelProvider(PanelSide.remote));
                    return grid
                        ? FileGridView(
                            side: PanelSide.remote,
                            files: current.files ?? [],
                            scrollController: controller,
                          )
                        : FileListView(
                            side: PanelSide.remote,
                            files: current.files ?? [],
                            scrollController: controller,
                          );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(panel.selection, hasLength(3));
        if (!grid) {
          final rows = tester.widgetList<CompactFileTile>(
            find.byType(CompactFileTile),
          );
          expect(
            rows.any((row) => row.isSelected && row.selectedFiles.length == 3),
            isTrue,
          );
          expect(panel.recognizesCollectionRows(panel.selection), isTrue);
        }
        await tester.runAsync(() => panel.loadCollectionPage(3));
        await tester.pumpAndSettle();
        expect(panel.selection.map((file) => file.path).toSet(), {
          '/file-00000.txt',
          '/file-00700.txt',
          '/file-01799.txt',
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        if (grid) {
          // This fixture owns its provider container beyond widget disposal.
          // Complete the panel reload requested when the gallery detaches.
          await tester.runAsync(panel.reloadCollectionQuery);
        }
        controller.dispose();
      },
    );
  }

  test(
    'old menu rows cannot rebind to a same-path replacement collection',
    () async {
      final panel = await open();
      final stale = panel.selection.toList();
      final storage = storageReferenceForClient(cloud);
      cloud.replacements[700] = 'new-object-700';
      final replacement = FileCollectionService.capture(
        cloud.file(700).copyWith(uuid: 'new-object-700'),
        storage,
      );
      await store.save(
        FileCollection(
          id: 'other',
          name: 'Replacement review',
          entries: [replacement],
          selectedKeys: {replacement.key},
        ),
      );
      await panel.openCollection('other');
      expect(panel.files!.single.uuid, 'new-object-700');
      await expectLater(panel.prepareOperationFiles(stale), throwsStateError);
      await expectLater(
        panel.prepareOperationFiles([panel.files!.single.copyWith()]),
        throwsStateError,
      );
      final prepared = await panel.prepareOperationFiles(panel.selection);
      final preparedAgain = await panel.prepareOperationFiles(prepared);
      expect(preparedAgain.single.uuid, 'new-object-700');
    },
  );

  test(
    'remember and restore retain verified marks across all pages and filters',
    () async {
      final panel = await open();
      expect(await panel.rememberCollectionSelection(), 3);
      await panel.loadCollectionPage(3);
      panel.clearSelection();
      await panel.flushCollectionMarks();
      expect(await panel.restoreCollectionSelection(), 3);
      expect(panel.selection.map((row) => row.path).toSet(), {
        '/file-00000.txt',
        '/file-00700.txt',
        '/file-01799.txt',
      });
      panel.setFilter('file-017');
      await panel.reloadCollectionQuery();
      expect(await panel.restoreCollectionSelection(), 1);
      expect(panel.selection.single.path, '/file-01799.txt');
      panel.clearFilter();
      await panel.reloadCollectionQuery();
      expect(await panel.restoreCollectionSelection(), 3);
      expect(panel.retainedSavedCollectionRows, lessThanOrEqualTo(500));
    },
  );

  test('remembered selection restore rejects an off-page replaced original as a whole', () async {
    final panel = await open();
    await panel.rememberCollectionSelection();
    panel.clearSelection();
    panel.toggleSelection(panel.files![2]);
    cloud.replacements[1799] = 'new-object';
    await expectLater(panel.restoreCollectionSelection(), throwsStateError);
    expect(panel.selection.single.path, '/file-00002.txt');
    expect(store.get('large')!.selectedCount, 1);
  });

  test('changing the collection during the first preparation await rejects captured rows', () async {
    final panel = await open();
    final original = panel.captureRemoteSearchOrigin();
    final pending = panel.prepareOperationFiles(panel.selection);
    final rejected = expectLater(pending, throwsStateError);
    panel.showSearchResults([
      cloud.file(0).copyWith(uuid: 'different-object'),
    ], origin: original);
    await rejected;
    expect(panel.files!.single.uuid, 'different-object');
  });

  test('opening another saved collection honors a locked tab without losing page state', () async {
    final panel = await open();
    final locked = panel.activeTabId;
    panel.setTabLock(locked, TabLockMode.locked);
    await store.save(fixture('second'));
    await panel.openCollection('second');
    expect(panel.activeTabId, isNot(locked));
    expect(panel.activeCollectionId, 'second');
    expect(panel.files, hasLength(500));
    expect(panel.selection, hasLength(3));
    expect(panel.collectionBusy, isFalse);
  });

  for (final prefix in ['page:', 'manifest:']) {
    test(
      'cancelling during staged $prefix mark persistence keeps all old marks',
      () async {
        final panel = await open();
        final before = Map<String, String>.of(storage.values);
        storage.pausePrefix = prefix;
        storage.entered = Completer<void>();
        storage.release = Completer<void>();
        final pending = panel.selectWholeCollection();
        final rejected = expectLater(pending, throwsStateError);
        await storage.entered!.future;
        expect(panel.selection, hasLength(3));
        expect(store.get('large')!.selectedCount, 3);
        panel.cancelCollectionRefresh();
        storage.release!.complete();
        await rejected;
        expect(panel.selection, hasLength(3));
        expect(store.get('large')!.selectedCount, 3);
        expect(storage.values, before);
      },
    );
  }
}

import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_view_configuration.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/workspace_configuration.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/toolbar_provider.dart';
import 'package:crisp_cloud/providers/workspace_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends CloudStorageClient {
  _Cloud(this.account);
  final String account;
  final paths = <String>[];
  bool includeHidden = false;
  bool authenticated = true;
  @override
  String get providerName => 'Workspace cloud';
  @override
  String get userId => account;
  @override
  String get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<void> logout() async {}
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    paths.add(path);
    return {
      'files': [
        {'name': '$account.txt', 'uuid': '$account:$path', 'size': 3},
        if (includeHidden) {'name': '.hidden', 'uuid': '$account:hidden:$path'},
      ],
      'folders': [
        if (path == '/') {'name': 'one'},
        if (path == '/') {'name': 'two'},
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
  bool isConnected = true;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => '${client.account}@example.test';
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
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late _Auth auth;
  late ProviderContainer container;
  late PanelNotifier panel;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud('account-a');
    auth = _Auth(cloud);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
  });
  tearDown(() => container.dispose());

  test(
    'every available visual layout survives a per-tab profile round-trip',
    () async {
      for (final mode in ViewMode.values.where(
        (mode) => mode != ViewMode.list,
      )) {
        final display = FileViewDisplay.values.byName(mode.name);
        await panel.applyViewConfiguration(
          FileViewConfiguration(display: display),
        );
        final saved = await panel.exportTabs();
        await panel.applyViewConfiguration(FileViewConfiguration());
        await panel.restoreTabs(saved, replace: true, keepProtected: false);
        expect(container.read(remoteViewModeProvider), mode);
        expect(panel.captureViewConfiguration().display, display);
      }
    },
  );

  test('remote hidden files follow the saved view configuration', () async {
    cloud.includeHidden = true;
    await panel.refresh();
    expect(panel.files!.any((file) => file.name == '.hidden'), isFalse);
    await panel.applyViewConfiguration(FileViewConfiguration(showHidden: true));
    expect(panel.files!.any((file) => file.name == '.hidden'), isTrue);
    await panel.applyViewConfiguration(FileViewConfiguration());
    expect(panel.files!.any((file) => file.name == '.hidden'), isFalse);
  });

  test(
    'restored file-list tabs keep their saved filter after collection refresh',
    () async {
      panel.showSearchResults([
        panel.files!.firstWhere((file) => !file.isFolder),
      ], origin: panel.captureCurrentOrigin());
      await panel.applyViewConfiguration(
        FileViewConfiguration(filter: 'account', display: FileViewDisplay.grid),
      );
      final saved = await panel.exportTabs();
      await panel.restoreTabs(saved, replace: true, keepProtected: false);
      expect(panel.showingSearchResults, isTrue);
      expect(panel.filterQuery, 'account');
      expect(panel.captureViewConfiguration().display, FileViewDisplay.grid);
    },
  );

  test(
    'workspace captures and restores both pane layouts and active views',
    () async {
      final left = container.read(panelProvider(PanelSide.local));
      await left.refresh();
      final controller = container.read(workspaceControllerProvider);
      await panel.navigateToPath('/one');
      await panel.applyViewConfiguration(
        FileViewConfiguration(display: FileViewDisplay.grid),
      );
      container.read(panelSplitRatioProvider.notifier).state = 0.63;
      final group = await controller.captureGroup('Saved work');
      await panel.navigateToPath('/two');
      await panel.applyViewConfiguration(FileViewConfiguration());
      container.read(panelSplitRatioProvider.notifier).state = 0.5;
      await controller.openGroup(group, replace: true, keepProtected: false);
      expect(panel.currentPath, '/one');
      expect(panel.captureViewConfiguration().display, FileViewDisplay.grid);
      expect(container.read(panelSplitRatioProvider), 0.63);
      expect(left.currentPath, group.left.tabs.single.path);
    },
  );

  test(
    'paired bookmarks preflight both accounts before changing either pane',
    () async {
      final left = container.read(panelProvider(PanelSide.local));
      await left.refresh();
      final originalLeft = left.currentPath;
      final originalRight = panel.currentPath;
      final account = panel.captureCurrentOrigin().storageReference;
      final pair = PairedBookmark(
        id: 'pair',
        name: 'Unavailable account',
        left: WorkspaceTabSnapshot.fromJson({
          'path': '/one',
          'storage': account.toJson(),
        }),
        right: WorkspaceTabSnapshot.fromJson({
          'path': '/two',
          'storage': const StorageReference(
            kind: 'remote',
            provider: 'Workspace cloud',
            accountKey: 'missing',
          ).toJson(),
        }),
      );
      await expectLater(
        container.read(workspaceControllerProvider).openPair(pair),
        throwsStateError,
      );
      expect(left.currentPath, originalLeft);
      expect(panel.currentPath, originalRight);
    },
  );

  test(
    'paired locations use captured account in either pane and preserve locks',
    () async {
      final left = container.read(panelProvider(PanelSide.local));
      await left.refresh();
      final account = panel.captureCurrentOrigin().storageReference;
      final pair = PairedBookmark(
        id: 'pair',
        name: 'Same account both sides',
        left: WorkspaceTabSnapshot.fromJson({
          'path': '/one',
          'storage': account.toJson(),
        }),
        right: WorkspaceTabSnapshot.fromJson({
          'path': '/two',
          'storage': account.toJson(),
        }),
      );
      final lockedId = panel.activeTabId;
      panel.setTabLock(lockedId, TabLockMode.locked);
      await container.read(workspaceControllerProvider).openPair(pair);
      expect(left.currentPath, '/one');
      expect(left.captureCurrentOrigin().storageId, account.id);
      expect(panel.currentPath, '/two');
      expect(panel.tabs.firstWhere((tab) => tab.id == lockedId).path, '/');
      expect(panel.activeTabId, isNot(lockedId));
    },
  );

  test(
    'tabs retain independent views, filters, columns and sort direction',
    () async {
      final first = panel.activeTabId;
      await panel.applyViewConfiguration(
        FileViewConfiguration(
          display: FileViewDisplay.grid,
          sortBy: SortBy.size,
          sortOrder: SortOrder.descending,
          filter: 'account',
          widths: {'size': 115, 'date': -78, 'ext': 40},
        ),
        profileId: 'reports',
      );
      panel.addTab(path: '/one');
      await panel.refresh();
      final second = panel.activeTabId;
      await panel.applyViewConfiguration(
        FileViewConfiguration(display: FileViewDisplay.brief),
      );
      await panel.selectTab(first);
      expect(panel.captureViewConfiguration().display, FileViewDisplay.grid);
      expect(panel.filterQuery, 'account');
      expect(panel.sortOrder, SortOrder.descending);
      expect(
        container.read(columnWidthsProvider(PanelSide.remote))['size'],
        115,
      );
      expect(panel.activeTab!.viewProfileId, 'reports');
      await panel.selectTab(second);
      expect(panel.captureViewConfiguration().display, FileViewDisplay.brief);
      expect(panel.filterQuery, '');
    },
  );

  test(
    'replacing tabs and closing active tabs never overwrites destination views',
    () async {
      await panel.applyViewConfiguration(
        FileViewConfiguration(display: FileViewDisplay.grid),
      );
      final saved = (await panel.exportTabs()).single;
      await panel.applyViewConfiguration(
        FileViewConfiguration(display: FileViewDisplay.brief),
      );
      await panel.restoreTabs([saved], replace: true, keepProtected: false);
      expect(panel.captureViewConfiguration().display, FileViewDisplay.grid);
      final first = panel.activeTabId;
      panel.addTab(path: '/one');
      await panel.refresh();
      await panel.applyViewConfiguration(
        FileViewConfiguration(display: FileViewDisplay.brief),
      );
      panel.closeTab(panel.activeTabId);
      await panel.refresh();
      expect(panel.activeTabId, first);
      expect(panel.captureViewConfiguration().display, FileViewDisplay.grid);
    },
  );

  test(
    'metadata profiles sort virtual result rows by supplied numeric values',
    () async {
      panel.showSearchResults([
        FileItem(
          name: 'ten',
          path: '/ten',
          isFolder: false,
          metadata: {'rating': 10},
        ),
        FileItem(
          name: 'two',
          path: '/two',
          isFolder: false,
          metadata: {'rating': 2},
        ),
      ], origin: panel.captureCurrentOrigin());
      const rating = FileColumnDefinition(
        id: 'rating',
        label: 'Rating',
        kind: FileColumnKind.metadata,
        metadataKey: 'rating',
      );
      await panel.applyViewConfiguration(
        FileViewConfiguration(
          columns: [rating],
          widths: {'rating': 80},
          sortColumnId: 'rating',
        ),
      );
      expect(panel.files!.map((file) => file.name), ['two', 'ten']);
      panel.setColumnSort('rating');
      expect(panel.files!.map((file) => file.name), ['ten', 'two']);
    },
  );

  test('custom titles survive folder navigation and serialization', () async {
    panel.renameTab(panel.activeTabId, 'My project');
    await panel.navigateToPath('/one');
    expect(panel.activeTab!.label, 'My project');
    expect(
      PanelTab.fromJson('restored', panel.activeTab!.toJson()).customLabel,
      'My project',
    );
    panel.renameTab(panel.activeTabId, '');
    expect(panel.activeTab!.label, 'one');
  });

  test(
    'locked locations reject folder navigation before clearing or listing',
    () async {
      final tab = panel.activeTabId;
      final original = List.of(panel.files!);
      panel.setTabLock(tab, TabLockMode.locked);
      await panel.navigateToPath('/one');
      expect(panel.activeTabId, tab);
      expect(panel.currentPath, '/');
      expect(panel.files, original);
      expect(cloud.paths, isNot(contains('/one')));
    },
  );

  test('new-tab lock preserves its original location and account', () async {
    final locked = panel.activeTab!;
    final storage = locked.storage;
    panel.setTabLock(locked.id, TabLockMode.newTab);
    await panel.navigateToPath('/one');
    expect(panel.tabs, hasLength(2));
    expect(locked.path, '/');
    expect(locked.storage, storage);
    expect(panel.activeTab!.path, '/one');
    expect(panel.activeTab!.isLocked, isFalse);
    panel.closeTab(locked.id);
    expect(panel.tabs, hasLength(2));
    panel.closeTab(locked.id, force: true);
    expect(panel.tabs, hasLength(1));
  });

  test(
    'return lock resets both on tab departure and when restored from JSON',
    () async {
      final home = panel.activeTab!;
      panel.setTabLock(home.id, TabLockMode.resetOnLeave);
      await panel.navigateToPath('/one');
      expect(home.path, '/one');
      expect(PanelTab.fromJson('reload', home.toJson()).path, '/');
      panel.addTab(path: '/two');
      await panel.refresh();
      expect(home.path, '/');
      await panel.selectTab(home.id);
      expect(panel.currentPath, '/');
      expect(panel.activeTab!.storage, storageReferenceForClient(cloud));
    },
  );

  test(
    'changing source cannot rebind a locked same-path tab to another account',
    () async {
      final locked = panel.activeTab!;
      final originalStorage = locked.storage;
      panel.setTabLock(locked.id, TabLockMode.locked);
      final second = _Cloud('account-b');
      container
          .read(multiCloudProvider)
          .addConnection(
            id: 'second',
            label: 'Second account',
            provider: CloudProvider.webdav,
            client: second,
          );
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(
            RemotePanelSource(
              providerName: second.providerName,
              client: second,
              path: '/',
            ),
          );
      await panel.refresh();
      expect(panel.tabs, hasLength(2));
      expect(locked.storage, originalStorage);
      expect(panel.activeTab!.storage, storageReferenceForClient(second));
      await panel.selectTab(locked.id);
      expect(panel.files!.any((item) => item.name == 'account-a.txt'), isTrue);
      expect(panel.activeTabId, locked.id);
    },
  );

  test(
    'duplicating an inactive tab uses that tab rather than the current folder',
    () async {
      await panel.navigateToPath('/one');
      final first = panel.activeTab!;
      panel.renameTab(first.id, 'Original');
      panel.setTabLock(first.id, TabLockMode.locked);
      panel.addTab(path: '/two');
      await panel.refresh();
      panel.duplicateTab(first.id);
      await panel.refresh();
      expect(panel.currentPath, '/one');
      expect(panel.activeTabId, isNot(first.id));
      expect(panel.activeTab!.customLabel, 'Original');
      expect(panel.activeTab!.isLocked, isFalse);
    },
  );

  test(
    'tab ordering preserves the active location and is saved in that order',
    () async {
      final first = panel.activeTabId;
      panel.addTab(path: '/one');
      await panel.refresh();
      final second = panel.activeTabId;
      panel.addTab(path: '/two');
      await panel.refresh();
      final third = panel.activeTabId;
      panel.reorderTabs(0, 3);
      expect(panel.tabs.map((tab) => tab.id), [second, third, first]);
      expect(panel.activeTabId, third);
      expect((await panel.exportTabs()).map((tab) => tab['path']), [
        '/one',
        '/two',
        '/',
      ]);
    },
  );

  test(
    'group replacement retains protected tabs unless explicitly requested',
    () async {
      final original = panel.activeTabId;
      panel.toggleTabPin(original);
      final saved = panel.activeTab!.toJson()
        ..['path'] = '/one'
        ..['pinned'] = false;
      await panel.restoreTabs([saved], replace: true);
      expect(panel.tabs, hasLength(2));
      expect(panel.tabs.first.id, original);
      expect(panel.currentPath, '/one');
      await panel.restoreTabs([saved], replace: true, keepProtected: false);
      expect(panel.tabs, hasLength(1));
      expect(panel.activeTabId, isNot(original));
    },
  );

  test('unavailable stored accounts remain offline instead of using the current account', () async {
    const otherStorage = StorageReference(
      kind: 'remote',
      provider: 'Workspace cloud',
      accountKey: 'not-connected',
    );
    final originalReads = cloud.paths.length;
    final saved = PanelTab(
      id: 'imported',
      path: '/one',
      storage: otherStorage,
    ).toJson();
    await panel.restoreTabs([saved], replace: true);
    expect(panel.activeTab!.storage, otherStorage);
    expect(panel.files, isEmpty);
    expect(cloud.paths.length, originalReads);
  });

  test(
    'invalid group locations are rejected before any open tab is removed',
    () async {
      final original = panel.activeTabId;
      final invalid = panel.activeTab!.toJson()..['path'] = '../wrong';
      await expectLater(
        panel.restoreTabs([invalid], replace: true, keepProtected: false),
        throwsFormatException,
      );
      expect(panel.activeTabId, original);
      expect(panel.tabs, hasLength(1));
    },
  );

  test('closing a nonexistent tab never closes the first tab', () async {
    panel.addTab(path: '/one');
    await panel.refresh();
    final ids = panel.tabs.map((tab) => tab.id).toList();
    panel.closeTab('missing');
    expect(panel.tabs.map((tab) => tab.id), ids);
  });

  test('duplicate cleanup keeps a protected source-scoped tab', () async {
    final first = panel.activeTabId;
    panel.setTabLock(first, TabLockMode.newTab);
    panel.duplicateTab(first);
    await panel.refresh();
    expect(panel.tabs, hasLength(2));
    expect(panel.closeDuplicateTabs(), 1);
    await panel.refresh();
    expect(panel.tabs.single.id, first);
    expect(panel.currentPath, '/');
  });

  test(
    'feeding results preserves a locked directory in its original tab',
    () async {
      final original = panel.activeTabId;
      final file = panel.files!.firstWhere((item) => !item.isFolder);
      final origin = panel.captureCurrentOrigin();
      panel.setTabLock(original, TabLockMode.locked);
      panel.showSearchResults([file], origin: origin, title: 'Found');
      expect(panel.tabs, hasLength(2));
      expect(panel.activeTabId, isNot(original));
      expect(panel.showingSearchResults, isTrue);
      await panel.selectTab(original);
      expect(panel.showingSearchResults, isFalse);
      expect(panel.currentPath, '/');
    },
  );

  test(
    'opening a result parent preserves the new-tab-locked file list',
    () async {
      await panel.navigateToPath('/one');
      final file = panel.files!.firstWhere((item) => !item.isFolder);
      panel.showSearchResults(
        [file],
        origin: panel.captureCurrentOrigin(),
        title: 'Found',
      );
      final resultsTab = panel.activeTabId;
      panel.setTabLock(resultsTab, TabLockMode.newTab);
      await panel.openContainingFolder(panel.files!.single);
      expect(panel.activeTabId, isNot(resultsTab));
      expect(panel.currentPath, '/one');
      expect(panel.showingSearchResults, isFalse);
      await panel.selectTab(resultsTab);
      expect(panel.showingSearchResults, isTrue);
      expect(panel.files!.single.path, '/one/account-a.txt');
    },
  );

  test(
    'saved tab groups retain virtual lists as source-bound collections',
    () async {
      final file = panel.files!.firstWhere((item) => !item.isFolder);
      panel.showSearchResults(
        [file],
        origin: panel.captureCurrentOrigin(),
        title: 'Found',
      );
      final saved = await panel.exportTabs();
      expect(saved.single['collectionId'], isNotNull);
      await panel.restoreTabs(saved, replace: true, keepProtected: false);
      expect(panel.showingSearchResults, isTrue);
      expect(panel.files!.single.path, '/account-a.txt');
      expect(panel.originForOperation(panel.files!.single), isNotNull);
    },
  );
}

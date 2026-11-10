import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/file_view_configuration.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/multi_cloud_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/recent_locations_provider.dart';
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
  bool authenticated = true;
  final paths = <String>[];
  final delays = <String, Completer<void>>{};
  final failures = <String>{};
  @override
  String get providerName => 'Navigation cloud';
  @override
  String get userId => account;
  @override
  String get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<void> logout() async { authenticated = false; }
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    paths.add(path);
    if (delays[path] case final delay?) await delay.future;
    if (failures.contains(path)) throw StateError('Folder unavailable');
    return {
      'files': [
        {'name': 'first.txt', 'uuid': '$account:$path:first', 'size': 3},
        {'name': 'second.txt', 'uuid': '$account:$path:second', 'size': 4},
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
  bool get isConnected => client.authenticated;
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
  late _Cloud accountA;
  late _Cloud accountB;
  late ProviderContainer container;
  late PanelNotifier panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    accountA = _Cloud('a');
    accountB = _Cloud('b');
    container = ProviderContainer(overrides: [
      authProvider.overrideWith((_) => _Auth(accountA)),
      localFileServiceProvider.overrideWithValue(_Local()),
    ]);
    container.read(multiCloudProvider).addConnection(
      id: 'secondary', label: 'Second account',
      provider: CloudProvider.s3, client: accountB,
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
  });
  tearDown(() => container.dispose());

  test('back and forward resolve identical paths against their exact accounts', () async {
    await panel.navigateToPath('/shared');
    final accountBOrigin = panel.resolveStorageReference(storageReferenceForClient(accountB), '/shared')!;
    await panel.navigateToPath('/shared', origin: accountBOrigin);
    expect(panel.captureCurrentOrigin().storageReference, storageReferenceForClient(accountB));
    await panel.navigateBack();
    expect(panel.currentPath, '/shared');
    expect(panel.captureCurrentOrigin().storageReference, storageReferenceForClient(accountA));
    expect(panel.files!.where((file) => !file.isFolder).every((file) => file.uuid!.startsWith('a:')), isTrue);
    await panel.navigateForward();
    expect(panel.captureCurrentOrigin().storageReference, storageReferenceForClient(accountB));
  });

  test('back restores local storage in a pane currently displaying a cloud', () async {
    final local = panel.captureLocalClipboardOrigin('/');
    await panel.navigateToPath('/', origin: local);
    await panel.navigateToPath('/shared', origin: panel.resolveStorageReference(storageReferenceForClient(accountB), '/shared'));
    await panel.navigateBack();
    expect(panel.captureCurrentOrigin().source, isA<LocalPanelSource>());
    expect(container.read(panelSourceProvider(PanelSide.remote)), isA<LocalPanelSource>());
    expect(panel.currentPath, '/');
  });

  test('history and forward position stay independent when switching tabs', () async {
    final first = panel.activeTabId;
    await panel.navigateToPath('/one');
    await panel.navigateToPath('/two');
    await panel.navigateBack();
    await panel.restoreTabs([{
      'path': '/other', 'storage': storageReferenceForClient(accountA).toJson(),
    }]);
    final second = panel.activeTabId;
    expect(panel.navigationHistory.map((entry) => entry.path), ['/other']);
    await panel.selectTab(first);
    expect(panel.currentPath, '/one');
    expect(panel.canNavigateForward, isTrue);
    await panel.navigateForward();
    expect(panel.currentPath, '/two');
    await panel.selectTab(second);
    expect(panel.currentPath, '/other');
    expect(panel.canNavigateBack, isFalse);
  });

  test('history navigation restores cursor using a fresh verified row', () async {
    final second = panel.files!.firstWhere((file) => file.name == 'second.txt');
    panel.setCursorOnly(second);
    await panel.navigateToPath('/one');
    await panel.navigateBack();
    expect(panel.cursorItem?.name, 'second.txt');
    expect(identical(panel.cursorItem, second), isFalse);
    expect(panel.originForOperation(panel.cursorItem!), isNotNull);
  });

  test('unavailable history retains its index and never uses a different account', () async {
    await panel.navigateToPath('/one');
    await panel.navigateToPath('/shared', origin: panel.resolveStorageReference(storageReferenceForClient(accountB), '/shared'));
    final index = panel.navigationHistoryIndex;
    final requests = accountB.paths.length;
    accountA.authenticated = false;
    await panel.navigateBack();
    expect(panel.navigationHistoryIndex, index);
    expect(panel.currentPath, '/shared');
    expect(accountB.paths.length, requests);
    expect(container.read(errorProvider).lastAppError!.code, PanelErrorCode.navigationUnavailable);
  });

  test('failed history listing does not advance its history position', () async {
    await panel.navigateToPath('/one');
    await panel.navigateToPath('/two');
    final index = panel.navigationHistoryIndex;
    accountA.failures.add('/one');
    await panel.navigateBack();
    expect(panel.navigationHistoryIndex, index);
    accountA.failures.clear();
    await panel.navigateBack();
    expect(panel.currentPath, '/one');
    expect(panel.navigationHistoryIndex, index - 1);
  });

  test('a late back result cannot change the tab selected while it loads', () async {
    final first = panel.activeTabId;
    await panel.navigateToPath('/one');
    await panel.navigateToPath('/two');
    await panel.restoreTabs([{
      'path': '/other', 'storage': storageReferenceForClient(accountA).toJson(),
    }]);
    final second = panel.activeTabId;
    await panel.selectTab(first);
    final delay = Completer<void>();
    accountA.delays['/one'] = delay;
    final back = panel.navigateBack();
    await panel.selectTab(second);
    delay.complete();
    await back;
    expect(panel.activeTabId, second);
    expect(panel.currentPath, '/other');
    final original = panel.tabs.firstWhere((tab) => tab.id == first);
    expect(original.navigation.current!.path, '/two');
  });

  test('recent destinations reopen exact accounts and refuse legacy unscoped paths', () async {
    await panel.navigateToPath('/one');
    final recent = container.read(recentLocationsProvider).entries.first;
    await panel.navigateToPath('/shared', origin: panel.resolveStorageReference(storageReferenceForClient(accountB), '/shared'));
    await panel.openRecentLocation(recent);
    expect(panel.captureCurrentOrigin().storageReference, storageReferenceForClient(accountA));
    final requests = accountA.paths.length;
    await panel.openRecentLocation(RecentEntry(path: '/legacy', side: PanelSide.remote, visitedAt: DateTime.utc(2026)));
    expect(accountA.paths.length, requests);
    expect(panel.currentPath, '/one');
    expect(container.read(errorProvider).lastAppError!.code, PanelErrorCode.navigationUnavailable);
  });

  test('closed tab recovery preserves name, view, source, placement and history', () async {
    final first = panel.activeTabId;
    await panel.restoreTabs([{
      'path': '/one', 'storage': storageReferenceForClient(accountB).toJson(),
    }]);
    await panel.navigateToPath('/two');
    panel.renameTab(panel.activeTabId, 'Working files');
    await panel.applyViewConfiguration(FileViewConfiguration(filter: '.txt', sortBy: SortBy.size));
    panel.closeTab(panel.activeTabId);
    await panel.selectTab(first);
    expect(panel.canReopenClosedTab, isTrue);
    await panel.reopenClosedTab();
    expect(panel.activeTab!.label, 'Working files');
    expect(panel.currentPath, '/two');
    expect(panel.captureCurrentOrigin().storageReference, storageReferenceForClient(accountB));
    expect(panel.filterQuery, '.txt');
    expect(panel.sortBy, SortBy.size);
    expect(panel.tabs.indexWhere((tab) => tab.id == panel.activeTabId), 1);
    expect(panel.canNavigateBack, isTrue);
    expect(panel.canReopenClosedTab, isFalse);
    await panel.navigateBack();
    expect(panel.currentPath, '/one');
  });

  test('closing a protected tab does not create a phantom recovery entry', () async {
    await panel.restoreTabs([{
      'path': '/one', 'storage': storageReferenceForClient(accountA).toJson(),
    }]);
    panel.toggleTabPin(panel.activeTabId);
    panel.closeTab(panel.activeTabId);
    expect(panel.canReopenClosedTab, isFalse);
    expect(panel.tabs, hasLength(2));
  });

  test('closed tab recovery metadata is saved with an exact source and bounded history', () async {
    final first = panel.activeTabId;
    await panel.restoreTabs([{
      'path': '/one', 'storage': storageReferenceForClient(accountB).toJson(),
    }]);
    await panel.navigateToPath('/two');
    panel.closeTab(panel.activeTabId);
    await panel.selectTab(first);
    await panel.exportTabs();
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('panel_tabs_remote_closed')!) as List;
    final restored = PanelTab.fromJson('recovered', Map<String, dynamic>.from(saved.single['tab'] as Map));
    expect(restored.path, '/two');
    expect(restored.storage, storageReferenceForClient(accountB));
    expect(restored.navigation.current!.path, '/two');
    expect(restored.navigation.entries.first.path, '/one');
  });

  test('reopening an offline tab never redirects its location into the current account', () async {
    final first = panel.activeTabId;
    await panel.restoreTabs([{
      'path': '/private', 'storage': storageReferenceForClient(accountB).toJson(),
    }]);
    panel.closeTab(panel.activeTabId);
    await panel.selectTab(first);
    accountB.authenticated = false;
    final count = accountA.paths.length;
    await panel.reopenClosedTab();
    expect(panel.activeTab!.storage, storageReferenceForClient(accountB));
    expect(panel.activeTab!.path, '/private');
    expect(accountA.paths.length, count);
    expect(panel.files, isEmpty);
    expect(container.read(errorProvider).lastError, contains('Reconnect'));
  });
}

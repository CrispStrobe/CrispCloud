// test/providers_test.dart
//
// Tests for the Riverpod providers that replaced the monolithic AppState.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

class _TestLocalFileService implements LocalFileService {
  @override
  String currentPath = Directory.systemTemp.path;
  @override
  String? get grantedBasePath => Directory.systemTemp.path;

  @override
  Future<bool> ensureAccess(String path) async => true;

  @override
  Future<bool> beginStreamAccess(String path) async => true;

  @override
  Future<void> endStreamAccess() async {}

  @override
  Future<int?> fileLength(String path) async => 0;

  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async =>
      currentPath;
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

// Publish rows through the panel API and retain the displayed objects. The
// panel deliberately copies input rows and only accepts its current objects
// for selection; detached or stale same-path objects are not valid clicks.
List<FileItem> _publishSelectionRows(PanelNotifier panel, List<String> names) {
  panel.showSearchResults([
    for (final name in names)
      FileItem(name: name, isFolder: false, path: '/selection-fixture/$name'),
  ]);
  return panel.files!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late InMemorySecureStorage secureStorage;
  late FilenConfigService configService;
  late TransferJournal journal;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    journal = TransferJournal(MemoryTransferJournalStorage());
    configService = FilenConfigService(
      configPath: '/tmp/providers_test_config',
      secureStorage: secureStorage,
    );
    container = ProviderContainer(
      overrides: [
        transferJournalProvider.overrideWithValue(journal),
        secureStorageProvider.overrideWithValue(secureStorage),
        configPathProvider.overrideWithValue('/tmp/providers_test_config'),
        localFileServiceProvider.overrideWithValue(_TestLocalFileService()),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            initialProvider: CloudProvider.filen,
            config: configService,
            configPath: '/tmp/providers_test_config',
            secureStorage: secureStorage,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  // --- Error Provider ---
  group('ErrorNotifier', () {
    test('starts with no errors', () {
      final errors = container.read(errorProvider);
      expect(errors.hasErrors, isFalse);
      expect(errors.lastError, isNull);
      expect(errors.errors, isEmpty);
    });

    test('addError adds an error', () {
      final errors = container.read(errorProvider);
      errors.addError('test error');
      expect(errors.hasErrors, isTrue);
      expect(errors.lastError, equals('test error'));
      expect(errors.errors.length, equals(1));
    });

    test('clearErrors clears all errors', () {
      final errors = container.read(errorProvider);
      errors.addError('err1');
      errors.addError('err2');
      errors.clearErrors();
      expect(errors.hasErrors, isFalse);
      expect(errors.errors, isEmpty);
    });

    test('clearLastError removes only the last error', () {
      final errors = container.read(errorProvider);
      errors.addError('err1');
      errors.addError('err2');
      errors.clearLastError();
      expect(errors.errors.length, equals(1));
      expect(errors.lastError, equals('err1'));
    });

    test('clearLastError does not throw when no errors', () {
      final errors = container.read(errorProvider);
      errors.clearLastError();
      expect(errors.hasErrors, isFalse);
    });
  });

  // --- Settings Providers ---
  group('Settings providers', () {
    test('activePanelProvider defaults to local', () {
      expect(container.read(activePanelProvider), equals(PanelSide.local));
    });

    test('activePanelProvider can be set to remote', () {
      container.read(activePanelProvider.notifier).state = PanelSide.remote;
      expect(container.read(activePanelProvider), equals(PanelSide.remote));
    });

    test('showPreviewProvider defaults to false', () {
      expect(container.read(showPreviewProvider), isFalse);
    });

    test('showPreviewProvider can be toggled', () {
      container.read(showPreviewProvider.notifier).state = true;
      expect(container.read(showPreviewProvider), isTrue);
    });
  });

  // --- Auth Provider ---
  group('AuthNotifier', () {
    test('is not connected initially', () {
      final auth = container.read(authProvider);
      expect(auth.isConnected, isFalse);
    });

    test('userEmail is null initially', () {
      final auth = container.read(authProvider);
      expect(auth.userEmail, isNull);
    });

    test('defaults to filen provider', () {
      final auth = container.read(authProvider);
      expect(auth.currentProvider, equals(CloudProvider.filen));
    });

    test('providerName returns Filen for default provider', () {
      final auth = container.read(authProvider);
      expect(auth.providerName, equals('Filen'));
    });

    test('client accessor returns a CloudStorageClient', () {
      final auth = container.read(authProvider);
      expect(auth.client, isNotNull);
    });

    test('isEncryptionEnabled is false initially', () {
      final auth = container.read(authProvider);
      expect(auth.isEncryptionEnabled, isFalse);
    });
  });

  // --- Panel Provider ---
  group('PanelNotifier (local)', () {
    test('local panel starts with empty or null files', () {
      final panel = container.read(panelProvider(PanelSide.local));
      // Files are loaded asynchronously, may be null initially
      expect(panel.files == null || panel.files is List<FileItem>, isTrue);
    });

    test('selection starts empty', () {
      final panel = container.read(panelProvider(PanelSide.local));
      expect(panel.selection, isEmpty);
    });

    test('toggleSelection adds item to selection', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'test.txt', isFolder: false);
      panel.showSearchResults([item]);
      item = panel.files!.single;
      panel.toggleSelection(item);
      expect(panel.selection.contains(item), isTrue);
    });

    test('toggleSelection replaces previous without modifier', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item1 = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      var item2 = FileItem(name: 'b.txt', isFolder: false, path: '/b.txt');
      panel.showSearchResults([item1, item2]);
      item1 = panel.files![0];
      item2 = panel.files![1];
      panel.toggleSelection(item1);
      expect(panel.selection.single, same(item1));
      panel.toggleSelection(item2);
      expect(panel.selection.length, equals(1));
      expect(panel.selection.single, same(item2));
    });

    test('toggleSelection with ctrlKey adds to selection', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item1 = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      var item2 = FileItem(name: 'b.txt', isFolder: false, path: '/b.txt');
      panel.showSearchResults([item1, item2]);
      item1 = panel.files![0];
      item2 = panel.files![1];
      panel.toggleSelection(item1);
      panel.toggleSelection(item2, ctrlKey: true);
      expect(panel.selection, unorderedEquals([item1, item2]));
    });

    test('toggleSelection with ctrlKey removes already-selected', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      panel.showSearchResults([item]);
      item = panel.files!.single;
      panel.toggleSelection(item);
      expect(panel.selection.single, same(item));
      panel.toggleSelection(item, ctrlKey: true);
      expect(panel.selection.contains(item), isFalse);
    });

    test('clearSelection empties selection', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'test.txt', isFolder: false);
      panel.showSearchResults([item]);
      item = panel.files!.single;
      panel.toggleSelection(item);
      expect(panel.selection.single, same(item));
      panel.clearSelection();
      expect(panel.selection, isEmpty);
    });

    test('isSelected returns true for selected item', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'test.txt', isFolder: false);
      panel.showSearchResults([item]);
      item = panel.files!.single;
      panel.toggleSelection(item);
      expect(panel.isSelected(item), isTrue);
    });

    test('isSelected returns false for unselected item', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'test.txt', isFolder: false);
      expect(panel.isSelected(item), isFalse);
    });

    test('toggleSelection rejects detached and stale same-path rows', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final old = _publishSelectionRows(panel, ['test.txt']).single;
      panel.toggleSelection(old.copyWith());
      expect(panel.selection, isEmpty);
      panel.toggleSelection(old);
      expect(panel.selection.single, same(old));

      final current = _publishSelectionRows(panel, ['test.txt']).single;
      expect(identical(current, old), isFalse);
      panel.toggleSelection(old);
      expect(panel.selection, isEmpty);
      panel.toggleSelection(current);
      expect(panel.selection.single, same(current));
      panel.toggleSelection(old, ctrlKey: true);
      expect(panel.selection.single, same(current));
    });

    test('sort defaults to name ascending', () {
      final panel = container.read(panelProvider(PanelSide.local));
      expect(panel.sortBy, equals(SortBy.name));
      expect(panel.sortOrder, equals(SortOrder.ascending));
    });

    test('setSortBy changes sort field', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.setSortBy(SortBy.size);
      expect(panel.sortBy, equals(SortBy.size));
    });

    test('toggleSortOrder flips ascending to descending', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.toggleSortOrder();
      expect(panel.sortOrder, equals(SortOrder.descending));
    });

    test('toggleSortOrder twice returns to ascending', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.toggleSortOrder();
      panel.toggleSortOrder();
      expect(panel.sortOrder, equals(SortOrder.ascending));
    });

    test('itemToScrollTo is null initially', () {
      final panel = container.read(panelProvider(PanelSide.local));
      expect(panel.itemToScrollTo, isNull);
    });

    test('clearItemToScrollTo sets it to null', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.clearItemToScrollTo();
      expect(panel.itemToScrollTo, isNull);
    });
  });

  group('PanelNotifier (remote)', () {
    test('remote panel starts with null files', () {
      final panel = container.read(panelProvider(PanelSide.remote));
      expect(panel.files, isNull);
    });

    test('remote currentPath defaults to /', () {
      final panel = container.read(panelProvider(PanelSide.remote));
      expect(panel.currentPath, equals('/'));
    });

    test('selection is independent per panel', () {
      final local = container.read(panelProvider(PanelSide.local));
      final remote = container.read(panelProvider(PanelSide.remote));
      var item = FileItem(name: 'test.txt', isFolder: false);
      local.showSearchResults([item]);
      item = local.files!.single;
      local.toggleSelection(item);
      expect(local.selection.contains(item), isTrue);
      expect(remote.selection.contains(item), isFalse);
    });

    test('sort is independent per panel', () {
      final local = container.read(panelProvider(PanelSide.local));
      final remote = container.read(panelProvider(PanelSide.remote));
      local.setSortBy(SortBy.extension);
      expect(remote.sortBy, equals(SortBy.name));
    });
  });

  // --- Tabs ---
  // Note: PanelNotifier._restoreTabs() is async (reads SharedPreferences),
  // so we must await a microtask flush before checking tab state.
  group('PanelNotifier tabs', () {
    test('starts with one tab', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(Duration.zero); // flush async _restoreTabs
      expect(panel.tabs.length, equals(1));
    });

    test('addTab adds a tab and activates it', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(Duration.zero);
      final originalTabId = panel.activeTabId;
      panel.addTab();
      expect(panel.tabs.length, equals(2));
      expect(panel.activeTabId, isNot(equals(originalTabId)));
    });

    test('closeTab removes non-pinned tab', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(Duration.zero);
      panel.addTab();
      expect(panel.tabs.length, equals(2));
      final newTabId = panel.activeTabId;
      panel.closeTab(newTabId);
      expect(panel.tabs.length, equals(1));
    });

    test('closeTab does not remove last tab', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(Duration.zero);
      final tabId = panel.activeTabId;
      panel.closeTab(tabId);
      expect(panel.tabs.length, equals(1));
    });

    test('toggleTabPin toggles pin state', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(Duration.zero);
      final tabId = panel.activeTabId;
      expect(panel.activeTab!.isPinned, isFalse);
      panel.toggleTabPin(tabId);
      expect(panel.activeTab!.isPinned, isTrue);
    });

    test('renameTab sets custom label', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(Duration.zero);
      final tabId = panel.activeTabId;
      panel.renameTab(tabId, 'MyCustomLabel');
      expect(panel.activeTab!.label, 'MyCustomLabel');
    });
  });

  // --- DC Parity: Navigation History ---
  group('PanelNotifier navigation history', () {
    test('canNavigateBack is false initially', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(const Duration(milliseconds: 100));
      // After initial load, history has 1 entry — can't go back
      expect(panel.canNavigateBack, isFalse);
    });

    test('canNavigateForward is false initially', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(const Duration(milliseconds: 100));
      expect(panel.canNavigateForward, isFalse);
    });

    test('navigateBack does not throw when no history', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(const Duration(milliseconds: 100));
      await panel.navigateBack(); // Should silently do nothing
    });

    test('navigateForward does not throw when no forward history', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future.delayed(const Duration(milliseconds: 100));
      await panel.navigateForward();
    });
  });

  // --- DC Parity: In-place Rename ---
  group('PanelNotifier in-place rename', () {
    test('startRename sets renamingItem', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'test.txt', isFolder: false);
      panel.startRename(item);
      expect(panel.renamingItem, item);
    });

    test('cancelRename clears renamingItem', () {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'test.txt', isFolder: false);
      panel.startRename(item);
      panel.cancelRename();
      expect(panel.renamingItem, isNull);
    });

    test('startRename ignores .. entry', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final dotDot = FileItem(name: '..', isFolder: true);
      panel.startRename(dotDot);
      expect(panel.renamingItem, isNull);
    });

    test('commitRename with empty name cancels silently', () async {
      final panel = container.read(panelProvider(PanelSide.local));
      var item = FileItem(name: 'test.txt', isFolder: false);
      panel.startRename(item);
      await panel.commitRename(''); // Should clear without rename
      expect(panel.renamingItem, isNull);
    });
  });

  // --- DC Parity: Type-ahead Search ---
  group('PanelNotifier type-ahead', () {
    test('isTypeahead is false initially', () {
      final panel = container.read(panelProvider(PanelSide.local));
      expect(panel.isTypeahead, isFalse);
    });

    test('typeaheadAppend sets isTypeahead and filterQuery', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.typeaheadAppend('a');
      expect(panel.isTypeahead, isTrue);
      expect(panel.filterQuery, 'a');
    });

    test('typeaheadAppend accumulates chars', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.typeaheadAppend('a');
      panel.typeaheadAppend('b');
      panel.typeaheadAppend('c');
      expect(panel.filterQuery, 'abc');
    });

    test('typeaheadBackspace removes last char', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.typeaheadAppend('a');
      panel.typeaheadAppend('b');
      panel.typeaheadBackspace();
      expect(panel.filterQuery, 'a');
    });

    test('typeaheadBackspace on empty string does nothing', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.typeaheadBackspace(); // Should not throw
      expect(panel.filterQuery, '');
    });

    test('clearTypeahead clears filter and isTypeahead', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.typeaheadAppend('ab');
      panel.clearTypeahead();
      expect(panel.filterQuery, '');
      expect(panel.isTypeahead, isFalse);
    });
  });

  // --- Quick search / quick filter modes ---
  group('PanelNotifier quick search modes', () {
    late PanelNotifier panel;

    setUp(() async {
      panel = container.read(panelProvider(PanelSide.local));
      // Let the provider finish its initial directory load before replacing
      // the listing with the fixed fixture.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      panel.showSearchResults([
        FileItem(name: 'alpha.txt', isFolder: false),
        FileItem(name: 'alphabet.txt', isFolder: false),
        FileItem(name: 'beta.txt', isFolder: false),
        FileItem(name: 'gamma.txt', isFolder: false),
      ]);
      panel.moveCursorTo(0);
      expect(panel.cursorItem?.name, 'alpha.txt');
    });

    test('jump mode moves the cursor without filtering', () {
      container
          .read(quickSearchSettingsProvider.notifier)
          .setMode(QuickSearchMode.jump);
      panel.typeaheadAppend('b');

      expect(panel.isTypeahead, isTrue);
      expect(panel.typeaheadMode, QuickSearchMode.jump);
      expect(panel.filteredFiles!.length, 4);
      expect(panel.cursorItem!.name, 'beta.txt');
    });

    test('jump mode keeps the current entry while refining', () {
      container
          .read(quickSearchSettingsProvider.notifier)
          .setMode(QuickSearchMode.jump);
      panel.typeaheadAppend('b');
      panel.typeaheadAppend('e');
      expect(panel.cursorItem!.name, 'beta.txt');
    });

    test('select mode marks every matching entry', () {
      // Give the fixture unique paths so FileItem equality distinguishes them.
      panel.showSearchResults([
        FileItem(name: 'alpha.txt', path: '/alpha.txt', isFolder: false),
        FileItem(name: 'alphabet.txt', path: '/alphabet.txt', isFolder: false),
        FileItem(name: 'beta.txt', path: '/beta.txt', isFolder: false),
        FileItem(name: 'gamma.txt', path: '/gamma.txt', isFolder: false),
      ]);
      panel.moveCursorTo(0);
      container
          .read(quickSearchSettingsProvider.notifier)
          .setMode(QuickSearchMode.select);
      panel.typeaheadAppend('al');

      expect(panel.filteredFiles!.length, 4);
      expect(panel.cursorItem!.name, 'alpha.txt');
      expect(panel.selection.map((f) => f.name).toSet(), {
        'alpha.txt',
        'alphabet.txt',
      });
    });

    test('filter mode narrows the listing', () {
      container
          .read(quickSearchSettingsProvider.notifier)
          .setMode(QuickSearchMode.filter);
      panel.typeaheadAppend('a');

      expect(panel.isQuickFilterActive, isTrue);
      expect(panel.filteredFiles!.map((f) => f.name).toList(), [
        'alpha.txt',
        'alphabet.txt',
      ]);
      expect(panel.cursorItem!.name, 'alpha.txt');
    });

    test('arrow cycling visits all matches and wraps', () {
      container
          .read(quickSearchSettingsProvider.notifier)
          .setMode(QuickSearchMode.jump);
      panel.typeaheadAppend('a');
      expect(panel.cursorItem!.name, 'alphabet.txt');

      expect(panel.cycleTypeahead(1), isTrue);
      expect(panel.cursorItem!.name, 'alpha.txt');
      expect(panel.cycleTypeahead(-1), isTrue);
      expect(panel.cursorItem!.name, 'alphabet.txt');
    });

    test('arrow movement stays inside the filtered list', () {
      container
          .read(quickSearchSettingsProvider.notifier)
          .setMode(QuickSearchMode.filter);
      panel.typeaheadAppend('a');
      expect(panel.cursorItem!.name, 'alpha.txt');

      panel.moveCursor(1);
      expect(panel.cursorItem!.name, 'alphabet.txt');
      panel.moveCursor(1);
      expect(panel.cursorItem!.name, 'alphabet.txt');
    });

    test('substring matching is honoured', () {
      final notifier = container.read(quickSearchSettingsProvider.notifier);
      notifier.setMode(QuickSearchMode.filter);
      notifier.setMatchFromStart(false);
      panel.typeaheadAppend('ph');

      expect(panel.filteredFiles!.map((f) => f.name).toList(), [
        'alpha.txt',
        'alphabet.txt',
      ]);
    });

    test('case-sensitive matching is honoured', () {
      final notifier = container.read(quickSearchSettingsProvider.notifier);
      notifier.setMode(QuickSearchMode.filter);
      notifier.setCaseSensitive(true);
      panel.typeaheadAppend('A');
      expect(panel.filteredFiles!, isEmpty);

      panel.clearTypeahead();
      notifier.setCaseSensitive(false);
      panel.typeaheadAppend('A');
      expect(panel.filteredFiles!.length, 2);
    });

    test('off mode ignores typed characters', () {
      container
          .read(quickSearchSettingsProvider.notifier)
          .setMode(QuickSearchMode.off);
      panel.typeaheadAppend('a');

      expect(panel.isTypeahead, isFalse);
      expect(panel.filterQuery, '');
    });

    test('plain click moves the cursor without selecting', () {
      final second = panel.files![1];
      panel.setCursorOnly(second);

      expect(panel.cursorItem!.name, second.name);
      expect(panel.selection, isEmpty);
    });

    test('setFilter moves the cursor to a visible entry', () {
      panel.setFilter('beta');

      expect(panel.filteredFiles!.map((f) => f.name), ['beta.txt']);
      expect(panel.cursorItem!.name, 'beta.txt');
      expect(panel.isTypeahead, isFalse);
    });
  });

  // --- DC Parity: Checksum Service ---

  // --- Transfer Provider ---
  group('TransferNotifier', () {
    test('operations starts empty', () {
      final transfers = container.read(transferProvider);
      expect(transfers.operations, isEmpty);
    });

    test('hasActiveOperations is false initially', () {
      final transfers = container.read(transferProvider);
      expect(transfers.hasActiveOperations, isFalse);
    });

    test('clearCompletedOperations does not throw when empty', () {
      final transfers = container.read(transferProvider);
      transfers.clearCompletedOperations();
      expect(transfers.operations, isEmpty);
    });

    test(
      'clearCompletedOperations removes failed and cancelled transfers',
      () async {
        final backend = LocalOperationBackend(
          _TestLocalFileService(),
          isCurrent: () => true,
        );
        final plan = FileOperationPlan(
          source: backend,
          destination: backend,
          targetDirectory: '/target',
          options: const FileOperationOptions(),
          entries: [],
          errors: [],
        );
        await journal.create('failed', plan);
        await journal.setStatus('failed', TransferJobStatus.failed);
        await journal.create('cancelled', plan);
        await journal.setStatus('cancelled', TransferJobStatus.cancelled);
        final transfers = container.read(transferProvider);
        await transfers.ready;
        expect(transfers.operations, hasLength(2));
        transfers.clearCompletedOperations();
        expect(transfers.operations, isEmpty);
        // Clearing visible outcomes must retain the durable recovery records.
        expect(journal.jobs, hasLength(2));
      },
    );

    test('removeOperation does not throw for non-existent id', () {
      final transfers = container.read(transferProvider);
      transfers.removeOperation('non-existent-id');
      expect(transfers.operations, isEmpty);
    });
  });

  // --- Search Provider ---
  group('SearchNotifier', () {
    test('isSearching is false initially', () {
      final search = container.read(searchProvider);
      expect(search.isSearching, isFalse);
    });
  });
}

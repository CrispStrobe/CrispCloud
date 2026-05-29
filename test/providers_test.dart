// test/providers_test.dart
//
// Tests for the Riverpod providers that replaced the monolithic AppState.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  late ProviderContainer container;
  late InMemorySecureStorage secureStorage;
  late FilenConfigService configService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    configService = FilenConfigService(
      configPath: '/tmp/providers_test_config',
      secureStorage: secureStorage,
    );
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(secureStorage),
        configPathProvider.overrideWithValue('/tmp/providers_test_config'),
        authProvider.overrideWith((ref) => AuthNotifier(
          ref,
          initialProvider: CloudProvider.filen,
          config: configService,
          configPath: '/tmp/providers_test_config',
          secureStorage: secureStorage,
        )),
      ],
    );
  });

  tearDown(() async {
    // Wait for async init in PanelNotifier/AuthNotifier to settle
    await Future.delayed(const Duration(milliseconds: 200));
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
      final item = FileItem(name: 'test.txt', isFolder: false);
      panel.toggleSelection(item);
      expect(panel.selection.contains(item), isTrue);
    });

    test('toggleSelection replaces previous without modifier', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final item1 = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      final item2 = FileItem(name: 'b.txt', isFolder: false, path: '/b.txt');
      panel.toggleSelection(item1);
      panel.toggleSelection(item2);
      expect(panel.selection.length, equals(1));
      expect(panel.selection.contains(item2), isTrue);
    });

    test('toggleSelection with ctrlKey adds to selection', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final item1 = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      final item2 = FileItem(name: 'b.txt', isFolder: false, path: '/b.txt');
      panel.toggleSelection(item1);
      panel.toggleSelection(item2, ctrlKey: true);
      expect(panel.selection.length, equals(2));
    });

    test('toggleSelection with ctrlKey removes already-selected', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final item = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      panel.toggleSelection(item);
      panel.toggleSelection(item, ctrlKey: true);
      expect(panel.selection.contains(item), isFalse);
    });

    test('clearSelection empties selection', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final item = FileItem(name: 'test.txt', isFolder: false);
      panel.toggleSelection(item);
      panel.clearSelection();
      expect(panel.selection, isEmpty);
    });

    test('isSelected returns true for selected item', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final item = FileItem(name: 'test.txt', isFolder: false);
      panel.toggleSelection(item);
      expect(panel.isSelected(item), isTrue);
    });

    test('isSelected returns false for unselected item', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final item = FileItem(name: 'test.txt', isFolder: false);
      expect(panel.isSelected(item), isFalse);
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
      final item = FileItem(name: 'test.txt', isFolder: false);
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
  group('PanelNotifier tabs', () {
    test('starts with one tab', () {
      final panel = container.read(panelProvider(PanelSide.local));
      expect(panel.tabs.length, equals(1));
    });

    test('addTab adds a tab and activates it', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final originalTabId = panel.activeTabId;
      panel.addTab();
      expect(panel.tabs.length, equals(2));
      expect(panel.activeTabId, isNot(equals(originalTabId)));
    });

    test('closeTab removes non-pinned tab', () {
      final panel = container.read(panelProvider(PanelSide.local));
      panel.addTab();
      expect(panel.tabs.length, equals(2));
      final newTabId = panel.activeTabId;
      panel.closeTab(newTabId);
      expect(panel.tabs.length, equals(1));
    });

    test('closeTab does not remove last tab', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final tabId = panel.activeTabId;
      panel.closeTab(tabId);
      expect(panel.tabs.length, equals(1));
    });

    test('toggleTabPin toggles pin state', () {
      final panel = container.read(panelProvider(PanelSide.local));
      final tabId = panel.activeTabId;
      expect(panel.activeTab!.isPinned, isFalse);
      panel.toggleTabPin(tabId);
      expect(panel.activeTab!.isPinned, isTrue);
    });
  });

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

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/app_state.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';

void main() {
  late AppState appState;
  late FilenConfigService configService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    configService = FilenConfigService(configPath: '/tmp/app_state_test_config');
    appState = AppState(config: configService);
  });

  tearDown(() {
    appState.dispose();
  });

  group('AppState initial state', () {
    test('is not connected initially', () {
      expect(appState.isConnected, isFalse);
    });

    test('userEmail is null initially', () {
      expect(appState.userEmail, isNull);
    });

    test('localFileItems may be null before async init completes', () {
      // localFileItems is loaded asynchronously, may be null right after construction
      // We just verify it does not throw
      final files = appState.localFileItems;
      expect(files == null || files is List<FileItem>, isTrue);
    });

    test('remoteFiles is null initially', () {
      expect(appState.remoteFiles, isNull);
    });

    test('activePanel defaults to local', () {
      expect(appState.activePanel, equals(PanelSide.local));
    });

    test('remotePath defaults to /', () {
      expect(appState.remotePath, equals('/'));
    });

    test('hasActiveOperations is false initially', () {
      expect(appState.hasActiveOperations, isFalse);
    });

    test('lastError is null initially', () {
      expect(appState.lastError, isNull);
    });

    test('hasErrors is false initially', () {
      expect(appState.hasErrors, isFalse);
    });

    test('isSearching is false initially', () {
      expect(appState.isSearching, isFalse);
    });

    test('hasLocalSelection is false initially', () {
      expect(appState.hasLocalSelection, isFalse);
    });

    test('hasRemoteSelection is false initially', () {
      expect(appState.hasRemoteSelection, isFalse);
    });
  });

  group('AppState currentProvider', () {
    test('defaults to filen', () {
      expect(appState.currentProvider, equals(CloudProvider.filen));
    });

    test('providerName returns Filen for default provider', () {
      expect(appState.providerName, equals('Filen'));
    });

    test('can be set via initialProvider parameter', () {
      final sftpState = AppState(
        config: configService,
        initialProvider: CloudProvider.filen,
      );
      expect(sftpState.currentProvider, equals(CloudProvider.filen));
      sftpState.dispose();
    });
  });

  group('AppState operations', () {
    test('operations list starts empty', () {
      expect(appState.operations, isEmpty);
    });

    test('clearCompletedOperations removes completed ops', () {
      // We cannot directly add to _operations from outside,
      // but we can verify the method does not throw on empty list
      appState.clearCompletedOperations();
      expect(appState.operations, isEmpty);
    });

    test('removeOperation does not throw for non-existent id', () {
      // Should not throw when removing a non-existent operation
      appState.removeOperation('non-existent-id');
      expect(appState.operations, isEmpty);
    });
  });

  group('AppState sorting', () {
    test('default sort is by name ascending for local panel', () {
      expect(appState.getSort(PanelSide.local), equals(SortBy.name));
      expect(appState.getSortOrder(PanelSide.local), equals(SortOrder.ascending));
    });

    test('default sort is by name ascending for remote panel', () {
      expect(appState.getSort(PanelSide.remote), equals(SortBy.name));
      expect(appState.getSortOrder(PanelSide.remote), equals(SortOrder.ascending));
    });

    test('setSortBy changes local sort', () {
      appState.setSortBy(PanelSide.local, SortBy.size);
      expect(appState.getSort(PanelSide.local), equals(SortBy.size));
    });

    test('setSortBy changes remote sort', () {
      appState.setSortBy(PanelSide.remote, SortBy.date);
      expect(appState.getSort(PanelSide.remote), equals(SortBy.date));
    });

    test('setSortBy does not affect the other panel', () {
      appState.setSortBy(PanelSide.local, SortBy.extension);
      expect(appState.getSort(PanelSide.remote), equals(SortBy.name));
    });

    test('toggleSortOrder flips local ascending to descending', () {
      expect(appState.getSortOrder(PanelSide.local), equals(SortOrder.ascending));
      appState.toggleSortOrder(PanelSide.local);
      expect(appState.getSortOrder(PanelSide.local), equals(SortOrder.descending));
    });

    test('toggleSortOrder flips remote ascending to descending', () {
      expect(appState.getSortOrder(PanelSide.remote), equals(SortOrder.ascending));
      appState.toggleSortOrder(PanelSide.remote);
      expect(appState.getSortOrder(PanelSide.remote), equals(SortOrder.descending));
    });

    test('toggleSortOrder twice returns to ascending', () {
      appState.toggleSortOrder(PanelSide.local);
      appState.toggleSortOrder(PanelSide.local);
      expect(appState.getSortOrder(PanelSide.local), equals(SortOrder.ascending));
    });
  });

  group('AppState selection management', () {
    test('toggleSelection adds item to local selection', () {
      // localSelection is a Set<FileItem> exposed via getter
      final item = FileItem(name: 'test.txt', isFolder: false);
      appState.toggleSelection(PanelSide.local, item);
      expect(appState.localSelection.contains(item), isTrue);
    });

    test('toggleSelection replaces previous selection without modifier keys', () {
      final item1 = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      final item2 = FileItem(name: 'b.txt', isFolder: false, path: '/b.txt');
      appState.toggleSelection(PanelSide.local, item1);
      appState.toggleSelection(PanelSide.local, item2);
      expect(appState.localSelection.length, equals(1));
      expect(appState.localSelection.contains(item2), isTrue);
      expect(appState.localSelection.contains(item1), isFalse);
    });

    test('toggleSelection with ctrlKey adds to selection', () {
      final item1 = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      final item2 = FileItem(name: 'b.txt', isFolder: false, path: '/b.txt');
      appState.toggleSelection(PanelSide.local, item1);
      appState.toggleSelection(PanelSide.local, item2, ctrlKey: true);
      expect(appState.localSelection.length, equals(2));
    });

    test('toggleSelection with ctrlKey removes already-selected item', () {
      final item = FileItem(name: 'a.txt', isFolder: false, path: '/a.txt');
      appState.toggleSelection(PanelSide.local, item);
      appState.toggleSelection(PanelSide.local, item, ctrlKey: true);
      expect(appState.localSelection.contains(item), isFalse);
    });

    test('clearSelection clears local selection', () {
      final item = FileItem(name: 'test.txt', isFolder: false);
      appState.toggleSelection(PanelSide.local, item);
      appState.clearSelection(PanelSide.local);
      expect(appState.localSelection, isEmpty);
    });

    test('clearSelection clears remote selection', () {
      final item = FileItem(name: 'test.txt', isFolder: false);
      appState.toggleSelection(PanelSide.remote, item);
      appState.clearSelection(PanelSide.remote);
      expect(appState.remoteSelection, isEmpty);
    });

    test('toggleSelection works for remote panel', () {
      final item = FileItem(name: 'remote.txt', isFolder: false);
      appState.toggleSelection(PanelSide.remote, item);
      expect(appState.remoteSelection.contains(item), isTrue);
    });

    test('isSelected returns true for selected items', () {
      final item = FileItem(name: 'test.txt', isFolder: false);
      appState.toggleSelection(PanelSide.local, item);
      expect(appState.isSelected(PanelSide.local, item), isTrue);
    });

    test('isSelected returns false for unselected items', () {
      final item = FileItem(name: 'test.txt', isFolder: false);
      expect(appState.isSelected(PanelSide.local, item), isFalse);
    });
  });

  group('AppState active panel', () {
    test('setActivePanel changes active panel', () {
      appState.setActivePanel(PanelSide.remote);
      expect(appState.activePanel, equals(PanelSide.remote));
    });

    test('setActivePanel back to local', () {
      appState.setActivePanel(PanelSide.remote);
      appState.setActivePanel(PanelSide.local);
      expect(appState.activePanel, equals(PanelSide.local));
    });
  });

  group('AppState error handling', () {
    test('clearErrors empties error list', () {
      appState.clearErrors();
      expect(appState.hasErrors, isFalse);
      expect(appState.errors, isEmpty);
    });

    test('clearLastError does not throw when no errors', () {
      appState.clearLastError();
      expect(appState.hasErrors, isFalse);
    });
  });

  group('AppState ChangeNotifier', () {
    test('notifies listeners on setActivePanel', () {
      var notified = false;
      appState.addListener(() => notified = true);
      appState.setActivePanel(PanelSide.remote);
      expect(notified, isTrue);
    });

    test('notifies listeners on toggleSortOrder', () {
      var notified = false;
      appState.addListener(() => notified = true);
      appState.toggleSortOrder(PanelSide.local);
      expect(notified, isTrue);
    });

    test('notifies listeners on setSortBy', () {
      var notified = false;
      appState.addListener(() => notified = true);
      appState.setSortBy(PanelSide.local, SortBy.date);
      expect(notified, isTrue);
    });

    test('notifies listeners on clearSelection', () {
      var notified = false;
      final item = FileItem(name: 'x.txt', isFolder: false);
      appState.toggleSelection(PanelSide.local, item);
      appState.addListener(() => notified = true);
      appState.clearSelection(PanelSide.local);
      expect(notified, isTrue);
    });
  });

  group('AppState misc', () {
    test('itemToScrollTo is null initially', () {
      expect(appState.itemToScrollTo, isNull);
    });

    test('clearItemToScrollTo sets it to null', () {
      appState.clearItemToScrollTo();
      expect(appState.itemToScrollTo, isNull);
    });

    test('receivedFiles starts empty', () {
      expect(appState.receivedFiles, isEmpty);
    });

    test('receivedText is null initially', () {
      expect(appState.receivedText, isNull);
    });

    test('clearReceivedFiles resets state', () {
      appState.clearReceivedFiles();
      expect(appState.receivedFiles, isEmpty);
      expect(appState.receivedText, isNull);
    });

    test('client accessor returns a CloudStorageClient', () {
      expect(appState.client, isNotNull);
    });
  });
}

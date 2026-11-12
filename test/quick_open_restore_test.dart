import 'dart:async';

import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/workspace_configuration.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/quick_open_provider.dart';
import 'package:crisp_cloud/providers/workspace_provider.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/quick_open_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/quick_open_fixture.dart';

void main() {
  late QuickOpenHarness harness;
  setUp(() async => harness = await QuickOpenHarness.create());
  tearDown(() => harness.dispose());

  QuickOpenController controller() =>
      harness.container.read(quickOpenControllerProvider);
  List<QuickOpenEntry> entries({QuickOpenSavedItems? saved}) =>
      controller().entries(PanelSide.local, saved, reviewRename: (_) async {});
  Future<void> open(QuickOpenEntry entry) =>
      controller().executor.open(entry, isCurrent: () => true);
  StorageReference localStorage() =>
      storageReferenceForSource(const LocalPanelSource('/'));

  SavedWorkspace workspace(StorageReference storage) {
    WorkspaceTabSnapshot tab(String path) => WorkspaceTabSnapshot.fromJson({
      'path': path,
      'storage': storage.toJson(),
    });
    return SavedWorkspace(
      id: 'work',
      name: 'Saved work',
      left: WorkspacePanelSnapshot(tabs: [tab('/favorite')]),
      right: WorkspacePanelSnapshot(tabs: [tab('/drive')]),
      layout: const WorkspaceLayout(tree: true, split: 0.65),
    );
  }

  Future<QuickOpenEntry> favorite(StorageReference storage) async {
    await harness.container
        .read(bookmarksProvider)
        .add('Saved folder', '/favorite', PanelSide.local, storage: storage);
    return entries().singleWhere(
      (entry) => entry.kind == QuickOpenKind.favorite,
    );
  }

  Future<QuickOpenEntry> savedWorkspace(StorageReference storage) async {
    final saved = workspace(storage);
    await harness.container.read(workspaceStoreProvider).saveGroup(saved);
    return entries(
      saved: QuickOpenSavedItems(workspaces: [saved], renamePresets: {}),
    ).singleWhere((entry) => entry.kind == QuickOpenKind.workspace);
  }

  test(
    'locked local favorite never opens a picker for inaccessible storage',
    () async {
      final panel = harness.container.read(panelProvider(PanelSide.local));
      final locked = panel.activeTab!;
      final originalPath = locked.path;
      panel.setTabLock(locked.id, TabLockMode.locked);
      final entry = await favorite(localStorage());
      harness.local.paths.remove('/favorite');

      await expectLater(open(entry), throwsA(isA<Exception>()));

      expect(harness.local.accessRequests, 0);
      expect(harness.local.snapshots, contains('/favorite'));
      expect(locked.path, originalPath);
      expect(panel.hasVerifiedDirectoryListing, isFalse);
    },
  );

  test('workspace local load failure is explicit and stops the other pane and layout', () async {
    final right = harness.container.read(panelProvider(PanelSide.remote));
    final originalTabs = right.tabs.map((tab) => tab.id).toList();
    final entry = await savedWorkspace(localStorage());
    harness.local.paths.remove('/favorite');

    await expectLater(open(entry), throwsA(isA<Exception>()));

    expect(harness.local.accessRequests, 0);
    expect(right.tabs.map((tab) => tab.id), originalTabs);
    expect(harness.container.read(showTreeSidebarProvider), isFalse);
  });

  test(
    'remote restore propagates a failed listing instead of reporting success',
    () async {
      final panel = harness.container.read(panelProvider(PanelSide.local));
      panel.setTabLock(panel.activeTabId, TabLockMode.locked);
      final entry = await favorite(storageReferenceForClient(harness.cloud));
      harness.cloud.failPaths.add('/favorite');

      await expectLater(open(entry), throwsStateError);

      expect(panel.hasVerifiedDirectoryListing, isFalse);
      expect(
        panel.directoryListingError?.message,
        contains('Folder unavailable'),
      );
    },
  );

  test('client replaced while departing collection marks save never supplies restored paths', () async {
    final panel = harness.container.read(panelProvider(PanelSide.local));
    final storage = storageReferenceForClient(harness.cloud);
    await harness.collections.save(
      FileCollection(
        id: 'review',
        name: 'Review',
        entries: [
          FileCollectionService.capture(
            FileItem(
              name: 'a.txt',
              path: '/favorite/a.txt',
              isFolder: false,
              size: 1,
            ),
            storage,
          ),
        ],
      ),
    );
    await panel.openCollection('review');
    panel.toggleSelection(
      panel.files!.firstWhere((file) => file.name == 'a.txt'),
    );
    final originalTabs = panel.tabs.map((tab) => tab.id).toList();
    final entry = await savedWorkspace(storage);
    final gate = Completer<void>();
    harness.collections.marksGate = gate;
    final pending = open(entry);
    final rejected = expectLater(pending, throwsA(isA<QuickOpenException>()));
    await harness.collections.marksStarted.future;
    final replacement = QuickOpenCloud('account-a')
      ..put('/favorite/wrong.txt', [9]);
    harness.cloud.current = false;
    harness.auth.client = replacement;
    harness.auth.changed();
    gate.complete();
    await rejected;

    expect(panel.tabs.map((tab) => tab.id), originalTabs);
    expect(replacement.listingStarted, isNot(contains('/favorite')));
    expect(replacement.listingStarted, isNot(contains('/drive')));
    expect(harness.container.read(showTreeSidebarProvider), isFalse);
  });

  test('replacement client during tab load cannot publish or supply saved workspace paths', () async {
    final panel = harness.container.read(panelProvider(PanelSide.local));
    final right = harness.container.read(panelProvider(PanelSide.remote));
    final originalRightTabs = right.tabs.map((tab) => tab.id).toList();
    final entry = await savedWorkspace(
      storageReferenceForClient(harness.cloud),
    );
    final gate = Completer<void>();
    harness.cloud.gates['/favorite'] = gate;
    final pending = open(entry);
    final rejected = expectLater(pending, throwsA(isA<QuickOpenException>()));
    while (!harness.cloud.listingStarted.contains('/favorite')) {
      await Future<void>.delayed(Duration.zero);
    }
    final replacement = QuickOpenCloud('account-a')
      ..put('/favorite/wrong.txt', [9]);
    harness.cloud.current = false;
    harness.auth.client = replacement;
    harness.auth.changed();
    gate.complete();
    await rejected;

    expect(replacement.listingStarted, isNot(contains('/favorite')));
    expect(replacement.listingStarted, isNot(contains('/drive')));
    expect(panel.hasVerifiedDirectoryListing, isFalse);
    expect(right.tabs.map((tab) => tab.id), originalRightTabs);
    expect(harness.container.read(showTreeSidebarProvider), isFalse);
  });
}

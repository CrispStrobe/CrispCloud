import 'dart:async';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/workspace_configuration.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/quick_open_provider.dart';
import 'package:crisp_cloud/providers/workspace_provider.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/quick_open_service.dart';
import 'package:crisp_cloud/services/rename_preset_store.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/quick_open_fixture.dart';

void main() {
  late QuickOpenHarness harness;
  setUp(() async => harness = await QuickOpenHarness.create());
  tearDown(() => harness.dispose());

  QuickOpenController controller() =>
      harness.container.read(quickOpenControllerProvider);
  List<QuickOpenEntry> entries({
    PanelSide side = PanelSide.local,
    QuickOpenSavedItems? saved,
    List<QuickOpenDevice> devices = const [],
    Future<void> Function(QuickOpenRenameRequest)? review,
  }) => controller().entries(
    side,
    saved,
    devices: devices,
    reviewRename: review ?? (_) async {},
  );
  Future<void> open(QuickOpenEntry entry) =>
      controller().executor.open(entry, isCurrent: () => true);
  StorageReference localStorage() =>
      storageReferenceForSource(const LocalPanelSource('/'));

  test(
    'duplicate favorite names retain distinct paths and original accounts',
    () async {
      final marks = harness.container.read(bookmarksProvider);
      final remote = storageReferenceForClient(harness.cloud);
      await marks.add(
        'Documents',
        '/favorite',
        PanelSide.local,
        storage: localStorage(),
      );
      await marks.add(
        'Documents',
        '/favorite',
        PanelSide.remote,
        storage: remote,
      );
      final favorites = entries()
          .where((entry) => entry.kind == QuickOpenKind.favorite)
          .toList();
      expect(favorites, hasLength(2));
      expect(favorites.map((entry) => entry.id).toSet(), hasLength(2));
      final selected = favorites.firstWhere(
        (entry) => entry.id.contains(remote.id),
      );
      await open(selected);
      final panel = harness.container.read(panelProvider(PanelSide.local));
      expect(panel.currentPath, '/favorite');
      expect(panel.captureCurrentOrigin().storageReference, remote);
      expect(harness.local.snapshots, isEmpty);
    },
  );

  test('unbound favorites, unavailable accounts and missing collections are disabled', () async {
    final marks = harness.container.read(bookmarksProvider);
    await marks.add('Old path', '/favorite', PanelSide.local);
    await marks.add(
      'Other account',
      '/favorite',
      PanelSide.remote,
      storage: const StorageReference(
        kind: 'remote',
        provider: 'Memory',
        accountKey: 'missing',
      ),
    );
    await marks.add(
      'Missing list',
      '/',
      PanelSide.local,
      collectionId: 'missing-list',
    );
    final values = entries()
        .where((entry) => entry.kind == QuickOpenKind.favorite)
        .toList();
    expect(values.map((entry) => entry.unavailable).toSet(), {
      QuickOpenUnavailable.unboundFavorite,
      QuickOpenUnavailable.sourceUnavailable,
      QuickOpenUnavailable.collectionUnavailable,
    });
    for (final entry in values) {
      await expectLater(open(entry), throwsA(isA<QuickOpenException>()));
    }
  });

  test('a disconnected favorite never adopts another account with the same provider label', () async {
    final original = storageReferenceForClient(harness.cloud);
    await harness.container
        .read(bookmarksProvider)
        .add('Remote', '/favorite', PanelSide.remote, storage: original);
    final entry = entries().firstWhere(
      (entry) => entry.kind == QuickOpenKind.favorite,
    );
    harness.cloud.current = false;
    final replacement = QuickOpenCloud('account-b')
      ..put('/favorite/wrong.txt', [9]);
    harness.auth.client = replacement;
    harness.auth.changed();
    await expectLater(open(entry), throwsA(isA<QuickOpenException>()));
    expect(
      replacement.listingStarted.where((path) => path == '/favorite'),
      isEmpty,
    );
  });

  test(
    'connected source action rejects replacement of its live client',
    () async {
      final entry = entries().firstWhere(
        (entry) => entry.kind == QuickOpenKind.source && entry.name == 'Memory',
      );
      harness.cloud.current = false;
      harness.auth.client = QuickOpenCloud('account-b');
      harness.auth.changed();
      await expectLater(open(entry), throwsA(isA<QuickOpenException>()));
    },
  );

  test(
    'device action opens captured local storage from a remote pane',
    () async {
      harness.container.read(activePanelProvider.notifier).state =
          PanelSide.remote;
      final entry = entries(
        side: PanelSide.remote,
        devices: [const QuickOpenDevice(path: '/drive', name: 'Drive')],
      ).singleWhere((entry) => entry.kind == QuickOpenKind.device);
      await open(entry);
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      expect(panel.currentPath, '/drive');
      expect(panel.captureCurrentOrigin().storageReference.isLocal, isTrue);
      expect(harness.local.accessRequests, 0);
    },
  );

  test('removed device fails without replacing the current view or requesting access', () async {
    final panel = harness.container.read(panelProvider(PanelSide.local));
    final before = panel.currentPath;
    final entry = entries(
      devices: [const QuickOpenDevice(path: '/drive', name: 'Drive')],
    ).singleWhere((entry) => entry.kind == QuickOpenKind.device);
    harness.local.paths.remove('/drive');
    await expectLater(open(entry), throwsA(isA<Exception>()));
    expect(panel.currentPath, before);
    expect(harness.local.accessRequests, 0);
  });

  test('newer local navigation wins over a pending device snapshot', () async {
    final panel = harness.container.read(panelProvider(PanelSide.local));
    final blocked = Completer<void>();
    harness.local.gates['/drive'] = blocked;
    final entry = entries(
      devices: [const QuickOpenDevice(path: '/drive', name: 'Drive')],
    ).singleWhere((entry) => entry.kind == QuickOpenKind.device);
    final pending = open(entry);
    while (!harness.local.snapshots.contains('/drive')) {
      await Future<void>.delayed(Duration.zero);
    }
    final origin = panel.resolveStorageReference(localStorage(), '/newer')!;
    await panel.navigateToPath(
      '/newer',
      origin: origin,
      allowAccessRequests: false,
    );
    blocked.complete();
    await pending;
    expect(panel.currentPath, '/newer');
  });

  SavedWorkspace workspace() {
    final storage = storageReferenceForClient(harness.cloud);
    WorkspaceTabSnapshot tab(String path) => WorkspaceTabSnapshot.fromJson({
      'path': path,
      'label': path,
      'storage': storage.toJson(),
    });
    return SavedWorkspace(
      id: 'work',
      name: 'Research',
      left: WorkspacePanelSnapshot(tabs: [tab('/left')]),
      right: WorkspacePanelSnapshot(tabs: [tab('/right')]),
      layout: const WorkspaceLayout(tree: true, split: 0.65),
    );
  }

  test('workspace opens its saved accounts in appended tabs and applies its layout', () async {
    final saved = workspace();
    await harness.container.read(workspaceStoreProvider).saveGroup(saved);
    final left = harness.container.read(panelProvider(PanelSide.local));
    final right = harness.container.read(panelProvider(PanelSide.remote));
    final leftIds = left.tabs.map((tab) => tab.id).toSet();
    final rightIds = right.tabs.map((tab) => tab.id).toSet();
    final entry = entries(
      saved: QuickOpenSavedItems(workspaces: [saved], renamePresets: {}),
    ).singleWhere((entry) => entry.kind == QuickOpenKind.workspace);
    await open(entry);
    expect(left.currentPath, '/left');
    expect(right.currentPath, '/right');
    expect(left.tabs.map((tab) => tab.id), containsAll(leftIds));
    expect(right.tabs.map((tab) => tab.id), containsAll(rightIds));
    expect(harness.container.read(showTreeSidebarProvider), isTrue);
    expect(harness.container.read(panelSplitRatioProvider), 0.65);
  });

  test('changed workspace or pane during catalog reload cancels before tabs change', () async {
    final saved = workspace();
    await harness.container.read(workspaceStoreProvider).saveGroup(saved);
    final left = harness.container.read(panelProvider(PanelSide.local));
    final before = left.tabs.length;
    final entry = entries(
      saved: QuickOpenSavedItems(workspaces: [saved], renamePresets: {}),
    ).singleWhere((entry) => entry.kind == QuickOpenKind.workspace);
    final gate = Completer<void>();
    harness.persistence.gate = gate;
    final pending = open(entry);
    final rejected = expectLater(pending, throwsA(isA<QuickOpenException>()));
    await left.navigateToPath(
      '/newer',
      origin: left.resolveStorageReference(localStorage(), '/newer'),
      allowAccessRequests: false,
    );
    gate.complete();
    await rejected;
    expect(left.tabs, hasLength(before));
    expect(left.currentPath, '/newer');
  });

  test('newer navigation while first workspace pane loads prevents second pane and layout changes', () async {
    final saved = workspace();
    await harness.container.read(workspaceStoreProvider).saveGroup(saved);
    final left = harness.container.read(panelProvider(PanelSide.local));
    final right = harness.container.read(panelProvider(PanelSide.remote));
    final rightTab = right.activeTabId;
    final rightPath = right.currentPath;
    final rightCount = right.tabs.length;
    final gate = Completer<void>();
    harness.cloud.gates['/left'] = gate;
    final entry = entries(
      saved: QuickOpenSavedItems(workspaces: [saved], renamePresets: {}),
    ).singleWhere((entry) => entry.kind == QuickOpenKind.workspace);
    final pending = open(entry);
    final rejected = expectLater(pending, throwsA(isA<QuickOpenException>()));
    while (!harness.cloud.listingStarted.contains('/left')) {
      await Future<void>.delayed(Duration.zero);
    }
    await left.navigateToPath(
      '/newer',
      origin: left.resolveStorageReference(localStorage(), '/newer'),
      allowAccessRequests: false,
    );
    gate.complete();
    await rejected;
    expect(left.currentPath, '/newer');
    expect(right.activeTabId, rightTab);
    expect(right.currentPath, rightPath);
    expect(right.tabs, hasLength(rightCount));
    expect(harness.container.read(showTreeSidebarProvider), isFalse);
  });

  test(
    'rename preset hands captured files and rules to review without writing',
    () async {
      harness.container.read(activePanelProvider.notifier).state =
          PanelSide.remote;
      final panel = harness.container.read(panelProvider(PanelSide.remote));
      await panel.navigateToPath(
        '/favorite',
        origin: panel.resolveStorageReference(
          storageReferenceForClient(harness.cloud),
          '/favorite',
        ),
      );
      final file = panel.files!.firstWhere((file) => !file.isFolder);
      panel.toggleSelection(file);
      const options = MultiRenameOptions(nameMask: '[N]-review');
      await RenamePresetStore().save({'Suffix': options});
      QuickOpenRenameRequest? request;
      final entry = entries(
        side: PanelSide.remote,
        saved: const QuickOpenSavedItems(
          workspaces: [],
          renamePresets: {'Suffix': options},
        ),
        review: (value) async => request = value,
      ).singleWhere((entry) => entry.kind == QuickOpenKind.renamePreset);
      expect(entry.enabled, isTrue);
      await open(entry);
      expect(request?.files.single, same(file));
      expect(
        request?.origin.storageReference,
        storageReferenceForClient(harness.cloud),
      );
      expect(request?.options.nameMask, '[N]-review');
      expect(harness.cloud.writes, isEmpty);
      expect(harness.cloud.files.keys, contains('/favorite/a.txt'));
    },
  );

  test('removed rename preset is rejected before opening the review', () async {
    harness.container.read(activePanelProvider.notifier).state =
        PanelSide.remote;
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await panel.navigateToPath(
      '/favorite',
      origin: panel.resolveStorageReference(
        storageReferenceForClient(harness.cloud),
        '/favorite',
      ),
    );
    final file = panel.files!.firstWhere((file) => !file.isFolder);
    panel.toggleSelection(file);
    var reviewed = false;
    final entry = entries(
      side: PanelSide.remote,
      saved: const QuickOpenSavedItems(
        workspaces: [],
        renamePresets: {'Deleted': MultiRenameOptions()},
      ),
      review: (_) async {
        reviewed = true;
      },
    ).singleWhere((entry) => entry.kind == QuickOpenKind.renamePreset);
    await expectLater(open(entry), throwsA(isA<QuickOpenException>()));
    expect(reviewed, isFalse);
    expect(harness.cloud.writes, isEmpty);
  });
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../models/workspace_configuration.dart';
import '../services/local_file_service.dart';
import '../services/multi_rename_service.dart';
import '../services/panel_source_service.dart';
import '../services/quick_open_service.dart';
import '../services/rename_preset_store.dart';
import '../services/storage_identity.dart';
import 'bookmarks_provider.dart';
import 'core_providers.dart';
import 'file_collection_provider.dart';
import 'panel_provider.dart';
import 'panel_source_provider.dart';
import 'workspace_provider.dart';

final quickOpenRenamePresetStoreProvider = Provider<RenamePresetStore>(
  (ref) => RenamePresetStore(),
);

class QuickOpenSavedItems {
  const QuickOpenSavedItems({
    required this.workspaces,
    required this.renamePresets,
    this.workspaceError = false,
    this.renamePresetError = false,
  });
  final List<SavedWorkspace> workspaces;
  final Map<String, MultiRenameOptions> renamePresets;
  final bool workspaceError;
  final bool renamePresetError;
}

/// Reopened palettes reload stores; a failed section remains visibly unavailable
/// while independently readable sections still work.
final quickOpenSavedItemsProvider =
    FutureProvider.autoDispose<QuickOpenSavedItems>((ref) async {
      var workspaceError = false;
      var renamePresetError = false;
      final workspaces = ref
          .read(workspaceStoreProvider)
          .load()
          .then(
            (catalog) => catalog.groups,
            onError: (Object _) {
              workspaceError = true;
              return <SavedWorkspace>[];
            },
          );
      final presets = ref
          .read(quickOpenRenamePresetStoreProvider)
          .load()
          .then(
            (values) => values,
            onError: (Object _) {
              renamePresetError = true;
              return <String, MultiRenameOptions>{};
            },
          );
      final groups = await workspaces;
      final rules = await presets;
      return QuickOpenSavedItems(
        workspaces: groups,
        renamePresets: rules,
        workspaceError: workspaceError,
        renamePresetError: renamePresetError,
      );
    });

class QuickOpenDevice {
  const QuickOpenDevice({required this.path, required this.name});
  final String path;
  final String name;
}

/// Read-only handoff to the existing rename preview. No operation is executed
/// by the palette, and its source is never recaptured from a different account.
class QuickOpenRenameRequest {
  const QuickOpenRenameRequest({
    required this.side,
    required this.files,
    required this.origin,
    required this.directory,
    required this.name,
    required this.options,
  });
  final PanelSide side;
  final List<FileItem> files;
  final PanelFileOrigin origin;
  final String directory;
  final String name;
  final MultiRenameOptions options;
}

final quickOpenControllerProvider = Provider<QuickOpenController>((ref) {
  final controller = QuickOpenController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class QuickOpenController {
  QuickOpenController(this.ref);
  final Ref ref;
  final executor = QuickOpenService();

  void dispose() => executor.dispose();

  List<QuickOpenEntry> entries(
    PanelSide side,
    QuickOpenSavedItems? saved, {
    List<QuickOpenDevice> devices = const [],
    required Future<void> Function(QuickOpenRenameRequest request) reviewRename,
  }) {
    final panel = ref.read(panelProvider(side));
    final entries = <QuickOpenEntry>[];
    for (final bookmark in ref.read(bookmarksProvider).bookmarks) {
      final origin = bookmark.storage == null
          ? null
          : panel.resolveStorageReference(bookmark.storage!, bookmark.path);
      final reason = !bookmark.isBound
          ? QuickOpenUnavailable.unboundFavorite
          : _locationUnavailable(
              panel,
              bookmark.storage,
              bookmark.path,
              bookmark.collectionId,
              origin,
            );
      entries.add(
        QuickOpenEntry(
          id: 'favorite:${bookmark.identity}',
          name: bookmark.name,
          kind: QuickOpenKind.favorite,
          detail:
              '${_storageLabel(panel, bookmark.storage)} · ${bookmark.path}',
          unavailable: reason,
          open: (run) async {
            final scope = _PaneScope(panel);
            await ref.read(bookmarksProvider).ready;
            _checkScope(run, side, scope);
            final live = ref.read(bookmarksProvider).bookmarks;
            if (!live.any(
              (value) =>
                  value.identity == bookmark.identity &&
                  jsonEncode(value.toJson()) == jsonEncode(bookmark.toJson()),
            )) {
              throw const QuickOpenException(QuickOpenUnavailable.changed);
            }
            await _openLocation(run, side, scope, bookmark.toTabJson(), origin);
          },
        ),
      );
    }

    for (final source in ref.read(availableSourcesProvider)) {
      final storage = storageReferenceForSource(source.source);
      final path = source.source.currentPath;
      final origin = panel.resolveStorageReference(storage, path);
      entries.add(
        QuickOpenEntry(
          id: 'source:${source.key}:${storage.id}',
          name: source.label,
          kind: QuickOpenKind.source,
          detail: '${_storageLabel(panel, storage)} · $path',
          unavailable: _locationUnavailable(panel, storage, path, null, origin),
          open: (run) async {
            final scope = _PaneScope(panel);
            _checkScope(run, side, scope);
            if (!_sourceIsLive(source, storage)) {
              throw const QuickOpenException(
                QuickOpenUnavailable.sourceUnavailable,
              );
            }
            await _openLocation(
              run,
              side,
              scope,
              {'path': path, 'storage': storage.toJson()},
              origin,
              targetCurrent: () => _sourceIsLive(source, storage),
            );
          },
        ),
      );
    }

    final uniqueDevices = <String>{};
    for (final device in devices) {
      if (!uniqueDevices.add(device.path)) continue;
      final storage = storageReferenceForSource(LocalPanelSource(device.path));
      final origin = panel.resolveStorageReference(storage, device.path);
      entries.add(
        QuickOpenEntry(
          id: 'device:${storage.id}:${device.path}',
          name: device.name,
          kind: QuickOpenKind.device,
          detail: device.path,
          unavailable: _locationUnavailable(
            panel,
            storage,
            device.path,
            null,
            origin,
          ),
          open: (run) async {
            final scope = _PaneScope(panel);
            _checkScope(run, side, scope);
            await _openLocation(run, side, scope, {
              'path': device.path,
              'storage': storage.toJson(),
            }, origin);
          },
        ),
      );
    }

    if (saved == null) return entries;
    for (final workspace in saved.workspaces) {
      final origins = _workspaceOrigins(workspace);
      final unavailable = _workspaceUnavailable(workspace, origins);
      entries.add(
        QuickOpenEntry(
          id: 'workspace:${workspace.id}',
          name: workspace.name,
          kind: QuickOpenKind.workspace,
          detail:
              '${workspace.left.tabs[workspace.left.activeIndex].path} · ${workspace.right.tabs[workspace.right.activeIndex].path}',
          unavailable: unavailable,
          open: (run) => _openWorkspace(run, side, workspace, origins),
        ),
      );
    }

    final files = List<FileItem>.unmodifiable(
      panel.selection.isNotEmpty
          ? panel.selection.where((file) => file.name != '..')
          : <FileItem>[
              if (panel.cursorItem case final file? when file.name != '..')
                file,
            ],
    );
    QuickOpenUnavailable? selectionReason;
    if (files.isEmpty) {
      selectionReason = QuickOpenUnavailable.noSelection;
    } else {
      try {
        panel.captureOperationOrigin(files);
      } catch (_) {
        selectionReason = QuickOpenUnavailable.selectionUnavailable;
      }
    }
    for (final preset in saved.renamePresets.entries) {
      final hadSelection = panel.selection.isNotEmpty;
      entries.add(
        QuickOpenEntry(
          id: 'rename:${preset.key}',
          name: preset.key,
          kind: QuickOpenKind.renamePreset,
          detail: '${files.length}',
          unavailable: selectionReason,
          open: (run) async {
            final scope = _PaneScope(panel);
            final captured = panel.captureOperationOrigin(files);
            final presets = await ref
                .read(quickOpenRenamePresetStoreProvider)
                .load();
            _checkScope(run, side, scope);
            if (!captured.isCurrent ||
                !_sameSelection(panel, files, hadSelection) ||
                jsonEncode(presets[preset.key]?.toJson()) !=
                    jsonEncode(preset.value.toJson())) {
              throw const QuickOpenException(QuickOpenUnavailable.changed);
            }
            final prepared = await panel.prepareOperationFiles(files);
            _checkScope(run, side, scope);
            if (!captured.isCurrent ||
                !_sameSelection(panel, files, hadSelection)) {
              throw const QuickOpenException(QuickOpenUnavailable.changed);
            }
            final origin = panel.captureOperationOrigin(prepared);
            if (origin.storageReference != captured.storageReference) {
              throw const QuickOpenException(
                QuickOpenUnavailable.sourceUnavailable,
              );
            }
            await reviewRename(
              QuickOpenRenameRequest(
                side: side,
                files: List.unmodifiable(prepared),
                origin: origin,
                directory: scope.path,
                name: preset.key,
                options: preset.value,
              ),
            );
          },
        ),
      );
    }
    return entries;
  }

  String _storageLabel(PanelNotifier panel, StorageReference? storage) =>
      storage == null ? '' : panel.storageDisplayName(storage);

  QuickOpenUnavailable? _locationUnavailable(
    PanelNotifier panel,
    StorageReference? storage,
    String path,
    String? collectionId,
    PanelFileOrigin? origin,
  ) {
    if (collectionId != null) {
      return ref.read(fileCollectionStoreProvider).get(collectionId) == null
          ? QuickOpenUnavailable.collectionUnavailable
          : null;
    }
    if (storage == null || origin == null || !origin.isCurrent) {
      return QuickOpenUnavailable.sourceUnavailable;
    }
    if (storage.isLocal &&
        ref.read(localFileServiceProvider) is! LocalDirectorySnapshotReader) {
      return QuickOpenUnavailable.localAccessUnavailable;
    }
    return null;
  }

  bool _sourceIsLive(AvailableSource captured, StorageReference storage) => ref
      .read(availableSourcesProvider)
      .any(
        (live) =>
            live.key == captured.key &&
            live.source.currentPath == captured.source.currentPath &&
            storageReferenceForSource(live.source) == storage &&
            switch (captured.source) {
              final RemotePanelSource old =>
                live.source is RemotePanelSource &&
                    identical(
                      (live.source as RemotePanelSource).client,
                      old.client,
                    ) &&
                    old.client.isAuthenticated,
              LocalPanelSource _ => live.source is LocalPanelSource,
              _ => false,
            },
      );

  bool _sameSelection(
    PanelNotifier panel,
    List<FileItem> files,
    bool selected,
  ) {
    final current = selected
        ? panel.selection.where((file) => file.name != '..').toList()
        : <FileItem>[if (panel.cursorItem case final file?) file];
    return current.length == files.length &&
        files.every((file) => current.any((other) => identical(file, other)));
  }

  void _checkScope(QuickOpenRun run, PanelSide side, _PaneScope scope) {
    run.check();
    if (ref.read(activePanelProvider) != side || !scope.unchanged) {
      throw const QuickOpenException(QuickOpenUnavailable.changed);
    }
  }

  Future<void> _openLocation(
    QuickOpenRun run,
    PanelSide side,
    _PaneScope scope,
    Map<String, dynamic> saved,
    PanelFileOrigin? origin, {
    bool Function()? targetCurrent,
  }) async {
    _checkScope(run, side, scope);
    if (origin?.isCurrent == false || targetCurrent?.call() == false) {
      throw const QuickOpenException(QuickOpenUnavailable.sourceUnavailable);
    }
    final panel = scope.panel;
    final collection = saved['collectionId'] as String?;
    if (collection != null) {
      final store = ref.read(fileCollectionStoreProvider);
      await store.ready;
      _checkScope(run, side, scope);
      if (store.get(collection) == null) {
        throw const QuickOpenException(
          QuickOpenUnavailable.collectionUnavailable,
        );
      }
    }
    if (panel.activeTab?.isLocked == true || collection != null) {
      await _appendTabs(
        run,
        side,
        scope,
        [saved],
        0,
        origin: origin,
        targetCurrent: () =>
            (origin?.isCurrent ?? true) && (targetCurrent?.call() ?? true),
      );
      return;
    }
    if (origin == null) {
      throw const QuickOpenException(QuickOpenUnavailable.sourceUnavailable);
    }
    await panel.navigateToPath(
      saved['path'] as String,
      origin: origin,
      allowAccessRequests: false,
      canContinue: () =>
          run.isCurrent() &&
          ref.read(activePanelProvider) == side &&
          panel.activeTabId == scope.tab &&
          panel.navigationIntentRevision <= scope.revision + 1 &&
          origin.isCurrent &&
          (targetCurrent?.call() ?? true),
    );
  }

  List<PanelFileOrigin?> _workspaceOrigins(SavedWorkspace workspace) => [
    for (final pair in [
      (PanelSide.local, workspace.left),
      (PanelSide.remote, workspace.right),
    ])
      for (final tab in pair.$2.tabs)
        tab.storage == null
            ? null
            : ref
                  .read(panelProvider(pair.$1))
                  .resolveStorageReference(tab.storage!, tab.path),
  ];

  QuickOpenUnavailable? _workspaceUnavailable(
    SavedWorkspace workspace,
    List<PanelFileOrigin?> origins,
  ) {
    var index = 0;
    for (final pair in [
      (PanelSide.local, workspace.left),
      (PanelSide.remote, workspace.right),
    ]) {
      final panel = ref.read(panelProvider(pair.$1));
      for (final tab in pair.$2.tabs) {
        final reason = _locationUnavailable(
          panel,
          tab.storage,
          tab.path,
          tab.collectionId,
          origins[index++],
        );
        if (reason != null) return reason;
      }
    }
    return null;
  }

  Future<void> _openWorkspace(
    QuickOpenRun run,
    PanelSide side,
    SavedWorkspace workspace,
    List<PanelFileOrigin?> origins,
  ) async {
    final left = _PaneScope(ref.read(panelProvider(PanelSide.local)));
    final right = _PaneScope(ref.read(panelProvider(PanelSide.remote)));
    final catalog = await ref.read(workspaceStoreProvider).load();
    _checkScope(run, side, side == PanelSide.local ? left : right);
    if (!left.unchanged ||
        !right.unchanged ||
        !catalog.groups.any(
          (value) =>
              value.id == workspace.id &&
              jsonEncode(value.toJson()) == jsonEncode(workspace.toJson()),
        ) ||
        _workspaceUnavailable(workspace, origins) != null) {
      throw const QuickOpenException(QuickOpenUnavailable.changed);
    }
    bool targetsCurrent() =>
        origins.every((origin) => origin?.isCurrent ?? true) &&
        _workspaceUnavailable(workspace, origins) == null;
    final openedLeft = await _appendTabs(
      run,
      side,
      left,
      workspace.left.tabs.map((tab) => tab.toJson()).toList(),
      workspace.left.activeIndex,
      origin: origins[workspace.left.activeIndex],
      targetCurrent: () => right.unchanged && targetsCurrent(),
    );
    if (!openedLeft.unchanged || !right.unchanged || !targetsCurrent()) {
      throw const QuickOpenException(QuickOpenUnavailable.changed);
    }
    final openedRight = await _appendTabs(
      run,
      side,
      right,
      workspace.right.tabs.map((tab) => tab.toJson()).toList(),
      workspace.right.activeIndex,
      origin: origins[workspace.left.tabs.length + workspace.right.activeIndex],
      targetCurrent: () => openedLeft.unchanged && targetsCurrent(),
    );
    run.check();
    if (!openedLeft.unchanged ||
        !openedRight.unchanged ||
        !targetsCurrent() ||
        ref.read(activePanelProvider) != side) {
      throw const QuickOpenException(QuickOpenUnavailable.changed);
    }
    ref.read(showDualPanelProvider.notifier).state = workspace.layout.dualPanel;
    ref.read(showTreeSidebarProvider.notifier).state = workspace.layout.tree;
    ref.read(showPreviewProvider.notifier).state = workspace.layout.preview;
    ref.read(panelSplitRatioProvider.notifier).state = workspace.layout.split;
    ref.read(activePanelProvider.notifier).state = PanelSide.values.byName(
      workspace.layout.activeSide,
    );
  }

  Future<_PaneScope> _appendTabs(
    QuickOpenRun run,
    PanelSide activeSide,
    _PaneScope before,
    List<Map<String, dynamic>> tabs,
    int activeIndex, {
    required PanelFileOrigin? origin,
    required bool Function() targetCurrent,
  }) async {
    _checkScope(run, activeSide, before);
    if (!targetCurrent()) {
      throw const QuickOpenException(QuickOpenUnavailable.changed);
    }
    final panel = before.panel;
    final existing = panel.tabs.map((tab) => tab.id).toSet();
    // restoreTabs selects the appended tab (one intent), then navigates its
    // filesystem path (one more). Collections retain the selection intent.
    final expectedRevision =
        before.revision + (tabs[activeIndex]['collectionId'] == null ? 2 : 1);
    String? targetId() {
      final added = panel.tabs
          .where((tab) => !existing.contains(tab.id))
          .toList();
      return added.length == tabs.length ? added[activeIndex].id : null;
    }

    bool canContinue() =>
        run.isCurrent() &&
        ref.read(activePanelProvider) == activeSide &&
        targetCurrent() &&
        panel.navigationIntentRevision >= before.revision &&
        panel.navigationIntentRevision <= expectedRevision &&
        (panel.activeTabId == before.tab || panel.activeTabId == targetId());
    try {
      await panel.restoreTabs(
        tabs,
        activeIndex: activeIndex,
        capturedOrigin: origin,
        allowAccessRequests: false,
        canContinue: canContinue,
        requireAvailable: true,
      );
    } catch (_) {
      run.check();
      if (!canContinue()) {
        throw const QuickOpenException(QuickOpenUnavailable.changed);
      }
      rethrow;
    }
    run.check();
    if (ref.read(activePanelProvider) != activeSide ||
        !targetCurrent() ||
        panel.activeTabId != targetId() ||
        panel.navigationIntentRevision != expectedRevision) {
      throw const QuickOpenException(QuickOpenUnavailable.changed);
    }
    return _PaneScope(panel);
  }
}

class _PaneScope {
  _PaneScope(this.panel)
    : tab = panel.activeTabId,
      revision = panel.navigationIntentRevision,
      path = panel.currentPath;
  final PanelNotifier panel;
  final String tab;
  final int revision;
  final String path;
  bool get unchanged =>
      panel.activeTabId == tab &&
      panel.navigationIntentRevision == revision &&
      panel.currentPath == path;
}

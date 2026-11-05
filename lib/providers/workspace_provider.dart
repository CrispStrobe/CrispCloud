import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/panel_side.dart';
import '../models/workspace_configuration.dart';
import '../services/workspace_store.dart';
import 'core_providers.dart';
import 'file_collection_provider.dart';
import 'panel_provider.dart';

final workspaceStoreProvider = Provider<WorkspaceStore>(
  (ref) => WorkspaceStore(),
);
final workspaceControllerProvider = Provider<WorkspaceController>(
  WorkspaceController.new,
);

/// Captures both panes using the same source-bound tab serialization as restart
/// restoration. A named workspace never adopts the currently signed-in account.
class WorkspaceController {
  WorkspaceController(this.ref);
  final Ref ref;

  Future<WorkspacePanelSnapshot> _capture(PanelSide side) async {
    final panel = ref.read(panelProvider(side));
    final saved = await panel.exportTabs();
    return WorkspacePanelSnapshot(
      tabs: saved.map(WorkspaceTabSnapshot.fromJson).toList(),
      activeIndex: panel.tabs
          .indexWhere((tab) => tab.id == panel.activeTabId)
          .clamp(0, saved.length - 1),
    );
  }

  Future<SavedWorkspace> captureGroup(String name, {String? id}) async {
    final left = await _capture(PanelSide.local);
    final right = await _capture(PanelSide.remote);
    return SavedWorkspace(
      id: id ?? const Uuid().v4(),
      name: name,
      left: left,
      right: right,
      layout: WorkspaceLayout(
        dualPanel: ref.read(showDualPanelProvider),
        tree: ref.read(showTreeSidebarProvider),
        preview: ref.read(showPreviewProvider),
        split: ref.read(panelSplitRatioProvider).clamp(0.15, 0.85),
        activeSide: ref.read(activePanelProvider).name,
      ),
    );
  }

  Future<PairedBookmark> capturePair(String name, {String? id}) async {
    final left = await _capture(PanelSide.local);
    final right = await _capture(PanelSide.remote);
    return PairedBookmark(
      id: id ?? const Uuid().v4(),
      name: name,
      left: left.tabs[left.activeIndex],
      right: right.tabs[right.activeIndex],
    );
  }

  Future<void> openGroup(
    SavedWorkspace group, {
    bool replace = false,
    bool keepProtected = true,
  }) async {
    // Models validate both panes before either live pane can be changed.
    await ref
        .read(panelProvider(PanelSide.local))
        .restoreTabs(
          group.left.tabs.map((tab) => tab.toJson()).toList(),
          activeIndex: group.left.activeIndex,
          replace: replace,
          keepProtected: keepProtected,
        );
    await ref
        .read(panelProvider(PanelSide.remote))
        .restoreTabs(
          group.right.tabs.map((tab) => tab.toJson()).toList(),
          activeIndex: group.right.activeIndex,
          replace: replace,
          keepProtected: keepProtected,
        );
    ref.read(showDualPanelProvider.notifier).state = group.layout.dualPanel;
    ref.read(showTreeSidebarProvider.notifier).state = group.layout.tree;
    ref.read(showPreviewProvider.notifier).state = group.layout.preview;
    ref.read(panelSplitRatioProvider.notifier).state = group.layout.split;
    ref.read(activePanelProvider.notifier).state = PanelSide.values.byName(
      group.layout.activeSide,
    );
  }

  Future<PanelFileOrigin?> _verifyPairTarget(
    PanelSide side,
    WorkspaceTabSnapshot target,
  ) async {
    final panel = ref.read(panelProvider(side));
    if (target.collectionId != null) {
      final store = ref.read(fileCollectionStoreProvider);
      await store.ready;
      if (store.get(target.collectionId!) == null) {
        throw StateError(
          'The collection for "${target.label}" is not available on this installation. Import that collection first.',
        );
      }
      return null;
    }
    final origin = panel.resolveStorageReference(target.storage!, target.path);
    if (origin == null) {
      throw StateError(
        'Reconnect the original ${target.storage!.provider} account for "${target.label}" before opening this pair.',
      );
    }
    return origin;
  }

  Future<void> openPair(PairedBookmark pair, {bool newTabs = false}) async {
    // Verify both sources before navigating either pane. Recheck after awaits
    // so a reconnection while loading a collection cannot rebind the pair.
    final left = await _verifyPairTarget(PanelSide.local, pair.left);
    final right = await _verifyPairTarget(PanelSide.remote, pair.right);
    if (left?.isCurrent == false || right?.isCurrent == false) {
      throw StateError(
        'A storage account changed while opening the paired bookmark.',
      );
    }
    await ref
        .read(panelProvider(PanelSide.local))
        .openSavedLocation(pair.left.toJson(), newTab: newTabs);
    if (right?.isCurrent == false) {
      throw StateError(
        'The right account disconnected after the left location opened. Reconnect it and reopen the pair.',
      );
    }
    await ref
        .read(panelProvider(PanelSide.remote))
        .openSavedLocation(pair.right.toJson(), newTab: newTabs);
    ref.read(showDualPanelProvider.notifier).state = true;
  }
}

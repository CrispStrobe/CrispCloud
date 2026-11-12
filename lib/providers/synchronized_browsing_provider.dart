import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/panel_side.dart';
import '../services/file_operation_backend.dart';
import '../services/local_file_service.dart';
import '../services/panel_source_service.dart';
import '../services/synchronized_browsing_service.dart';
import 'core_providers.dart';
import 'panel_provider.dart';

final synchronizedBrowsingProvider =
    ChangeNotifierProvider<SynchronizedBrowsingService>((ref) {
      final local = ref.read(localFileServiceProvider);
      final left = PanelBrowsingPane(
        ref.read(panelProvider(PanelSide.local)),
        local,
      );
      final right = PanelBrowsingPane(
        ref.read(panelProvider(PanelSide.remote)),
        local,
      );
      ref.onDispose(() {
        left.dispose();
        right.dispose();
      });
      return SynchronizedBrowsingService(left, right);
    });

/// Uses verified panel origins rather than the pane's visual left/right label.
class PanelBrowsingPane extends BrowsingPane {
  PanelBrowsingPane(this.panel, this.local) {
    panel.addListener(notifyListeners);
  }

  final PanelNotifier panel;
  final LocalFileService local;

  @override
  BrowsingLocation? get location {
    if (panel.isInArchive || panel.showingSearchResults || panel.isFlatView) {
      return null;
    }
    final origin = panel.directoryPresentationOrigin;
    if (origin == null) return null;
    final source = origin.source;
    if (source is! LocalPanelSource && source is! RemotePanelSource) {
      return null;
    }
    return BrowsingLocation(
      path: panel.currentPath,
      paths: source.isLocal && !kIsWeb ? p.context : p.posix,
      tabId: panel.activeTabId,
      storage: origin.storageReference,
      session: source is RemotePanelSource ? source.client : local,
      isCurrent: () => origin.isCurrent,
      navigationRevision: panel.navigationIntentRevision,
      loading: panel.isLoading,
      verified: panel.hasVerifiedDirectoryListing,
      locked: panel.activeTab?.isLocked ?? false,
      handle: origin,
    );
  }

  PanelFileOrigin _verify(BrowsingLocation captured) {
    final current = location;
    if (current == null ||
        !captured.isCurrent() ||
        !current.isCurrent() ||
        current.loading ||
        !current.verified ||
        current.locked ||
        !current.sameSource(captured) ||
        current.navigationRevision != captured.navigationRevision ||
        !current.samePath(captured)) {
      throw StateError(
        'The linked folder changed while navigation was pending.',
      );
    }
    return captured.handle! as PanelFileOrigin;
  }

  @override
  Future<bool> containsDirectory(String path, BrowsingLocation captured) async {
    final origin = _verify(captured);
    if (origin.source is LocalPanelSource) {
      // Snapshot reads use existing grants and cannot open a folder picker.
      // Read the target itself: its parent may be outside the granted root.
      try {
        final entries = await local.listDirectorySnapshot(path);
        _verify(captured);
        return entries != null;
      } on FileSystemException catch (error) {
        _verify(captured);
        if (const {2, 3, 20}.contains(error.osError?.errorCode)) return false;
        rethrow;
      }
    }
    final backend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => origin.isCurrent,
    );
    final item = await backend.stat(path);
    _verify(captured);
    return item != null && item.isFolder && item.isSymlink != true;
  }

  @override
  Future<void> navigate(
    String path,
    BrowsingLocation captured, {
    required bool Function() canContinue,
  }) async {
    final origin = _verify(captured);
    await panel.navigateToPath(
      path,
      origin: origin,
      allowAccessRequests: false,
      canContinue: canContinue,
    );
  }

  @override
  void dispose() {
    panel.removeListener(notifyListeners);
    super.dispose();
  }
}

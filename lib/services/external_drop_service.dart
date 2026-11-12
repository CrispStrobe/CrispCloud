import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';

import '../models/panel_drag_data.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import 'external_drop_source.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'panel_source_service.dart';
import 'storage_identity.dart';

class CapturedExternalDropDestination {
  CapturedExternalDropDestination._(
    this._isCurrent, {
    required this.side,
    required this.origin,
    required this.path,
    required this.backend,
    required this.local,
  });

  final PanelSide side;
  final PanelFileOrigin origin;
  final String path;
  final FileOperationBackend backend;
  final LocalFileService local;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent() && origin.isCurrent;

  void check() {
    if (!isCurrent) {
      throw const PanelDragException(PanelDragFailure.destinationChanged);
    }
  }

  Future<void> verify() async {
    check();
    try {
      if (origin.source.isLocal) {
        // Existing grants only; a hover/drop never opens an access picker.
        if (await local.listDirectorySnapshot(path) == null) {
          throw const PanelDragException(PanelDragFailure.unavailable);
        }
      } else {
        // A root stat may be synthetic. A fresh read proves the captured
        // account/path can actually be reached before its review is shown.
        await backend.list(path);
      }
    } catch (_) {
      check();
      throw const PanelDragException(PanelDragFailure.unavailable);
    }
    check();
  }
}

class PreparedExternalDrop {
  PreparedExternalDrop({
    required this.source,
    required this.sourceOrigin,
    required this.destination,
  });
  final ExternalDropSource source;
  final PanelFileOrigin sourceOrigin;
  final CapturedExternalDropDestination destination;
}

/// External files only reach the existing copy review. Their destination is
/// captured from the actual displayed source, independently of pane position.
class ExternalDropService {
  const ExternalDropService({
    this.browser = kIsWeb,
    this.access = const DesktopExternalDropAccess(),
  });
  final bool browser;
  final ExternalDropAccess access;

  CapturedExternalDropDestination capture(
    PanelNotifier panel,
    LocalFileService local,
  ) {
    if (panel.isInArchive || panel.showingSearchResults || panel.isFlatView) {
      throw const PanelDragException(PanelDragFailure.invalidDestination);
    }
    final origin = panel.captureCurrentOrigin();
    final tab = panel.activeTabId;
    final navigation = panel.navigationIntentRevision;
    final session = panel.captureOperationSession();
    final backend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => origin.isCurrent,
    );
    final path = backend.paths.normalize(origin.source.currentPath);
    if (!backend.paths.isAbsolute(path) || path.contains('\u0000')) {
      throw const PanelDragException(PanelDragFailure.invalidDestination);
    }
    if (origin.source.isLocal &&
        local is LocalFileSourceIdentity &&
        (local as LocalFileSourceIdentity).sourceIdentityForPath(path) ==
            null) {
      throw const PanelDragException(PanelDragFailure.invalidDestination);
    }
    return CapturedExternalDropDestination._(
      () =>
          session() &&
          panel.activeTabId == tab &&
          panel.navigationIntentRevision == navigation &&
          panel.hasVerifiedDirectoryListing &&
          !panel.isLoading,
      side: panel.side,
      origin: origin,
      path: path,
      backend: backend,
      local: local,
    );
  }

  Future<PreparedExternalDrop> prepare(
    PanelNotifier panel,
    CapturedExternalDropDestination destination,
    List<DropItem> items, {
    bool Function()? isMounted,
  }) async {
    bool current() => destination.isCurrent && (isMounted?.call() ?? true);
    destination.check();
    await destination.verify();
    ExternalDropSource? source;
    try {
      source = await ExternalDropSource.prepare(
        List.unmodifiable(items),
        browser: browser,
        access: access,
        canContinue: current,
      );
      destination.check();
      if (!(isMounted?.call() ?? true)) {
        throw const ExternalDropException(ExternalDropFailure.unavailable);
      }
      final capturedSource = source;
      // This origin is only the lifetime guard for the explicit read-only
      // backend. It is never offered as a writable destination in the review.
      final localReference = storageReferenceForSource(
        const LocalPanelSource('/'),
      );
      final origin = panel.resolveStorageReference(localReference, '/');
      if (origin == null) {
        throw const ExternalDropException(ExternalDropFailure.unavailable);
      }
      return PreparedExternalDrop(
        source: source,
        sourceOrigin: origin.withAvailabilityGuard(
          () => capturedSource.isCurrent,
        ),
        destination: destination,
      );
    } catch (_) {
      await source?.close();
      destination.check();
      rethrow;
    }
  }
}

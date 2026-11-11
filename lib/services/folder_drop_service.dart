import 'dart:io';

import '../models/file_item.dart';
import '../models/panel_drag_data.dart';
import '../providers/panel_provider.dart';
import 'file_collection_service.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';

class CapturedFolderDropTarget {
  CapturedFolderDropTarget._({
    required this.origin,
    required this.folder,
    required this.path,
    required this.backend,
    required bool Function() isCurrent,
    Future<bool> Function()? hasAccess,
    Future<FileItem?> Function()? readFolder,
    bool compareModified = true,
  }) : _isCurrent = isCurrent,
       _hasAccess = hasAccess,
       _readFolder = readFolder,
       _compareModified = compareModified;

  final PanelFileOrigin origin;
  final FileItem folder;
  final String path;
  final FileOperationBackend backend;
  final bool Function() _isCurrent;
  final Future<bool> Function()? _hasAccess;
  final Future<FileItem?> Function()? _readFolder;
  final bool _compareModified;
  bool get isCurrent => _isCurrent() && origin.isCurrent;
}

class PreparedFolderDrop {
  PreparedFolderDrop({
    required this.data,
    required this.destination,
    required this.kind,
    required this.groups,
  });
  final PanelDragData data;
  final CapturedFolderDropTarget destination;
  final FileOperationKind kind;
  final Map<PanelFileOrigin, List<FileItem>> groups;
  List<FileItem> get files => [for (final group in groups.values) ...group];
}

/// Only prepares a review. All copying/moving remains in the existing reviewed
/// operation dialog and its staged, conflict-aware transfer engine.
class FolderDropService {
  const FolderDropService();

  bool _isFolder(FileItem folder) =>
      folder.isFolder &&
      folder.isSymlink != true &&
      folder.name != '.' &&
      folder.name != '..';

  /// Keep an already captured local grant alive through review and execution.
  /// Pane navigation is deliberately separate from this source availability
  /// check: a reviewed background operation can outlive its originating view.
  PanelFileOrigin _guardLocalSource(
    PanelFileOrigin origin,
    LocalFileService local,
    String path,
  ) {
    if (!origin.source.isLocal) return origin;
    if (local is LocalFileSourceIdentity) {
      final identities = local as LocalFileSourceIdentity;
      final identity = identities.sourceIdentityForPath(path);
      return origin.withAvailabilityGuard(
        () =>
            identity != null &&
            identical(identities.sourceIdentityForPath(path), identity),
      );
    }
    // A native service can retain several valid bookmarks. Its last chosen
    // root is presentation state, so changing it must not revoke a reviewed
    // literal path. The backend still acquires and verifies its actual scope.
    return origin;
  }

  /// Virtual folders have no authoritative modified time. Read their existing
  /// grant directly; normal backend listing can reuse cached browser rows and
  /// change the shared directory cache. A snapshot cannot request new access.
  Future<FileItem?> _readVirtualFolder(
    LocalFileService local,
    FileOperationBackend backend,
    String path,
  ) async {
    final paths = backend.paths;
    final parent = paths.dirname(path);
    final entries = await local.listDirectorySnapshot(parent);
    if (entries == null) {
      throw const PanelDragException(PanelDragFailure.unavailable);
    }
    final matches = entries
        .where(
          (entry) =>
              !entry.path.contains('\u0000') &&
              paths.isAbsolute(entry.path) &&
              paths.normalize(entry.path) == path &&
              paths.dirname(paths.normalize(entry.path)) == parent,
        )
        .toList();
    if (matches.length > 1) {
      throw const PanelDragException(PanelDragFailure.destinationChanged);
    }
    if (matches.isEmpty) return null;
    final entry = matches.single;
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: entry is Directory,
      isSymlink: entry is Link,
    );
  }

  CapturedFolderDropTarget? capture(
    PanelNotifier panel,
    FileItem folder,
    LocalFileService local,
  ) {
    if (!_isFolder(folder) || panel.showingSearchResults || panel.isInArchive) {
      return null;
    }
    final listedOrigin = panel.originForOperation(folder);
    if (listedOrigin == null) return null;
    final origin = _guardLocalSource(
      listedOrigin,
      local,
      folder.path ?? listedOrigin.source.currentPath,
    );
    final tab = panel.activeTabId;
    final sessionIsCurrent = panel.captureOperationSession();
    final backend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => origin.isCurrent,
    );
    final path =
        folder.path ??
        backend.paths.join(origin.source.currentPath, folder.name);
    if (!backend.paths.isAbsolute(path) || path.contains('\u0000')) return null;
    final virtual = origin.source.isLocal && local is LocalFileSourceIdentity;
    bool current() =>
        sessionIsCurrent() &&
        panel.activeTabId == tab &&
        !panel.showingSearchResults &&
        panel.originForOperation(folder) != null &&
        origin.isCurrent;
    return CapturedFolderDropTarget._(
      origin: origin,
      folder: folder,
      path: backend.paths.normalize(path),
      backend: backend,
      isCurrent: current,
      hasAccess: origin.source.isLocal
          ? () => local.hasAccessToPath(backend.paths.dirname(path))
          : null,
      readFolder: virtual
          ? () => _readVirtualFolder(
              local,
              backend,
              backend.paths.normalize(path),
            )
          : null,
      compareModified: !virtual,
    );
  }

  /// Ancestor rows request a destination; they are never operation sources.
  /// Require their exact live endpoint, a real ancestor of the current folder,
  /// and a direct child inside the original source/grant before fresh stat.
  CapturedFolderDropTarget? captureSnapshot(
    PanelNotifier panel,
    FileItem folder,
    LocalFileService local, {
    required PanelFileOrigin snapshotOrigin,
    required String directoryPath,
    required bool Function() snapshotIsCurrent,
  }) {
    if (!_isFolder(folder) ||
        folder.path == null ||
        !snapshotIsCurrent() ||
        !snapshotOrigin.isCurrent ||
        panel.showingSearchResults ||
        panel.isFlatView ||
        panel.isInArchive) {
      return null;
    }
    final PanelFileOrigin live;
    try {
      live = panel.captureCurrentOrigin();
    } on StateError {
      return null;
    }
    if (live.storageReference != snapshotOrigin.storageReference ||
        live.source.withPath('') != snapshotOrigin.source.withPath('')) {
      return null;
    }
    final origin = _guardLocalSource(snapshotOrigin, local, folder.path!);
    final backend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => origin.isCurrent,
    );
    final paths = backend.paths;
    if ([
      folder.path!,
      directoryPath,
      live.source.currentPath,
    ].any((path) => !paths.isAbsolute(path) || path.contains('\u0000'))) {
      return null;
    }
    final parent = paths.normalize(directoryPath);
    final path = paths.normalize(folder.path!);
    final livePath = paths.normalize(live.source.currentPath);
    if (paths.dirname(path) != parent ||
        paths.basename(path) != folder.name ||
        !paths.isWithin(parent, livePath)) {
      return null;
    }
    if (origin.source.isLocal) {
      if (local is LocalFileSourceIdentity) {
        final identities = local as LocalFileSourceIdentity;
        final identity = identities.sourceIdentityForPath(livePath);
        if (identity == null ||
            !identical(identities.sourceIdentityForPath(parent), identity) ||
            !identical(identities.sourceIdentityForPath(path), identity)) {
          return null;
        }
      } else if (local.grantedBasePath case final String grant) {
        final root = paths.normalize(grant);
        if (!paths.isAbsolute(root) ||
            (parent != root && !paths.isWithin(root, parent))) {
          return null;
        }
      }
    } else {
      final root = paths.normalize(origin.storageReference.root);
      if (!paths.isAbsolute(root) ||
          (parent != root && !paths.isWithin(root, parent))) {
        return null;
      }
    }
    final sessionIsCurrent = panel.captureOperationSession();
    bool current() =>
        sessionIsCurrent() &&
        snapshotIsCurrent() &&
        !panel.isLoading &&
        !panel.showingSearchResults &&
        !panel.isInArchive &&
        !panel.isFlatView &&
        live.isCurrent &&
        origin.isCurrent;
    if (!current()) return null;
    final virtual = origin.source.isLocal && local is LocalFileSourceIdentity;
    return CapturedFolderDropTarget._(
      origin: origin,
      folder: folder,
      path: path,
      backend: backend,
      isCurrent: current,
      hasAccess: origin.source.isLocal
          ? () => local.hasAccessToPath(parent)
          : null,
      readFolder: virtual
          ? () => _readVirtualFolder(local, backend, path)
          : null,
      compareModified: !virtual,
    );
  }

  bool canAccept(
    PanelDragData data,
    CapturedFolderDropTarget destination,
    FileOperationKind kind,
  ) {
    if (!data.isCurrent || !destination.isCurrent || data.files.isEmpty) {
      return false;
    }
    final groups = data.capturedGroups;
    return groups == null || _validRelationship(groups, destination, kind);
  }

  bool _validRelationship(
    Map<PanelFileOrigin, List<FileItem>> groups,
    CapturedFolderDropTarget destination,
    FileOperationKind kind,
  ) {
    final backend = destination.backend;
    final target = backend.destinationPathKey(destination.path);
    for (final group in groups.entries) {
      if (group.key.storageReference != destination.origin.storageReference) {
        continue;
      }
      for (final file in group.value) {
        final path =
            file.path ??
            backend.paths.join(group.key.source.currentPath, file.name);
        final source = backend.destinationPathKey(path);
        if (source == target ||
            (file.isFolder && backend.paths.isWithin(source, target)) ||
            (kind == FileOperationKind.move &&
                backend.paths.dirname(source) == target)) {
          return false;
        }
      }
    }
    return true;
  }

  Future<PreparedFolderDrop> prepare(
    PanelDragData data,
    CapturedFolderDropTarget destination, {
    required FileOperationKind kind,
  }) async {
    final groups = await data.prepareForDrop();
    if (!destination.isCurrent) {
      throw const PanelDragException(PanelDragFailure.destinationChanged);
    }
    if (!_validRelationship(groups, destination, kind)) {
      throw const PanelDragException(PanelDragFailure.invalidDestination);
    }
    FileItem? current;
    try {
      if (destination._hasAccess != null && !await destination._hasAccess()) {
        throw const PanelDragException(PanelDragFailure.unavailable);
      }
      if (!destination.isCurrent || !data.isCurrent) {
        throw const PanelDragException(PanelDragFailure.destinationChanged);
      }
      current = destination._readFolder != null
          ? await destination._readFolder()
          : await destination.backend.stat(destination.path);
    } on PanelDragException {
      rethrow;
    } catch (_) {
      throw const PanelDragException(PanelDragFailure.unavailable);
    }
    if (!canAccept(data, destination, kind) ||
        current == null ||
        !current.isFolder ||
        current.isSymlink == true ||
        !_sameFolder(
          destination.folder,
          current,
          compareModified: destination._compareModified,
        )) {
      throw const PanelDragException(PanelDragFailure.destinationChanged);
    }
    return PreparedFolderDrop(
      data: data,
      destination: destination,
      kind: kind,
      groups: groups,
    );
  }

  bool _sameFolder(
    FileItem expected,
    FileItem current, {
    required bool compareModified,
  }) {
    final object = FileCollectionService.objectIdentity(expected);
    final version = FileCollectionService.version(expected);
    return (object == null ||
            object == FileCollectionService.objectIdentity(current)) &&
        (version == null ||
            version == FileCollectionService.version(current)) &&
        (!compareModified ||
            object != null ||
            expected.updatedAt == null ||
            expected.updatedAt == current.updatedAt);
  }
}

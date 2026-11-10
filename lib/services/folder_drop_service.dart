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
  }) : _isCurrent = isCurrent;

  final PanelFileOrigin origin;
  final FileItem folder;
  final String path;
  final FileOperationBackend backend;
  final bool Function() _isCurrent;
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

  CapturedFolderDropTarget? capture(
    PanelNotifier panel,
    FileItem folder,
    LocalFileService local,
  ) {
    if (!folder.isFolder ||
        folder.isSymlink == true ||
        folder.name == '.' ||
        folder.name == '..' ||
        panel.showingSearchResults ||
        panel.isInArchive) {
      return null;
    }
    final origin = panel.originForOperation(folder);
    if (origin == null) return null;
    final tab = panel.activeTabId;
    final backend = fileOperationBackend(
      source: origin.source,
      local: local,
      isCurrent: () => origin.isCurrent,
    );
    final path =
        folder.path ??
        backend.paths.join(origin.source.currentPath, folder.name);
    if (!backend.paths.isAbsolute(path) || path.contains('\u0000')) return null;
    bool current() =>
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
    );
  }

  bool canAccept(
    PanelDragData data,
    CapturedFolderDropTarget destination,
    FileOperationKind kind,
  ) {
    if (!data.isCurrent || !destination.isCurrent || data.files.isEmpty)
      return false;
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
      if (group.key.storageReference != destination.origin.storageReference)
        continue;
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
      current = await destination.backend.stat(destination.path);
    } catch (_) {
      throw const PanelDragException(PanelDragFailure.unavailable);
    }
    if (!canAccept(data, destination, kind) ||
        current == null ||
        !current.isFolder ||
        current.isSymlink == true ||
        !_sameFolder(destination.folder, current)) {
      throw const PanelDragException(PanelDragFailure.destinationChanged);
    }
    return PreparedFolderDrop(
      data: data,
      destination: destination,
      kind: kind,
      groups: groups,
    );
  }

  bool _sameFolder(FileItem expected, FileItem current) {
    final object = FileCollectionService.objectIdentity(expected);
    final version = FileCollectionService.version(expected);
    return (object == null ||
            object == FileCollectionService.objectIdentity(current)) &&
        (version == null ||
            version == FileCollectionService.version(current)) &&
        (object != null ||
            expected.updatedAt == null ||
            expected.updatedAt == current.updatedAt);
  }
}

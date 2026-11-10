import '../providers/panel_provider.dart';
import 'file_item.dart';
import 'panel_side.dart';

enum PanelDragFailure {
  sourceChanged,
  destinationChanged,
  invalidDestination,
  unavailable,
}

class PanelDragException implements Exception {
  const PanelDragException(this.failure);
  final PanelDragFailure failure;

  @override
  String toString() => 'Panel drag: ${failure.name}';
}

/// Transient drag state. It is never persisted or shared with native clipboard
/// data: its captured origins contain the live, original storage capabilities.
class PanelDragData {
  PanelDragData({required this.sourceSide, required Iterable<FileItem> files})
    : _files = List.unmodifiable(files);

  final PanelSide sourceSide;
  List<FileItem> _files;
  List<FileItem> get files => _files;
  PanelNotifier? _source;
  bool Function()? _sourceSession;
  String? _tabId;
  String? _collectionId;
  String? _collectionRevision;
  List<FileItem>? _publishedRows;
  int _publishedCount = 0;
  Map<PanelFileOrigin, List<FileItem>>? _groups;
  Future<void>? _preparing;
  Object? _failure;
  bool _captured = false;
  Object? _folderTarget;

  bool get hasCapturedSource => _captured;
  bool get hasFolderTarget => _folderTarget != null;
  void enterFolderTarget(Object owner) => _folderTarget = owner;
  void leaveFolderTarget(Object owner) {
    if (identical(_folderTarget, owner)) _folderTarget = null;
  }

  /// Called by the drag anchor before Flutter creates its first target hit.
  /// Files and account groups are frozen once; a later pane is never substituted.
  void captureFrom(PanelNotifier source, {FileItem? primary}) {
    if (_captured) return;
    _captured = true;
    _source = source;
    _sourceSession = source.captureOperationSession();
    _tabId = source.activeTabId;
    _collectionId = source.activeCollectionId;
    _collectionRevision = source.collectionRevision;
    _publishedRows = source.files;
    _publishedCount = source.files?.length ?? 0;
    if (primary != null) {
      _files = List.unmodifiable(
        source.isSelected(primary) ? source.selection : [primary],
      );
    }
    try {
      if (source.side != sourceSide || _files.isEmpty) {
        throw const PanelDragException(PanelDragFailure.sourceChanged);
      }
      if (source.isPagedCollection) {
        if (!source.recognizesCollectionRows(_files)) {
          throw const PanelDragException(PanelDragFailure.sourceChanged);
        }
        // Off-page marks require fresh reads. Begin those at drag start and
        // await them before reviewing a drop; failure never returns a subset.
        _preparing = _prepareCollection(source);
      } else {
        _groups = Map.unmodifiable(source.captureOperationGroups(_files));
      }
    } catch (error) {
      _failure = error;
    }
  }

  Future<void> _prepareCollection(PanelNotifier source) async {
    try {
      final verified = await source.prepareOperationFiles(_files);
      if (!_sameView) {
        throw const PanelDragException(PanelDragFailure.sourceChanged);
      }
      _collectionRevision = source.collectionRevision;
      _publishedRows = source.files;
      _publishedCount = source.files?.length ?? 0;
      _groups = Map.unmodifiable(source.captureOperationGroups(verified));
    } catch (error) {
      _failure = error;
    }
  }

  bool get _sameView =>
      _source != null &&
      (_sourceSession?.call() ?? false) &&
      _source!.activeTabId == _tabId &&
      _source!.activeCollectionId == _collectionId &&
      identical(_source!.files, _publishedRows) &&
      (_source!.files?.length ?? 0) == _publishedCount;

  bool get isCurrent {
    if (!_captured || _failure != null || !_sameView) return false;
    final groups = _groups;
    if (groups == null) return _preparing != null;
    if (_source!.collectionRevision != _collectionRevision) return false;
    return groups.entries.every(
      (group) =>
          group.key.isCurrent &&
          group.value.isNotEmpty &&
          _source!.originForOperation(group.value.first) != null,
    );
  }

  Map<PanelFileOrigin, List<FileItem>>? get capturedGroups => _groups;

  Future<Map<PanelFileOrigin, List<FileItem>>> prepareForDrop() async {
    await _preparing;
    if (!isCurrent || _groups == null) {
      throw const PanelDragException(PanelDragFailure.sourceChanged);
    }
    // Hover remains cheap for large selections. Recheck every exact source row
    // once at drop without replacing the account groups captured at drag start.
    try {
      _source!.captureOperationGroups([
        for (final group in _groups!.values) ...group,
      ]);
    } catch (_) {
      throw const PanelDragException(PanelDragFailure.sourceChanged);
    }
    return _groups!;
  }
}

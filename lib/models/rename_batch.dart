import '../models/file_item.dart';
import 'storage_reference.dart';

enum RenameBatchState {
  prepared,
  running,
  paused,
  completed,
  failed,
  needsReview,
  restoring,
  restored,
}

enum RenameStepState { pending, inFlight, completed, restoring, restored }

enum RenameStepKind { direct, stage, finish }

/// A deliberately small, non-secret object fingerprint. Raw provider metadata,
/// authorization headers and credentials are never written to the journal.
class RenameFingerprint {
  const RenameFingerprint({
    required this.folder,
    this.objectId,
    this.version,
    this.size,
    this.modified,
    this.link = false,
    this.linkTarget,
    this.digest,
  });

  final bool folder;
  final String? objectId;
  final String? version;
  final int? size;
  final DateTime? modified;
  final bool link;
  final String? linkTarget;
  final String? digest;

  factory RenameFingerprint.fromFile(
    FileItem file, {
    String? digest,
  }) => RenameFingerprint(
    folder: file.isFolder,
    // Several path-oriented adapters use the path as a UI UUID. Such aliases
    // change when renamed and cannot certify an interrupted mutation.
    objectId:
        file.uuid == null ||
            file.uuid!.isEmpty ||
            file.uuid == file.path ||
            file.uuid!.startsWith('/') ||
            RegExp(r'^[A-Za-z]:[\\/]').hasMatch(file.uuid!)
        ? null
        : file.uuid,
    version:
        file.metadata?['version']?.toString() ??
        file.metadata?['eTag']?.toString() ??
        file.metadata?['etag']?.toString(),
    size: file.size,
    modified: file.updatedAt,
    link: file.isSymlink == true,
    linkTarget: file.symlinkTarget,
    digest: digest,
  );

  bool matches(RenameFingerprint other, {bool afterMove = false}) {
    if (folder != other.folder || link != other.link) return false;
    if (objectId != null && objectId != other.objectId) return false;
    if (!afterMove && version != null && version != other.version) return false;
    if (link && linkTarget != null && linkTarget != other.linkTarget) {
      return false;
    }
    if (!folder && size != null && size != other.size) return false;
    if (!folder &&
        !afterMove &&
        modified != null &&
        (other.modified == null ||
            !modified!.isAtSameMomentAs(other.modified!))) {
      return false;
    }
    if (digest != null && digest != other.digest) return false;
    return true;
  }

  /// Auto-reconciliation after an interrupted write requires stable identity
  /// or a content digest, not merely a coincidentally equal size/date.
  bool get canReconcile => objectId != null || digest != null;

  Map<String, dynamic> toJson() => {
    'folder': folder,
    'link': link,
    if (objectId != null) 'objectId': objectId,
    if (version != null) 'version': version,
    if (size != null) 'size': size,
    if (modified != null) 'modified': modified!.toUtc().toIso8601String(),
    if (linkTarget != null) 'linkTarget': linkTarget,
    if (digest != null) 'digest': digest,
  };

  factory RenameFingerprint.fromJson(Map<String, dynamic> value) =>
      RenameFingerprint(
        folder: value['folder'] == true,
        link: value['link'] == true,
        objectId: value['objectId'] as String?,
        version: value['version'] as String?,
        size: value['size'] as int?,
        modified: DateTime.tryParse(value['modified'] as String? ?? ''),
        linkTarget: value['linkTarget'] as String?,
        digest: value['digest'] as String?,
      );
}

class RenameBatchItem {
  RenameBatchItem({
    required this.sourcePath,
    required this.targetPath,
    required this.currentPath,
    required this.fingerprint,
    this.error,
  });

  final String sourcePath;
  final String targetPath;
  String currentPath;
  RenameFingerprint fingerprint;
  String? error;

  FileItem asFile(String name, {String? storageId}) => FileItem(
    name: name,
    path: currentPath,
    uuid: fingerprint.objectId,
    storageId: storageId,
    isFolder: fingerprint.folder,
    size: fingerprint.size,
    updatedAt: fingerprint.modified,
    isSymlink: fingerprint.link,
    symlinkTarget: fingerprint.linkTarget,
    metadata: {if (fingerprint.version != null) 'version': fingerprint.version},
  );

  Map<String, dynamic> toJson() => {
    'source': sourcePath,
    'target': targetPath,
    'current': currentPath,
    'fingerprint': fingerprint.toJson(),
    if (error != null) 'error': error,
  };
  factory RenameBatchItem.fromJson(Map<String, dynamic> value) =>
      RenameBatchItem(
        sourcePath: value['source'] as String,
        targetPath: value['target'] as String,
        currentPath: value['current'] as String,
        fingerprint: RenameFingerprint.fromJson(
          Map<String, dynamic>.from(value['fingerprint'] as Map),
        ),
        error: value['error'] as String?,
      );
}

class RenameBatchStep {
  RenameBatchStep({
    required this.itemIndex,
    required this.from,
    required this.to,
    required this.kind,
    this.state = RenameStepState.pending,
    this.before,
    this.after,
    this.copied,
  });

  final int itemIndex;
  final String from;
  final String to;
  final RenameStepKind kind;
  RenameStepState state;
  RenameFingerprint? before;
  RenameFingerprint? after;

  /// Confirmed exclusive copy, persisted before conditionally deleting its
  /// source. Applies to the currently in-flight direction (rename or restore).
  RenameFingerprint? copied;

  Map<String, dynamic> toJson() => {
    'item': itemIndex,
    'from': from,
    'to': to,
    'kind': kind.name,
    'state': state.name,
    if (before != null) 'before': before!.toJson(),
    if (after != null) 'after': after!.toJson(),
    if (copied != null) 'copied': copied!.toJson(),
  };
  factory RenameBatchStep.fromJson(Map<String, dynamic> value) =>
      RenameBatchStep(
        itemIndex: value['item'] as int,
        from: value['from'] as String,
        to: value['to'] as String,
        kind: RenameStepKind.values.byName(value['kind'] as String),
        state: RenameStepState.values.byName(value['state'] as String),
        before: value['before'] is Map
            ? RenameFingerprint.fromJson(
                Map<String, dynamic>.from(value['before'] as Map),
              )
            : null,
        after: value['after'] is Map
            ? RenameFingerprint.fromJson(
                Map<String, dynamic>.from(value['after'] as Map),
              )
            : null,
        copied: value['copied'] is Map
            ? RenameFingerprint.fromJson(
                Map<String, dynamic>.from(value['copied'] as Map),
              )
            : null,
      );
}

class RenameBatchRecord {
  RenameBatchRecord({
    required this.id,
    required this.storage,
    required this.created,
    required this.items,
    required this.steps,
    required this.windowsPaths,
    required this.caseSensitivePaths,
    required this.exclusiveMoves,
    this.state = RenameBatchState.prepared,
    this.message,
    this.restoring = false,
    this.options = const {},
    List<String>? manualResolutions,
  }) : manualResolutions = manualResolutions ?? [];

  final String id;
  final StorageReference storage;
  final DateTime created;
  final List<RenameBatchItem> items;
  final List<RenameBatchStep> steps;
  final bool windowsPaths;
  final bool caseSensitivePaths;
  final bool exclusiveMoves;
  final Map<String, dynamic> options;
  final List<String> manualResolutions;
  RenameBatchState state;
  String? message;
  bool restoring;

  bool get isComplete => state == RenameBatchState.completed;
  bool get isRestored => state == RenameBatchState.restored;
  bool get canRestore =>
      !isRestored &&
      steps.any(
        (step) =>
            step.state != RenameStepState.pending &&
            step.state != RenameStepState.restored,
      );
  int get changedCount =>
      items.where((item) => item.sourcePath != item.targetPath).length;
  int get completedSteps =>
      steps.where((step) => step.state == RenameStepState.completed).length;

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'storage': storage.toJson(),
    'created': created.toUtc().toIso8601String(),
    'windowsPaths': windowsPaths,
    'caseSensitivePaths': caseSensitivePaths,
    'exclusiveMoves': exclusiveMoves,
    'state': state.name,
    'restoring': restoring,
    if (message != null) 'message': message,
    'items': items.map((item) => item.toJson()).toList(),
    'steps': steps.map((step) => step.toJson()).toList(),
    'options': options,
    'manualResolutions': manualResolutions,
  };

  factory RenameBatchRecord.fromJson(Map<String, dynamic> value) {
    if (value['schema'] != 1) {
      throw const FormatException('Unsupported rename journal version.');
    }
    final record = RenameBatchRecord(
      id: value['id'] as String,
      storage: StorageReference.fromJson(
        Map<String, dynamic>.from(value['storage'] as Map),
      ),
      created: DateTime.parse(value['created'] as String),
      windowsPaths: value['windowsPaths'] == true,
      caseSensitivePaths: value['caseSensitivePaths'] == true,
      exclusiveMoves: value['exclusiveMoves'] == true,
      state: RenameBatchState.values.byName(value['state'] as String),
      restoring: value['restoring'] == true,
      message: value['message'] as String?,
      items: (value['items'] as List)
          .map(
            (item) => RenameBatchItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      steps: (value['steps'] as List)
          .map(
            (step) => RenameBatchStep.fromJson(
              Map<String, dynamic>.from(step as Map),
            ),
          )
          .toList(),
      options: value['options'] is Map
          ? Map<String, dynamic>.from(value['options'] as Map)
          : const {},
      manualResolutions: (value['manualResolutions'] as List?)
          ?.whereType<String>()
          .toList(),
    );
    if (record.steps.any(
      (step) => step.itemIndex < 0 || step.itemIndex >= record.items.length,
    )) {
      throw const FormatException('Invalid rename journal item reference.');
    }
    return record;
  }

  RenameBatchRecord copy() => RenameBatchRecord.fromJson(toJson());
}

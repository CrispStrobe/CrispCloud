// lib/services/action_history_service.dart
//
// Action history with undo support for file operations.
//
// Usage:
//   final svc = ActionHistoryService();
//   final id = svc.record(ActionRecord(...));
//   await svc.undo(id, client: ..., localFileService: ...);

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Enums & model
// ---------------------------------------------------------------------------

enum ActionType {
  delete,
  rename,
  move,
  copy,
  createFolder,
}

/// A single recorded file-operation that may be undone.
class ActionRecord {
  /// Unique identifier for this action.
  final String id;

  /// When the action was performed.
  final DateTime timestamp;

  /// What kind of operation was performed.
  final ActionType type;

  /// Path of the file/folder before the operation.
  ///
  /// - delete   : path that was deleted
  /// - rename   : path before rename  (e.g. /dir/oldName)
  /// - move     : path before move    (e.g. /src/file.txt)
  /// - copy     : path of the copy that was created  (e.g. /dst/file.txt)
  /// - createFolder: path that was created
  final String originalPath;

  /// Path after the operation (null for delete/createFolder).
  ///
  /// - rename  : new full path        (e.g. /dir/newName)
  /// - move    : new full path        (e.g. /dst/file.txt)
  /// - copy    : source file path     (e.g. /src/file.txt)
  final String? newPath;

  /// Provider name ("local", "filen", etc.).
  final String provider;

  /// Extra context stored at record time for display purposes.
  final Map<String, dynamic> metadata;

  ActionRecord({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.originalPath,
    this.newPath,
    required this.provider,
    this.metadata = const {},
  });

  /// Human-readable description of the action.
  String get description {
    switch (type) {
      case ActionType.delete:
        return 'Deleted ${p.basename(originalPath)}';
      case ActionType.rename:
        final oldName = p.basename(originalPath);
        final newName = newPath != null ? p.basename(newPath!) : '?';
        return 'Renamed $oldName → $newName';
      case ActionType.move:
        return 'Moved ${p.basename(originalPath)}';
      case ActionType.copy:
        return 'Copied ${p.basename(originalPath)}';
      case ActionType.createFolder:
        return 'Created folder ${p.basename(originalPath)}';
    }
  }
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// Outcome of an undo attempt.
class UndoResult {
  final bool success;
  final String message;

  const UndoResult.success(this.message) : success = true;
  const UndoResult.failure(this.message) : success = false;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Maintains an in-memory list of recent file actions and can reverse them.
///
/// The service is intentionally thin — it delegates the actual filesystem/
/// remote calls back to the caller via the [UndoContext] parameter so that it
/// remains independent of any specific cloud client.
class ActionHistoryService {
  static final _log = Log('ActionHistoryService');
  static const int _maxHistory = 50;

  final _uuid = const Uuid();
  final List<ActionRecord> _history = [];

  // --- Public API ----------------------------------------------------------

  /// All recorded actions, most-recent first.
  List<ActionRecord> get history => List.unmodifiable(_history.reversed.toList());

  /// Record a new action and return its assigned id.
  String record(ActionRecord action) {
    _log.info('Recording action', {
      'type': action.type.name,
      'path': action.originalPath,
      'provider': action.provider,
    });
    _history.add(action);
    // Trim to max size (drop oldest entries from the front)
    while (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
    return action.id;
  }

  /// Convenience factory: create a new id and record in one call.
  String recordNew({
    required ActionType type,
    required String originalPath,
    String? newPath,
    required String provider,
    Map<String, dynamic> metadata = const {},
  }) {
    final action = ActionRecord(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      type: type,
      originalPath: originalPath,
      newPath: newPath,
      provider: provider,
      metadata: Map.unmodifiable(metadata),
    );
    return record(action);
  }

  /// Return true if [action] can be undone given the current environment.
  bool canUndo(ActionRecord action) {
    if (kIsWeb && action.provider == 'local') return false;
    switch (action.type) {
      case ActionType.delete:
        // Delete undo is only possible for remote providers (trash restore).
        // For local we cannot restore without a trash directory — report false.
        return action.provider != 'local';
      case ActionType.rename:
      case ActionType.move:
      case ActionType.createFolder:
      case ActionType.copy:
        return true;
    }
  }

  /// Attempt to undo [actionId].
  ///
  /// The caller supplies [context] so this service never imports cloud clients
  /// or flutter widgets directly.
  Future<UndoResult> undo(String actionId, UndoContext context) async {
    final idx = _history.indexWhere((a) => a.id == actionId);
    if (idx == -1) {
      return const UndoResult.failure('Action not found in history.');
    }

    final action = _history[idx];

    if (!canUndo(action)) {
      return UndoResult.failure(
        'Cannot undo ${action.type.name} on provider "${action.provider}". '
        'Operation is not reversible.',
      );
    }

    _log.info('Undoing action', {
      'id': actionId,
      'type': action.type.name,
      'path': action.originalPath,
    });

    try {
      final result = await _performUndo(action, context);
      if (result.success) {
        _history.removeAt(idx);
        _log.info('Undo successful', {'type': action.type.name});
      } else {
        _log.warn('Undo failed: ${result.message}');
      }
      return result;
    } catch (e, st) {
      _log.error('Undo threw an exception', e, st);
      return UndoResult.failure('Undo failed: $e');
    }
  }

  /// Clear all history.
  void clear() {
    _history.clear();
    _log.info('Action history cleared');
  }

  // --- Private helpers -----------------------------------------------------

  Future<UndoResult> _performUndo(
    ActionRecord action,
    UndoContext ctx,
  ) async {
    switch (action.type) {
      // ---- delete --------------------------------------------------------
      case ActionType.delete:
        // Remote providers may support trash restore via their client.
        if (ctx.restoreFromTrash != null) {
          await ctx.restoreFromTrash!(action.originalPath);
          return UndoResult.success('Restored ${p.basename(action.originalPath)} from trash.');
        }
        return const UndoResult.failure(
          'Cannot undo delete: provider does not support trash restore.',
        );

      // ---- rename --------------------------------------------------------
      case ActionType.rename:
        // newPath holds the path after renaming.
        // We rename it back to originalPath (i.e. original name).
        if (action.newPath == null) {
          return const UndoResult.failure('Cannot undo rename: new path unknown.');
        }
        if (action.provider == 'local') {
          await _localRename(action.newPath!, action.originalPath);
        } else {
          if (ctx.remoteRename == null) {
            return const UndoResult.failure('Cannot undo rename: no remote rename handler.');
          }
          final originalName = p.basename(action.originalPath);
          await ctx.remoteRename!(action.newPath!, originalName);
        }
        return UndoResult.success(
          'Renamed ${p.basename(action.newPath!)} back to ${p.basename(action.originalPath)}.',
        );

      // ---- move ----------------------------------------------------------
      case ActionType.move:
        // originalPath is the source (before move).
        // newPath is the destination path (after move).
        if (action.newPath == null) {
          return const UndoResult.failure('Cannot undo move: destination unknown.');
        }
        if (action.provider == 'local') {
          await _localRename(action.newPath!, action.originalPath);
        } else {
          if (ctx.remoteMove == null) {
            return const UndoResult.failure('Cannot undo move: no remote move handler.');
          }
          final originalDir = p.dirname(action.originalPath);
          await ctx.remoteMove!(action.newPath!, originalDir);
        }
        return UndoResult.success(
          'Moved ${p.basename(action.originalPath)} back to ${p.dirname(action.originalPath)}.',
        );

      // ---- createFolder --------------------------------------------------
      case ActionType.createFolder:
        if (action.provider == 'local') {
          final dir = Directory(action.originalPath);
          if (await dir.exists()) {
            await dir.delete(recursive: false);
          }
        } else {
          if (ctx.remoteDelete == null) {
            return const UndoResult.failure('Cannot undo create folder: no remote delete handler.');
          }
          await ctx.remoteDelete!(action.originalPath);
        }
        return UndoResult.success(
          'Deleted folder ${p.basename(action.originalPath)}.',
        );

      // ---- copy ----------------------------------------------------------
      case ActionType.copy:
        // originalPath for copy records is the path of the newly created copy.
        if (action.provider == 'local') {
          final entity = File(action.originalPath);
          if (await entity.exists()) {
            await entity.delete();
          } else {
            final dir = Directory(action.originalPath);
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          }
        } else {
          if (ctx.remoteDelete == null) {
            return const UndoResult.failure('Cannot undo copy: no remote delete handler.');
          }
          await ctx.remoteDelete!(action.originalPath);
        }
        return UndoResult.success(
          'Deleted copy ${p.basename(action.originalPath)}.',
        );
    }
  }

  Future<void> _localRename(String fromPath, String toPath) async {
    final fromFile = File(fromPath);
    final fromDir = Directory(fromPath);
    if (await fromFile.exists()) {
      await fromFile.rename(toPath);
    } else if (await fromDir.exists()) {
      await fromDir.rename(toPath);
    } else {
      throw FileSystemException('Source not found for local rename', fromPath);
    }
  }
}

// ---------------------------------------------------------------------------
// UndoContext — passed by the caller so the service stays dependency-free
// ---------------------------------------------------------------------------

/// Callbacks the service uses when executing undo operations.
///
/// All fields are optional. Supply only the ones relevant to the panel's
/// provider type.
class UndoContext {
  /// Restore a remote file from the provider's trash by its original path.
  final Future<void> Function(String path)? restoreFromTrash;

  /// Rename a remote file: [currentPath] to a new [name] (basename only).
  final Future<void> Function(String currentPath, String name)? remoteRename;

  /// Move a remote file to [targetDirectory].
  final Future<void> Function(String currentPath, String targetDirectory)? remoteMove;

  /// Delete a remote path.
  final Future<void> Function(String path)? remoteDelete;

  const UndoContext({
    this.restoreFromTrash,
    this.remoteRename,
    this.remoteMove,
    this.remoteDelete,
  });
}

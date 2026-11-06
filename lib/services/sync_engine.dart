// lib/services/sync_engine.dart
//
// Core sync engine: compares local filesystem state against remote provider
// state and the last-known sync state in the database. Produces a list of
// actions (upload, download, delete, conflict) then executes them.
//
// The engine is provider-agnostic — it takes a CloudStorageClient and works
// with any provider that implements the interface.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:glob/glob.dart' as globpkg;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'storage_identity.dart';
import 'sync_transfer_service.dart';
import 'transfer_journal.dart';
import 'transfer_recovery_service.dart';
import 'log_service.dart';
import 'placeholder_service.dart';
import 'sync_database.dart';
import 'sync_source_binding.dart';

/// A single action the sync engine wants to perform.
class SyncAction {
  final SyncActionType type;
  final String relativePath;
  final bool isFolder;
  final SyncEntry? dbEntry;

  /// For conflicts: the local and remote modification times.
  final DateTime? localModified;
  final DateTime? remoteModified;

  /// Remote content hash for delta sync (stored in DB after sync).
  final String? remoteContentHash;

  /// Remote file size (used for placeholder creation).
  final int? remoteSize;

  SyncAction({
    required this.type,
    required this.relativePath,
    this.isFolder = false,
    this.dbEntry,
    this.localModified,
    this.remoteModified,
    this.remoteContentHash,
    this.remoteSize,
  });

  @override
  String toString() =>
      'SyncAction($type, $relativePath${isFolder ? ' [dir]' : ''})';
}

enum SyncActionType {
  upload, // local file is new or modified → push to remote
  download, // remote file is new or modified → pull to local
  deleteLocal, // file was deleted on remote → delete locally
  deleteRemote, // file was deleted locally → delete on remote
  keepBoth, // preserve local under a new name and retain remote original
  conflict, // both sides changed → needs resolution
  createLocalFolder,
  createRemoteFolder,
  skip, // no action needed (already synced)
}

/// Result of a sync run.
class SyncResult {
  final int uploaded;
  final int downloaded;
  final int deletedLocal;
  final int deletedRemote;
  final int conflicts;
  final int errors;

  /// Offline actions successfully completed, including rename/move/delete.
  final int replayed;
  final List<String> errorMessages;
  final bool cancelled;

  const SyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
    this.conflicts = 0,
    this.errors = 0,
    this.replayed = 0,
    this.errorMessages = const [],
    this.cancelled = false,
  });

  SyncResult operator +(SyncResult other) => SyncResult(
    uploaded: uploaded + other.uploaded,
    downloaded: downloaded + other.downloaded,
    deletedLocal: deletedLocal + other.deletedLocal,
    deletedRemote: deletedRemote + other.deletedRemote,
    conflicts: conflicts + other.conflicts,
    errors: errors + other.errors,
    replayed: replayed + other.replayed,
    errorMessages: [...errorMessages, ...other.errorMessages],
    cancelled: cancelled || other.cancelled,
  );

  bool get hasChanges =>
      uploaded +
          downloaded +
          deletedLocal +
          deletedRemote +
          conflicts +
          replayed >
      0;

  @override
  String toString() =>
      'SyncResult(up:$uploaded down:$downloaded delL:$deletedLocal delR:$deletedRemote conflicts:$conflicts errors:$errors)';
}

/// A read-only comparison snapshot. Decisions are supplied separately at
/// execution, so changing a dropdown never mutates the scanned evidence.
class SyncPlan {
  SyncPlan._(
    this.pair,
    this.client,
    this.actions,
    this._local,
    this._remote,
    this._fingerprints,
    this._isCurrent,
    this._adopted,
    this.localSource,
    this.remoteSource,
  );
  final SyncPair pair;
  final CloudStorageClient client;
  final FileOperationBackend localSource;
  final FileOperationBackend remoteSource;
  final List<SyncAction> actions;
  final Map<String, _FileInfo> _local;
  final Map<String, _FileInfo> _remote;
  final Map<String, String> _fingerprints;
  final bool Function() _isCurrent;
  final List<String> _adopted;
  bool get isCurrent => _isCurrent();

  List<SyncActionType> choicesFor(SyncAction action) {
    final local = _local[action.relativePath];
    final remote = _remote[action.relativePath];
    final choices = <SyncActionType>{SyncActionType.skip, action.type};
    if (local != null && remote != null && local.isFolder != remote.isFolder) {
      return [SyncActionType.skip, SyncActionType.conflict];
    }
    if (local != null && !local.isFolder && pair.direction != 'downloadOnly') {
      choices.add(SyncActionType.upload);
    }
    if (remote != null && !remote.isFolder && pair.direction != 'uploadOnly') {
      choices.add(SyncActionType.download);
    }
    if (local != null &&
        remote != null &&
        !local.isFolder &&
        pair.direction == 'twoWay') {
      choices.add(SyncActionType.keepBoth);
    }
    return choices.toList();
  }
}

class SyncEngine {
  static const _log = Log('SyncEngine');

  final SyncDatabase db;

  SyncEngine(this.db, {LocalFileService? local, TransferJournal? journal})
    : _localService = local ?? LocalFileService(),
      _transfers = SyncTransferService(journal: journal);
  final LocalFileService _localService;
  final SyncTransferService _transfers;

  /// Check if a relative path passes the include/exclude filters for a pair.
  ///
  /// If include patterns are set, the path must match at least one.
  /// If exclude patterns are set, the path must not match any.
  static bool passesFilter(
    String relativePath,
    String includePatterns,
    String excludePatterns,
  ) {
    // Parse patterns (comma-separated, trim whitespace, skip empty)
    final includes = includePatterns
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final excludes = excludePatterns
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Check excludes first
    for (final pattern in excludes) {
      if (globpkg.Glob(pattern).matches(relativePath)) return false;
    }

    // If no include patterns, everything passes
    if (includes.isEmpty) return true;

    // Must match at least one include pattern
    for (final pattern in includes) {
      if (globpkg.Glob(pattern).matches(relativePath)) return true;
    }
    return false;
  }

  /// Run a full sync for a given pair.
  ///
  /// 1. Scan local filesystem
  /// 2. Scan remote via CloudStorageClient
  /// 3. Compare against last-known state in DB
  /// 4. Produce actions (upload/download/delete/conflict)
  /// 5. Apply conflict policy
  /// 6. Execute actions
  /// 7. Update DB state
  Future<SyncResult> syncPair(
    SyncPair pair,
    CloudStorageClient client, {
    bool Function()? isCurrent,
  }) async {
    final plan = await planPair(
      pair,
      client,
      isCurrent: isCurrent,
      verifyContents: true,
    );
    return executePlan(plan);
  }

  /// Scan and compare only. This method never writes files or sync metadata.
  Future<SyncPlan> planPair(
    SyncPair pair,
    CloudStorageClient client, {
    bool Function()? isCurrent,
    bool Function()? isCancelled,
    bool verifyContents = true,
  }) async {
    final binding = SyncSourceBinding.require(pair, client);
    await _assertSavedPair(pair);
    final account = storageReferenceForClient(client);
    bool current() =>
        (isCurrent?.call() ?? true) &&
        client.isAuthenticated &&
        storageReferenceForClient(client) == account &&
        binding.matches(pair, client);
    void check() {
      if (isCancelled?.call() ?? false) throw const SyncCancelledException();
      if (!current()) throw StateError('The synchronization source changed.');
    }

    final localSource = LocalOperationBackend(
      _localService,
      isCurrent: current,
    );
    final remoteSource = CloudOperationBackend(client, isCurrent: current);
    check();
    if (!p.isAbsolute(pair.localPath) || !p.posix.isAbsolute(pair.remotePath)) {
      throw const FormatException('Sync roots must be absolute paths.');
    }
    _log.info('Starting sync for "${pair.name}"');
    final policy = ConflictPolicy.values.firstWhere(
      (p) => p.name == pair.conflictPolicy,
      orElse: () => ConflictPolicy.newestWins,
    );
    final direction = SyncDirection.values.firstWhere(
      (d) => d.name == pair.direction,
      orElse: () => SyncDirection.twoWay,
    );

    // 1. Scan local
    final localFiles = await _scan(
      localSource,
      pair.localPath,
      local: true,
      check: check,
    );

    // 2. Scan remote
    final remoteFiles = await _scan(
      remoteSource,
      pair.remotePath,
      check: check,
    );

    // 3. Load last-known state from DB
    final dbEntries = await db.getEntriesForPair(pair.id);
    final dbMap = <String, SyncEntry>{};
    for (final e in dbEntries) {
      dbMap[e.relativePath] = e;
    }

    // 4. Compute actions (applying selective sync filters)
    final includePatterns = pair.includePatterns;
    final excludePatterns = pair.excludePatterns;
    final hasFilters = includePatterns.isNotEmpty || excludePatterns.isNotEmpty;

    final allPaths = <String>{
      ...localFiles.keys,
      ...remoteFiles.keys,
      ...dbMap.keys,
    };

    final actions = <SyncAction>[];
    for (final path in allPaths) {
      // Apply selective sync filters
      if (hasFilters && !passesFilter(path, includePatterns, excludePatterns)) {
        continue;
      }
      final local = localFiles[path];
      final remote = remoteFiles[path];
      final known = dbMap[path];

      final action = _computeAction(
        path,
        local,
        remote,
        known,
        policy: policy,
        direction: direction,
      );
      if (action.type != SyncActionType.skip) {
        actions.add(action);
      }
    }

    check();
    final fingerprints = verifyContents
        ? await _fingerprint(
            pair,
            localSource,
            remoteSource,
            localFiles,
            remoteFiles,
            actions.map((action) => action.relativePath),
            check,
          )
        : <String, String>{};
    final adopted = <String>[];
    if (verifyContents) {
      actions.removeWhere((action) {
        final local = fingerprints['local:${action.relativePath}'];
        final remote = fingerprints['remote:${action.relativePath}'];
        if (local != null && local == remote) {
          adopted.add(action.relativePath);
          return true;
        }
        return false;
      });
    }
    return SyncPlan._(
      pair,
      client,
      List.unmodifiable(actions),
      localFiles,
      remoteFiles,
      fingerprints,
      current,
      adopted,
      localSource,
      remoteSource,
    );
  }

  /// Execute only a reviewed snapshot, rejecting changed sources before the
  /// first write. Deletions happen last and directories must be empty.
  Future<SyncResult> executePlan(
    SyncPlan plan, {
    Map<String, SyncActionType> decisions = const {},
    bool Function()? isCancelled,
    void Function(int completed, int total, String path)? onProgress,
  }) async {
    void check() {
      if (isCancelled?.call() ?? false) throw const SyncCancelledException();
      if (!plan.isCurrent) {
        throw StateError('The synchronization source changed. Compare again.');
      }
    }

    final control = _SyncOperationControl(check);
    // Also wake a stream stalled between chunks. Merely inspecting the next
    // chunk would leave a stopped sync waiting for a provider indefinitely.
    final cancellation = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if ((isCancelled?.call() ?? false) || !plan.isCurrent) control.cancel();
    });
    var result = const SyncResult();
    try {
      check();
      await _assertSavedPair(plan.pair);
      final local = await _scan(
        plan.localSource,
        plan.pair.localPath,
        local: true,
        check: check,
      );
      final remote = await _scan(
        plan.remoteSource,
        plan.pair.remotePath,
        check: check,
      );
      if (!_sameTree(plan._local, local) || !_sameTree(plan._remote, remote)) {
        throw StateError(
          'Files changed after comparison. Compare again before synchronizing.',
        );
      }
      if (plan._fingerprints.isNotEmpty) {
        final fingerprints = await _fingerprint(
          plan.pair,
          plan.localSource,
          plan.remoteSource,
          local,
          remote,
          [
            ...plan.actions.map((action) => action.relativePath),
            ...plan._adopted,
          ],
          check,
          operationControl: control,
        );
        if (fingerprints.length != plan._fingerprints.length ||
            plan._fingerprints.entries.any(
              (entry) => fingerprints[entry.key] != entry.value,
            )) {
          throw StateError(
            'File contents changed after comparison. Compare again.',
          );
        }
      }
      final actions = <SyncAction>[];
      for (final action in plan.actions) {
        final type = decisions[action.relativePath] ?? action.type;
        if (!plan.choicesFor(action).contains(type)) {
          throw StateError('Unsupported decision for ${action.relativePath}.');
        }
        if (type != SyncActionType.skip) {
          actions.add(
            SyncAction(
              type: type,
              relativePath: action.relativePath,
              isFolder: action.isFolder,
              dbEntry: action.dbEntry,
              localModified: local[action.relativePath]?.modified,
              remoteModified: remote[action.relativePath]?.modified,
              remoteSize: remote[action.relativePath]?.size,
              remoteContentHash: remote[action.relativePath]?.contentHash,
            ),
          );
        }
      }
      int priority(SyncAction action) => switch (action.type) {
        SyncActionType.createLocalFolder ||
        SyncActionType.createRemoteFolder => 0,
        SyncActionType.deleteLocal || SyncActionType.deleteRemote => 2,
        _ => 1,
      };
      actions.sort((a, b) {
        final order = priority(a).compareTo(priority(b));
        if (order != 0) return order;
        final depth = a.relativePath
            .split('/')
            .length
            .compareTo(b.relativePath.split('/').length);
        if (depth != 0) return priority(a) == 2 ? -depth : depth;
        return a.relativePath.compareTo(b.relativePath);
      });
      var completed = 0;
      for (final action in actions) {
        check();
        await _validateRow(plan, action.relativePath, control, check);
        if (action.type == SyncActionType.conflict) {
          await db.upsertEntry(
            SyncEntriesCompanion.insert(
              pairId: plan.pair.id,
              relativePath: action.relativePath,
              status: const Value('conflict'),
              localModified: Value(action.localModified),
              remoteModified: Value(action.remoteModified),
              isFolder: Value(action.isFolder),
            ),
          );
          result += const SyncResult(conflicts: 1);
        } else {
          final step = await _executeAction(
            action,
            plan,
            control: control,
            check: check,
          );
          result += step;
          if (step.errors > 0 || step.cancelled) break;
        }
        completed++;
        onProgress?.call(completed, actions.length, action.relativePath);
      }
      if (result.errors == 0 && !result.cancelled) {
        for (final path in plan._adopted) {
          check();
          await _validateRow(plan, path, control, check);
          await _updateEntryAfterSync(
            plan.pair.id,
            path,
            (await plan.localSource.stat(p.join(plan.pair.localPath, path)))!,
            local[path]!.size,
            localHash: plan._fingerprints['local:$path'],
            remote: remote[path],
          );
        }
        await (db.update(db.syncPairs)
              ..where((table) => table.id.equals(plan.pair.id)))
            .write(SyncPairsCompanion(lastSyncAt: Value(DateTime.now())));
      }
    } on SyncCancelledException {
      return result + const SyncResult(cancelled: true);
    } on FileOperationCancelled {
      return result + const SyncResult(cancelled: true);
    } catch (error) {
      return result + SyncResult(errors: 1, errorMessages: [error.toString()]);
    } finally {
      cancellation.cancel();
    }
    return result;
  }

  bool _sameInfo(_FileInfo? first, _FileInfo? second) => first == null
      ? second == null
      : second != null &&
            first.isFolder == second.isFolder &&
            (first.isFolder ||
                first.size == second.size &&
                    first.modified == second.modified &&
                    first.contentHash == second.contentHash) &&
            (first.file == null ||
                second.file != null &&
                    sameTransferVersion(first.file!, second.file!));

  bool _sameTree(Map<String, _FileInfo> first, Map<String, _FileInfo> second) =>
      first.length == second.length &&
      first.entries.every((entry) => _sameInfo(entry.value, second[entry.key]));

  Future<void> _validateRow(
    SyncPlan plan,
    String path,
    FileOperationControl control,
    void Function() check,
  ) async {
    await _assertSavedPair(plan.pair);
    for (final (label, source, root, expected) in [
      ('local', plan.localSource, plan.pair.localPath, plan._local[path]),
      ('remote', plan.remoteSource, plan.pair.remotePath, plan._remote[path]),
    ]) {
      check();
      final item = await source.stat(
        source.paths.joinAll([root, ...path.split('/')]),
      );
      if (!_sameInfo(
        expected,
        item == null ? null : _FileInfo.fromItem(item),
      )) {
        throw StateError('$path changed after comparison. Compare again.');
      }
      final hash = plan._fingerprints['$label:$path'];
      if (hash != null &&
          await transferDigest(source, item!, control) != hash) {
        throw StateError(
          '$path contents changed after comparison. Compare again.',
        );
      }
    }
    check();
  }

  Future<Map<String, String>> _fingerprint(
    SyncPair pair,
    FileOperationBackend localSource,
    FileOperationBackend remoteSource,
    Map<String, _FileInfo> local,
    Map<String, _FileInfo> remote,
    Iterable<String> paths,
    void Function() check, {
    FileOperationControl? operationControl,
  }) async {
    final result = <String, String>{};
    final control = operationControl ?? _SyncOperationControl(check);
    final cancellation = operationControl == null
        ? Timer.periodic(const Duration(milliseconds: 50), (_) {
            try {
              check();
            } catch (_) {
              control.cancel();
            }
          })
        : null;
    try {
      for (final path in paths.toSet()) {
        for (final (label, source, info) in [
          ('local', localSource, local[path]),
          ('remote', remoteSource, remote[path]),
        ]) {
          check();
          if (info != null && !info.isFolder) {
            result['$label:$path'] = await transferDigest(
              source,
              info.file!,
              control,
            );
          }
        }
      }
      check();
      return result;
    } on FileOperationCancelled {
      check();
      rethrow;
    } finally {
      cancellation?.cancel();
    }
  }

  Future<void> _assertSavedPair(SyncPair pair) async {
    final saved = await db.getPair(pair.id);
    if (saved.sourceBinding != pair.sourceBinding ||
        saved.localPath != pair.localPath ||
        saved.remotePath != pair.remotePath) {
      throw StateError('The sync pair was rebound or changed. Compare again.');
    }
  }

  /// Determine what action to take for a given path.
  SyncAction _computeAction(
    String relativePath,
    _FileInfo? local,
    _FileInfo? remote,
    SyncEntry? known, {
    required ConflictPolicy policy,
    required SyncDirection direction,
  }) {
    final existsLocal = local != null;
    final existsRemote = remote != null;
    final existsInDb = known != null;

    // A cloud-only stub deliberately has no original local file. It must
    // never become a request to propagate a local deletion to cloud storage.
    if (known?.status == 'placeholder' && local == null) {
      return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
    }

    // Directories are containers, not conflicting byte streams. A file/folder
    // type conflict requires a deliberate decision; never overwrite either.
    if (local != null && remote != null) {
      if (local.isFolder != remote.isFolder) {
        return SyncAction(
          type: SyncActionType.conflict,
          relativePath: relativePath,
          dbEntry: known,
        );
      }
      if (local.isFolder) {
        return SyncAction(
          type: SyncActionType.skip,
          relativePath: relativePath,
        );
      }
    }

    if (known?.status == 'pendingUpload' && local != null && !local.isFolder) {
      return SyncAction(
        type: SyncActionType.upload,
        relativePath: relativePath,
        localModified: local.modified,
        dbEntry: known,
      );
    }
    if (known?.status == 'pendingDownload' &&
        remote != null &&
        !remote.isFolder) {
      return SyncAction(
        type: SyncActionType.download,
        relativePath: relativePath,
        remoteModified: remote.modified,
        remoteSize: remote.size,
        remoteContentHash: remote.contentHash,
        dbEntry: known,
      );
    }
    if (direction == SyncDirection.uploadOnly) {
      policy = ConflictPolicy.localWins;
    }
    if (direction == SyncDirection.downloadOnly) {
      policy = ConflictPolicy.remoteWins;
    }

    // --- New files (not in DB) ---
    if (!existsInDb) {
      if (existsLocal && existsRemote) {
        // Both exist but we've never seen them — treat as conflict or merge
        return _resolveConflict(relativePath, local, remote, known, policy);
      }
      if (existsLocal && !existsRemote) {
        // New local file → upload (if direction allows)
        if (direction == SyncDirection.downloadOnly) {
          return SyncAction(
            type: SyncActionType.skip,
            relativePath: relativePath,
          );
        }
        if (local.isFolder) {
          return SyncAction(
            type: SyncActionType.createRemoteFolder,
            relativePath: relativePath,
            isFolder: true,
          );
        }
        return SyncAction(
          type: SyncActionType.upload,
          relativePath: relativePath,
          localModified: local.modified,
        );
      }
      if (!existsLocal && existsRemote) {
        // New remote file → download
        if (direction == SyncDirection.uploadOnly) {
          return SyncAction(
            type: SyncActionType.skip,
            relativePath: relativePath,
          );
        }
        if (remote.isFolder) {
          return SyncAction(
            type: SyncActionType.createLocalFolder,
            relativePath: relativePath,
            isFolder: true,
          );
        }
        return SyncAction(
          type: SyncActionType.download,
          relativePath: relativePath,
          remoteModified: remote.modified,
          remoteContentHash: remote.contentHash,
          remoteSize: remote.size,
        );
      }
      return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
    }

    // --- Known files (in DB) ---

    // Deleted on both sides → clean up DB entry
    if (!existsLocal && !existsRemote) {
      return SyncAction(
        type: SyncActionType.skip,
        relativePath: relativePath,
        dbEntry: known,
      );
    }

    // Deleted locally, still exists remote → delete remote or re-download
    if (!existsLocal && existsRemote) {
      if (direction == SyncDirection.downloadOnly) {
        return SyncAction(
          type: SyncActionType.download,
          relativePath: relativePath,
          remoteModified: remote.modified,
          remoteContentHash: remote.contentHash,
          remoteSize: remote.size,
        );
      }
      // Check if remote was also modified since last sync
      if (known.remoteModified != null &&
          remote.modified != null &&
          remote.modified!.isAfter(known.remoteModified!)) {
        // Remote changed after our last sync — conflict
        return _resolveConflict(relativePath, local, remote, known, policy);
      }
      return SyncAction(
        type: SyncActionType.deleteRemote,
        relativePath: relativePath,
        dbEntry: known,
      );
    }

    // Deleted remotely, still exists local → delete local or re-upload
    if (existsLocal && !existsRemote) {
      if (direction == SyncDirection.uploadOnly) {
        return SyncAction(
          type: SyncActionType.upload,
          relativePath: relativePath,
          localModified: local.modified,
        );
      }
      if (known.localModified != null &&
          local.modified != null &&
          local.modified!.isAfter(known.localModified!)) {
        return _resolveConflict(relativePath, local, remote, known, policy);
      }
      return SyncAction(
        type: SyncActionType.deleteLocal,
        relativePath: relativePath,
        dbEntry: known,
      );
    }

    // Both exist — check for modifications
    final localChanged = _isModified(
      local!,
      known.localModified,
      known.localSize,
    );
    final remoteChanged = _isRemoteModified(
      remote!,
      known.remoteModified,
      known.remoteSize,
      knownHash: known.remoteHash,
    );

    if (!localChanged && !remoteChanged) {
      return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
    }

    if (localChanged && !remoteChanged) {
      if (direction == SyncDirection.downloadOnly) {
        return SyncAction(
          type: SyncActionType.skip,
          relativePath: relativePath,
        );
      }
      return SyncAction(
        type: SyncActionType.upload,
        relativePath: relativePath,
        localModified: local.modified,
      );
    }

    if (!localChanged && remoteChanged) {
      if (direction == SyncDirection.uploadOnly) {
        return SyncAction(
          type: SyncActionType.skip,
          relativePath: relativePath,
        );
      }
      return SyncAction(
        type: SyncActionType.download,
        relativePath: relativePath,
        remoteModified: remote.modified,
        remoteContentHash: remote.contentHash,
        remoteSize: remote.size,
      );
    }

    // Both changed → conflict
    return _resolveConflict(relativePath, local, remote, known, policy);
  }

  SyncAction _resolveConflict(
    String relativePath,
    _FileInfo? local,
    _FileInfo? remote,
    SyncEntry? known,
    ConflictPolicy policy,
  ) {
    if (policy != ConflictPolicy.manual && (local == null || remote == null)) {
      return SyncAction(
        type: local == null ? SyncActionType.download : SyncActionType.upload,
        relativePath: relativePath,
        localModified: local?.modified,
        remoteModified: remote?.modified,
        remoteSize: remote?.size,
        remoteContentHash: remote?.contentHash,
        dbEntry: known,
      );
    }
    switch (policy) {
      case ConflictPolicy.localWins:
        return SyncAction(
          type: SyncActionType.upload,
          relativePath: relativePath,
          localModified: local?.modified,
        );
      case ConflictPolicy.remoteWins:
        return SyncAction(
          type: SyncActionType.download,
          relativePath: relativePath,
          remoteModified: remote?.modified,
          remoteSize: remote?.size,
        );
      case ConflictPolicy.newestWins:
        final localTime = local?.modified ?? DateTime(1970);
        final remoteTime = remote?.modified ?? DateTime(1970);
        if (localTime.isAfter(remoteTime)) {
          return SyncAction(
            type: SyncActionType.upload,
            relativePath: relativePath,
            localModified: localTime,
          );
        } else {
          return SyncAction(
            type: SyncActionType.download,
            relativePath: relativePath,
            remoteModified: remoteTime,
            remoteSize: remote?.size,
          );
        }
      case ConflictPolicy.keepBoth:
        // A deletion conflict only has one surviving version to preserve.
        return SyncAction(
          type: local == null
              ? SyncActionType.download
              : remote == null
              ? SyncActionType.upload
              : SyncActionType.keepBoth,
          relativePath: relativePath,
          localModified: local?.modified,
          remoteModified: remote?.modified,
          remoteContentHash: remote?.contentHash,
          remoteSize: remote?.size,
          dbEntry: known,
        );
      case ConflictPolicy.manual:
        return SyncAction(
          type: SyncActionType.conflict,
          relativePath: relativePath,
          localModified: local?.modified,
          remoteModified: remote?.modified,
          dbEntry: known,
        );
    }
  }

  bool _isModified(_FileInfo file, DateTime? knownModified, int knownSize) {
    if (file.isFolder) return false;
    if (knownModified == null) return true;
    // Compare modification time (1-second tolerance) and size
    final timeDiff = file.modified != null
        ? file.modified!.difference(knownModified).inSeconds.abs()
        : 0;
    return timeDiff > 1 || file.size != knownSize;
  }

  bool _isRemoteModified(
    _FileInfo file,
    DateTime? knownModified,
    int knownSize, {
    String? knownHash,
  }) {
    if (file.isFolder) return false;
    if (knownModified == null) return true;

    // Delta sync: if both sides have content hashes, use those
    // (more reliable than timestamp comparison, and enables delta detection)
    if (file.contentHash != null && knownHash != null) {
      return file.contentHash != knownHash;
    }

    // Fallback: timestamp + size comparison
    final timeDiff = file.modified != null
        ? file.modified!.difference(knownModified).inSeconds.abs()
        : 0;
    return timeDiff > 1 || file.size != knownSize;
  }

  /// Execute the reviewed object through captured backends. Copy operations
  /// are streamed, staged and verified before replacing an existing file.
  Future<SyncResult> _executeAction(
    SyncAction action,
    SyncPlan plan, {
    required FileOperationControl control,
    required void Function() check,
  }) async {
    final pair = plan.pair;
    final localPath = plan.localSource.paths.joinAll([
      pair.localPath,
      ...action.relativePath.split('/'),
    ]);
    final remotePath = p.posix.join(pair.remotePath, action.relativePath);
    try {
      check();
      switch (action.type) {
        case SyncActionType.keepBoth:
          return await _keepBoth(action, plan, control: control, check: check);
        case SyncActionType.upload:
          final written = await _transfers.copy(
            source: plan.localSource,
            file: plan._local[action.relativePath]!.file!,
            destination: plan.remoteSource,
            destinationPath: remotePath,
            expectedDestination: plan._remote[action.relativePath]?.file,
            expectedSourceHash:
                plan._fingerprints['local:${action.relativePath}'],
            expectedDestinationHash:
                plan._fingerprints['remote:${action.relativePath}'],
            control: control,
            check: check,
          );
          check();
          await _updateEntryAfterSync(
            pair.id,
            action.relativePath,
            (await plan.localSource.stat(localPath))!,
            written.size ?? plan._local[action.relativePath]!.size,
            localHash: plan._fingerprints['local:${action.relativePath}'],
            remote: _FileInfo.fromItem(written),
          );
          return const SyncResult(uploaded: 1);
        case SyncActionType.download:
          if (pair.usePlaceholders &&
              action.dbEntry == null &&
              plan._local[action.relativePath] == null) {
            final placeholder = PlaceholderService(db);
            await placeholder.createPlaceholder(
              pairId: pair.id,
              localBasePath: pair.localPath,
              relativePath: action.relativePath,
              remotePath: remotePath,
              provider: pair.provider,
              sizeBytes: action.remoteSize ?? 0,
              remoteModified: action.remoteModified,
              contentHash: action.remoteContentHash,
            );
            return const SyncResult(downloaded: 1);
          }
          final written = await _transfers.copy(
            source: plan.remoteSource,
            file: plan._remote[action.relativePath]!.file!,
            destination: plan.localSource,
            destinationPath: localPath,
            expectedDestination: plan._local[action.relativePath]?.file,
            expectedSourceHash:
                plan._fingerprints['remote:${action.relativePath}'],
            expectedDestinationHash:
                plan._fingerprints['local:${action.relativePath}'],
            control: control,
            check: check,
          );
          check();
          await _updateEntryAfterSync(
            pair.id,
            action.relativePath,
            written,
            written.size ?? plan._remote[action.relativePath]!.size,
            localHash: plan._fingerprints['remote:${action.relativePath}'],
            remote: plan._remote[action.relativePath],
          );
          return const SyncResult(downloaded: 1);
        case SyncActionType.deleteLocal:
        case SyncActionType.deleteRemote:
          final source = action.type == SyncActionType.deleteLocal
              ? plan.localSource
              : plan.remoteSource;
          final item =
              (action.type == SyncActionType.deleteLocal
                      ? plan._local
                      : plan._remote)[action.relativePath]
                  ?.file;
          if (item != null) {
            check();
            if (item.isFolder) {
              // Never emulate this with a listing followed by recursive delete.
              // The backend must provide a nonrecursive empty-directory primitive.
              await source.deleteEmptyDirectory(item.path!);
            } else {
              await source.deleteFile(item);
            }
          }
          final existing = await db.getEntry(pair.id, action.relativePath);
          if (existing != null) {
            await (db.delete(
              db.syncEntries,
            )..where((table) => table.id.equals(existing.id))).go();
          }
          return action.type == SyncActionType.deleteLocal
              ? const SyncResult(deletedLocal: 1)
              : const SyncResult(deletedRemote: 1);
        case SyncActionType.createLocalFolder:
        case SyncActionType.createRemoteFolder:
          final source = action.type == SyncActionType.createLocalFolder
              ? plan.localSource
              : plan.remoteSource;
          final path = action.type == SyncActionType.createLocalFolder
              ? localPath
              : remotePath;
          await source.createDirectory(path);
          check();
          await db.upsertEntry(
            SyncEntriesCompanion.insert(
              pairId: pair.id,
              relativePath: action.relativePath,
              isFolder: const Value(true),
              status: const Value('synced'),
              lastSyncAt: Value(DateTime.now()),
            ),
          );
          return action.type == SyncActionType.createLocalFolder
              ? const SyncResult(downloaded: 1)
              : const SyncResult(uploaded: 1);
        case SyncActionType.conflict:
        case SyncActionType.skip:
          return const SyncResult();
      }
    } on SyncCancelledException {
      return const SyncResult(cancelled: true);
    } on FileOperationCancelled {
      return const SyncResult(cancelled: true);
    } catch (error) {
      _log.error('Error executing $action', error);
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: pair.id,
          relativePath: action.relativePath,
          status: const Value('error'),
          error: Value(error.toString()),
        ),
      );
      return SyncResult(
        errors: 1,
        errorMessages: ['${action.relativePath}: $error'],
      );
    }
  }

  Future<void> _updateEntryAfterSync(
    int pairId,
    String relativePath,
    FileItem local,
    int size, {
    String? localHash,
    String? remoteContentHash,
    DateTime? remoteModified,
    _FileInfo? remote,
  }) async {
    await db.upsertEntry(
      SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: relativePath,
        localModified: Value(local.updatedAt),
        localHash: Value(localHash),
        remoteModified: Value(remote?.modified ?? remoteModified),
        localSize: Value(size),
        remoteSize: Value(size),
        remoteHash: Value(remote?.contentHash ?? remoteContentHash),
        status: const Value('synced'),
        error: const Value(null),
        lastSyncAt: Value(DateTime.now()),
      ),
    );
  }

  Future<SyncResult> _keepBoth(
    SyncAction action,
    SyncPlan plan, {
    required FileOperationControl control,
    required void Function() check,
  }) async {
    final pair = plan.pair;
    final local = plan.localSource;
    final remote = plan.remoteSource;
    final original = plan._local[action.relativePath]!.file!;
    final remoteOriginal = plan._remote[action.relativePath]!.file!;
    final parent = p.posix.dirname(action.relativePath);
    final basename = p.posix.basenameWithoutExtension(action.relativePath);
    final extension = p.posix.extension(action.relativePath);
    var suffix = 1;
    late String copyRelative, localCopyPath, remoteCopyPath;
    while (true) {
      check();
      if (suffix > 10000) {
        throw StateError(
          'No unused conflict name was found after 10000 attempts.',
        );
      }
      final name =
          '$basename (local conflict${suffix == 1 ? '' : ' $suffix'})$extension';
      copyRelative = p.posix.normalize(p.posix.join(parent, name));
      localCopyPath = local.paths.joinAll([
        pair.localPath,
        ...copyRelative.split('/'),
      ]);
      remoteCopyPath = p.posix.join(pair.remotePath, copyRelative);
      if (await local.stat(localCopyPath) == null &&
          await remote.stat(remoteCopyPath) == null) {
        break;
      }
      suffix++;
    }
    // This verified recovery copy remains if a later cloud step fails. Neither
    // original is replaced until both conflict versions have been preserved.
    final copy = await _transfers.copy(
      source: local,
      file: original,
      destination: local,
      destinationPath: localCopyPath,
      expectedDestination: null,
      expectedSourceHash: plan._fingerprints['local:${action.relativePath}'],
      control: control,
      check: check,
    );
    await _validateRow(plan, action.relativePath, control, check);
    final remoteCopy = await _transfers.copy(
      source: local,
      file: copy,
      destination: remote,
      destinationPath: remoteCopyPath,
      expectedDestination: null,
      expectedSourceHash: plan._fingerprints['local:${action.relativePath}'],
      control: control,
      check: check,
    );
    await _updateEntryAfterSync(
      pair.id,
      copyRelative,
      copy,
      copy.size!,
      localHash: plan._fingerprints['local:${action.relativePath}'],
      remote: _FileInfo.fromItem(remoteCopy),
    );
    await _validateRow(plan, action.relativePath, control, check);
    final written = await _transfers.copy(
      source: remote,
      file: remoteOriginal,
      destination: local,
      destinationPath: original.path!,
      expectedDestination: original,
      expectedSourceHash: plan._fingerprints['remote:${action.relativePath}'],
      expectedDestinationHash:
          plan._fingerprints['local:${action.relativePath}'],
      control: control,
      check: check,
    );
    await _updateEntryAfterSync(
      pair.id,
      action.relativePath,
      written,
      written.size!,
      localHash: plan._fingerprints['remote:${action.relativePath}'],
      remote: plan._remote[action.relativePath],
    );
    return const SyncResult(uploaded: 1, downloaded: 1);
  }

  Future<Map<String, _FileInfo>> _scan(
    FileOperationBackend source,
    String root, {
    bool local = false,
    required void Function() check,
  }) async {
    check();
    root = source.paths.normalize(root);
    final directory = await source.stat(root);
    if (directory == null ||
        !directory.isFolder ||
        directory.isSymlink == true) {
      throw FileSystemException('Sync root is unavailable.', root);
    }
    final found = <String, _FileInfo>{};
    final seen = <String>{};
    Future<void> walk(String path, int depth) async {
      check();
      if (depth > 200 || found.length > 200000) {
        throw StateError('Sync tree exceeds supported traversal limits.');
      }
      if (!seen.add(source.pathKey(path))) {
        throw StateError('Repeated sync directory: $path');
      }
      for (final item in await source.list(path)) {
        check();
        // Private staged writes and verified replacement backups belong to
        // transfer recovery, never to the synchronized user tree.
        if (_transferArtifact.hasMatch(item.name)) continue;
        if (item.path == null ||
            !source.isWithin(root, item.path!) ||
            source.paths.dirname(item.path!) != path) {
          throw StateError(
            'Storage returned an unsafe sync path: ${item.path}',
          );
        }
        if (item.isSymlink == true) {
          throw UnsupportedError(
            'Synchronization does not follow symbolic links: ${item.path}',
          );
        }
        if (local &&
            (item.name.startsWith('.') ||
                PlaceholderService.isPlaceholder(item.name))) {
          continue;
        }
        final relative = source.paths
            .relative(item.path!, from: root)
            .replaceAll(source.paths.separator, '/');
        if (found.containsKey(relative)) {
          throw StateError('Ambiguous sync path: $relative');
        }
        found[relative] = _FileInfo.fromItem(item);
        if (item.isFolder) await walk(item.path!, depth + 1);
      }
    }

    await walk(root, 0);
    check();
    return found;
  }

  static final _transferArtifact = RegExp(
    r'^\.crisp-(?:transfer-[0-9a-f-]{36}\.tmp|replaced-[0-9a-f-]{36}\.bak)$',
  );
}

/// Internal file info record for comparison.
class _FileInfo {
  final bool isFolder;
  final DateTime? modified;
  final int size;

  /// Provider-supplied content hash (e.g. Dropbox content_hash, OneDrive crc32Hash).
  /// When available, enables delta sync — only transfer files whose hash changed.
  final String? contentHash;
  final FileItem? file;

  factory _FileInfo.fromItem(FileItem file) => _FileInfo(
    isFolder: file.isFolder,
    modified: file.updatedAt,
    size: file.size ?? 0,
    contentHash: (file.metadata?['content_hash'] ?? file.metadata?['crc32Hash'])
        ?.toString(),
    file: file,
  );

  const _FileInfo({
    required this.isFolder,
    this.modified,
    this.size = 0,
    this.contentHash,
    this.file,
  });
}

class SyncCancelledException implements Exception {
  const SyncCancelledException();
  @override
  String toString() => 'Synchronization cancelled.';
}

class _SyncOperationControl extends FileOperationControl {
  _SyncOperationControl(this.check);
  final void Function() check;
  @override
  Future<void> checkpoint() async {
    try {
      check();
      await super.checkpoint();
      check();
    } catch (_) {
      cancel();
      rethrow;
    }
  }
}

// lib/services/sync_engine.dart
//
// Core sync engine: compares local filesystem state against remote provider
// state and the last-known sync state in the database. Produces a list of
// actions (upload, download, delete, conflict) then executes them.
//
// The engine is provider-agnostic — it takes a CloudStorageClient and works
// with any provider that implements the interface.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart' as globpkg;
import 'package:path/path.dart' as p;

import 'cloud_storage_interface.dart';
import 'log_service.dart';
import 'placeholder_service.dart';
import 'sync_database.dart';

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
/// Retains the original error alongside the legacy string representation.
class SyncFailureDetail {
  const SyncFailureDetail({
    required this.location,
    this.cause,
    this.providerUnavailable = false,
    this.provider,
  });
  final String location;
  final Object? cause;
  final bool providerUnavailable;
  final String? provider;
}

class SyncResult {
  final int uploaded;
  final int downloaded;
  final int deletedLocal;
  final int deletedRemote;
  final int conflicts;
  final int errors;
  final List<String> errorMessages;
  final bool cancelled;
  final List<SyncFailureDetail> failureDetails;

  const SyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
    this.conflicts = 0,
    this.errors = 0,
    this.errorMessages = const [],
    this.cancelled = false,
    this.failureDetails = const [],
  });

  SyncResult operator +(SyncResult other) => SyncResult(
    uploaded: uploaded + other.uploaded,
    downloaded: downloaded + other.downloaded,
    deletedLocal: deletedLocal + other.deletedLocal,
    deletedRemote: deletedRemote + other.deletedRemote,
    conflicts: conflicts + other.conflicts,
    errors: errors + other.errors,
    errorMessages: [...errorMessages, ...other.errorMessages],
    cancelled: cancelled || other.cancelled,
    failureDetails: [...failureDetails, ...other.failureDetails],
  );

  bool get hasChanges =>
      uploaded + downloaded + deletedLocal + deletedRemote + conflicts > 0;

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
  );
  final SyncPair pair;
  final CloudStorageClient client;
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
        pair.direction == 'twoWay')
      choices.add(SyncActionType.keepBoth);
    return choices.toList();
  }
}

class SyncEngine {
  static const _log = Log('SyncEngine');

  final SyncDatabase db;

  SyncEngine(this.db);

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
      verifyContents: false,
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
    final account = client.userId;
    final bucket = client.bucketId;
    bool current() =>
        (isCurrent?.call() ?? true) &&
        client.isAuthenticated &&
        client.userId == account &&
        client.bucketId == bucket;
    void check() {
      if (isCancelled?.call() ?? false) throw const SyncCancelledException();
      if (!current()) throw StateError('The synchronization source changed.');
    }

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
    final localFiles = await _scanLocal(pair.localPath, check: check);

    // 2. Scan remote
    final remoteFiles = await _scanRemote(
      client,
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
            client,
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
      if (!plan.isCurrent)
        throw StateError('The synchronization source changed. Compare again.');
    }

    var result = const SyncResult();
    try {
      check();
      final local = await _scanLocal(plan.pair.localPath, check: check);
      final remote = await _scanRemote(
        plan.client,
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
          plan.client,
          local,
          remote,
          [
            ...plan.actions.map((action) => action.relativePath),
            ...plan._adopted,
          ],
          check,
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
        return priority(a) == 2 ? -depth : depth;
      });
      var completed = 0;
      for (final action in actions) {
        check();
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
            plan.pair,
            plan.client,
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
          await _updateEntryAfterSync(
            plan.pair.id,
            path,
            await File(p.join(plan.pair.localPath, path)).stat(),
            local[path]!.size,
            remote: remote[path],
          );
        }
        await (db.update(db.syncPairs)
              ..where((table) => table.id.equals(plan.pair.id)))
            .write(SyncPairsCompanion(lastSyncAt: Value(DateTime.now())));
      }
    } on SyncCancelledException {
      return result + const SyncResult(cancelled: true);
    } catch (error) {
      return result + SyncResult(errors: 1, errorMessages: [error.toString()]);
    }
    return result;
  }

  bool _sameTree(Map<String, _FileInfo> first, Map<String, _FileInfo> second) =>
      first.length == second.length &&
      first.entries.every((entry) {
        final other = second[entry.key];
        return other != null &&
            entry.value.isFolder == other.isFolder &&
            entry.value.size == other.size &&
            entry.value.modified == other.modified &&
            entry.value.contentHash == other.contentHash;
      });

  Future<Map<String, String>> _fingerprint(
    SyncPair pair,
    CloudStorageClient client,
    Map<String, _FileInfo> local,
    Map<String, _FileInfo> remote,
    Iterable<String> paths,
    void Function() check,
  ) async {
    final result = <String, String>{};
    for (final path in paths.toSet()) {
      check();
      if (local[path] != null && !local[path]!.isFolder) {
        result['local:$path'] =
            (await sha256
                    .bind(
                      File(p.join(pair.localPath, path))
                          .openRead()
                          .map((chunk) {
                            check();
                            return chunk;
                          }),
                    )
                    .first)
                .toString();
      }
      check();
      if (remote[path] != null && !remote[path]!.isFolder) {
        result['remote:$path'] =
            (await sha256
                    .bind(
                      client
                          .downloadStream(p.posix.join(pair.remotePath, path))
                          .map((chunk) {
                            check();
                            return chunk;
                          }),
                    )
                    .first)
                .toString();
      }
    }
    check();
    return result;
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
    if (direction == SyncDirection.uploadOnly)
      policy = ConflictPolicy.localWins;
    if (direction == SyncDirection.downloadOnly)
      policy = ConflictPolicy.remoteWins;

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

  /// Execute a single sync action.
  Future<SyncResult> _executeAction(
    SyncAction action,
    SyncPair pair,
    CloudStorageClient client, {
    void Function()? check,
  }) async {
    final localBase = pair.localPath;
    final remoteBase = pair.remotePath;
    final localPath = p.join(localBase, action.relativePath);
    final remotePath = p.posix.join(remoteBase, action.relativePath);

    try {
      check?.call();
      switch (action.type) {
        case SyncActionType.keepBoth:
          return await _keepBoth(action, pair, client, check: check);
        case SyncActionType.upload:
          final bytes = await File(localPath).readAsBytes();
          final fileName = p.basename(action.relativePath);
          final targetDir = p.posix.dirname(remotePath);
          check?.call();
          await client.uploadFile(bytes, fileName, targetDir);
          check?.call();
          final stat = await File(localPath).stat();
          await _updateEntryAfterSync(
            pair.id,
            action.relativePath,
            stat,
            bytes.length,
            remote: await _remoteInfo(client, remotePath),
          );
          return const SyncResult(uploaded: 1);

        case SyncActionType.download:
          // Placeholder mode: create stub instead of downloading (for new files only)
          if (pair.usePlaceholders && action.dbEntry == null) {
            final placeholder = PlaceholderService(db);
            await placeholder.createPlaceholder(
              pairId: pair.id,
              localBasePath: localBase,
              relativePath: action.relativePath,
              remotePath: remotePath,
              provider: pair.provider,
              sizeBytes: action.remoteSize ?? 0,
              remoteModified: action.remoteModified,
              contentHash: action.remoteContentHash,
            );
            return const SyncResult(downloaded: 1);
          }
          final bytes = await client.downloadFileBytes(remotePath);
          check?.call();
          final file = File(localPath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          final stat = await file.stat();
          await _updateEntryAfterSync(
            pair.id,
            action.relativePath,
            stat,
            bytes.length,
            remoteContentHash: action.remoteContentHash,
            remoteModified: action.remoteModified,
          );
          return const SyncResult(downloaded: 1);

        case SyncActionType.deleteLocal:
          final entity = FileSystemEntity.typeSync(localPath);
          if (entity == FileSystemEntityType.directory) {
            await Directory(localPath).delete();
          } else if (entity == FileSystemEntityType.file) {
            await File(localPath).delete();
          }
          final existing = await db.getEntry(pair.id, action.relativePath);
          if (existing != null) {
            await (db.delete(
              db.syncEntries,
            )..where((table) => table.id.equals(existing.id))).go();
          }
          return const SyncResult(deletedLocal: 1);

        case SyncActionType.deleteRemote:
          if (action.isFolder || action.dbEntry?.isFolder == true) {
            final listing = await client.listPath(remotePath);
            if (((listing['files'] as List?)?.isNotEmpty ?? false) ||
                ((listing['folders'] as List?)?.isNotEmpty ?? false)) {
              throw StateError(
                'Directory is not empty; refusing recursive deletion: $remotePath',
              );
            }
          }
          check?.call();
          await client.deletePath(remotePath);
          // Remove from DB
          final existing = await db.getEntry(pair.id, action.relativePath);
          if (existing != null) {
            await (db.delete(
              db.syncEntries,
            )..where((t) => t.id.equals(existing.id))).go();
          }
          return const SyncResult(deletedRemote: 1);

        case SyncActionType.createLocalFolder:
          await Directory(localPath).create(recursive: true);
          await db.upsertEntry(
            SyncEntriesCompanion.insert(
              pairId: pair.id,
              relativePath: action.relativePath,
              isFolder: const Value(true),
              status: const Value('synced'),
              lastSyncAt: Value(DateTime.now()),
            ),
          );
          return const SyncResult(downloaded: 1);

        case SyncActionType.createRemoteFolder:
          await client.createFolderPath(remotePath);
          await db.upsertEntry(
            SyncEntriesCompanion.insert(
              pairId: pair.id,
              relativePath: action.relativePath,
              isFolder: const Value(true),
              status: const Value('synced'),
              lastSyncAt: Value(DateTime.now()),
            ),
          );
          return const SyncResult(uploaded: 1);

        case SyncActionType.conflict:
        case SyncActionType.skip:
          return const SyncResult();
      }
    } on SyncCancelledException {
      return const SyncResult(cancelled: true);
    } catch (e) {
      _log.error('Error executing $action', e);
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: pair.id,
          relativePath: action.relativePath,
          status: const Value('error'),
          error: Value(e.toString()),
        ),
      );
      return SyncResult(
        errors: 1,
        errorMessages: ['${action.relativePath}: $e'],
        failureDetails: [
          SyncFailureDetail(location: action.relativePath, cause: e),
        ],
      );
    }
  }

  Future<void> _updateEntryAfterSync(
    int pairId,
    String relativePath,
    FileStat stat,
    int size, {
    String? remoteContentHash,
    DateTime? remoteModified,
    _FileInfo? remote,
  }) async {
    await db.upsertEntry(
      SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: relativePath,
        localModified: Value(stat.modified),
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

  Future<_FileInfo?> _remoteInfo(CloudStorageClient client, String path) async {
    final listing = await client.listPath(p.posix.dirname(path));
    for (final item in (listing['files'] as List?) ?? []) {
      if (item['name'] != p.posix.basename(path)) continue;
      final date = item['lastModified'] ?? item['modificationTime'];
      return _FileInfo(
        isFolder: false,
        size: (item['size'] as num?)?.toInt() ?? 0,
        modified: date is int
            ? DateTime.fromMillisecondsSinceEpoch(date)
            : DateTime.tryParse(date?.toString() ?? ''),
        contentHash:
            item['content_hash'] as String? ?? item['crc32Hash'] as String?,
      );
    }
    return null;
  }

  Future<SyncResult> _keepBoth(
    SyncAction action,
    SyncPair pair,
    CloudStorageClient client, {
    void Function()? check,
  }) async {
    check?.call();
    final original = File(p.join(pair.localPath, action.relativePath));
    final remotePath = p.posix.join(pair.remotePath, action.relativePath);
    final parent = p.posix.dirname(action.relativePath);
    final basename = p.posix.basenameWithoutExtension(action.relativePath);
    final extension = p.posix.extension(action.relativePath);
    final listing = await client.listPath(p.posix.dirname(remotePath));
    final remoteNames = <String>{
      for (final entry in [
        ...?listing['files'] as List?,
        ...?listing['folders'] as List?,
      ])
        entry['name'] as String,
    };
    var suffix = 1;
    late String copyRelative;
    late File copy;
    while (true) {
      final name =
          '$basename (local conflict${suffix == 1 ? '' : ' $suffix'})$extension';
      copyRelative = p.posix.normalize(p.posix.join(parent, name));
      copy = File(p.join(pair.localPath, copyRelative));
      if (!remoteNames.contains(name) &&
          await FileSystemEntity.type(copy.path, followLinks: false) ==
              FileSystemEntityType.notFound)
        break;
      suffix++;
    }

    // Preserve the local version before touching the original. If either cloud
    // operation fails, both originals and this recovery copy remain intact.
    check?.call();
    await original.copy(copy.path);
    final remoteBytes = await client.downloadFileBytes(remotePath);
    check?.call();
    final localBytes = await copy.readAsBytes();
    final copyRemotePath = p.posix.join(pair.remotePath, copyRelative);
    check?.call();
    await client.uploadFile(
      localBytes,
      p.posix.basename(copyRelative),
      p.posix.dirname(copyRemotePath),
    );
    await _updateEntryAfterSync(
      pair.id,
      copyRelative,
      await copy.stat(),
      localBytes.length,
      remote: await _remoteInfo(client, copyRemotePath),
    );

    // Stage the download before replacing the local original. Do not leave a
    // partially written original if the download or disk write fails.
    final stage = await Directory(pair.localPath).createTemp('.crisp-sync-');
    try {
      final stagedFile = File(p.join(stage.path, 'download'));
      await stagedFile.writeAsBytes(remoteBytes, flush: true);
      check?.call();
      await stagedFile.rename(original.path);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
    await _updateEntryAfterSync(
      pair.id,
      action.relativePath,
      await original.stat(),
      remoteBytes.length,
      remoteModified: action.remoteModified,
      remoteContentHash: action.remoteContentHash,
    );
    return const SyncResult(uploaded: 1, downloaded: 1);
  }

  // --- Filesystem scanning ---

  /// Recursively scan a local directory and return a map of relative paths → file info.
  Future<Map<String, _FileInfo>> _scanLocal(
    String basePath, {
    void Function()? check,
  }) async {
    final result = <String, _FileInfo>{};
    final dir = Directory(basePath);
    if (!await dir.exists())
      throw FileSystemException('Sync root is unavailable.', basePath);

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      check?.call();
      if (entity is Link)
        throw UnsupportedError(
          'Synchronization does not follow symbolic links: ${entity.path}',
        );
      final relative = p
          .relative(entity.path, from: basePath)
          .replaceAll(p.separator, '/');
      // Skip hidden files and placeholder stubs
      if (p.split(relative).any((s) => s.startsWith('.'))) continue;
      if (PlaceholderService.isPlaceholder(relative)) continue;

      final stat = await entity.stat();
      result[relative] = _FileInfo(
        isFolder: stat.type == FileSystemEntityType.directory,
        modified: stat.modified,
        size: stat.type == FileSystemEntityType.file ? stat.size : 0,
      );
    }
    return result;
  }

  String _safeChildName(dynamic value) {
    if (value is! String ||
        value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains(':') ||
        value.contains('/') ||
        value.contains('\\') ||
        value.contains('\u0000')) {
      throw StateError('Storage returned an unsafe child name.');
    }
    return value;
  }

  /// Recursively scan a remote directory via the cloud client.
  Future<Map<String, _FileInfo>> _scanRemote(
    CloudStorageClient client,
    String basePath, {
    void Function()? check,
  }) async {
    final result = <String, _FileInfo>{};
    await _scanRemoteRecursive(client, basePath, '', result, check: check);
    return result;
  }

  Future<void> _scanRemoteRecursive(
    CloudStorageClient client,
    String basePath,
    String prefix,
    Map<String, _FileInfo> result, {
    void Function()? check,
  }) async {
    check?.call();
    final fullPath = prefix.isEmpty ? basePath : p.posix.join(basePath, prefix);
    if (prefix.split('/').length > 200 || result.length > 200000) {
      throw StateError('Sync tree exceeds supported traversal limits.');
    }
    final listing = await client.listPath(fullPath);
    check?.call();

    for (final folder in (listing['folders'] as List?) ?? []) {
      final name = _safeChildName(folder['name']);
      final relative = prefix.isEmpty ? name : '$prefix/$name';
      DateTime? modified;
      final rawDate = folder['lastModified'] ?? folder['modificationTime'];
      if (rawDate != null) {
        try {
          if (rawDate is int) {
            modified = DateTime.fromMillisecondsSinceEpoch(rawDate);
          } else {
            modified = DateTime.parse(rawDate.toString());
          }
        } catch (_) {}
      }
      result[relative] = _FileInfo(isFolder: true, modified: modified, size: 0);
      // Recurse into subfolder
      await _scanRemoteRecursive(
        client,
        basePath,
        relative,
        result,
        check: check,
      );
    }

    for (final file in (listing['files'] as List?) ?? []) {
      final name = _safeChildName(file['name']);
      final relative = prefix.isEmpty ? name : '$prefix/$name';
      DateTime? modified;
      final rawDate = file['lastModified'] ?? file['modificationTime'];
      if (rawDate != null) {
        try {
          if (rawDate is int) {
            modified = DateTime.fromMillisecondsSinceEpoch(rawDate);
          } else {
            modified = DateTime.parse(rawDate.toString());
          }
        } catch (_) {}
      }
      final size = file['size'] as int? ?? 0;
      // Capture provider content hash for delta sync (Dropbox, OneDrive)
      final contentHash =
          file['content_hash'] as String? ?? file['crc32Hash'] as String?;
      result[relative] = _FileInfo(
        isFolder: false,
        modified: modified,
        size: size,
        contentHash: contentHash,
      );
    }
  }
}

/// Internal file info record for comparison.
class _FileInfo {
  final bool isFolder;
  final DateTime? modified;
  final int size;

  /// Provider-supplied content hash (e.g. Dropbox content_hash, OneDrive crc32Hash).
  /// When available, enables delta sync — only transfer files whose hash changed.
  final String? contentHash;

  const _FileInfo({
    required this.isFolder,
    this.modified,
    this.size = 0,
    this.contentHash,
  });
}

class SyncCancelledException implements Exception {
  const SyncCancelledException();
  @override
  String toString() => 'Synchronization cancelled.';
}

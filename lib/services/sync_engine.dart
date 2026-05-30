// lib/services/sync_engine.dart
//
// Core sync engine: compares local filesystem state against remote provider
// state and the last-known sync state in the database. Produces a list of
// actions (upload, download, delete, conflict) then executes them.
//
// The engine is provider-agnostic — it takes a CloudStorageClient and works
// with any provider that implements the interface.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
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
  String toString() => 'SyncAction($type, $relativePath${isFolder ? ' [dir]' : ''})';
}

enum SyncActionType {
  upload,       // local file is new or modified → push to remote
  download,     // remote file is new or modified → pull to local
  deleteLocal,  // file was deleted on remote → delete locally
  deleteRemote, // file was deleted locally → delete on remote
  conflict,     // both sides changed → needs resolution
  createLocalFolder,
  createRemoteFolder,
  skip,         // no action needed (already synced)
}

/// Result of a sync run.
class SyncResult {
  final int uploaded;
  final int downloaded;
  final int deletedLocal;
  final int deletedRemote;
  final int conflicts;
  final int errors;
  final List<String> errorMessages;

  const SyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
    this.conflicts = 0,
    this.errors = 0,
    this.errorMessages = const [],
  });

  SyncResult operator +(SyncResult other) => SyncResult(
    uploaded: uploaded + other.uploaded,
    downloaded: downloaded + other.downloaded,
    deletedLocal: deletedLocal + other.deletedLocal,
    deletedRemote: deletedRemote + other.deletedRemote,
    conflicts: conflicts + other.conflicts,
    errors: errors + other.errors,
    errorMessages: [...errorMessages, ...other.errorMessages],
  );

  bool get hasChanges => uploaded + downloaded + deletedLocal + deletedRemote + conflicts > 0;

  @override
  String toString() => 'SyncResult(up:$uploaded down:$downloaded delL:$deletedLocal delR:$deletedRemote conflicts:$conflicts errors:$errors)';
}

class SyncEngine {
  static final _log = Log('SyncEngine');

  final SyncDatabase db;

  SyncEngine(this.db);

  /// Check if a relative path passes the include/exclude filters for a pair.
  ///
  /// If include patterns are set, the path must match at least one.
  /// If exclude patterns are set, the path must not match any.
  static bool passesFilter(String relativePath, String includePatterns, String excludePatterns) {
    // Parse patterns (comma-separated, trim whitespace, skip empty)
    final includes = includePatterns.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final excludes = excludePatterns.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

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
  Future<SyncResult> syncPair(SyncPair pair, CloudStorageClient client) async {
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
    final localFiles = await _scanLocal(pair.localPath);

    // 2. Scan remote
    final remoteFiles = await _scanRemote(client, pair.remotePath);

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
        path, local, remote, known,
        policy: policy,
        direction: direction,
      );
      if (action.type != SyncActionType.skip) {
        actions.add(action);
      }
    }

    _log.info('${actions.length} actions to execute');

    // 5. Execute actions
    var result = const SyncResult();

    // Process folders first (create), then files, then deletes last
    final folderCreates = actions.where((a) =>
        a.type == SyncActionType.createLocalFolder || a.type == SyncActionType.createRemoteFolder);
    final fileActions = actions.where((a) =>
        a.type == SyncActionType.upload || a.type == SyncActionType.download);
    final deleteActions = actions.where((a) =>
        a.type == SyncActionType.deleteLocal || a.type == SyncActionType.deleteRemote);
    final conflictActions = actions.where((a) => a.type == SyncActionType.conflict);

    for (final action in folderCreates) {
      result = result + await _executeAction(action, pair, client);
    }
    for (final action in fileActions) {
      result = result + await _executeAction(action, pair, client);
    }
    for (final action in deleteActions) {
      result = result + await _executeAction(action, pair, client);
    }
    for (final action in conflictActions) {
      result = result + SyncResult(conflicts: 1);
      // Mark as conflict in DB
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pair.id,
        relativePath: action.relativePath,
        status: const Value('conflict'),
        localModified: Value(action.localModified),
        remoteModified: Value(action.remoteModified),
        isFolder: Value(action.isFolder),
      ));
    }

    // 6. Update pair last sync time
    await (db.update(db.syncPairs)..where((t) => t.id.equals(pair.id)))
        .write(SyncPairsCompanion(lastSyncAt: Value(DateTime.now())));

    _log.info('Sync complete — $result');
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

    // --- New files (not in DB) ---
    if (!existsInDb) {
      if (existsLocal && existsRemote) {
        // Both exist but we've never seen them — treat as conflict or merge
        return _resolveConflict(relativePath, local, remote, known, policy);
      }
      if (existsLocal && !existsRemote) {
        // New local file → upload (if direction allows)
        if (direction == SyncDirection.downloadOnly) {
          return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
        }
        if (local!.isFolder) {
          return SyncAction(type: SyncActionType.createRemoteFolder, relativePath: relativePath, isFolder: true);
        }
        return SyncAction(type: SyncActionType.upload, relativePath: relativePath, localModified: local.modified);
      }
      if (!existsLocal && existsRemote) {
        // New remote file → download
        if (direction == SyncDirection.uploadOnly) {
          return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
        }
        if (remote!.isFolder) {
          return SyncAction(type: SyncActionType.createLocalFolder, relativePath: relativePath, isFolder: true);
        }
        return SyncAction(type: SyncActionType.download, relativePath: relativePath, remoteModified: remote.modified, remoteContentHash: remote.contentHash, remoteSize: remote.size);
      }
      return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
    }

    // --- Known files (in DB) ---

    // Deleted on both sides → clean up DB entry
    if (!existsLocal && !existsRemote) {
      return SyncAction(type: SyncActionType.skip, relativePath: relativePath, dbEntry: known);
    }

    // Deleted locally, still exists remote → delete remote or re-download
    if (!existsLocal && existsRemote) {
      if (direction == SyncDirection.downloadOnly) {
        return SyncAction(type: SyncActionType.download, relativePath: relativePath, remoteModified: remote!.modified, remoteContentHash: remote.contentHash, remoteSize: remote.size);
      }
      // Check if remote was also modified since last sync
      if (known.remoteModified != null && remote!.modified != null &&
          remote.modified!.isAfter(known.remoteModified!)) {
        // Remote changed after our last sync — conflict
        return _resolveConflict(relativePath, local, remote, known, policy);
      }
      return SyncAction(type: SyncActionType.deleteRemote, relativePath: relativePath, dbEntry: known);
    }

    // Deleted remotely, still exists local → delete local or re-upload
    if (existsLocal && !existsRemote) {
      if (direction == SyncDirection.uploadOnly) {
        return SyncAction(type: SyncActionType.upload, relativePath: relativePath, localModified: local!.modified);
      }
      if (known.localModified != null && local!.modified != null &&
          local.modified!.isAfter(known.localModified!)) {
        return _resolveConflict(relativePath, local, remote, known, policy);
      }
      return SyncAction(type: SyncActionType.deleteLocal, relativePath: relativePath, dbEntry: known);
    }

    // Both exist — check for modifications
    final localChanged = _isModified(local!, known.localModified, known.localSize);
    final remoteChanged = _isRemoteModified(remote!, known.remoteModified, known.remoteSize,
        knownHash: known.remoteHash);

    if (!localChanged && !remoteChanged) {
      return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
    }

    if (localChanged && !remoteChanged) {
      if (direction == SyncDirection.downloadOnly) {
        return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
      }
      return SyncAction(type: SyncActionType.upload, relativePath: relativePath, localModified: local.modified);
    }

    if (!localChanged && remoteChanged) {
      if (direction == SyncDirection.uploadOnly) {
        return SyncAction(type: SyncActionType.skip, relativePath: relativePath);
      }
      return SyncAction(type: SyncActionType.download, relativePath: relativePath, remoteModified: remote.modified, remoteContentHash: remote.contentHash, remoteSize: remote.size);
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
    switch (policy) {
      case ConflictPolicy.localWins:
        return SyncAction(type: SyncActionType.upload, relativePath: relativePath, localModified: local?.modified);
      case ConflictPolicy.remoteWins:
        return SyncAction(type: SyncActionType.download, relativePath: relativePath, remoteModified: remote?.modified, remoteSize: remote?.size);
      case ConflictPolicy.newestWins:
        final localTime = local?.modified ?? DateTime(1970);
        final remoteTime = remote?.modified ?? DateTime(1970);
        if (localTime.isAfter(remoteTime)) {
          return SyncAction(type: SyncActionType.upload, relativePath: relativePath, localModified: localTime);
        } else {
          return SyncAction(type: SyncActionType.download, relativePath: relativePath, remoteModified: remoteTime, remoteSize: remote?.size);
        }
      case ConflictPolicy.keepBoth:
        // Upload local with a renamed copy, then download remote
        // For now, treat as upload (caller renames the local copy)
        return SyncAction(type: SyncActionType.upload, relativePath: relativePath, localModified: local?.modified);
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

  bool _isRemoteModified(_FileInfo file, DateTime? knownModified, int knownSize, {String? knownHash}) {
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
  Future<SyncResult> _executeAction(SyncAction action, SyncPair pair, CloudStorageClient client) async {
    final localBase = pair.localPath;
    final remoteBase = pair.remotePath;
    final localPath = p.join(localBase, action.relativePath);
    final remotePath = p.posix.join(remoteBase, action.relativePath);

    try {
      switch (action.type) {
        case SyncActionType.upload:
          final bytes = await File(localPath).readAsBytes();
          final fileName = p.basename(action.relativePath);
          final targetDir = p.posix.dirname(remotePath);
          await client.uploadFile(bytes, fileName, targetDir);
          final stat = await File(localPath).stat();
          await _updateEntryAfterSync(pair.id, action.relativePath, stat, bytes.length);
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
          final file = File(localPath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          final stat = await file.stat();
          await _updateEntryAfterSync(pair.id, action.relativePath, stat, bytes.length,
              remoteContentHash: action.remoteContentHash);
          return const SyncResult(downloaded: 1);

        case SyncActionType.deleteLocal:
          final entity = FileSystemEntity.typeSync(localPath);
          if (entity == FileSystemEntityType.directory) {
            await Directory(localPath).delete(recursive: true);
          } else if (entity == FileSystemEntityType.file) {
            await File(localPath).delete();
          }
          await db.upsertEntry(SyncEntriesCompanion.insert(
            pairId: pair.id,
            relativePath: action.relativePath,
            status: const Value('synced'),
          ));
          return const SyncResult(deletedLocal: 1);

        case SyncActionType.deleteRemote:
          await client.deletePath(remotePath);
          // Remove from DB
          final existing = await db.getEntry(pair.id, action.relativePath);
          if (existing != null) {
            await (db.delete(db.syncEntries)..where((t) => t.id.equals(existing.id))).go();
          }
          return const SyncResult(deletedRemote: 1);

        case SyncActionType.createLocalFolder:
          await Directory(localPath).create(recursive: true);
          await db.upsertEntry(SyncEntriesCompanion.insert(
            pairId: pair.id,
            relativePath: action.relativePath,
            isFolder: const Value(true),
            status: const Value('synced'),
            lastSyncAt: Value(DateTime.now()),
          ));
          return const SyncResult(downloaded: 1);

        case SyncActionType.createRemoteFolder:
          await client.createFolderPath(remotePath);
          await db.upsertEntry(SyncEntriesCompanion.insert(
            pairId: pair.id,
            relativePath: action.relativePath,
            isFolder: const Value(true),
            status: const Value('synced'),
            lastSyncAt: Value(DateTime.now()),
          ));
          return const SyncResult(uploaded: 1);

        case SyncActionType.conflict:
        case SyncActionType.skip:
          return const SyncResult();
      }
    } catch (e) {
      _log.error('Error executing $action', e);
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pair.id,
        relativePath: action.relativePath,
        status: const Value('error'),
        error: Value(e.toString()),
      ));
      return SyncResult(errors: 1, errorMessages: ['${action.relativePath}: $e']);
    }
  }

  Future<void> _updateEntryAfterSync(int pairId, String relativePath, FileStat stat, int size, {String? remoteContentHash}) async {
    await db.upsertEntry(SyncEntriesCompanion.insert(
      pairId: pairId,
      relativePath: relativePath,
      localModified: Value(stat.modified),
      remoteModified: Value(stat.modified), // After sync they match
      localSize: Value(size),
      remoteSize: Value(size),
      remoteHash: Value(remoteContentHash),
      status: const Value('synced'),
      error: const Value(null),
      lastSyncAt: Value(DateTime.now()),
    ));
  }

  // --- Filesystem scanning ---

  /// Recursively scan a local directory and return a map of relative paths → file info.
  Future<Map<String, _FileInfo>> _scanLocal(String basePath) async {
    final result = <String, _FileInfo>{};
    final dir = Directory(basePath);
    if (!await dir.exists()) return result;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: basePath);
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

  /// Recursively scan a remote directory via the cloud client.
  Future<Map<String, _FileInfo>> _scanRemote(CloudStorageClient client, String basePath) async {
    final result = <String, _FileInfo>{};
    await _scanRemoteRecursive(client, basePath, '', result);
    return result;
  }

  Future<void> _scanRemoteRecursive(
    CloudStorageClient client,
    String basePath,
    String prefix,
    Map<String, _FileInfo> result,
  ) async {
    final fullPath = prefix.isEmpty ? basePath : p.posix.join(basePath, prefix);
    final listing = await client.listPath(fullPath);

    for (final folder in (listing['folders'] as List?) ?? []) {
      final name = folder['name'] as String;
      final relative = prefix.isEmpty ? name : '$prefix/$name';
      DateTime? modified;
      final rawDate = folder['lastModified'] ?? folder['modificationTime'];
      if (rawDate != null) {
        try {
          if (rawDate is int) modified = DateTime.fromMillisecondsSinceEpoch(rawDate);
          else modified = DateTime.parse(rawDate.toString());
        } catch (_) {}
      }
      result[relative] = _FileInfo(isFolder: true, modified: modified, size: 0);
      // Recurse into subfolder
      await _scanRemoteRecursive(client, basePath, relative, result);
    }

    for (final file in (listing['files'] as List?) ?? []) {
      final name = file['name'] as String;
      final relative = prefix.isEmpty ? name : '$prefix/$name';
      DateTime? modified;
      final rawDate = file['lastModified'] ?? file['modificationTime'];
      if (rawDate != null) {
        try {
          if (rawDate is int) modified = DateTime.fromMillisecondsSinceEpoch(rawDate);
          else modified = DateTime.parse(rawDate.toString());
        } catch (_) {}
      }
      final size = file['size'] as int? ?? 0;
      // Capture provider content hash for delta sync (Dropbox, OneDrive)
      final contentHash = file['content_hash'] as String? ?? file['crc32Hash'] as String?;
      result[relative] = _FileInfo(isFolder: false, modified: modified, size: size, contentHash: contentHash);
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

  const _FileInfo({required this.isFolder, this.modified, this.size = 0, this.contentHash});
}

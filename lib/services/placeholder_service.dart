// lib/services/placeholder_service.dart
//
// Placeholder / cloud-only file service for on-demand sync.
// Creates lightweight stub files locally for remote-only files so the user
// can see the directory structure without downloading everything.
//
// Placeholder files:
//   - Have a .crispcloud extension appended (e.g., "photo.jpg.crispcloud")
//   - Contain JSON metadata (remote path, size, modified, provider)
//   - Are tiny (< 1 KB) regardless of the actual remote file size
//
// When the user opens a placeholder, the real file is downloaded and the
// placeholder is replaced with the actual content.
//
// "Free Up Space" converts a synced local file back to a placeholder.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import 'cloud_storage_interface.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'sync_source_binding.dart';
import 'sync_transfer_service.dart';
import 'transfer_journal.dart';
import 'transfer_recovery_service.dart';
import 'log_service.dart';
import 'sync_database.dart';

/// Extension appended to placeholder files.
const placeholderExtension = '.crispcloud';

/// Metadata stored inside a placeholder file.
class PlaceholderMeta {
  final String remotePath;
  final String provider;
  final int sizeBytes;
  final DateTime? remoteModified;
  final String? contentHash;
  final String? sourceBinding;

  const PlaceholderMeta({
    required this.remotePath,
    required this.provider,
    required this.sizeBytes,
    this.remoteModified,
    this.contentHash,
    this.sourceBinding,
  });

  Map<String, dynamic> toJson() => {
    'remotePath': remotePath,
    'provider': provider,
    'sizeBytes': sizeBytes,
    if (remoteModified != null)
      'remoteModified': remoteModified!.toIso8601String(),
    if (contentHash != null) 'contentHash': contentHash,
    if (sourceBinding != null) 'sourceBinding': sourceBinding,
    'version': 1,
  };

  factory PlaceholderMeta.fromJson(Map<String, dynamic> json) =>
      PlaceholderMeta(
        remotePath: json['remotePath'] as String,
        provider: json['provider'] as String,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        remoteModified: json['remoteModified'] != null
            ? DateTime.tryParse(json['remoteModified'] as String)
            : null,
        contentHash: json['contentHash'] as String?,
        sourceBinding: json['sourceBinding'] as String?,
      );

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static PlaceholderMeta? decode(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      return PlaceholderMeta.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

class PlaceholderService {
  static const _log = Log('PlaceholderService');

  final SyncDatabase _db;

  PlaceholderService(this._db, {TransferJournal? journal})
    : _transfers = SyncTransferService(journal: journal);
  final SyncTransferService _transfers;

  /// Check if a local file path is a placeholder.
  static bool isPlaceholder(String path) => path.endsWith(placeholderExtension);

  /// Get the real file name from a placeholder path.
  static String realName(String placeholderPath) => placeholderPath.substring(
    0,
    placeholderPath.length - placeholderExtension.length,
  );

  /// Get the placeholder path for a real file path.
  static String placeholderName(String realPath) =>
      '$realPath$placeholderExtension';

  /// Create a placeholder file for a remote file.
  ///
  /// Creates a small JSON stub at `localPath.crispcloud` instead of
  /// downloading the full file.
  Future<void> createPlaceholder({
    required int pairId,
    required String localBasePath,
    required String relativePath,
    required String remotePath,
    required String provider,
    required int sizeBytes,
    DateTime? remoteModified,
    String? contentHash,
  }) async {
    final pair = await _db.getPair(pairId);
    SyncSourceBinding.requireLocal(pair);
    validateSyncRelativePath(relativePath);
    if (!p.equals(pair.localPath, localBasePath) ||
        provider != pair.provider ||
        remotePath != p.posix.join(pair.remotePath, relativePath)) {
      throw StateError('The placeholder does not belong to this saved pair.');
    }
    final meta = PlaceholderMeta(
      sourceBinding: pair.sourceBinding,
      remotePath: remotePath,
      provider: provider,
      sizeBytes: sizeBytes,
      remoteModified: remoteModified,
      contentHash: contentHash,
    );

    final realLocalPath = p.join(localBasePath, relativePath);
    final stubPath = placeholderName(realLocalPath);

    // Write the stub file
    final stubFile = File(stubPath);
    if (await FileSystemEntity.type(stubPath, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('A placeholder cannot replace a symbolic link.');
    }
    if (await stubFile.exists()) {
      if (await stubFile.length() > 64 * 1024 ||
          PlaceholderMeta.decode(await stubFile.readAsString()) == null) {
        throw StateError('An unrelated file occupies the placeholder path.');
      }
    }
    await stubFile.parent.create(recursive: true);
    await stubFile.writeAsString(meta.encode());

    // Mark in DB as placeholder
    await _db.upsertEntry(
      SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: relativePath,
        remoteModified: Value(remoteModified),
        remoteSize: Value(sizeBytes),
        remoteHash: Value(contentHash),
        status: const Value('placeholder'),
        isFolder: const Value(false),
        lastSyncAt: Value(DateTime.now()),
      ),
    );

    _log.debug('Created placeholder for $relativePath');
  }

  /// Hydrate a placeholder: download the real file and replace the stub.
  ///
  /// Returns the local path to the downloaded file.
  Future<String> hydrate({
    required int pairId,
    required String localBasePath,
    required String relativePath,
    required CloudStorageClient client,
    bool Function()? isCurrent,
  }) async {
    final pair = await _db.getPair(pairId);
    final binding = SyncSourceBinding.require(pair, client);
    validateSyncRelativePath(relativePath);
    if (!p.equals(pair.localPath, localBasePath)) {
      throw StateError('The placeholder local folder changed.');
    }
    bool current() =>
        (isCurrent?.call() ?? true) && binding.matches(pair, client);
    void check() {
      if (!current()) throw StateError('The placeholder account changed.');
    }

    final local = LocalOperationBackend(LocalFileService(), isCurrent: current);
    final remote = CloudOperationBackend(client, isCurrent: current);
    final realLocalPath = p.join(localBasePath, relativePath);
    final stubPath = placeholderName(realLocalPath);
    final stubFile = File(stubPath);
    final stub = await local.stat(stubPath);
    if (stub == null ||
        stub.isFolder ||
        stub.isSymlink == true ||
        stub.size == null ||
        stub.size! > 64 * 1024) {
      throw StateError('The placeholder metadata is missing or invalid.');
    }
    final stubContents = await stubFile.readAsString();
    final meta = PlaceholderMeta.decode(stubContents);
    final remotePath = p.posix.join(pair.remotePath, relativePath);
    if (meta == null ||
        meta.sourceBinding != pair.sourceBinding ||
        meta.remotePath != remotePath ||
        meta.provider != pair.provider) {
      throw StateError(
        'This placeholder belongs to an earlier account binding. Compare the pair to recreate it.',
      );
    }
    if (await local.stat(realLocalPath) != null) {
      throw StateError(
        'A local file already exists. Compare the pair before replacing it.',
      );
    }
    final file = await remote.stat(remotePath);
    if (file == null || file.isFolder || file.isSymlink == true) {
      throw StateError('The placeholder cloud file is unavailable.');
    }
    final control = FileOperationControl();
    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!current()) control.cancel();
    });
    try {
      final hash = await transferDigest(remote, file, control);
      final written = await _transfers.copy(
        source: remote,
        file: file,
        destination: local,
        destinationPath: realLocalPath,
        expectedDestination: null,
        expectedSourceHash: hash,
        control: control,
        check: check,
      );
      check();
      if (await stubFile.exists() &&
          await stubFile.readAsString() == stubContents) {
        await stubFile.delete();
      }
      await _db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: pairId,
          relativePath: relativePath,
          localModified: Value(written.updatedAt),
          remoteModified: Value(file.updatedAt),
          localSize: Value(written.size ?? file.size ?? 0),
          remoteSize: Value(file.size ?? written.size ?? 0),
          localHash: Value(hash),
          remoteHash: Value(
            (file.metadata?['content_hash'] ?? file.metadata?['crc32Hash'])
                ?.toString(),
          ),
          status: const Value('synced'),
          error: const Value(null),
          isFolder: const Value(false),
          lastSyncAt: Value(DateTime.now()),
        ),
      );
      _log.info('Hydrated $relativePath');
      return realLocalPath;
    } finally {
      timer.cancel();
    }
  }

  /// Free up space: replace a synced local file with a placeholder.
  ///
  /// The real file is deleted and a stub is created in its place.
  Future<void> dehydrate({
    required int pairId,
    required String localBasePath,
    required String relativePath,
    required String remotePath,
    required String provider,
    required CloudStorageClient client,
    bool Function()? isCurrent,
  }) async {
    final pair = await _db.getPair(pairId);
    final binding = SyncSourceBinding.require(pair, client);
    validateSyncRelativePath(relativePath);
    if (!p.equals(localBasePath, pair.localPath) ||
        remotePath != p.posix.join(pair.remotePath, relativePath) ||
        provider != pair.provider) {
      throw StateError('The cloud-only file does not belong to this pair.');
    }
    bool current() =>
        (isCurrent?.call() ?? true) && binding.matches(pair, client);
    final local = LocalOperationBackend(LocalFileService(), isCurrent: current);
    final remote = CloudOperationBackend(client, isCurrent: current);
    final control = FileOperationControl();
    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!current()) control.cancel();
    });
    try {
      final realLocalPath = p.join(localBasePath, relativePath);
      final entry = await _db.getEntry(pairId, relativePath);
      final file = await local.stat(realLocalPath);
      if (entry == null ||
          entry.status != 'synced' ||
          entry.localHash == null ||
          file == null ||
          file.isSymlink == true ||
          file.isFolder ||
          file.size != entry.localSize ||
          await transferDigest(local, file, control) != entry.localHash) {
        throw StateError(
          'Sync and verify this file before freeing space; its local contents changed or have no verified baseline.',
        );
      }
      final cloud = await remote.stat(remotePath);
      if (cloud == null ||
          cloud.isFolder ||
          cloud.isSymlink == true ||
          await transferDigest(remote, cloud, control) != entry.localHash) {
        throw StateError(
          'The cloud copy changed or is unavailable. The local version was retained.',
        );
      }
      await createPlaceholder(
        pairId: pairId,
        localBasePath: localBasePath,
        relativePath: relativePath,
        remotePath: remotePath,
        provider: provider,
        sizeBytes: file.size!,
        remoteModified: cloud.updatedAt,
        contentHash:
            (cloud.metadata?['content_hash'] ?? cloud.metadata?['crc32Hash'])
                ?.toString(),
      );
      final latest = await local.stat(realLocalPath);
      final latestCloud = await remote.stat(remotePath);
      if ((await _db.getPair(pairId)).sourceBinding != pair.sourceBinding ||
          latest == null ||
          !sameTransferVersion(file, latest) ||
          latestCloud == null ||
          !sameTransferVersion(cloud, latestCloud) ||
          await transferDigest(local, latest, control) != entry.localHash ||
          await transferDigest(remote, latestCloud, control) !=
              entry.localHash) {
        throw StateError(
          'A file changed while freeing space; the local version was retained.',
        );
      }
      await local.deleteFile(latest);
      _log.info('Dehydrated $relativePath (freed ${file.size} bytes)');
    } finally {
      timer.cancel();
    }
  }

  /// Check if a file is currently a placeholder (by DB status).
  Future<bool> isFilePlaceholder(int pairId, String relativePath) async {
    final entry = await _db.getEntry(pairId, relativePath);
    return entry?.status == 'placeholder';
  }

  /// Get all placeholder entries for a sync pair.
  Future<List<SyncEntry>> getPlaceholders(int pairId) async {
    return (await _db.getEntriesForPair(pairId))
        .where((e) => e.status == 'placeholder')
        .toList();
  }

  /// Auto-evict synced files that haven't been accessed in [maxAgeDays] days.
  ///
  /// Iterates all 'synced' entries for every pair that has placeholders
  /// enabled and calls [dehydrate] on those not accessed recently.
  /// Returns the number of files evicted.
  Future<int> autoEvict(
    int maxAgeDays,
    SyncDatabase db, {
    required CloudStorageClient client,
    bool Function()? isCurrent,
  }) async {
    if (maxAgeDays <= 0 || !client.isAuthenticated) return 0;

    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
    final pairs = await db.getAllPairs();
    int evicted = 0;

    for (final pair in pairs) {
      if (!pair.usePlaceholders ||
          !(SyncSourceBinding.decode(pair.sourceBinding)
                  ?.matches(pair, client) ??
              false)) {
        continue;
      }

      final entries = await db.getEntriesForPair(pair.id);
      final syncedEntries = entries.where(
        (e) => e.status == 'synced' && !e.isFolder,
      );

      for (final entry in syncedEntries) {
        final realLocalPath = p.join(pair.localPath, entry.relativePath);
        final realFile = File(realLocalPath);

        if (!await realFile.exists()) continue;

        try {
          final stat = await realFile.stat();
          // Use last-accessed time; fall back to modified if not available
          final lastAccess = stat.accessed;
          if (lastAccess.isBefore(cutoff)) {
            await dehydrate(
              pairId: pair.id,
              localBasePath: pair.localPath,
              relativePath: entry.relativePath,
              remotePath: '${pair.remotePath}/${entry.relativePath}',
              provider: pair.provider,
              client: client,
              isCurrent: isCurrent,
            );
            evicted++;
            _log.info(
              'Auto-evicted ${entry.relativePath} (last accessed: $lastAccess)',
            );
          }
        } catch (e) {
          _log.error('Auto-evict error for ${entry.relativePath}: $e');
        }
      }
    }

    _log.info(
      'Auto-eviction complete: $evicted file(s) evicted (maxAge: ${maxAgeDays}d)',
    );
    return evicted;
  }

  /// Hydrate all placeholders for a sync pair (download everything).
  Future<int> hydrateAll({
    required int pairId,
    required String localBasePath,
    required CloudStorageClient client,
    bool Function()? isCurrent,
  }) async {
    final placeholders = await getPlaceholders(pairId);
    int count = 0;
    for (final entry in placeholders) {
      try {
        await hydrate(
          pairId: pairId,
          localBasePath: localBasePath,
          relativePath: entry.relativePath,
          client: client,
          isCurrent: isCurrent,
        );
        count++;
      } catch (e) {
        _log.error('Failed to hydrate ${entry.relativePath}: $e');
      }
    }
    return count;
  }
}

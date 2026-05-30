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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import 'cloud_storage_interface.dart';
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

  const PlaceholderMeta({
    required this.remotePath,
    required this.provider,
    required this.sizeBytes,
    this.remoteModified,
    this.contentHash,
  });

  Map<String, dynamic> toJson() => {
        'remotePath': remotePath,
        'provider': provider,
        'sizeBytes': sizeBytes,
        if (remoteModified != null)
          'remoteModified': remoteModified!.toIso8601String(),
        if (contentHash != null) 'contentHash': contentHash,
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
      );

  String encode() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

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
  static final _log = Log('PlaceholderService');

  final SyncDatabase _db;

  PlaceholderService(this._db);

  /// Check if a local file path is a placeholder.
  static bool isPlaceholder(String path) =>
      path.endsWith(placeholderExtension);

  /// Get the real file name from a placeholder path.
  static String realName(String placeholderPath) =>
      placeholderPath.substring(
          0, placeholderPath.length - placeholderExtension.length);

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
    final meta = PlaceholderMeta(
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
    await stubFile.parent.create(recursive: true);
    await stubFile.writeAsString(meta.encode());

    // Mark in DB as placeholder
    await _db.upsertEntry(SyncEntriesCompanion.insert(
      pairId: pairId,
      relativePath: relativePath,
      remoteModified: Value(remoteModified),
      remoteSize: Value(sizeBytes),
      remoteHash: Value(contentHash),
      status: const Value('placeholder'),
      isFolder: const Value(false),
      lastSyncAt: Value(DateTime.now()),
    ));

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
  }) async {
    final realLocalPath = p.join(localBasePath, relativePath);
    final stubPath = placeholderName(realLocalPath);
    final stubFile = File(stubPath);

    // Read metadata from stub
    PlaceholderMeta? meta;
    if (await stubFile.exists()) {
      final content = await stubFile.readAsString();
      meta = PlaceholderMeta.decode(content);
    }

    // Download the real file
    final remotePath =
        meta?.remotePath ?? relativePath; // Fallback to relative
    _log.info('Hydrating placeholder: $relativePath');
    final bytes = await client.downloadFileBytes(remotePath);

    // Write the real file
    final realFile = File(realLocalPath);
    await realFile.parent.create(recursive: true);
    await realFile.writeAsBytes(bytes);

    // Remove the stub
    if (await stubFile.exists()) {
      await stubFile.delete();
    }

    // Update DB: synced, no longer placeholder
    final stat = await realFile.stat();
    await _db.upsertEntry(SyncEntriesCompanion.insert(
      pairId: pairId,
      relativePath: relativePath,
      localModified: Value(stat.modified),
      remoteModified: Value(meta?.remoteModified ?? stat.modified),
      localSize: Value(bytes.length),
      remoteSize: Value(bytes.length),
      remoteHash: Value(meta?.contentHash),
      status: const Value('synced'),
      isFolder: const Value(false),
      lastSyncAt: Value(DateTime.now()),
    ));

    _log.info('Hydrated $relativePath (${bytes.length} bytes)');
    return realLocalPath;
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
  }) async {
    final realLocalPath = p.join(localBasePath, relativePath);
    final realFile = File(realLocalPath);

    if (!await realFile.exists()) {
      _log.warn('Cannot dehydrate: file not found at $realLocalPath');
      return;
    }

    final stat = await realFile.stat();
    final entry = await _db.getEntry(pairId, relativePath);

    // Create placeholder with metadata from real file + DB
    await createPlaceholder(
      pairId: pairId,
      localBasePath: localBasePath,
      relativePath: relativePath,
      remotePath: remotePath,
      provider: provider,
      sizeBytes: stat.size,
      remoteModified: entry?.remoteModified ?? stat.modified,
      contentHash: entry?.remoteHash,
    );

    // Delete the real file
    await realFile.delete();

    _log.info('Dehydrated $relativePath (freed ${stat.size} bytes)');
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

  /// Hydrate all placeholders for a sync pair (download everything).
  Future<int> hydrateAll({
    required int pairId,
    required String localBasePath,
    required CloudStorageClient client,
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
        );
        count++;
      } catch (e) {
        _log.error('Failed to hydrate ${entry.relativePath}: $e');
      }
    }
    return count;
  }
}

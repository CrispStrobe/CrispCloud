// lib/services/multi_cloud_service.dart
//
// Manages multiple simultaneous cloud connections, cloud-to-cloud transfers,
// cross-provider file comparison, and unified search across providers.

import 'dart:async';

import '../models/file_item.dart';
import '../models/operation_progress.dart';
import '../services/cloud_storage_interface.dart';
import '../services/log_service.dart';
import '../services/transfer_queue.dart';

/// Represents a single registered cloud connection.
class CloudConnection {
  final String id;
  final String label;
  final CloudProvider provider;
  final CloudStorageClient client;

  const CloudConnection({
    required this.id,
    required this.label,
    required this.provider,
    required this.client,
  });
}

/// Describes a difference found during cross-provider comparison.
enum FileDiffKind { onlyInA, onlyInB, sizeDiffers, dateDiffers, bothDiffer }

class FileDiff {
  final String name;
  final FileDiffKind kind;
  final FileItem? itemA;
  final FileItem? itemB;

  const FileDiff({
    required this.name,
    required this.kind,
    this.itemA,
    this.itemB,
  });

  @override
  String toString() {
    switch (kind) {
      case FileDiffKind.onlyInA:
        return '$name: only in A';
      case FileDiffKind.onlyInB:
        return '$name: only in B';
      case FileDiffKind.sizeDiffers:
        return '$name: size differs (A=${itemA?.size}, B=${itemB?.size})';
      case FileDiffKind.dateDiffers:
        return '$name: date differs (A=${itemA?.updatedAt}, B=${itemB?.updatedAt})';
      case FileDiffKind.bothDiffer:
        return '$name: size and date differ';
    }
  }
}

/// A search result with an attached provider label.
class MultiCloudSearchResult {
  final String connectionId;
  final String connectionLabel;
  final String providerName;
  final FileItem item;

  const MultiCloudSearchResult({
    required this.connectionId,
    required this.connectionLabel,
    required this.providerName,
    required this.item,
  });
}

/// Service that manages multiple simultaneous cloud connections and provides
/// cloud-to-cloud operations: transfer, compare, and unified search.
class MultiCloudService {
  static final _log = Log('MultiCloudService');

  final Map<String, CloudConnection> _connections = {};
  final TransferQueue _queue = TransferQueue(maxConcurrent: 2);

  // ---------------------------------------------------------------------------
  // Connection management
  // ---------------------------------------------------------------------------

  /// Register an already-authenticated client under a unique [id].
  void addConnection({
    required String id,
    required String label,
    required CloudProvider provider,
    required CloudStorageClient client,
  }) {
    _log.info('Adding connection: $id ($label / ${client.providerName})');
    _connections[id] = CloudConnection(
      id: id,
      label: label,
      provider: provider,
      client: client,
    );
  }

  /// Retrieve a specific connection by [id], or null if not registered.
  CloudConnection? getConnection(String id) => _connections[id];

  /// Return all currently active connections.
  List<CloudConnection> getAllConnections() => List.unmodifiable(_connections.values);

  /// Disconnect and remove a connection.
  Future<void> removeConnection(String id) async {
    final conn = _connections.remove(id);
    if (conn == null) return;
    _log.info('Removing connection: $id (${conn.label})');
    try {
      await conn.client.logout();
    } catch (e) {
      _log.warn('Error during logout for $id', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud-to-cloud transfer
  // ---------------------------------------------------------------------------

  /// Transfer [files] from [sourceClient]/[sourcePath] to
  /// [targetClient]/[targetPath].
  ///
  /// Uses streaming when both sides support it to avoid buffering full files.
  /// Progress is reported per-file via [onFileProgress] and per-byte via the
  /// returned [OperationProgress].
  Future<OperationProgress> transferBetweenClouds({
    required CloudStorageClient sourceClient,
    required String sourcePath,
    required CloudStorageClient targetClient,
    required String targetPath,
    required List<FileItem> files,
    void Function(String fileName, int current, int total)? onFileProgress,
  }) async {
    _log.info(
      'Cloud-to-cloud transfer: ${files.length} files '
      '${sourceClient.providerName} -> ${targetClient.providerName}',
    );

    final fileProgresses = files
        .map((f) => FileProgress(name: f.name, path: f.path ?? f.name, size: f.size ?? 0))
        .toList();
    final totalBytes = files.fold<int>(0, (sum, f) => sum + (f.size ?? 0));

    final operation = OperationProgress(
      id: 'xcloud_${DateTime.now().millisecondsSinceEpoch}',
      type: OperationType.copy,
      sourcePath: '${sourceClient.providerName}:$sourcePath',
      targetPath: '${targetClient.providerName}:$targetPath',
      fileName: files.length == 1 ? files.first.name : '${files.length} files',
      totalBytes: totalBytes,
      files: fileProgresses,
    );

    int completedBytes = 0;
    int tasksFinished = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileProgress = fileProgresses[i];
      final taskId = '${operation.id}_xfer_$i';

      _queue.enqueue(TransferTask(
        id: taskId,
        operation: operation,
        execute: () async {
          if (operation.isCancelled) return;
          if (operation.isPaused) await operation.pauseFuture;
          if (operation.isCancelled) return;

          final remoteFilePath =
              file.path ?? '${sourcePath.endsWith('/') ? sourcePath : '$sourcePath/'}${file.name}';

          _log.debug('Transferring ${file.name} (${file.size} bytes)');

          try {
            if (sourceClient.supportsStreaming && targetClient.supportsStreaming) {
              // True streaming path: pipe download stream into upload stream
              int transferred = 0;
              final stream = sourceClient.downloadStream(
                remoteFilePath,
                onProgress: (current, total) {
                  transferred = current;
                  operation.currentBytes = completedBytes + current;
                  onFileProgress?.call(file.name, current, total);
                },
              );
              await targetClient.uploadStream(
                stream,
                file.size ?? 0,
                file.name,
                targetPath,
                onProgress: (current, total) {
                  operation.currentBytes = completedBytes + current;
                  onFileProgress?.call(file.name, current, total);
                },
              );
            } else {
              // Fallback: download bytes then upload
              final bytes = await sourceClient.downloadFileBytes(
                remoteFilePath,
                onProgress: (current, total) {
                  operation.currentBytes = completedBytes + current;
                  onFileProgress?.call(file.name, current, total);
                },
              );
              await targetClient.uploadFile(
                bytes,
                file.name,
                targetPath,
                onProgress: (current, total) {
                  operation.currentBytes = completedBytes + current;
                  onFileProgress?.call(file.name, current, total);
                },
              );
            }

            fileProgress.isComplete = true;
            completedBytes += fileProgress.size;
            operation.currentBytes = completedBytes;
          } catch (e, st) {
            _log.error('Transfer failed for ${file.name}', e, st);
            fileProgress.error = e.toString();
          }

          tasksFinished++;
          if (tasksFinished == files.length) {
            _finalizeBatch(operation, fileProgresses);
          }
        },
      ));
    }

    return operation;
  }

  void _finalizeBatch(OperationProgress operation, List<FileProgress> fileProgresses) {
    if (operation.isCancelled) {
      operation.fail('Cancelled by user');
      return;
    }
    final failed = fileProgresses.where((f) => f.error != null).length;
    if (failed == fileProgresses.length) {
      operation.fail('All files failed');
    } else {
      operation.complete();
    }
  }

  // ---------------------------------------------------------------------------
  // Cross-provider comparison
  // ---------------------------------------------------------------------------

  /// Compare the contents of [pathA] on [clientA] against [pathB] on [clientB].
  ///
  /// Returns a list of [FileDiff] entries describing files that are unique to
  /// one side or differ in size or modification date.  Files that are identical
  /// (same name, size, and date) are omitted.
  Future<List<FileDiff>> compareFiles({
    required CloudStorageClient clientA,
    required String pathA,
    required CloudStorageClient clientB,
    required String pathB,
  }) async {
    _log.info(
      'Comparing ${clientA.providerName}:$pathA <-> ${clientB.providerName}:$pathB',
    );

    final resultA = await clientA.listPath(pathA);
    final resultB = await clientB.listPath(pathB);

    final mapA = <String, FileItem>{};
    final mapB = <String, FileItem>{};

    for (final raw in (resultA['files'] as List<dynamic>? ?? [])) {
      final item = _rawToFileItem(raw, pathA);
      mapA[item.name] = item;
    }
    for (final raw in (resultA['folders'] as List<dynamic>? ?? [])) {
      final item = _rawToFileItem(raw, pathA, isFolder: true);
      mapA[item.name] = item;
    }
    for (final raw in (resultB['files'] as List<dynamic>? ?? [])) {
      final item = _rawToFileItem(raw, pathB);
      mapB[item.name] = item;
    }
    for (final raw in (resultB['folders'] as List<dynamic>? ?? [])) {
      final item = _rawToFileItem(raw, pathB, isFolder: true);
      mapB[item.name] = item;
    }

    final diffs = <FileDiff>[];
    final allNames = {...mapA.keys, ...mapB.keys};

    for (final name in allNames) {
      final a = mapA[name];
      final b = mapB[name];

      if (a == null) {
        diffs.add(FileDiff(name: name, kind: FileDiffKind.onlyInB, itemB: b));
        continue;
      }
      if (b == null) {
        diffs.add(FileDiff(name: name, kind: FileDiffKind.onlyInA, itemA: a));
        continue;
      }

      final sizeDiff = a.size != null && b.size != null && a.size != b.size;
      final dateDiff = a.updatedAt != null &&
          b.updatedAt != null &&
          a.updatedAt!.difference(b.updatedAt!).abs() > const Duration(seconds: 2);

      if (sizeDiff && dateDiff) {
        diffs.add(FileDiff(name: name, kind: FileDiffKind.bothDiffer, itemA: a, itemB: b));
      } else if (sizeDiff) {
        diffs.add(FileDiff(name: name, kind: FileDiffKind.sizeDiffers, itemA: a, itemB: b));
      } else if (dateDiff) {
        diffs.add(FileDiff(name: name, kind: FileDiffKind.dateDiffers, itemA: a, itemB: b));
      }
      // Identical — omit
    }

    _log.info('Comparison found ${diffs.length} differences');
    return diffs;
  }

  FileItem _rawToFileItem(dynamic raw, String basePath, {bool isFolder = false}) {
    final name = raw['name'] as String? ?? '';
    final size = raw['size'] != null ? int.tryParse(raw['size'].toString()) : null;
    final updatedAt = raw['updatedAt'] != null
        ? DateTime.tryParse(raw['updatedAt'].toString())
        : null;
    return FileItem(
      name: name,
      isFolder: isFolder,
      path: '$basePath/$name',
      size: size,
      updatedAt: updatedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Unified search across providers
  // ---------------------------------------------------------------------------

  /// Search all [connections] concurrently for [query].
  ///
  /// Each provider is searched by listing its root and recursively matching
  /// names that contain [query] (case-insensitive).  Providers that natively
  /// support search via [listPath] are used directly.
  ///
  /// Returns a combined, labelled list of results.
  Future<List<MultiCloudSearchResult>> searchAcrossProviders(
    String query,
    List<CloudConnection> connections,
  ) async {
    if (query.trim().isEmpty) return [];
    _log.info('Unified search: "$query" across ${connections.length} providers');

    final futures = connections.map((conn) => _searchOneProvider(query, conn));
    final nested = await Future.wait(futures, eagerError: false);

    final results = <MultiCloudSearchResult>[];
    for (final list in nested) {
      results.addAll(list);
    }
    _log.info('Unified search returned ${results.length} total results');
    return results;
  }

  Future<List<MultiCloudSearchResult>> _searchOneProvider(
    String query,
    CloudConnection conn,
  ) async {
    try {
      final items = await _walkAndMatch(conn.client, conn.client.rootPath, query, depth: 0);
      return items
          .map((item) => MultiCloudSearchResult(
                connectionId: conn.id,
                connectionLabel: conn.label,
                providerName: conn.client.providerName,
                item: item,
              ))
          .toList();
    } catch (e) {
      _log.warn('Search failed on ${conn.label}', e);
      return [];
    }
  }

  Future<List<FileItem>> _walkAndMatch(
    CloudStorageClient client,
    String path,
    String query, {
    required int depth,
    int maxDepth = 3,
  }) async {
    if (depth > maxDepth) return [];

    final lowerQuery = query.toLowerCase();
    final result = await client.listPath(path);

    final matched = <FileItem>[];

    for (final raw in (result['files'] as List<dynamic>? ?? [])) {
      final name = raw['name'] as String? ?? '';
      if (name.toLowerCase().contains(lowerQuery)) {
        matched.add(_rawToFileItem(raw, path));
      }
    }

    for (final raw in (result['folders'] as List<dynamic>? ?? [])) {
      final name = raw['name'] as String? ?? '';
      final folderPath = '$path/$name';
      if (name.toLowerCase().contains(lowerQuery)) {
        matched.add(_rawToFileItem(raw, path, isFolder: true));
      }
      // Recurse into sub-folders
      try {
        final sub = await _walkAndMatch(client, folderPath, query, depth: depth + 1, maxDepth: maxDepth);
        matched.addAll(sub);
      } catch (_) {}
    }

    return matched;
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    _queue.dispose();
    for (final id in _connections.keys.toList()) {
      await removeConnection(id);
    }
  }
}

/// Download pipeline: single file, range, and batch downloads with
/// conflict handling and resume support.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:filen_client/api.dart';
import 'package:filen_client/cache.dart';
import 'package:filen_client/crypto.dart';
import 'package:filen_client/drive.dart';
import 'package:filen_client/memory_gate.dart';
import 'package:filen_client/utils.dart';

/// Chunk download concurrency (Step 1). N chunks fetched + decrypted at once,
/// bounded by a [ChunkSemaphore]; out-of-order completion is reassembled by
/// writing each chunk at its fixed file offset.
const int kDefaultDownloadConcurrency = 4;

/// Files with this many chunks or fewer keep the simple sequential path.
const int kSequentialDownloadChunkThreshold = 2;

const int _kDownloadChunkSize = 1048576;

class FilenDownload {
  final FilenApi api;
  final FilenCrypto crypto;
  final FilenCache cache;
  final FilenDrive drive;

  FilenDownload({
    required this.api,
    required this.crypto,
    required this.cache,
    required this.drive,
  });

  List<String> get masterKeys => drive.masterKeys;

  /// Download file with range support.
  Future<Uint8List> downloadFileRange(
    String uuid, {
    int? rangeStart,
    int? rangeEnd,
  }) async {
    api.log('Downloading file range: $uuid ($rangeStart-$rangeEnd)');

    final info = await api.post('/v3/file', {'uuid': uuid});
    final d = info['data'];
    final metaStr = await crypto.tryDecrypt(d['metadata'], masterKeys);
    final meta = json.decode(metaStr);
    final keyBytes = crypto.decodeUniversalKey(meta['key']);
    final chunks = int.parse(d['chunks'].toString());
    final host = 'https://egest.filen.io';

    const chunkSize = 1048576;
    final startChunk = rangeStart != null ? rangeStart ~/ chunkSize : 0;
    final endChunk = rangeEnd != null ? rangeEnd ~/ chunkSize : chunks - 1;

    final buffer = BytesBuilder();

    for (var i = startChunk; i <= endChunk && i < chunks; i++) {
      final r = await api.client
          .get(Uri.parse('$host/${d['region']}/${d['bucket']}/$uuid/$i'));
      if (r.statusCode != 200) {
        throw Exception('Chunk download failed: ${r.statusCode}');
      }

      var chunkBytes = await crypto.decryptData(r.bodyBytes, keyBytes);

      // Trim the tail of the last chunk, then the head of the first chunk.
      // Trimming end-before-start keeps both offsets relative to the chunk
      // start — required when the whole range lies within a single chunk
      // (start == end), where the previous if/else only trimmed the head.
      if (i == endChunk && rangeEnd != null) {
        final endOffset = rangeEnd % chunkSize + 1;
        if (endOffset < chunkBytes.length) {
          chunkBytes = chunkBytes.sublist(0, endOffset);
        }
      }
      if (i == startChunk && rangeStart != null) {
        chunkBytes = chunkBytes.sublist(rangeStart % chunkSize);
      }
      buffer.add(chunkBytes);
    }

    return buffer.toBytes();
  }

  /// Download file content as bytes (no disk I/O — needed for Web platform).
  Future<Uint8List> downloadFileBytes(
    String uuid, {
    int maxConcurrentChunks = kDefaultDownloadConcurrency,
    Function(int bytesDownloaded, int totalBytes)? onProgress,
  }) async {
    api.log('Downloading file bytes: $uuid');

    final info = await api.post('/v3/file', {'uuid': uuid});
    final d = info['data'];
    final metaStr = await crypto.tryDecrypt(d['metadata'], masterKeys);
    final meta = json.decode(metaStr);
    final keyBytes = crypto.decodeUniversalKey(meta['key']);
    final chunks = int.parse(d['chunks'].toString());
    final host = 'https://egest.filen.io';
    final fileSize = meta['size'] ?? 0;

    final useConcurrency =
        maxConcurrentChunks > 1 && chunks > kSequentialDownloadChunkThreshold;

    int bytesDownloaded = 0;

    if (!useConcurrency) {
      final buffer = BytesBuilder();
      for (var i = 0; i < chunks; i++) {
        final decrypted = await _fetchChunk(host, d, uuid, i, keyBytes);
        buffer.add(decrypted);
        bytesDownloaded += decrypted.length;
        if (onProgress != null) onProgress(bytesDownloaded, fileSize);
      }
      return buffer.toBytes();
    }

    // Fetch N chunks concurrently into ordered slots, then assemble in index
    // order. The whole file is held in memory regardless (this API returns the
    // full bytes); concurrency only overlaps the network fetches.
    final slots = List<Uint8List?>.filled(chunks, null);
    final sem = ChunkSemaphore(maxConcurrentChunks);
    final inflight = <Future<void>>[];
    Object? firstError;

    for (var i = 0; i < chunks; i++) {
      if (firstError != null) break;
      await sem.acquire();
      if (firstError != null) {
        sem.release();
        break;
      }
      final idx = i;
      inflight.add(() async {
        try {
          final decrypted = await _fetchChunk(host, d, uuid, idx, keyBytes);
          slots[idx] = decrypted;
          bytesDownloaded += decrypted.length;
          if (onProgress != null) onProgress(bytesDownloaded, fileSize);
        } catch (e) {
          firstError ??= e;
        } finally {
          sem.release();
        }
      }());
    }

    await Future.wait(inflight);
    if (firstError != null) throw firstError!;

    final buffer = BytesBuilder();
    for (var i = 0; i < chunks; i++) {
      buffer.add(slots[i]!);
    }
    return buffer.toBytes();
  }

  /// Fetch + decrypt a single chunk through the pooled client.
  Future<Uint8List> _fetchChunk(
      String host, dynamic d, String uuid, int i, Uint8List keyBytes) async {
    final r = await api.client
        .get(Uri.parse('$host/${d['region']}/${d['bucket']}/$uuid/$i'));
    if (r.statusCode != 200) {
      throw Exception('Chunk download failed: ${r.statusCode}');
    }
    return crypto.decryptData(r.bodyBytes, keyBytes);
  }

  /// Download a single file by UUID.
  Future<Map<String, dynamic>> downloadFile(
    String uuid, {
    String? savePath,
    int maxConcurrentChunks = kDefaultDownloadConcurrency,
    ChunkSemaphore? globalChunkSlots,
    Function(int bytesDownloaded, int totalBytes)? onProgress,
  }) async {
    api.log('Downloading file: $uuid');

    final info = await api.post('/v3/file', {'uuid': uuid});
    final d = info['data'];
    final metaStr = await crypto.tryDecrypt(d['metadata'], masterKeys);
    final meta = json.decode(metaStr);
    final keyBytes = crypto.decodeUniversalKey(meta['key']);
    final chunks = int.parse(d['chunks'].toString());
    final host = 'https://egest.filen.io';

    final filename = meta['name'] ?? 'file';
    final fileSize = meta['size'] ?? 0;
    final modificationTime = meta['lastModified'];

    if (onProgress == null) {
      print('   📄 File: $filename (${formatSize(fileSize)})');
    }

    final targetPath = savePath ?? filename;

    // Tiny files keep the simple sequential streaming path.
    final useConcurrency =
        maxConcurrentChunks > 1 && chunks > kSequentialDownloadChunkThreshold;

    int bytesDownloaded = 0;

    if (!useConcurrency) {
      final sink = File(targetPath).openWrite();
      try {
        for (var i = 0; i < chunks; i++) {
          // Shared batch budget (Step 2): one permit per chunk in flight across
          // the batch. No-op for a lone file (globalChunkSlots == null).
          if (globalChunkSlots != null) await globalChunkSlots.acquire();
          Uint8List decrypted;
          try {
            decrypted = await _fetchChunk(host, d, uuid, i, keyBytes);
          } finally {
            if (globalChunkSlots != null) globalChunkSlots.release();
          }
          sink.add(decrypted);
          bytesDownloaded += decrypted.length;
          if (onProgress != null) onProgress(bytesDownloaded, fileSize);
        }
      } finally {
        await sink.close();
      }
    } else {
      // Fetch N chunks concurrently and write each at its fixed offset (every
      // plaintext chunk is exactly 1 MB except the last), so out-of-order
      // completion still reassembles byte-exactly. A 1-permit lock serialises
      // the seek+write critical section. At most N decrypted chunks are live.
      final raf = await File(targetPath).open(mode: FileMode.write);
      try {
        if (fileSize is int && fileSize > 0) {
          await raf.truncate(fileSize);
        }
        final sem = ChunkSemaphore(maxConcurrentChunks);
        final writeLock = ChunkSemaphore(1);
        final inflight = <Future<void>>[];
        Object? firstError;

        for (var i = 0; i < chunks; i++) {
          if (firstError != null) break;
          await sem.acquire();
          if (firstError != null) {
            sem.release();
            break;
          }
          final idx = i;
          inflight.add(() async {
            try {
              // Shared batch budget (Step 2): bound chunk fetches in flight
              // across the WHOLE batch, not just this file.
              if (globalChunkSlots != null) await globalChunkSlots.acquire();
              Uint8List decrypted;
              try {
                decrypted = await _fetchChunk(host, d, uuid, idx, keyBytes);
              } finally {
                if (globalChunkSlots != null) globalChunkSlots.release();
              }
              await writeLock.acquire();
              try {
                await raf.setPosition(idx * _kDownloadChunkSize);
                await raf.writeFrom(decrypted);
              } finally {
                writeLock.release();
              }
              bytesDownloaded += decrypted.length;
              if (onProgress != null) onProgress(bytesDownloaded, fileSize);
            } catch (e) {
              firstError ??= e;
            } finally {
              sem.release();
            }
          }());
        }

        await Future.wait(inflight);
        if (firstError != null) throw firstError!;
      } finally {
        await raf.close();
      }
    }

    return {
      'data': await File(targetPath).readAsBytes(),
      'filename': filename,
      'modificationTime': modificationTime,
    };
  }

  /// Batch download by path with recursive support and resume.
  Future<void> downloadPath(
    String remotePath, {
    String? localDestination,
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
    int maxWorkers = kDefaultFileConcurrency,
  }) async {
    final itemInfo = await drive.resolvePath(remotePath);

    // Handle single file
    if (itemInfo['type'] == 'file') {
      final filename = p.basename(remotePath);
      if (!shouldIncludeFile(filename, include, exclude)) return;

      final localPath = localDestination != null &&
              FileSystemEntity.isDirectorySync(localDestination)
          ? p.join(localDestination, filename)
          : (localDestination ?? filename);

      if (File(localPath).existsSync() && onConflict == 'skip') {
        print('⏭️  Skipping: $filename (exists)');
        return;
      }

      print('📥 Downloading: $filename');
      await downloadFile(itemInfo['uuid'], savePath: localPath);
      print('✅ Downloaded: $localPath');
      return;
    }

    // Handle folder
    if (itemInfo['type'] != 'folder') throw Exception("Unknown type");
    if (!recursive) throw Exception("Use -r for recursive download");

    final baseDestPath =
        localDestination ?? (itemInfo['metadata']?['name'] ?? 'download');
    await Directory(baseDestPath).create(recursive: true);

    Map<String, dynamic> batchState;
    List<dynamic> tasks;

    if (initialBatchState != null) {
      print("🔄 Resuming batch...");
      batchState = initialBatchState;
      tasks = batchState['tasks'];
    } else {
      print("🔍 Building task list (Fast)...");
      tasks = [];

      final treeData = await drive.getFlatFolderTree(itemInfo['uuid']);
      final rawFolders = treeData['folders'] as List? ?? [];
      final rawFiles =
          (treeData['files'] as List?) ?? (treeData['uploads'] as List?) ?? [];

      final folderMap = <String, Map<String, dynamic>>{};
      for (var f in rawFolders) {
        try {
          String uuid, encName, parent;
          if (f is List) {
            if (f.length < 3) continue;
            uuid = f[0];
            encName = f[1];
            parent = f[2];
          } else {
            if (f['deleted'] == true || f['trash'] == true) continue;
            uuid = f['uuid'];
            encName = f['name'];
            parent = f['parent'];
          }
          var decName = await crypto.tryDecrypt(encName, masterKeys);
          if (decName.startsWith('{')) {
            decName = json.decode(decName)['name'];
          }
          folderMap[uuid] = {'name': decName, 'parent': parent};
        } catch (_) {}
      }

      String? getRelPath(String? parentUuid) {
        var parts = <String>[];
        var curr = parentUuid;
        var seen = <String>{};
        while (curr != null && curr != itemInfo['uuid']) {
          if (seen.contains(curr)) return null;
          seen.add(curr);
          if (!folderMap.containsKey(curr)) return null;
          final f = folderMap[curr]!;
          parts.add(f['name']);
          curr = f['parent'];
        }
        if (curr == null && itemInfo['uuid'] != 'root') return null;
        return parts.reversed.join(Platform.pathSeparator);
      }

      for (var f in rawFiles) {
        try {
          String uuid, encMeta, parent;
          if (f is List) {
            if (f.length < 6) continue;
            uuid = f[0];
            parent = f[4];
            encMeta = f[5];
          } else {
            if (f['deleted'] == true || f['trash'] == true) continue;
            uuid = f['uuid'];
            parent = f['parent'];
            encMeta = f['metadata'];
          }

          final decMeta = await crypto.tryDecrypt(encMeta, masterKeys);
          final meta = json.decode(decMeta);
          final filename = meta['name'];
          final lastMod = meta['lastModified'] ?? 0;

          if (!shouldIncludeFile(filename, include, exclude)) continue;

          var relDir = getRelPath(parent);
          if (parent == itemInfo['uuid'])
            relDir = '';
          else if (relDir == null) continue;

          final localPath = p.join(baseDestPath, relDir, filename);
          tasks.add({
            'remoteUuid': uuid,
            'localPath': localPath,
            'status': 'pending',
            'remoteModificationTime': lastMod,
          });
        } catch (e) {
          api.log("File parse error: $e");
        }
      }

      batchState = {
        'operationType': 'download',
        'remotePath': remotePath,
        'localDestination': baseDestPath,
        'tasks': tasks
      };
      await saveStateCallback(batchState);
      print("📝 Task list: ${tasks.length} files");
    }

    // Execution
    int successCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    int completedPreviously = 0;
    int processed = 0;
    final totalTasks = tasks.length;

    // Step 2: whole FILES downloaded at once. Capped at pending count, floored
    // at 1 (single file / maxWorkers<=1 → sequential path).
    final pending = [
      for (final t in tasks)
        if ((t as Map<String, dynamic>)['status'] != 'completed') t
    ];
    final effectiveWorkers =
        max(1, min(maxWorkers, pending.isEmpty ? 1 : pending.length));

    // Serialize the shared (whole-batchState) async saves under a 1-permit mutex.
    final saveMutex = ChunkSemaphore(1);
    Future<void> saveState() async {
      await saveMutex.acquire();
      try {
        await saveStateCallback(batchState);
      } finally {
        saveMutex.release();
      }
    }

    void tally(String token) {
      switch (token) {
        case 'completed':
          successCount++;
          break;
        case 'skipped':
          skippedCount++;
          break;
        case 'error':
          errorCount++;
          break;
        case 'already':
          completedPreviously++;
          break;
      }
      processed++;
      if (!api.debugMode) {
        final pct = totalTasks > 0
            ? (processed / totalTasks * 100).toStringAsFixed(1)
            : '0.0';
        stdout.write('\rDown: $processed/$totalTasks files ($pct%)  ');
      }
    }

    if (effectiveWorkers <= 1) {
      for (final t in tasks) {
        tally(await _downloadTask(
          t as Map<String, dynamic>,
          onConflict: onConflict,
          preserveTimestamps: preserveTimestamps,
          saveState: saveState,
          globalChunkSlots: null,
        ));
      }
    } else {
      final globalChunkSlots = ChunkSemaphore(kGlobalMaxInflightChunks);
      print(
          "  🧵 Downloading ${pending.length} file(s) with $effectiveWorkers worker(s)");
      await runWithConcurrency(tasks, effectiveWorkers, (t) async {
        tally(await _downloadTask(
          t as Map<String, dynamic>,
          onConflict: onConflict,
          preserveTimestamps: preserveTimestamps,
          saveState: saveState,
          globalChunkSlots: globalChunkSlots,
        ));
      });
    }

    print('\n' + '=' * 40);
    print('📊 Download Summary:');
    if (completedPreviously > 0) print('  ✅ Previous: $completedPreviously');
    print('  ✅ Downloaded: $successCount');
    print('  ⏭️  Skipped: $skippedCount');
    print('  ❌ Errors: $errorCount');
    print('=' * 40);
  }

  /// Download a single batch task; returns 'completed', 'skipped', 'error',
  /// or 'already'. Safe to run concurrently: it writes only its own local file
  /// + [task], routes state writes through the serialized [saveState], and
  /// shares the batch-wide [globalChunkSlots] budget.
  Future<String> _downloadTask(
    Map<String, dynamic> task, {
    required String onConflict,
    required bool preserveTimestamps,
    required Future<void> Function() saveState,
    required ChunkSemaphore? globalChunkSlots,
  }) async {
    final localPath = task['localPath'] as String;
    final remoteUuid = task['remoteUuid'] as String;
    final status = task['status'] as String;
    final remoteModTime = task['remoteModificationTime'];

    if (status == 'completed') return 'already';
    if (status.startsWith('skipped')) return 'skipped';

    await Directory(p.dirname(localPath)).create(recursive: true);
    final localFile = File(localPath);

    if (await localFile.exists()) {
      if (onConflict == 'skip') {
        task['status'] = 'skipped_conflict';
        await saveState();
        return 'skipped';
      }
      if (onConflict == 'newer' && remoteModTime != null) {
        final stat = await localFile.stat();
        if (stat.modified.millisecondsSinceEpoch >=
            (remoteModTime is int
                ? remoteModTime
                : int.parse(remoteModTime.toString()))) {
          task['status'] = 'skipped_newer';
          await saveState();
          return 'skipped';
        }
      }
    }

    try {
      final result = await downloadFile(remoteUuid,
          savePath: localPath, globalChunkSlots: globalChunkSlots);

      if (preserveTimestamps) {
        final mt = result['modificationTime'] ?? remoteModTime;
        if (mt != null) {
          try {
            final dt = mt is int
                ? DateTime.fromMillisecondsSinceEpoch(mt)
                : DateTime.parse(mt.toString());
            await localFile.setLastModified(dt);
          } catch (_) {}
        }
      }

      task['status'] = 'completed';
      await saveState();
      return 'completed';
    } catch (e) {
      if (api.debugMode) print("Error: $e");
      task['status'] = 'error_download';
      await saveState();
      return 'error';
    }
  }
}

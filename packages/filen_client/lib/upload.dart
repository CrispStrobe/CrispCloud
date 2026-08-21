/// Upload pipeline: chunked uploads with resume, batch operations,
/// and progress tracking.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:hex/hex.dart';
import 'package:path/path.dart' as p;

import 'package:filen_client/api.dart';
import 'package:filen_client/cache.dart';
import 'package:filen_client/crypto.dart';
import 'package:filen_client/drive.dart';
import 'package:filen_client/memory_gate.dart';
import 'package:filen_client/utils.dart';

/// Chunk transfer concurrency (Step 1). N chunks may be in flight at once,
/// bounded by both a [ChunkSemaphore] (count) and the [MemoryGate] (bytes), so
/// at most N×(plaintext + encrypted) chunks are ever live — important on mobile.
const int kDefaultUploadConcurrency = 4;

/// Files with this many chunks or fewer keep the simple sequential path — no
/// concurrency machinery is spun up (the overlap win doesn't pay for tiny files).
const int kSequentialChunkThreshold = 2;

/// Exception for chunk upload failures (carries resume state).
///
/// With concurrent uploads, chunks complete out of order, so resume can no
/// longer assume "all chunks < N are done". [completedChunks] carries the exact
/// set of indices that succeeded; [lastSuccessfulChunk] is kept as the
/// contiguous-prefix high-water mark for backward-compatible callers. [fileKey]
/// must be carried so a resumed upload reuses it — chunks already on the server
/// were encrypted with it.
class ChunkUploadException implements Exception {
  final String message;
  final String fileUuid;
  final String uploadKey;
  final int lastSuccessfulChunk;
  final Set<int> completedChunks;
  final String? fileKey;
  final Object? originalError;

  ChunkUploadException(
    this.message, {
    required this.fileUuid,
    required this.uploadKey,
    required this.lastSuccessfulChunk,
    Set<int>? completedChunks,
    this.fileKey,
    this.originalError,
  }) : completedChunks = completedChunks ?? <int>{};

  @override
  String toString() => 'ChunkUploadException: $message '
      '(uuid: $fileUuid, uploadKey: $uploadKey, lastChunk: $lastSuccessfulChunk)';
}

/// Largest M such that chunks 0..M are all in [completed] (else -1). Expresses
/// an out-of-order completed set as a backward-compatible high-water mark.
int contiguousCompletedMax(Set<int> completed) {
  var i = 0;
  while (completed.contains(i)) {
    i++;
  }
  return i - 1;
}

class FilenUpload {
  final FilenApi api;
  final FilenCrypto crypto;
  final FilenCache cache;
  final FilenDrive drive;
  final MemoryGate memoryGate;

  FilenUpload({
    required this.api,
    required this.crypto,
    required this.cache,
    required this.drive,
    MemoryGate? memoryGate,
  }) : memoryGate = memoryGate ??
            // Per-chunk byte budget (Step 1): a fixed ceiling on bytes in
            // flight, no per-chunk system-memory polling. 64 MB comfortably
            // holds the default 4–8 chunks (~2 MB each) without constraining
            // the degree, and is modest enough for mobile.
            MemoryGate(maxBytes: 64 * 1024 * 1024, safetyMarginBytes: 0);

  List<String> get masterKeys => drive.masterKeys;
  String get email => drive.email;

  Future<Map<String, String>> uploadFileChunked(
    File file,
    String parent, {
    String? fileUuid,
    String? creationTime,
    String? modificationTime,
    String? resumeUploadKey,
    int resumeFromChunk = 0,
    Set<int>? completedChunks,
    String? fileKey,
    int maxConcurrentChunks = kDefaultUploadConcurrency,
    ChunkSemaphore? globalChunkSlots,
    Function(int current, int total, int bytesUploaded, int totalBytes)?
        onProgress,
    Function(String uuid, String uploadKey, String fileKey)? onUploadStart,
    void Function(Set<int> completed)? onChunksCompleted,
  }) async {
    final name = p.basename(file.path);
    final size = await file.length();
    final uuid = fileUuid ?? crypto.uuid();
    final mk = masterKeys.last;
    if (mk.isEmpty) throw Exception('No master keys available');

    // Reuse the caller-supplied key when resuming so chunks uploaded across
    // attempts share one key (otherwise already-uploaded chunks would be
    // undecryptable). Generate a fresh key for new uploads.
    final fileKeyStr = fileKey ?? crypto.randomString(32);
    final fileKeyBytes = Uint8List.fromList(utf8.encode(fileKeyStr));

    var lastMod = modificationTime;
    if (lastMod == null && creationTime == null) {
      try {
        final stat = await file.stat();
        lastMod = stat.modified.millisecondsSinceEpoch.toString();
      } catch (_) {}
    }

    // Handle empty files
    if (size == 0) {
      api.log('Uploading empty file via /v3/upload/empty');

      final metaJson = json.encode({
        'name': name,
        'size': size,
        'mime': 'application/octet-stream',
        'key': fileKeyStr,
        'hash': '',
        'lastModified': lastMod != null
            ? int.tryParse(lastMod) ?? DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
      });

      final nameEncrypted = await crypto.encryptMetadata002(name, fileKeyStr);
      final sizeEncrypted =
          await crypto.encryptMetadata002(size.toString(), fileKeyStr);
      final mimeEncrypted = await crypto.encryptMetadata002(
          'application/octet-stream', fileKeyStr);
      final metadataEncrypted = await crypto.encryptMetadata002(metaJson, mk);
      final nameHashed = await crypto.hashFileName(name, masterKeys, email);

      await api.post('/v3/upload/empty', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'parent': parent,
        'mime': mimeEncrypted,
        'metadata': metadataEncrypted,
        'version': 2,
      });

      cache.invalidate(parent);
      if (onProgress != null) onProgress(1, 1, 0, 0);

      return {'uuid': uuid, 'hash': '', 'size': '0'};
    }

    // Regular chunked upload
    final uploadKey = resumeUploadKey ?? crypto.randomString(32);

    // Resume is a SET of completed indices, not a high-water mark: with
    // concurrent uploads chunks finish out of order. resumeFromChunk (legacy)
    // folds in as a contiguous range; completedChunks carries an exact set.
    final done = <int>{...?completedChunks};
    if (resumeFromChunk > 0) {
      for (var i = 0; i < resumeFromChunk; i++) {
        done.add(i);
      }
    }

    if (onUploadStart != null && done.isEmpty) {
      onUploadStart(uuid, uploadKey, fileKeyStr);
    }

    final rm = crypto.randomString(32);
    const chunkSz = 1048576;
    final totalChunks = (size / chunkSz).ceil();
    final ingest = 'https://ingest.filen.io';

    // Running SHA-512 over the *plaintext* chunks, in order — cannot be
    // parallelized. A sequential producer reads + hashes each chunk in order
    // (cheap) and hands the slow network POST to the bounded pool.
    final digestSink = DigestSink();
    final byteSink = crypto_pkg.sha512.startChunkedConversion(digestSink);

    final completed = <int>{...done};

    // POST one already-encrypted chunk; throws on a non-200 response.
    Future<void> postChunk(int idx, Uint8List enc) async {
      final hashHex =
          HEX.encode(crypto_pkg.sha512.convert(enc).bytes).toLowerCase();
      final url = Uri.parse(
          '$ingest/v3/upload?uuid=$uuid&index=$idx&parent=$parent&uploadKey=$uploadKey&hash=$hashHex');
      final r = await api.client.post(url, body: enc, headers: {
        'Authorization': 'Bearer ${api.apiKey}'
      }).timeout(Duration(seconds: 30));
      if (r.statusCode != 200) {
        throw Exception('Chunk upload failed: ${r.statusCode} - ${r.body}');
      }
    }

    void reportProgress() {
      if (onProgress != null) {
        final n = completed.length;
        onProgress(n, totalChunks, min(n * chunkSz, size), size);
      }
      onChunksCompleted?.call(Set.of(completed));
    }

    ChunkUploadException fail(int idx, Object e) {
      api.log('Chunk $idx failed: $e');
      return ChunkUploadException(
        'Chunk $idx upload failed',
        fileUuid: uuid,
        uploadKey: uploadKey,
        lastSuccessfulChunk: contiguousCompletedMax(completed),
        completedChunks: Set.of(completed),
        fileKey: fileKeyStr,
        originalError: e,
      );
    }

    // Tiny files (and concurrency disabled) keep the simple sequential path:
    // no semaphore, no MemoryGate — nothing is spun up.
    final useConcurrency =
        maxConcurrentChunks > 1 && totalChunks > kSequentialChunkThreshold;

    final raf = await file.open();
    try {
      if (useConcurrency) {
        // N chunk Futures in flight, bounded by BOTH a count semaphore and the
        // byte-budget MemoryGate (≈ N×(plaintext+encrypted) live at once).
        final sem = ChunkSemaphore(maxConcurrentChunks);
        final inflight = <Future<void>>[];
        final errors = <MapEntry<int, Object>>[];

        var idx = 0;
        var off = 0;
        while (off < size) {
          final len = min(chunkSz, size - off);
          final bytes = await raf.read(len);
          byteSink.add(bytes); // in-order plaintext hash (sequential producer)
          off += len;
          final myIdx = idx++;
          if (done.contains(myIdx)) continue;
          if (errors.isNotEmpty) break;

          await sem.acquire(); // bound concurrency by count
          if (errors.isNotEmpty) {
            sem.release();
            break;
          }
          final enc = await crypto.encryptData(bytes, fileKeyBytes);
          final budget = bytes.length + enc.length; // plaintext + encrypted
          await memoryGate.acquire(budget); // bound concurrency by bytes

          inflight.add(() async {
            try {
              // Shared batch budget (Step 2): bound the number of chunk POSTs
              // in flight across the WHOLE batch, not just this file. No-op when
              // uploading a single file (globalChunkSlots == null).
              if (globalChunkSlots != null) await globalChunkSlots.acquire();
              try {
                await postChunk(myIdx, enc);
              } finally {
                if (globalChunkSlots != null) globalChunkSlots.release();
              }
              completed.add(myIdx);
              reportProgress();
            } catch (e) {
              errors.add(MapEntry(myIdx, e));
            } finally {
              memoryGate.release(budget);
              sem.release();
            }
          }());
        }

        await Future.wait(inflight); // join all in-flight workers
        if (errors.isNotEmpty) {
          errors.sort((a, b) => a.key.compareTo(b.key));
          throw fail(errors.first.key, errors.first.value);
        }
      } else {
        var idx = 0;
        var off = 0;
        while (off < size) {
          final len = min(chunkSz, size - off);
          final bytes = await raf.read(len);
          byteSink.add(bytes); // in-order plaintext hash
          off += len;
          final myIdx = idx++;
          if (done.contains(myIdx)) continue;

          final enc = await crypto.encryptData(bytes, fileKeyBytes);
          // Shared batch budget (Step 2): one permit per chunk in flight across
          // the batch. No-op for a lone file (globalChunkSlots == null).
          if (globalChunkSlots != null) await globalChunkSlots.acquire();
          try {
            await postChunk(myIdx, enc);
          } catch (e) {
            throw fail(myIdx, e);
          } finally {
            if (globalChunkSlots != null) globalChunkSlots.release();
          }
          completed.add(myIdx);
          reportProgress();
        }
      }

      print('');

      byteSink.close();
      final totalHash = HEX.encode(digestSink.value?.bytes ?? []).toLowerCase();

      final metaJsonWithHash = json.encode({
        'name': name,
        'size': size,
        'mime': 'application/octet-stream',
        'key': fileKeyStr,
        'hash': totalHash,
        'lastModified': lastMod != null
            ? int.tryParse(lastMod) ?? DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
      });

      final nameEncrypted = await crypto.encryptMetadata002(name, fileKeyStr);
      final sizeEncrypted =
          await crypto.encryptMetadata002(size.toString(), fileKeyStr);
      final mimeEncrypted = await crypto.encryptMetadata002(
          'application/octet-stream', fileKeyStr);
      final metadataEncryptedWithHash =
          await crypto.encryptMetadata002(metaJsonWithHash, mk);
      final nameHashed = await crypto.hashFileName(name, masterKeys, email);

      await api.post('/v3/upload/done', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'chunks': totalChunks,
        'mime': mimeEncrypted,
        'rm': rm,
        'metadata': metadataEncryptedWithHash,
        'version': 2,
        'uploadKey': uploadKey,
      });

      cache.invalidate(parent);
      return {'uuid': uuid, 'hash': totalHash, 'size': size.toString()};
    } finally {
      await raf.close();
    }
  }

  /// Batch upload with resume, conflict handling, and progress tracking.
  Future<void> upload(
    List<String> sources,
    String targetPath, {
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
    Function(String filename, int current, int total, int bytesUploaded,
            int totalBytes)?
        onFileProgress,
    int maxWorkers = kDefaultFileConcurrency,
  }) async {
    api.log("Upload target path: $targetPath");

    Map<String, dynamic> batchState;
    List<dynamic> tasks;

    if (initialBatchState != null) {
      print("🔄 Resuming batch...");
      batchState = initialBatchState;
      tasks = batchState['tasks'] as List<dynamic>;
    } else {
      print("🔍 Building task list...");
      tasks = [];

      for (final sourceArg in sources) {
        if (sourceArg.contains('*') ||
            sourceArg.contains('?') ||
            sourceArg.contains('[')) {
          final glob = Glob(sourceArg.replaceAll('\\', '/'));
          await for (final entity in glob.list()) {
            await _processEntityForUpload(entity, sourceArg, targetPath,
                recursive, include, exclude, tasks, preserveTimestamps);
          }
        } else {
          final type = await FileSystemEntity.type(sourceArg);
          if (type == FileSystemEntityType.directory) {
            await _processEntityForUpload(
                Directory(sourceArg),
                sourceArg,
                targetPath,
                recursive,
                include,
                exclude,
                tasks,
                preserveTimestamps);
          } else if (type == FileSystemEntityType.file) {
            await _processEntityForUpload(
                File(sourceArg),
                sourceArg,
                targetPath,
                recursive,
                include,
                exclude,
                tasks,
                preserveTimestamps);
          } else {
            api.log("⚠️ Source not found: $sourceArg");
          }
        }
      }

      batchState = {
        'operationType': 'upload',
        'targetRemotePath': targetPath,
        'tasks': tasks,
      };
      await saveStateCallback(batchState);
      print("📝 Task list: ${tasks.length} files");
    }

    int successCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    int completedPreviously = 0;
    int processed = 0;
    final totalTasks = tasks.length;

    // Step 2: number of whole FILES uploaded at once. Capped at the count of
    // pending tasks and floored at 1 — a single file, or maxWorkers<=1, keeps
    // the sequential path (no shared budget, no pre-creation).
    final pending = [
      for (final t in tasks)
        if ((t as Map<String, dynamic>)['status'] != 'completed') t
    ];
    final effectiveWorkers =
        max(1, min(maxWorkers, pending.isEmpty ? 1 : pending.length));

    // saveStateCallback is async and shared (whole batchState). With files
    // completing out of order it must be serialized — a 1-permit semaphore
    // mutex prevents two concurrent file writers from interleaving.
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
        stdout.write('\rUp: $processed/$totalTasks files ($pct%)  ');
      }
    }

    if (effectiveWorkers <= 1) {
      // Sequential path: behaves exactly like the pre-Step-2 loop.
      for (final t in tasks) {
        tally(await _uploadTask(
          t as Map<String, dynamic>,
          parentMap: null,
          onConflict: onConflict,
          preserveTimestamps: preserveTimestamps,
          saveState: saveState,
          maxConcurrentChunks: kDefaultUploadConcurrency,
          globalChunkSlots: null,
        ));
      }
    } else {
      // Pre-create unique parent folders ONCE, before fan-out, so the shared
      // createFolderRecursive + cache-invalidation side effects can't race
      // across concurrent files (constraint 3).
      final parentMap = <String, Map<String, dynamic>>{};
      for (final t in pending) {
        final rp = p.dirname(t['remotePath'].toString()).replaceAll('\\', '/');
        if (parentMap.containsKey(rp)) continue;
        try {
          parentMap[rp] = await drive.createFolderRecursive(rp);
        } catch (e) {
          // Leave it unmapped; the per-task path retries and marks
          // error_parent — same outcome as the sequential path.
          api.log('Pre-create parent failed for $rp: $e');
        }
      }

      // ONE shared budget across files × chunks (constraint 2). Per-file chunk
      // concurrency is lowered too so no single file monopolizes the budget.
      final perFileChunks =
          max(1, kGlobalMaxInflightChunks ~/ effectiveWorkers);
      final globalChunkSlots = ChunkSemaphore(kGlobalMaxInflightChunks);
      print(
          "  🧵 Uploading ${pending.length} file(s) with $effectiveWorkers worker(s)");

      await runWithConcurrency(tasks, effectiveWorkers, (t) async {
        tally(await _uploadTask(
          t as Map<String, dynamic>,
          parentMap: parentMap,
          onConflict: onConflict,
          preserveTimestamps: preserveTimestamps,
          saveState: saveState,
          maxConcurrentChunks: perFileChunks,
          globalChunkSlots: globalChunkSlots,
        ));
      });
    }

    if (!api.debugMode) stdout.write('\n');

    print('=' * 40);
    print('📊 Upload Summary:');
    if (completedPreviously > 0) print('  ✅ Previous: $completedPreviously');
    print('  ✅ Uploaded: $successCount');
    print('  ⏭️  Skipped: $skippedCount');
    print('  ❌ Errors: $errorCount');
    print('=' * 40);

    if (errorCount > 0) throw Exception("Upload finished with errors");
  }

  /// Upload a single batch task; returns one of 'completed', 'skipped',
  /// 'error', 'already'. Safe to run concurrently: it mutates only its own
  /// [task], routes every state write through the serialized [saveState], and
  /// shares the batch-wide [globalChunkSlots] budget.
  Future<String> _uploadTask(
    Map<String, dynamic> task, {
    required Map<String, Map<String, dynamic>>? parentMap,
    required String onConflict,
    required bool preserveTimestamps,
    required Future<void> Function() saveState,
    required int maxConcurrentChunks,
    required ChunkSemaphore? globalChunkSlots,
  }) async {
    final localPath = task['localPath'] as String;
    final remotePath = task['remotePath'] as String;
    final status = task['status'] as String;
    final remoteName = p.basename(remotePath);

    if (status == 'completed') return 'already';
    if (status.startsWith('skipped')) return 'skipped';

    final localFile = File(localPath);
    if (!await localFile.exists()) {
      task['status'] = 'skipped_missing';
      await saveState();
      return 'skipped';
    }

    // Parent folder: pre-created before fan-out (parentMap) in the concurrent
    // path; created on demand for the sequential path / a missed parent.
    final remoteParentPath = p.dirname(remotePath).replaceAll('\\', '/');
    Map<String, dynamic>? parentInfo = parentMap?[remoteParentPath];
    if (parentInfo == null) {
      try {
        parentInfo = await drive.createFolderRecursive(remoteParentPath);
      } catch (e) {
        task['status'] = 'error_parent';
        await saveState();
        return 'error';
      }
    }

    if (task['fileUuid'] == null) {
      final cachedFiles = cache.fileCache[parentInfo['uuid']]?.items;
      bool exists = false;
      if (cachedFiles != null) {
        exists = (cachedFiles as List).any((f) => f['name'] == remoteName);
      } else {
        exists = await drive.checkFileExists(parentInfo['uuid'], remoteName);
      }
      if (exists && onConflict == 'skip') {
        task['status'] = 'skipped_conflict';
        await saveState();
        return 'skipped';
      }
    }

    try {
      String? cTime, mTime;
      if (preserveTimestamps) {
        final stat = await localFile.stat();
        mTime = stat.modified.millisecondsSinceEpoch.toString();
        cTime = stat.changed.millisecondsSinceEpoch.toString();
      }

      // Resume from the completed SET (legacy lastChunk folds into it).
      final resumeCompleted = <int>{
        ...((task['completedChunks'] as List?)?.cast<int>() ?? const []),
      };
      if ((task['lastChunk'] ?? -1) >= 0) {
        for (var i = 0; i <= (task['lastChunk'] as int); i++) {
          resumeCompleted.add(i);
        }
      }
      final isResuming = resumeCompleted.isNotEmpty;

      task['status'] = 'uploading';
      await saveState();

      await uploadFileChunked(
        localFile,
        parentInfo['uuid'],
        fileUuid: task['fileUuid'],
        resumeUploadKey: task['uploadKey'],
        fileKey: isResuming ? task['fileKey'] : null,
        completedChunks: isResuming ? resumeCompleted : null,
        creationTime: cTime,
        modificationTime: mTime,
        maxConcurrentChunks: maxConcurrentChunks,
        globalChunkSlots: globalChunkSlots,
        onUploadStart: (uuid, key, fkey) {
          task['fileUuid'] = uuid;
          task['uploadKey'] = key;
          task['fileKey'] = fkey;
          task['lastChunk'] = -1;
          task['completedChunks'] = <int>[];
          saveState();
        },
        // Chunks complete out of order: persist the exact set plus a
        // contiguous-safe high-water mark for legacy resume.
        onChunksCompleted: (completed) {
          task['completedChunks'] = completed.toList()..sort();
          task['lastChunk'] = contiguousCompletedMax(completed);
        },
      );

      task['status'] = 'completed';
      task['fileUuid'] = null;
      task['uploadKey'] = null;
      task['fileKey'] = null;
      task['lastChunk'] = -1;
      task['completedChunks'] = <int>[];
      await saveState();
      return 'completed';
    } on ChunkUploadException catch (e) {
      if (api.debugMode) print("\n❌ Upload error: $e");
      task['fileUuid'] = e.fileUuid;
      task['uploadKey'] = e.uploadKey;
      task['fileKey'] = e.fileKey;
      task['completedChunks'] = e.completedChunks.toList()..sort();
      task['lastChunk'] = e.lastSuccessfulChunk;
      task['status'] = 'interrupted';
      await saveState();
      return 'error';
    } catch (e) {
      if (api.debugMode) print("\n❌ Upload error: $e");
      task['status'] = 'interrupted';
      await saveState();
      return 'error';
    }
  }

  Future<void> _processEntityForUpload(
      FileSystemEntity entity,
      String sourceBase,
      String targetPath,
      bool recursive,
      List<String> include,
      List<String> exclude,
      List<dynamic> tasks,
      bool preserveTimestamps) async {
    if (entity is Directory) {
      if (!recursive) {
        api.log("Skipping directory: ${entity.path}");
        return;
      }

      final localDir = Directory(entity.path);
      String remoteBase;
      if (sourceBase.endsWith(Platform.pathSeparator) ||
          sourceBase == '.' ||
          sourceBase == './') {
        remoteBase = targetPath;
      } else {
        remoteBase =
            p.join(targetPath, p.basename(localDir.path)).replaceAll('\\', '/');
      }

      await drive.createFolderRecursive(remoteBase);

      await for (final fileEntity
          in localDir.list(recursive: true, followLinks: false)) {
        if (fileEntity is File) {
          final relPath = p.relative(fileEntity.path, from: localDir.path);
          final remotePath = p.join(remoteBase, relPath).replaceAll('\\', '/');

          if (shouldIncludeFile(
              p.basename(fileEntity.path), include, exclude)) {
            tasks.add({
              'localPath': fileEntity.path,
              'remotePath': remotePath,
              'status': 'pending',
              'fileUuid': null,
              'uploadKey': null,
              'lastChunk': -1,
            });
          }
        }
      }
    } else if (entity is File) {
      final remotePath =
          p.join(targetPath, p.basename(entity.path)).replaceAll('\\', '/');
      if (shouldIncludeFile(p.basename(entity.path), include, exclude)) {
        tasks.add({
          'localPath': entity.path,
          'remotePath': remotePath,
          'status': 'pending',
          'fileUuid': null,
          'uploadKey': null,
          'lastChunk': -1,
        });
      }
    }
  }

  /// Simple single-file upload (non-chunked, for small files / WebDAV).
  Future<void> uploadFile(File file, String parent,
      {String? creationTime, String? modificationTime}) async {
    await uploadFileChunked(file, parent,
        creationTime: creationTime, modificationTime: modificationTime);
  }

  /// Upload raw bytes from memory (needed for Web platform where File I/O
  /// is not available).
  Future<void> uploadBytes(
    Uint8List data,
    String fileName,
    String parentUuid, {
    int maxConcurrentChunks = kDefaultUploadConcurrency,
    Function(int bytesUploaded, int totalBytes)? onProgress,
  }) async {
    api.log(
        'Starting memory upload for $fileName (${formatSize(data.length)})');

    final size = data.length;
    final uuid = crypto.uuid();
    final mk = masterKeys.last;
    if (mk.isEmpty) throw Exception('No master keys available');

    final fileKeyStr = crypto.randomString(32);
    final fileKeyBytes = Uint8List.fromList(utf8.encode(fileKeyStr));

    if (size == 0) {
      final metaJson = json.encode({
        'name': fileName,
        'size': 0,
        'mime': 'application/octet-stream',
        'key': fileKeyStr,
        'hash': '',
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });

      final nameEncrypted =
          await crypto.encryptMetadata002(fileName, fileKeyStr);
      final sizeEncrypted = await crypto.encryptMetadata002('0', fileKeyStr);
      final mimeEncrypted = await crypto.encryptMetadata002(
          'application/octet-stream', fileKeyStr);
      final metadataEncrypted = await crypto.encryptMetadata002(metaJson, mk);
      final nameHashed = await crypto.hashFileName(fileName, masterKeys, email);

      await api.post('/v3/upload/empty', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'parent': parentUuid,
        'mime': mimeEncrypted,
        'metadata': metadataEncrypted,
        'version': 2,
      });

      if (onProgress != null) onProgress(0, 0);
      cache.invalidate(parentUuid);
      return;
    }

    final uploadKey = crypto.randomString(32);
    final rm = crypto.randomString(32);
    const chunkSz = 1048576;
    final ingest = 'https://ingest.filen.io';
    final totalChunks = (size / chunkSz).ceil();

    final digestSink = DigestSink();
    final byteSink = crypto_pkg.sha512.startChunkedConversion(digestSink);

    // POST one already-encrypted chunk with up to 3 retries; throws if all fail.
    Future<void> postChunk(int idx, Uint8List enc) async {
      final hashHex =
          HEX.encode(crypto_pkg.sha512.convert(enc).bytes).toLowerCase();
      final url = Uri.parse(
          '$ingest/v3/upload?uuid=$uuid&index=$idx&parent=$parentUuid&uploadKey=$uploadKey&hash=$hashHex');
      var retry = 0;
      while (true) {
        try {
          final r = await api.client.post(url, body: enc, headers: {
            'Authorization': 'Bearer ${api.apiKey}'
          }).timeout(Duration(seconds: 45));
          if (r.statusCode != 200) {
            throw Exception('Status ${r.statusCode}: ${r.body}');
          }
          return;
        } catch (e) {
          retry++;
          api.log('Chunk $idx failed (Attempt $retry): $e');
          if (retry >= 3) rethrow;
          await Future.delayed(Duration(seconds: 1));
        }
      }
    }

    // Tiny files keep the simple sequential path; larger ones overlap chunks
    // bounded by both the semaphore (count) and MemoryGate (bytes).
    final useConcurrency =
        maxConcurrentChunks > 1 && totalChunks > kSequentialChunkThreshold;
    var doneBytes = 0;

    if (useConcurrency) {
      final sem = ChunkSemaphore(maxConcurrentChunks);
      final inflight = <Future<void>>[];
      Object? firstError;

      var offset = 0;
      var index = 0;
      while (offset < size) {
        final end = min(size, offset + chunkSz);
        final chunkBytes = data.sublist(offset, end);
        byteSink.add(chunkBytes); // in-order plaintext hash
        offset = end;
        final myIdx = index++;
        if (firstError != null) break;

        await sem.acquire();
        if (firstError != null) {
          sem.release();
          break;
        }
        final enc = await crypto.encryptData(chunkBytes, fileKeyBytes);
        final budget = chunkBytes.length + enc.length;
        await memoryGate.acquire(budget);

        inflight.add(() async {
          try {
            await postChunk(myIdx, enc);
            doneBytes += chunkBytes.length;
            if (onProgress != null) onProgress(doneBytes, size);
          } catch (e) {
            firstError ??= e;
          } finally {
            memoryGate.release(budget);
            sem.release();
          }
        }());
      }

      await Future.wait(inflight);
      if (firstError != null) throw firstError!;
    } else {
      var offset = 0;
      var index = 0;
      while (offset < size) {
        final end = min(size, offset + chunkSz);
        final chunkBytes = data.sublist(offset, end);
        byteSink.add(chunkBytes); // in-order plaintext hash
        offset = end;
        final enc = await crypto.encryptData(chunkBytes, fileKeyBytes);
        await postChunk(index++, enc);
        doneBytes += chunkBytes.length;
        if (onProgress != null) onProgress(doneBytes, size);
      }
    }

    byteSink.close();
    final totalHash = HEX.encode(digestSink.value?.bytes ?? []).toLowerCase();

    final metaJsonWithHash = json.encode({
      'name': fileName,
      'size': size,
      'mime': 'application/octet-stream',
      'key': fileKeyStr,
      'hash': totalHash,
      'lastModified': DateTime.now().millisecondsSinceEpoch,
    });

    final nameEncrypted = await crypto.encryptMetadata002(fileName, fileKeyStr);
    final sizeEncrypted =
        await crypto.encryptMetadata002(size.toString(), fileKeyStr);
    final mimeEncrypted =
        await crypto.encryptMetadata002('application/octet-stream', fileKeyStr);
    final metadataEncryptedWithHash =
        await crypto.encryptMetadata002(metaJsonWithHash, mk);
    final nameHashed = await crypto.hashFileName(fileName, masterKeys, email);

    await api.post('/v3/upload/done', {
      'uuid': uuid,
      'name': nameEncrypted,
      'nameHashed': nameHashed,
      'size': sizeEncrypted,
      'chunks': totalChunks,
      'mime': mimeEncrypted,
      'rm': rm,
      'metadata': metadataEncryptedWithHash,
      'version': 2,
      'uploadKey': uploadKey,
    });

    cache.invalidate(parentUuid);
  }
}

// lib/providers/transfer_provider.dart
//
// Manages file transfers: upload/download via TransferQueue,
// operation tracking, pause/resume/cancel.
//
// On desktop/mobile, uploads and downloads use streaming I/O to avoid
// buffering entire files in memory.
// On web with browser support, downloads use showSaveFilePicker +
// WritableStream (no memory Blob) and uploads use FileReader slice reads.
// Older browsers fall back to byte-buffer methods.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/operation_progress.dart';
import '../models/panel_side.dart';
import '../services/audit_service.dart';
import '../services/s3_client_adapter.dart';
import '../services/transfer_queue.dart';
import '../services/web_streaming_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'panel_provider.dart';

class TransferNotifier extends ChangeNotifier {
  static const _log = Log('TransferNotifier');
  final Ref _ref;
  final TransferQueue _queue = TransferQueue();
  final List<OperationProgress> _operations = [];

  TransferNotifier(this._ref);

  List<OperationProgress> get operations => _operations;
  bool get hasActiveOperations => _operations.any((op) => !op.isComplete);

  void clearCompletedOperations() {
    _operations.removeWhere((op) => op.isComplete || op.isCancelled);
    notifyListeners();
  }

  void cancelAllOperations() {
    _queue.cancelAll();
    for (final operation in _operations.where((op) => !op.isComplete)) {
      operation.cancel();
    }
    notifyListeners();
  }

  void removeOperation(String id) {
    _operations.removeWhere((op) => op.id == id);
    notifyListeners();
  }

  void pauseOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.pause();
      notifyListeners();
    } catch (e) {
      _log.warn('pauseOperation failed', e);
    }
  }

  void resumeOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.resume();
      notifyListeners();
    } catch (e) {
      _log.warn('resumeOperation failed', e);
    }
  }

  void cancelOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.cancel();
      notifyListeners();
    } catch (e) {
      _log.warn('cancelOperation failed', e);
    }
  }

  Future<void> uploadFiles(List<FileItem> files, {String? targetPath}) async {
    final auth = _ref.read(authProvider);
    final localFileService = _ref.read(localFileServiceProvider);
    final client = auth.client;

    _log.info('UPLOAD: ${files.length} files via ${client.providerName}');
    await auth.ensureAuthenticated();

    final remotePath = _ref.read(panelProvider(PanelSide.remote)).currentPath;
    final target = targetPath ?? remotePath;

    final fileProgresses = <FileProgress>[];
    int totalBytes = 0;
    for (final file in files) {
      int fileSize = 0;
      if (file.isFolder && file.path != null) {
        fileSize = await _calculateFolderSize(file.path!, localFileService);
      } else {
        fileSize = file.size ?? 0;
      }
      fileProgresses
          .add(FileProgress(name: file.name, path: file.path!, size: fileSize));
      totalBytes += fileSize;
    }

    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.upload,
      sourcePath:
          files.length == 1 ? files.first.path! : '${files.length} files',
      targetPath: target,
      fileName: files.length == 1 ? files.first.name : '${files.length} files',
      totalBytes: totalBytes,
      files: fileProgresses,
    );

    _operations.add(operation);
    notifyListeners();

    int completedBytes = 0;
    int tasksFinished = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileProgress = fileProgresses[i];
      final taskId = '${operation.id}_upload_$i';

      _queue.enqueue(TransferTask(
        id: taskId,
        operation: operation,
        execute: () async {
          if (operation.isCancelled) return;
          if (operation.isPaused) await operation.pauseFuture;
          if (operation.isCancelled) return;

          if (file.path == null) {
            fileProgress.error = 'No path';
            return;
          }

          final audit = _ref.read(auditServiceProvider);
          try {
            if (file.isFolder) {
              await _uploadFolder(
                  file.path!, target, operation, client, localFileService);
            } else if (!kIsWeb && file.path != null) {
              // Streaming upload on desktop/mobile — avoids buffering entire
              // file in memory.  A StreamTransformer caps buffered-ahead
              // chunks at 2 to keep resident memory low.
              final localFile = File(file.path!);
              final length = await localFile.length();
              final rawStream = localFile.openRead();

              // Limit to 2 chunks buffered ahead via a back-pressure
              // transformer (StreamController in paused mode).
              final controller = StreamController<List<int>>();
              int pending = 0;
              const maxPending = 2;
              late StreamSubscription<List<int>> sub;
              sub = rawStream.listen(
                (chunk) {
                  controller.add(chunk);
                  pending++;
                  if (pending >= maxPending) sub.pause();
                },
                onDone: () => controller.close(),
                onError: (e, st) => controller.addError(e, st),
              );
              controller.onCancel = () => sub.cancel();
              controller.onResume = () {
                pending = 0;
                sub.resume();
              };

              await client.uploadStream(
                controller.stream,
                length,
                file.name,
                target,
                onProgress: (current, total) {
                  operation.currentBytes = completedBytes + current;
                  notifyListeners();
                },
              );
            } else {
              // Web upload path.
              // When a raw Blob reference exists (e.g. from directory-picker
              // grant), stream it in chunks rather than reading the whole file
              // into memory.
              final webStreaming = WebStreamingService();
              final blobRef =
                  kIsWeb ? localFileService.getWebFileRef(file.path!) : null;

              if (kIsWeb && webStreaming.isSupported && blobRef != null) {
                int sent = 0;
                final blobStream = webStreaming.streamFromBlob(blobRef);
                final trackedStream = blobStream.map((chunk) {
                  sent += chunk.length;
                  operation.currentBytes = completedBytes + sent;
                  notifyListeners();
                  return chunk;
                });

                final length = file.size ?? 0;
                await client.uploadStream(
                  trackedStream,
                  length,
                  file.name,
                  target,
                  onProgress: (current, total) {
                    operation.currentBytes = completedBytes + current;
                    notifyListeners();
                  },
                );
              } else {
                // Fallback for web: buffer-based upload (no Blob ref or older
                // browser without streaming support).
                final fileData =
                    await localFileService.readFile(file.path!, fileItem: file);
                await client.uploadFile(
                  fileData,
                  file.name,
                  target,
                  onProgress: (current, total) {
                    operation.currentBytes = completedBytes + current;
                    notifyListeners();
                  },
                );
              }
            }
            await audit.logSuccess(
              operation: AuditOperation.upload,
              sourcePath: file.path ?? file.name,
              targetPath: target,
              provider: client.providerName,
              sizeBytes: file.size,
            );
          } catch (e) {
            _log.warn('operation failed', e);
            fileProgress.error = e.toString();
            // If an S3 multipart upload was interrupted, persist state
            // for future resume.
            if (client is S3ClientAdapter) {
              try {
                await client.persistInterruptedUploads();
              } catch (e) {
                _log.warn('operation failed', e);
              }
            }
            await audit.logError(
              operation: AuditOperation.upload,
              sourcePath: file.path ?? file.name,
              targetPath: target,
              provider: client.providerName,
              error: e.toString(),
            );
            rethrow;
          }

          fileProgress.isComplete = true;
          completedBytes += fileProgress.size;
          operation.currentBytes = completedBytes;

          tasksFinished++;
          if (tasksFinished == files.length) {
            _finalizeBatch(operation, fileProgresses);
            await _ref.read(panelProvider(PanelSide.remote)).refresh();
            _ref.read(panelProvider(PanelSide.local)).clearSelection();
          }
        },
      ));
    }
  }

  Future<void> downloadFiles(List<FileItem> files, {String? localPath}) async {
    final auth = _ref.read(authProvider);
    final localFileService = _ref.read(localFileServiceProvider);
    final client = auth.client;

    _log.info('DOWNLOAD: ${files.length} files via ${client.providerName}');
    await auth.ensureAuthenticated();

    final target = localPath ?? localFileService.currentPath;
    final remotePath = _ref.read(panelProvider(PanelSide.remote)).currentPath;

    final fileProgresses = files
        .map((f) => FileProgress(
            name: f.name, path: f.uuid ?? f.name, size: f.size ?? 0))
        .toList();
    final totalBytes = files.fold(0, (sum, f) => sum + (f.size ?? 0));

    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.download,
      sourcePath:
          files.length == 1 ? files.first.name : '${files.length} files',
      targetPath: target,
      fileName: files.length == 1 ? files.first.name : '${files.length} files',
      totalBytes: totalBytes,
      files: fileProgresses,
    );

    _operations.add(operation);
    notifyListeners();

    int completedBytes = 0;
    int tasksFinished = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileProgress = fileProgresses[i];
      final taskId = '${operation.id}_download_$i';

      _queue.enqueue(TransferTask(
        id: taskId,
        operation: operation,
        execute: () async {
          if (operation.isCancelled) return;
          if (operation.isPaused) await operation.pauseFuture;
          if (operation.isCancelled) return;

          final fileRemotePath =
              file.path ?? p.posix.join(remotePath, file.name);
          final audit = _ref.read(auditServiceProvider);

          try {
            if (file.isFolder) {
              if (!kIsWeb) {
                await _downloadFolder(
                    fileRemotePath, target, operation, client);
              }
            } else if (!kIsWeb) {
              // Streaming download on desktop/mobile — pipe chunks to disk
              // without buffering the entire file in memory.
              final localFilePath = p.join(target, file.name);
              final sink = File(localFilePath).openWrite();
              int received = 0;

              try {
                await for (final chunk in client.downloadStream(
                  fileRemotePath,
                  onProgress: (current, total) {
                    // Some providers report progress via this callback;
                    // we also track via byte counting below.
                  },
                )) {
                  sink.add(chunk);
                  received += chunk.length;
                  operation.currentBytes = completedBytes + received;
                  notifyListeners();
                }
              } finally {
                await sink.close();
              }

              if (file.updatedAt != null) {
                try {
                  final f = File(localFilePath);
                  if (await f.exists())
                    await f.setLastModified(file.updatedAt!);
                } catch (e) {
                  _log.warn('operation failed', e);
                }
              }
            } else {
              // Web download path.
              // Prefer streaming via showSaveFilePicker + WritableStream so the
              // browser never buffers the entire file as a Blob in memory.
              final webStreaming = WebStreamingService();
              if (kIsWeb && webStreaming.isSupported) {
                int received = 0;
                final rawStream = client.downloadStream(
                  fileRemotePath,
                  onProgress: (current, total) {},
                );

                // Wrap the raw stream so we can track progress before piping
                // to the writable stream.
                final trackedStream = rawStream.map((chunk) {
                  received += chunk.length;
                  operation.currentBytes = completedBytes + received;
                  notifyListeners();
                  return chunk;
                });

                final saved = await webStreaming.downloadWithWritableStream(
                  trackedStream,
                  file.name,
                  totalSize: file.size,
                );

                if (!saved) {
                  // User cancelled the picker — treat as a no-op (not an error).
                  _log.info('DOWNLOAD: web streaming cancelled by user',
                      {'file': file.name});
                }
              } else {
                // Fallback for web browsers without showSaveFilePicker: load
                // into memory and hand off to the local file service (which on
                // web triggers a download-link click).
                final bytes = await client.downloadFileBytes(
                  fileRemotePath,
                  onProgress: (current, total) {
                    if (total > 0) {
                      operation.currentBytes = completedBytes + current;
                      notifyListeners();
                    }
                  },
                );

                final localFilePath = p.join(target, file.name);
                await localFileService.saveFile(localFilePath, bytes);
              }
            }
            await audit.logSuccess(
              operation: AuditOperation.download,
              sourcePath: fileRemotePath,
              targetPath: target,
              provider: client.providerName,
              sizeBytes: file.size,
            );
          } catch (e) {
            _log.warn('operation failed', e);
            fileProgress.error = e.toString();
            await audit.logError(
              operation: AuditOperation.download,
              sourcePath: fileRemotePath,
              targetPath: target,
              provider: client.providerName,
              error: e.toString(),
            );
            rethrow;
          }

          fileProgress.isComplete = true;
          completedBytes += fileProgress.size;
          operation.currentBytes = completedBytes;

          tasksFinished++;
          if (tasksFinished == files.length) {
            _finalizeBatch(operation, fileProgresses);
            await _ref.read(panelProvider(PanelSide.local)).refresh();
            _ref.read(panelProvider(PanelSide.remote)).clearSelection();
          }
        },
      ));
    }
  }

  // --- Helpers ---
  void _finalizeBatch(
      OperationProgress operation, List<FileProgress> fileProgresses) {
    if (operation.isCancelled) {
      operation.fail('Cancelled by user');
    } else {
      final failedCount = fileProgresses.where((f) => f.error != null).length;
      if (failedCount == 0) {
        operation.complete();
      } else if (failedCount == fileProgresses.length) {
        operation.fail('All files failed');
      } else {
        operation.complete();
      }
    }
    notifyListeners();
  }

  Future<int> _calculateFolderSize(
      String folderPath, dynamic localFileService) async {
    try {
      final entities = await localFileService.listDirectory(folderPath);
      if (entities == null) return 0;
      int totalSize = 0;
      for (final entity in entities) {
        if (entity is File) {
          try {
            totalSize += (await entity.stat()).size;
          } catch (e) {
            _log.warn('operation failed', e);
          }
        } else if (entity is Directory) {
          totalSize +=
              await _calculateFolderSize(entity.path, localFileService);
        }
      }
      return totalSize;
    } catch (e) {
      _log.warn('operation failed', e);
      return 0;
    }
  }

  Future<void> _uploadFolder(
    String localPath,
    String remotePath,
    OperationProgress operation,
    dynamic client,
    dynamic localFileService,
  ) async {
    if (kIsWeb) return;
    final folderName = p.basename(localPath);
    final newRemotePath = p.posix.join(remotePath, folderName);
    try {
      await client.createFolderPath(newRemotePath);
    } catch (_) {}

    final entities = await localFileService.listDirectory(localPath);
    if (entities == null) return;

    for (final entity in entities) {
      if (operation.isCancelled) break;
      if (entity is File) {
        try {
          final fileName = p.basename(entity.path);
          final fileData = await localFileService.readFile(entity.path);
          await client.uploadFile(fileData, fileName, newRemotePath);
          operation.currentBytes += fileData.length as int;
          notifyListeners();
        } catch (e) {
          _log.warn('operation failed', e);
        }
      } else if (entity is Directory) {
        await _uploadFolder(
            entity.path, newRemotePath, operation, client, localFileService);
      }
    }
  }

  Future<void> _downloadFolder(
    String remotePath,
    String localPath,
    OperationProgress operation,
    dynamic client,
  ) async {
    if (kIsWeb) return;
    final folderName = p.basename(remotePath);
    final newLocalPath = p.join(localPath, folderName);
    await Directory(newLocalPath).create(recursive: true);

    final contents = await client.listPath(remotePath);
    for (final file in contents['files']) {
      if (operation.isCancelled) break;
      final fileName = file['name'];
      final fileSize = int.tryParse(file['size']?.toString() ?? '0') ?? 0;
      await client.downloadFileByPath(
          p.posix.join(remotePath, fileName), p.join(newLocalPath, fileName));
      operation.currentBytes += fileSize;
      notifyListeners();
    }

    for (final folder in contents['folders']) {
      if (operation.isCancelled) break;
      await _downloadFolder(p.posix.join(remotePath, folder['name']),
          newLocalPath, operation, client);
    }
  }
}

final transferProvider = ChangeNotifierProvider<TransferNotifier>((ref) {
  return TransferNotifier(ref);
});

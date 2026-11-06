import 'package:crisp_storage/crisp_storage.dart' show TransferCancelled;
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
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';
import '../models/operation_progress.dart';
import '../models/transfer_job.dart';
import '../models/panel_side.dart';
import '../services/audit_service.dart';
import '../services/file_operation_service.dart';
import '../services/s3_client_adapter.dart';
import '../services/transfer_queue.dart';
import '../services/transfer_journal.dart';
import '../services/background_transfer_journal.dart';
import '../services/transfer_recovery_service.dart';
import '../models/integrity_recovery.dart';
import '../services/web_streaming_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'panel_provider.dart';

class TransferNotifier extends ChangeNotifier {
  static const _log = Log('TransferNotifier');
  final Ref _ref;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  final TransferQueue _queue = TransferQueue();
  final List<OperationProgress> _operations = [];
  final Map<String, FileOperationControl> _fileOperationControls = {};
  final Set<String> _integrityProgressIds = {};

  late final TransferJournal _journal;
  late final Future<void> ready;
  String? recoveryError;
  Future<void>? _backgroundRefresh;

  TransferNotifier(this._ref) {
    _journal = _ref.read(transferJournalProvider);
    _queue.addListener(notifyListeners);
    ready = _restore();
  }

  List<OperationProgress> get operations => List.unmodifiable(_operations);
  List<TransferJobRecord> get savedJobs => _journal.jobs;
  List<String> get recoveryWarnings => List.unmodifiable(_journal.warnings);
  TransferJobRecord? savedJob(String id) => _journal.job(id);
  bool get hasActiveOperations => _operations.any((op) => op.isActive);
  bool isJobLive(String id) =>
      _fileOperationControls.containsKey(id) || _journal.isOperationActive(id);
  int get maxConcurrent => _queue.maxConcurrent;
  int get queuedCount => _queue.pendingCount;
  List<String> get queuedIds =>
      _queue.pendingTasks.map((task) => task.id).toList();
  bool isQueued(String id) => _queue.pendingTasks.any((task) => task.id == id);
  int priorityOf(String id) => _journal.job(id)?.priority ?? 0;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final limit = prefs.getInt('commander_transfer_concurrency') ?? 3;
      _queue.setMaxConcurrent(limit.clamp(0, 16));
    } catch (error) {
      _log.warn('Could not load transfer concurrency', error);
    }
    try {
      await _journal.initialize();
      await _importBackgroundRecovery(addProgress: false);
      if (_disposed) return;
      for (final job in _journal.jobs.where((job) => job.needsReview)) {
        if (isIntegrityTransferJob(job) || isJobLive(job.id)) continue;
        _operations.add(_savedProgress(job));
      }
      _reconcileIntegrityProgress();
    } catch (error) {
      recoveryError = 'Saved transfer history could not be read: $error';
      _log.warn('Transfer recovery unavailable', error);
    }
    notifyListeners();
  }

  Future<void> refreshBackgroundRecovery() =>
      _backgroundRefresh ??= _refreshBackgroundRecovery().whenComplete(
        () => _backgroundRefresh = null,
      );

  /// Integrity owns its active progress/cancel UI. Keep only its stopped or
  /// newly completed rows in generic history, without touching queue jobs.
  Future<void> refreshIntegrityHistory() async {
    await ready;
    if (_disposed) return;
    _reconcileIntegrityProgress();
    notifyListeners();
  }

  void _reconcileIntegrityProgress() {
    final jobs = _journal.jobs.where(isIntegrityTransferJob).toList();
    final currentIds = jobs.map((job) => job.id).toSet();
    _operations.removeWhere(
      (operation) =>
          _integrityProgressIds.contains(operation.id) ||
          currentIds.contains(operation.id),
    );
    _integrityProgressIds.retainAll(currentIds);
    for (final job in jobs) {
      if (!job.isFinished) _integrityProgressIds.add(job.id);
      if (isJobLive(job.id)) continue;
      if (job.needsReview ||
          job.isFinished && _integrityProgressIds.contains(job.id)) {
        _operations.add(_savedProgress(job));
      }
    }
  }

  Future<void> _refreshBackgroundRecovery() async {
    await ready;
    if (_disposed) return;
    await _importBackgroundRecovery();
    notifyListeners();
  }

  Future<void> _importBackgroundRecovery({bool addProgress = true}) async {
    try {
      final result = await importBackgroundTransferJournals(_journal);
      for (final warning in result.warnings) {
        if (!_journal.warnings.contains(warning)) {
          _journal.warnings.add(warning);
        }
      }
      if (addProgress && !_disposed) {
        for (final job in _journal.jobs.where((job) => job.needsReview)) {
          if (isIntegrityTransferJob(job) || isJobLive(job.id)) continue;
          if (!_operations.any((operation) => operation.id == job.id)) {
            _operations.add(_savedProgress(job));
          }
        }
        _reconcileIntegrityProgress();
      }
    } catch (error) {
      final warning =
          'Background transfer history could not be imported: $error';
      if (!_journal.warnings.contains(warning)) _journal.warnings.add(warning);
      _log.warn('Background transfer recovery retained its journal', error);
    }
  }

  OperationProgress _savedProgress(TransferJobRecord job) {
    if (isIntegrityTransferJob(job)) return _savedIntegrityProgress(job);
    final files = job.entries
        .map(
          (entry) => FileProgress(
            name: entry.source.name,
            path: entry.source.path!,
            size: entry.source.isFolder ? 0 : entry.source.size ?? 0,
            isComplete: const [
              FileOperationOutcome.copied,
              FileOperationOutcome.moved,
              FileOperationOutcome.directoryCreated,
            ].contains(entry.outcome),
            error:
                const [
                  FileOperationOutcome.failed,
                  FileOperationOutcome.metadataFailed,
                ].contains(entry.outcome)
                ? entry.message
                : null,
            statusLabel: entry.outcome == FileOperationOutcome.needsDecision
                ? 'Waiting for a conflict decision'
                : entry.outcome.name,
          ),
        )
        .toList();
    final complete = job.status == TransferJobStatus.completed;
    final waiting = job.status == TransferJobStatus.waitingForDecision;
    return OperationProgress(
      id: job.id,
      type: job.options.kind == FileOperationKind.move
          ? OperationType.move
          : OperationType.copy,
      sourcePath: job.sourceLabel,
      targetPath: job.targetDirectory,
      fileName: '${files.length} saved items',
      files: files,
      totalBytes: files.fold(0, (sum, file) => sum + file.size),
      currentBytes: files
          .where((file) => file.isComplete)
          .fold(0, (sum, file) => sum + file.size),
      status: complete
          ? OperationStatus.completed
          : waiting
          ? OperationStatus.waitingForDecision
          : OperationStatus.failed,
      errorMessage: complete || waiting
          ? null
          : job.message ?? transferStatusLabel(job.status),
    );
  }

  OperationProgress _savedIntegrityProgress(TransferJobRecord job) {
    final header = job.entries.firstOrNull;
    final splitting = header?.recovery['integrityKind'] == 'split';
    final entries = splitting ? job.entries.skip(1) : job.entries.take(1);
    final files = entries.map((entry) {
      final rawSize = splitting
          ? entry.recovery['partSize']
          : entry.recovery['totalBytes'];
      return FileProgress(
        name: p.basename(entry.destination),
        path: entry.destination,
        size: rawSize is int ? rawSize : 0,
        isComplete: entry.recovery['confirmed'] is Map,
        statusLabel: entry.phase,
      );
    }).toList();
    final completed = job.isFinished;
    return OperationProgress(
      id: job.id,
      type: OperationType.copy,
      sourcePath: job.sourceLabel,
      targetPath: job.targetDirectory,
      fileName: header?.source.name ?? job.targetDirectory,
      files: files,
      totalBytes: files.fold(0, (sum, file) => sum + file.size),
      currentBytes: files
          .where((file) => file.isComplete)
          .fold(0, (sum, file) => sum + file.size),
      status: completed ? OperationStatus.completed : OperationStatus.failed,
      errorMessage: completed
          ? null
          : job.message ?? transferStatusLabel(job.status),
    );
  }

  String? statusLabel(String id) {
    final job = _journal.job(id);
    if (job == null) return null;
    if (isQueued(id)) return 'Queued · priority ${job.priority}';
    return transferStatusLabel(job.status);
  }

  Future<void> setConcurrency(int limit) async {
    if (limit < 0 || limit > 16) throw ArgumentError.value(limit, 'limit');
    await ready;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setInt('commander_transfer_concurrency', limit)) {
      throw StateError('Could not save transfer concurrency.');
    }
    _queue.setMaxConcurrent(limit);
  }

  Future<void> setPriority(String id, int priority) async {
    if (!isQueued(id)) return;
    final job = _journal.job(id);
    if (job != null) {
      await _journal.updateQueue(id, priority: priority);
    }
    _queue.setPendingPriority(id, priority);
    await _saveQueueOrder();
  }

  Future<void> reorderPending(int oldIndex, int newIndex) async {
    _queue.reorderPending(oldIndex, newIndex);
    await _saveQueueOrder();
  }

  Future<void> moveQueuedFirst(String id) async {
    _queue.movePendingToTop(id);
    await _saveQueueOrder();
  }

  Future<void> moveQueuedLast(String id) async {
    _queue.movePendingToBottom(id);
    await _saveQueueOrder();
  }

  Future<void> _saveQueueOrder() async {
    final ids = queuedIds;
    for (var i = 0; i < ids.length; i++) {
      final job = _journal.job(ids[i]);
      if (job != null) {
        await _journal.updateQueue(job.id, queueOrder: i);
      }
    }
    notifyListeners();
  }

  Future<void> dismissSavedJob(String id) async {
    await ready;
    if (isJobLive(id)) {
      throw StateError('Finish or cancel this transfer first.');
    }
    final job = _journal.job(id);
    if (job != null && isIntegrityTransferJob(job)) {
      await _journal.runExclusiveOperation(id, () => _journal.dismiss(id));
    } else {
      await _journal.dismiss(id);
    }
    _operations.removeWhere((operation) => operation.id == id);
    notifyListeners();
  }

  Future<void> clearSavedCompleted() async {
    await ready;
    for (final job in _journal.jobs.where((job) => job.isFinished)) {
      if (!isJobLive(job.id)) {
        if (isIntegrityTransferJob(job)) {
          await _journal.runExclusiveOperation(
            job.id,
            () => _journal.dismiss(job.id),
          );
        } else {
          await _journal.dismiss(job.id);
        }
      }
    }
    await _journal.compact();
    _operations.removeWhere(
      (operation) => operation.status == OperationStatus.completed,
    );
    notifyListeners();
  }

  /// Restores a reviewed backup only into a vacant original location. The
  /// rename intent is durable before the storage operation starts.
  Future<void> restoreSavedBackup(
    String id,
    int index,
    FileOperationBackend destination,
    FileOperationControl control,
  ) async {
    await ready;
    final job = _journal.job(id);
    if (job == null || isJobLive(id)) {
      throw StateError('Transfer is unavailable or active.');
    }
    final saved = job.entries[index];
    final entry =
        FileOperationEntry(
            saved.source,
            saved.destination,
            existing: saved.existing,
          )
          ..outcome = saved.outcome
          ..message = saved.message
          ..recovery = Map.of(saved.recovery);
    await const TransferRecoveryService().restoreBackup(
      job,
      saved,
      destination,
      control,
      checkpoint: (phase) async {
        entry.recovery = {...?entry.recovery, 'phase': phase};
        if (phase == 'backupRestored') {
          entry.message = 'Previous destination restored from verified backup.';
        }
        await _journal.checkpoint(id, index, entry, phase);
      },
    );
    notifyListeners();
  }

  void clearCompletedOperations() {
    _operations.removeWhere((op) => op.isComplete || op.isCancelled);
    _queue.clearCompleted();
    notifyListeners();
  }

  void cancelAllOperations() {
    for (final operation in _operations.where(
      (op) => op.isWaitingForDecision,
    )) {
      unawaited(_cancelWaitingJob(operation.id));
    }
    for (final control in _fileOperationControls.values) {
      control.cancel();
    }
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

  Future<void> _saveLiveStatus(String id, TransferJobStatus status) async {
    if (!_fileOperationControls.containsKey(id)) return;
    try {
      await _journal.setStatus(
        id,
        status,
        onlyIf: const {
          TransferJobStatus.queued,
          TransferJobStatus.running,
          TransferJobStatus.paused,
        },
      );
    } catch (error) {
      recoveryError = 'Could not save the transfer state: $error';
      _fileOperationControls[id]?.cancel();
    }
    notifyListeners();
  }

  void pauseOperation(String operationId) {
    _fileOperationControls[operationId]?.pause();
    for (final operation in _operations.where((op) => op.id == operationId)) {
      operation.pause();
    }
    unawaited(_saveLiveStatus(operationId, TransferJobStatus.paused));
    _queue.refresh();
  }

  void resumeOperation(String operationId) {
    _fileOperationControls[operationId]?.resume();
    for (final operation in _operations.where((op) => op.id == operationId)) {
      operation.resume();
    }
    unawaited(
      _saveLiveStatus(
        operationId,
        isQueued(operationId)
            ? TransferJobStatus.queued
            : TransferJobStatus.running,
      ),
    );
    _queue.refresh();
  }

  void cancelOperation(String operationId) {
    if (_operations.any(
      (op) => op.id == operationId && op.isWaitingForDecision,
    )) {
      unawaited(_cancelWaitingJob(operationId));
    }
    _fileOperationControls[operationId]?.cancel();
    for (final operation in _operations.where((op) => op.id == operationId)) {
      operation.cancel();
    }
    for (final task in [..._queue.pendingTasks, ..._queue.activeTasks]) {
      if (task.operation.id == operationId) _queue.cancel(task.id);
    }
    notifyListeners();
  }

  Future<void> _cancelWaitingJob(String id) async {
    try {
      await _journal.setStatus(
        id,
        TransferJobStatus.cancelled,
        message: 'Cancelled while waiting for a conflict decision. Saved progress can be reviewed later.',
        onlyIf: const {TransferJobStatus.waitingForDecision},
      );
    } catch (error) {
      recoveryError = 'Could not save the transfer state: $error';
    }
    notifyListeners();
  }

  /// The journal is flushed before a queue item can mutate storage. Recovery
  /// reuses the same stable entry indices and never auto-retries a partial job.
  Future<void> runFileOperation(
    FileOperationPlan plan, {
    required FileOperationControl control,
    FileConflictResolver? resolveConflict,
    DetailedFileConflictResolver? resolveDetailedConflict,
    void Function(FileOperationEntry, int, int?)? onProgress,
    void Function(FileOperationEntry)? onEntryComplete,
    VoidCallback? onQueued,
    String? recoveryJobId,
    int priority = 0,
  }) async {
    await ready;
    if (recoveryError != null) throw StateError(recoveryError!);
    if (!plan.canExecute && (recoveryJobId == null || plan.errors.isNotEmpty)) {
      throw StateError('Review a valid operation plan first.');
    }
    if (_disposed) throw StateError('The transfer queue is closed.');
    final id =
        recoveryJobId ?? 'commander_${DateTime.now().microsecondsSinceEpoch}';
    if (isJobLive(id)) throw StateError('This transfer is already queued.');
    TransferJobRecord job;
    if (recoveryJobId == null) {
      job = await _journal.create(id, plan, priority: priority);
    } else {
      final saved = _journal.job(id);
      if (saved != null && isIntegrityTransferJob(saved)) {
        throw StateError('Use Split/combine recovery for this operation.');
      }
      if (saved == null ||
          !saved.ready ||
          saved.entries.length != plan.entries.length ||
          saved.source != plan.source.storageReference ||
          saved.destination != plan.destination.storageReference) {
        throw StateError('The recovery plan does not belong to this transfer.');
      }
      job = saved;
      for (var i = 0; i < saved.entries.length; i++) {
        if (saved.entries[i].source.path != plan.entries[i].source.path) {
          throw StateError('Recovery must retain the original source entries.');
        }
      }
      if (saved.protectedDestinationPaths.any(
        (path) => !plan.protectedDestinationPaths.contains(path),
      )) {
        throw StateError('Recovery must retain protected selected sources.');
      }
      await _journal.saveReviewedOptions(id, plan.options);
      await _journal.saveEntries(id, plan.entries);
      await _journal.setStatus(id, TransferJobStatus.queued);
      priority = saved.priority;
    }
    _operations.removeWhere((operation) => operation.id == id);
    // A lost response can be reconciled entirely by read-only verification.
    if (!plan.canExecute) {
      await _journal.setStatus(
        id,
        TransferJobStatus.completed,
        message: 'All remaining items reconciled or explicitly excluded.',
      );
      _operations.add(_savedProgress(job));
      for (final entry in plan.entries) {
        onEntryComplete?.call(entry);
      }
      notifyListeners();
      return;
    }
    final rows = {
      for (final entry in plan.entries)
        entry: FileProgress(
          name: entry.source.name,
          path: entry.source.path!,
          size: entry.source.isFolder ? 0 : entry.source.size ?? 0,
          isComplete: entry.completed,
          statusLabel: entry.outcome == FileOperationOutcome.pending
              ? null
              : entry.outcome.name,
        ),
    };
    final operation = OperationProgress(
      id: id,
      type: plan.options.kind == FileOperationKind.move
          ? OperationType.move
          : OperationType.copy,
      sourcePath: plan.source.label,
      targetPath: plan.targetDirectory,
      fileName: '${plan.fileCount} files',
      totalBytes: plan.entries
          .where((entry) => !entry.source.isFolder)
          .fold(0, (sum, entry) => sum + (entry.source.size ?? 0)),
      files: rows.values.toList(),
    );
    final done = Completer<void>();
    final audit = _ref.read(auditServiceProvider);
    _operations.add(operation);
    _fileOperationControls[operation.id] = control;
    notifyListeners();
    var completedBytes = rows.values
        .where((row) => row.isComplete)
        .fold(0, (sum, row) => sum + row.size);
    final counted = plan.entries.where((entry) => entry.completed).toSet();
    final transferSizes = {
      for (final entry in plan.entries) entry: rows[entry]!.size,
    };
    var started = false;
    _queue.enqueue(
      TransferTask(
        id: id,
        operation: operation,
        providerName:
            plan.destination.persistentStorageId ?? plan.destination.label,
        priority: priority,
        execute: () async {
          started = true;
          // The service records failures. Do not return them to the queue's
          // transient-network retry loop after partial destructive work.
          try {
            await JournaledTransferRunner(_journal).execute(
              id,
              plan,
              control: control,
              resolveConflict: resolveConflict,
              resolveDetailedConflict: resolveDetailedConflict,
              onPhase: (_, phase) {
                notifyListeners();
              },
              onProgress: (entry, bytes, total) {
                if (total != null && total != transferSizes[entry]) {
                  operation.totalBytes += total - transferSizes[entry]!;
                  transferSizes[entry] = total;
                }
                operation.updateProgress(completedBytes + bytes);
                onProgress?.call(entry, bytes, total);
                notifyListeners();
              },
              onEntryComplete: (entry) {
                final row = rows[entry]!;
                row.isComplete = entry.completed;
                row.error = entry.failed ? entry.message : null;
                row.statusLabel =
                    entry.outcome == FileOperationOutcome.needsDecision
                    ? 'Waiting for a conflict decision'
                    : entry.outcome.name;
                if (entry.completed && counted.add(entry)) {
                  completedBytes += transferSizes[entry]!;
                }
                operation.currentBytes = completedBytes;
                onEntryComplete?.call(entry);
                notifyListeners();
              },
            );
            final waiting = plan.entries.any(
              (entry) => entry.outcome == FileOperationOutcome.needsDecision,
            );
            if (control.isCancelled) {
              operation.cancel();
            } else if (waiting) {
              // A background conflict stops the service with remaining rows
              // still pending. Never report that partially executed plan as
              // complete, or invite a retry of the already completed rows.
              for (final entry in plan.entries.where(
                (entry) => entry.outcome == FileOperationOutcome.pending,
              )) {
                rows[entry]!.statusLabel =
                    'Not started (awaiting conflict decision)';
              }
              operation.waitForDecision();
            } else if (plan.entries.any((entry) => entry.failed)) {
              operation.fail(
                '${plan.entries.where((entry) => entry.failed).length} item(s) need review.',
              );
            } else {
              operation.status = OperationStatus.completed;
              operation.totalBytes = completedBytes;
              operation.currentBytes = completedBytes;
            }
            // Audit failures must not turn a verified transfer into a retry.
            try {
              for (final entry in plan.entries) {
                if (entry.completed) {
                  await audit.logSuccess(
                    operation: entry.outcome == FileOperationOutcome.moved
                        ? AuditOperation.move
                        : AuditOperation.copy,
                    sourcePath: entry.source.path!,
                    targetPath: entry.destination,
                    provider: plan.destination.label,
                    sizeBytes: entry.source.size,
                  );
                } else if (entry.failed) {
                  await audit.logError(
                    operation: plan.options.kind == FileOperationKind.move
                        ? AuditOperation.move
                        : AuditOperation.copy,
                    sourcePath: entry.source.path!,
                    targetPath: entry.destination,
                    provider: plan.destination.label,
                    error: entry.message ?? 'Operation failed',
                  );
                }
              }
            } catch (error) {
              _log.warn('Transfer audit could not be saved', error);
            }
          } catch (error) {
            operation.fail(error.toString());
          }
        },
        onDone: (error) async {
          try {
            if (!started || operation.isCancelled || control.isCancelled) {
              control.cancel();
              for (final entry in plan.entries.where(
                (entry) => entry.outcome == FileOperationOutcome.pending,
              )) {
                entry.outcome = FileOperationOutcome.cancelled;
                entry.message = 'Cancelled before starting.';
                rows[entry]!.statusLabel = 'cancelled';
                onEntryComplete?.call(entry);
              }
              await _journal.saveEntries(id, plan.entries);
              await _journal.setStatus(
                id,
                TransferJobStatus.cancelled,
                message: 'Cancelled. Review the saved transfer to retry unfinished items.',
              );
            }
            if (error != null && error is! TransferCancelled) {
              operation.fail(error.toString());
            }
          } catch (error) {
            recoveryError = 'Could not save transfer completion: $error';
            operation.fail(recoveryError!);
          } finally {
            _fileOperationControls.remove(id);
            notifyListeners();
            if (!done.isCompleted) done.complete();
          }
        },
      ),
    );
    onQueued?.call();
    unawaited(
      Future.any([control.cancellationFuture, done.future]).then((_) {
        if (control.isCancelled && _fileOperationControls.containsKey(id)) {
          cancelOperation(id);
        }
      }),
    );
    await done.future;
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
      fileProgresses.add(
        FileProgress(name: file.name, path: file.path!, size: fileSize),
      );
      totalBytes += fileSize;
    }

    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.upload,
      sourcePath: files.length == 1
          ? files.first.path!
          : '${files.length} files',
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

      _queue.enqueue(
        TransferTask(
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
                  file.path!,
                  target,
                  operation,
                  client,
                  localFileService,
                );
              } else if (!kIsWeb && file.path != null) {
                final localFile = File(file.path!);
                final length = await localFile.length();
                await client.uploadStream(
                  localFile.openRead().asyncMap((chunk) async {
                    await _checkpoint(operation);
                    return chunk;
                  }),
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
                final blobRef = kIsWeb
                    ? localFileService.getWebFileRef(file.path!)
                    : null;

                if (kIsWeb && webStreaming.isSupported && blobRef != null) {
                  int sent = 0;
                  final blobStream = webStreaming.streamFromBlob(blobRef);
                  final trackedStream = blobStream.asyncMap((chunk) async {
                    await _checkpoint(operation);
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
                  final fileData = await localFileService.readFile(
                    file.path!,
                    fileItem: file,
                  );
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
          },
          onDone: (error) {
            fileProgress.error = error?.toString();
            tasksFinished++;
            if (tasksFinished == files.length) {
              _finalizeBatch(operation, fileProgresses);
              if (!_disposed) unawaited(_refreshAfterTransfer());
            }
          },
        ),
      );
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
        .map(
          (f) => FileProgress(
            name: f.name,
            path: f.uuid ?? f.name,
            size: f.size ?? 0,
          ),
        )
        .toList();
    final totalBytes = files.fold(0, (sum, f) => sum + (f.size ?? 0));

    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.download,
      sourcePath: files.length == 1
          ? files.first.name
          : '${files.length} files',
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

      _queue.enqueue(
        TransferTask(
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
                    fileRemotePath,
                    target,
                    operation,
                    client,
                  );
                }
              } else if (!kIsWeb) {
                // Streaming download on desktop/mobile — pipe chunks to disk
                // without buffering the entire file in memory.
                final localFilePath = _localTarget(target, file.name);
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
                    await _checkpoint(operation);
                    sink.add(chunk);
                    await sink.flush();
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
                    if (await f.exists()) {
                      await f.setLastModified(file.updatedAt!);
                    }
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
                  final trackedStream = rawStream.asyncMap((chunk) async {
                    await _checkpoint(operation);
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
                    _log.info('DOWNLOAD: web streaming cancelled by user', {
                      'file': file.name,
                    });
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

                  await _checkpoint(operation);
                  final localFilePath = _localTarget(target, file.name);
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
          },
          onDone: (error) {
            fileProgress.error = error?.toString();
            tasksFinished++;
            if (tasksFinished == files.length) {
              _finalizeBatch(operation, fileProgresses);
              if (!_disposed) unawaited(_refreshAfterTransfer());
            }
          },
        ),
      );
    }
  }

  Future<void> _refreshAfterTransfer() async {
    try {
      await _ref.read(panelProvider(PanelSide.local)).refresh();
      await _ref.read(panelProvider(PanelSide.remote)).refresh();
    } catch (error) {
      _log.warn('Refreshing panels after transfer failed', error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final control in _fileOperationControls.values) {
      control.cancel();
    }
    _queue.dispose();
    super.dispose();
  }

  // --- Helpers ---
  void _finalizeBatch(
    OperationProgress operation,
    List<FileProgress> fileProgresses,
  ) {
    if (operation.isCancelled) {
      operation.fail('Cancelled by user');
    } else {
      final failedCount = fileProgresses.where((f) => f.error != null).length;
      if (failedCount == 0) {
        operation.complete();
      } else if (failedCount == fileProgresses.length) {
        operation.fail('All files failed');
      } else {
        operation.fail('$failedCount of ${fileProgresses.length} files failed');
      }
    }
    notifyListeners();
  }

  Future<int> _calculateFolderSize(
    String folderPath,
    dynamic localFileService,
  ) async {
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
          totalSize += await _calculateFolderSize(
            entity.path,
            localFileService,
          );
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
      await _checkpoint(operation);
      if (entity is File) {
        try {
          final fileName = p.basename(entity.path);
          final fileData = await localFileService.readFile(entity.path);
          await client.uploadFile(fileData, fileName, newRemotePath);
          operation.currentBytes += fileData.length as int;
          notifyListeners();
        } catch (e) {
          _log.warn('operation failed', e);
          rethrow;
        }
      } else if (entity is Directory) {
        await _uploadFolder(
          entity.path,
          newRemotePath,
          operation,
          client,
          localFileService,
        );
      }
    }
  }

  String _localTarget(String directory, String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\x00')) {
      throw const FormatException('The server returned an invalid file name');
    }
    return p.join(directory, name);
  }

  Future<void> _checkpoint(OperationProgress operation) async {
    if (operation.isPaused) await operation.pauseFuture;
    if (operation.isCancelled) throw const TransferCancelled();
  }

  Future<void> _downloadFolder(
    String remotePath,
    String localPath,
    OperationProgress operation,
    dynamic client,
  ) async {
    if (kIsWeb) return;
    final folderName = p.basename(remotePath);
    final newLocalPath = _localTarget(localPath, folderName);
    await Directory(newLocalPath).create(recursive: true);

    final contents = await client.listPath(remotePath);
    for (final file in contents['files']) {
      await _checkpoint(operation);
      final fileName = file['name'];
      final sink = File(_localTarget(newLocalPath, fileName)).openWrite();
      try {
        await for (final chunk in client.downloadStream(
          p.posix.join(remotePath, fileName),
        )) {
          await _checkpoint(operation);
          sink.add(chunk);
          await sink.flush();
          operation.currentBytes += (chunk as List<int>).length;
          notifyListeners();
        }
      } finally {
        await sink.close();
      }
      notifyListeners();
    }

    for (final folder in contents['folders']) {
      await _checkpoint(operation);
      await _downloadFolder(
        p.posix.join(remotePath, folder['name']),
        newLocalPath,
        operation,
        client,
      );
    }
  }
}

final transferProvider = ChangeNotifierProvider<TransferNotifier>((ref) {
  return TransferNotifier(ref);
});

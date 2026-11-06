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
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/operation_progress.dart';
import '../models/transfer_job.dart';
import '../models/transfer_queue_summary.dart';
import '../models/panel_side.dart';
import '../services/audit_service.dart';
import '../services/file_operation_service.dart';
import '../services/s3_client_adapter.dart';
import '../services/transfer_queue.dart';
import '../services/transfer_journal.dart';
import '../services/background_transfer_journal.dart';
import '../services/transfer_recovery_service.dart';
import '../services/transfer_resource_claims.dart';
import '../models/integrity_recovery.dart';
import '../services/web_streaming_service.dart';
import '../services/log_service.dart';
import '../utils/async_lock.dart';
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
  final Map<String, StreamSubscription<void>> _controlSubscriptions = {};
  final Map<String, Set<FileOperationEntry>> _unknownFileSizes = {};
  final Set<String> _integrityProgressIds = {};
  final AsyncLock _queueConfiguration = AsyncLock();
  List<TransferTask> _pendingTasks = const [];
  final Map<String, TransferTask> _firstPendingTask = {};
  final Map<String, OperationProgress> _activeOperations = {};
  bool _queueUserPaused = false;
  int _dispatchHolds = 0;

  late final TransferJournal _journal;
  late final Future<void> ready;
  String? recoveryError;
  Future<void>? _backgroundRefresh;

  TransferNotifier(this._ref) {
    _journal = _ref.read(transferJournalProvider);
    _queue.addListener(_queueChanged);
    ready = _restore();
  }

  void _queueChanged() {
    _pendingTasks = _queue.pendingTasks;
    _firstPendingTask.clear();
    for (final task in _pendingTasks) {
      _firstPendingTask.putIfAbsent(task.operation.id, () => task);
    }
    _activeOperations.clear();
    for (final task in _queue.activeTasks) {
      _activeOperations[task.operation.id] = task.operation;
    }
    notifyListeners();
  }

  List<OperationProgress> get operations => List.unmodifiable(_operations);
  List<TransferJobRecord> get savedJobs => _journal.jobs;
  List<String> get recoveryWarnings => List.unmodifiable(_journal.warnings);
  TransferJobRecord? savedJob(String id) => _journal.job(id);
  bool get hasActiveOperations => _operations.any(
    (op) => op.isActive || op.isCancelled && isJobLive(op.id),
  );
  bool isJobLive(String id) =>
      _fileOperationControls.containsKey(id) ||
      _journal.isOperationActive(id) ||
      _firstPendingTask.containsKey(id) ||
      _activeOperations.containsKey(id);
  int get maxConcurrent => _queue.maxConcurrent;
  bool get queuePaused => _queueUserPaused;
  int get queuedCount => queuedIds.length;

  /// Queue controls operate on user-visible jobs, even when a legacy upload
  /// consists of several scheduler tasks sharing the same operation.
  List<String> get queuedIds {
    return [
      ..._firstPendingTask.keys.where(
        (id) => !_activeOperations.containsKey(id),
      ),
    ];
  }

  bool isQueued(String id) =>
      !_activeOperations.containsKey(id) && _firstPendingTask.containsKey(id);

  bool isRunning(String id) {
    final operation = _activeOperations[id];
    return operation != null && operation.isActive && !operation.isPaused;
  }

  int priorityOf(String id) =>
      _journal.job(id)?.priority ?? _firstPendingTask[id]?.priority ?? 0;

  String? queueBlockedReason(String id) {
    if (!isQueued(id)) return null;
    if (_dispatchHolds > 0 && !_queueUserPaused) {
      return 'Saving queue changes';
    }
    final task = _firstPendingTask[id];
    return task == null ? null : _queue.blockedReason(task.id);
  }

  TransferQueueSummary get queueSummary {
    final now = DateTime.now();
    final pending = <String, List<TransferTask>>{};
    for (final task in _pendingTasks) {
      pending.putIfAbsent(task.operation.id, () => []).add(task);
    }
    var running = 0;
    var queued = 0;
    var scheduled = 0;
    var paused = 0;
    var waiting = 0;
    var needsReview = 0;
    var completed = 0;
    var cancelling = 0;
    var cancelled = 0;
    var totalBytes = 0;
    var transferredBytes = 0;
    var bytesPerSecond = 0.0;
    var hasUnknownSize = false;
    for (final operation in _operations) {
      final saved = _journal.job(operation.id);
      final live = isJobLive(operation.id);
      if (operation.isCancelled ||
          !live && saved?.status == TransferJobStatus.cancelled) {
        if (live) {
          cancelling++;
        } else {
          cancelled++;
        }
        continue;
      }
      if (operation.isWaitingForDecision) {
        waiting++;
        continue;
      }
      if (operation.status == OperationStatus.completed) {
        completed++;
        continue;
      }
      if (operation.status == OperationStatus.failed) {
        needsReview++;
        continue;
      }
      if (operation.isPaused) {
        paused++;
      } else if (_activeOperations.containsKey(operation.id)) {
        running++;
        final speed = operation.currentSpeed;
        if (speed.isFinite && speed > 0) bytesPerSecond += speed;
      } else {
        final tasks = pending[operation.id] ?? const <TransferTask>[];
        if (tasks.isNotEmpty &&
            tasks.every((task) => task.notBefore?.isAfter(now) == true)) {
          scheduled++;
        } else {
          queued++;
        }
      }
      final total = operation.totalBytes < 0 ? 0 : operation.totalBytes;
      final current = operation.currentBytes < 0 ? 0 : operation.currentBytes;
      totalBytes += total;
      transferredBytes += total > 0 && current > total ? total : current;
      final unknown = _unknownFileSizes[operation.id];
      if (unknown != null) {
        hasUnknownSize = hasUnknownSize || unknown.isNotEmpty;
      } else if (saved != null) {
        hasUnknownSize =
            hasUnknownSize ||
            saved.entries.any(
              (entry) =>
                  !entry.source.isFolder &&
                  entry.source.size == null &&
                  entry.outcome != FileOperationOutcome.filtered &&
                  entry.outcome != FileOperationOutcome.skipped,
            );
      }
    }
    return TransferQueueSummary(
      running: running,
      queued: queued,
      scheduled: scheduled,
      paused: paused,
      waiting: waiting,
      needsReview: needsReview,
      completed: completed,
      cancelling: cancelling,
      cancelled: cancelled,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes,
      bytesPerSecond: bytesPerSecond,
      hasUnknownSize: hasUnknownSize,
    );
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final limit = prefs.getInt('commander_transfer_concurrency') ?? 3;
      _queueUserPaused =
          prefs.getBool('commander_transfer_queue_paused') ?? false;
      _applyDispatchState();
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
    await _withDispatchHeld(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setInt('commander_transfer_concurrency', limit)) {
        throw StateError('Could not save transfer concurrency.');
      }
      _queue.setMaxConcurrent(limit);
    });
  }

  /// Stop admitting new work without changing the user's parallelism setting
  /// or unpausing any job that was paused individually.
  Future<void> setQueuePaused(bool paused) async {
    await ready;
    await _withDispatchHeld(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool('commander_transfer_queue_paused', paused)) {
        throw StateError('Could not save the queue pause setting.');
      }
      _queueUserPaused = paused;
    });
  }

  void _applyDispatchState() {
    if (_disposed) return;
    if (_queueUserPaused || _dispatchHolds > 0) {
      _queue.pause();
    } else {
      _queue.resume();
    }
  }

  /// A job cannot start halfway through saving its schedule or queue policy.
  /// This hold affects dispatch only; active I/O retains its worker and claims.
  /// A counter and the separate user pause flag prevent one concurrent change
  /// from resuming dispatch while another change is still being saved.
  Future<T> _withDispatchHeld<T>(Future<T> Function() action) async {
    if (_disposed) throw StateError('The transfer queue is closed.');
    _dispatchHolds++;
    _applyDispatchState();
    try {
      return await _queueConfiguration.synchronized(() async {
        if (_disposed) throw StateError('The transfer queue is closed.');
        return action();
      });
    } finally {
      _dispatchHolds--;
      _applyDispatchState();
      notifyListeners();
    }
  }

  Future<void> setPriority(String id, int priority) async {
    await ready;
    await _withDispatchHeld(() async {
      if (!isQueued(id)) return;
      final job = _journal.job(id);
      if (job != null) {
        await _journal.updateQueue(id, priority: priority);
      }
      for (final task in _queue.pendingTasks.where(
        (task) => task.operation.id == id,
      )) {
        _queue.setPendingPriority(task.id, priority);
      }
      await _saveQueueOrder();
    });
  }

  Future<void> setScheduledStart(String id, DateTime? notBefore) async {
    await ready;
    await _withDispatchHeld(() async {
      if (!isQueued(id)) {
        throw StateError(
          'This job has already started or finished; its start time cannot be changed.',
        );
      }
      final job = _journal.job(id);
      if (job == null) {
        throw StateError('This transfer does not have a saved plan.');
      }
      final scheduledAt = notBefore?.toUtc();
      await _journal.updateQueue(
        id,
        scheduledAt: scheduledAt,
        clearScheduledAt: scheduledAt == null,
      );
      for (final task in _queue.pendingTasks.where(
        (task) => task.operation.id == id,
      )) {
        _queue.setPendingStart(task.id, scheduledAt);
      }
    });
  }

  Future<void> reorderPending(int oldIndex, int newIndex) async {
    await ready;
    await _withDispatchHeld(() async {
      final ids = queuedIds;
      if (oldIndex < 0 ||
          oldIndex >= ids.length ||
          newIndex < 0 ||
          newIndex > ids.length) {
        return;
      }
      final id = ids.removeAt(oldIndex);
      if (newIndex > oldIndex) newIndex--;
      ids.insert(newIndex, id);
      for (final id in ids.reversed) {
        _movePendingJobFirst(id);
      }
      await _saveQueueOrder();
    });
  }

  Future<void> moveQueuedFirst(String id) async {
    await ready;
    await _withDispatchHeld(() async {
      if (!isQueued(id)) return;
      _movePendingJobFirst(id);
      await _saveQueueOrder();
    });
  }

  Future<void> moveQueuedLast(String id) async {
    await ready;
    await _withDispatchHeld(() async {
      if (!isQueued(id)) return;
      for (final task in _queue.pendingTasks.where(
        (task) => task.operation.id == id,
      )) {
        _queue.movePendingToBottom(task.id);
      }
      await _saveQueueOrder();
    });
  }

  void _movePendingJobFirst(String id) {
    final tasks = _queue.pendingTasks
        .where((task) => task.operation.id == id)
        .toList();
    for (final task in tasks.reversed) {
      _queue.movePendingToTop(task.id);
    }
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
    await _journal.runExclusiveOperation(id, () => _journal.dismiss(id));
    _operations.removeWhere((operation) => operation.id == id);
    notifyListeners();
  }

  Future<void> clearSavedCompleted() async {
    await ready;
    for (final job in _journal.jobs.where((job) => job.isFinished)) {
      if (!isJobLive(job.id)) {
        await _journal.runExclusiveOperation(
          job.id,
          () => _journal.dismiss(job.id),
        );
      }
    }
    await _journal.compact();
    _operations.removeWhere(
      (operation) =>
          operation.status == OperationStatus.completed &&
          !isJobLive(operation.id),
    );
    notifyListeners();
  }

  /// Restores a reviewed backup only into a vacant original location. The
  /// rename intent is durable before the storage operation starts. Restoration
  /// holds dispatch and requires existing workers to settle, so its verification
  /// and publication cannot race a different queued transfer.
  Future<void> restoreSavedBackup(
    String id,
    int index,
    FileOperationBackend destination,
    FileOperationControl control,
  ) async {
    await ready;
    await _withDispatchHeld(() async {
      if (_queue.activeCount > 0) {
        throw StateError(
          'Wait for running transfers to finish before restoring a backup.',
        );
      }
      final job = _journal.job(id);
      if (job == null || isJobLive(id)) {
        throw StateError('Transfer is unavailable or active.');
      }
      await _journal.runExclusiveOperation(id, () async {
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
              entry.message =
                  'Previous destination restored from verified backup.';
            }
            await _journal.checkpoint(id, index, entry, phase);
          },
        );
      });
    });
    notifyListeners();
  }

  void clearCompletedOperations() {
    _operations.removeWhere(
      (op) => _canHideOperation(op.id) && (op.isComplete || op.isCancelled),
    );
    _queue.clearCompleted();
    notifyListeners();
  }

  /// Hide successful/cancelled rows while keeping failures and conflicts in
  /// view. Saved manifests remain available in history and recovery.
  void clearFinishedOperations() {
    _operations.removeWhere(
      (op) =>
          _canHideOperation(op.id) &&
          (op.status == OperationStatus.completed ||
              op.isCancelled ||
              _journal.job(op.id)?.status == TransferJobStatus.cancelled),
    );
    _queue.clearCompleted();
    notifyListeners();
  }

  bool _canHideOperation(String id) => !isJobLive(id);

  void cancelAllOperations() {
    for (final operation in _operations.where(
      (op) => op.isWaitingForDecision,
    )) {
      unawaited(_cancelWaitingJob(operation.id));
    }
    for (final control in [..._fileOperationControls.values]) {
      control.cancel();
    }
    _queue.cancelAll();
    for (final operation in _operations.where((op) => !op.isComplete)) {
      operation.cancel();
    }
    notifyListeners();
  }

  void removeOperation(String id) {
    if (!_canHideOperation(id)) return;
    _operations.removeWhere((op) => op.id == id);
    // The durable journal owns history. Scheduler closures can retain plans,
    // streams and account clients, so discard their settled cache as well.
    _queue.clearCompleted();
    notifyListeners();
  }

  Future<void> _saveLiveStatus(String id, TransferJobStatus status) async {
    if (_disposed || !_fileOperationControls.containsKey(id)) return;
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
    final control = _fileOperationControls[operationId];
    control?.pause();
    for (final operation in _operations.where((op) => op.id == operationId)) {
      operation.pause();
    }
    if (control == null) notifyListeners();
    _queue.refresh();
  }

  void resumeOperation(String operationId) {
    final control = _fileOperationControls[operationId];
    control?.resume();
    for (final operation in _operations.where((op) => op.id == operationId)) {
      operation.resume();
    }
    if (control == null) notifyListeners();
    _queue.refresh();
  }

  void pauseOperations(Iterable<String> ids) {
    for (final id in ids.toSet()) {
      pauseOperation(id);
    }
  }

  void resumeOperations(Iterable<String> ids) {
    for (final id in ids.toSet()) {
      resumeOperation(id);
    }
  }

  void cancelOperations(Iterable<String> ids) {
    for (final id in ids.toSet()) {
      cancelOperation(id);
    }
  }

  void _synchronizeControl(
    String id,
    FileOperationControl control,
    OperationProgress operation,
  ) {
    if (_disposed) return;
    if (control.isCancelled) {
      operation.cancel();
      _queue.cancel(id);
    } else {
      if (control.isPaused) {
        operation.pause();
      } else {
        operation.resume();
      }
      unawaited(
        _saveLiveStatus(
          id,
          control.isPaused
              ? TransferJobStatus.paused
              : isQueued(id)
              ? TransferJobStatus.queued
              : TransferJobStatus.running,
        ),
      );
      _queue.refresh();
    }
    notifyListeners();
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
    DateTime? notBefore,
  }) async {
    await ready;
    if (recoveryError != null) throw StateError(recoveryError!);
    if (!plan.canExecute && (recoveryJobId == null || plan.errors.isNotEmpty)) {
      throw StateError('Review a valid operation plan first.');
    }
    if (_disposed) throw StateError('The transfer queue is closed.');
    final id = recoveryJobId ?? 'commander_${const Uuid().v4()}';
    if (isJobLive(id)) throw StateError('This transfer is already queued.');
    // Admission is synchronous, before any plan/journal await. A second
    // recovery cannot replace the live owner's controls or durable entries.
    try {
      await _journal.runExclusiveOperation(
        id,
        () => _runAdmittedFileOperation(
          id,
          plan,
          control: control,
          resolveConflict: resolveConflict,
          resolveDetailedConflict: resolveDetailedConflict,
          onProgress: onProgress,
          onEntryComplete: onEntryComplete,
          onQueued: onQueued,
          recoveryJobId: recoveryJobId,
          priority: priority,
          notBefore: notBefore,
        ),
      );
    } finally {
      notifyListeners();
    }
  }

  Future<void> _runAdmittedFileOperation(
    String id,
    FileOperationPlan plan, {
    required FileOperationControl control,
    FileConflictResolver? resolveConflict,
    DetailedFileConflictResolver? resolveDetailedConflict,
    void Function(FileOperationEntry, int, int?)? onProgress,
    void Function(FileOperationEntry)? onEntryComplete,
    VoidCallback? onQueued,
    String? recoveryJobId,
    int priority = 0,
    DateTime? notBefore,
  }) async {
    TransferJobRecord job;
    if (recoveryJobId == null) {
      job = await _journal.create(
        id,
        plan,
        priority: priority,
        scheduledAt: notBefore?.toUtc(),
      );
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
      if (notBefore != null) {
        await _journal.updateQueue(id, scheduledAt: notBefore.toUtc());
      }
      await _journal.setStatus(id, TransferJobStatus.queued);
      priority = saved.priority;
    }
    if (_disposed) {
      await _journal.setStatus(
        id,
        TransferJobStatus.cancelled,
        message: 'Cancelled before queue admission. The saved plan can be reviewed later.',
      );
      throw StateError('The transfer queue is closed.');
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
    final excludedFromTotal = plan.entries
        .where(
          (entry) =>
              entry.outcome == FileOperationOutcome.skipped ||
              entry.outcome == FileOperationOutcome.filtered,
        )
        .toSet();
    final operation = OperationProgress(
      id: id,
      type: plan.options.kind == FileOperationKind.move
          ? OperationType.move
          : OperationType.copy,
      sourcePath: plan.source.label,
      targetPath: plan.targetDirectory,
      fileName: '${plan.fileCount} files',
      totalBytes: plan.entries
          .where(
            (entry) =>
                !entry.source.isFolder && !excludedFromTotal.contains(entry),
          )
          .fold(0, (sum, entry) => sum + (entry.source.size ?? 0)),
      files: rows.values.toList(),
    );
    final done = Completer<void>();
    final audit = _ref.read(auditServiceProvider);
    _operations.add(operation);
    _fileOperationControls[operation.id] = control;
    _unknownFileSizes[id] = plan.entries
        .where(
          (entry) =>
              !entry.source.isFolder &&
              entry.source.size == null &&
              !excludedFromTotal.contains(entry),
        )
        .toSet();
    _controlSubscriptions[id] = control.changes.listen(
      (_) => _synchronizeControl(id, control, operation),
    );
    if (control.isPaused) operation.pause();
    if (control.isCancelled) operation.cancel();
    notifyListeners();
    var completedBytes = rows.values
        .where((row) => row.isComplete)
        .fold(0, (sum, row) => sum + row.size);
    operation.currentBytes = completedBytes;
    final counted = plan.entries.where((entry) => entry.completed).toSet();
    final transferSizes = {
      for (final entry in plan.entries) entry: rows[entry]!.size,
    };
    final progressBytes = <FileOperationEntry, int>{};
    var started = false;
    try {
      _queue.enqueue(
        TransferTask(
          id: id,
          operation: operation,
          providerNames: transferProviderNames(plan),
          resourceClaims: transferResourceClaims(plan),
          notBefore: job.scheduledAt,
          maxRetries: 0,
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
                onPhase: (entry, phase) {
                  operation.currentFilePath = entry.source.path;
                  operation.phaseLabel = _transferPhaseLabel(phase);
                  notifyListeners();
                },
                onProgress: (entry, bytes, total) {
                  operation.currentFilePath = entry.source.path;
                  operation.phaseLabel = 'Copying';
                  progressBytes[entry] = bytes;
                  if (total != null) _unknownFileSizes[id]?.remove(entry);
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
                  if ((entry.outcome == FileOperationOutcome.skipped ||
                          entry.outcome == FileOperationOutcome.filtered) &&
                      excludedFromTotal.add(entry)) {
                    operation.totalBytes -= transferSizes[entry]!;
                    _unknownFileSizes[id]?.remove(entry);
                  }
                  final actual = progressBytes[entry];
                  if (entry.completed &&
                      actual != null &&
                      _unknownFileSizes[id]?.remove(entry) == true) {
                    operation.totalBytes += actual - transferSizes[entry]!;
                    transferSizes[entry] = actual;
                  }
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
              operation.currentFilePath = null;
              operation.phaseLabel = null;
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
              operation.currentFilePath = null;
              operation.phaseLabel = null;
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
              operation.currentFilePath = null;
              operation.phaseLabel = null;
              _unknownFileSizes.remove(id);
              await _controlSubscriptions.remove(id)?.cancel();
              _fileOperationControls.remove(id);
              notifyListeners();
              if (!done.isCompleted) done.complete();
            }
          },
        ),
      );
    } catch (error) {
      _unknownFileSizes.remove(id);
      await _controlSubscriptions.remove(id)?.cancel();
      _fileOperationControls.remove(id);
      operation.fail(error.toString());
      await _journal.setStatus(id, TransferJobStatus.failed, message: '$error');
      rethrow;
    }
    if (control.isPaused) {
      unawaited(_saveLiveStatus(id, TransferJobStatus.paused));
    }
    try {
      onQueued?.call();
    } catch (error) {
      // A dismissed UI observer cannot release job ownership while I/O runs.
      _log.warn('Transfer queue observer failed', error);
    }
    await done.future;
  }

  String _transferPhaseLabel(String phase) => switch (phase) {
    'creatingParent' || 'writing' => 'Preparing transfer',
    'staging' || 'uploading' => 'Copying',
    'allocating' => 'Reserving disk space',
    'backingUp' ||
    'backedUp' ||
    'renamingExisting' => 'Saving existing destination',
    'committing' => 'Publishing copy',
    'committed' ||
    'verified' ||
    'finishingCopy' ||
    'complete' => 'Finishing transfer',
    'metadata' || 'directoryMetadata' => 'Preserving metadata',
    'deletingSource' || 'deletingSourceDirectory' => 'Removing source',
    'needsDecision' => 'Waiting for a conflict decision',
    'cancelled' => 'Cancelling',
    'failed' || 'metadataFailed' => 'Needs review',
    _ => 'Running',
  };

  Future<void> uploadFiles(List<FileItem> files, {String? targetPath}) async {
    await ready;
    if (_disposed) throw StateError('The transfer queue is closed.');
    if (files.isEmpty) return;
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
    await ready;
    if (_disposed) throw StateError('The transfer queue is closed.');
    if (files.isEmpty) return;
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
    for (final control in [..._fileOperationControls.values]) {
      control.cancel();
    }
    for (final subscription in _controlSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _controlSubscriptions.clear();
    _queue.dispose();
    _pendingTasks = const [];
    _firstPendingTask.clear();
    _activeOperations.clear();
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

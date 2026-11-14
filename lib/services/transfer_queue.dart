import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:crisp_storage/crisp_storage.dart' as shared;

import '../models/operation_progress.dart';
import 'log_service.dart';

export 'package:crisp_storage/crisp_storage.dart' show TransferResourceClaim;

typedef TransferTask = shared.ScheduledTransfer<OperationProgress>;

class TransferQueue extends ChangeNotifier {
  static const _log = Log('TransferQueue');
  late final shared.TransferScheduler<OperationProgress> _queue;
  final shared.TransferBandwidthAllocator? _bandwidth;
  final Future<void> Function()? _bandwidthReady;
  final Set<shared.TransferBandwidthContext> _bandwidthContexts = {};
  final Set<void Function()> _bandwidthReadinessWaiters = {};
  bool _disposed = false;
  TransferQueue({
    int maxConcurrent = 3,
    int maxRetries = 3,
    Duration retryBaseDelay = const Duration(seconds: 2),
    DateTime Function()? now,
    void Function(String taskId, Object error, StackTrace stackTrace)?
    onCallbackError,
    shared.TransferBandwidthAllocator? bandwidth,
    this._bandwidthReady,
  }) : _bandwidth = bandwidth {
    _queue = shared.TransferScheduler(
      maxConcurrent: maxConcurrent,
      maxRetries: maxRetries,
      retryBaseDelay: retryBaseDelay,
      now: now,
      onCallbackError:
          onCallbackError ??
          (id, error, stackTrace) => _log.error(
            'Transfer finalization failed: $id',
            error,
            stackTrace,
          ),
      onChanged: notifyListeners,
      executeTask: bandwidth == null ? null : _executeWithBandwidth,
    );
  }

  Future<void> _executeWithBandwidth(TransferTask task) async {
    do {
      await _waitForBandwidthReadiness(task.operation);
    } while (task.operation.isPaused && !task.operation.isCancelled);
    if (_disposed || task.operation.isCancelled) {
      throw const shared.TransferCancelled();
    }
    final context = _bandwidth!.openContext(task.operation.id);
    _bandwidthContexts.add(context);
    void synchronize() {
      if (task.operation.isCancelled || _disposed) {
        context.cancel();
      } else {
        context.setPaused(task.operation.isPaused);
      }
    }

    task.operation.addControlListener(synchronize);
    try {
      synchronize();
      await context.run(task.execute);
    } on shared.TransferBandwidthCancelled {
      // Keep scheduler and journal cancellation classification unchanged.
      throw const shared.TransferCancelled();
    } finally {
      task.operation.removeControlListener(synchronize);
      _bandwidthContexts.remove(context);
      context.close();
    }
  }

  Future<void> _waitForBandwidthReadiness(OperationProgress operation) async {
    final done = Completer<void>();
    var loaded = false;
    void check() {
      if (done.isCompleted) return;
      if (_disposed || operation.isCancelled) {
        done.completeError(const shared.TransferCancelled());
      } else if (loaded && !operation.isPaused) {
        done.complete();
      }
    }

    operation.addControlListener(check);
    _bandwidthReadinessWaiters.add(check);
    try {
      final ready = _bandwidthReady?.call() ?? Future<void>.value();
      unawaited(
        ready.then<void>(
          (_) {
            loaded = true;
            check();
          },
          onError: (Object error, StackTrace stack) {
            if (!done.isCompleted) done.completeError(error, stack);
          },
        ),
      );
      check();
      await done.future;
    } finally {
      operation.removeControlListener(check);
      _bandwidthReadinessWaiters.remove(check);
    }
  }

  int get maxConcurrent => _queue.maxConcurrent;
  int get maxRetries => _queue.maxRetries;
  Duration get retryBaseDelay => _queue.retryBaseDelay;
  int get pendingCount => _queue.pendingCount;
  int get activeCount => _queue.activeCount;
  int get completedCount => _queue.completedCount;
  bool get hasActive => _queue.hasActive;
  bool get isPaused => _queue.isPaused;
  Map<String, Object> get callbackErrors => _queue.callbackErrors;
  List<TransferTask> get pendingTasks => _queue.pendingTasks;
  List<TransferTask> get activeTasks => _queue.activeTasks;
  void setProviderLimit(String provider, int limit) =>
      _queue.setProviderLimit(provider, limit);
  void setProviderRateLimit(String provider, {int minDelayMs = 100}) =>
      _queue.setProviderRateLimit(provider, minDelayMs: minDelayMs);
  void setMaxConcurrent(int limit) => _queue.setMaxConcurrent(limit);
  void pause() => _queue.pause();
  void resume() => _queue.resume();
  void refresh() => _queue.refresh();
  void setPendingPriority(String id, int priority) =>
      _queue.setPendingPriority(id, priority);
  void setPendingStart(String id, DateTime? notBefore) =>
      _queue.setPendingStart(id, notBefore);
  String? blockedReason(String id) => _queue.blockedReason(id);
  void cancel(String id) => _queue.cancel(id);
  void enqueue(TransferTask task) => _queue.enqueue(task);
  void reorderPending(int oldIndex, int newIndex) =>
      _queue.reorderPending(oldIndex, newIndex);
  void movePendingToTop(String id) => _queue.movePendingToTop(id);
  void movePendingToBottom(String id) => _queue.movePendingToBottom(id);
  void cancelAll() => _queue.cancelAll();
  void clearCompleted() => _queue.clearCompleted();
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final wake in _bandwidthReadinessWaiters.toList()) {
      wake();
    }
    for (final context in _bandwidthContexts.toList()) {
      context.cancel();
      context.close();
    }
    _bandwidthContexts.clear();
    _queue.dispose();
    super.dispose();
  }
}

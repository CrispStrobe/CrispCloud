import 'package:flutter/foundation.dart';
import 'package:crisp_storage/crisp_storage.dart' as shared;

import '../models/operation_progress.dart';
import 'log_service.dart';

export 'package:crisp_storage/crisp_storage.dart' show TransferResourceClaim;

typedef TransferTask = shared.ScheduledTransfer<OperationProgress>;

class TransferQueue extends ChangeNotifier {
  static const _log = Log('TransferQueue');
  late final shared.TransferScheduler<OperationProgress> _queue;
  bool _disposed = false;
  TransferQueue({
    int maxConcurrent = 3,
    int maxRetries = 3,
    Duration retryBaseDelay = const Duration(seconds: 2),
    DateTime Function()? now,
    void Function(String taskId, Object error, StackTrace stackTrace)?
    onCallbackError,
  }) {
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
    );
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
    _queue.dispose();
    super.dispose();
  }
}

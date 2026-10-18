import 'package:flutter/foundation.dart';
import 'package:crisp_storage/crisp_storage.dart' as shared;
import '../models/operation_progress.dart';

typedef TransferTask = shared.ScheduledTransfer<OperationProgress>;

class TransferQueue extends ChangeNotifier {
  late final shared.TransferScheduler<OperationProgress> _queue;
  TransferQueue(
      {int maxConcurrent = 3,
      int maxRetries = 3,
      Duration retryBaseDelay = const Duration(seconds: 2)}) {
    _queue = shared.TransferScheduler(
        maxConcurrent: maxConcurrent,
        maxRetries: maxRetries,
        retryBaseDelay: retryBaseDelay,
        onChanged: notifyListeners);
  }
  int get maxConcurrent => _queue.maxConcurrent;
  int get maxRetries => _queue.maxRetries;
  Duration get retryBaseDelay => _queue.retryBaseDelay;
  int get pendingCount => _queue.pendingCount;
  int get activeCount => _queue.activeCount;
  int get completedCount => _queue.completedCount;
  bool get hasActive => _queue.hasActive;
  List<TransferTask> get pendingTasks => _queue.pendingTasks;
  List<TransferTask> get activeTasks => _queue.activeTasks;
  void setProviderLimit(String provider, int limit) =>
      _queue.setProviderLimit(provider, limit);
  void setProviderRateLimit(String provider, {int minDelayMs = 100}) =>
      _queue.setProviderRateLimit(provider, minDelayMs: minDelayMs);
  void enqueue(TransferTask task) => _queue.enqueue(task);
  void reorderPending(int oldIndex, int newIndex) =>
      _queue.reorderPending(oldIndex, newIndex);
  void movePendingToTop(String id) => _queue.movePendingToTop(id);
  void movePendingToBottom(String id) => _queue.movePendingToBottom(id);
  void cancelAll() => _queue.cancelAll();
  void clearCompleted() => _queue.clearCompleted();
  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }
}

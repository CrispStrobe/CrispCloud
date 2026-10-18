// lib/services/transfer_queue.dart
//
// Manages concurrent file transfers with configurable parallelism,
// retry logic, and pause/resume/cancel support.

import 'dart:async';
import 'remote_client.dart';

abstract interface class TransferOperation {
  bool get isCancelled;
  bool get isPaused;
  Future<void> get cancellationFuture;
  Future<void>? get pauseFuture;
  void cancel();
}

class TransferCancelled implements Exception {
  const TransferCancelled();
  @override
  String toString() => 'Transfer cancelled';
}

/// A single transfer task that the queue can execute.
///
/// Multiple tasks may share the same [operation] (batch transfers).
/// The queue does NOT call operation.complete()/fail() — the caller
/// handles batch finalization via [onDone].
class ScheduledTransfer<T extends TransferOperation> {
  final String id;
  final T operation;
  final Future<void> Function() execute;
  final void Function(Object? error)? onDone;
  final int priority; // higher = runs first
  final String? providerName; // for per-provider rate limiting

  ScheduledTransfer({
    required this.id,
    required this.operation,
    required this.execute,
    this.onDone,
    this.priority = 0,
    this.providerName,
  });
}

/// Manages concurrent transfers with a configurable pool size.
class TransferScheduler<T extends TransferOperation> {
  final void Function()? onChanged;
  bool _disposed = false;
  void notifyListeners() {
    if (!_disposed) onChanged?.call();
  }

  final int maxConcurrent;
  final int maxRetries;
  final Duration retryBaseDelay;

  final List<ScheduledTransfer<T>> _pending = [];
  final Map<String, ScheduledTransfer<T>> _active = {};
  final List<ScheduledTransfer<T>> _completed = [];

  /// Per-provider rate limits: max concurrent transfers per provider.
  /// Defaults to maxConcurrent if not set.
  final Map<String, int> _providerLimits = {};

  /// Track last request time per provider for rate-limit delay.
  final Map<String, DateTime> _providerLastRequest = {};

  /// Minimum delay between requests per provider (milliseconds).
  final Map<String, int> _providerMinDelayMs = {};

  TransferScheduler({
    this.onChanged,
    this.maxConcurrent = 3,
    this.maxRetries = 3,
    this.retryBaseDelay = const Duration(seconds: 2),
  }) {
    if (maxConcurrent < 0 || maxRetries < 0 || retryBaseDelay.isNegative) {
      throw ArgumentError('Invalid transfer scheduler limits');
    }
  }

  /// Set max concurrent transfers for a specific provider.
  void setProviderLimit(String provider, int limit) {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    _providerLimits[provider] = limit;
  }

  /// Set minimum delay between requests for a provider (rate limiting).
  void setProviderRateLimit(String provider, {int minDelayMs = 100}) {
    if (minDelayMs < 0) throw ArgumentError.value(minDelayMs, 'minDelayMs');
    _providerMinDelayMs[provider] = minDelayMs;
  }

  int get pendingCount => _pending.length;
  int get activeCount => _active.length;
  int get completedCount => _completed.length;
  bool get hasActive => _active.isNotEmpty;

  /// Read-only view of pending tasks (for UI display).
  List<ScheduledTransfer<T>> get pendingTasks => List.unmodifiable(_pending);

  /// Read-only view of active tasks (for UI display).
  List<ScheduledTransfer<T>> get activeTasks =>
      List.unmodifiable(_active.values.toList());

  /// Enqueue a transfer task. Sorted by priority (higher first).
  /// Starts immediately if capacity available.
  void enqueue(ScheduledTransfer<T> task) {
    if (_disposed) throw StateError('Transfer scheduler is closed');
    if (_pending.any((t) => t.id == task.id) || _active.containsKey(task.id)) {
      throw StateError('Transfer already queued');
    }
    // Insert maintaining priority order (descending)
    int insertIdx = _pending.length;
    for (var i = 0; i < _pending.length; i++) {
      if (task.priority > _pending[i].priority) {
        insertIdx = i;
        break;
      }
    }
    _pending.insert(insertIdx, task);
    _processQueue();
  }

  /// Reorder a pending task from [oldIndex] to [newIndex].
  void reorderPending(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pending.length) return;
    if (newIndex < 0 || newIndex > _pending.length) return;
    final task = _pending.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    _pending.insert(newIndex, task);
    notifyListeners();
  }

  /// Move a pending task to the front of the queue.
  void movePendingToTop(String taskId) {
    final idx = _pending.indexWhere((t) => t.id == taskId);
    if (idx <= 0) return;
    final task = _pending.removeAt(idx);
    _pending.insert(0, task);
    notifyListeners();
  }

  /// Move a pending task to the end of the queue.
  void movePendingToBottom(String taskId) {
    final idx = _pending.indexWhere((t) => t.id == taskId);
    if (idx < 0 || idx == _pending.length - 1) return;
    final task = _pending.removeAt(idx);
    _pending.add(task);
    notifyListeners();
  }

  /// Cancel all pending and active transfers.
  void cancelAll() {
    for (final task in _pending) {
      task.operation.cancel();
      task.onDone?.call(const TransferCancelled());
    }
    _pending.clear();

    for (final task in _active.values) {
      task.operation.cancel();
    }
    notifyListeners();
  }

  void cancel(String taskId) {
    final index = _pending.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      final task = _pending.removeAt(index);
      task.operation.cancel();
      task.onDone?.call(const TransferCancelled());
      notifyListeners();
    } else {
      _active[taskId]?.operation.cancel();
    }
  }

  /// Remove completed/failed tasks from history.
  void clearCompleted() {
    _completed.clear();
    notifyListeners();
  }

  int _activeCountForProvider(String? provider) {
    if (provider == null) return 0;
    return _active.values.where((t) => t.providerName == provider).length;
  }

  void _processQueue() {
    if (_disposed) return;
    final skipped = <ScheduledTransfer<T>>[];

    while (_active.length < maxConcurrent && _pending.isNotEmpty) {
      final task = _pending.removeAt(0);

      // Check per-provider limit
      if (task.providerName != null) {
        final limit = _providerLimits[task.providerName] ?? maxConcurrent;
        if (_activeCountForProvider(task.providerName) >= limit) {
          skipped.add(task);
          continue;
        }
      }

      _active[task.id] = task;
      _runTask(task);
    }

    // Put back skipped tasks at the front
    for (var i = skipped.length - 1; i >= 0; i--) {
      _pending.insert(0, skipped[i]);
    }

    notifyListeners();
  }

  Future<void> _wait(Duration delay, T operation) async {
    final elapsed = Completer<void>();
    final timer = Timer(delay, elapsed.complete);
    try {
      await Future.any([elapsed.future, operation.cancellationFuture]);
    } finally {
      timer.cancel();
    }
    if (operation.isCancelled) throw const TransferCancelled();
  }

  Future<void> _runTask(ScheduledTransfer<T> task) async {
    Object? taskError;
    try {
      for (var attempt = 0;; attempt++) {
        if (task.operation.isCancelled) throw const TransferCancelled();
        if (task.operation.isPaused) await task.operation.pauseFuture;
        if (task.operation.isCancelled) throw const TransferCancelled();
        final provider = task.providerName;
        if (provider != null) {
          final minDelay = _providerMinDelayMs[provider] ?? 0;
          final now = DateTime.now();
          final last = _providerLastRequest[provider];
          final earliest = last?.add(Duration(milliseconds: minDelay));
          final slot =
              earliest != null && earliest.isAfter(now) ? earliest : now;
          // Reserve before awaiting so parallel tasks receive distinct slots.
          _providerLastRequest[provider] = slot;
          if (slot.isAfter(now)) {
            await _wait(slot.difference(now), task.operation);
          }
        }
        try {
          await task.execute();
          if (task.operation.isCancelled) throw const TransferCancelled();
          break;
        } catch (error) {
          if (task.operation.isCancelled) throw const TransferCancelled();
          if (!_isRetryable(error) || attempt >= maxRetries) rethrow;
          await _wait(retryBaseDelay * (1 << attempt), task.operation);
        }
      }
    } catch (error) {
      taskError = error;
    }
    _active.remove(task.id);
    _completed.add(task);
    try {
      task.onDone?.call(taskError);
    } finally {
      _processQueue();
    }
  }

  bool _isRetryable(Object error) {
    if (error is RemoteException) return error.retryable;
    final msg = error.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('429') ||
        msg.contains('503') ||
        msg.contains('socket') ||
        msg.contains('network');
  }

  void dispose() {
    _disposed = true;
    cancelAll();
  }
}

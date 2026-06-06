// lib/services/transfer_queue.dart
//
// Manages concurrent file transfers with configurable parallelism,
// retry logic, and pause/resume/cancel support.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/operation_progress.dart';
import 'log_service.dart';

/// A single transfer task that the queue can execute.
///
/// Multiple tasks may share the same [operation] (batch transfers).
/// The queue does NOT call operation.complete()/fail() — the caller
/// handles batch finalization via [onDone].
class TransferTask {
  final String id;
  final OperationProgress operation;
  final Future<void> Function() execute;
  final void Function(Object? error)? onDone;
  final int priority; // higher = runs first
  final String? providerName; // for per-provider rate limiting

  TransferTask({
    required this.id,
    required this.operation,
    required this.execute,
    this.onDone,
    this.priority = 0,
    this.providerName,
  });
}

/// Manages concurrent transfers with a configurable pool size.
class TransferQueue extends ChangeNotifier {
  static const _log = Log('TransferQueue');
  final int maxConcurrent;
  final int maxRetries;
  final Duration retryBaseDelay;

  final List<TransferTask> _pending = [];
  final Map<String, TransferTask> _active = {};
  final List<TransferTask> _completed = [];

  /// Per-provider rate limits: max concurrent transfers per provider.
  /// Defaults to maxConcurrent if not set.
  final Map<String, int> _providerLimits = {};

  /// Track last request time per provider for rate-limit delay.
  final Map<String, DateTime> _providerLastRequest = {};

  /// Minimum delay between requests per provider (milliseconds).
  final Map<String, int> _providerMinDelayMs = {};

  TransferQueue({
    this.maxConcurrent = 3,
    this.maxRetries = 3,
    this.retryBaseDelay = const Duration(seconds: 2),
  });

  /// Set max concurrent transfers for a specific provider.
  void setProviderLimit(String provider, int limit) {
    _providerLimits[provider] = limit;
  }

  /// Set minimum delay between requests for a provider (rate limiting).
  void setProviderRateLimit(String provider, {int minDelayMs = 100}) {
    _providerMinDelayMs[provider] = minDelayMs;
  }

  int get pendingCount => _pending.length;
  int get activeCount => _active.length;
  int get completedCount => _completed.length;
  bool get hasActive => _active.isNotEmpty;

  /// Read-only view of pending tasks (for UI display).
  List<TransferTask> get pendingTasks => List.unmodifiable(_pending);

  /// Read-only view of active tasks (for UI display).
  List<TransferTask> get activeTasks => List.unmodifiable(_active.values.toList());

  /// Enqueue a transfer task. Sorted by priority (higher first).
  /// Starts immediately if capacity available.
  void enqueue(TransferTask task) {
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
    }
    _pending.clear();

    for (final task in _active.values) {
      task.operation.cancel();
    }
    notifyListeners();
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
    final skipped = <TransferTask>[];

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

  Future<void> _runTask(TransferTask task, {int attempt = 0}) async {
    // Per-provider rate limiting: enforce minimum delay between requests
    if (task.providerName != null) {
      final minDelay = _providerMinDelayMs[task.providerName];
      if (minDelay != null && minDelay > 0) {
        final lastReq = _providerLastRequest[task.providerName!];
        if (lastReq != null) {
          final elapsed = DateTime.now().difference(lastReq).inMilliseconds;
          if (elapsed < minDelay) {
            await Future.delayed(Duration(milliseconds: minDelay - elapsed));
          }
        }
        _providerLastRequest[task.providerName!] = DateTime.now();
      }
    }

    Object? taskError;
    try {
      await task.execute();
    } catch (e) {
      if (task.operation.isCancelled) {
        taskError = e;
      } else if (_isRetryable(e) && attempt < maxRetries) {
        final delay = retryBaseDelay * (1 << attempt); // exponential backoff
        _log.info('Retry ${attempt + 1}/$maxRetries for ${task.id} in ${delay.inSeconds}s');
        await Future.delayed(delay);
        if (!task.operation.isCancelled) {
          await _runTask(task, attempt: attempt + 1);
          return;
        }
      } else {
        taskError = e;
      }
    }

    _active.remove(task.id);
    _completed.add(task);
    task.onDone?.call(taskError);
    _processQueue();
  }

  bool _isRetryable(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('429') ||
        msg.contains('503') ||
        msg.contains('socket') ||
        msg.contains('network');
  }

  @override
  void dispose() {
    cancelAll();
    super.dispose();
  }
}

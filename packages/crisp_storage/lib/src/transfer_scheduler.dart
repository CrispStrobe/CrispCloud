// Shared scheduling, admission control, and cancellation for file transfers.

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

/// A read or write reservation in one backend/account's path namespace.
///
/// Callers supply canonical segments (including any backend-specific case
/// folding). Segment boundaries matter: `['photos']` covers its descendants,
/// but does not cover `['photos-old']`. An empty path covers the namespace.
class TransferResourceClaim {
  final Object namespace;
  final List<String> pathSegments;
  final bool write;

  TransferResourceClaim({
    required this.namespace,
    required List<String> pathSegments,
    required this.write,
  }) : pathSegments = List.unmodifiable(pathSegments);

  bool conflictsWith(TransferResourceClaim other) {
    if (namespace != other.namespace || (!write && !other.write)) return false;
    final commonLength = pathSegments.length < other.pathSegments.length
        ? pathSegments.length
        : other.pathSegments.length;
    for (var index = 0; index < commonLength; index++) {
      if (pathSegments[index] != other.pathSegments[index]) return false;
    }
    return true;
  }
}

/// An immutable-after-construction index of a task's reservation footprint.
///
/// Namespace buckets and path tries avoid comparing every selected file with
/// every file in another task. Read-only subtrees never need comparison, and
/// disjoint branches are pruned at their first differing path segment.
class _TransferResourceIndex {
  final Map<Object, _TransferClaimNode> _namespaces = {};

  _TransferResourceIndex(List<TransferResourceClaim> claims) {
    for (final claim in claims) {
      _add(claim);
    }
  }

  void _add(TransferResourceClaim claim) {
    var node = _namespaces.putIfAbsent(claim.namespace, _TransferClaimNode.new);
    node.hasWrites = node.hasWrites || claim.write;
    for (final segment in claim.pathSegments) {
      if (node.write || !claim.write && node.read) return;
      node = node.children.putIfAbsent(segment, _TransferClaimNode.new);
      node.hasWrites = node.hasWrites || claim.write;
    }
    if (claim.write) {
      node.write = true;
      node.read = false;
      node.children.clear();
    } else if (!node.write) {
      node.read = true;
    }
  }

  bool conflictsWith(_TransferResourceIndex other) {
    for (final namespace in _namespaces.entries) {
      final matching = other._namespaces[namespace.key];
      if (matching == null) continue;
      final pending = <(_TransferClaimNode, _TransferClaimNode)>[
        (namespace.value, matching),
      ];
      while (pending.isNotEmpty) {
        final (left, right) = pending.removeLast();
        if (!left.hasWrites && !right.hasWrites) continue;
        // Every node contains at least one claim at or below its path. A
        // terminal write conflicts with either kind of claim below the peer;
        // a terminal read conflicts only with writes below the peer.
        if (left.write ||
            right.write ||
            left.read && right.hasWrites ||
            right.read && left.hasWrites) {
          return true;
        }
        final smaller = left.children.length <= right.children.length
            ? left.children
            : right.children;
        final larger = identical(smaller, left.children)
            ? right.children
            : left.children;
        for (final child in smaller.entries) {
          final peer = larger[child.key];
          if (peer != null && (child.value.hasWrites || peer.hasWrites)) {
            pending.add((child.value, peer));
          }
        }
      }
    }
    return false;
  }
}

class _TransferClaimNode {
  final Map<String, _TransferClaimNode> children = {};
  bool read = false;
  bool write = false;
  bool hasWrites = false;
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
  final FutureOr<void> Function(Object? error)? onDone;
  final int priority; // higher = runs first
  final String? providerName; // compatibility with single-provider callers
  final Set<String> providerNames;
  final List<TransferResourceClaim> resourceClaims;
  final DateTime? notBefore;
  final _TransferResourceIndex _resourceIndex;

  /// Number of retries after the initial attempt. Zero disables replay.
  final int? maxRetries;

  ScheduledTransfer({
    required this.id,
    required this.operation,
    required this.execute,
    this.onDone,
    this.priority = 0,
    this.providerName,
    Set<String> providerNames = const {},
    List<TransferResourceClaim> resourceClaims = const [],
    this.notBefore,
    this.maxRetries,
  }) : providerNames = Set.unmodifiable({
         ...providerNames,
         if (providerName != null) providerName,
       }),
       resourceClaims = List.unmodifiable(resourceClaims),
       _resourceIndex = _TransferResourceIndex(resourceClaims) {
    if (maxRetries != null && maxRetries! < 0) {
      throw ArgumentError.value(maxRetries, 'maxRetries');
    }
  }

  // Policy changes share the already-built immutable footprint instead of
  // rebuilding an index for a potentially large selection of individual files.
  ScheduledTransfer._withPolicy(
    ScheduledTransfer<T> task, {
    required this.priority,
    required this.notBefore,
  }) : id = task.id,
       operation = task.operation,
       execute = task.execute,
       onDone = task.onDone,
       providerName = task.providerName,
       providerNames = task.providerNames,
       resourceClaims = task.resourceClaims,
       maxRetries = task.maxRetries,
       _resourceIndex = task._resourceIndex;
}

/// Manages concurrent transfers with a configurable pool size.
class TransferScheduler<T extends TransferOperation> {
  final void Function()? onChanged;
  final void Function(String taskId, Object error, StackTrace stackTrace)?
  onCallbackError;
  bool _disposed = false;
  bool _paused = false;
  bool _processing = false;
  bool _notifying = false;
  final DateTime Function() _now;
  final Completer<void> _closed = Completer<void>();
  Timer? _wakeTimer;
  DateTime? _wakeAt;

  void notifyListeners() {
    if (_disposed || _notifying) return;
    _notifying = true;
    try {
      onChanged?.call();
    } finally {
      _notifying = false;
    }
  }

  int _maxConcurrent;
  int get maxConcurrent => _maxConcurrent;
  final int maxRetries;
  final Duration retryBaseDelay;

  final List<ScheduledTransfer<T>> _pending = [];
  final Map<String, ScheduledTransfer<T>> _active = {};
  final List<ScheduledTransfer<T>> _completed = [];
  final Map<ScheduledTransfer<T>, Future<void>> _pendingPauseSignals = {};
  final Map<String, ScheduledTransfer<T>> _settlingPending = {};
  final Set<ScheduledTransfer<T>> _finishing = {};
  final Map<String, Object> _callbackErrors = {};

  /// Per-provider rate limits: max concurrent transfers per provider.
  /// Defaults to maxConcurrent if not set.
  final Map<String, int> _providerLimits = {};

  /// Track last request time per provider for rate-limit delay.
  final Map<String, DateTime> _providerLastRequest = {};

  /// Minimum delay between requests per provider (milliseconds).
  final Map<String, int> _providerMinDelayMs = {};

  TransferScheduler({
    this.onChanged,
    this.onCallbackError,
    int maxConcurrent = 3,
    this.maxRetries = 3,
    this.retryBaseDelay = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _maxConcurrent = maxConcurrent,
       _now = now ?? DateTime.now {
    if (maxConcurrent < 0 || maxRetries < 0 || retryBaseDelay.isNegative) {
      throw ArgumentError('Invalid transfer scheduler limits');
    }
  }

  bool get isPaused => _paused;

  /// Stop admitting work without changing limits or interrupting active work.
  void pause() {
    if (_disposed || _paused) return;
    _paused = true;
    _processQueue();
  }

  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _processQueue();
  }

  /// Zero stops starting queued work; lowering a limit leaves active work
  /// intact. Increasing it immediately fills the newly available slots.
  void setMaxConcurrent(int limit) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    _maxConcurrent = limit;
    _processQueue();
  }

  /// Resume scheduling after an operation's pause state changes.
  void refresh() => _processQueue();

  void setPendingPriority(String taskId, int priority) {
    final index = _pending.indexWhere((task) => task.id == taskId);
    if (index < 0) return;
    final task = _pending.removeAt(index);
    _pendingPauseSignals.remove(task);
    final replacement = _copyTask(
      task,
      priority: priority,
      notBefore: task.notBefore,
    );
    _insertPending(replacement);
    _watchPendingCancellation(replacement);
    _processQueue();
  }

  /// Change only a queued task's start time, preserving its manual order.
  void setPendingStart(String taskId, DateTime? notBefore) {
    final index = _pending.indexWhere((task) => task.id == taskId);
    if (index < 0) return;
    final task = _pending[index];
    _pendingPauseSignals.remove(task);
    final replacement = _copyTask(
      task,
      priority: task.priority,
      notBefore: notBefore,
    );
    _pending[index] = replacement;
    _watchPendingCancellation(replacement);
    _processQueue();
  }

  ScheduledTransfer<T> _copyTask(
    ScheduledTransfer<T> task, {
    required int priority,
    required DateTime? notBefore,
  }) => ScheduledTransfer<T>._withPolicy(
    task,
    priority: priority,
    notBefore: notBefore,
  );

  /// The current admission blocker for a queued task, or null if ready/absent.
  String? blockedReason(String taskId) {
    for (final task in _pending) {
      if (task.id == taskId) return _blockedReason(task, _now());
    }
    return null;
  }

  /// Set max concurrent transfers for a specific provider.
  void setProviderLimit(String provider, int limit) {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    _providerLimits[provider] = limit;
    _processQueue();
  }

  /// Set minimum delay between requests for a provider (rate limiting).
  void setProviderRateLimit(String provider, {int minDelayMs = 100}) {
    if (minDelayMs < 0) throw ArgumentError.value(minDelayMs, 'minDelayMs');
    _providerMinDelayMs[provider] = minDelayMs;
    _processQueue();
  }

  int get pendingCount => _pending.length;
  int get activeCount => _active.length;
  int get completedCount => _completed.length;
  bool get hasActive => _active.isNotEmpty;

  /// Completion failures are retained separately from execution failures.
  /// They never cause an already-executed transfer to be retried.
  Map<String, Object> get callbackErrors => Map.unmodifiable(_callbackErrors);

  /// Read-only view of pending tasks (for UI display).
  List<ScheduledTransfer<T>> get pendingTasks => List.unmodifiable(_pending);

  /// Read-only view of active tasks (for UI display).
  List<ScheduledTransfer<T>> get activeTasks =>
      List.unmodifiable(_active.values.toList());

  /// Enqueue a transfer task. Sorted by priority (higher first).
  /// Starts immediately if capacity available.
  void enqueue(ScheduledTransfer<T> task) {
    if (_disposed) throw StateError('Transfer scheduler is closed');
    if (_pending.any((t) => t.id == task.id) ||
        _active.containsKey(task.id) ||
        _settlingPending.containsKey(task.id)) {
      throw StateError('Transfer already queued');
    }
    _callbackErrors.remove(task.id);
    _insertPending(task);
    _watchPendingCancellation(task);
    _processQueue();
  }

  void _insertPending(ScheduledTransfer<T> task) {
    // Insert maintaining priority order (descending)
    int insertIdx = _pending.length;
    for (var i = 0; i < _pending.length; i++) {
      if (task.priority > _pending[i].priority) {
        insertIdx = i;
        break;
      }
    }
    _pending.insert(insertIdx, task);
  }

  void _watchPendingCancellation(ScheduledTransfer<T> task) {
    // Operations can be cancelled directly by their owner (including a batch
    // operation shared by several tasks), even while the queue has no slots.
    unawaited(
      task.operation.cancellationFuture.then((_) {
        if (_disposed) return;
        if (!_pending.remove(task)) return;
        _pendingPauseSignals.remove(task);
        _settlingPending[task.id] = task;
        unawaited(_finishTask(task, const TransferCancelled()));
        _processQueue();
      }),
    );
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
    final pending = List<ScheduledTransfer<T>>.of(_pending);
    final active = List<ScheduledTransfer<T>>.of(_active.values);
    // Detach all pending tasks before calling owner code, which may re-enter.
    _pending.clear();
    _pendingPauseSignals.clear();
    for (final task in pending) {
      _settlingPending[task.id] = task;
    }
    for (final task in pending) {
      task.operation.cancel();
      unawaited(_finishTask(task, const TransferCancelled()));
    }
    for (final task in active) {
      if (!_finishing.contains(task)) task.operation.cancel();
    }
    _processQueue();
  }

  void cancel(String taskId) {
    final index = _pending.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      final task = _pending.removeAt(index);
      _pendingPauseSignals.remove(task);
      _settlingPending[task.id] = task;
      task.operation.cancel();
      unawaited(_finishTask(task, const TransferCancelled()));
      _processQueue();
    } else {
      final task = _active[taskId];
      if (task != null && !_finishing.contains(task)) task.operation.cancel();
    }
  }

  /// Remove completed/failed tasks from history.
  void clearCompleted() {
    _completed.clear();
    _callbackErrors.clear();
    notifyListeners();
  }

  int _activeCountForProvider(String provider) =>
      _active.values.where((t) => t.providerNames.contains(provider)).length;

  void _watchPendingPause(ScheduledTransfer<T> task) {
    final signal = task.operation.pauseFuture;
    if (signal == null || identical(_pendingPauseSignals[task], signal)) return;
    _pendingPauseSignals[task] = signal;
    unawaited(
      signal.then((_) {
        if (!identical(_pendingPauseSignals[task], signal)) return;
        _pendingPauseSignals.remove(task);
        if (_pending.contains(task)) _processQueue();
      }),
    );
  }

  void _processQueue() {
    if (_disposed || _processing) return;
    _processing = true;
    try {
      for (final task in List<ScheduledTransfer<T>>.of(_pending)) {
        if (!task.operation.isCancelled || !_pending.remove(task)) continue;
        _pendingPauseSignals.remove(task);
        _settlingPending[task.id] = task;
        unawaited(_finishTask(task, const TransferCancelled()));
      }
      while (!_disposed && !_paused && _active.length < maxConcurrent) {
        ScheduledTransfer<T>? next;
        final now = _now();
        for (final task in _pending) {
          if (task.operation.isPaused) _watchPendingPause(task);
          if (_blockedReason(task, now) == null) {
            next = task;
            break;
          }
        }
        if (next == null) break;
        _pending.remove(next);
        _pendingPauseSignals.remove(next);
        _active[next.id] = next;
        unawaited(_runTask(next));
      }
    } finally {
      _processing = false;
      _scheduleNextWake();
      notifyListeners();
    }
  }

  String? _blockedReason(ScheduledTransfer<T> task, DateTime now) {
    if (task.operation.isCancelled) return 'Cancelled';
    if (_paused) return 'Queue paused';
    if (task.operation.isPaused) return 'Job paused';
    if (task.notBefore?.isAfter(now) ?? false) return 'Scheduled start';
    if (maxConcurrent == 0) return 'Waiting for transfer slot';
    for (final provider in task.providerNames) {
      if (_providerReadyAt(provider, now).isAfter(now)) {
        return 'Waiting for provider rate limit';
      }
      if (_activeCountForProvider(provider) >=
          (_providerLimits[provider] ?? maxConcurrent)) {
        return 'Waiting for provider capacity';
      }
    }
    for (final active in _active.values) {
      if (task._resourceIndex.conflictsWith(active._resourceIndex)) {
        return 'Path busy';
      }
    }
    if (_active.length >= maxConcurrent) return 'Waiting for transfer slot';
    return null;
  }

  DateTime _providerReadyAt(String provider, DateTime now) {
    final last = _providerLastRequest[provider];
    if (last == null) return now;
    final earliest = last.add(
      Duration(milliseconds: _providerMinDelayMs[provider] ?? 0),
    );
    return earliest.isAfter(now) ? earliest : now;
  }

  DateTime _readyAt(ScheduledTransfer<T> task, DateTime now) {
    var earliest = task.notBefore?.isAfter(now) ?? false
        ? task.notBefore!
        : now;
    for (final provider in task.providerNames) {
      final providerReady = _providerReadyAt(provider, now);
      if (providerReady.isAfter(earliest)) earliest = providerReady;
    }
    return earliest;
  }

  /// Exactly one wake timer covers scheduled starts and provider pacing.
  void _scheduleNextWake() {
    DateTime? earliest;
    final now = _now();
    if (!_disposed && !_paused && maxConcurrent > 0) {
      for (final task in _pending) {
        if (task.operation.isCancelled || task.operation.isPaused) continue;
        final ready = _readyAt(task, now);
        if (ready.isAfter(now) &&
            (earliest == null || ready.isBefore(earliest))) {
          earliest = ready;
        }
      }
    }
    if (earliest != null &&
        _wakeTimer?.isActive == true &&
        _wakeAt?.isAtSameMomentAs(earliest) == true) {
      return;
    }
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _wakeAt = earliest;
    if (earliest != null) {
      _wakeTimer = Timer(earliest.difference(now), () {
        _wakeTimer = null;
        _wakeAt = null;
        _processQueue();
      });
    }
  }

  Future<void> _wait(Duration delay, T operation) async {
    final elapsed = Completer<void>();
    final timer = Timer(delay, elapsed.complete);
    try {
      await Future.any([
        elapsed.future,
        operation.cancellationFuture,
        _closed.future,
      ]);
    } finally {
      timer.cancel();
    }
    if (_disposed || operation.isCancelled) throw const TransferCancelled();
  }

  Future<void> _runTask(ScheduledTransfer<T> task) async {
    Object? taskError;
    try {
      for (var attempt = 0; ; attempt++) {
        if (_disposed || task.operation.isCancelled) {
          throw const TransferCancelled();
        }
        while (task.operation.isPaused && !task.operation.isCancelled) {
          final resumed = task.operation.pauseFuture;
          if (resumed == null) break;
          await Future.any([
            resumed,
            task.operation.cancellationFuture,
            _closed.future,
          ]);
          if (_disposed) throw const TransferCancelled();
        }
        if (_disposed || task.operation.isCancelled) {
          throw const TransferCancelled();
        }
        final now = _now();
        var slot = now;
        for (final provider in task.providerNames) {
          final ready = _providerReadyAt(provider, now);
          if (ready.isAfter(slot)) slot = ready;
        }
        // Reserve every endpoint together before awaiting a retry's rate slot.
        for (final provider in task.providerNames) {
          _providerLastRequest[provider] = slot;
        }
        if (slot.isAfter(now)) {
          await _wait(slot.difference(now), task.operation);
        }
        try {
          await task.execute();
          if (_disposed || task.operation.isCancelled) {
            throw const TransferCancelled();
          }
          break;
        } catch (error) {
          if (_disposed || task.operation.isCancelled) {
            throw const TransferCancelled();
          }
          if (!_isRetryable(error) ||
              attempt >= (task.maxRetries ?? maxRetries)) {
            rethrow;
          }
          await _wait(retryBaseDelay * (1 << attempt), task.operation);
        }
      }
    } catch (error) {
      taskError = error;
    }
    await _finishTask(task, taskError);
  }

  Future<void> _finishTask(ScheduledTransfer<T> task, Object? error) async {
    if (!identical(_active[task.id], task) &&
        !identical(_settlingPending[task.id], task)) {
      return;
    }
    if (!_finishing.add(task)) return;
    try {
      // Journal commits and other asynchronous finalization still own the
      // active slot, provider capacity, and path reservations.
      final completion = task.onDone?.call(error);
      if (completion is Future<void>) await completion;
    } catch (callbackError, stackTrace) {
      _callbackErrors[task.id] = callbackError;
      try {
        onCallbackError?.call(task.id, callbackError, stackTrace);
      } catch (_) {
        // A diagnostic observer must not prevent release of reservations.
        // The original completion failure remains available in callbackErrors.
      }
    } finally {
      if (identical(_active[task.id], task)) _active.remove(task.id);
      if (identical(_settlingPending[task.id], task)) {
        _settlingPending.remove(task.id);
      }
      _finishing.remove(task);
      _completed.add(task);
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
    if (_disposed) return;
    _disposed = true;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _wakeAt = null;
    _closed.complete();
    cancelAll();
  }
}

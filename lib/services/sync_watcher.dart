// lib/services/sync_watcher.dart
//
// Watches local filesystem directories for changes and triggers
// sync when modifications are detected. Uses package:watcher on
// desktop; falls back to periodic polling on web/mobile.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:watcher/watcher.dart';

import 'sync_database.dart';

/// Callback when a watched directory has changes.
typedef SyncWatchCallback = Future<void> Function(int pairId);

/// Manages filesystem watchers for all enabled sync pairs.
/// On desktop, uses native directory watching (inotify/FSEvents/ReadDirectoryChanges).
/// Debounces rapid changes to avoid syncing on every keystroke in an editor.
class SyncWatcherService {
  final Map<int, DirectoryWatcher> _watchers = {};
  final Map<int, StreamSubscription> _subscriptions = {};
  final Map<int, Timer?> _debounceTimers = {};

  /// How long to wait after the last change before triggering sync.
  final Duration debounceDelay;

  SyncWatcherService({this.debounceDelay = const Duration(seconds: 5)});

  /// Start watching a sync pair's local directory.
  void watchPair(SyncPair pair, SyncWatchCallback onChanged) {
    if (kIsWeb) return; // No filesystem watching on web
    if (_watchers.containsKey(pair.id)) return; // Already watching

    try {
      final watcher = DirectoryWatcher(pair.localPath);
      _watchers[pair.id] = watcher;

      _subscriptions[pair.id] = watcher.events.listen((event) {
        debugPrint('SyncWatcher: ${event.type} ${event.path} (pair ${pair.id})');

        // Debounce: reset timer on each event
        _debounceTimers[pair.id]?.cancel();
        _debounceTimers[pair.id] = Timer(debounceDelay, () {
          debugPrint('SyncWatcher: triggering sync for pair ${pair.id}');
          onChanged(pair.id);
        });
      });

      debugPrint('SyncWatcher: watching ${pair.localPath} for pair ${pair.id}');
    } catch (e) {
      debugPrint('SyncWatcher: failed to watch ${pair.localPath}: $e');
    }
  }

  /// Stop watching a specific pair.
  void unwatchPair(int pairId) {
    _debounceTimers[pairId]?.cancel();
    _debounceTimers.remove(pairId);
    _subscriptions[pairId]?.cancel();
    _subscriptions.remove(pairId);
    _watchers.remove(pairId);
    debugPrint('SyncWatcher: stopped watching pair $pairId');
  }

  /// Stop watching all pairs.
  void unwatchAll() {
    for (final id in _watchers.keys.toList()) {
      unwatchPair(id);
    }
  }

  /// Check if a pair is being watched.
  bool isWatching(int pairId) => _watchers.containsKey(pairId);

  /// IDs of all currently watched pairs.
  Set<int> get watchedPairIds => _watchers.keys.toSet();

  /// Number of active watchers.
  int get watcherCount => _watchers.length;

  void dispose() {
    unwatchAll();
  }
}

/// Fallback polling watcher for platforms without native filesystem events.
/// Periodically triggers a sync callback for all registered pairs.
class PollingWatcherService {
  Timer? _timer;
  final Duration interval;
  final List<int> _pairIds = [];
  SyncWatchCallback? _callback;

  PollingWatcherService({this.interval = const Duration(minutes: 5)});

  void start(List<int> pairIds, SyncWatchCallback callback) {
    _pairIds
      ..clear()
      ..addAll(pairIds);
    _callback = callback;

    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      for (final id in _pairIds) {
        _callback?.call(id);
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _pairIds.clear();
  }

  void dispose() {
    stop();
  }
}

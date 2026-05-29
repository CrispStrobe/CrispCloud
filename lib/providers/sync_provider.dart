// lib/providers/sync_provider.dart
//
// Riverpod provider for the sync engine. Manages sync pairs,
// triggers sync runs, and exposes sync status to the UI.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_storage_interface.dart';
import '../services/sync_database.dart';
import '../services/sync_engine.dart';
import '../services/sync_watcher.dart';
import '../services/tray_service.dart';
import 'auth_provider.dart';
import 'error_provider.dart';

class SyncNotifier extends ChangeNotifier {
  final Ref _ref;
  late final SyncDatabase _db;
  late final SyncEngine _engine;
  late final SyncWatcherService _watcher;
  final TrayService _tray = TrayService();
  bool _watchEnabled = false;
  bool _trayInitialized = false;

  List<SyncPair> _pairs = [];
  bool _isSyncing = false;
  SyncResult? _lastResult;
  String? _currentPairName;

  SyncNotifier(this._ref) {
    _db = SyncDatabase();
    _engine = SyncEngine(_db);
    _watcher = SyncWatcherService();
    _loadPairs();
  }

  // --- Getters ---
  List<SyncPair> get pairs => _pairs;
  bool get isSyncing => _isSyncing;
  SyncResult? get lastResult => _lastResult;
  String? get currentPairName => _currentPairName;
  SyncDatabase get database => _db;
  bool get isWatchEnabled => _watchEnabled;
  int get watcherCount => _watcher.watcherCount;
  bool get isTrayActive => _trayInitialized;

  /// Initialize system tray (call once from app startup on desktop).
  Future<void> initTray({
    required VoidCallback onShowApp,
    required VoidCallback onQuit,
  }) async {
    if (!TrayService.isSupported || _trayInitialized) return;
    await _tray.initialize(
      onSyncAll: () => syncAll(),
      onShowApp: onShowApp,
      onQuit: onQuit,
    );
    _trayInitialized = true;
    _updateTray();
  }

  void _updateTray() {
    if (!_trayInitialized) return;
    _tray.updateStatus(
      isSyncing: _isSyncing,
      currentPairName: _currentPairName,
      lastResult: _lastResult,
      pairCount: _pairs.where((p) => p.enabled).length,
    );
  }

  // --- Pair management ---

  Future<void> _loadPairs() async {
    _pairs = await _db.getAllPairs();
    // Auto-start watchers for enabled pairs if watching is on
    if (_watchEnabled) {
      for (final pair in _pairs) {
        if (pair.enabled && !_watcher.isWatching(pair.id)) {
          _watcher.watchPair(pair, (pairId) => syncOne(pairId));
        }
      }
      // Stop watching disabled/removed pairs
      for (final id in _watcher.watchedPairIds.toList()) {
        if (!_pairs.any((p) => p.id == id && p.enabled)) {
          _watcher.unwatchPair(id);
        }
      }
    }
    notifyListeners();
  }

  Future<void> addPair({
    required String name,
    required String localPath,
    required String remotePath,
    required String provider,
    ConflictPolicy conflictPolicy = ConflictPolicy.newestWins,
    SyncDirection direction = SyncDirection.twoWay,
  }) async {
    await _db.insertPair(SyncPairsCompanion.insert(
      name: name,
      localPath: localPath,
      remotePath: remotePath,
      provider: provider,
      conflictPolicy: Value(conflictPolicy.name),
      direction: Value(direction.name),
    ));
    await _loadPairs();
  }

  Future<void> removePair(int id) async {
    await _db.deleteEntriesForPair(id);
    await _db.deletePair(id);
    await _loadPairs();
  }

  Future<void> togglePair(int id, bool enabled) async {
    await (_db.update(_db.syncPairs)..where((t) => t.id.equals(id)))
        .write(SyncPairsCompanion(enabled: Value(enabled)));
    await _loadPairs();
  }

  // --- Sync execution ---

  /// Sync all enabled pairs.
  Future<SyncResult> syncAll() async {
    if (_isSyncing) return const SyncResult();

    _isSyncing = true;
    notifyListeners();
    _updateTray();

    var totalResult = const SyncResult();

    try {
      final auth = _ref.read(authProvider);
      final client = auth.client;
      final enabledPairs = await _db.getEnabledPairs();

      for (final pair in enabledPairs) {
        if (pair.provider != auth.currentProvider.name) continue;
        _currentPairName = pair.name;
        notifyListeners();
        _updateTray();

        try {
          final result = await _engine.syncPair(pair, client);
          totalResult = totalResult + result;
        } catch (e) {
          debugPrint('SyncProvider: error syncing "${pair.name}": $e');
          _ref.read(errorProvider).addError('Sync failed for "${pair.name}": $e');
          totalResult = totalResult + SyncResult(errors: 1, errorMessages: ['${pair.name}: $e']);
        }
      }
    } finally {
      _isSyncing = false;
      _currentPairName = null;
      _lastResult = totalResult;
      notifyListeners();
      _updateTray();
      await _loadPairs();
    }

    return totalResult;
  }

  /// Sync a single pair by ID.
  Future<SyncResult> syncOne(int pairId) async {
    if (_isSyncing) return const SyncResult();

    _isSyncing = true;
    notifyListeners();

    try {
      final pair = await _db.getPair(pairId);
      final auth = _ref.read(authProvider);
      _currentPairName = pair.name;
      notifyListeners();

      final result = await _engine.syncPair(pair, auth.client);
      _lastResult = result;
      return result;
    } catch (e) {
      _ref.read(errorProvider).addError('Sync failed: $e');
      return SyncResult(errors: 1, errorMessages: [e.toString()]);
    } finally {
      _isSyncing = false;
      _currentPairName = null;
      notifyListeners();
      await _loadPairs();
    }
  }

  // --- Filesystem watching ---

  /// Enable real-time watching on all enabled pairs' local directories.
  void enableWatch() {
    _watchEnabled = true;
    for (final pair in _pairs) {
      if (pair.enabled && !_watcher.isWatching(pair.id)) {
        _watcher.watchPair(pair, (pairId) => syncOne(pairId));
      }
    }
    notifyListeners();
  }

  /// Disable all filesystem watchers.
  void disableWatch() {
    _watchEnabled = false;
    _watcher.unwatchAll();
    notifyListeners();
  }

  /// Get conflicts for a pair.
  Future<List<SyncEntry>> getConflicts(int pairId) => _db.getConflicts(pairId);

  /// Resolve a conflict by choosing a side.
  Future<void> resolveConflict(int pairId, String relativePath, SyncActionType resolution) async {
    final status = resolution == SyncActionType.upload ? 'pendingUpload' : 'pendingDownload';
    await _db.upsertEntry(SyncEntriesCompanion.insert(
      pairId: pairId,
      relativePath: relativePath,
      status: Value(status),
      error: const Value(null),
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    _watcher.dispose();
    _tray.dispose();
    _db.close();
    super.dispose();
  }
}

final syncProvider = ChangeNotifierProvider<SyncNotifier>((ref) {
  return SyncNotifier(ref);
});

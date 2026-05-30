// lib/providers/sync_provider.dart
//
// Riverpod provider for the sync engine. Manages sync pairs,
// triggers sync runs, and exposes sync status to the UI.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_storage_interface.dart';
import '../services/placeholder_service.dart';
import '../services/sync_database.dart';
import '../services/sync_engine.dart';
import '../services/sync_watcher.dart';
import '../services/tray_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'error_provider.dart';

class SyncNotifier extends ChangeNotifier {
  static final _log = Log('SyncNotifier');
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
    String includePatterns = '',
    String excludePatterns = '',
    bool usePlaceholders = false,
  }) async {
    await _db.insertPair(SyncPairsCompanion.insert(
      name: name,
      localPath: localPath,
      remotePath: remotePath,
      provider: provider,
      conflictPolicy: Value(conflictPolicy.name),
      direction: Value(direction.name),
      includePatterns: Value(includePatterns),
      excludePatterns: Value(excludePatterns),
      usePlaceholders: Value(usePlaceholders),
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
          _log.error('Error syncing "${pair.name}"', e);
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

  // --- Offline Queue ---

  /// Enqueue an operation for later replay (when offline).
  Future<void> enqueueOfflineOp({
    required int pairId,
    required String operation,
    required String path,
    String? targetPath,
  }) async {
    await _db.enqueueOffline(OfflineQueueCompanion.insert(
      pairId: pairId,
      operation: operation,
      path: path,
      targetPath: Value(targetPath),
    ));
    notifyListeners();
  }

  /// Replay all pending offline operations for all pairs.
  ///
  /// Call this when the app comes back online. Operations are replayed
  /// in chronological order. Failed ops are marked with an error but not
  /// retried (the user can trigger replay again).
  Future<SyncResult> replayOfflineQueue() async {
    if (_isSyncing) return const SyncResult();

    _isSyncing = true;
    _currentPairName = 'Replaying offline queue';
    notifyListeners();

    var result = const SyncResult();

    try {
      final auth = _ref.read(authProvider);
      final client = auth.client;
      final allPairs = await _db.getAllPairs();

      for (final pair in allPairs) {
        if (pair.provider != auth.currentProvider.name) continue;
        final pendingOps = await _db.getPendingOfflineOps(pair.id);
        if (pendingOps.isEmpty) continue;

        _log.info('Replaying ${pendingOps.length} offline ops for "${pair.name}"');

        for (final op in pendingOps) {
          try {
            await _executeOfflineOp(op, pair, client);
            await _db.markOfflineCompleted(op.id);
            result = result + const SyncResult(uploaded: 1);
          } catch (e) {
            _log.error('Offline replay failed for ${op.operation} ${op.path}', e);
            // Mark the op with an error but leave it in the queue
            await (_db.update(_db.offlineQueue)..where((t) => t.id.equals(op.id)))
                .write(OfflineQueueCompanion(error: Value(e.toString())));
            result = result + SyncResult(errors: 1, errorMessages: ['${op.path}: $e']);
          }
        }
      }

      // Clean up completed ops
      await _db.clearCompletedOffline();
    } finally {
      _isSyncing = false;
      _currentPairName = null;
      _lastResult = result;
      notifyListeners();
    }

    return result;
  }

  /// Execute a single offline operation.
  Future<void> _executeOfflineOp(
    OfflineQueueEntry op,
    SyncPair pair,
    CloudStorageClient client,
  ) async {
    final localBase = pair.localPath;
    final remoteBase = pair.remotePath;

    switch (op.operation) {
      case 'upload':
        final localPath = '$localBase/${op.path}';
        final remotePath = '$remoteBase/${op.path}';
        final file = File(localPath);
        if (!await file.exists()) return; // file was deleted since queue
        final bytes = await file.readAsBytes();
        final fileName = op.path.split('/').last;
        final targetDir = remotePath.substring(0, remotePath.lastIndexOf('/'));
        await client.uploadFile(bytes, fileName, targetDir.isEmpty ? '/' : targetDir);
        break;
      case 'download':
        final remotePath = '$remoteBase/${op.path}';
        final localPath = '$localBase/${op.path}';
        final bytes = await client.downloadFileBytes(remotePath);
        final file = File(localPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        break;
      case 'delete':
        final remotePath = '$remoteBase/${op.path}';
        await client.deletePath(remotePath);
        break;
      case 'rename':
        final remotePath = '$remoteBase/${op.path}';
        final newName = op.targetPath ?? op.path.split('/').last;
        await client.renamePath(remotePath, newName);
        break;
      case 'move':
        final sourcePath = '$remoteBase/${op.path}';
        final targetPath = '$remoteBase/${op.targetPath ?? op.path}';
        await client.movePath(sourcePath, targetPath);
        break;
      default:
        throw UnsupportedError('Unknown offline operation: ${op.operation}');
    }
  }

  // --- Placeholder / Cloud-Only Files ---

  /// Toggle placeholder mode for a sync pair.
  Future<void> setPlaceholders(int pairId, bool enabled) async {
    await (_db.update(_db.syncPairs)..where((t) => t.id.equals(pairId)))
        .write(SyncPairsCompanion(usePlaceholders: Value(enabled)));
    await _loadPairs();
  }

  /// Hydrate (download) a single placeholder file.
  Future<String?> hydratePlaceholder(int pairId, String relativePath) async {
    try {
      final pair = await _db.getPair(pairId);
      final auth = _ref.read(authProvider);
      final placeholder = PlaceholderService(_db);
      final localPath = await placeholder.hydrate(
        pairId: pairId,
        localBasePath: pair.localPath,
        relativePath: relativePath,
        client: auth.client,
      );
      notifyListeners();
      return localPath;
    } catch (e) {
      _log.error('Failed to hydrate placeholder: $e');
      _ref.read(errorProvider).addError('Failed to download file: $e');
      return null;
    }
  }

  /// Free up space: convert a synced file back to a placeholder.
  Future<void> dehydrateFile(int pairId, String relativePath) async {
    try {
      final pair = await _db.getPair(pairId);
      final remoteBase = pair.remotePath;
      final placeholder = PlaceholderService(_db);
      await placeholder.dehydrate(
        pairId: pairId,
        localBasePath: pair.localPath,
        relativePath: relativePath,
        remotePath: '$remoteBase/$relativePath',
        provider: pair.provider,
      );
      notifyListeners();
    } catch (e) {
      _log.error('Failed to dehydrate file: $e');
      _ref.read(errorProvider).addError('Failed to free up space: $e');
    }
  }

  /// Download all placeholder files for a pair.
  Future<int> hydrateAllPlaceholders(int pairId) async {
    try {
      final pair = await _db.getPair(pairId);
      final auth = _ref.read(authProvider);
      final placeholder = PlaceholderService(_db);
      final count = await placeholder.hydrateAll(
        pairId: pairId,
        localBasePath: pair.localPath,
        client: auth.client,
      );
      notifyListeners();
      return count;
    } catch (e) {
      _log.error('Failed to hydrate all: $e');
      _ref.read(errorProvider).addError('Failed to download all files: $e');
      return 0;
    }
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

// lib/providers/sync_provider.dart
//
// Riverpod provider for the sync engine. Manages sync pairs,
// triggers sync runs, and exposes sync status to the UI.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/background_sync_service.dart';
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
  bool _backgroundSyncEnabled = false;
  int _backgroundSyncIntervalMinutes = 15;
  int _autoEvictDays = 0; // 0 = disabled

  // Bandwidth scheduling
  bool _syncOnlyOnWifi = false;
  int _syncStartHour = 0;  // 0 = no restriction
  int _syncEndHour = 0;    // 0 = no restriction

  static const _autoEvictDaysKey = 'sync_auto_evict_days';
  static const _syncOnlyOnWifiKey = 'sync_only_on_wifi';
  static const _syncStartHourKey = 'sync_start_hour';
  static const _syncEndHourKey = 'sync_end_hour';

  SyncNotifier(this._ref) {
    _db = SyncDatabase();
    _engine = SyncEngine(_db);
    _watcher = SyncWatcherService();
    _loadPairs();
    _loadBackgroundSyncState();
    _loadAutoEvictDays();
    _loadBandwidthSchedule();
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
  int get autoEvictDays => _autoEvictDays;
  bool get syncOnlyOnWifi => _syncOnlyOnWifi;
  int get syncStartHour => _syncStartHour;
  int get syncEndHour => _syncEndHour;

  /// Check if sync is allowed right now based on bandwidth schedule.
  bool get isSyncAllowedNow {
    // Check time window
    if (_syncStartHour != 0 || _syncEndHour != 0) {
      final hour = DateTime.now().hour;
      if (_syncStartHour < _syncEndHour) {
        // e.g. 2-6: allowed between 2:00 and 5:59
        if (hour < _syncStartHour || hour >= _syncEndHour) return false;
      } else if (_syncStartHour > _syncEndHour) {
        // e.g. 22-6: allowed from 22:00 to 5:59 (overnight)
        if (hour < _syncStartHour && hour >= _syncEndHour) return false;
      }
    }
    // WiFi check would require connectivity_plus package — for now just expose the flag
    return true;
  }

  /// Whether background sync is currently scheduled on this device.
  bool get isBackgroundSyncEnabled => _backgroundSyncEnabled;

  /// The interval (in minutes) between background sync runs.
  int get backgroundSyncIntervalMinutes => _backgroundSyncIntervalMinutes;

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

  // --- Auto-eviction ---

  Future<void> _loadAutoEvictDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoEvictDays = prefs.getInt(_autoEvictDaysKey) ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadBandwidthSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _syncOnlyOnWifi = prefs.getBool(_syncOnlyOnWifiKey) ?? false;
      _syncStartHour = prefs.getInt(_syncStartHourKey) ?? 0;
      _syncEndHour = prefs.getInt(_syncEndHourKey) ?? 0;
    } catch (_) {}
  }

  /// Set bandwidth scheduling: sync only on WiFi.
  Future<void> setSyncOnlyOnWifi(bool value) async {
    _syncOnlyOnWifi = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncOnlyOnWifiKey, value);
  }

  /// Set allowed sync hours (0,0 = no restriction). Uses 24h format.
  Future<void> setSyncHours(int startHour, int endHour) async {
    _syncStartHour = startHour;
    _syncEndHour = endHour;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncStartHourKey, startHour);
    await prefs.setInt(_syncEndHourKey, endHour);
  }

  /// Get the current auto-evict threshold (days). 0 = disabled.
  int getAutoEvictDays() => _autoEvictDays;

  /// Persist the auto-evict threshold and refresh state.
  Future<void> setAutoEvictDays(int days) async {
    _autoEvictDays = days;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_autoEvictDaysKey, days);
    } catch (e) {
      _log.error('Failed to persist auto-evict days: $e');
    }
  }

  /// Run auto-eviction for all pairs that have placeholders enabled.
  Future<int> runAutoEviction() async {
    if (_autoEvictDays <= 0) return 0;
    try {
      final service = PlaceholderService(_db);
      final count = await service.autoEvict(_autoEvictDays, _db);
      if (count > 0) {
        _log.info('Auto-eviction freed $count file(s)');
        await _loadPairs();
      }
      return count;
    } catch (e) {
      _log.error('Auto-eviction failed: $e');
      return 0;
    }
  }

  // --- Background sync ---

  /// Load persisted background-sync state from SharedPreferences.
  Future<void> _loadBackgroundSyncState() async {
    if (!BackgroundSyncService.isSupported) return;
    _backgroundSyncEnabled = await BackgroundSyncService.isScheduled();
    _backgroundSyncIntervalMinutes = await BackgroundSyncService.getIntervalMinutes();
    notifyListeners();
  }

  /// Enable background sync with an optional custom [intervalMinutes].
  Future<void> enableBackgroundSync({int intervalMinutes = 15}) async {
    if (!BackgroundSyncService.isSupported) return;
    await BackgroundSyncService.schedulePeriodicSync(intervalMinutes: intervalMinutes);
    _backgroundSyncEnabled = true;
    _backgroundSyncIntervalMinutes = intervalMinutes;
    _log.info('Background sync enabled — interval: $intervalMinutes min');
    notifyListeners();
  }

  /// Disable and cancel the background sync task.
  Future<void> disableBackgroundSync() async {
    if (!BackgroundSyncService.isSupported) return;
    await BackgroundSyncService.cancelSync();
    _backgroundSyncEnabled = false;
    _log.info('Background sync disabled');
    notifyListeners();
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

  /// Sync all enabled pairs (respects bandwidth schedule).
  Future<SyncResult> syncAll() async {
    if (_isSyncing) return const SyncResult();
    if (!isSyncAllowedNow) {
      _log.info('Sync skipped: outside allowed schedule (${_syncStartHour}:00-${_syncEndHour}:00)');
      return const SyncResult();
    }

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

    // Run auto-eviction after sync completes (fire-and-forget)
    unawaited(runAutoEviction());

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
            // Check for conflicts before replaying upload operations
            if (op.operation == 'upload') {
              final remote = await client.resolvePath(op.path);
              if (remote != null) {
                final remoteModStr = remote['modificationTime'] ?? remote['lastModified'];
                if (remoteModStr != null && op.createdAt != null) {
                  DateTime? remoteMod;
                  if (remoteModStr is int) {
                    remoteMod = DateTime.fromMillisecondsSinceEpoch(remoteModStr);
                  } else {
                    remoteMod = DateTime.tryParse(remoteModStr.toString());
                  }
                  if (remoteMod != null && remoteMod.isAfter(op.createdAt!)) {
                    _log.warn('Conflict detected: ${op.path} modified on server since offline op queued');
                    result = result + SyncResult(conflicts: 1, errorMessages: ['Conflict: ${op.path} modified on server']);
                    continue; // Skip this op, leave it in queue for manual resolution
                  }
                }
              }
            }

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

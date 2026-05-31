// lib/providers/backup_provider.dart
//
// Riverpod providers for the backup engine.
//
// Providers:
//   backupServiceProvider     — singleton BackupService
//   backupPlansProvider       — StateNotifier that manages plan CRUD + state
//   backupSnapshotsProvider   — family provider: snapshots for one planId
//   backupRunningProvider     — StateNotifier: which plan IDs are running

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup_service.dart';
import '../services/log_service.dart';

// ---------------------------------------------------------------------------
// Singleton service provider
// ---------------------------------------------------------------------------

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService();
});

// ---------------------------------------------------------------------------
// Plans notifier
// ---------------------------------------------------------------------------

class BackupPlansNotifier extends StateNotifier<AsyncValue<List<BackupPlan>>> {
  static final _log = Log('BackupPlansNotifier');
  final BackupService _service;

  BackupPlansNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await _service.getPlans();
      state = AsyncValue.data(plans);
    } catch (e, st) {
      _log.error('Failed to load backup plans', e, st);
      state = AsyncValue.error(e, st);
    }
  }

  /// Reload plans from persistence.
  Future<void> refresh() => _load();

  /// Create a new backup plan.
  Future<BackupPlan?> createPlan({
    required String name,
    required String sourcePath,
    required String destinationPath,
    required String provider,
    String schedule = '0 2 * * *',
    int maxVersions = 10,
    bool encryptionEnabled = false,
    String? encryptionKey,
    bool enabled = true,
    List<String> excludePatterns = const [],
  }) async {
    if (kIsWeb) return null;
    try {
      final plan = await _service.createPlan(
        name: name,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        provider: provider,
        schedule: schedule,
        maxVersions: maxVersions,
        encryptionEnabled: encryptionEnabled,
        encryptionKey: encryptionKey,
        enabled: enabled,
        excludePatterns: excludePatterns,
      );
      await _load();
      return plan;
    } catch (e, st) {
      _log.error('createPlan failed', e, st);
      rethrow;
    }
  }

  /// Update an existing plan.
  Future<void> updatePlan(BackupPlan plan) async {
    if (kIsWeb) return;
    try {
      await _service.updatePlan(plan);
      await _load();
    } catch (e, st) {
      _log.error('updatePlan failed', e, st);
      rethrow;
    }
  }

  /// Delete a plan and all its snapshots.
  Future<void> deletePlan(String planId) async {
    if (kIsWeb) return;
    try {
      await _service.deletePlan(planId);
      await _load();
    } catch (e, st) {
      _log.error('deletePlan failed', e, st);
      rethrow;
    }
  }
}

final backupPlansProvider =
    StateNotifierProvider<BackupPlansNotifier, AsyncValue<List<BackupPlan>>>((ref) {
  return BackupPlansNotifier(ref.watch(backupServiceProvider));
});

// ---------------------------------------------------------------------------
// Snapshots family provider
// ---------------------------------------------------------------------------

class BackupSnapshotsNotifier extends StateNotifier<AsyncValue<List<BackupSnapshot>>> {
  static final _log = Log('BackupSnapshotsNotifier');
  final BackupService _service;
  final String planId;

  BackupSnapshotsNotifier(this._service, this.planId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshots = await _service.getSnapshots(planId);
      state = AsyncValue.data(snapshots);
    } catch (e, st) {
      _log.error('Failed to load snapshots for $planId', e, st);
      state = AsyncValue.error(e, st);
    }
  }

  /// Reload snapshots from persistence.
  Future<void> refresh() => _load();
}

/// Family provider: returns snapshots for a given [planId].
final backupSnapshotsProvider = StateNotifierProvider.family<
    BackupSnapshotsNotifier, AsyncValue<List<BackupSnapshot>>, String>(
  (ref, planId) => BackupSnapshotsNotifier(ref.watch(backupServiceProvider), planId),
);

// ---------------------------------------------------------------------------
// Running state notifier
// ---------------------------------------------------------------------------

/// Tracks which plan IDs currently have a running backup.
class BackupRunningNotifier extends StateNotifier<Set<String>> {
  BackupRunningNotifier() : super({});

  void markRunning(String planId) {
    state = {...state, planId};
  }

  void markDone(String planId) {
    state = state.difference({planId});
  }

  bool isRunning(String planId) => state.contains(planId);
}

final backupRunningProvider =
    StateNotifierProvider<BackupRunningNotifier, Set<String>>((ref) {
  return BackupRunningNotifier();
});

// ---------------------------------------------------------------------------
// Convenience action provider
// ---------------------------------------------------------------------------

/// Controller for triggering backup operations and refreshing providers.
class BackupController {
  static final _log = Log('BackupController');
  final Ref _ref;

  BackupController(this._ref);

  BackupService get _service => _ref.read(backupServiceProvider);

  /// Run a backup for [planId], updating running state and refreshing snapshots.
  Future<BackupSnapshot?> runBackup(
    String planId, {
    required Future<String> Function(String relativePath, List<int> bytes) uploadFile,
    List<int> Function(List<int> bytes, String key)? encryptBytes,
  }) async {
    if (kIsWeb) return null;

    _ref.read(backupRunningProvider.notifier).markRunning(planId);
    try {
      final snapshot = await _service.runBackup(
        planId,
        uploadFile: uploadFile,
        encryptBytes: encryptBytes,
      );
      // Refresh the snapshots provider for this plan
      await _ref.read(backupSnapshotsProvider(planId).notifier).refresh();
      // Refresh plans (lastRun was updated)
      await _ref.read(backupPlansProvider.notifier).refresh();
      return snapshot;
    } catch (e, st) {
      _log.error('runBackup failed for $planId', e, st);
      return null;
    } finally {
      _ref.read(backupRunningProvider.notifier).markDone(planId);
    }
  }

  /// Delete a snapshot and refresh the snapshots list.
  Future<void> deleteSnapshot(
    String planId,
    String snapshotId, {
    Future<void> Function(List<String>)? deleteRemoteFiles,
  }) async {
    await _service.deleteSnapshot(snapshotId, deleteRemoteFiles: deleteRemoteFiles);
    await _ref.read(backupSnapshotsProvider(planId).notifier).refresh();
  }

  /// Prune old snapshots for a plan and refresh.
  Future<int> pruneSnapshots(
    String planId, {
    Future<void> Function(List<String>)? deleteRemoteFiles,
  }) async {
    final pruned = await _service.pruneSnapshots(planId, deleteRemoteFiles: deleteRemoteFiles);
    await _ref.read(backupSnapshotsProvider(planId).notifier).refresh();
    return pruned;
  }
}

final backupControllerProvider = Provider<BackupController>((ref) {
  return BackupController(ref);
});

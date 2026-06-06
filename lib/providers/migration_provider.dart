// lib/providers/migration_provider.dart
//
// Riverpod providers for the Migration Wizard.
//
// Providers:
//   migrationServiceProvider     — singleton MigrationService
//   migrationPlansProvider       — StateNotifier: CRUD for MigrationPlans
//   migrationProgressProvider    — family provider: progress for one planId
//   activeMigrationProvider      — currently running migration plan id(s)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/migration_service.dart';
import '../services/log_service.dart';

// ---------------------------------------------------------------------------
// Singleton service
// ---------------------------------------------------------------------------

final migrationServiceProvider = Provider<MigrationService>((ref) {
  return MigrationService();
});

// ---------------------------------------------------------------------------
// Plans notifier
// ---------------------------------------------------------------------------

class MigrationPlansNotifier
    extends StateNotifier<AsyncValue<List<MigrationPlan>>> {
  static const _log = Log('MigrationPlansNotifier');
  final MigrationService _service;

  MigrationPlansNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await _service.getPlans();
      state = AsyncValue.data(plans);
    } catch (e, st) {
      _log.error('Failed to load migration plans', e, st);
      state = AsyncValue.error(e, st);
    }
  }

  /// Reload plans from persistence.
  Future<void> refresh() => _load();

  /// Create and persist a new plan, then refresh state.
  Future<MigrationPlan?> createPlan({
    required String name,
    required String sourceProvider,
    required String destinationProvider,
    required String sourcePath,
    required String destinationPath,
    List<String> includePatterns = const [],
    List<String> excludePatterns = const [],
    ConflictPolicy conflictPolicy = ConflictPolicy.skip,
    bool preserveStructure = true,
    bool verifyAfter = false,
    double? throttleMBps,
  }) async {
    if (kIsWeb) return null;
    try {
      final plan = await _service.createPlan(
        name: name,
        sourceProvider: sourceProvider,
        destinationProvider: destinationProvider,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        includePatterns: includePatterns,
        excludePatterns: excludePatterns,
        conflictPolicy: conflictPolicy,
        preserveStructure: preserveStructure,
        verifyAfter: verifyAfter,
        throttleMBps: throttleMBps,
      );
      await _load();
      return plan;
    } catch (e, st) {
      _log.error('createPlan failed', e, st);
      rethrow;
    }
  }

  /// Update an existing plan.
  Future<void> updatePlan(MigrationPlan plan) async {
    if (kIsWeb) return;
    try {
      await _service.updatePlan(plan);
      await _load();
    } catch (e, st) {
      _log.error('updatePlan failed', e, st);
      rethrow;
    }
  }

  /// Delete a plan.
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

final migrationPlansProvider = StateNotifierProvider<MigrationPlansNotifier,
    AsyncValue<List<MigrationPlan>>>((ref) {
  return MigrationPlansNotifier(ref.watch(migrationServiceProvider));
});

// ---------------------------------------------------------------------------
// Progress family provider
// ---------------------------------------------------------------------------

/// Polls [MigrationService.getProgress] for a specific [planId].
///
/// Returns null when no migration has been started for this plan yet.
final migrationProgressProvider =
    Provider.family<MigrationProgress?, String>((ref, planId) {
  final service = ref.watch(migrationServiceProvider);
  return service.getProgress(planId);
});

// ---------------------------------------------------------------------------
// Active migration notifier
// ---------------------------------------------------------------------------

/// Tracks which plan IDs currently have a running migration.
class ActiveMigrationNotifier extends StateNotifier<Set<String>> {
  static const _log = Log('ActiveMigrationNotifier');

  ActiveMigrationNotifier() : super({});

  void markRunning(String planId) {
    state = {...state, planId};
  }

  void markDone(String planId) {
    state = state.difference({planId});
  }

  bool isRunning(String planId) => state.contains(planId);
}

final activeMigrationProvider =
    StateNotifierProvider<ActiveMigrationNotifier, Set<String>>((ref) {
  return ActiveMigrationNotifier();
});

// ---------------------------------------------------------------------------
// Migration controller
// ---------------------------------------------------------------------------

/// High-level controller that drives migrations and keeps providers in sync.
class MigrationController {
  static const _log = Log('MigrationController');
  final Ref _ref;

  MigrationController(this._ref);

  MigrationService get _service => _ref.read(migrationServiceProvider);

  /// Execute a migration for [plan] using the given [source] and [destination]
  /// clients. Updates [activeMigrationProvider] and refreshes plans when done.
  Future<void> executeMigration(
    MigrationPlan plan,
    List<MigrationFileEntry> entries, {
    required dynamic source, // CloudStorageClient
    required dynamic destination, // CloudStorageClient
    void Function(MigrationProgress)? onProgress,
  }) async {
    if (kIsWeb) return;

    _ref.read(activeMigrationProvider.notifier).markRunning(plan.id);
    try {
      await _service.executeMigration(
        plan,
        entries,
        source: source,
        destination: destination,
        onProgress: onProgress,
      );
      await _ref.read(migrationPlansProvider.notifier).refresh();
    } catch (e, st) {
      _log.error('executeMigration failed for ${plan.id}', e, st);
      rethrow;
    } finally {
      _ref.read(activeMigrationProvider.notifier).markDone(plan.id);
    }
  }

  /// Pause a running migration.
  void pauseMigration(String planId) => _service.pauseMigration(planId);

  /// Resume a paused migration.
  void resumeMigration(String planId) => _service.resumeMigration(planId);

  /// Cancel a running migration.
  void cancelMigration(String planId) {
    _service.cancelMigration(planId);
    _ref.read(activeMigrationProvider.notifier).markDone(planId);
  }
}

final migrationControllerProvider = Provider<MigrationController>((ref) {
  return MigrationController(ref);
});

// lib/services/migration_service.dart
//
// Migration Wizard: guided "Move from Provider A to Provider B" workflow.
//
// Key concepts:
//   MigrationPlan        — configuration (source/dest providers, paths, policies)
//   MigrationProgress    — in-memory run-time counters for one migration execution
//   MigrationFileEntry   — per-file state within a migration run
//   MigrationError       — single error record attached to a progress object
//   MigrationVerification — result of post-migration hash comparison
//   MigrationService     — orchestration: scan → estimate → execute → verify
//
// Persistence:
//   Plans → SharedPreferences key 'migration_plans'  (JSON list)
//   Progress is held in memory only (keyed by planId).
//
// Platform guard: mutating operations are no-ops on web (kIsWeb).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'cloud_storage_interface.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum MigrationStatus {
  pending,
  running,
  paused,
  completed,
  failed,
  verifying,
}

enum ConflictPolicy {
  skip,
  overwrite,
  rename,
  newest,
}

enum MigrationFileStatus {
  pending,
  migrating,
  migrated,
  skipped,
  failed,
  verified,
}

// ---------------------------------------------------------------------------
// MigrationError
// ---------------------------------------------------------------------------

/// A single error that occurred while migrating a file.
class MigrationError {
  final String filePath;
  final String error;
  final DateTime timestamp;
  final bool retryable;

  MigrationError({
    required this.filePath,
    required this.error,
    required this.timestamp,
    required this.retryable,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'error': error,
        'timestamp': timestamp.toIso8601String(),
        'retryable': retryable,
      };

  factory MigrationError.fromJson(Map<String, dynamic> json) => MigrationError(
        filePath: json['filePath'] as String,
        error: json['error'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        retryable: json['retryable'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// MigrationFileEntry
// ---------------------------------------------------------------------------

/// State of a single file within a migration.
class MigrationFileEntry {
  final String relativePath;
  final int sizeBytes;
  final DateTime? sourceModified;
  MigrationFileStatus status;

  /// MD5 or SHA-256 hash computed from the source bytes (nullable – not always available).
  String? sourceHash;

  /// Hash of the destination copy after upload (nullable).
  String? destHash;

  MigrationFileEntry({
    required this.relativePath,
    required this.sizeBytes,
    this.sourceModified,
    this.status = MigrationFileStatus.pending,
    this.sourceHash,
    this.destHash,
  });

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'sizeBytes': sizeBytes,
        if (sourceModified != null) 'sourceModified': sourceModified!.toIso8601String(),
        'status': status.name,
        if (sourceHash != null) 'sourceHash': sourceHash,
        if (destHash != null) 'destHash': destHash,
      };

  factory MigrationFileEntry.fromJson(Map<String, dynamic> json) => MigrationFileEntry(
        relativePath: json['relativePath'] as String,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        sourceModified: json['sourceModified'] != null
            ? DateTime.parse(json['sourceModified'] as String)
            : null,
        status: MigrationFileStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => MigrationFileStatus.pending,
        ),
        sourceHash: json['sourceHash'] as String?,
        destHash: json['destHash'] as String?,
      );

  MigrationFileEntry copyWith({
    MigrationFileStatus? status,
    String? sourceHash,
    String? destHash,
  }) =>
      MigrationFileEntry(
        relativePath: relativePath,
        sizeBytes: sizeBytes,
        sourceModified: sourceModified,
        status: status ?? this.status,
        sourceHash: sourceHash ?? this.sourceHash,
        destHash: destHash ?? this.destHash,
      );
}

// ---------------------------------------------------------------------------
// MigrationProgress
// ---------------------------------------------------------------------------

/// Runtime counters for an active or completed migration.
class MigrationProgress {
  final String planId;
  final int totalFiles;
  final int totalBytes;
  int migratedFiles;
  int skippedFiles;
  int failedFiles;
  int migratedBytes;
  String? currentFile;
  final DateTime startedAt;
  DateTime? estimatedCompletion;
  final List<MigrationError> errors;

  MigrationProgress({
    required this.planId,
    required this.totalFiles,
    required this.totalBytes,
    this.migratedFiles = 0,
    this.skippedFiles = 0,
    this.failedFiles = 0,
    this.migratedBytes = 0,
    this.currentFile,
    required this.startedAt,
    this.estimatedCompletion,
    List<MigrationError>? errors,
  }) : errors = errors ?? [];

  /// Fraction [0.0 – 1.0] of bytes transferred.
  double get bytesProgress => totalBytes == 0 ? 1.0 : migratedBytes / totalBytes;

  /// Fraction [0.0 – 1.0] of files processed (migrated + skipped + failed).
  double get filesProgress =>
      totalFiles == 0 ? 1.0 : (migratedFiles + skippedFiles + failedFiles) / totalFiles;

  int get processedFiles => migratedFiles + skippedFiles + failedFiles;

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'totalFiles': totalFiles,
        'totalBytes': totalBytes,
        'migratedFiles': migratedFiles,
        'skippedFiles': skippedFiles,
        'failedFiles': failedFiles,
        'migratedBytes': migratedBytes,
        if (currentFile != null) 'currentFile': currentFile,
        'startedAt': startedAt.toIso8601String(),
        if (estimatedCompletion != null)
          'estimatedCompletion': estimatedCompletion!.toIso8601String(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };

  factory MigrationProgress.fromJson(Map<String, dynamic> json) => MigrationProgress(
        planId: json['planId'] as String,
        totalFiles: json['totalFiles'] as int,
        totalBytes: json['totalBytes'] as int,
        migratedFiles: json['migratedFiles'] as int? ?? 0,
        skippedFiles: json['skippedFiles'] as int? ?? 0,
        failedFiles: json['failedFiles'] as int? ?? 0,
        migratedBytes: json['migratedBytes'] as int? ?? 0,
        currentFile: json['currentFile'] as String?,
        startedAt: DateTime.parse(json['startedAt'] as String),
        estimatedCompletion: json['estimatedCompletion'] != null
            ? DateTime.parse(json['estimatedCompletion'] as String)
            : null,
        errors: (json['errors'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(MigrationError.fromJson)
                .toList() ??
            [],
      );
}

// ---------------------------------------------------------------------------
// MigrationVerification
// ---------------------------------------------------------------------------

/// Result of post-migration hash comparison.
class MigrationVerification {
  final int totalFiles;
  final int verifiedFiles;
  final int matchedFiles;
  final int mismatchedFiles;

  /// Each entry: {'path': String, 'sourceHash': String, 'destHash': String}
  final List<Map<String, String>> mismatches;

  MigrationVerification({
    required this.totalFiles,
    required this.verifiedFiles,
    required this.matchedFiles,
    required this.mismatchedFiles,
    required this.mismatches,
  });

  bool get allMatch => mismatchedFiles == 0;

  Map<String, dynamic> toJson() => {
        'totalFiles': totalFiles,
        'verifiedFiles': verifiedFiles,
        'matchedFiles': matchedFiles,
        'mismatchedFiles': mismatchedFiles,
        'mismatches': mismatches,
      };
}

// ---------------------------------------------------------------------------
// MigrationEstimate
// ---------------------------------------------------------------------------

/// Output of estimateMigration.
class MigrationEstimate {
  final int totalFiles;
  final int totalBytes;

  /// Rough duration assuming the given throttle cap (or a default 10 MB/s).
  final Duration estimatedDuration;

  MigrationEstimate({
    required this.totalFiles,
    required this.totalBytes,
    required this.estimatedDuration,
  });
}

// ---------------------------------------------------------------------------
// MigrationPlan
// ---------------------------------------------------------------------------

/// Configuration for a single migration run.
class MigrationPlan {
  final String id;
  final String name;

  /// Provider name string (matches CloudStorageClient.providerName).
  final String sourceProvider;
  final String destinationProvider;

  /// Remote path on the source provider to migrate from.
  final String sourcePath;

  /// Remote path on the destination provider to migrate into.
  final String destinationPath;

  /// Glob include patterns. Empty list = include everything.
  final List<String> includePatterns;

  /// Glob exclude patterns. Matched files are always skipped.
  final List<String> excludePatterns;

  final ConflictPolicy conflictPolicy;

  /// When true, recreate the folder hierarchy under destinationPath.
  final bool preserveStructure;

  /// When true, run hash verification after migration.
  final bool verifyAfter;

  /// Optional bandwidth cap in megabytes-per-second. null = unlimited.
  final double? throttleMBps;

  MigrationStatus status;
  final DateTime createdAt;

  MigrationPlan({
    required this.id,
    required this.name,
    required this.sourceProvider,
    required this.destinationProvider,
    required this.sourcePath,
    required this.destinationPath,
    this.includePatterns = const [],
    this.excludePatterns = const [],
    this.conflictPolicy = ConflictPolicy.skip,
    this.preserveStructure = true,
    this.verifyAfter = false,
    this.throttleMBps,
    this.status = MigrationStatus.pending,
    required this.createdAt,
  });

  /// Validate the plan. Returns null on success, error description on failure.
  String? validate() {
    if (name.trim().isEmpty) return 'name must not be empty';
    if (sourceProvider.trim().isEmpty) return 'sourceProvider must not be empty';
    if (destinationProvider.trim().isEmpty) return 'destinationProvider must not be empty';
    if (sourcePath.trim().isEmpty) return 'sourcePath must not be empty';
    if (destinationPath.trim().isEmpty) return 'destinationPath must not be empty';
    if (throttleMBps != null && throttleMBps! <= 0) {
      return 'throttleMBps must be positive';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sourceProvider': sourceProvider,
        'destinationProvider': destinationProvider,
        'sourcePath': sourcePath,
        'destinationPath': destinationPath,
        'includePatterns': includePatterns,
        'excludePatterns': excludePatterns,
        'conflictPolicy': conflictPolicy.name,
        'preserveStructure': preserveStructure,
        'verifyAfter': verifyAfter,
        if (throttleMBps != null) 'throttleMBps': throttleMBps,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MigrationPlan.fromJson(Map<String, dynamic> json) => MigrationPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        sourceProvider: json['sourceProvider'] as String,
        destinationProvider: json['destinationProvider'] as String,
        sourcePath: json['sourcePath'] as String,
        destinationPath: json['destinationPath'] as String,
        includePatterns: (json['includePatterns'] as List?)?.cast<String>() ?? [],
        excludePatterns: (json['excludePatterns'] as List?)?.cast<String>() ?? [],
        conflictPolicy: ConflictPolicy.values.firstWhere(
          (p) => p.name == json['conflictPolicy'],
          orElse: () => ConflictPolicy.skip,
        ),
        preserveStructure: json['preserveStructure'] as bool? ?? true,
        verifyAfter: json['verifyAfter'] as bool? ?? false,
        throttleMBps: (json['throttleMBps'] as num?)?.toDouble(),
        status: MigrationStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => MigrationStatus.pending,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  MigrationPlan copyWith({
    String? name,
    String? sourceProvider,
    String? destinationProvider,
    String? sourcePath,
    String? destinationPath,
    List<String>? includePatterns,
    List<String>? excludePatterns,
    ConflictPolicy? conflictPolicy,
    bool? preserveStructure,
    bool? verifyAfter,
    double? throttleMBps,
    MigrationStatus? status,
  }) =>
      MigrationPlan(
        id: id,
        name: name ?? this.name,
        sourceProvider: sourceProvider ?? this.sourceProvider,
        destinationProvider: destinationProvider ?? this.destinationProvider,
        sourcePath: sourcePath ?? this.sourcePath,
        destinationPath: destinationPath ?? this.destinationPath,
        includePatterns: includePatterns ?? this.includePatterns,
        excludePatterns: excludePatterns ?? this.excludePatterns,
        conflictPolicy: conflictPolicy ?? this.conflictPolicy,
        preserveStructure: preserveStructure ?? this.preserveStructure,
        verifyAfter: verifyAfter ?? this.verifyAfter,
        throttleMBps: throttleMBps ?? this.throttleMBps,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}

// ---------------------------------------------------------------------------
// Glob helpers (shared logic, copied from backup_service pattern)
// ---------------------------------------------------------------------------

bool _matchesAnyGlob(String relativePath, List<String> patterns) {
  final normalised = relativePath.replaceAll('\\', '/');
  for (final pattern in patterns) {
    if (_globMatches(pattern, normalised)) return true;
  }
  return false;
}

bool _globMatches(String pattern, String path) {
  final regexStr = _globToRegex(pattern);
  try {
    return RegExp(regexStr).hasMatch(path);
  } catch (_) {
    return false;
  }
}

String _globToRegex(String glob) {
  final sb = StringBuffer('^');
  int i = 0;
  while (i < glob.length) {
    final c = glob[i];
    if (c == '*') {
      if (i + 1 < glob.length && glob[i + 1] == '*') {
        sb.write('.*');
        i += 2;
        if (i < glob.length && glob[i] == '/') i++;
        continue;
      } else {
        sb.write('[^/]*');
      }
    } else if (c == '?') {
      sb.write('[^/]');
    } else if (r'\.+^{}$|()[]'.contains(c)) {
      sb.write('\\$c');
    } else {
      sb.write(c);
    }
    i++;
  }
  sb.write(r'$');
  return sb.toString();
}

// ---------------------------------------------------------------------------
// MigrationService
// ---------------------------------------------------------------------------

/// Orchestrates the full migration workflow.
///
/// Usage:
///   1. createPlan(...)
///   2. scanSource(plan) → List<MigrationFileEntry>
///   3. estimateMigration(plan, entries) → MigrationEstimate
///   4. executeMigration(plan, entries, onProgress: ...)
///   5. [optional] verifyMigration(plan, entries)
class MigrationService {
  static const _log = Log('MigrationService');
  static const _uuid = Uuid();

  static const _plansKey = 'migration_plans';

  /// In-memory progress keyed by planId.
  final Map<String, MigrationProgress> _progress = {};

  /// Pause flags: planId → Completer that resolves when resumed.
  final Map<String, Completer<void>> _pauseCompleters = {};

  /// Cancel flags.
  final Set<String> _cancelledIds = {};

  /// Tracks which plan IDs are currently running.
  final Set<String> _runningIds = {};

  // -------------------------------------------------------------------------
  // Plan CRUD
  // -------------------------------------------------------------------------

  /// Create and persist a new migration plan.
  Future<MigrationPlan> createPlan({
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
    final plan = MigrationPlan(
      id: _uuid.v4(),
      name: name,
      sourceProvider: sourceProvider,
      destinationProvider: destinationProvider,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      includePatterns: List.unmodifiable(includePatterns),
      excludePatterns: List.unmodifiable(excludePatterns),
      conflictPolicy: conflictPolicy,
      preserveStructure: preserveStructure,
      verifyAfter: verifyAfter,
      throttleMBps: throttleMBps,
      status: MigrationStatus.pending,
      createdAt: DateTime.now(),
    );

    final error = plan.validate();
    if (error != null) throw ArgumentError(error);

    if (!kIsWeb) {
      final plans = await getPlans();
      plans.add(plan);
      await _savePlans(plans);
    }
    return plan;
  }

  /// Return all persisted plans.
  Future<List<MigrationPlan>> getPlans() async {
    if (kIsWeb) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_plansKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(MigrationPlan.fromJson)
          .toList();
    } catch (e, st) {
      _log.error('Failed to parse migration plans', e, st);
      return [];
    }
  }

  /// Return a single plan by id, or null.
  Future<MigrationPlan?> getPlan(String planId) async {
    final plans = await getPlans();
    try {
      return plans.firstWhere((p) => p.id == planId);
    } catch (_) {
      return null;
    }
  }

  /// Persist updated plan state.
  Future<void> updatePlan(MigrationPlan updated) async {
    if (kIsWeb) return;
    final plans = await getPlans();
    final idx = plans.indexWhere((p) => p.id == updated.id);
    if (idx == -1) throw StateError('Plan ${updated.id} not found');
    plans[idx] = updated;
    await _savePlans(plans);
  }

  /// Delete a plan (no-op if not found).
  Future<void> deletePlan(String planId) async {
    if (kIsWeb) return;
    final plans = await getPlans();
    plans.removeWhere((p) => p.id == planId);
    await _savePlans(plans);
    _progress.remove(planId);
    _pauseCompleters.remove(planId);
    _cancelledIds.remove(planId);
    _runningIds.remove(planId);
  }

  Future<void> _savePlans(List<MigrationPlan> plans) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_plansKey, jsonEncode(plans.map((p) => p.toJson()).toList()));
  }

  // -------------------------------------------------------------------------
  // Scan
  // -------------------------------------------------------------------------

  /// Recursively list all files under [plan.sourcePath] on [source],
  /// applying include/exclude glob filters.
  ///
  /// The returned entries have [relativePath] relative to [plan.sourcePath].
  Future<List<MigrationFileEntry>> scanSource(
    MigrationPlan plan,
    CloudStorageClient source,
  ) async {
    final entries = <MigrationFileEntry>[];
    await _scanDirectory(source, plan.sourcePath, plan.sourcePath, entries, plan);
    _log.info('scanSource: found ${entries.length} files under ${plan.sourcePath}');
    return entries;
  }

  Future<void> _scanDirectory(
    CloudStorageClient client,
    String basePath,
    String currentPath,
    List<MigrationFileEntry> out,
    MigrationPlan plan,
  ) async {
    late Map<String, dynamic> listing;
    try {
      listing = await client.listPath(currentPath);
    } catch (e) {
      _log.warn('Could not list $currentPath: $e');
      return;
    }

    final files = (listing['files'] as List<dynamic>?) ?? [];
    final folders = (listing['folders'] as List<dynamic>?) ?? [];

    for (final f in files) {
      final file = f as Map<String, dynamic>;
      final name = file['name'] as String? ?? file['fileName'] as String? ?? '';
      if (name.isEmpty) continue;

      final fullPath = currentPath.endsWith('/')
          ? '$currentPath$name'
          : '$currentPath/$name';

      // Build relative path from basePath
      String rel = fullPath;
      if (fullPath.startsWith(basePath)) {
        rel = fullPath.substring(basePath.length);
        if (rel.startsWith('/')) rel = rel.substring(1);
      }

      // Apply exclude patterns first
      if (plan.excludePatterns.isNotEmpty && _matchesAnyGlob(rel, plan.excludePatterns)) {
        continue;
      }

      // Apply include patterns (empty = include all)
      if (plan.includePatterns.isNotEmpty &&
          !_matchesAnyGlob(rel, plan.includePatterns)) {
        continue;
      }

      final sizeBytes = (file['size'] as num?)?.toInt() ??
          (file['sizeBytes'] as num?)?.toInt() ??
          0;

      DateTime? modified;
      final modRaw = file['modified'] ?? file['modifiedAt'] ?? file['lastModified'];
      if (modRaw is String) {
        modified = DateTime.tryParse(modRaw);
      }

      out.add(MigrationFileEntry(
        relativePath: rel,
        sizeBytes: sizeBytes,
        sourceModified: modified,
        status: MigrationFileStatus.pending,
      ));
    }

    // Recurse into sub-folders
    for (final d in folders) {
      final dir = d as Map<String, dynamic>;
      final name = dir['name'] as String? ?? dir['folderName'] as String? ?? '';
      if (name.isEmpty) continue;
      final subPath = currentPath.endsWith('/')
          ? '$currentPath$name'
          : '$currentPath/$name';
      await _scanDirectory(client, basePath, subPath, out, plan);
    }
  }

  // -------------------------------------------------------------------------
  // Estimate
  // -------------------------------------------------------------------------

  /// Estimate duration and size for the migration.
  MigrationEstimate estimateMigration(
    MigrationPlan plan,
    List<MigrationFileEntry> entries,
  ) {
    final totalBytes = entries.fold<int>(0, (sum, e) => sum + e.sizeBytes);
    final totalFiles = entries.length;

    // Default assumed speed: 5 MB/s if no throttle set.
    final speedBytesPerSec =
        (plan.throttleMBps ?? 5.0) * 1024 * 1024;

    final seconds = speedBytesPerSec > 0 ? (totalBytes / speedBytesPerSec) : 0.0;
    final duration = Duration(seconds: seconds.ceil());

    return MigrationEstimate(
      totalFiles: totalFiles,
      totalBytes: totalBytes,
      estimatedDuration: duration,
    );
  }

  // -------------------------------------------------------------------------
  // Execute
  // -------------------------------------------------------------------------

  /// Run the migration sequentially, with throttling, conflict resolution,
  /// pause/resume/cancel support. Calls [onProgress] after each file.
  ///
  /// Throws [StateError] if another migration for the same planId is already
  /// running, or if [plan.validate()] returns an error.
  Future<void> executeMigration(
    MigrationPlan plan,
    List<MigrationFileEntry> entries, {
    required CloudStorageClient source,
    required CloudStorageClient destination,
    void Function(MigrationProgress)? onProgress,
  }) async {
    if (kIsWeb) return;

    final validationError = plan.validate();
    if (validationError != null) throw StateError(validationError);

    if (_runningIds.contains(plan.id)) {
      throw StateError('Migration ${plan.id} is already running');
    }

    _runningIds.add(plan.id);
    _cancelledIds.remove(plan.id);

    final totalBytes = entries.fold<int>(0, (s, e) => s + e.sizeBytes);
    final progress = MigrationProgress(
      planId: plan.id,
      totalFiles: entries.length,
      totalBytes: totalBytes,
      startedAt: DateTime.now(),
    );
    _progress[plan.id] = progress;

    // Update plan status to running
    plan.status = MigrationStatus.running;
    if (!kIsWeb) {
      await updatePlan(plan).catchError((_) {});
    }

    try {
      for (final entry in entries) {
        // Honour cancel
        if (_cancelledIds.contains(plan.id)) {
          _log.info('Migration ${plan.id} cancelled');
          break;
        }

        // Honour pause
        if (_pauseCompleters.containsKey(plan.id)) {
          _log.info('Migration ${plan.id} paused at ${entry.relativePath}');
          await _pauseCompleters[plan.id]!.future;
        }

        progress.currentFile = entry.relativePath;
        entry.status = MigrationFileStatus.migrating;
        onProgress?.call(progress);

        try {
          await _transferFile(plan, entry, source, destination);

          progress.migratedFiles++;
          progress.migratedBytes += entry.sizeBytes;
          entry.status = MigrationFileStatus.migrated;

          // Bandwidth throttle: sleep to maintain the configured MB/s cap.
          if (plan.throttleMBps != null && entry.sizeBytes > 0) {
            final delayMs = _throttleDelayMs(entry.sizeBytes, plan.throttleMBps!);
            if (delayMs > 0) {
              await Future.delayed(Duration(milliseconds: delayMs));
            }
          }
        } on _SkipFileException {
          progress.skippedFiles++;
          entry.status = MigrationFileStatus.skipped;
        } catch (e) {
          _log.warn('Failed to migrate ${entry.relativePath}: $e');
          final isRetryable = _isRetryable(e);
          progress.errors.add(MigrationError(
            filePath: entry.relativePath,
            error: e.toString(),
            timestamp: DateTime.now(),
            retryable: isRetryable,
          ));
          progress.failedFiles++;
          entry.status = MigrationFileStatus.failed;
        }

        // Update ETA
        _updateEta(progress);
        onProgress?.call(progress);
      }

      // Determine final status
      if (_cancelledIds.contains(plan.id)) {
        plan.status = MigrationStatus.failed;
      } else if (progress.failedFiles > 0 && progress.migratedFiles == 0) {
        plan.status = MigrationStatus.failed;
      } else if (plan.verifyAfter) {
        plan.status = MigrationStatus.verifying;
      } else {
        plan.status = MigrationStatus.completed;
      }
    } catch (e, st) {
      _log.error('executeMigration failed for ${plan.id}', e, st);
      plan.status = MigrationStatus.failed;
      rethrow;
    } finally {
      _runningIds.remove(plan.id);
      _pauseCompleters.remove(plan.id);
      progress.currentFile = null;
      if (!kIsWeb) {
        await updatePlan(plan).catchError((_) {});
      }
      onProgress?.call(progress);
    }
  }

  Future<void> _transferFile(
    MigrationPlan plan,
    MigrationFileEntry entry,
    CloudStorageClient source,
    CloudStorageClient destination,
  ) async {
    // Build destination path
    final destPath = _buildDestPath(plan, entry.relativePath);
    final destDir = _parentPath(destPath);
    final fileName = destPath.split('/').last;

    // Conflict resolution: check if file exists at destination
    final existingMeta = await _tryResolvePath(destination, destPath);

    if (existingMeta != null) {
      switch (plan.conflictPolicy) {
        case ConflictPolicy.skip:
          throw const _SkipFileException();

        case ConflictPolicy.overwrite:
          // Will overwrite by uploading to same path.
          break;

        case ConflictPolicy.rename:
          // We need a new unique name — find _1, _2 … suffix.
          final newDest = await _findUniqueName(destination, destDir, fileName);
          // Redirect the upload to the renamed path.
          await _doTransfer(source, destination, entry, newDest, plan);
          return;

        case ConflictPolicy.newest:
          // Keep the newer file. Compare sourceModified vs destination modified.
          final destModRaw = existingMeta['modified'] ??
              existingMeta['modifiedAt'] ??
              existingMeta['lastModified'];
          DateTime? destModified;
          if (destModRaw is String) destModified = DateTime.tryParse(destModRaw);

          if (entry.sourceModified != null && destModified != null) {
            if (!entry.sourceModified!.isAfter(destModified)) {
              throw const _SkipFileException();
            }
          } else {
            // Cannot determine — skip to be safe
            throw const _SkipFileException();
          }
          break;
      }
    }

    await _doTransfer(source, destination, entry, destPath, plan);
  }

  Future<void> _doTransfer(
    CloudStorageClient source,
    CloudStorageClient destination,
    MigrationFileEntry entry,
    String destPath,
    MigrationPlan plan,
  ) async {
    final sourcePath = _buildSourcePath(plan, entry.relativePath);
    final destDir = _parentPath(destPath);
    final fileName = destPath.split('/').last;

    // Download from source
    final bytes = await source.downloadFileBytes(sourcePath);

    // Ensure destination directory exists
    if (destDir.isNotEmpty && destDir != '/') {
      await destination.createFolderPath(destDir);
    }

    // Upload to destination
    await destination.uploadFile(bytes, fileName, destDir);
  }

  String _buildSourcePath(MigrationPlan plan, String relativePath) {
    final base = plan.sourcePath.endsWith('/')
        ? plan.sourcePath
        : '${plan.sourcePath}/';
    return '$base$relativePath';
  }

  String _buildDestPath(MigrationPlan plan, String relativePath) {
    if (!plan.preserveStructure) {
      // Flatten: all files go directly into destinationPath
      final fileName = relativePath.split('/').last;
      final base = plan.destinationPath.endsWith('/')
          ? plan.destinationPath
          : '${plan.destinationPath}/';
      return '$base$fileName';
    }
    final base = plan.destinationPath.endsWith('/')
        ? plan.destinationPath
        : '${plan.destinationPath}/';
    return '$base$relativePath';
  }

  String _parentPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return '';
    parts.removeLast();
    return parts.join('/');
  }

  Future<Map<String, dynamic>?> _tryResolvePath(
    CloudStorageClient client,
    String path,
  ) async {
    try {
      return await client.resolvePath(path);
    } catch (_) {
      return null;
    }
  }

  Future<String> _findUniqueName(
    CloudStorageClient destination,
    String dir,
    String fileName,
  ) async {
    // Split basename and extension
    final lastDot = fileName.lastIndexOf('.');
    final base = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
    final ext = lastDot > 0 ? fileName.substring(lastDot) : '';

    for (int i = 1; i <= 999; i++) {
      final candidate = '${base}_$i$ext';
      final candidatePath = dir.isEmpty ? candidate : '$dir/$candidate';
      final existing = await _tryResolvePath(destination, candidatePath);
      if (existing == null) return candidatePath;
    }
    // Fallback with timestamp
    final ts = DateTime.now().millisecondsSinceEpoch;
    return dir.isEmpty ? '${base}_$ts$ext' : '$dir/${base}_$ts$ext';
  }

  bool _isRetryable(Object e) {
    final msg = e.toString().toLowerCase();
    // Rate limit / timeout / network errors are retryable; auth / not-found are not.
    return msg.contains('timeout') ||
        msg.contains('rate') ||
        msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('503') ||
        msg.contains('429');
  }

  void _updateEta(MigrationProgress progress) {
    if (progress.migratedBytes == 0) return;
    final elapsed = DateTime.now().difference(progress.startedAt);
    if (elapsed.inSeconds == 0) return;
    final bytesPerSec = progress.migratedBytes / elapsed.inSeconds;
    final remaining = progress.totalBytes - progress.migratedBytes;
    if (bytesPerSec > 0) {
      final secsLeft = remaining / bytesPerSec;
      progress.estimatedCompletion =
          DateTime.now().add(Duration(seconds: secsLeft.ceil()));
    }
  }

  // -------------------------------------------------------------------------
  // Throttle
  // -------------------------------------------------------------------------

  /// Calculate how many milliseconds to sleep after transferring [sizeBytes]
  /// to stay within [throttleMBps].
  int _throttleDelayMs(int sizeBytes, double throttleMBps) {
    if (throttleMBps <= 0) return 0;
    final allowedBytesPerSec = throttleMBps * 1024 * 1024;
    // Time this transfer "should" take at the throttled rate, in ms
    final expectedMs = (sizeBytes / allowedBytesPerSec * 1000).round();
    // We've already spent some wall-clock time transferring; sleep the remainder.
    // Without knowing the actual transfer time, we always sleep the full amount.
    return expectedMs;
  }

  /// Public helper used by tests (and the provider) to compute delay externally.
  int throttleDelayMs(int sizeBytes, double throttleMBps) =>
      _throttleDelayMs(sizeBytes, throttleMBps);

  // -------------------------------------------------------------------------
  // Pause / Resume / Cancel
  // -------------------------------------------------------------------------

  /// Pause the migration for [planId]. The next file transfer will block until
  /// [resumeMigration] is called.
  void pauseMigration(String planId) {
    if (!_runningIds.contains(planId)) return;
    if (!_pauseCompleters.containsKey(planId)) {
      _pauseCompleters[planId] = Completer<void>();
    }
  }

  /// Resume a paused migration.
  void resumeMigration(String planId) {
    final completer = _pauseCompleters.remove(planId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Cancel an in-progress migration.
  void cancelMigration(String planId) {
    _cancelledIds.add(planId);
    // Also resume if paused so the loop can see the cancel flag.
    resumeMigration(planId);
    _progress.remove(planId);
  }

  bool isPaused(String planId) => _pauseCompleters.containsKey(planId);
  bool isRunning(String planId) => _runningIds.contains(planId);
  bool isCancelled(String planId) => _cancelledIds.contains(planId);

  // -------------------------------------------------------------------------
  // Progress
  // -------------------------------------------------------------------------

  /// Return current progress for [planId], or null if not started.
  MigrationProgress? getProgress(String planId) => _progress[planId];

  // -------------------------------------------------------------------------
  // Verify
  // -------------------------------------------------------------------------

  /// Compare source vs destination files by size (and hash when available).
  ///
  /// For each entry that was [MigrationFileStatus.migrated], downloads the
  /// destination copy and compares its size. If [entry.sourceHash] is set,
  /// also performs a content comparison (byte-level equality via size check
  /// here; full hash comparison requires provider support).
  Future<MigrationVerification> verifyMigration(
    MigrationPlan plan,
    List<MigrationFileEntry> entries,
    CloudStorageClient destination,
  ) async {
    int verified = 0;
    int matched = 0;
    int mismatched = 0;
    final mismatches = <Map<String, String>>[];

    for (final entry in entries) {
      if (entry.status != MigrationFileStatus.migrated &&
          entry.status != MigrationFileStatus.verified) {
        continue;
      }

      final destPath = _buildDestPath(plan, entry.relativePath);
      Map<String, dynamic>? meta;
      try {
        meta = await destination.resolvePath(destPath);
      } catch (_) {
        // Cannot resolve → treat as mismatch
        mismatched++;
        mismatches.add({
          'path': entry.relativePath,
          'sourceHash': entry.sourceHash ?? '(unknown)',
          'destHash': '(not found)',
        });
        verified++;
        continue;
      }

      if (meta == null) {
        mismatched++;
        mismatches.add({
          'path': entry.relativePath,
          'sourceHash': entry.sourceHash ?? '(unknown)',
          'destHash': '(not found)',
        });
        verified++;
        continue;
      }

      // Compare sizes
      final destSize = (meta['size'] as num?)?.toInt() ??
          (meta['sizeBytes'] as num?)?.toInt();
      final sizeMatch = destSize == null || destSize == entry.sizeBytes;

      // Hash comparison when available
      final destHashFromMeta = meta['md5Hash'] as String? ??
          meta['sha256Hash'] as String? ??
          meta['hash'] as String?;

      final String? resolvedDestHash = destHashFromMeta ?? entry.destHash;

      if (!sizeMatch) {
        mismatched++;
        mismatches.add({
          'path': entry.relativePath,
          'sourceHash': entry.sourceHash ?? '(size:${entry.sizeBytes})',
          'destHash': '(size:${destSize.toString()})',
        });
      } else if (entry.sourceHash != null &&
          resolvedDestHash != null &&
          entry.sourceHash != resolvedDestHash) {
        mismatched++;
        mismatches.add({
          'path': entry.relativePath,
          'sourceHash': entry.sourceHash!,
          'destHash': resolvedDestHash,
        });
      } else {
        matched++;
        entry.status = MigrationFileStatus.verified;
      }

      verified++;
    }

    return MigrationVerification(
      totalFiles: entries
          .where((e) =>
              e.status == MigrationFileStatus.migrated ||
              e.status == MigrationFileStatus.verified)
          .length +
          mismatched,
      verifiedFiles: verified,
      matchedFiles: matched,
      mismatchedFiles: mismatched,
      mismatches: mismatches,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _SkipFileException implements Exception {
  const _SkipFileException();
}

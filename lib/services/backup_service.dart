// lib/services/backup_service.dart
//
// Backup Engine: scheduled, incremental, versioned backups of a local folder
// to a cloud provider path. Independent of the sync engine — one-way, snapshot
// based. Snapshots are immutable once completed.
//
// Key concepts:
//   BackupPlan    — configuration (source, destination, schedule, maxVersions)
//   BackupSnapshot — a point-in-time snapshot produced by one backup run
//   BackupFileEntry — one file's state within a snapshot
//
// Persistence:
//   Plans    → SharedPreferences key 'backup_plans'       (JSON list)
//   Snapshots → SharedPreferences key 'backup_snapshots_<planId>' (JSON list)
//
// Platform guard: all mutating operations are no-ops on web (kIsWeb).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum BackupFileStatus {
  added,
  modified,
  unchanged,
  deleted,
}

enum BackupSnapshotStatus {
  pending,
  running,
  completed,
  failed,
  verifying,
}

// ---------------------------------------------------------------------------
// BackupFileEntry
// ---------------------------------------------------------------------------

/// State of a single file within a backup snapshot.
class BackupFileEntry {
  final String relativePath;
  final int sizeBytes;
  final String md5Hash;
  final BackupFileStatus status;

  /// Remote path where this file was stored in the backup destination.
  final String backupPath;

  BackupFileEntry({
    required this.relativePath,
    required this.sizeBytes,
    required this.md5Hash,
    required this.status,
    required this.backupPath,
  });

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'sizeBytes': sizeBytes,
        'md5Hash': md5Hash,
        'status': status.name,
        'backupPath': backupPath,
      };

  factory BackupFileEntry.fromJson(Map<String, dynamic> json) => BackupFileEntry(
        relativePath: json['relativePath'] as String,
        sizeBytes: json['sizeBytes'] as int,
        md5Hash: json['md5Hash'] as String,
        status: BackupFileStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => BackupFileStatus.added,
        ),
        backupPath: json['backupPath'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is BackupFileEntry && relativePath == other.relativePath && md5Hash == other.md5Hash;

  @override
  int get hashCode => Object.hash(relativePath, md5Hash);
}

// ---------------------------------------------------------------------------
// BackupSnapshot
// ---------------------------------------------------------------------------

/// A point-in-time snapshot produced by one backup run.
class BackupSnapshot {
  final String id;
  final String planId;
  final DateTime timestamp;
  final int fileCount;
  final int totalBytes;
  BackupSnapshotStatus status;
  final List<BackupFileEntry> files;
  final int durationMs;
  final String? error;

  BackupSnapshot({
    required this.id,
    required this.planId,
    required this.timestamp,
    required this.fileCount,
    required this.totalBytes,
    required this.status,
    required this.files,
    this.durationMs = 0,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'planId': planId,
        'timestamp': timestamp.toIso8601String(),
        'fileCount': fileCount,
        'totalBytes': totalBytes,
        'status': status.name,
        'files': files.map((f) => f.toJson()).toList(),
        'durationMs': durationMs,
        if (error != null) 'error': error,
      };

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) => BackupSnapshot(
        id: json['id'] as String,
        planId: json['planId'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        fileCount: json['fileCount'] as int,
        totalBytes: json['totalBytes'] as int,
        status: BackupSnapshotStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => BackupSnapshotStatus.pending,
        ),
        files: (json['files'] as List)
            .cast<Map<String, dynamic>>()
            .map(BackupFileEntry.fromJson)
            .toList(),
        durationMs: json['durationMs'] as int? ?? 0,
        error: json['error'] as String?,
      );

  /// Return a copy with a modified status.
  BackupSnapshot copyWithStatus(BackupSnapshotStatus newStatus, {String? error}) =>
      BackupSnapshot(
        id: id,
        planId: planId,
        timestamp: timestamp,
        fileCount: fileCount,
        totalBytes: totalBytes,
        status: newStatus,
        files: files,
        durationMs: durationMs,
        error: error ?? this.error,
      );
}

// ---------------------------------------------------------------------------
// BackupPlan
// ---------------------------------------------------------------------------

/// Configuration for one backup plan.
class BackupPlan {
  final String id;
  final String name;
  final String sourcePath;
  final String destinationPath;
  final String provider;

  /// Cron expression (e.g. '0 2 * * *' = daily at 2 AM).
  final String schedule;

  /// Maximum number of snapshots to keep (oldest pruned beyond this).
  final int maxVersions;

  final bool encryptionEnabled;

  /// Passphrase used when encryptionEnabled == true.
  final String? encryptionKey;

  final DateTime? lastRun;
  final DateTime? nextRun;
  final bool enabled;

  /// Glob patterns of files/directories to exclude (e.g. ['*.tmp', '.git/**']).
  final List<String> excludePatterns;

  final DateTime createdAt;

  BackupPlan({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.destinationPath,
    required this.provider,
    required this.schedule,
    this.maxVersions = 10,
    this.encryptionEnabled = false,
    this.encryptionKey,
    this.lastRun,
    this.nextRun,
    this.enabled = true,
    this.excludePatterns = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sourcePath': sourcePath,
        'destinationPath': destinationPath,
        'provider': provider,
        'schedule': schedule,
        'maxVersions': maxVersions,
        'encryptionEnabled': encryptionEnabled,
        if (encryptionKey != null) 'encryptionKey': encryptionKey,
        if (lastRun != null) 'lastRun': lastRun!.toIso8601String(),
        if (nextRun != null) 'nextRun': nextRun!.toIso8601String(),
        'enabled': enabled,
        'excludePatterns': excludePatterns,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BackupPlan.fromJson(Map<String, dynamic> json) => BackupPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        sourcePath: json['sourcePath'] as String,
        destinationPath: json['destinationPath'] as String,
        provider: json['provider'] as String,
        schedule: json['schedule'] as String,
        maxVersions: json['maxVersions'] as int? ?? 10,
        encryptionEnabled: json['encryptionEnabled'] as bool? ?? false,
        encryptionKey: json['encryptionKey'] as String?,
        lastRun: json['lastRun'] != null ? DateTime.parse(json['lastRun'] as String) : null,
        nextRun: json['nextRun'] != null ? DateTime.parse(json['nextRun'] as String) : null,
        enabled: json['enabled'] as bool? ?? true,
        excludePatterns: (json['excludePatterns'] as List?)?.cast<String>() ?? [],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  BackupPlan copyWith({
    String? name,
    String? sourcePath,
    String? destinationPath,
    String? provider,
    String? schedule,
    int? maxVersions,
    bool? encryptionEnabled,
    String? encryptionKey,
    DateTime? lastRun,
    DateTime? nextRun,
    bool? enabled,
    List<String>? excludePatterns,
  }) =>
      BackupPlan(
        id: id,
        name: name ?? this.name,
        sourcePath: sourcePath ?? this.sourcePath,
        destinationPath: destinationPath ?? this.destinationPath,
        provider: provider ?? this.provider,
        schedule: schedule ?? this.schedule,
        maxVersions: maxVersions ?? this.maxVersions,
        encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
        encryptionKey: encryptionKey ?? this.encryptionKey,
        lastRun: lastRun ?? this.lastRun,
        nextRun: nextRun ?? this.nextRun,
        enabled: enabled ?? this.enabled,
        excludePatterns: excludePatterns ?? this.excludePatterns,
        createdAt: createdAt,
      );

  /// Validate plan configuration. Returns null if valid, error string otherwise.
  String? validate() {
    if (sourcePath.trim().isEmpty) return 'sourcePath must not be empty';
    if (destinationPath.trim().isEmpty) return 'destinationPath must not be empty';
    if (name.trim().isEmpty) return 'name must not be empty';
    if (maxVersions < 1) return 'maxVersions must be at least 1';
    if (schedule.trim().isEmpty) return 'schedule must not be empty';
    if (!_isValidCron(schedule)) return 'schedule is not a valid cron expression';
    if (encryptionEnabled && (encryptionKey == null || encryptionKey!.trim().isEmpty)) {
      return 'encryptionKey is required when encryptionEnabled is true';
    }
    return null;
  }

  /// Very basic cron validation: 5 space-separated fields.
  static bool _isValidCron(String cron) {
    final parts = cron.trim().split(RegExp(r'\s+'));
    return parts.length == 5;
  }
}

// ---------------------------------------------------------------------------
// Glob matching helper
// ---------------------------------------------------------------------------

/// Returns true if [relativePath] matches any of the [patterns] using simple
/// glob rules: * matches within a path segment, ** matches across segments,
/// ? matches a single non-separator character.
bool _matchesAnyGlob(String relativePath, List<String> patterns) {
  final normalised = relativePath.replaceAll('\\', '/');
  for (final pattern in patterns) {
    if (_globMatches(pattern, normalised)) return true;
  }
  return false;
}

bool _globMatches(String pattern, String path) {
  // Convert glob to regex
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
        // ** matches everything including /
        sb.write('.*');
        i += 2;
        // Skip optional trailing /
        if (i < glob.length && glob[i] == '/') i++;
        continue;
      } else {
        // * matches within a path segment (no /)
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
// MD5 helper
// ---------------------------------------------------------------------------

String _md5OfBytes(List<int> bytes) {
  return md5.convert(bytes).toString();
}

// ---------------------------------------------------------------------------
// BackupService
// ---------------------------------------------------------------------------

/// Provides scheduled, incremental, versioned backups.
///
/// Platform note: all methods return early / return empty values on web
/// because local filesystem access is not available in that environment.
class BackupService {
  static final _log = Log('BackupService');
  static const _uuid = Uuid();

  static const _plansKey = 'backup_plans';
  static String _snapshotsKey(String planId) => 'backup_snapshots_$planId';

  /// Tracks which plan IDs are actively running a backup.
  final Set<String> _runningPlanIds = {};

  bool get isRunning => _runningPlanIds.isNotEmpty;
  bool isRunningPlan(String planId) => _runningPlanIds.contains(planId);

  // ---------------------------------------------------------------------------
  // Plan CRUD
  // ---------------------------------------------------------------------------

  /// Load all backup plans from SharedPreferences.
  Future<List<BackupPlan>> getPlans() async {
    if (kIsWeb) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_plansKey);
      if (raw == null) return [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(BackupPlan.fromJson).toList();
    } catch (e) {
      _log.error('Failed to load backup plans', e);
      return [];
    }
  }

  /// Retrieve a single plan by ID.
  Future<BackupPlan?> getPlan(String id) async {
    final plans = await getPlans();
    try {
      return plans.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Create a new plan. Validates before saving. Returns the created plan.
  ///
  /// Throws [ArgumentError] if validation fails.
  Future<BackupPlan> createPlan({
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
    if (kIsWeb) throw UnsupportedError('Backup plans are not supported on web');

    final plan = BackupPlan(
      id: _uuid.v4(),
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
      createdAt: DateTime.now(),
    );

    final validationError = plan.validate();
    if (validationError != null) throw ArgumentError(validationError);

    final plans = await getPlans();
    plans.add(plan);
    await _savePlans(plans);
    _log.info('Created backup plan "${plan.name}" (${plan.id})');
    return plan;
  }

  /// Update an existing plan. Throws [StateError] if plan not found.
  Future<BackupPlan> updatePlan(BackupPlan updated) async {
    if (kIsWeb) throw UnsupportedError('Backup plans are not supported on web');

    final validationError = updated.validate();
    if (validationError != null) throw ArgumentError(validationError);

    final plans = await getPlans();
    final idx = plans.indexWhere((p) => p.id == updated.id);
    if (idx == -1) throw StateError('Plan ${updated.id} not found');
    plans[idx] = updated;
    await _savePlans(plans);
    _log.info('Updated backup plan "${updated.name}"');
    return updated;
  }

  /// Delete a plan and all its snapshots. Throws [StateError] if not found.
  Future<void> deletePlan(String planId) async {
    if (kIsWeb) return;

    final plans = await getPlans();
    plans.removeWhere((p) => p.id == planId);
    await _savePlans(plans);

    // Remove all snapshots for this plan
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snapshotsKey(planId));

    _log.info('Deleted backup plan $planId and all its snapshots');
  }

  Future<void> _savePlans(List<BackupPlan> plans) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_plansKey, jsonEncode(plans.map((p) => p.toJson()).toList()));
  }

  // ---------------------------------------------------------------------------
  // Snapshot CRUD
  // ---------------------------------------------------------------------------

  /// Load all snapshots for a plan, sorted newest-first.
  Future<List<BackupSnapshot>> getSnapshots(String planId) async {
    if (kIsWeb) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_snapshotsKey(planId));
      if (raw == null) return [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final snapshots = list.map(BackupSnapshot.fromJson).toList();
      snapshots.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return snapshots;
    } catch (e) {
      _log.error('Failed to load snapshots for plan $planId', e);
      return [];
    }
  }

  Future<BackupSnapshot?> _getSnapshot(String planId, String snapshotId) async {
    final snapshots = await getSnapshots(planId);
    try {
      return snapshots.firstWhere((s) => s.id == snapshotId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSnapshots(String planId, List<BackupSnapshot> snapshots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snapshotsKey(planId),
      jsonEncode(snapshots.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _upsertSnapshot(BackupSnapshot snapshot) async {
    final snapshots = await getSnapshots(snapshot.planId);
    final idx = snapshots.indexWhere((s) => s.id == snapshot.id);
    if (idx == -1) {
      snapshots.add(snapshot);
    } else {
      snapshots[idx] = snapshot;
    }
    await _saveSnapshots(snapshot.planId, snapshots);
  }

  /// Delete a snapshot record (does not remove remote files — caller's
  /// responsibility if needed, or use [deleteSnapshot] which does both).
  Future<void> _removeSnapshotRecord(String planId, String snapshotId) async {
    final snapshots = await getSnapshots(planId);
    snapshots.removeWhere((s) => s.id == snapshotId);
    await _saveSnapshots(planId, snapshots);
  }

  /// Delete a snapshot and its associated remote files (best-effort).
  ///
  /// [deleteRemoteFiles] is an optional callback to remove files from the
  /// provider. Pass null to skip remote deletion (e.g. when testing or the
  /// provider client is unavailable).
  Future<void> deleteSnapshot(
    String snapshotId, {
    Future<void> Function(List<String> paths)? deleteRemoteFiles,
  }) async {
    if (kIsWeb) return;

    // Find the plan that owns this snapshot
    final plans = await getPlans();
    for (final plan in plans) {
      final snapshot = await _getSnapshot(plan.id, snapshotId);
      if (snapshot == null) continue;

      // Best-effort remote file deletion
      if (deleteRemoteFiles != null) {
        final remotePaths = snapshot.files
            .where((f) => f.status != BackupFileStatus.deleted)
            .map((f) => f.backupPath)
            .toList();
        try {
          await deleteRemoteFiles(remotePaths);
        } catch (e) {
          _log.warn('Failed to delete remote files for snapshot $snapshotId', e);
        }
      }

      await _removeSnapshotRecord(plan.id, snapshotId);
      _log.info('Deleted snapshot $snapshotId from plan ${plan.id}');
      return;
    }
    _log.warn('deleteSnapshot: snapshot $snapshotId not found in any plan');
  }

  /// Prune snapshots for a plan, keeping only the [BackupPlan.maxVersions]
  /// most recent completed ones. Older completed snapshots are removed.
  ///
  /// [deleteRemoteFiles] is optional (see [deleteSnapshot]).
  Future<int> pruneSnapshots(
    String planId, {
    Future<void> Function(List<String> paths)? deleteRemoteFiles,
  }) async {
    if (kIsWeb) return 0;

    final plan = await getPlan(planId);
    if (plan == null) return 0;

    final snapshots = await getSnapshots(planId);

    // Only prune completed snapshots; keep failed/pending/running as-is.
    final completed = snapshots
        .where((s) => s.status == BackupSnapshotStatus.completed)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // newest first

    if (completed.length <= plan.maxVersions) return 0;

    final toDelete = completed.sublist(plan.maxVersions);
    int pruned = 0;

    for (final old in toDelete) {
      if (deleteRemoteFiles != null) {
        final paths = old.files
            .where((f) => f.status != BackupFileStatus.deleted)
            .map((f) => f.backupPath)
            .toList();
        try {
          await deleteRemoteFiles(paths);
        } catch (e) {
          _log.warn('pruneSnapshots: failed to delete remote files for ${old.id}', e);
        }
      }
      await _removeSnapshotRecord(planId, old.id);
      pruned++;
    }

    if (pruned > 0) {
      _log.info('Pruned $pruned old snapshot(s) from plan "$planId"');
    }
    return pruned;
  }

  // ---------------------------------------------------------------------------
  // Running a backup
  // ---------------------------------------------------------------------------

  /// Run a backup for [planId].
  ///
  /// [uploadFile] is a callback that uploads bytes to a remote path and returns
  /// the remote path where the file was stored. This keeps the service
  /// provider-agnostic.
  ///
  /// [encryptBytes] is an optional callback to encrypt file bytes before
  /// upload (used when [BackupPlan.encryptionEnabled] is true).
  ///
  /// Returns the resulting [BackupSnapshot].
  Future<BackupSnapshot> runBackup(
    String planId, {
    required Future<String> Function(String relativePath, List<int> bytes) uploadFile,
    List<int> Function(List<int> bytes, String key)? encryptBytes,
  }) async {
    if (kIsWeb) {
      return BackupSnapshot(
        id: _uuid.v4(),
        planId: planId,
        timestamp: DateTime.now(),
        fileCount: 0,
        totalBytes: 0,
        status: BackupSnapshotStatus.completed,
        files: [],
      );
    }

    if (_runningPlanIds.contains(planId)) {
      throw StateError('Backup for plan $planId is already running');
    }

    // Add synchronously BEFORE the first await so a concurrent caller
    // that checks _runningPlanIds before any suspension will see the guard.
    _runningPlanIds.add(planId);

    try {
      final plan = await getPlan(planId);
      if (plan == null) {
        throw StateError('Plan $planId not found');
      }

      return await _runBackupInternal(planId, plan, uploadFile, encryptBytes);
    } finally {
      _runningPlanIds.remove(planId);
    }
  }

  Future<BackupSnapshot> _runBackupInternal(
    String planId,
    BackupPlan plan,
    Future<String> Function(String relativePath, List<int> bytes) uploadFile,
    List<int> Function(List<int> bytes, String key)? encryptBytes,
  ) async {
    final startTime = DateTime.now();

    // Create a pending snapshot record
    final snapshotId = _uuid.v4();
    var snapshot = BackupSnapshot(
      id: snapshotId,
      planId: planId,
      timestamp: startTime,
      fileCount: 0,
      totalBytes: 0,
      status: BackupSnapshotStatus.running,
      files: [],
    );
    await _upsertSnapshot(snapshot);

    try {
      _log.info('Starting backup for plan "${plan.name}" (snapshot $snapshotId)');

      // Load previous snapshot to enable incremental detection
      final previousSnapshots = await getSnapshots(planId);
      final previousCompleted = previousSnapshots
          .where((s) =>
              s.status == BackupSnapshotStatus.completed && s.id != snapshotId)
          .toList();
      previousCompleted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final previous = previousCompleted.isNotEmpty ? previousCompleted.first : null;

      // Build lookup from previous snapshot: relativePath → BackupFileEntry
      final previousFiles = <String, BackupFileEntry>{};
      if (previous != null) {
        for (final f in previous.files) {
          previousFiles[f.relativePath] = f;
        }
      }

      // Scan source directory
      final sourceDir = Directory(plan.sourcePath);
      if (!await sourceDir.exists()) {
        throw StateError('Source directory does not exist: ${plan.sourcePath}');
      }

      final scannedFiles = await _scanDirectory(sourceDir, plan.sourcePath, plan.excludePatterns);

      // Compare against previous snapshot → build entries
      final entries = <BackupFileEntry>[];
      int totalBytes = 0;

      for (final localFile in scannedFiles) {
        final relativePath = localFile.relativePath;
        final localBytes = await File(localFile.absolutePath).readAsBytes();
        final hash = _md5OfBytes(localBytes);
        final sizeBytes = localBytes.length;

        final prev = previousFiles[relativePath];
        final isNew = prev == null;
        final isUnchanged = prev != null && prev.md5Hash == hash;

        if (isUnchanged) {
          // Carry forward the previous backup path — no upload needed.
          entries.add(BackupFileEntry(
            relativePath: relativePath,
            sizeBytes: sizeBytes,
            md5Hash: hash,
            status: BackupFileStatus.unchanged,
            backupPath: prev.backupPath,
          ));
          totalBytes += sizeBytes;
          continue;
        }

        // Need to upload (new or modified)
        final bytesToUpload = _applyEncryption(localBytes, plan, encryptBytes);
        final remotePath = await uploadFile(relativePath, bytesToUpload);

        entries.add(BackupFileEntry(
          relativePath: relativePath,
          sizeBytes: sizeBytes,
          md5Hash: hash,
          status: isNew ? BackupFileStatus.added : BackupFileStatus.modified,
          backupPath: remotePath,
        ));
        totalBytes += sizeBytes;
      }

      // Detect deleted files (in previous but not in current scan)
      final scannedRelPaths = scannedFiles.map((f) => f.relativePath).toSet();
      for (final prevEntry in previousFiles.values) {
        if (!scannedRelPaths.contains(prevEntry.relativePath)) {
          entries.add(BackupFileEntry(
            relativePath: prevEntry.relativePath,
            sizeBytes: 0,
            md5Hash: prevEntry.md5Hash,
            status: BackupFileStatus.deleted,
            backupPath: prevEntry.backupPath,
          ));
        }
      }

      final durationMs = DateTime.now().difference(startTime).inMilliseconds;
      final nonDeletedEntries =
          entries.where((e) => e.status != BackupFileStatus.deleted).toList();

      snapshot = BackupSnapshot(
        id: snapshotId,
        planId: planId,
        timestamp: startTime,
        fileCount: nonDeletedEntries.length,
        totalBytes: totalBytes,
        status: BackupSnapshotStatus.completed,
        files: entries,
        durationMs: durationMs,
      );
      await _upsertSnapshot(snapshot);

      // Update plan's lastRun
      final updatedPlan = plan.copyWith(lastRun: startTime);
      final plans = await getPlans();
      final idx = plans.indexWhere((p) => p.id == planId);
      if (idx != -1) {
        plans[idx] = updatedPlan;
        await _savePlans(plans);
      }

      // Auto-prune
      await pruneSnapshots(planId);

      _log.info(
        'Backup completed for "${plan.name}": '
        '${entries.length} files, $totalBytes bytes, ${durationMs}ms',
      );
      return snapshot;
    } catch (e, st) {
      _log.error('Backup failed for plan "${plan.name}"', e, st);
      final failed = snapshot.copyWithStatus(BackupSnapshotStatus.failed, error: e.toString());
      await _upsertSnapshot(failed);
      return failed;
    }
  }

  // ---------------------------------------------------------------------------
  // Verification
  // ---------------------------------------------------------------------------

  /// Re-hash local source files and compare against snapshot records.
  ///
  /// For each file in the snapshot that is not marked deleted:
  ///   - If the local file exists and hash matches → pass
  ///   - Otherwise → fail
  ///
  /// Returns a map of relativePath → verification result ('ok' / 'mismatch' / 'missing').
  Future<Map<String, String>> verifySnapshot(String snapshotId) async {
    if (kIsWeb) return {};

    final plans = await getPlans();
    for (final plan in plans) {
      final snapshot = await _getSnapshot(plan.id, snapshotId);
      if (snapshot == null) continue;

      _log.info('Verifying snapshot $snapshotId for plan "${plan.name}"');

      // Mark as verifying
      await _upsertSnapshot(snapshot.copyWithStatus(BackupSnapshotStatus.verifying));

      final result = <String, String>{};

      for (final entry in snapshot.files) {
        if (entry.status == BackupFileStatus.deleted) continue;

        final localPath = '${plan.sourcePath}/${entry.relativePath}';
        final file = File(localPath);

        if (!await file.exists()) {
          result[entry.relativePath] = 'missing';
          continue;
        }

        final bytes = await file.readAsBytes();
        final hash = _md5OfBytes(bytes);
        result[entry.relativePath] = hash == entry.md5Hash ? 'ok' : 'mismatch';
      }

      // Restore completed status
      await _upsertSnapshot(snapshot.copyWithStatus(BackupSnapshotStatus.completed));

      _log.info(
        'Verification done for $snapshotId: '
        '${result.values.where((v) => v == 'ok').length} ok, '
        '${result.values.where((v) => v != 'ok').length} failures',
      );
      return result;
    }

    _log.warn('verifySnapshot: snapshot $snapshotId not found in any plan');
    return {};
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Returns the list of files that would be restored from [snapshotId].
  /// Excludes files marked as deleted.
  Future<List<BackupFileEntry>> getRestorePreview(String snapshotId) async {
    if (kIsWeb) return [];

    final plans = await getPlans();
    for (final plan in plans) {
      final snapshot = await _getSnapshot(plan.id, snapshotId);
      if (snapshot == null) continue;

      return snapshot.files
          .where((f) => f.status != BackupFileStatus.deleted)
          .toList();
    }
    return [];
  }

  /// Download all files from [snapshotId] into [targetPath].
  ///
  /// [downloadFile] is a callback that downloads bytes from a remote path.
  ///
  /// [decryptBytes] is an optional callback to decrypt file bytes after
  /// download when [BackupPlan.encryptionEnabled] is true.
  ///
  /// Returns the number of files restored.
  Future<int> restoreSnapshot(
    String snapshotId,
    String targetPath, {
    required Future<List<int>> Function(String backupPath) downloadFile,
    List<int> Function(List<int> bytes, String key)? decryptBytes,
  }) async {
    if (kIsWeb) return 0;

    final plans = await getPlans();
    for (final plan in plans) {
      final snapshot = await _getSnapshot(plan.id, snapshotId);
      if (snapshot == null) continue;

      _log.info('Restoring snapshot $snapshotId to $targetPath');

      int restored = 0;
      for (final entry in snapshot.files) {
        if (entry.status == BackupFileStatus.deleted) continue;

        try {
          var bytes = await downloadFile(entry.backupPath);
          if (plan.encryptionEnabled && decryptBytes != null && plan.encryptionKey != null) {
            bytes = decryptBytes(bytes, plan.encryptionKey!);
          }

          final destPath = '$targetPath/${entry.relativePath}';
          final destFile = File(destPath);
          await destFile.parent.create(recursive: true);
          await destFile.writeAsBytes(bytes);
          restored++;
        } catch (e) {
          _log.error('Failed to restore ${entry.relativePath}', e);
        }
      }

      _log.info('Restore complete: $restored files written to $targetPath');
      return restored;
    }

    _log.warn('restoreSnapshot: snapshot $snapshotId not found in any plan');
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Apply encryption to [bytes] if the plan requires it.
  List<int> _applyEncryption(
    List<int> bytes,
    BackupPlan plan,
    List<int> Function(List<int>, String)? encryptBytes,
  ) {
    if (!plan.encryptionEnabled) return bytes;
    if (encryptBytes == null) return bytes;
    if (plan.encryptionKey == null || plan.encryptionKey!.isEmpty) return bytes;
    return encryptBytes(bytes, plan.encryptionKey!);
  }
}

// ---------------------------------------------------------------------------
// Directory scanning helpers (non-web)
// ---------------------------------------------------------------------------

/// Holds information about a discovered local file.
class _ScannedFile {
  final String relativePath;
  final String absolutePath;
  _ScannedFile(this.relativePath, this.absolutePath);
}

/// Recursively list all files under [rootDir], applying [excludePatterns].
Future<List<_ScannedFile>> _scanDirectory(
  Directory rootDir,
  String basePath,
  List<String> excludePatterns,
) async {
  final results = <_ScannedFile>[];

  await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final absolutePath = entity.path;
    // Build relative path (always forward-slashes)
    var relativePath = absolutePath.substring(basePath.length);
    if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
      relativePath = relativePath.substring(1);
    }
    relativePath = relativePath.replaceAll('\\', '/');

    if (_matchesAnyGlob(relativePath, excludePatterns)) continue;

    results.add(_ScannedFile(relativePath, absolutePath));
  }

  // Sort for deterministic ordering
  results.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return results;
}

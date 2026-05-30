// lib/services/sync_database.dart
//
// SQLite database for sync metadata using drift.
// Stores sync pairs (local ↔ remote mappings) and per-file sync state
// (hash, modification time, sync status) for change detection and
// conflict resolution.
//
// Uses drift's "manager" API with typed tables for compile-time safety.

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'sync_database_connection.dart';

part 'sync_database.g.dart';

// --- Enums stored as text ---

/// How to resolve conflicts when both sides changed.
enum ConflictPolicy { newestWins, localWins, remoteWins, keepBoth, manual }

/// Current sync status of a file entry.
enum SyncStatus { synced, localModified, remoteModified, conflict, pendingUpload, pendingDownload, error, placeholder }

/// Direction of sync.
enum SyncDirection { twoWay, uploadOnly, downloadOnly }

// --- Tables ---

/// A sync pair defines a mapping between a local folder and a remote folder.
class SyncPairs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  TextColumn get localPath => text()();
  TextColumn get remotePath => text()();
  TextColumn get provider => text()(); // CloudProvider.name
  TextColumn get conflictPolicy => text().withDefault(const Constant('newestWins'))();
  TextColumn get direction => text().withDefault(const Constant('twoWay'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Comma-separated glob patterns to include (empty = include all).
  /// Example: "*.dart,*.yaml,lib/**"
  TextColumn get includePatterns => text().withDefault(const Constant(''))();

  /// Comma-separated glob patterns to exclude.
  /// Example: ".git/**,*.tmp,node_modules/**"
  TextColumn get excludePatterns => text().withDefault(const Constant(''))();

  /// When true, new remote files are created as lightweight placeholders
  /// instead of being fully downloaded. Users can hydrate on demand.
  BoolColumn get usePlaceholders => boolean().withDefault(const Constant(false))();
}

/// Per-file sync state within a sync pair.
class SyncEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pairId => integer().references(SyncPairs, #id)();
  TextColumn get relativePath => text()(); // relative to sync pair root
  TextColumn get localHash => text().nullable()(); // MD5 or SHA-256
  TextColumn get remoteHash => text().nullable()();
  DateTimeColumn get localModified => dateTime().nullable()();
  DateTimeColumn get remoteModified => dateTime().nullable()();
  IntColumn get localSize => integer().withDefault(const Constant(0))();
  IntColumn get remoteSize => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('synced'))();
  TextColumn get error => text().nullable()();
  BoolColumn get isFolder => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [{pairId, relativePath}];
}

/// Queued operations for offline mode — replayed on reconnect.
class OfflineQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pairId => integer().references(SyncPairs, #id)();
  TextColumn get operation => text()(); // upload, download, delete, rename, move
  TextColumn get path => text()();
  TextColumn get targetPath => text().nullable()(); // for move/rename
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  TextColumn get error => text().nullable()();
}

@DriftDatabase(tables: [SyncPairs, SyncEntries, OfflineQueue])
class SyncDatabase extends _$SyncDatabase {
  SyncDatabase() : super(openSyncDatabase());

  /// For testing: inject a custom executor.
  SyncDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(syncPairs, syncPairs.includePatterns);
        await m.addColumn(syncPairs, syncPairs.excludePatterns);
      }
      if (from < 3) {
        await m.addColumn(syncPairs, syncPairs.usePlaceholders);
      }
    },
  );

  // --- SyncPair CRUD ---

  Future<List<SyncPair>> getAllPairs() => select(syncPairs).get();

  Future<List<SyncPair>> getEnabledPairs() =>
      (select(syncPairs)..where((t) => t.enabled.equals(true))).get();

  Future<SyncPair> getPair(int id) =>
      (select(syncPairs)..where((t) => t.id.equals(id))).getSingle();

  Future<int> insertPair(SyncPairsCompanion pair) =>
      into(syncPairs).insert(pair);

  Future<bool> updatePair(SyncPairsCompanion pair) =>
      update(syncPairs).replace(pair);

  Future<int> deletePair(int id) =>
      (delete(syncPairs)..where((t) => t.id.equals(id))).go();

  // --- SyncEntry CRUD ---

  Future<List<SyncEntry>> getEntriesForPair(int pairId) =>
      (select(syncEntries)..where((t) => t.pairId.equals(pairId))).get();

  Future<SyncEntry?> getEntry(int pairId, String relativePath) =>
      (select(syncEntries)
            ..where((t) => t.pairId.equals(pairId) & t.relativePath.equals(relativePath)))
          .getSingleOrNull();

  Future<int> upsertEntry(SyncEntriesCompanion entry) =>
      into(syncEntries).insertOnConflictUpdate(entry);

  Future<int> deleteEntriesForPair(int pairId) =>
      (delete(syncEntries)..where((t) => t.pairId.equals(pairId))).go();

  Future<List<SyncEntry>> getConflicts(int pairId) =>
      (select(syncEntries)
            ..where((t) => t.pairId.equals(pairId) & t.status.equals('conflict')))
          .get();

  Future<List<SyncEntry>> getPendingEntries(int pairId) =>
      (select(syncEntries)
            ..where((t) =>
                t.pairId.equals(pairId) &
                (t.status.equals('pendingUpload') |
                    t.status.equals('pendingDownload') |
                    t.status.equals('localModified') |
                    t.status.equals('remoteModified'))))
          .get();

  // --- Offline Queue ---

  Future<int> enqueueOffline(OfflineQueueCompanion entry) =>
      into(offlineQueue).insert(entry);

  Future<List<OfflineQueueEntry>> getPendingOfflineOps(int pairId) =>
      (select(offlineQueue)
            ..where((t) => t.pairId.equals(pairId) & t.completed.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<void> markOfflineCompleted(int id) =>
      (update(offlineQueue)..where((t) => t.id.equals(id)))
          .write(const OfflineQueueCompanion(completed: Value(true)));

  Future<int> clearCompletedOffline() =>
      (delete(offlineQueue)..where((t) => t.completed.equals(true))).go();
}

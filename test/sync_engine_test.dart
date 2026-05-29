// test/sync_engine_test.dart
//
// Tests for the sync engine: change detection, conflict resolution,
// database operations, and sync pair management.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';

void main() {
  late SyncDatabase db;

  setUp(() {
    // In-memory database for testing
    db = SyncDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncDatabase CRUD', () {
    test('insert and retrieve sync pair', () async {
      final id = await db.insertPair(SyncPairsCompanion.insert(
        name: 'Test Pair',
        localPath: '/home/user/docs',
        remotePath: '/docs',
        provider: 'filen',
      ));

      expect(id, greaterThan(0));

      final pairs = await db.getAllPairs();
      expect(pairs.length, equals(1));
      expect(pairs.first.name, equals('Test Pair'));
      expect(pairs.first.localPath, equals('/home/user/docs'));
      expect(pairs.first.remotePath, equals('/docs'));
      expect(pairs.first.provider, equals('filen'));
      expect(pairs.first.enabled, isTrue);
      expect(pairs.first.conflictPolicy, equals('newestWins'));
      expect(pairs.first.direction, equals('twoWay'));
    });

    test('getEnabledPairs filters disabled pairs', () async {
      await db.insertPair(SyncPairsCompanion.insert(
        name: 'Enabled',
        localPath: '/a',
        remotePath: '/a',
        provider: 'filen',
      ));
      await db.insertPair(SyncPairsCompanion.insert(
        name: 'Disabled',
        localPath: '/b',
        remotePath: '/b',
        provider: 'filen',
        enabled: const Value(false),
      ));

      final enabled = await db.getEnabledPairs();
      expect(enabled.length, equals(1));
      expect(enabled.first.name, equals('Enabled'));
    });

    test('deletePair removes pair and returns count', () async {
      final id = await db.insertPair(SyncPairsCompanion.insert(
        name: 'Delete Me',
        localPath: '/x',
        remotePath: '/x',
        provider: 'sftp',
      ));

      final deleted = await db.deletePair(id);
      expect(deleted, equals(1));

      final pairs = await db.getAllPairs();
      expect(pairs, isEmpty);
    });
  });

  group('SyncEntry operations', () {
    late int pairId;

    setUp(() async {
      pairId = await db.insertPair(SyncPairsCompanion.insert(
        name: 'Test',
        localPath: '/local',
        remotePath: '/remote',
        provider: 'sftp',
      ));
    });

    test('upsert and retrieve entry', () async {
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'docs/report.pdf',
        status: const Value('synced'),
        localSize: const Value(1024),
        remoteSize: const Value(1024),
      ));

      final entries = await db.getEntriesForPair(pairId);
      expect(entries.length, equals(1));
      expect(entries.first.relativePath, equals('docs/report.pdf'));
      expect(entries.first.status, equals('synced'));
      expect(entries.first.localSize, equals(1024));
    });

    test('getEntry returns specific entry', () async {
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'a.txt',
      ));
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'b.txt',
      ));

      final entry = await db.getEntry(pairId, 'a.txt');
      expect(entry, isNotNull);
      expect(entry!.relativePath, equals('a.txt'));
    });

    test('getEntry returns null for non-existent path', () async {
      final entry = await db.getEntry(pairId, 'nonexistent.txt');
      expect(entry, isNull);
    });

    test('getConflicts returns only conflict entries', () async {
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'ok.txt',
        status: const Value('synced'),
      ));
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'conflict.txt',
        status: const Value('conflict'),
      ));

      final conflicts = await db.getConflicts(pairId);
      expect(conflicts.length, equals(1));
      expect(conflicts.first.relativePath, equals('conflict.txt'));
    });

    test('getPendingEntries returns modified/pending entries', () async {
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'synced.txt',
        status: const Value('synced'),
      ));
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'modified.txt',
        status: const Value('localModified'),
      ));
      await db.upsertEntry(SyncEntriesCompanion.insert(
        pairId: pairId,
        relativePath: 'pending.txt',
        status: const Value('pendingUpload'),
      ));

      final pending = await db.getPendingEntries(pairId);
      expect(pending.length, equals(2));
    });

    test('deleteEntriesForPair removes all entries', () async {
      await db.upsertEntry(SyncEntriesCompanion.insert(pairId: pairId, relativePath: 'a.txt'));
      await db.upsertEntry(SyncEntriesCompanion.insert(pairId: pairId, relativePath: 'b.txt'));

      final count = await db.deleteEntriesForPair(pairId);
      expect(count, equals(2));

      final remaining = await db.getEntriesForPair(pairId);
      expect(remaining, isEmpty);
    });
  });

  group('OfflineQueue operations', () {
    late int pairId;

    setUp(() async {
      pairId = await db.insertPair(SyncPairsCompanion.insert(
        name: 'Queue Test',
        localPath: '/local',
        remotePath: '/remote',
        provider: 'sftp',
      ));
    });

    test('enqueue and retrieve pending operations', () async {
      await db.enqueueOffline(OfflineQueueCompanion.insert(
        pairId: pairId,
        operation: 'upload',
        path: '/local/file.txt',
      ));
      await db.enqueueOffline(OfflineQueueCompanion.insert(
        pairId: pairId,
        operation: 'delete',
        path: '/remote/old.txt',
      ));

      final pending = await db.getPendingOfflineOps(pairId);
      expect(pending.length, equals(2));
      expect(pending.first.operation, equals('upload'));
    });

    test('markOfflineCompleted and clearCompleted', () async {
      final id = await db.enqueueOffline(OfflineQueueCompanion.insert(
        pairId: pairId,
        operation: 'upload',
        path: '/file.txt',
      ));

      await db.markOfflineCompleted(id);

      final pending = await db.getPendingOfflineOps(pairId);
      expect(pending, isEmpty);

      final cleared = await db.clearCompletedOffline();
      expect(cleared, equals(1));
    });
  });

  group('SyncEngine action computation', () {
    test('SyncResult addition works', () {
      const a = SyncResult(uploaded: 3, downloaded: 2, errors: 1);
      const b = SyncResult(uploaded: 1, conflicts: 2);
      final c = a + b;
      expect(c.uploaded, equals(4));
      expect(c.downloaded, equals(2));
      expect(c.conflicts, equals(2));
      expect(c.errors, equals(1));
    });

    test('SyncResult hasChanges', () {
      const empty = SyncResult();
      expect(empty.hasChanges, isFalse);

      const withUpload = SyncResult(uploaded: 1);
      expect(withUpload.hasChanges, isTrue);
    });

    test('ConflictPolicy enum has all expected values', () {
      expect(ConflictPolicy.values.length, equals(5));
      expect(ConflictPolicy.values, contains(ConflictPolicy.newestWins));
      expect(ConflictPolicy.values, contains(ConflictPolicy.localWins));
      expect(ConflictPolicy.values, contains(ConflictPolicy.remoteWins));
      expect(ConflictPolicy.values, contains(ConflictPolicy.keepBoth));
      expect(ConflictPolicy.values, contains(ConflictPolicy.manual));
    });

    test('SyncStatus enum has all expected values', () {
      expect(SyncStatus.values.length, equals(7));
    });

    test('SyncDirection enum has all expected values', () {
      expect(SyncDirection.values.length, equals(3));
    });

    test('SyncAction toString is readable', () {
      final action = SyncAction(type: SyncActionType.upload, relativePath: 'docs/file.txt');
      expect(action.toString(), contains('upload'));
      expect(action.toString(), contains('docs/file.txt'));
    });

    test('SyncAction folder flag', () {
      final action = SyncAction(type: SyncActionType.createRemoteFolder, relativePath: 'photos', isFolder: true);
      expect(action.isFolder, isTrue);
      expect(action.toString(), contains('[dir]'));
    });
  });
}

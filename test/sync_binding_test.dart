import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/services/sync_offline_service.dart';
import 'package:crisp_cloud/services/sync_source_binding.dart';

import 'support/sync_test_binding.dart';
import 'support/workflow_fake_client.dart';

class _AccountClient extends WorkflowFakeClient
    implements StorageNamespaceIdentity {
  String account = 'account-a';
  String? bucket;
  String endpoint = 'memory://one';
  int listings = 0;
  @override
  String? get userId => account;
  @override
  String? get bucketId => bucket;
  @override
  String get storageNamespace => endpoint;
  @override
  Future<Map<String, dynamic>> listPath(String path) {
    listings++;
    return super.listPath(path);
  }
}

void main() {
  late Directory local;
  late SyncDatabase db;
  late SyncPair pair;
  late _AccountClient cloud;
  late SyncOfflineService offline;
  setUp(() async {
    local = await Directory.systemTemp.createTemp('sync-binding-');
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    cloud = _AccountClient()..directories.add('/docs');
    pair = await db.getPair(
      await db.insertPair(
        SyncPairsCompanion.insert(
          name: 'Bound sources',
          localPath: local.path,
          remotePath: '/docs',
          provider: 'sftp',
        ),
      ),
    );
    pair = await bindTestPair(db, pair, cloud);
    offline = SyncOfflineService(db);
    await File(p.join(local.path, 'new.txt')).writeAsString('local');
  });
  tearDown(() async {
    await db.close();
    await local.delete(recursive: true);
  });

  test(
    'legacy pairs require explicit binding before any storage listing',
    () async {
      await (db.update(db.syncPairs)..where((t) => t.id.equals(pair.id))).write(
        const SyncPairsCompanion(sourceBinding: Value(null)),
      );
      final legacy = await db.getPair(pair.id);
      await expectLater(
        SyncEngine(db).syncPair(legacy, cloud),
        throwsStateError,
      );
      expect(cloud.listings, 0);
      expect(cloud.writes, isEmpty);
    },
  );

  for (final changed in ['account', 'bucket', 'endpoint']) {
    test(
      'saved pair rejects a changed $changed on the same provider',
      () async {
        switch (changed) {
          case 'account':
            cloud.account = 'account-b';
          case 'bucket':
            cloud.bucket = 'other-bucket';
          case 'endpoint':
            cloud.endpoint = 'memory://other';
        }
        await expectLater(
          SyncEngine(db).planPair(pair, cloud),
          throwsStateError,
        );
        expect(cloud.listings, 0);
        expect(cloud.writes, isEmpty);
      },
    );
  }

  test('restored database paths cannot target another installation', () async {
    final binding = jsonDecode(pair.sourceBinding!) as Map<String, dynamic>;
    (binding['local'] as Map<String, dynamic>)['accountKey'] =
        'installation:other';
    await (db.update(db.syncPairs)..where((t) => t.id.equals(pair.id))).write(
      SyncPairsCompanion(sourceBinding: Value(jsonEncode(binding))),
    );
    final restored = await db.getPair(pair.id);
    await expectLater(
      SyncEngine(db).planPair(restored, cloud),
      throwsStateError,
    );
    expect(cloud.listings, 0);
  });

  test(
    'rebind invalidates an already reviewed plan and clears baseline',
    () async {
      final engine = SyncEngine(db);
      final plan = await engine.planPair(pair, cloud);
      await db.upsertEntry(
        SyncEntriesCompanion.insert(pairId: pair.id, relativePath: 'old.txt'),
      );
      final rebound = await bindTestPair(db, pair, cloud);
      expect(rebound.sourceBinding, isNot(pair.sourceBinding));
      expect(await db.getEntriesForPair(pair.id), isEmpty);
      final result = await engine.executePlan(plan);
      expect(result.errors, 1);
      expect(cloud.writes, isEmpty);
    },
  );

  test(
    'offline operations retain binding and replay into the captured root',
    () async {
      await offline.enqueue(
        pairId: pair.id,
        operation: 'upload',
        path: 'new.txt',
      );
      final op = (await db.getPendingOfflineOps(pair.id)).single;
      expect(op.sourceBinding, pair.sourceBinding);
      cloud.account = 'account-b';
      await expectLater(offline.execute(op, pair, cloud), throwsStateError);
      expect(cloud.writes, isEmpty);
      cloud.account = 'account-a';
      final result = await offline.execute(op, pair, cloud);
      expect(result.uploaded, 1);
      expect(String.fromCharCodes(cloud.files['/docs/new.txt']!), 'local');
      expect(cloud.files.containsKey('/new.txt'), isFalse);
    },
  );

  test(
    'rebind to the same account never silently adopts old queued work',
    () async {
      await offline.enqueue(
        pairId: pair.id,
        operation: 'upload',
        path: 'new.txt',
      );
      final old = (await db.getPendingOfflineOps(pair.id)).single;
      pair = await bindTestPair(db, pair, cloud);
      await expectLater(offline.execute(old, pair, cloud), throwsStateError);
      final retained = (await db.getPendingOfflineOps(pair.id)).single;
      expect(retained.completed, isFalse);
      expect(retained.error, contains('rebound'));
      expect(cloud.writes, isEmpty);
    },
  );

  test('legacy queued operations stay blocked even on a bound pair', () async {
    await db.enqueueOffline(
      OfflineQueueCompanion.insert(
        pairId: pair.id,
        operation: 'upload',
        path: 'new.txt',
      ),
    );
    final op = (await db.getPendingOfflineOps(pair.id)).single;
    await expectLater(offline.execute(op, pair, cloud), throwsStateError);
    expect(cloud.writes, isEmpty);
  });

  test('offline replay rejects a destination edited after enqueue', () async {
    await offline.enqueue(
      pairId: pair.id,
      operation: 'upload',
      path: 'new.txt',
    );
    final op = (await db.getPendingOfflineOps(pair.id)).single;
    cloud.put(
      '/docs/new.txt',
      'later'.codeUnits,
      date: op.createdAt.add(const Duration(seconds: 2)),
    );
    await expectLater(offline.execute(op, pair, cloud), throwsStateError);
    expect(String.fromCharCodes(cloud.files['/docs/new.txt']!), 'later');
  });

  test(
    'queue rejects traversal and absolute paths before persistence',
    () async {
      for (final path in [
        '../escape',
        '/absolute',
        r'..\escape',
        'a/../b',
        'C:/root',
      ]) {
        await expectLater(
          offline.enqueue(pairId: pair.id, operation: 'upload', path: path),
          throwsFormatException,
        );
      }
      expect(await db.getPendingOfflineOps(pair.id), isEmpty);
    },
  );

  test(
    'version 3 migration preserves paths and requires review of legacy jobs',
    () async {
      final path = p.join(local.path, 'legacy.sqlite');
      await db.close();
      db = SyncDatabase.forTesting(NativeDatabase(File(path)));
      final old = db;
      final id = await old.insertPair(
        SyncPairsCompanion.insert(
          name: 'Legacy',
          localPath: '/old/local',
          remotePath: '/old/remote',
          provider: 'sftp',
        ),
      );
      await old.enqueueOffline(
        OfflineQueueCompanion.insert(
          pairId: id,
          operation: 'upload',
          path: 'file.txt',
        ),
      );
      await old.close();
      db = SyncDatabase.forTesting(
        NativeDatabase(
          File(path),
          setup: (raw) {
            raw.execute('ALTER TABLE sync_pairs DROP COLUMN source_binding');
            raw.execute('ALTER TABLE offline_queue DROP COLUMN source_binding');
            raw.execute('PRAGMA user_version = 3');
          },
        ),
      );
      final migrated = db;
      {
        final saved = await migrated.getPair(id);
        expect(saved.localPath, '/old/local');
        expect(saved.remotePath, '/old/remote');
        expect(saved.sourceBinding, isNull);
        expect(SyncSourceBinding.decode(saved.sourceBinding), isNull);
        expect(
          (await migrated.getPendingOfflineOps(id)).single.sourceBinding,
          isNull,
        );
        expect(migrated.schemaVersion, 4);
      }
    },
  );
}

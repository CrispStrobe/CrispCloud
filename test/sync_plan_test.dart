import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';

import 'support/workflow_fake_client.dart';

void main() {
  late Directory local;
  late SyncDatabase db;
  late SyncPair pair;
  late WorkflowFakeClient cloud;
  late SyncEngine engine;
  setUp(() async {
    local = await Directory.systemTemp.createTemp('sync-plan-');
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    final id = await db.insertPair(
      SyncPairsCompanion.insert(
        name: 'Review',
        localPath: local.path,
        remotePath: '/docs',
        provider: 'sftp',
        conflictPolicy: const Value('manual'),
      ),
    );
    pair = await db.getPair(id);
    cloud = WorkflowFakeClient();
    engine = SyncEngine(db);
    await File(p.join(local.path, 'a.txt')).writeAsString('left');
    cloud.put('/docs/a.txt', 'right'.codeUnits);
  });
  tearDown(() async {
    await db.close();
    await local.delete(recursive: true);
  });

  test('planning performs no writes or sync database changes', () async {
    final plan = await engine.planPair(pair, cloud);
    expect(plan.actions.single.type, SyncActionType.conflict);
    expect(cloud.writes, isEmpty);
    expect(await db.getEntriesForPair(pair.id), isEmpty);
    expect((await db.getPair(pair.id)).lastSyncAt, isNull);
    expect(await File(p.join(local.path, 'a.txt')).readAsString(), 'left');
  });

  test(
    'manual conflict can choose cloud version through reviewed execution',
    () async {
      final plan = await engine.planPair(pair, cloud);
      final result = await engine.executePlan(
        plan,
        decisions: {'a.txt': SyncActionType.download},
      );
      expect(result.errors, 0);
      expect(result.downloaded, 1);
      expect(await File(p.join(local.path, 'a.txt')).readAsString(), 'right');
      expect((await db.getEntry(pair.id, 'a.txt'))!.status, 'synced');
    },
  );

  test('skip decisions leave both versions untouched', () async {
    final plan = await engine.planPair(pair, cloud);
    final result = await engine.executePlan(
      plan,
      decisions: {'a.txt': SyncActionType.skip},
    );
    expect(result.hasChanges, isFalse);
    expect(await File(p.join(local.path, 'a.txt')).readAsString(), 'left');
    expect(cloud.writes, isEmpty);
  });

  test(
    'same-size content edits with restored timestamps invalidate review',
    () async {
      final file = File(p.join(local.path, 'a.txt'));
      final plan = await engine.planPair(pair, cloud);
      final modified = (await file.stat()).modified;
      await file.writeAsString('edit');
      await file.setLastModified(modified);
      final result = await engine.executePlan(
        plan,
        decisions: {'a.txt': SyncActionType.upload},
      );
      expect(result.errors, 1);
      expect(result.errorMessages.single, contains('contents changed'));
      expect(cloud.writes, isEmpty);
      expect(String.fromCharCodes(cloud.files['/docs/a.txt']!), 'right');
    },
  );

  test('changed connection invalidates plan before mutation', () async {
    var current = true;
    final plan = await engine.planPair(pair, cloud, isCurrent: () => current);
    current = false;
    final result = await engine.executePlan(
      plan,
      decisions: {'a.txt': SyncActionType.upload},
    );
    expect(result.errors, 1);
    expect(cloud.writes, isEmpty);
  });

  test('cancellation leaves an unapplied plan unchanged', () async {
    final plan = await engine.planPair(pair, cloud);
    final result = await engine.executePlan(plan, isCancelled: () => true);
    expect(result.cancelled, isTrue);
    expect(cloud.writes, isEmpty);
  });

  test('identical content is adopted only when the plan is applied', () async {
    cloud.put('/docs/a.txt', 'left'.codeUnits);
    final plan = await engine.planPair(pair, cloud);
    expect(plan.actions, isEmpty);
    expect(await db.getEntriesForPair(pair.id), isEmpty);
    final result = await engine.executePlan(plan);
    expect(result.errors, 0);
    expect((await db.getEntry(pair.id, 'a.txt'))!.status, 'synced');
    expect(cloud.writes, isEmpty);
  });

  test(
    'missing local root never becomes an implicit delete-all request',
    () async {
      final missing = pair.copyWith(localPath: p.join(local.path, 'missing'));
      await expectLater(
        engine.planPair(missing, cloud),
        throwsA(isA<FileSystemException>()),
      );
      expect(cloud.files, hasLength(1));
    },
  );

  test(
    'manual resolution persisted as pending download is actually applied',
    () async {
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: pair.id,
          relativePath: 'a.txt',
          status: const Value('pendingDownload'),
        ),
      );
      final result = await engine.syncPair(pair, cloud);
      expect(result.downloaded, 1);
      expect(result.conflicts, 0);
      expect(await File(p.join(local.path, 'a.txt')).readAsString(), 'right');
    },
  );
}

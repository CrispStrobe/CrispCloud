import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';

import 'support/workflow_fake_client.dart';
import 'support/sync_test_binding.dart';

void main() {
  late Directory local;
  late SyncDatabase db;
  late SyncPair pair;
  late WorkflowFakeClient cloud;
  setUp(() async {
    local = await Directory.systemTemp.createTemp('sync-conflict-');
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    final id = await db.insertPair(
      SyncPairsCompanion.insert(
        name: 'Conflict',
        localPath: local.path,
        remotePath: '/docs',
        provider: 'sftp',
        conflictPolicy: const Value('keepBoth'),
      ),
    );
    pair = await db.getPair(id);
    cloud = WorkflowFakeClient();
    pair = await bindTestPair(db, pair, cloud);
    await File(p.join(local.path, 'notes.txt')).writeAsString('local version');
    cloud.put('/docs/notes.txt', 'cloud version'.codeUnits);
  });
  tearDown(() async {
    await db.close();
    await local.delete(recursive: true);
  });

  test(
    'keep both preserves both contents on both sides and reaches stable state',
    () async {
      final engine = SyncEngine(db);
      final result = await engine.syncPair(pair, cloud);
      expect(result.errors, 0);
      expect(result.uploaded, 1);
      expect(result.downloaded, 1);
      expect(
        await File(p.join(local.path, 'notes.txt')).readAsString(),
        'cloud version',
      );
      expect(
        await File(p.join(local.path, 'notes (local conflict).txt'))
            .readAsString(),
        'local version',
      );
      expect(
        String.fromCharCodes(cloud.files['/docs/notes.txt']!),
        'cloud version',
      );
      expect(
        String.fromCharCodes(cloud.files['/docs/notes (local conflict).txt']!),
        'local version',
      );
      final second = await engine.syncPair(pair, cloud);
      expect(second.hasChanges, isFalse);
      expect(second.errors, 0);
    },
  );

  test(
    'conflict copies never replace an existing local or cloud filename',
    () async {
      await File(p.join(local.path, 'notes (local conflict).txt'))
          .writeAsString('existing local');
      cloud.put(
        '/docs/notes (local conflict 2).txt',
        'existing remote'.codeUnits,
      );
      final result = await SyncEngine(db).syncPair(pair, cloud);
      expect(result.errors, 0);
      expect(
        await File(p.join(local.path, 'notes (local conflict 3).txt'))
            .readAsString(),
        'local version',
      );
      expect(
        await File(p.join(local.path, 'notes (local conflict).txt'))
            .readAsString(),
        'existing local',
      );
      expect(
        String.fromCharCodes(
          cloud.files['/docs/notes (local conflict 2).txt']!,
        ),
        'existing remote',
      );
    },
  );

  test(
    'failed conflict upload preserves originals and a local recovery copy',
    () async {
      cloud.failUploads = true;
      final result = await SyncEngine(db).syncPair(pair, cloud);
      expect(result.errors, 1);
      expect(
        await File(p.join(local.path, 'notes.txt')).readAsString(),
        'local version',
      );
      expect(
        await File(p.join(local.path, 'notes (local conflict).txt'))
            .readAsString(),
        'local version',
      );
      expect(
        String.fromCharCodes(cloud.files['/docs/notes.txt']!),
        'cloud version',
      );
    },
  );

  test('matching directory containers are not uploaded as files', () async {
    await Directory(p.join(local.path, 'nested')).create();
    cloud.directories.add('/docs/nested');
    final result = await SyncEngine(db).syncPair(pair, cloud);
    expect(result.errors, 0);
    expect(cloud.writes, isNot(contains('/docs/nested')));
  });
}

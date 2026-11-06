import 'package:crisp_cloud/services/sync_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'SQLite native binding supports the shipped Drift schema and transactions',
    () async {
      final db = SyncDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await db.insertPair(
        SyncPairsCompanion.insert(
          name: 'CI database probe',
          localPath: '/local',
          remotePath: '/remote',
          provider: 'filen',
        ),
      );
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: id,
          relativePath: 'sample.txt',
          localSize: const Value(3),
        ),
      );
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: id,
          relativePath: 'sample.txt',
          localSize: const Value(7),
        ),
      );
      expect((await db.getEntriesForPair(id)).single.localSize, 7);
      await expectLater(
        db.transaction(() async {
          await db.deleteEntriesForPair(id);
          throw StateError('force rollback');
        }),
        throwsStateError,
      );
      expect(
        (await db.getEntriesForPair(id)).single.relativePath,
        'sample.txt',
      );
      expect((await db.getPair(id)).name, 'CI database probe');
    },
  );
}

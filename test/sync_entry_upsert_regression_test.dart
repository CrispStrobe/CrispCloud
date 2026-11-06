import 'package:crisp_cloud/services/sync_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repeated sync upserts update pair/path in place and isolate other pairs',
    () async {
      final db = SyncDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      Future<int> createPair(String name) => db.insertPair(
        SyncPairsCompanion.insert(
          name: name,
          localPath: '/local/$name',
          remotePath: '/remote/$name',
          provider: 'filen',
        ),
      );
      final firstPair = await createPair('first');
      final secondPair = await createPair('second');
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: firstPair,
          relativePath: 'docs/report.txt',
          localHash: const Value('original-hash'),
          remoteHash: const Value('retained-hash'),
          localSize: const Value(3),
          status: const Value('pendingUpload'),
        ),
      );
      final original = (await db.getEntry(firstPair, 'docs/report.txt'))!;
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: secondPair,
          relativePath: 'docs/report.txt',
          localHash: const Value('other-pair'),
          localSize: const Value(42),
        ),
      );
      // A second scan supplies the natural key, as SyncEngine does, with no id.
      await db.upsertEntry(
        SyncEntriesCompanion.insert(
          pairId: firstPair,
          relativePath: 'docs/report.txt',
          localHash: const Value('new-hash'),
          localSize: const Value(9),
          status: const Value('synced'),
        ),
      );
      final updated = (await db.getEntry(firstPair, 'docs/report.txt'))!;
      expect(updated.id, original.id);
      expect(updated.localHash, 'new-hash');
      expect(updated.localSize, 9);
      expect(updated.status, 'synced');
      expect(updated.remoteHash, 'retained-hash');
      expect(await db.getEntriesForPair(firstPair), hasLength(1));
      final other = (await db.getEntry(secondPair, 'docs/report.txt'))!;
      expect(other.localHash, 'other-pair');
      expect(other.localSize, 42);
      expect(other.id, isNot(original.id));
    },
  );
}

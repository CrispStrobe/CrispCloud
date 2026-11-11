import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_storage_factory.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('IndexedDB bounded page batches survive restart and reject invalid groups before writes', () async {
    final storage = createFileCollectionStorage(
      preferences: SharedPreferences.getInstance,
    );
    final writer = storage as FileCollectionStorageBatchWriter;
    final records = [
      for (var index = 0; index < 4; index++)
        FileCollectionStorageRecord(
          'browser-batch-$index',
          '{"資料":"📁-$index"}',
        ),
    ];
    const extraKey = 'browser-batch-extra';
    for (final key in [...records.map((record) => record.key), extraKey]) {
      await storage.remove(key);
    }
    try {
      await writer.writeBatch(records);
      final restarted = createFileCollectionStorage(
        preferences: SharedPreferences.getInstance,
      );
      for (final record in records) {
        expect(await restarted.read(record.key, maxBytes: 100), record.value);
      }
      await expectLater(
        writer.writeBatch([
          ...records.map(
            (record) => FileCollectionStorageRecord(record.key, 'replacement'),
          ),
          FileCollectionStorageRecord(extraKey, 'exceeds count'),
        ]),
        throwsArgumentError,
      );
      await expectLater(
        writer.writeBatch([
          FileCollectionStorageRecord(records.first.key, 'first replacement'),
          FileCollectionStorageRecord(records.first.key, 'second replacement'),
        ]),
        throwsArgumentError,
      );
      for (final record in records) {
        expect(await restarted.read(record.key, maxBytes: 100), record.value);
      }
      expect(await restarted.read(extraKey, maxBytes: 100), isNull);
    } finally {
      for (final key in [...records.map((record) => record.key), extraKey]) {
        await storage.remove(key);
      }
    }
  }, skip: !kIsWeb);

  test('IndexedDB clients serialize catalog CAS and preserve bounded records after restart', () async {
    final first = createFileCollectionStorage(
      preferences: SharedPreferences.getInstance,
    );
    final second = createFileCollectionStorage(
      preferences: SharedPreferences.getInstance,
    );
    const key = 'browser-cas-fixture';
    await first.remove(key);
    final race = await Future.wait([
      first.compareAndSwap(key, null, 'first'),
      second.compareAndSwap(key, null, 'second'),
    ]);
    expect(race.where((won) => won), hasLength(1));
    final stored = await second.read(key, maxBytes: 50);
    expect(stored, race.first ? 'first' : 'second');
    await expectLater(first.read(key, maxBytes: 1), throwsFormatException);
    expect(await second.compareAndSwap(key, 'wrong', 'replacement'), isFalse);
    expect(await first.read(key, maxBytes: 50), stored);
    await first.remove(key);

    final store = FileCollectionStore(storage: first, cacheEntryLimit: 500);
    await store.ready;
    const source = StorageReference(
      kind: 'remote',
      provider: 'Browser fixture',
      accountKey: 'original',
    );
    final entries = [
      for (var index = 0; index < 1400; index++)
        FileCollectionService.capture(
          FileItem(
            name: 'item-$index',
            path: '/item-$index',
            uuid: 'object-$index',
            isFolder: false,
          ),
          source,
        ),
    ];
    await store.save(
      FileCollection(
        id: 'browser-pages',
        name: 'Browser pages',
        entries: entries,
        selectedKeys: {entries.first.key, entries.last.key},
      ),
    );
    store.dispose();
    final restarted = FileCollectionStore(
      storage: second,
      cacheEntryLimit: 500,
    );
    await restarted.ready;
    expect(restarted.get('browser-pages')!.itemCount, 1400);
    expect(restarted.residentEntryCount, 0);
    final last = await restarted.loadPage('browser-pages', 2);
    expect(last.collection.entries, hasLength(400));
    expect(last.collection.entries.last.reference.objectId, 'object-1399');
    expect(last.collection.selectedKeys, {entries.last.key});
    expect(restarted.residentEntryCount, 400);
    await restarted.remove('browser-pages');
    restarted.dispose();
  }, skip: !kIsWeb);
}

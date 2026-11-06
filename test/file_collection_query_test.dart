import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_collection_query.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = StorageReference(
  kind: 'remote',
  provider: 'Fixture',
  accountKey: 'a',
);
const _b = StorageReference(
  kind: 'remote',
  provider: 'Fixture',
  accountKey: 'b',
);

FileCollection _fixture(int count) => FileCollection(
  id: 'query',
  name: 'Whole collection',
  entries: [
    for (var index = count - 1; index >= 0; index--)
      FileCollectionService.capture(
        FileItem(
          name: 'row-${(index ~/ 2).toString().padLeft(5, '0')}.txt',
          path: '/row-${(index ~/ 2).toString().padLeft(5, '0')}.txt',
          uuid: 'object-${index ~/ 2}',
          isFolder: false,
          size: index,
          updatedAt: DateTime.utc(2024, 1, 1).add(Duration(seconds: index)),
        ),
        index.isEven ? _a : _b,
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('global windows sort across physical pages without losing equal-name accounts', () async {
    final store = FileCollectionStore(
      storage: MemoryFileCollectionStorage(),
      cacheEntryLimit: 600,
    );
    addTearDown(store.dispose);
    final collection = _fixture(2401);
    await store.save(collection);
    final manifest = await store.manifest('query');
    int compare(FileItem a, FileItem b) => a.name.compareTo(b.name);
    final expected = List.of(collection.entries)
      ..sort((a, b) {
        final value = compare(a.file, b.file);
        return value == 0 ? a.key.compareTo(b.key) : value;
      });
    final query = FileCollectionQuery();
    var window = await query.run(
      store,
      manifest,
      compare: compare,
      matches: (_) => true,
    );
    final seen = <String>[];
    for (var page = 0; page < 5; page++) {
      expect(window.rows.length, lessThanOrEqualTo(500));
      expect(window.start, page * 500);
      expect(window.index, page);
      expect(window.total, 2401);
      expect(window.pageCount, 5);
      seen.addAll(window.rows.map((row) => row.entry.key));
      expect(store.residentEntryCount, lessThanOrEqualTo(600));
      if (page < 4) {
        window = await query.run(
          store,
          manifest,
          compare: compare,
          matches: (_) => true,
          after: window.rows.last.entry,
        );
      }
    }
    expect(seen, expected.map((entry) => entry.key).toList());
    final previous = await query.run(
      store,
      manifest,
      compare: compare,
      matches: (_) => true,
      before: window.rows.first.entry,
    );
    expect(previous.start, 1500);
    expect(
      previous.rows.map((row) => row.entry.key),
      expected.skip(1500).take(500).map((entry) => entry.key),
    );
    final last = await query.run(
      store,
      manifest,
      compare: compare,
      matches: (_) => true,
      last: true,
    );
    expect(last.start, 2000);
    expect(
      last.rows.map((row) => row.entry.key),
      expected.skip(2000).map((entry) => entry.key),
    );
  });

  test('a filter finds rows absent from the first physical page and sorts by metadata', () async {
    final store = FileCollectionStore(storage: MemoryFileCollectionStorage());
    addTearDown(store.dispose);
    await store.save(_fixture(6000));
    final manifest = await store.manifest('query');
    final result = await FileCollectionQuery().run(
      store,
      manifest,
      compare: (a, b) => b.size!.compareTo(a.size!),
      matches: (file) => file.size! < 1200 && file.size!.isEven,
    );
    expect(result.total, 600);
    expect(result.rows.first.entry.file.size, 1198);
    expect(result.rows.last.entry.file.size, 200);
    expect(result.rows.every((row) => row.pageIndex >= 9), isTrue);
    final next = await FileCollectionQuery().run(
      store,
      manifest,
      compare: (a, b) => b.size!.compareTo(a.size!),
      matches: (file) => file.size! < 1200 && file.size!.isEven,
      after: result.rows.last.entry,
    );
    expect(next.start, 500);
    expect(next.rows, hasLength(100));
    expect(next.rows.last.entry.file.size, 0);
  });

  test(
    'cancelled scans never return a partial window or mutate saved rows',
    () async {
      final store = FileCollectionStore(storage: MemoryFileCollectionStorage());
      addTearDown(store.dispose);
      await store.save(_fixture(3000));
      final manifest = await store.manifest('query');
      var cancelled = false;
      await expectLater(
        FileCollectionQuery().run(
          store,
          manifest,
          compare: (a, b) => a.name.compareTo(b.name),
          matches: (_) => true,
          isCancelled: () => cancelled,
          onProgress: (done, _) {
            if (done >= 1000) cancelled = true;
          },
        ),
        throwsStateError,
      );
      expect(store.get('query')!.revision, manifest.summary.revision);
      expect(store.get('query')!.itemCount, 3000);
    },
  );

  test(
    'captured query revision rejects replacement instead of mixing saved pages',
    () async {
      final store = FileCollectionStore(storage: MemoryFileCollectionStorage());
      addTearDown(store.dispose);
      await store.save(_fixture(1200));
      final before = await store.manifest('query');
      await store.save(_fixture(600));
      await expectLater(
        FileCollectionQuery().run(
          store,
          before,
          compare: (a, b) => a.name.compareTo(b.name),
          matches: (_) => true,
        ),
        throwsStateError,
      );
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_collection_page.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_storage_native.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = StorageReference(
  kind: 'remote',
  provider: 'Fixture',
  accountKey: 'account-a',
);
const _b = StorageReference(
  kind: 'remote',
  provider: 'Fixture',
  accountKey: 'account-b',
);

FileCollection _collection(String id, int count) {
  final entries = List.generate(
    count,
    (index) => FileCollectionService.capture(
      FileItem(
        name: 'row-${index ~/ 2}.txt',
        path: '/files/row-${index ~/ 2}.txt',
        uuid: 'object-${index ~/ 2}',
        isFolder: false,
        size: index,
        metadata: {'etag': 'version-$index'},
      ),
      index.isEven ? _a : _b,
    ),
  );
  return FileCollection(
    id: id,
    name: 'Saved $id',
    entries: entries,
    selectedKeys: {
      for (var index = 0; index < count; index += 127) entries[index].key,
    },
  );
}

class _RejectCommit extends MemoryFileCollectionStorage {
  bool reject = false;
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async => reject ? false : super.compareAndSwap(key, expected, value);
}

class _LostCatalogAcknowledgement extends MemoryFileCollectionStorage {
  bool loseNextAcknowledgement = false;
  bool blockCatalogReadsAfterCommit = false;
  bool catalogReadsBlocked = false;
  bool manifestReadsBlocked = false;
  Future<void> Function()? afterCommit;

  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    if ((key == 'catalog-v2' && catalogReadsBlocked) ||
        (key.startsWith('manifest:') && manifestReadsBlocked)) {
      throw StateError('Injected record read failure.');
    }
    return super.read(key, maxBytes: maxBytes);
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final committed = await super.compareAndSwap(key, expected, value);
    if (committed) {
      final callback = afterCommit;
      afterCommit = null;
      await callback?.call();
      if (loseNextAcknowledgement) {
        loseNextAcknowledgement = false;
        catalogReadsBlocked = blockCatalogReadsAfterCommit;
        throw StateError('Injected lost catalog acknowledgement.');
      }
    }
    return committed;
  }
}

void _rewriteManifest(
  MemoryFileCollectionStorage storage,
  String id,
  void Function(Map<String, dynamic> manifest) change,
) {
  final catalog = jsonDecode(storage.values['catalog-v2']!) as Map;
  final summaries = catalog['collections'] as List;
  final index = summaries.indexWhere((record) => (record as Map)['id'] == id);
  final revision = (summaries[index] as Map)['revision'];
  final key = 'manifest:$id:$revision';
  final manifest = Map<String, dynamic>.from(
    jsonDecode(storage.values[key]!) as Map,
  );
  change(manifest);
  summaries[index] = manifest['summary'];
  storage.values[key] = jsonEncode(manifest);
  storage.values['catalog-v2'] = jsonEncode(catalog);
}

class _PausedNativeStorage extends NativeFileCollectionStorage {
  _PausedNativeStorage(String path)
    : super(directory: () async => Directory(path));
  final entered = Completer<void>();
  final release = Completer<void>();
  bool pause = false;
  @override
  Future<void> write(String key, String value) async {
    if (pause) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'restart loads only the catalog across many large collections',
    () async {
      final storage = MemoryFileCollectionStorage();
      final store = FileCollectionStore(storage: storage);
      for (var index = 0; index < 8; index++) {
        await store.save(_collection('large-$index', 6000));
      }
      expect(store.residentEntryCount, 0);
      store.dispose();
      storage.reads.clear();
      final reopened = FileCollectionStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect(reopened.collections, hasLength(8));
      expect(
        reopened.collections.every((record) => record.itemCount == 6000),
        isTrue,
      );
      expect(storage.reads, ['catalog-v2']);
      expect(reopened.residentPageBytes, 0);
      expect(reopened.residentEntryCount, 0);
      final page = await reopened.loadPage('large-7', 9);
      expect(page.collection.entries, hasLength(500));
      expect(page.startIndex, 4500);
      expect(page.summary.itemCount, 6000);
      expect(page.collection.entries.first.reference.storage, _a);
      expect(page.collection.entries[1].reference.storage, _b);
      expect(
        page.collection.entries.first.reference.path,
        page.collection.entries[1].reference.path,
      );
      expect(page.collection.entries.first.reference.objectId, 'object-2250');
      expect(page.collection.entries.first.reference.version, 'version-4500');
      expect(reopened.residentEntryCount, 500);
    },
  );

  test('one aggregate byte/entry LRU budget covers all collections and concurrent loads', () async {
    final storage = MemoryFileCollectionStorage();
    final store = FileCollectionStore(
      storage: storage,
      cacheByteLimit: 800 * 1024,
      cacheEntryLimit: 700,
    );
    addTearDown(store.dispose);
    for (var index = 0; index < 3; index++) {
      await store.save(_collection('set-$index', 3000));
    }
    for (var index = 0; index < 15; index++) {
      await store.loadPage('set-${index % 3}', index % 6);
      expect(store.residentPageBytes, lessThanOrEqualTo(800 * 1024));
      expect(store.residentEntryCount, lessThanOrEqualTo(700));
      expect(store.residentPageCount, lessThanOrEqualTo(1));
    }
    await Future.wait([store.loadPage('set-0', 0), store.loadPage('set-0', 0)]);
    expect(store.residentEntryCount, 500);
    expect(store.residentPageCount, 1);
  });

  test('page mark changes preserve other pages and remain exact across account identities', () async {
    final storage = MemoryFileCollectionStorage();
    final store = FileCollectionStore(storage: storage);
    addTearDown(store.dispose);
    final original = _collection('marked', 1600);
    await store.save(original);
    final first = await store.loadPage('marked', 0);
    final last = await store.loadPage('marked', 3);
    final wanted = first.collection.entries[1].key;
    await store.updatePage(
      first,
      (page) => page.copyWith(selectedKeys: {wanted}),
    );
    final updated = await store.loadPage('marked', 0);
    expect(updated.collection.selectedKeys, {wanted});
    expect(
      updated.collection.entries.first.reference.path,
      updated.collection.entries[1].reference.path,
    );
    expect(updated.collection.entries.first.key, isNot(wanted));
    final lastAgain = await store.loadPage('marked', 3);
    expect(lastAgain.pageKey, last.pageKey);
    expect(lastAgain.collection.selectedKeys, last.collection.selectedKeys);
    await expectLater(
      store.loadPage('marked', 1, revision: first.summary.revision),
      throwsStateError,
    );
    final reopened = FileCollectionStore(storage: storage);
    addTearDown(reopened.dispose);
    await reopened.ready;
    final all = await reopened.load('marked');
    expect(all.entries, hasLength(1600));
    expect(all.selectedKeys, {
      ...original.selectedKeys.where(
        (key) => !first.collection.entries.any((entry) => entry.key == key),
      ),
      wanted,
    });
  });

  test('append and rename keep every unloaded page and clear only the saved query on append', () async {
    final store = FileCollectionStore(storage: MemoryFileCollectionStorage());
    addTearDown(store.dispose);
    await store.save(_collection('base', 2000));
    final additions = FileCollection(
      id: 'new',
      name: 'New',
      entries: [
        FileCollectionService.capture(
          FileItem(
            name: 'added.txt',
            path: '/other/added.txt',
            isFolder: false,
          ),
          _b,
        ),
      ],
    );
    await store.append('base', additions);
    await store.rename('base', 'Renamed');
    expect(store.get('base')!.itemCount, 2001);
    expect(store.get('base')!.name, 'Renamed');
    final last = await store.loadPage('base', 4);
    expect(last.collection.entries.single.reference.path, '/other/added.txt');
  });

  test(
    'failed catalog commit keeps the previous revision and removes staged data',
    () async {
      final storage = _RejectCommit();
      final store = FileCollectionStore(storage: storage);
      addTearDown(store.dispose);
      await store.save(_collection('stable', 1200));
      final before = Map.of(storage.values);
      final revision = store.get('stable')!.revision;
      storage.reject = true;
      await expectLater(
        store.save(_collection('stable', 2100)),
        throwsStateError,
      );
      expect(storage.values, before);
      expect(store.get('stable')!.revision, revision);
      final reopened = FileCollectionStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect((await reopened.load('stable')).entries, hasLength(1200));
    },
  );

  test('stale catalog writers cannot lose another collection update', () async {
    final storage = MemoryFileCollectionStorage();
    final one = FileCollectionStore(storage: storage);
    final two = FileCollectionStore(storage: storage);
    addTearDown(one.dispose);
    addTearDown(two.dispose);
    await Future.wait([one.ready, two.ready]);
    await one.save(_collection('first', 3));
    await expectLater(two.save(_collection('second', 4)), throwsStateError);
    await two.reload();
    await two.save(_collection('second', 4));
    final reopened = FileCollectionStore(storage: storage);
    addTearDown(reopened.dispose);
    await reopened.ready;
    expect(reopened.collections.map((record) => record.id).toSet(), {
      'first',
      'second',
    });
  });

  test(
    'lost catalog acknowledgement adopts the live immutable revision',
    () async {
      final storage = _LostCatalogAcknowledgement();
      final store = FileCollectionStore(storage: storage);
      addTearDown(store.dispose);
      await store.save(_collection('live', 600));
      final previous = store.get('live')!.revision;
      storage.loseNextAcknowledgement = true;
      await store.save(_collection('live', 1200));
      expect(store.get('live')!.revision, isNot(previous));
      expect(store.loadErrors, isEmpty);
      final reopened = FileCollectionStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect((await reopened.load('live')).entries, hasLength(1200));
    },
  );

  test(
    'unreadable catalog acknowledgement retains both revisions until reload',
    () async {
      final storage = _LostCatalogAcknowledgement();
      final store = FileCollectionStore(storage: storage);
      addTearDown(store.dispose);
      await store.save(_collection('uncertain', 600));
      final oldRecords = Map.of(storage.values)..remove('catalog-v2');
      storage
        ..loseNextAcknowledgement = true
        ..blockCatalogReadsAfterCommit = true;
      await expectLater(
        store.save(_collection('uncertain', 1200)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Both revisions were kept'),
          ),
        ),
      );
      for (final entry in oldRecords.entries) {
        expect(storage.values[entry.key], entry.value);
      }
      final retained = Map.of(storage.values);
      await expectLater(
        store.save(_collection('blocked', 1)),
        throwsStateError,
      );
      expect(storage.values, retained);
      storage.catalogReadsBlocked = false;
      await store.reload();
      expect(store.loadErrors, isEmpty);
      expect((await store.load('uncertain')).entries, hasLength(1200));
      await store.save(_collection('after-reload', 1));
    },
  );

  test(
    'a later catalog writer cannot make lost-ack cleanup delete live pages',
    () async {
      final storage = _LostCatalogAcknowledgement();
      final store = FileCollectionStore(storage: storage);
      addTearDown(store.dispose);
      await store.save(_collection('retained', 600));
      storage.afterCommit = () async {
        final other = FileCollectionStore(storage: storage);
        try {
          await other.save(_collection('other-window', 3));
        } finally {
          other.dispose();
        }
        // Arm this only after the nested writer has completed its own CAS.
        storage.loseNextAcknowledgement = true;
      };
      await expectLater(
        store.save(_collection('retained', 1200)),
        throwsStateError,
      );
      final reopened = FileCollectionStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect((await reopened.load('retained')).entries, hasLength(1200));
      expect((await reopened.load('other-window')).entries, hasLength(3));
    },
  );

  test('mark commit returns its durable manifest without a fallible follow-up read', () async {
    final storage = _LostCatalogAcknowledgement();
    final store = FileCollectionStore(storage: storage);
    addTearDown(store.dispose);
    await store.save(_collection('marks', 600));
    final before = await store.manifest('marks');
    final first = await store.loadPage('marks', 0);
    final selected = {first.collection.entries[1].key};
    storage.afterCommit = () async => storage.manifestReadsBlocked = true;
    final committed = await store.updateMarks(before, {0: selected});
    expect(committed.summary.revision, isNot(before.summary.revision));
    storage.manifestReadsBlocked = false;
    final reopened = FileCollectionStore(storage: storage);
    addTearDown(reopened.dispose);
    await reopened.ready;
    expect(
      (await reopened.loadPage('marks', 0)).collection.selectedKeys,
      selected,
    );
    expect((await reopened.load('marks')).entries, hasLength(600));
  });

  test('transform rejects duplicate source paths across changed and unchanged pages', () async {
    final storage = MemoryFileCollectionStorage();
    final store = FileCollectionStore(storage: storage);
    addTearDown(store.dispose);
    final original = _collection('unique-transform', 600);
    await store.save(original);
    final before = Map.of(storage.values);
    await expectLater(
      store.applyFileChanges(_a, {
        original.entries.first.reference.path: original.entries[500].file,
      }),
      throwsFormatException,
    );
    expect(storage.values, before);
    final restored = await store.load(original.id);
    expect(
      restored.entries.map((entry) => entry.key),
      original.entries.map((entry) => entry.key),
    );
    expect(restored.selectedKeys, original.selectedKeys);
  });

  test('single-page updates cannot collide with an unloaded page', () async {
    final storage = MemoryFileCollectionStorage();
    final store = FileCollectionStore(storage: storage);
    addTearDown(store.dispose);
    final original = _collection('unique-page', 600);
    await store.save(original);
    final first = await store.loadPage(original.id, 0);
    final before = Map.of(storage.values);
    await expectLater(
      store.updatePage(
        first,
        (page) => page.copyWith(
          entries: [original.entries[500], ...page.entries.skip(1)],
        ),
      ),
      throwsFormatException,
    );
    expect(storage.values, before);
    expect((await store.load(original.id)).entries, hasLength(600));
  });

  test('legacy migration is committed before removing original data, with restart-compatible marks', () async {
    final original = _collection('legacy', 1200);
    final raw = jsonEncode(original.toJson());
    SharedPreferences.setMockInitialValues({
      'commander_collections_v1': ['legacy'],
      'commander_collection_v1_legacy': raw,
    });
    final storage = _RejectCommit()..reject = true;
    final store = FileCollectionStore(storage: storage);
    addTearDown(store.dispose);
    await store.ready;
    expect(store.loadErrors.single, contains('legacy'));
    expect(
      (await SharedPreferences.getInstance()).getString(
        'commander_collection_v1_legacy',
      ),
      raw,
    );
    storage.reject = false;
    await store.reload();
    expect(store.loadErrors, isEmpty);
    expect(store.get('legacy')!.itemCount, 1200);
    expect(store.residentEntryCount, 0);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'commander_collection_v1_legacy',
      ),
      isNull,
    );
    final reopened = FileCollectionStore(storage: storage);
    addTearDown(reopened.dispose);
    await reopened.ready;
    final restored = await reopened.load('legacy');
    expect(restored.selectedKeys, original.selectedKeys);
    expect(restored.entries[1].reference.storage, _b);
  });

  for (final damage in ['missing manifest', 'missing page', 'corrupt page']) {
    test(
      'migration retains legacy fallback for $damage and continues other records',
      () async {
        final storage = MemoryFileCollectionStorage();
        final initial = FileCollectionStore(storage: storage);
        final broken = _collection('legacy-broken', 600);
        final valid = _collection('legacy-valid', 4);
        final unmigrated = _collection('legacy-new', 3);
        await initial.save(broken);
        await initial.save(valid);
        final manifest = await initial.manifest(broken.id);
        initial.dispose();
        final manifestKey =
            'manifest:${broken.id}:${manifest.summary.revision}';
        final damagedKey = damage == 'missing manifest'
            ? manifestKey
            : manifest.pages.last.key;
        final originalRecord = storage.values[damagedKey]!;
        if (damage == 'corrupt page') {
          storage.values[damagedKey] = originalRecord.replaceFirst(
            'row-250.txt',
            'row-XXX.txt',
          );
        } else {
          storage.values.remove(damagedKey);
        }
        final legacyRaw = jsonEncode(broken.toJson());
        SharedPreferences.setMockInitialValues({
          'commander_collections_v1': [broken.id, valid.id, unmigrated.id],
          'commander_collection_v1_${broken.id}': legacyRaw,
          'commander_collection_v1_${valid.id}': jsonEncode(valid.toJson()),
          'commander_collection_v1_${unmigrated.id}': jsonEncode(
            unmigrated.toJson(),
          ),
        });
        final reopened = FileCollectionStore(storage: storage);
        addTearDown(reopened.dispose);
        await reopened.ready;
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('commander_collection_v1_${broken.id}'),
          legacyRaw,
        );
        expect(prefs.getStringList('commander_collections_v1'), [broken.id]);
        expect(prefs.getString('commander_collection_v1_${valid.id}'), isNull);
        expect(
          prefs.getString('commander_collection_v1_${unmigrated.id}'),
          isNull,
        );
        expect(
          reopened.loadErrors.any(
            (error) => error.contains(broken.id) || error.contains(broken.name),
          ),
          isTrue,
        );
        expect(reopened.residentEntryCount, 0);
        expect((await reopened.load(valid.id)).entries, hasLength(4));
        expect((await reopened.load(unmigrated.id)).entries, hasLength(3));

        storage.values[damagedKey] = originalRecord;
        await reopened.reload();
        expect(reopened.loadErrors, isEmpty);
        expect(prefs.getString('commander_collection_v1_${broken.id}'), isNull);
        expect(prefs.getStringList('commander_collections_v1'), isEmpty);
        expect(
          (await reopened.load(broken.id)).selectedKeys,
          broken.selectedKeys,
        );
      },
    );
  }

  test('a mixed corrupt catalog cannot authorize legacy cleanup', () async {
    final storage = MemoryFileCollectionStorage();
    final initial = FileCollectionStore(storage: storage);
    final original = _collection('legacy-catalog', 600);
    await initial.save(original);
    initial.dispose();
    final catalog = jsonDecode(storage.values['catalog-v2']!) as Map;
    (catalog['collections'] as List).add({'id': 'invalid-record'});
    storage.values['catalog-v2'] = jsonEncode(catalog);
    final raw = jsonEncode(original.toJson());
    SharedPreferences.setMockInitialValues({
      'commander_collections_v1': [original.id],
      'commander_collection_v1_${original.id}': raw,
    });
    final reopened = FileCollectionStore(storage: storage);
    addTearDown(reopened.dispose);
    await reopened.ready;
    expect(reopened.loadErrors, isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('commander_collection_v1_${original.id}'), raw);
    expect(prefs.getStringList('commander_collections_v1'), [original.id]);
    await expectLater(
      reopened.save(_collection('blocked', 1)),
      throwsStateError,
    );
  });

  test('manifest source counts must match the declared page sources', () async {
    final storage = MemoryFileCollectionStorage();
    final store = FileCollectionStore(storage: storage);
    addTearDown(store.dispose);
    await store.save(_collection('source-count', 10));
    _rewriteManifest(storage, 'source-count', (manifest) {
      (manifest['summary'] as Map)['sourceCount'] = 3;
    });
    await store.reload();
    await expectLater(store.loadPage('source-count', 0), throwsFormatException);
  });

  test(
    'summary and page source sets reject impossible counts and duplicates',
    () async {
      final store = FileCollectionStore(storage: MemoryFileCollectionStorage());
      addTearDown(store.dispose);
      await store.save(_collection('source-validation', 1));
      final manifest = await store.manifest('source-validation');
      final summary = manifest.summary.toJson()..['sourceCount'] = 2;
      expect(
        () => FileCollectionSummary.fromJson(summary),
        throwsFormatException,
      );
      for (final sources in [
        <String>[],
        [_a.id, _a.id],
        [_a.id, _b.id],
      ]) {
        final page = manifest.pages.single.toJson()..['sources'] = sources;
        expect(
          () => CollectionPageDescriptor.fromJson(page),
          throwsFormatException,
        );
      }
    },
  );

  for (final cached in [false, true]) {
    for (final field in ['sources', 'unavailable', 'digest']) {
      test('page $field evidence is validated with cache=$cached', () async {
        final storage = MemoryFileCollectionStorage();
        final store = FileCollectionStore(
          storage: storage,
          cacheByteLimit: cached ? 4 * 1024 * 1024 : 0,
        );
        addTearDown(store.dispose);
        final base = _collection('descriptor', 600);
        final first = base.entries.first;
        await store.save(
          base.copyWith(
            entries: [
              FileCollectionEntry(
                reference: first.reference,
                file: first.file,
                state: CollectionItemState.offline,
              ),
              ...base.entries.skip(1),
            ],
          ),
        );
        await store.loadPage(base.id, 0);
        expect(store.residentEntryCount, cached ? 500 : 0);
        _rewriteManifest(storage, base.id, (manifest) {
          final pages = manifest['pages'] as List;
          final page = pages.first as Map;
          if (field == 'sources') {
            // Page 1 keeps both accounts, so the aggregate summary stays valid.
            page['sources'] = [_a.id];
          } else if (field == 'unavailable') {
            page['unavailable'] = 0;
            (pages.last as Map)['unavailable'] = 1;
          } else {
            page['digest'] = List.filled(64, '0').join();
          }
        });
        await expectLater(store.loadPage(base.id, 0), throwsFormatException);
        expect(
          store.loadErrors.any((error) => error.contains('page 1')),
          isTrue,
        );
      });
    }
  }

  test('same-size page corruption is visible and never substituted with empty rows', () async {
    final storage = MemoryFileCollectionStorage();
    final store = FileCollectionStore(storage: storage, cacheByteLimit: 0);
    addTearDown(store.dispose);
    await store.save(_collection('damaged', 10));
    final page = await store.loadPage('damaged', 0);
    storage.values[page.pageKey!] = storage.values[page.pageKey!]!.replaceFirst(
      'row-0.txt',
      'row-X.txt',
    );
    await expectLater(store.loadPage('damaged', 0), throwsFormatException);
    expect(store.loadErrors.single, contains('page 1'));
    expect(store.get('damaged')!.itemCount, 10);
  });

  test(
    'native CAS excludes a second isolate while the first holds its lease',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'collection-cas-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final first = _PausedNativeStorage(directory.path);
      await first.write('catalog', 'old');
      first.pause = true;
      final writing = first.compareAndSwap('catalog', 'old', 'first');
      await first.entered.future;
      bool? second;
      try {
        final path = directory.path;
        second = await Isolate.run(
          () => NativeFileCollectionStorage(
            directory: () async => Directory(path),
          ).compareAndSwap('catalog', 'old', 'second'),
        );
      } finally {
        first.release.complete();
      }
      expect(await writing, isTrue);
      expect(second, isFalse);
      expect(await first.read('catalog', maxBytes: 100), 'first');
    },
  );

  test('native independent pages survive store restart without preference payloads', () async {
    final directory = await Directory.systemTemp.createTemp(
      'collection-native-',
    );
    addTearDown(() => directory.delete(recursive: true));
    NativeFileCollectionStorage storage() =>
        NativeFileCollectionStorage(directory: () async => directory);
    final store = FileCollectionStore(storage: storage());
    await store.save(_collection('native', 1300));
    store.dispose();
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    final reopened = FileCollectionStore(storage: storage());
    addTearDown(reopened.dispose);
    await reopened.ready;
    expect(reopened.residentEntryCount, 0);
    final page = await reopened.loadPage('native', 2);
    expect(page.collection.entries, hasLength(300));
    expect(page.collection.entries.first.reference.path, '/files/row-500.txt');
  });
}

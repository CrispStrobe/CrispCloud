import 'dart:convert';

import 'package:archive/archive.dart';

import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Backend extends Fake implements FileOperationBackend {
  final Map<String, FileItem> items = {};
  final Map<String, List<int>> content = {};
  final List<String> listed = [];
  @override
  bool isCurrent = true;
  @override
  p.Context get paths => p.posix;
  @override
  String pathKey(String path) => paths.normalize(path);
  @override
  bool isWithin(String parent, String child) => paths.isWithin(parent, child);
  @override
  Future<List<FileItem>> list(String path) async {
    listed.add(path);
    return items.values
        .where((file) => file.path != path && paths.dirname(file.path!) == path)
        .toList();
  }

  @override
  Future<FileItem?> stat(String path) async => items[path];
  @override
  Stream<List<int>> readFile(FileItem file) =>
      Stream.value(content[file.path] ?? utf8.encode(file.name));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const a = StorageReference(
    kind: 'remote',
    provider: 'Cloud',
    accountKey: 'opaque-a',
  );
  const b = StorageReference(
    kind: 'remote',
    provider: 'Cloud',
    accountKey: 'opaque-b',
  );
  const service = FileCollectionService();
  FileItem file(String path, {String? id, int size = 4}) => FileItem(
    name: p.posix.basename(path),
    path: path,
    uuid: id,
    isFolder: false,
    size: size,
  );
  FileCollection collection(
    List<FileCollectionEntry> entries, {
    CollectionSearch? search,
  }) => FileCollection(
    id: 'saved',
    name: 'Results',
    entries: entries,
    search: search,
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'same paths on two accounts survive persistence as distinct selected rows',
    () async {
      final one = FileCollectionService.capture(
        file('/same.txt', id: 'same-id'),
        a,
      );
      final two = FileCollectionService.capture(
        file('/same.txt', id: 'same-id'),
        b,
      );
      final value = collection([one, two])
          .copyWith(selectedKeys: {one.key, two.key});
      final store = FileCollectionStore();
      await store.save(value);
      store.dispose();
      final reopened = FileCollectionStore();
      await reopened.ready;
      final restored = reopened.get('saved')!;
      expect(restored.entries.length, 2);
      expect(restored.entries.map((entry) => entry.file).toSet().length, 2);
      expect(restored.selectedKeys.length, 2);
      reopened.dispose();
    },
  );

  test('refresh keeps missing/offline rows and never falls back to another account', () async {
    final backend = _Backend()..items['/found'] = file('/found');
    final value = collection([
      FileCollectionService.capture(file('/found'), a),
      FileCollectionService.capture(file('/missing'), a),
      FileCollectionService.capture(file('/found'), b),
    ]);
    final result = await service.refresh(
      value,
      (storage, _) => storage == a ? backend : null,
    );
    expect(result.collection.entries.map((entry) => entry.state), [
      CollectionItemState.ready,
      CollectionItemState.missing,
      CollectionItemState.offline,
    ]);
    expect(result.verifiedKeys, {value.entries.first.key});
    expect(backend.listed, ['/']); // siblings are fetched once
  });

  test(
    'replacement object is blocked until the user accepts the changed row',
    () async {
      final backend = _Backend()
        ..items['/same'] = file('/same', id: 'new-object');
      final value = collection([
        FileCollectionService.capture(file('/same', id: 'original-object'), a),
      ]);
      final blocked = await service.refresh(value, (_, _) => backend);
      expect(blocked.verifiedKeys, isEmpty);
      expect(blocked.collection.entries.single.replacement, isTrue);
      expect(
        blocked.collection.entries.single.reference.objectId,
        'original-object',
      );
      final accepted = await service.refresh(
        blocked.collection,
        (_, _) => backend,
        acceptReplacements: true,
      );
      expect(accepted.verifiedKeys.length, 1);
      expect(
        accepted.collection.entries.single.reference.objectId,
        'new-object',
      );
    },
  );

  test(
    'a type-only replacement stays blocked after refresh and persistence',
    () async {
      final backend = _Backend()
        ..items['/same'] = FileItem(
          name: 'same',
          path: '/same',
          isFolder: true,
        );
      final original = FileCollectionService.capture(file('/same'), a);
      expect(original.reference.objectId, isNull);
      final blocked = await service.refresh(
        collection([original]),
        (_, _) => backend,
      );
      expect(blocked.verifiedKeys, isEmpty);
      expect(blocked.collection.entries.single.replacement, isTrue);
      expect(blocked.collection.entries.single.file, same(original.file));

      final repeated = await service.refresh(
        blocked.collection,
        (_, _) => backend,
      );
      expect(repeated.verifiedKeys, isEmpty);
      expect(repeated.collection.entries.single.replacement, isTrue);
      expect(repeated.collection.entries.single.file.isFolder, isFalse);

      final restored = FileCollection.fromJson(
        jsonDecode(jsonEncode(repeated.collection.toJson()))
            as Map<String, dynamic>,
      );
      final reopened = await service.refresh(restored, (_, _) => backend);
      expect(reopened.verifiedKeys, isEmpty);
      expect(reopened.collection.entries.single.replacement, isTrue);
      expect(reopened.collection.entries.single.file.isFolder, isFalse);

      final accepted = await service.refresh(
        reopened.collection,
        (_, _) => backend,
        acceptReplacements: true,
      );
      expect(accepted.verifiedKeys, {original.key});
      expect(accepted.collection.entries.single.file.isFolder, isTrue);
      expect(accepted.collection.entries.single.replacement, isFalse);
      expect(original.file.isFolder, isFalse);
    },
  );

  test('metadata changes are visible and path-valued provider IDs are not opaque identities', () async {
    final backend = _Backend()
      ..items['/same'] = file('/same', id: '/same', size: 9);
    final value = collection([
      FileCollectionService.capture(file('/same', id: '/same'), a),
    ]);
    expect(value.entries.single.reference.objectId, isNull);
    final result = await service.refresh(value, (_, _) => backend);
    expect(result.collection.entries.single.state, CollectionItemState.changed);
    expect(result.verifiedKeys.length, 1);
    expect(result.collection.entries.single.replacement, isFalse);
  });

  test(
    'refresh and rerun retain distinct semantics with a complete saved query',
    () async {
      final backend = _Backend()
        ..items['/root'] = FileItem(name: 'root', path: '/root', isFolder: true)
        ..items['/root/a.txt'] = file('/root/a.txt')
        ..items['/root/new.txt'] = file('/root/new.txt')
        ..items['/root/image.png'] = file('/root/image.png');
      final value = collection(
        [FileCollectionService.capture(file('/root/a.txt'), a)],
        search: const CollectionSearch(
          storage: a,
          directory: '/root',
          query: FileSearchQuery(namePattern: '*.txt', includeFolders: false),
        ),
      );
      final restored = FileCollection.fromJson(
        jsonDecode(jsonEncode(value.toJson())) as Map<String, dynamic>,
      );
      final refreshed = await service.refresh(restored, (_, _) => backend);
      expect(refreshed.collection.entries.length, 1);
      final rerun = await service.rerun(restored, (_, _) => backend);
      expect(rerun.collection.entries.map((entry) => entry.file.name).toSet(), {
        'a.txt',
        'new.txt',
      });
      expect(restored.entries.length, 1);
    },
  );

  test('folder moves rewrite saved descendants and marks only on their original account', () {
    final child = FileCollectionService.capture(file('/old/child.txt'), a);
    final other = FileCollectionService.capture(file('/old/child.txt'), b);
    final before = collection([child, other])
        .copyWith(selectedKeys: {child.key, other.key});
    final after = service.rewrite(before, a, {
      '/old': FileItem(name: 'new', path: '/new', isFolder: true),
    });
    expect(after.entries.map((entry) => entry.reference.path), [
      '/new/child.txt',
      '/old/child.txt',
    ]);
    expect(after.selectedKeys, after.entries.map((entry) => entry.key).toSet());
    final deleted = service.rewrite(
      after,
      a,
      {'/new': null},
      removedDirectories: {'/new'},
    );
    expect(deleted.entries.single.reference.storage, b);
    expect(before.entries.first.reference.path, '/old/child.txt');
  });

  test('cancellation leaves the saved collection intact', () async {
    final backend = _Backend()..items['/a'] = file('/a');
    final value = collection([FileCollectionService.capture(file('/a'), a)]);
    await expectLater(
      service.refresh(value, (_, _) => backend, isCancelled: () => true),
      throwsStateError,
    );
    expect(value.entries.single.state, CollectionItemState.ready);
  });

  test(
    'archive match evidence survives rerun and restart, and expires on change',
    () async {
      final bytes = ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile('one.txt', 6, 'needle'.codeUnits))
          ..addFile(ArchiveFile('sub/two.txt', 6, 'needle'.codeUnits)),
      );
      final backend = _Backend()
        ..items['/docs.zip'] = file('/docs.zip', size: bytes.length)
        ..content['/docs.zip'] = bytes;
      final value = collection(
        [],
        search: const CollectionSearch(
          storage: a,
          directory: '/',
          query: FileSearchQuery(
            searchArchives: true,
            contentPattern: 'needle',
            namePattern: '*.txt',
          ),
        ),
      );
      final result = await service.rerun(value, (_, _) => backend);
      final reopened = FileCollection.fromJson(
        jsonDecode(jsonEncode(result.collection.toJson()))
            as Map<String, dynamic>,
      );
      expect(reopened.entries, hasLength(1));
      expect(reopened.entries.single.file.metadata?['matchingArchiveMembers'], [
        'one.txt',
        'sub/two.txt',
      ]);
      final refreshed = await service.refresh(reopened, (_, _) => backend);
      expect(
        refreshed
            .collection
            .entries
            .single
            .file
            .metadata?['matchingArchiveMembers'],
        ['one.txt', 'sub/two.txt'],
      );
      backend.items['/docs.zip'] = file('/docs.zip', size: bytes.length + 1);
      final changed = await service.refresh(reopened, (_, _) => backend);
      expect(
        changed
            .collection
            .entries
            .single
            .file
            .metadata?['matchingArchiveMembers'],
        isNull,
      );
    },
  );

  test('malformed persisted collections are reported and preserved', () async {
    SharedPreferences.setMockInitialValues({
      'commander_collections_v1': ['broken'],
      'commander_collection_v1_broken': '{invalid',
    });
    final store = FileCollectionStore();
    await store.ready;
    expect(store.collections, isEmpty);
    expect(store.loadErrors.single, contains('broken'));
    expect(
      (await SharedPreferences.getInstance()).getString(
        'commander_collection_v1_broken',
      ),
      '{invalid',
    );
    store.dispose();
  });

  test(
    'persistent snapshots exclude arbitrary provider metadata and credentials',
    () {
      final entry = FileCollectionService.capture(
        file('/a').copyWith(
          metadata: {'access_token': 'never-persist-me', 'etag': 'version-1'},
        ),
        a,
      );
      final json = jsonEncode(entry.toJson());
      expect(json, isNot(contains('never-persist-me')));
      expect(json, contains('version-1'));
    },
  );
}

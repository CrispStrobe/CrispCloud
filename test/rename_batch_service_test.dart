import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/rename_batch.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:crisp_cloud/services/rename_batch_service.dart';
import 'package:crisp_cloud/services/rename_batch_store.dart';
import 'package:crisp_cloud/services/rename_batch_store_io.dart';
import 'package:crisp_cloud/services/rename_batch_store_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

FileItem item(String path, {bool folder = false, String? id}) => FileItem(
  name: p.posix.basename(path),
  path: path,
  isFolder: folder,
  uuid: id ?? 'object:$path',
  size: folder ? null : 3,
  updatedAt: DateTime.utc(2024, 1, 1),
);

class Storage extends RenameBatchStorage {
  Storage(
    Iterable<FileItem> values, {
    this.caseSensitivePaths = true,
    this.reference = const StorageReference(
      kind: 'local',
      provider: 'local',
      accountKey: 'test',
    ),
  }) {
    for (final value in values) {
      files[pathKey(value.path!)] = value;
    }
  }
  final Map<String, FileItem> files = {};
  final List<(String, String)> moves = [];
  bool current = true;
  FutureOr<void> Function(String, String)? afterMove;
  FutureOr<void> Function(String, String)? beforeMove;
  String? failStat;
  @override
  final StorageReference reference;
  @override
  final bool caseSensitivePaths;
  @override
  bool get exclusiveMoves => true;
  @override
  bool get isCurrent => current;
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) async {
    if (failStat == path) throw const FileSystemException('Permission denied');
    return files[pathKey(path)];
  }

  @override
  Future<void> move(FileItem source, String destination) async {
    final from = source.path!;
    await beforeMove?.call(from, destination);
    if (files.containsKey(pathKey(destination))) {
      throw StateError('Exclusive destination conflict.');
    }
    if (!files.containsKey(pathKey(from))) {
      throw StateError('Source disappeared.');
    }
    final moved = files.values
        .where(
          (file) =>
              pathKey(file.path!) == pathKey(from) ||
              (source.isFolder &&
                  paths.isWithin(pathKey(from), pathKey(file.path!))),
        )
        .toList();
    for (final file in moved) {
      files.remove(pathKey(file.path!));
    }
    for (final file in moved) {
      final path = file.path == from
          ? destination
          : paths.join(destination, paths.relative(file.path!, from: from));
      files[pathKey(path)] = file.copyWith(
        path: path,
        name: paths.basename(path),
      );
    }
    moves.add((from, destination));
    await afterMove?.call(from, destination);
  }
}

class FailingStore extends MemoryRenameBatchStore {
  bool reject = false;
  FutureOr<void> Function(RenameBatchRecord)? onSave;
  @override
  Future<void> save(RenameBatchRecord record) async {
    if (reject) throw StateError('Disk full');
    await super.save(record);
    await onSave?.call(record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const planner = MultiRenameService();
  MultiRenamePlan plan(
    Storage storage,
    Map<String, String> names, {
    List<FileItem>? selection,
  }) => planner.preview(
    selection ?? storage.files.values.toList(),
    const MultiRenameOptions(),
    directory: '/',
    targetNames: names,
    allowDependencies: true,
    caseSensitivePaths: storage.caseSensitivePaths,
  );

  group('dependency execution and batch restore', () {
    test('swaps preserve each object and restore the whole cycle', () async {
      final storage = Storage([item('/a.txt'), item('/b.txt')]);
      final store = MemoryRenameBatchStore();
      final service = RenameBatchService(store);
      final record = await service.prepare(
        plan(storage, {'/a.txt': 'b.txt', '/b.txt': 'a.txt'}),
        storage,
      );
      expect(record.steps, hasLength(4));
      await service.run(record, storage);
      expect(record.state, RenameBatchState.completed);
      expect(storage.files['/b.txt']!.uuid, 'object:/a.txt');
      expect(storage.files['/a.txt']!.uuid, 'object:/b.txt');
      await service.restore(record, storage);
      expect(record.state, RenameBatchState.restored);
      expect(storage.files['/a.txt']!.uuid, 'object:/a.txt');
      expect(storage.files['/b.txt']!.uuid, 'object:/b.txt');
      expect(
        storage.files.keys.any((key) => key.contains('.crisp-rename')),
        isFalse,
      );
    });

    test('case-only names are staged on case-insensitive storage', () async {
      final storage = Storage([item('/a.txt')], caseSensitivePaths: false);
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(
        plan(storage, {'/a.txt': 'A.TXT'}),
        storage,
      );
      await service.run(record, storage);
      expect(record.isComplete, isTrue);
      expect(storage.files.values.single.name, 'A.TXT');
      expect(storage.moves, hasLength(2));
      await service.restore(record, storage);
      expect(storage.files.values.single.name, 'a.txt');
    });

    test(
      'nested parents and children use current paths at every step',
      () async {
        final storage = Storage([
          item('/a', folder: true),
          item('/a/b', folder: true),
          item('/a/b/c.txt'),
          item('/a/untouched.txt'),
        ]);
        final selection = storage.files.values
            .where((file) => file.name != 'untouched.txt')
            .toList();
        final service = RenameBatchService(MemoryRenameBatchStore());
        final record = await service.prepare(
          plan(storage, {
            '/a': 'renamed',
            '/a/b': 'sub',
            '/a/b/c.txt': 'done.txt',
          }, selection: selection),
          storage,
        );
        await service.run(record, storage);
        expect(record.state, RenameBatchState.completed);
        expect(
          storage.files.keys,
          containsAll([
            '/renamed',
            '/renamed/sub',
            '/renamed/sub/done.txt',
            '/renamed/untouched.txt',
          ]),
        );
        expect(
          RenameBatchService.changes(record)['/a/b/c.txt']!.path,
          '/renamed/sub/done.txt',
        );
        await service.restore(record, storage);
        expect(
          storage.files.keys,
          containsAll(['/a', '/a/b', '/a/b/c.txt', '/a/untouched.txt']),
        );
      },
    );

    test('unchanged selected child follows parent and is reported', () async {
      final storage = Storage([item('/a', folder: true), item('/a/c.txt')]);
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(plan(storage, {'/a': 'b'}), storage);
      await service.run(record, storage);
      expect(RenameBatchService.changes(record)['/a/c.txt']!.path, '/b/c.txt');
      await service.restore(record, storage);
      expect(
        RenameBatchService.changes(
          record,
          sinceTargets: true,
        )['/b/c.txt']!.path,
        '/a/c.txt',
      );
    });

    test('batch undo keeps every item beyond the action menu limit', () async {
      final storage = Storage([for (var i = 0; i < 130; i++) item('/$i.txt')]);
      final store = MemoryRenameBatchStore();
      final service = RenameBatchService(store);
      final record = await service.prepare(
        plan(storage, {
          for (var i = 0; i < 130; i++) '/$i.txt': '${i}_new.txt',
        }),
        storage,
      );
      await service.run(record, storage);
      final reopened = await store.read(record.id);
      expect(reopened!.items, hasLength(130));
      await service.restore(reopened, storage);
      expect(reopened.isRestored, isTrue);
      expect(storage.files.keys, everyElement(isNot(contains('_new'))));
    });
  });

  group('preconditions and collision safety', () {
    test('serialized fingerprints compare timestamp instants across time-zone representations', () {
      final fingerprint = RenameFingerprint(
        folder: false,
        size: 3,
        modified: DateTime(2024, 1, 1),
      );
      final reopened = RenameFingerprint.fromJson(fingerprint.toJson());
      expect(reopened.modified!.isUtc, isTrue);
      expect(fingerprint.matches(reopened), isTrue);
    });
    test('path-valued adapter UUIDs cannot certify an interrupted rename', () {
      final before = RenameFingerprint.fromFile(item('/a', id: '/a'));
      final after = RenameFingerprint.fromFile(item('/b', id: '/b'));
      expect(before.objectId, isNull);
      expect(after.objectId, isNull);
      expect(before.canReconcile, isFalse);
      expect(before.matches(after, afterMove: true), isTrue);
    });
    test(
      'external occupied targets stop the entire batch before mutation',
      () async {
        final storage = Storage([item('/a'), item('/b'), item('/occupied')]);
        final service = RenameBatchService(MemoryRenameBatchStore());
        await expectLater(
          service.prepare(
            plan(
              storage,
              {'/a': 'new', '/b': 'occupied'},
              selection: [storage.files['/a']!, storage.files['/b']!],
            ),
            storage,
          ),
          throwsA(isA<MultiRenamePreflightException>()),
        );
        expect(storage.moves, isEmpty);
      },
    );

    test(
      'permission failure is never treated as a vacant destination',
      () async {
        final storage = Storage([item('/a')])..failStat = '/new';
        await expectLater(
          RenameBatchService(MemoryRenameBatchStore())
              .prepare(plan(storage, {'/a': 'new'}), storage),
          throwsA(isA<FileSystemException>()),
        );
        expect(storage.moves, isEmpty);
      },
    );

    test('source replacement after preview prevents writes', () async {
      final storage = Storage([item('/a')]);
      final preview = plan(storage, {'/a': 'new'});
      storage.files['/a'] = item('/a', id: 'replacement');
      await expectLater(
        RenameBatchService(MemoryRenameBatchStore()).prepare(preview, storage),
        throwsA(isA<MultiRenamePreflightException>()),
      );
      expect(storage.moves, isEmpty);
    });

    test('source replacement after preparation is not renamed', () async {
      final storage = Storage([item('/a')]);
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(
        plan(storage, {'/a': 'new'}),
        storage,
      );
      storage.files['/a'] = item('/a', id: 'replacement');
      await service.run(record, storage);
      expect(record.state, RenameBatchState.failed);
      expect(storage.moves, isEmpty);
    });

    test('a racing destination is protected by the actual mutation', () async {
      final storage = Storage([item('/a')]);
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(
        plan(storage, {'/a': 'new'}),
        storage,
      );
      storage.beforeMove = (_, to) {
        storage.files[to] = item(to, id: 'racer');
      };
      await service.run(record, storage);
      expect(record.state, RenameBatchState.needsReview);
      expect(storage.files['/new']!.uuid, 'racer');
      expect(storage.files['/a']!.uuid, 'object:/a');
      expect(storage.moves, isEmpty);
    });

    test(
      'restore preflights every original name before changing any item',
      () async {
        final storage = Storage([item('/a'), item('/b')]);
        final service = RenameBatchService(MemoryRenameBatchStore());
        final record = await service.prepare(
          plan(storage, {'/a': 'new_a', '/b': 'new_b'}),
          storage,
        );
        await service.run(record, storage);
        storage.files['/a'] = item('/a', id: 'unrelated');
        await expectLater(
          service.restore(record, storage),
          throwsA(isA<MultiRenamePreflightException>()),
        );
        expect(storage.files, contains('/new_b'));
        expect(storage.moves, hasLength(2));
      },
    );

    test('recovery cannot use another account with the same paths', () async {
      final first = Storage([item('/a')]);
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(plan(first, {'/a': 'new'}), first);
      final second = Storage(
        [item('/a')],
        reference: const StorageReference(
          kind: 'remote',
          provider: 'cloud',
          accountKey: 'other',
        ),
      );
      await expectLater(service.run(record, second), throwsStateError);
      expect(second.moves, isEmpty);
    });
  });

  group('interruption journal', () {
    test(
      'cancellation during staging persists exact paths for restart resume',
      () async {
        final storage = Storage([item('/a'), item('/b')]);
        final store = MemoryRenameBatchStore();
        final service = RenameBatchService(store);
        final record = await service.prepare(
          plan(storage, {'/a': 'b', '/b': 'a'}),
          storage,
        );
        var cancelled = false;
        storage.afterMove = (_, _) {
          cancelled = true;
        };
        await service.run(record, storage, isCancelled: () => cancelled);
        expect(record.state, RenameBatchState.paused);
        expect(record.items.first.currentPath, contains('.crisp-rename'));
        storage.afterMove = null;
        final reopened = (await store.read(record.id))!;
        await RenameBatchService(store).run(reopened, storage);
        expect(reopened.isComplete, isTrue);
        expect(storage.files['/b']!.uuid, 'object:/a');
      },
    );

    test(
      'partially staged batch can restore without finishing forward plan',
      () async {
        final storage = Storage([item('/a'), item('/b')]);
        final service = RenameBatchService(MemoryRenameBatchStore());
        final record = await service.prepare(
          plan(storage, {'/a': 'b', '/b': 'a'}),
          storage,
        );
        await service.run(
          record,
          storage,
          isCancelled: () => storage.moves.length == 1,
        );
        await service.restore(record, storage);
        expect(record.isRestored, isTrue);
        expect(storage.files['/a']!.uuid, 'object:/a');
        expect(storage.files['/b']!.uuid, 'object:/b');
      },
    );

    test(
      'failure to save write-ahead intent makes no filesystem change',
      () async {
        final storage = Storage([item('/a')]);
        final store = FailingStore();
        final service = RenameBatchService(store);
        final record = await service.prepare(
          plan(storage, {'/a': 'b'}),
          storage,
        );
        store.reject = true;
        await expectLater(
          service.run(record, storage),
          throwsA(isA<RenameBatchPersistenceException>()),
        );
        expect(storage.moves, isEmpty);
      },
    );

    test('rename committed before journal acknowledgement is reconciled by object identity', () async {
      final storage = Storage([item('/a')]);
      final store = FailingStore();
      final service = RenameBatchService(store);
      final record = await service.prepare(plan(storage, {'/a': 'b'}), storage);
      storage.afterMove = (_, _) {
        store.reject = true;
      };
      await expectLater(
        service.run(record, storage),
        throwsA(isA<RenameBatchPersistenceException>()),
      );
      final persisted = (await store.read(record.id))!;
      expect(persisted.steps.single.state, RenameStepState.inFlight);
      store.reject = false;
      storage.afterMove = null;
      await RenameBatchService(store).run(persisted, storage);
      expect(persisted.isComplete, isTrue);
      expect(storage.moves, hasLength(1));
      expect(persisted.items.single.currentPath, '/b');
    });

    test('provider error after confirmed movement is reconciled without repeating it', () async {
      final storage = Storage([item('/a')]);
      final service = RenameBatchService(MemoryRenameBatchStore());
      final record = await service.prepare(plan(storage, {'/a': 'b'}), storage);
      storage.afterMove = (_, _) {
        throw StateError('Connection interrupted after commit');
      };
      await service.run(record, storage);
      expect(record.isComplete, isTrue);
      expect(storage.moves, hasLength(1));
    });

    test(
      'weak metadata never certifies an ambiguous interrupted write',
      () async {
        final weak = FileItem(name: 'a', path: '/a', isFolder: false, size: 3);
        final storage = Storage([weak]);
        final store = FailingStore();
        final service = RenameBatchService(store);
        final record = await service.prepare(
          plan(storage, {'/a': 'b'}),
          storage,
        );
        storage.afterMove = (_, _) {
          store.reject = true;
        };
        await expectLater(
          service.run(record, storage),
          throwsA(isA<RenameBatchPersistenceException>()),
        );
        store.reject = false;
        storage.afterMove = null;
        final persisted = (await store.read(record.id))!;
        await service.run(persisted, storage);
        expect(persisted.state, RenameBatchState.needsReview);
        expect(storage.moves, hasLength(1));
        await service.acknowledgeObservedDestination(persisted, storage);
        expect(persisted.manualResolutions, hasLength(1));
        await service.run(persisted, storage);
        expect(persisted.isComplete, isTrue);
        expect(storage.moves, hasLength(1));
      },
    );

    test(
      'all journals exclude raw provider metadata and credentials',
      () async {
        final file = item('/a').copyWith(
          metadata: {
            'token': 'secret-token',
            'authorization': 'secret-header',
            'version': 'v1',
          },
        );
        final storage = Storage([file]);
        final record = await RenameBatchService(MemoryRenameBatchStore())
            .prepare(plan(storage, {'/a': 'b'}), storage);
        final encoded = encodeRenameBatch(record);
        expect(encoded, isNot(contains('secret')));
        expect(encoded, contains('v1'));
        expect(
          decodeRenameBatch(encoded).items.single.fingerprint.version,
          'v1',
        );
      },
    );

    test(
      'independent continue-on-error reports failed items and retries later',
      () async {
        final storage = Storage([item('/a'), item('/b')]);
        final service = RenameBatchService(MemoryRenameBatchStore());
        final record = await service.prepare(
          plan(storage, {'/a': 'new_a', '/b': 'new_b'}),
          storage,
        );
        storage.beforeMove = (from, _) {
          if (from == '/a') throw StateError('Read only');
        };
        await service.run(record, storage, continueOnError: true);
        expect(record.state, RenameBatchState.failed);
        expect(storage.files, contains('/a'));
        expect(storage.files, contains('/new_b'));
        storage.beforeMove = null;
        await service.run(record, storage);
        expect(record.isComplete, isTrue);
      },
    );
  });

  group('native durable store', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('rename-journal-');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('flush/replacement round-trips and leaves no pending file', () async {
      final store = NativeRenameBatchStore(directory: () async => directory);
      final storage = Storage([item('/a')]);
      final record = await RenameBatchService(store)
          .prepare(plan(storage, {'/a': 'b'}), storage);
      record.state = RenameBatchState.paused;
      await store.save(record);
      expect((await store.read(record.id))!.state, RenameBatchState.paused);
      expect(
        (await directory.list().toList()).where(
          (entry) => entry.path.endsWith('.pending'),
        ),
        isEmpty,
      );
      await store.remove(record.id);
      expect(await store.list(), isEmpty);
    });

    test(
      'checksum detects corruption without deleting the recoverable record',
      () async {
        final store = NativeRenameBatchStore(directory: () async => directory);
        final storage = Storage([item('/a')]);
        final record = await RenameBatchService(store)
            .prepare(plan(storage, {'/a': 'b'}), storage);
        final file = File(p.join(directory.path, '${record.id}.json'));
        final value =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        value['payload'] = (value['payload'] as String).replaceFirst(
          '/a',
          '/x',
        );
        await file.writeAsString(jsonEncode(value));
        await expectLater(store.read(record.id), throwsFormatException);
        expect(await file.exists(), isTrue);
        expect(await store.list(), isEmpty);
        expect(store.warnings.single, contains('checksum'));
      },
    );

    test('path traversal identifiers never reach the filesystem', () async {
      final store = NativeRenameBatchStore(directory: () async => directory);
      await expectLater(store.read('../other'), throwsFormatException);
    });
  });

  test(
    'browser journals survive a new store instance without raw secrets',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = BrowserRenameBatchStore();
      final storage = Storage([item('/a')]);
      final record = await RenameBatchService(store)
          .prepare(plan(storage, {'/a': 'b'}), storage);
      await RenameBatchService(store).run(record, storage);
      final restarted = BrowserRenameBatchStore();
      expect((await restarted.list()).single.isComplete, isTrue);
      await RenameBatchService(restarted)
          .restore((await restarted.read(record.id))!, storage);
      expect(storage.files, contains('/a'));
      await restarted.remove(record.id);
      expect(await restarted.list(), isEmpty);
    },
  );
}

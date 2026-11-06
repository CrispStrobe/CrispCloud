import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';

import 'support/sync_test_binding.dart';
import 'support/workflow_fake_client.dart';

/// Models providers without a content hash. Their size and timestamps can
/// remain unchanged when a different application rewrites a file in place.
class _ContentClient extends WorkflowFakeClient {
  final reads = <String>[];
  Future<void> Function(String)? beforeRead;
  String account = 'account-a';
  @override
  String get userId => account;

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final listing = await super.listPath(path);
    for (final file in listing['files'] as List) {
      (file as Map).remove('content_hash');
    }
    return listing;
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) => throw StateError('Content comparison must use bounded streams.');

  @override
  Stream<List<int>> downloadStream(
    String path, {
    Function(int, int)? onProgress,
  }) async* {
    reads.add(path);
    await beforeRead?.call(path);
    final data = files[path] ?? (throw StateError('Missing $path'));
    for (var offset = 0; offset < data.length; offset += 64 * 1024) {
      yield Uint8List.sublistView(
        data,
        offset,
        (offset + 64 * 1024).clamp(0, data.length),
      );
    }
  }
}

void main() {
  late Directory local;
  late SyncDatabase database;
  late _ContentClient cloud;
  late SyncPair pair;
  late SyncEngine engine;
  final timestamp = DateTime.utc(2026, 1, 1, 12);

  setUp(() async {
    local = await Directory.systemTemp.createTemp('sync-contents-');
    database = SyncDatabase.forTesting(NativeDatabase.memory());
    cloud = _ContentClient()..directories.add('/docs');
    pair = await database.getPair(
      await database.insertPair(
        SyncPairsCompanion.insert(
          name: 'Content comparison',
          localPath: local.path,
          remotePath: '/docs',
          provider: 'fixture',
          conflictPolicy: const Value('manual'),
        ),
      ),
    );
    pair = await bindTestPair(database, pair, cloud);
    engine = SyncEngine(database);
  });
  tearDown(() async {
    await database.close();
    await local.delete(recursive: true);
  });

  Future<File> localContents(String name, String contents) async {
    final file = await File(p.join(local.path, name)).writeAsString(contents);
    await file.setLastModified(timestamp);
    return file;
  }

  Future<File> synced(String name, String contents) async {
    final file = await localContents(name, contents);
    cloud.put('/docs/$name', contents.codeUnits, date: timestamp);
    final result = await engine.syncPair(pair, cloud);
    expect(result.errors, 0, reason: result.errorMessages.join('\n'));
    return file;
  }

  Future<void> configure({
    String? policy,
    String? direction,
    String? exclude,
  }) async {
    await (database.update(
      database.syncPairs,
    )..where((row) => row.id.equals(pair.id))).write(
      SyncPairsCompanion(
        conflictPolicy: policy == null ? const Value.absent() : Value(policy),
        direction: direction == null ? const Value.absent() : Value(direction),
        excludePatterns: exclude == null
            ? const Value.absent()
            : Value(exclude),
      ),
    );
    pair = await database.getPair(pair.id);
  }

  test(
    'full content review finds a local edit with unchanged size and time',
    () async {
      await synced('file.txt', 'base');
      await localContents('file.txt', 'edit');
      expect((await engine.planPair(pair, cloud)).actions, isEmpty);
      final plan = await engine.planPair(pair, cloud, compareContents: true);
      expect(plan.compareContents, isTrue);
      expect(plan.actions.single.type, SyncActionType.upload);
      expect(cloud.files['/docs/file.txt'], 'base'.codeUnits);
      final result = await engine.executePlan(plan);
      expect(result.errors, 0, reason: result.errorMessages.join('\n'));
      expect(result.uploaded, 1);
      expect(cloud.files['/docs/file.txt'], 'edit'.codeUnits);
    },
  );

  test(
    'full content review finds a remote edit without provider hashes',
    () async {
      final file = await synced('file.txt', 'base');
      cloud.put('/docs/file.txt', 'edit'.codeUnits, date: timestamp);
      expect((await engine.planPair(pair, cloud)).actions, isEmpty);
      final plan = await engine.planPair(pair, cloud, compareContents: true);
      expect(plan.actions.single.type, SyncActionType.download);
      final result = await engine.executePlan(plan);
      expect(result.errors, 0, reason: result.errorMessages.join('\n'));
      expect(result.downloaded, 1);
      expect(await file.readAsString(), 'edit');
    },
  );

  for (final unknownBaseline in [false, true]) {
    test(
      'different bytes with ${unknownBaseline ? "an unknown baseline" : "tied newest timestamps"} need an explicit choice',
      () async {
        await synced('file.txt', 'base');
        await configure(policy: 'newestWins');
        if (unknownBaseline) {
          await database.upsertEntry(
            SyncEntriesCompanion.insert(
              pairId: pair.id,
              relativePath: 'file.txt',
              localHash: const Value(null),
            ),
          );
        }
        await localContents('file.txt', 'left');
        cloud.put('/docs/file.txt', 'rght'.codeUnits, date: timestamp);
        final plan = await engine.planPair(pair, cloud, compareContents: true);
        expect(plan.actions.single.type, SyncActionType.conflict);
        expect(
          plan.choicesFor(plan.actions.single),
          containsAll([
            SyncActionType.skip,
            SyncActionType.upload,
            SyncActionType.download,
            SyncActionType.keepBoth,
          ]),
        );
        final result = await engine.executePlan(plan);
        expect(result.conflicts, 1);
        expect(cloud.writes, isEmpty);
        expect(cloud.files['/docs/file.txt'], 'rght'.codeUnits);
        expect(
          await File(p.join(local.path, 'file.txt')).readAsString(),
          'left',
        );
      },
    );
  }

  for (final deletedLocal in [false, true]) {
    test(
      'a ${deletedLocal ? "cloud" : "local"} content edit prevents propagation of the opposite deletion',
      () async {
        final file = await synced('file.txt', 'base');
        if (deletedLocal) {
          await file.delete();
          cloud.put('/docs/file.txt', 'edit'.codeUnits, date: timestamp);
        } else {
          await cloud.deletePath('/docs/file.txt');
          await localContents('file.txt', 'edit');
        }
        final fast = await engine.planPair(pair, cloud);
        expect(
          fast.actions.single.type,
          deletedLocal
              ? SyncActionType.deleteRemote
              : SyncActionType.deleteLocal,
        );
        final plan = await engine.planPair(pair, cloud, compareContents: true);
        expect(plan.actions.single.type, SyncActionType.conflict);
        final result = await engine.executePlan(plan);
        expect(result.conflicts, 1);
        if (deletedLocal) {
          expect(cloud.files['/docs/file.txt'], 'edit'.codeUnits);
        } else {
          expect(await file.readAsString(), 'edit');
        }
      },
    );
  }

  test('content changes in an equal reviewed row invalidate the entire plan before writing', () async {
    await synced('first.txt', 'aaaa');
    await synced('second.txt', '2222');
    await localContents('first.txt', 'bbbb');
    final plan = await engine.planPair(pair, cloud, compareContents: true);
    expect(plan.actions.single.relativePath, 'first.txt');
    cloud.put('/docs/second.txt', '3333'.codeUnits, date: timestamp);
    final result = await engine.executePlan(plan);
    expect(result.errors, 1);
    expect(result.errorMessages.single, contains('contents changed'));
    expect(cloud.writes, isEmpty);
    expect(cloud.files['/docs/first.txt'], 'aaaa'.codeUnits);
  });

  test('one-way reviews expose unequal receiving-side bytes without offering the forbidden direction', () async {
    await synced('file.txt', 'base');
    await configure(direction: 'uploadOnly');
    cloud.put('/docs/file.txt', 'edit'.codeUnits, date: timestamp);
    final plan = await engine.planPair(pair, cloud, compareContents: true);
    expect(plan.actions.single.type, SyncActionType.conflict);
    expect(
      plan.choicesFor(plan.actions.single),
      contains(SyncActionType.upload),
    );
    expect(
      plan.choicesFor(plan.actions.single),
      isNot(contains(SyncActionType.download)),
    );
  });

  test('content scanning respects filters and records equal baselines only when applied', () async {
    await localContents('keep.txt', 'same');
    await localContents('skip.txt', 'left');
    cloud.put('/docs/keep.txt', 'same'.codeUnits, date: timestamp);
    cloud.put('/docs/skip.txt', 'rght'.codeUnits, date: timestamp);
    await configure(exclude: 'skip.txt');
    final progress = <(int, int, String)>[];
    final plan = await engine.planPair(
      pair,
      cloud,
      compareContents: true,
      onCompareProgress: (done, total, path) =>
          progress.add((done, total, path)),
    );
    expect(plan.actions, isEmpty);
    expect(cloud.reads, ['/docs/keep.txt']);
    expect(progress.last, (2, 2, 'keep.txt'));
    expect(await database.getEntriesForPair(pair.id), isEmpty);
    final result = await engine.executePlan(plan);
    expect(result.errors, 0);
    expect(
      (await database.getEntriesForPair(pair.id)).single.localHash,
      hasLength(64),
    );
    expect(cloud.writes, isEmpty);
  });

  test('full comparison remains cancellable while an otherwise unchanged source stalls', () async {
    await synced('file.txt', 'base');
    final entered = Completer<void>(), release = Completer<void>();
    cloud.beforeRead = (_) async {
      entered.complete();
      await release.future;
    };
    var cancelled = false;
    final pending = engine.planPair(
      pair,
      cloud,
      compareContents: true,
      isCancelled: () => cancelled,
    );
    await entered.future;
    cancelled = true;
    try {
      await expectLater(
        pending.timeout(const Duration(seconds: 2)),
        throwsA(isA<SyncCancelledException>()),
      );
    } finally {
      release.complete();
    }
    expect(cloud.writes, isEmpty);
  });

  test('rebinding during a full scan invalidates the comparison', () async {
    await synced('file.txt', 'base');
    cloud.beforeRead = (_) async {
      cloud.beforeRead = null;
      await bindTestPair(database, pair, cloud);
    };
    await expectLater(
      engine.planPair(pair, cloud, compareContents: true),
      throwsStateError,
    );
    expect(cloud.writes, isEmpty);
  });

  test(
    'changing account during a full scan cannot return a usable plan',
    () async {
      await synced('file.txt', 'base');
      cloud.beforeRead = (_) async => cloud.account = 'account-b';
      await expectLater(
        engine.planPair(pair, cloud, compareContents: true),
        throwsStateError,
      );
      expect(cloud.writes, isEmpty);
    },
  );
}

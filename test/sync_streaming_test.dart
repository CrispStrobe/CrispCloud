import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/services/sync_offline_service.dart';
import 'package:crisp_cloud/services/placeholder_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';

import 'support/workflow_fake_client.dart';
import 'support/sync_test_binding.dart';

/// Whole-file compatibility calls deliberately fail: these tests exercise the
/// actual sync workflow rather than a copy helper disconnected from the UI.
class _StreamOnlyClient extends WorkflowFakeClient {
  Future<void> Function(String path)? beforeUpload;
  Future<void> Function(String path, int read)? beforeRead;
  final reads = <String, int>{};
  int largestInputChunk = 0;
  int? failRead;
  bool sourceClosed = false;

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) => throw StateError('Sync must not buffer a complete download.');
  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String path, {
    Function(int, int)? onProgress,
  }) => throw StateError('Sync must use the streaming upload contract.');

  @override
  Stream<List<int>> downloadStream(
    String path, {
    Function(int, int)? onProgress,
  }) async* {
    final count = reads.update(path, (value) => value + 1, ifAbsent: () => 1);
    await beforeRead?.call(path, count);
    final bytes = files[path] ?? (throw StateError('Missing $path'));
    try {
      for (var offset = 0; offset < bytes.length; offset += 64 * 1024) {
        yield Uint8List.sublistView(
          bytes,
          offset,
          (offset + 64 * 1024).clamp(0, bytes.length),
        );
        if (count == failRead) throw StateError('Interrupted source stream');
      }
    } finally {
      sourceClosed = true;
    }
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> input,
    int length,
    String name,
    String path, {
    Function(int, int)? onProgress,
  }) async {
    final target = p.posix.join(path, name);
    await beforeUpload?.call(target);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in input) {
      if (chunk.length > largestInputChunk) largestInputChunk = chunk.length;
      bytes.add(chunk);
    }
    expect(bytes.length, length);
    writes.add(target);
    put(target, bytes.takeBytes(), date: DateTime.now());
  }
}

void main() {
  late Directory local;
  late SyncDatabase database;
  late _StreamOnlyClient cloud;
  late SyncPair pair;
  late TransferJournal journal;
  late SyncEngine engine;
  setUp(() async {
    local = await Directory.systemTemp.createTemp('sync-stream-');
    database = SyncDatabase.forTesting(NativeDatabase.memory());
    cloud = _StreamOnlyClient()..directories.add('/docs');
    pair = await database.getPair(
      await database.insertPair(
        SyncPairsCompanion.insert(
          name: 'Streamed sync',
          localPath: local.path,
          remotePath: '/docs',
          provider: 'sftp',
          conflictPolicy: const Value('manual'),
        ),
      ),
    );
    pair = await bindTestPair(database, pair, cloud);
    journal = TransferJournal(MemoryTransferJournalStorage());
    engine = SyncEngine(database, journal: journal);
  });
  tearDown(() async {
    await database.close();
    await local.delete(recursive: true);
  });

  test(
    'sync uploads a file beyond the legacy upload ceiling in bounded chunks',
    () async {
      final file = File(p.join(local.path, 'large.bin'));
      final output = file.openWrite();
      final block = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 7);
      for (var i = 0; i < 528; i++) {
        output.add(block);
      }
      await output.close();
      final result = await engine.syncPair(pair, cloud);
      expect(result.errors, 0, reason: result.errorMessages.join('\n'));
      expect(result.uploaded, 1);
      expect(cloud.files['/docs/large.bin']!.length, 33 * 1024 * 1024);
      expect(cloud.largestInputChunk, lessThanOrEqualTo(64 * 1024));
      expect(journal.jobs.single.status, TransferJobStatus.completed);
      expect(
        journal.jobs.single.entries.single.recovery['dataVerified'],
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('download streams and replaces only after verification', () async {
    await File(p.join(local.path, 'file.txt')).writeAsString('original');
    cloud.put('/docs/file.txt', 'replacement'.codeUnits);
    final plan = await engine.planPair(pair, cloud);
    final result = await engine.executePlan(
      plan,
      decisions: {'file.txt': SyncActionType.download},
    );
    expect(result.errors, 0, reason: result.errorMessages.join('\n'));
    expect(
      await File(p.join(local.path, 'file.txt')).readAsString(),
      'replacement',
    );
    expect(journal.jobs.single.status, TransferJobStatus.completed);
  });

  test(
    'private transfer recovery artifacts are never synchronized as files',
    () async {
      cloud.put(
        '/docs/.crisp-transfer-11111111-1111-4111-8111-111111111111.tmp',
        'stage'.codeUnits,
      );
      cloud.put(
        '/docs/.crisp-replaced-11111111-1111-4111-8111-111111111111.bak',
        'backup'.codeUnits,
      );
      cloud.put('/docs/user.txt', 'content'.codeUnits);
      final result = await engine.syncPair(pair, cloud);
      expect(result.errors, 0);
      expect(result.downloaded, 1);
      expect(await local.list().map((item) => p.basename(item.path)).toList(), [
        'user.txt',
      ]);
      expect(cloud.files, hasLength(3));
    },
  );

  test('interruption during the staged download retains the original and closes input', () async {
    await File(p.join(local.path, 'file.txt')).writeAsString('original');
    cloud.put('/docs/file.txt', List.filled(128 * 1024, 7));
    final plan = await engine.planPair(pair, cloud);
    // Plan hash, initial revalidation, per-row hash, source validation, then
    // the stream feeding the private destination stage.
    cloud.failRead = 5;
    final result = await engine.executePlan(
      plan,
      decisions: {'file.txt': SyncActionType.download},
    );
    expect(result.errors, 1);
    expect(
      await File(p.join(local.path, 'file.txt')).readAsString(),
      'original',
    );
    expect(cloud.sourceClosed, isTrue);
    expect(journal.jobs.single.status, TransferJobStatus.failed);
    expect(await local.list().map((item) => p.basename(item.path)).toList(), [
      'file.txt',
    ]);
  });

  test(
    'a later reviewed row changed during the first copy is not overwritten',
    () async {
      for (final name in ['a.txt', 'b.txt']) {
        await File(p.join(local.path, name)).writeAsString('local');
        cloud.put('/docs/$name', 'older'.codeUnits);
      }
      final plan = await engine.planPair(pair, cloud);
      final result = await engine.executePlan(
        plan,
        decisions: {
          'a.txt': SyncActionType.upload,
          'b.txt': SyncActionType.upload,
        },
        onProgress: (done, total, path) {
          if (path == 'a.txt') cloud.put('/docs/b.txt', 'other'.codeUnits);
        },
      );
      expect(result.uploaded, 1);
      expect(result.errors, 1);
      expect(String.fromCharCodes(cloud.files['/docs/a.txt']!), 'local');
      expect(String.fromCharCodes(cloud.files['/docs/b.txt']!), 'other');
    },
  );

  test(
    'same-size destination edit during upload is retained before commit',
    () async {
      await File(p.join(local.path, 'file.txt')).writeAsString('local');
      cloud.put('/docs/file.txt', 'older'.codeUnits);
      final plan = await engine.planPair(pair, cloud);
      cloud.beforeUpload = (_) async =>
          cloud.put('/docs/file.txt', 'other'.codeUnits);
      final result = await engine.executePlan(
        plan,
        decisions: {'file.txt': SyncActionType.upload},
      );
      expect(result.errors, 1);
      expect(String.fromCharCodes(cloud.files['/docs/file.txt']!), 'other');
      expect(cloud.files.keys, ['/docs/file.txt']);
    },
  );

  test(
    'keep both streams both versions and journals each verified copy',
    () async {
      await File(p.join(local.path, 'file.txt')).writeAsString('local');
      cloud.put('/docs/file.txt', 'cloud'.codeUnits);
      final plan = await engine.planPair(pair, cloud);
      final result = await engine.executePlan(
        plan,
        decisions: {'file.txt': SyncActionType.keepBoth},
      );
      expect(result.errors, 0, reason: result.errorMessages.join('\n'));
      expect(
        await File(p.join(local.path, 'file.txt')).readAsString(),
        'cloud',
      );
      expect(
        await File(p.join(local.path, 'file (local conflict).txt'))
            .readAsString(),
        'local',
      );
      expect(
        String.fromCharCodes(cloud.files['/docs/file (local conflict).txt']!),
        'local',
      );
      expect(journal.jobs, hasLength(3));
      expect(
        journal.jobs.every((job) => job.status == TransferJobStatus.completed),
        isTrue,
      );
    },
  );

  test('cancellation after input is consumed blocks the commit', () async {
    await File(p.join(local.path, 'file.txt')).writeAsString('local');
    cloud.put('/docs/file.txt', 'older'.codeUnits);
    final plan = await engine.planPair(pair, cloud);
    var cancel = false;
    cloud.beforeRead = (path, _) async {
      if (p.posix.basename(path).startsWith('.crisp-transfer-')) cancel = true;
    };
    final result = await engine.executePlan(
      plan,
      decisions: {'file.txt': SyncActionType.upload},
      isCancelled: () => cancel,
    );
    expect(result.cancelled, isTrue);
    expect(String.fromCharCodes(cloud.files['/docs/file.txt']!), 'older');
    expect(await File(p.join(local.path, 'file.txt')).readAsString(), 'local');
    expect(journal.jobs.single.status, TransferJobStatus.cancelled);
  });

  test(
    'cloud-only placeholders never propagate a false local deletion',
    () async {
      await (database.update(database.syncPairs)
            ..where((t) => t.id.equals(pair.id)))
          .write(const SyncPairsCompanion(usePlaceholders: Value(true)));
      pair = await database.getPair(pair.id);
      cloud.put('/docs/cloud.txt', 'cloud'.codeUnits);
      final first = await engine.syncPair(pair, cloud);
      expect(first.errors, 0);
      expect(
        await File(p.join(local.path, 'cloud.txt.crispcloud')).exists(),
        isTrue,
      );
      final second = await engine.syncPair(pair, cloud);
      expect(second.errors, 0);
      expect(second.deletedRemote, 0);
      expect(String.fromCharCodes(cloud.files['/docs/cloud.txt']!), 'cloud');

      final service = PlaceholderService(database, journal: journal);
      await service.hydrate(
        pairId: pair.id,
        localBasePath: local.path,
        relativePath: 'cloud.txt',
        client: cloud,
      );
      expect(
        await File(p.join(local.path, 'cloud.txt')).readAsString(),
        'cloud',
      );
      expect(
        await File(p.join(local.path, 'cloud.txt.crispcloud')).exists(),
        isFalse,
      );
      expect(journal.jobs.single.status, TransferJobStatus.completed);
    },
  );

  test(
    'a verified file can be evicted and hydrated without whole-file APIs',
    () async {
      final file = File(p.join(local.path, 'file.txt'));
      await file.writeAsString('identical');
      cloud.put('/docs/file.txt', 'identical'.codeUnits);
      expect((await engine.syncPair(pair, cloud)).errors, 0);
      final service = PlaceholderService(database, journal: journal);
      await service.dehydrate(
        pairId: pair.id,
        localBasePath: local.path,
        relativePath: 'file.txt',
        remotePath: '/docs/file.txt',
        provider: pair.provider,
        client: cloud,
      );
      expect(await file.exists(), isFalse);
      expect((await engine.syncPair(pair, cloud)).deletedRemote, 0);
      await service.hydrate(
        pairId: pair.id,
        localBasePath: local.path,
        relativePath: 'file.txt',
        client: cloud,
      );
      expect(await file.readAsString(), 'identical');
    },
  );

  test('freeing space never deletes a same-size local edit with restored timestamps', () async {
    final file = File(p.join(local.path, 'file.txt'));
    await file.writeAsString('local');
    cloud.put('/docs/file.txt', 'local'.codeUnits);
    expect((await engine.syncPair(pair, cloud)).errors, 0);
    final originalTime = (await file.stat()).modified;
    await file.writeAsString('edits');
    await file.setLastModified(originalTime);
    await expectLater(
      PlaceholderService(database).dehydrate(
        pairId: pair.id,
        localBasePath: local.path,
        relativePath: 'file.txt',
        remotePath: '/docs/file.txt',
        provider: pair.provider,
        client: cloud,
      ),
      throwsStateError,
    );
    expect(await file.readAsString(), 'edits');
    expect(await File('${file.path}.crispcloud').exists(), isFalse);
  });

  test('a placeholder cannot hydrate against a rebound source', () async {
    cloud.put('/docs/file.txt', 'cloud'.codeUnits);
    final service = PlaceholderService(database);
    await service.createPlaceholder(
      pairId: pair.id,
      localBasePath: local.path,
      relativePath: 'file.txt',
      remotePath: '/docs/file.txt',
      provider: pair.provider,
      sizeBytes: 5,
    );
    pair = await bindTestPair(database, pair, cloud);
    await expectLater(
      service.hydrate(
        pairId: pair.id,
        localBasePath: local.path,
        relativePath: 'file.txt',
        client: cloud,
      ),
      throwsStateError,
    );
    expect(await File(p.join(local.path, 'file.txt')).exists(), isFalse);
    expect(cloud.reads, isEmpty);
  });

  test(
    'freeing space retains the last local version when its cloud copy changed',
    () async {
      final file = File(p.join(local.path, 'file.txt'));
      await file.writeAsString('local');
      cloud.put('/docs/file.txt', 'local'.codeUnits);
      expect((await engine.syncPair(pair, cloud)).errors, 0);
      cloud.put('/docs/file.txt', 'other'.codeUnits);
      await expectLater(
        PlaceholderService(database).dehydrate(
          pairId: pair.id,
          localBasePath: local.path,
          relativePath: 'file.txt',
          remotePath: '/docs/file.txt',
          provider: pair.provider,
          client: cloud,
        ),
        throwsStateError,
      );
      expect(await file.readAsString(), 'local');
      expect(await File('${file.path}.crispcloud').exists(), isFalse);
    },
  );

  test('offline upload and download use verified streamed copies', () async {
    final service = SyncOfflineService(database, journal: journal);
    await File(p.join(local.path, 'upload.txt')).writeAsString('local');
    cloud.put('/docs/download.txt', 'cloud'.codeUnits);
    await service.enqueue(
      pairId: pair.id,
      operation: 'upload',
      path: 'upload.txt',
    );
    await service.enqueue(
      pairId: pair.id,
      operation: 'download',
      path: 'download.txt',
    );
    final operations = await database.getPendingOfflineOps(pair.id);
    for (final op in operations) {
      final result = await service.execute(op, pair, cloud);
      expect(result.errors, 0);
    }
    expect(String.fromCharCodes(cloud.files['/docs/upload.txt']!), 'local');
    expect(
      await File(p.join(local.path, 'download.txt')).readAsString(),
      'cloud',
    );
    expect(journal.jobs, hasLength(2));
    expect(
      journal.jobs.every((job) => job.status == TransferJobStatus.completed),
      isTrue,
    );
  });

  test(
    'planning cancellation releases a source stalled before its first chunk',
    () async {
      cloud.put('/docs/file.txt', 'cloud'.codeUnits);
      final entered = Completer<void>();
      final release = Completer<void>();
      cloud.beforeRead = (_, _) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      var cancel = false;
      final pending = engine.planPair(pair, cloud, isCancelled: () => cancel);
      await entered.future;
      cancel = true;
      try {
        await expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsA(isA<SyncCancelledException>()),
        );
      } finally {
        release.complete();
      }
      expect(cloud.writes, isEmpty);
    },
  );
}

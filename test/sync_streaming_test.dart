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
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';

import 'support/workflow_fake_client.dart';

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
  });
}

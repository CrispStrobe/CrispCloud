import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/background_transfer_journal.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/native_journal_lease.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('background-journal-'),
  );
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'native leases exclude different descriptors and isolates in one process',
    () async {
      final path = p.join(root.path, 'owner.lock');
      final first = await tryAcquireNativeJournalLease(path);
      expect(first, isNotNull);
      expect(await tryAcquireNativeJournalLease(path), isNull);
      final blocked = await Isolate.run(() async {
        final other = await tryAcquireNativeJournalLease(path);
        other?.close();
        return other == null;
      });
      expect(blocked, isTrue);
      first!.close();
      first.close();
      final after = await tryAcquireNativeJournalLease(path);
      expect(after, isNotNull);
      after!.close();
    },
  );

  test(
    'process interruption releases the native lease without a finally block',
    () async {
      final path = p.join(root.path, 'crashed.lock');
      final executable =
          Platform.environment['CRISP_DART_EXECUTABLE'] ?? 'dart';
      final worker = await Process.start(executable, [
        'test/fixtures/journal_lease_worker.dart',
        path,
      ]);
      final errors = worker.stderr.transform(utf8.decoder).join();
      expect(
        await worker.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'leased',
        reason: 'Worker must acquire the actual OS lease.',
      );
      expect(await tryAcquireNativeJournalLease(path), isNull);
      worker.kill(
        Platform.isWindows ? ProcessSignal.sigterm : ProcessSignal.sigkill,
      );
      await worker.exitCode;
      expect(await errors, isEmpty);
      final after = await tryAcquireNativeJournalLease(path);
      expect(after, isNotNull);
      after!.close();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('symbolic links cannot redirect a lease to another file', () async {
    final target = await File(p.join(root.path, 'target'))
        .writeAsString('retained');
    final link = await Link(p.join(root.path, 'link')).create(target.path);
    await expectLater(
      tryAcquireNativeJournalLease(link.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsString(), 'retained');
  }, skip: Platform.isWindows);

  test('active runs remain private; released runs import source-bound recovery evidence', () async {
    final first = await createBackgroundTransferJournalRun(rootPath: root.path);
    final second = await createBackgroundTransferJournalRun(
      rootPath: root.path,
    );
    await _save(first, 'first');
    await _save(second, 'second');
    final target = TransferJournal(MemoryTransferJournalStorage());
    final blocked = await importBackgroundTransferJournals(
      target,
      rootPath: root.path,
    );
    expect(blocked.activeRuns, 2);
    expect(target.jobs, isEmpty);
    await first.close();
    final imported = await importBackgroundTransferJournals(
      target,
      rootPath: root.path,
    );
    expect(imported.importedJobs, 1);
    expect(imported.activeRuns, 1);
    expect(target.jobs.single.status, TransferJobStatus.interrupted);
    expect(target.jobs.single.source!.accountKey, 'first');
    expect(
      target.jobs.single.entries.single.recovery['backupPath'],
      '/target/original.backup',
    );
    expect(await Directory(first.directoryPath).exists(), isFalse);
    await second.close();
    expect(
      (await importBackgroundTransferJournals(
        target,
        rootPath: root.path,
      )).importedJobs,
      1,
    );
    expect(target.jobs, hasLength(2));
    expect(
      (await importBackgroundTransferJournals(
        target,
        rootPath: root.path,
      )).importedJobs,
      0,
    );
  });

  test('closing a run drains checkpoints and forbids later writes', () async {
    final run = await createBackgroundTransferJournalRun(rootPath: root.path);
    await _save(run, 'closed');
    final checkpoints = [
      for (var i = 0; i < 20; i++)
        run.journal.updateQueue('sync-job', priority: i),
    ];
    // Close immediately: these admitted calls may still be awaiting initialize
    // and have not entered the lock. They must complete under the held lease.
    final closing = run.close();
    await expectLater(
      run.journal.updateQueue('sync-job', priority: 1000),
      throwsStateError,
    );
    expect(
      await tryAcquireNativeJournalLease(
        p.join(run.directoryPath, 'owner.lock'),
      ),
      isNull,
    );
    await closing;
    await Future.wait(checkpoints);
    await run.close();
    await expectLater(
      run.journal.setStatus('sync-job', TransferJobStatus.completed),
      throwsStateError,
    );
    final target = TransferJournal(MemoryTransferJournalStorage());
    expect(
      (await importBackgroundTransferJournals(
        target,
        rootPath: root.path,
      )).importedJobs,
      1,
    );
    expect(target.jobs.single.priority, 19);
  });

  test(
    'failed import retains its source and resumes after a foreground restart',
    () async {
      final run = await createBackgroundTransferJournalRun(rootPath: root.path);
      await _save(run, 'partial');
      await run.close();
      final storage = _FailingStorage()..failAt = 3;
      final first = TransferJournal(storage);
      final failure = await importBackgroundTransferJournals(
        first,
        rootPath: root.path,
      );
      expect(failure.warnings, isNotEmpty);
      expect(await Directory(run.directoryPath).exists(), isTrue);
      expect(first.jobs.single.ready, isFalse);
      storage.failAt = null;
      final reopened = TransferJournal(storage);
      expect(
        (await importBackgroundTransferJournals(
          reopened,
          rootPath: root.path,
        )).importedJobs,
        1,
      );
      expect(reopened.jobs, hasLength(1));
      expect(reopened.jobs.single.ready, isTrue);
      expect(reopened.jobs.single.entries, hasLength(1));
      expect(await Directory(run.directoryPath).exists(), isFalse);
    },
  );

  test('a receipt retry does not overwrite recovered progress', () async {
    final run = await createBackgroundTransferJournalRun(rootPath: root.path);
    await _save(run, 'receipt');
    await run.close();
    final storage = _FailingStorage()..failAt = 4;
    final target = TransferJournal(storage);
    await importBackgroundTransferJournals(target, rootPath: root.path);
    expect(target.jobs.single.ready, isTrue);
    storage.failAt = null;
    await target.setStatus(
      target.jobs.single.id,
      TransferJobStatus.completed,
      message: 'Reviewed and finished',
    );
    await importBackgroundTransferJournals(target, rootPath: root.path);
    expect(target.jobs.single.status, TransferJobStatus.completed);
    expect(target.jobs.single.message, 'Reviewed and finished');
  });

  for (final failedAppend in [3, 4]) {
    test(
      'dismissing an import after append $failedAppend fails survives restart and compaction',
      () async {
        final run = await createBackgroundTransferJournalRun(
          rootPath: root.path,
        );
        await _save(run, 'dismiss-before-receipt');
        await run.close();
        final storage = _FailingStorage()..failAt = failedAppend;
        final target = TransferJournal(storage);
        final attempt = await importBackgroundTransferJournals(
          target,
          rootPath: root.path,
        );
        expect(attempt.warnings, isNotEmpty);
        expect(await Directory(run.directoryPath).exists(), isTrue);
        expect(target.jobs.single.ready, failedAppend == 4);
        storage.failAt = null;
        await target.dismiss(target.jobs.single.id);
        await target.compact();
        final reopened = TransferJournal(storage);
        final retry = await importBackgroundTransferJournals(
          reopened,
          rootPath: root.path,
        );
        expect(retry.importedJobs, 0);
        expect(retry.warnings, isEmpty);
        expect(reopened.jobs, isEmpty);
        expect(await Directory(run.directoryPath).exists(), isFalse);
      },
    );
  }

  for (final failedAppend in [1, 2, 3, 4]) {
    test(
      'an acknowledgement failure after import event $failedAppend cannot corrupt a retry',
      () async {
        final run = await createBackgroundTransferJournalRun(
          rootPath: root.path,
        );
        await _save(run, 'durable-before-error');
        await run.close();
        final storage = _FailingStorage();
        final target = TransferJournal(storage);
        await _save(
          BackgroundTransferJournalRun(
            journal: target,
            directoryPath: root.path,
            close: () async {},
          ),
          'live-foreground',
        );
        storage
          ..failAt = storage.writes + failedAppend
          ..failAfterWrite = true;
        final failed = await importBackgroundTransferJournals(
          target,
          rootPath: root.path,
        );
        expect(failed.warnings, isNotEmpty);
        expect(await Directory(run.directoryPath).exists(), isTrue);
        storage.failAt = null;
        final retried = await importBackgroundTransferJournals(
          target,
          rootPath: root.path,
        );
        expect(retried.warnings, isEmpty);
        expect(retried.importedJobs, failedAppend == 4 ? 0 : 1);
        expect(target.job('sync-job')!.status, TransferJobStatus.running);
        final reopened = TransferJournal(storage);
        await reopened.initialize();
        expect(reopened.warnings, isEmpty);
        expect(reopened.jobs, hasLength(2));
        final imported = reopened.jobs.singleWhere(
          (job) => job.id != 'sync-job',
        );
        expect(imported.ready, isTrue);
        expect(
          imported.entries.single.recovery['backupPath'],
          '/target/original.backup',
        );
        expect(await Directory(run.directoryPath).exists(), isFalse);
      },
    );
  }

  test('a compaction acknowledgement failure reloads the installed sequence before the next mutation', () async {
    final run = await createBackgroundTransferJournalRun(rootPath: root.path);
    await _save(run, 'compact-ack');
    await run.close();
    final storage = _FailingStorage();
    final target = TransferJournal(storage);
    await importBackgroundTransferJournals(target, rootPath: root.path);
    final id = target.jobs.single.id;
    for (var i = 0; i < 5; i++) {
      await target.updateQueue(id, priority: i);
    }
    storage.failRewriteAfterWrite = true;
    await expectLater(target.compact(), throwsStateError);
    storage.failRewriteAfterWrite = false;
    await target.updateQueue(id, priority: 17);
    final reopened = TransferJournal(storage);
    await reopened.initialize();
    expect(reopened.warnings, isEmpty);
    expect(reopened.jobs.single.priority, 17);
    expect(reopened.jobs.single.ready, isTrue);
    await reopened.dismiss(id);
    await reopened.compact();
    expect(
      await reopened.importRecord(target.jobs.single, importedId: id),
      isFalse,
    );
  });

  test(
    'reconciling a failed import keeps previously interrupted jobs stopped',
    () async {
      final run = await createBackgroundTransferJournalRun(rootPath: root.path);
      await _save(run, 'new-import');
      await run.close();
      final storage = _FailingStorage();
      await _save(
        BackgroundTransferJournalRun(
          journal: TransferJournal(storage),
          directoryPath: root.path,
          close: () async {},
        ),
        'previous-process',
      );
      final target = TransferJournal(storage);
      await target.initialize();
      expect(target.job('sync-job')!.status, TransferJobStatus.interrupted);
      storage
        ..failAt = storage.writes + 1
        ..failAfterWrite = true;
      await importBackgroundTransferJournals(target, rootPath: root.path);
      storage.failAt = null;
      await importBackgroundTransferJournals(target, rootPath: root.path);
      expect(target.job('sync-job')!.status, TransferJobStatus.interrupted);
    },
  );

  test('import receipts survive dismissal and compaction without resurrecting jobs', () async {
    final run = await createBackgroundTransferJournalRun(rootPath: root.path);
    await _save(run, 'dismissed');
    await run.close();
    final saved = await File(p.join(run.directoryPath, 'journal.jsonl'))
        .readAsString();
    final storage = MemoryTransferJournalStorage();
    final target = TransferJournal(storage);
    await importBackgroundTransferJournals(target, rootPath: root.path);
    await target.dismiss(target.jobs.single.id);
    await target.compact();
    await Directory(run.directoryPath).create();
    await File(p.join(run.directoryPath, 'journal.jsonl')).writeAsString(saved);
    final reopened = TransferJournal(storage);
    expect(
      (await importBackgroundTransferJournals(
        reopened,
        rootPath: root.path,
      )).importedJobs,
      0,
    );
    expect(reopened.jobs, isEmpty);
  });

  test('a corrupt last checkpoint imports verified intents and retains diagnostic evidence', () async {
    final run = await createBackgroundTransferJournalRun(rootPath: root.path);
    await _save(run, 'damaged');
    await run.close();
    final file = File(p.join(run.directoryPath, 'journal.jsonl'));
    await file.writeAsString('{unfinished', mode: FileMode.append);
    final target = TransferJournal(MemoryTransferJournalStorage());
    final result = await importBackgroundTransferJournals(
      target,
      rootPath: root.path,
    );
    expect(result.importedJobs, 1);
    expect(result.warnings, isNotEmpty);
    expect(await File('${file.path}.previous').exists(), isTrue);
    await importBackgroundTransferJournals(target, rootPath: root.path);
    expect(await Directory(run.directoryPath).exists(), isTrue);
    expect(target.jobs, hasLength(1));
  });
}

Future<void> _save(BackgroundTransferJournalRun run, String account) async {
  final backend = _Backend(account);
  final entry =
      FileOperationEntry(
          FileItem(
            name: 'source',
            path: '/source',
            isFolder: false,
            size: 3,
            updatedAt: DateTime.utc(2026),
          ),
          '/target/source',
        )
        ..recovery = {
          'phase': 'committing',
          'backupPath': '/target/original.backup',
        };
  final plan = FileOperationPlan(
    source: backend,
    destination: backend,
    targetDirectory: '/target',
    options: const FileOperationOptions(),
    entries: [entry],
    errors: const [],
  );
  await run.journal.create('sync-job', plan);
  await run.journal.setStatus('sync-job', TransferJobStatus.running);
}

class _FailingStorage extends MemoryTransferJournalStorage {
  int? failAt;
  int writes = 0;
  bool failAfterWrite = false;
  bool failRewriteAfterWrite = false;
  @override
  Future<void> append(String line) async {
    final fail = ++writes == failAt;
    if (fail && !failAfterWrite) {
      throw StateError('Injected durable write failure');
    }
    await super.append(line);
    if (fail) throw StateError('Injected acknowledgement failure');
  }

  @override
  Future<void> rewrite(List<String> lines) async {
    await super.rewrite(lines);
    if (failRewriteAfterWrite) {
      throw StateError('Injected compaction acknowledgement failure');
    }
  }
}

class _Backend extends FileOperationBackend {
  _Backend(this.account);
  final String account;
  @override
  StorageReference get storageReference =>
      StorageReference(kind: 'remote', provider: 'test', accountKey: account);
  @override
  Object get identity => storageReference.id;
  @override
  bool get isCurrent => true;
  @override
  bool get canRecover => true;
  @override
  String get label => account;
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) => throw UnimplementedError();
  @override
  Future<List<FileItem>> list(String path) => throw UnimplementedError();
  @override
  Future<void> createDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteEmptyDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteFile(FileItem file) => throw UnimplementedError();
  @override
  Stream<List<int>> readFile(FileItem file) => throw UnimplementedError();
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => throw UnimplementedError();
}

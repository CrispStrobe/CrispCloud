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
    // Let all calls enter the journal queue while native disk flushes remain
    // outstanding. Closing must drain accepted work before dropping the lease.
    await Future<void>.delayed(Duration.zero);
    await run.close();
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
  @override
  Future<void> append(String line) async {
    if (++writes == failAt) throw StateError('Injected durable write failure');
    await super.append(line);
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

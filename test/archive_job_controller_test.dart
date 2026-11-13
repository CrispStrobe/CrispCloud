import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_job.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_creation_worker.dart';
import 'package:crisp_cloud/services/archive_job_controller.dart';
import 'package:crisp_cloud/services/archive_job_journal.dart';
import 'package:crisp_cloud/services/archive_publication_lease.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_creation_backend.dart';

class _Local extends Fake implements LocalFileService {}

class _Backend extends ArchiveCreationBackend {
  @override
  StorageReference get storageReference => const StorageReference(
    kind: 'local',
    provider: 'test',
    accountKey: 'jobs',
  );
  @override
  bool get canRecover => true;
}

class _Store extends MemoryFileCollectionStorage {
  bool refusePrepared = false;
  String? delayedStatus;
  Completer<void>? writeEntered, releaseWrite;
  void delayNextStatus(String status) {
    delayedStatus = status;
    writeEntered = Completer<void>();
    releaseWrite = Completer<void>();
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    if (delayedStatus != null &&
        (jsonDecode(value)['records'] as List).any(
          (record) => record['status'] == delayedStatus,
        )) {
      delayedStatus = null;
      writeEntered!.complete();
      await releaseWrite!.future;
    }
    if (refusePrepared &&
        (jsonDecode(value)['records'] as List).any(
          (record) => record['prepared'] != null,
        )) {
      throw StateError('Disk full while saving publication receipt');
    }
    return super.compareAndSwap(key, expected, value);
  }
}

class _Worker implements ArchiveCreationWorker {
  _Worker(this.options, this.onPrepared);
  final ArchiveCreationOptions options;
  final Future<void> Function(ArchiveCreationPrepared) onPrepared;
  final completed = Completer<ArchiveCreationResult>();
  bool cancelled = false, paused = false, published = false;
  static final bytes = utf8.encode('a verified archive candidate');
  ArchiveCreationPrepared get receipt => ArchiveCreationPrepared(
    '/output/${options.name}',
    1,
    bytes.length,
    sha256.convert(bytes).toString(),
  );
  Future<void> finish({bool lateSuccess = false, String? wrongPath}) async {
    try {
      final value = receipt;
      await onPrepared(
        wrongPath == null
            ? value
            : ArchiveCreationPrepared(
                wrongPath,
                value.entryCount,
                value.bytes,
                value.sha256,
              ),
      );
      if (cancelled && !lateSuccess) throw const FileOperationCancelled();
      published = true;
      completed.complete(
        ArchiveCreationResult(value.path, value.entryCount, value.bytes),
      );
    } catch (error, stack) {
      if (!completed.isCompleted) completed.completeError(error, stack);
    }
  }

  @override
  Future<ArchiveCreationResult> get result => completed.future;
  @override
  void cancel() {
    cancelled = true;
    paused = false;
  }

  @override
  void pause() => paused = true;
  @override
  void resume() => paused = false;
  @override
  Future<void> close() async {
    /* An already-drained fake has no resources. */
  }
}

void main() {
  late _Store store;
  late _Backend backend;
  final controllers = <ArchiveJobController>[];
  final workers = <_Worker>[];
  Future<ArchiveCreationWorker> factory({
    required LocalFileService local,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveCreationOptions options,
    required void Function(ArchiveCreationProgress) onProgress,
    required Future<void> Function(ArchiveCreationPrepared) onPrepared,
  }) async {
    final worker = _Worker(options, onPrepared);
    workers.add(worker);
    return worker;
  }

  ArchiveJobController controller() {
    final result = ArchiveJobController(
      local: _Local(),
      backend: backend,
      journal: ArchiveJobJournal(storage: store),
      workerFactory: factory,
      acquireLease: MemoryArchivePublicationLease.acquire,
    );
    controllers.add(result);
    return result;
  }

  Future<void> started(int count) async {
    for (var i = 0; i < 100 && workers.length < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(workers.length, count);
    await Future<void>.delayed(Duration.zero);
  }

  Future<ArchiveJobRecord> enqueue(
    ArchiveJobController target,
    String name, {
    String? password,
  }) => target.enqueue(
    files: [
      FileItem(
        name: 'source.txt',
        path: '/input/source.txt',
        isFolder: false,
        size: 1,
      ),
    ],
    destinationDirectory: '/output',
    options: ArchiveCreationOptions(name: '$name.zip', password: password),
  );

  setUp(() {
    store = _Store();
    backend = _Backend()..put('/input/source.txt', [1]);
    workers.clear();
    controllers.clear();
  });
  tearDown(() async {
    for (final worker in workers) {
      if (!worker.completed.isCompleted) {
        worker.completed.completeError(const FileOperationCancelled());
      }
    }
    for (final target in controllers) {
      await target.close();
      target.dispose();
    }
  });

  test('job intent is durable before a serial worker starts and receipt precedes success', () async {
    final target = controller();
    final first = await enqueue(target, 'one');
    final second = await enqueue(target, 'two');
    expect(store.values[ArchiveJobJournal.key], contains(first.id));
    await started(1);
    expect(target.job(first.id)!.status, ArchiveJobStatus.running);
    expect(target.job(second.id)!.status, ArchiveJobStatus.queued);
    await workers.first.finish();
    await started(2);
    expect(target.job(first.id)!.status, ArchiveJobStatus.completed);
    expect(
      target.job(first.id)!.prepared!.sha256,
      workers.first.receipt.sha256,
    );
    await workers.last.finish();
    await target.idle;
    expect(
      target.jobs.every((job) => job.status == ArchiveJobStatus.completed),
      isTrue,
    );
  });

  test('queue pause and reordering survive in the durable catalog', () async {
    final target = controller();
    await target.initialize();
    await target.setQueuePaused(true);
    final first = await enqueue(target, 'one');
    final second = await enqueue(target, 'two');
    await target.moveToTop(second.id);
    expect(workers, isEmpty);
    final saved = ArchiveJobJournal(storage: store);
    await saved.load();
    expect(saved.paused, isTrue);
    expect(saved.records.first.id, second.id);
    await target.setQueuePaused(false);
    await started(1);
    expect(workers.single.options.name, 'two.zip');
    await workers.single.finish();
    await started(2);
    expect(target.activeId, first.id);
    await workers.last.finish();
    await target.idle;
  });

  test('pause and resume control the active worker; stop drains before final status', () async {
    final target = controller();
    final queued = await enqueue(target, 'one');
    await started(1);
    final worker = workers.single;
    await target.pause(queued.id);
    expect(worker.paused, isTrue);
    expect(target.job(queued.id)!.status, ArchiveJobStatus.paused);
    await target.resume(queued.id);
    expect(worker.paused, isFalse);
    await target.cancel(queued.id);
    expect(target.job(queued.id)!.status, ArchiveJobStatus.stopping);
    expect(worker.cancelled, isTrue);
    await worker.finish();
    await target.idle;
    expect(worker.published, isFalse);
    expect(target.job(queued.id)!.status, ArchiveJobStatus.cancelled);
  });

  test('failed prepared checkpoint cannot authorize publication', () async {
    final target = controller();
    final queued = await enqueue(target, 'one');
    await started(1);
    store.refusePrepared = true;
    await workers.single.finish();
    await target.idle;
    expect(workers.single.published, isFalse);
    expect(target.error, isNotNull);
    final persisted = ArchiveJobJournal(storage: store);
    await persisted.load();
    expect(persisted.records.single.prepared, isNull);
    expect(persisted.records.single.id, queued.id);
  });

  test(
    'a pause racing admission cannot become an unresumable running job',
    () async {
      final target = controller();
      final record = await enqueue(target, 'private', password: 'memory-only');
      store.delayNextStatus('paused');
      final pausing = target.pause(record.id);
      await store.writeEntered!.future;
      // Let the scheduled driver observe the still-queued old journal snapshot.
      await Future<void>.delayed(Duration.zero);
      expect(workers, isEmpty);
      store.releaseWrite!.complete();
      await pausing;
      await target.idle;
      expect(target.job(record.id)!.status, ArchiveJobStatus.paused);
      expect(target.activeId, isNull);
      expect(workers, isEmpty);
      await target.resume(record.id);
      await started(1);
      expect(workers.single.options.password, 'memory-only');
      await workers.single.finish();
      await target.idle;
      expect(target.job(record.id)!.status, ArchiveJobStatus.completed);
    },
  );

  test(
    'resume waiting behind completion cannot resurrect a completed job',
    () async {
      final target = controller();
      final record = await enqueue(target, 'one');
      await started(1);
      final worker = workers.single;
      await worker.onPrepared(worker.receipt);
      await target.pause(record.id);
      store.delayNextStatus('completed');
      // Publication can finish immediately before the isolate observes pause.
      worker.completed.complete(worker.receipt);
      await store.writeEntered!.future;
      final resuming = target.resume(record.id);
      await Future<void>.delayed(Duration.zero);
      store.releaseWrite!.complete();
      await resuming;
      await target.idle;
      expect(target.job(record.id)!.status, ArchiveJobStatus.completed);
      expect(workers.length, 1);
    },
  );

  test('another window cannot start or mutate an owned queue', () async {
    final first = controller();
    await first.initialize();
    final second = controller();
    await second.initialize();
    expect(second.ownedElsewhere, isTrue);
    await expectLater(enqueue(second, 'blocked'), throwsStateError);
    expect(workers, isEmpty);
    expect(first.jobs, isEmpty);
  });

  test(
    'duplicate output jobs are refused before a second intent is accepted',
    () async {
      final target = controller();
      await target.initialize();
      await target.setQueuePaused(true);
      await enqueue(target, 'one');
      await expectLater(enqueue(target, 'one'), throwsStateError);
      expect(target.jobs.length, 1);
      expect(workers, isEmpty);
    },
  );

  test('restart requires explicit action and protected jobs require their password again', () async {
    final first = controller();
    await first.initialize();
    await first.setQueuePaused(true);
    final record = await enqueue(
      first,
      'secret',
      password: 'never-persist-this',
    );
    await first.close();
    final recovered = controller();
    await recovered.initialize();
    expect(recovered.job(record.id)!.status, ArchiveJobStatus.interrupted);
    expect(workers, isEmpty);
    expect(store.values.values.single, isNot(contains('never-persist-this')));
    await expectLater(recovered.restart(record.id), throwsStateError);
    await recovered.restart(record.id, password: 'new-session-password');
    await recovered.setQueuePaused(false);
    await started(1);
    expect(workers.single.options.password, 'new-session-password');
    await workers.single.finish();
    await recovered.idle;
  });

  test('restart cannot overwrite an existing destination', () async {
    final first = controller();
    await first.initialize();
    await first.setQueuePaused(true);
    final record = await enqueue(first, 'one');
    await first.close();
    final recovered = controller();
    await recovered.initialize();
    backend.put(record.request.outputPath, [9, 8, 7]);
    await expectLater(recovered.restart(record.id), throwsStateError);
    expect(backend.contents[record.request.outputPath], [9, 8, 7]);
    expect(recovered.job(record.id)!.status, ArchiveJobStatus.interrupted);
  });

  test(
    'changed or unacknowledged worker destination is never completed',
    () async {
      final target = controller();
      final record = await enqueue(target, 'one');
      await started(1);
      await workers.single.finish(wrongPath: '/output/other.zip');
      await target.idle;
      expect(workers.single.published, isFalse);
      expect(target.job(record.id)!.status, ArchiveJobStatus.failed);
    },
  );

  test(
    'verified output reconciliation uses exact persisted size and full SHA-256',
    () async {
      final first = controller();
      final record = await enqueue(first, 'one');
      await started(1);
      final worker = workers.single;
      await worker.onPrepared(worker.receipt);
      // Model a lost final acknowledgement after the exclusive publication.
      backend.put(worker.receipt.path, _Worker.bytes);
      worker.completed.completeError(
        StateError('Process disappeared after commit'),
      );
      await first.idle;
      await first.close();
      final recovered = controller();
      await recovered.initialize();
      expect(recovered.job(record.id)!.status, ArchiveJobStatus.failed);
      await recovered.verifyPublishedOutput(record.id);
      expect(recovered.job(record.id)!.status, ArchiveJobStatus.completed);
      expect(backend.contents[worker.receipt.path], _Worker.bytes);
    },
  );

  test(
    'mismatched saved output is retained without marking a job complete',
    () async {
      final target = controller();
      final record = await enqueue(target, 'one');
      await started(1);
      final worker = workers.single;
      await worker.onPrepared(worker.receipt);
      worker.completed.completeError(StateError('Lost acknowledgement'));
      await target.idle;
      backend.put(worker.receipt.path, List.filled(_Worker.bytes.length, 0));
      await expectLater(
        target.verifyPublishedOutput(record.id),
        throwsStateError,
      );
      expect(target.job(record.id)!.status, ArchiveJobStatus.failed);
      expect(backend.contents[worker.receipt.path], everyElement(0));
    },
  );

  test('close retains active intent for restart and releases ownership only after drain', () async {
    final first = controller();
    final record = await enqueue(first, 'one');
    await started(1);
    final worker = workers.single;
    var closed = false;
    final closing = first.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(worker.cancelled, isTrue);
    expect(closed, isFalse);
    final other = controller();
    await other.initialize();
    expect(other.ownedElsewhere, isTrue);
    worker.completed.completeError(const FileOperationCancelled());
    await closing;
    expect(closed, isTrue);
    final recovered = controller();
    await recovered.initialize();
    expect(recovered.job(record.id)!.status, ArchiveJobStatus.interrupted);
    expect(workers.length, 1);
  });
}

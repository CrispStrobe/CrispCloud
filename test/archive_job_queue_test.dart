import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/models/archive_job.dart';
import 'package:crisp_cloud/models/archive_operation.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_queue_fixture.dart';
import 'support/archive_workflow_backend.dart';

Future<void> _turn() => Future<void>.delayed(const Duration(milliseconds: 20));

class _FailingJournalStorage extends MemoryTransferJournalStorage {
  bool fail = false;
  @override
  Future<void> append(String line) async {
    if (fail) throw StateError('Journal unavailable');
    await super.append(line);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTransferJournalStorage storage;
  late TransferJournal journal;
  late ProviderContainer container;
  late TransferNotifier transfers;
  late QueueArchiveBackend source;
  late QueueArchiveBackend destination;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = MemoryTransferJournalStorage();
    journal = TransferJournal(storage);
    container = ProviderContainer(
      overrides: [transferJournalProvider.overrideWithValue(journal)],
    );
    transfers = container.read(transferProvider);
    await transfers.ready;
    source = QueueArchiveBackend('source')
      ..put('/input/data.txt', utf8.encode('queued payload'));
    destination = QueueArchiveBackend('destination');
  });
  tearDown(() => container.dispose());

  Future<ArchiveOperationHandle<ArchiveCreationResult>> enqueue({
    String name = 'result.zip',
    ArchiveCreationService? service,
  }) async => transfers.enqueueArchiveCreation(
    source: source,
    destination: destination,
    files: [(await source.stat('/input/data.txt'))!],
    destinationDirectory: '/output',
    options: ArchiveCreationOptions(name: name),
    service: service ?? const ArchiveCreationService(),
  );

  test(
    'durable queue admission and stopped pending job never open its writer',
    () async {
      await transfers.setQueuePaused(true);
      final service = GatedArchiveCreation();
      final handle = await enqueue(service: service);
      expect(journal.job(handle.id)!.ready, isTrue);
      expect(isArchiveTransferJob(journal.job(handle.id)!), isTrue);
      expect(transfers.isQueued(handle.id), isTrue);
      expect(service.calls, 0);
      transfers.cancelOperation(handle.id);
      await handle.completion;
      await _turn();
      expect(service.calls, 0);
      expect(handle.error, isA<FileOperationCancelled>());
      expect(journal.job(handle.id)!.status, TransferJobStatus.cancelled);
      expect(destination.writes, isEmpty);
      expect(transfers.isJobLive(handle.id), isFalse);
    },
  );

  test(
    'pause holds a running archive and Stop wakes it without publication',
    () async {
      final service = GatedArchiveCreation();
      final handle = await enqueue(service: service);
      await service.entered.future;
      transfers.pauseOperation(handle.id);
      service.release.complete();
      await _turn();
      expect(handle.control.isPaused, isTrue);
      expect(handle.isSettled, isFalse);
      expect(destination.writes, isEmpty);
      transfers.cancelOperation(handle.id);
      await handle.completion;
      expect(handle.error, isA<FileOperationCancelled>());
      expect(handle.control.isPaused, isFalse);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'resuming an observed job publishes after its dialog listener detaches',
    () async {
      final service = GatedArchiveCreation();
      final handle = await enqueue(service: service);
      void observer() {}
      handle.addListener(observer);
      await service.entered.future;
      transfers.pauseOperation(handle.id);
      handle.removeListener(observer);
      service.release.complete();
      transfers.resumeOperation(handle.id);
      await handle.completion;
      expect(handle.error, isNull);
      expect(handle.result!.path, '/output/result.zip');
      expect(journal.job(handle.id)!.status, TransferJobStatus.completed);
      final archive = codecs.ZipDecoder().decodeBytes(
        destination.contents['/output/result.zip']!,
      );
      expect(
        utf8.decode(archive.findFile('data.txt')!.content as List<int>),
        'queued payload',
      );
    },
  );

  for (final format in [
    ArchiveCreationFormat.zip,
    ArchiveCreationFormat.sevenZip,
    ArchiveCreationFormat.tarGzip,
  ]) {
    test(
      '${format.label} creates and reopens through the background queue',
      () async {
        final data = Uint8List.fromList(
          List.generate(512 * 1024, (i) => i % 251),
        );
        source.put('/input/data.txt', data);
        final handle = await transfers.enqueueArchiveCreation(
          source: source,
          destination: destination,
          files: [(await source.stat('/input/data.txt'))!],
          destinationDirectory: '/output',
          options: ArchiveCreationOptions(
            name: 'result${format.extension}',
            format: format,
          ),
        );
        await handle.completion;
        expect(handle.error, isNull);
        final archive = await openViewerArchive(
          destination.contents[handle.result!.path]!,
          name: 'result${format.extension}',
        );
        try {
          final member = archive.members.singleWhere(
            (entry) => entry.name == 'data.txt',
          );
          expect(await archive.readMember(member), data);
        } finally {
          await archive.close();
        }
        expect(handle.operation.type, OperationType.archive);
        expect(handle.operation.status, OperationStatus.completed);
      },
    );
  }

  test(
    'Stop after exclusive install retains completed result and durable receipt',
    () async {
      await transfers.setQueuePaused(true);
      final handle = await enqueue();
      destination.afterInstall = () => transfers.cancelOperation(handle.id);
      await transfers.setQueuePaused(false);
      await handle.completion;
      expect(handle.error, isNull);
      expect(handle.operation.isCancelled, isFalse);
      expect(handle.operation.status, OperationStatus.completed);
      expect(journal.job(handle.id)!.status, TransferJobStatus.completed);
      expect(destination.writes, ['/output/result.zip']);
    },
  );

  test('post-publication journal failure remains a successful archive with a warning', () async {
    final failedStorage = _FailingJournalStorage();
    final ownedJournal = TransferJournal(failedStorage);
    final other = ProviderContainer(
      overrides: [transferJournalProvider.overrideWithValue(ownedJournal)],
    );
    addTearDown(other.dispose);
    final queue = other.read(transferProvider);
    await queue.ready;
    destination.afterInstall = () => failedStorage.fail = true;
    final handle = await queue.enqueueArchiveCreation(
      source: source,
      destination: destination,
      files: [(await source.stat('/input/data.txt'))!],
      destinationDirectory: '/output',
      options: const ArchiveCreationOptions(name: 'confirmed.zip'),
    );
    await handle.completion;
    expect(handle.error, isNull);
    expect(handle.result, isNotNull);
    expect(handle.publicationWarning, isNotNull);
    expect(handle.operation.status, OperationStatus.completed);
    expect(destination.writes, ['/output/confirmed.zip']);
    failedStorage.fail = false;
    final replay = TransferJournal(failedStorage);
    await replay.initialize();
    final definition = ArchiveCreationJobDefinition.fromJob(replay.jobs.single);
    expect(definition.publication['packedSha256'], isNotNull);
    expect(
      definition.publication['packedBytes'],
      destination.contents['/output/confirmed.zip']!.length,
    );
  });

  test('a failed admission does not start archive I/O', () async {
    final failedStorage = _FailingJournalStorage()..fail = true;
    final other = ProviderContainer(
      overrides: [
        transferJournalProvider.overrideWithValue(
          TransferJournal(failedStorage),
        ),
      ],
    );
    addTearDown(other.dispose);
    final queue = other.read(transferProvider);
    await queue.ready;
    final service = GatedArchiveCreation();
    await expectLater(
      queue.enqueueArchiveCreation(
        source: source,
        destination: destination,
        files: [(await source.stat('/input/data.txt'))!],
        destinationDirectory: '/output',
        options: const ArchiveCreationOptions(name: 'no-write.zip'),
        service: service,
      ),
      throwsStateError,
    );
    expect(service.calls, 0);
    expect(destination.writes, isEmpty);
  });

  test('archive jobs honor priority, future schedules and shared destination claims', () async {
    await transfers.setConcurrency(2);
    await transfers.setQueuePaused(true);
    final firstService = GatedArchiveCreation();
    final secondService = GatedArchiveCreation();
    final first = await enqueue(name: 'first.zip', service: firstService);
    final second = await enqueue(name: 'second.zip', service: secondService);
    await transfers.setPriority(second.id, 10);
    await transfers.setQueuePaused(false);
    await secondService.entered.future;
    await _turn();
    expect(
      firstService.calls,
      0,
      reason: 'same destination directory is reserved',
    );
    transfers.cancelOperation(second.id);
    await second.completion;
    await firstService.entered.future;
    transfers.cancelOperation(first.id);
    await first.completion;
    final scheduledService = GatedArchiveCreation();
    final scheduled = await transfers.enqueueArchiveCreation(
      source: source,
      destination: destination,
      files: [(await source.stat('/input/data.txt'))!],
      destinationDirectory: '/output',
      options: const ArchiveCreationOptions(name: 'later.zip'),
      service: scheduledService,
      notBefore: DateTime.now().add(const Duration(hours: 1)),
    );
    await _turn();
    expect(scheduledService.calls, 0);
    expect(journal.job(scheduled.id)!.scheduledAt, isNotNull);
    transfers.cancelOperation(scheduled.id);
    await scheduled.completion;
  });

  test(
    'queue and normal copy compete for the same destination reservation',
    () async {
      final service = GatedArchiveCreation();
      final archive = await enqueue(service: service);
      await service.entered.future;
      final copyPlan = FileOperationPlan(
        source: source,
        destination: destination,
        targetDirectory: '/output',
        options: const FileOperationOptions(),
        entries: [
          FileOperationEntry(
            (await source.stat('/input/data.txt'))!,
            '/output/copied.txt',
          ),
        ],
        errors: const [],
      );
      final control = FileOperationControl();
      final copyQueued = Completer<void>();
      final copied = transfers.runFileOperation(
        copyPlan,
        control: control,
        onQueued: copyQueued.complete,
      );
      await copyQueued.future;
      await _turn();
      expect(destination.writes, isEmpty);
      expect(transfers.queuedCount, 1);
      control.cancel();
      await copied;
      transfers.cancelOperation(archive.id);
      await archive.completion;
    },
  );

  test('workspace draft survives queued Stop and can be reviewed and retried in session', () async {
    final zip = codecs.ZipEncoder().encode(
      codecs.Archive()..addFile(
        codecs.ArchiveFile.bytes('original.txt', utf8.encode('before')),
      ),
    );
    final client = ArchiveWorkflowClient()..put('/editable.zip', zip);
    final backend = ArchiveWorkflowBackend(
      client,
      isCurrent: () => client.current,
    );
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/editable.zip'))!,
      journal: ArchivePublicationJournal(
        storage: MemoryFileCollectionStorage(),
      ),
    );
    workspace.replace(
      '/original.txt',
      Uint8List.fromList(utf8.encode('after')),
    );
    await transfers.setQueuePaused(true);
    final stopped = await transfers.enqueueArchiveWorkspace(workspace);
    transfers.cancelOperation(stopped.id);
    await stopped.completion;
    await _turn();
    expect(
      identical(transfers.archiveWorkspaceForJob(stopped.id), workspace),
      isTrue,
    );
    expect(workspace.dirty, isTrue);
    expect(client.files['/editable.zip'], zip);
    final retry = await transfers.enqueueArchiveWorkspace(
      workspace,
      recoveryJobId: stopped.id,
    );
    await transfers.setQueuePaused(false);
    await retry.completion;
    expect(retry.error, isNull);
    expect(retry.result, isNotNull);
    expect(transfers.archiveWorkspaceForJob(retry.id), isNull);
    expect(workspace.isCurrent, isFalse);
    final archive = codecs.ZipDecoder().decodeBytes(
      client.files['/editable.zip']!,
    );
    expect(
      utf8.decode(archive.findFile('original.txt')!.content as List<int>),
      'after',
    );
  });

  test('a replayed archive recipe never auto-starts or falls through to copy recovery', () async {
    await transfers.setQueuePaused(true);
    final handle = await enqueue();
    final replay = TransferJournal(storage);
    await replay.initialize();
    final second = ProviderContainer(
      overrides: [transferJournalProvider.overrideWithValue(replay)],
    );
    addTearDown(second.dispose);
    final restored = second.read(transferProvider);
    await restored.ready;
    expect(restored.operations.single.type, OperationType.archive);
    expect(restored.operations.single.status, OperationStatus.failed);
    expect(restored.queuedCount, 0);
    expect(replay.job(handle.id)!.status, TransferJobStatus.interrupted);
    expect(destination.writes, isEmpty);
    transfers.cancelOperation(handle.id);
    await handle.completion;
  });

  test('reviewed restart rejects changed source bytes even with restored size and time', () async {
    await transfers.setQueuePaused(true);
    final stopped = await enqueue();
    destination.beforeStageVerification = () =>
        transfers.cancelOperation(stopped.id);
    await transfers.setQueuePaused(false);
    await stopped.completion;
    await _turn();
    final saved = journal.job(stopped.id)!;
    expect(
      ArchiveCreationJobDefinition.fromJob(saved).sourceManifestSha256,
      isNotNull,
    );
    source.put('/input/data.txt', utf8.encode('changed bytes!'));
    expect(source.contents['/input/data.txt']!.length, 14);
    destination.beforeStageVerification = null;
    final retry = await transfers.enqueueArchiveCreation(
      source: source,
      destination: destination,
      files: [(await source.stat('/input/data.txt'))!],
      destinationDirectory: '/output',
      options: const ArchiveCreationOptions(name: 'result.zip'),
      recoveryJobId: stopped.id,
    );
    await retry.completion;
    expect(retry.error, isA<ArchiveCreationException>());
    expect(
      (retry.error as ArchiveCreationException).code,
      ArchiveCreationError.sourceChanged,
    );
    expect(destination.contents.containsKey('/output/result.zip'), isFalse);
  });
}

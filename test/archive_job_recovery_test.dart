import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_job.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_job_recovery_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_queue_fixture.dart';

class _PausingOutputBackend extends QueueArchiveBackend {
  _PausingOutputBackend(this.control) : super('original-destination');

  final FileOperationControl control;
  final prefixRead = Completer<void>();
  int outputReads = 0;

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    if (file.path != '/output/saved.zip') {
      yield* super.readFile(file);
      return;
    }
    final bytes = contents[file.path]!;
    outputReads++;
    final split = bytes.length ~/ 2;
    yield Uint8List.sublistView(bytes, 0, split);
    if (outputReads == 1) {
      control.pause();
      prefixRead.complete();
    }
    yield Uint8List.sublistView(bytes, split);
  }
}

void main() {
  late QueueArchiveBackend source;
  late QueueArchiveBackend destination;
  late MemoryTransferJournalStorage storage;
  late TransferJournal journal;
  const service = ArchiveJobRecoveryService();
  setUp(() {
    source = QueueArchiveBackend('original-source')
      ..put('/input/source.txt', [1, 2, 3]);
    destination = QueueArchiveBackend('original-destination');
    storage = MemoryTransferJournalStorage();
    journal = TransferJournal(storage);
  });

  Future<TransferJobRecord> recipe({
    ArchiveCreationOptions options = const ArchiveCreationOptions(
      name: 'saved.zip',
    ),
  }) async {
    final plan = archiveCreationJobPlan(
      source: source,
      destination: destination,
      files: [(await source.stat('/input/source.txt'))!],
      destinationDirectory: '/output',
      options: options,
    );
    return journal.create('archive_create_saved', plan);
  }

  Future<void> receipt(TransferJobRecord job, List<int> bytes) async {
    final first = job.entries.first;
    final entry = FileOperationEntry(first.source, first.destination)
      ..recovery = {
        ...first.recovery,
        'archivePublication': {
          'phase': 'committing',
          'destination': '/output/saved.zip',
          'packedBytes': bytes.length,
          'packedSha256': sha256.convert(bytes).toString(),
          'entryCount': 1,
          'sourceManifestSha256': 'a' * 64,
        },
      };
    await journal.checkpoint(job.id, 0, entry, 'committing');
  }

  test(
    'password is never journaled and must be supplied again after restart',
    () async {
      await recipe(
        options: const ArchiveCreationOptions(
          name: 'private.7z',
          format: ArchiveCreationFormat.sevenZip,
          password: 'do-not-persist-this-password',
          encryptNames: true,
        ),
      );
      final replay = TransferJournal(storage);
      await replay.initialize();
      final definition = ArchiveCreationJobDefinition.fromJob(
        replay.jobs.single,
      );
      expect(definition.passwordRequired, isTrue);
      expect(definition.encryptNames, isTrue);
      expect(() => definition.options(), throwsStateError);
      expect(
        definition.options(password: 'entered-again').password,
        'entered-again',
      );
      expect(
        storage.lines.join(),
        isNot(contains('do-not-persist-this-password')),
      );
      expect(replay.jobs.single.status, TransferJobStatus.interrupted);
    },
  );

  test(
    'review of an absent output is read-only and binds the original accounts',
    () async {
      final job = await recipe();
      final review = await service.prepareCreation(
        job,
        source: source,
        destination: destination,
      );
      expect(review.alreadyPublished, isFalse);
      expect(review.definition.name, 'saved.zip');
      expect(destination.writes, isEmpty);
      await expectLater(
        service.prepareCreation(
          job,
          source: source,
          destination: QueueArchiveBackend('another-account'),
        ),
        throwsStateError,
      );
    },
  );

  test('lost completion acknowledgement reconciles only the full recorded output hash', () async {
    final job = await recipe();
    final bytes = utf8.encode('candidate bytes');
    await receipt(job, bytes);
    destination.put('/output/saved.zip', bytes);
    // A completed archive remains valid when an input later goes away.
    source.contents.remove('/input/source.txt');
    final review = await service.prepareCreation(
      journal.job(job.id)!,
      source: source,
      destination: destination,
    );
    expect(review.alreadyPublished, isTrue);
    expect(review.result!.bytes, bytes.length);
    expect(destination.writes, isEmpty);
    destination.put('/output/saved.zip', utf8.encode('different bytes'));
    await expectLater(
      service.prepareCreation(
        journal.job(job.id)!,
        source: source,
        destination: destination,
      ),
      throwsStateError,
    );
    expect(
      destination.contents['/output/saved.zip'],
      utf8.encode('different bytes'),
    );
  });

  test('an occupied output without a receipt is never overwritten', () async {
    final job = await recipe();
    destination.put('/output/saved.zip', [4, 5, 6]);
    await expectLater(
      service.prepareCreation(job, source: source, destination: destination),
      throwsStateError,
    );
    expect(destination.contents['/output/saved.zip'], [4, 5, 6]);
  });

  test(
    'a pause invalidates an existing-output proof when its read prefix changes',
    () async {
      final control = FileOperationControl();
      final pausing = _PausingOutputBackend(control);
      destination = pausing;
      final job = await recipe();
      final bytes = Uint8List.fromList(List.generate(65536, (i) => i % 251));
      await receipt(job, bytes);
      destination.put('/output/saved.zip', bytes);
      final before = (await destination.stat('/output/saved.zip'))!;
      final verification = service.prepareCreation(
        journal.job(job.id)!,
        source: source,
        destination: destination,
        control: control,
      );
      final rejected = expectLater(verification, throwsStateError);
      await pausing.prefixRead.future;
      expect(control.isPaused, isTrue);
      final changed = Uint8List.fromList(bytes)..[0] ^= 0xff;
      destination.put('/output/saved.zip', changed);
      final after = (await destination.stat('/output/saved.zip'))!;
      expect(after.size, before.size);
      expect(after.updatedAt, before.updatedAt);
      control.resume();
      await rejected;
      expect(pausing.outputReads, 2);
      expect(destination.contents['/output/saved.zip'], changed);
      expect(destination.writes, isEmpty);
    },
  );

  test('changed sources or revoked original account block restart', () async {
    final job = await recipe();
    source.put('/input/source.txt', [1]);
    await expectLater(
      service.prepareCreation(job, source: source, destination: destination),
      throwsStateError,
    );
    source.put('/input/source.txt', [1, 2, 3]);
    source.current = false;
    await expectLater(
      service.prepareCreation(job, source: source, destination: destination),
      throwsStateError,
    );
  });

  test('generic transfer execution, recovery and backup restore refuse archive recipes', () async {
    final job = await recipe();
    final gate = FileOperationControl();
    await expectLater(
      const TransferRecoveryService().prepare(
        job,
        source: source,
        destination: destination,
        control: gate,
      ),
      throwsStateError,
    );
    await expectLater(
      const TransferRecoveryService().restoreBackup(
        job,
        job.entries.first,
        destination,
        gate,
      ),
      throwsStateError,
    );
    final plan = archiveCreationJobPlan(
      source: source,
      destination: destination,
      files: [(await source.stat('/input/source.txt'))!],
      destinationDirectory: '/output',
      options: const ArchiveCreationOptions(name: 'saved.zip'),
    );
    await expectLater(
      JournaledTransferRunner(journal).execute(job.id, plan, control: gate),
      throwsStateError,
    );
    expect(destination.writes, isEmpty);
  });

  test('damaged archive marker remains classified as archive and cannot become a copy', () async {
    final job = await recipe();
    job.entries.first.recovery.clear();
    expect(isArchiveTransferJob(job), isTrue);
    expect(
      () => ArchiveCreationJobDefinition.fromJob(job),
      throwsFormatException,
    );
    await expectLater(
      const TransferRecoveryService().prepare(
        job,
        source: source,
        destination: destination,
        control: FileOperationControl(),
      ),
      throwsStateError,
    );
  });

  test(
    'recipe destination and receipt paths cannot be redirected independently',
    () async {
      final job = await recipe();
      job.entries.first.recovery['name'] = 'other.zip';
      await expectLater(
        service.prepareCreation(job, source: source, destination: destination),
        throwsFormatException,
      );
    },
  );
}

import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/models/archive_job.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/archive_creation_batch.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_queue_fixture.dart';

class _Backend extends QueueArchiveBackend {
  _Backend(super.account);
  int sourceReads = 0;
  bool verifiedWrites = true;
  Future<void> Function(String path)? beforeStat;
  @override
  bool get supportsStagedVerification => verifiedWrites;
  @override
  Future<FileItem?> stat(String path) async {
    await beforeStat?.call(path);
    return super.stat(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    sourceReads++;
    yield* super.readFile(file);
  }
}

class _AdmissionStorage extends MemoryTransferJournalStorage {
  bool gate = false;
  int gatedAdmission = 2;
  bool failSecond = false;
  bool failAfterWrite = false;
  int headers = 0;
  String? secondId;
  String? _gatedId;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool _handled = false;

  @override
  Future<void> append(String line) async {
    final event = decodeTransferEvent(line);
    if (event['kind'] == 'header') {
      headers++;
      if (headers == 2) secondId = event['id'] as String;
      if (headers == gatedAdmission) _gatedId = event['id'] as String;
    }
    if (!_handled &&
        event['id'] == _gatedId &&
        event['kind'] == 'state' &&
        event['ready'] == true) {
      _handled = true;
      if (gate) {
        entered.complete();
        await release.future;
      }
      if (failSecond) {
        if (failAfterWrite) await super.append(line);
        throw StateError('Second admission checkpoint was not acknowledged.');
      }
    }
    await super.append(line);
  }
}

Future<void> _turn() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _AdmissionStorage storage;
  late TransferJournal journal;
  late ProviderContainer container;
  late TransferNotifier transfers;
  late _Backend source, destination;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = _AdmissionStorage();
    journal = TransferJournal(storage);
    container = ProviderContainer(
      overrides: [transferJournalProvider.overrideWithValue(journal)],
    );
    transfers = container.read(transferProvider);
    await transfers.ready;
    source = _Backend('source')
      ..put('/input/first.txt', utf8.encode('first payload'))
      ..put('/input/second.txt', utf8.encode('second payload'));
    destination = _Backend('destination');
  });

  tearDown(() async {
    if (!storage.release.isCompleted) storage.release.complete();
    transfers.cancelAllOperations();
    await _turn();
    container.dispose();
  });

  Future<List<ArchiveCreationBatchItem>> items({
    ArchiveCreationOptions options = const ArchiveCreationOptions(
      name: 'unused.zip',
    ),
  }) async => planArchiveCreationBatch(
    files: [
      (await source.stat('/input/first.txt'))!,
      (await source.stat('/input/second.txt'))!,
    ],
    destinationDirectory: '/output',
    options: options,
  );

  test(
    'all output recipes are durable before either canonical worker starts',
    () async {
      storage.gate = true;
      final pending = transfers.enqueueArchiveCreationBatch(
        source: source,
        destination: destination,
        items: await items(),
      );
      await storage.entered.future.timeout(const Duration(seconds: 5));
      await _turn();
      expect(journal.jobs.where((job) => job.ready).length, 1);
      expect(transfers.queuedCount, 1);
      expect(source.sourceReads, 0);
      expect(destination.writes, isEmpty);
      storage.release.complete();
      final handles = await pending;
      expect(handles, hasLength(2));
      expect(handles.every((handle) => journal.job(handle.id)!.ready), isTrue);
      expect(() => handles.clear(), throwsUnsupportedError);
      await Future.wait(handles.map((handle) => handle.completion));
      expect(handles.every((handle) => handle.error == null), isTrue);
      expect(destination.writes, [
        '/output/first.txt.zip',
        '/output/second.txt.zip',
      ]);
      for (final name in ['first', 'second']) {
        final archive = codecs.ZipDecoder().decodeBytes(
          destination.contents['/output/$name.txt.zip']!,
        );
        expect(
          utf8.decode(archive.findFile('$name.txt')!.content as List<int>),
          '$name payload',
        );
      }
      expect(
        journal.jobs.every((job) => job.status == TransferJobStatus.completed),
        isTrue,
      );
    },
  );

  test('a collision at the last output refuses the whole batch before journal admission', () async {
    destination.put('/output/second.txt.zip', [9]);
    await expectLater(
      transfers.enqueueArchiveCreationBatch(
        source: source,
        destination: destination,
        items: await items(),
      ),
      throwsA(
        isA<ArchiveCreationException>().having(
          (error) => error.code,
          'code',
          ArchiveCreationError.destinationExists,
        ),
      ),
    );
    expect(journal.jobs, isEmpty);
    expect(transfers.queuedCount, 0);
    expect(source.sourceReads, 0);
    expect(destination.writes, isEmpty);
    expect(destination.contents['/output/second.txt.zip'], [9]);
  });

  test(
    'duplicate output aliases are refused before creating any durable job',
    () async {
      final plans = await items();
      await expectLater(
        transfers.enqueueArchiveCreationBatch(
          source: source,
          destination: destination,
          items: [
            plans.first,
            ArchiveCreationBatchItem(
              files: plans.last.files,
              destinationDirectory: '/output',
              options: const ArchiveCreationOptions(name: 'FIRST.TXT.ZIP'),
            ),
          ],
        ),
        throwsStateError,
      );
      expect(journal.jobs, isEmpty);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'a later invalid option is rejected before a valid prefix is admitted',
    () async {
      final plans = await items();
      await expectLater(
        transfers.enqueueArchiveCreationBatch(
          source: source,
          destination: destination,
          items: [
            plans.first,
            ArchiveCreationBatchItem(
              files: plans.last.files,
              destinationDirectory: '/output',
              options: const ArchiveCreationOptions(name: '../invalid.zip'),
            ),
          ],
        ),
        throwsA(isA<ArchiveCreationException>()),
      );
      expect(journal.jobs, isEmpty);
      expect(source.sourceReads, 0);
    },
  );

  test(
    'all destination directories must exist before the first admission',
    () async {
      final plans = await items();
      await expectLater(
        transfers.enqueueArchiveCreationBatch(
          source: source,
          destination: destination,
          items: [
            plans.first,
            ArchiveCreationBatchItem(
              files: plans.last.files,
              destinationDirectory: '/absent',
              options: plans.last.options,
            ),
          ],
        ),
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.invalidDestination,
          ),
        ),
      );
      expect(journal.jobs, isEmpty);
      expect(source.sourceReads, 0);
    },
  );

  test(
    'destinations without staged verification are rejected before admission',
    () async {
      destination.verifiedWrites = false;
      await expectLater(
        transfers.enqueueArchiveCreationBatch(
          source: source,
          destination: destination,
          items: await items(),
        ),
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.invalidDestination,
          ),
        ),
      );
      expect(journal.jobs, isEmpty);
    },
  );

  test(
    'account loss during output preflight does not admit a prefix',
    () async {
      destination.beforeStat = (path) async {
        if (path == '/output/second.txt.zip') source.current = false;
      };
      await expectLater(
        transfers.enqueueArchiveCreationBatch(
          source: source,
          destination: destination,
          items: await items(),
        ),
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.sourceUnavailable,
          ),
        ),
      );
      expect(journal.jobs, isEmpty);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'empty, oversized batches and excessive roots never enter the journal',
    () async {
      final plans = await items();
      for (final invalid in <List<ArchiveCreationBatchItem>>[
        [],
        List.filled(129, plans.first),
        [
          ArchiveCreationBatchItem(
            files: List.filled(5001, plans.first.files.single),
            destinationDirectory: '/output',
            options: plans.first.options,
          ),
        ],
      ]) {
        await expectLater(
          transfers.enqueueArchiveCreationBatch(
            source: source,
            destination: destination,
            items: invalid,
          ),
          throwsA(anyOf(isA<StateError>(), isA<ArchiveCreationException>())),
        );
      }
      expect(journal.jobs, isEmpty);
    },
  );

  test('recipe capture owns selection lists and revision metadata before its first wait', () async {
    await transfers.setQueuePaused(true);
    final revision = <String, dynamic>{'revision': 'reviewed'};
    final selected = (await source.stat('/input/first.txt'))!
        .copyWith(metadata: revision);
    final plans = [
      ArchiveCreationBatchItem(
        files: [selected],
        destinationDirectory: '/output',
        options: const ArchiveCreationOptions(name: 'captured.zip'),
      ),
    ];
    final pending = transfers.enqueueArchiveCreationBatch(
      source: source,
      destination: destination,
      items: plans,
    );
    plans.clear();
    revision['revision'] = 'changed after review';
    final handle = (await pending).single;
    final recipe = ArchiveCreationJobDefinition.fromJob(
      journal.job(handle.id)!,
    );
    expect(recipe.files.single.path, '/input/first.txt');
    expect(recipe.files.single.metadata!['revision'], 'reviewed');
    expect(source.sourceReads, 0);
    transfers.cancelOperation(handle.id);
    await handle.completion;
  });

  test(
    'batch recipes retain protection options without storing password values',
    () async {
      await transfers.setQueuePaused(true);
      final handles = await transfers.enqueueArchiveCreationBatch(
        source: source,
        destination: destination,
        items: await items(
          options: const ArchiveCreationOptions(
            name: 'unused.7z',
            format: ArchiveCreationFormat.sevenZip,
            compression: ArchiveCreationCompression.lzma2,
            password: 'ephemeral-test-secret',
            encryptNames: true,
          ),
        ),
      );
      for (final handle in handles) {
        final recipe = ArchiveCreationJobDefinition.fromJob(
          journal.job(handle.id)!,
        );
        expect(recipe.passwordRequired, isTrue);
        expect(recipe.encryptNames, isTrue);
        expect(recipe.compression, ArchiveCreationCompression.lzma2);
      }
      expect(storage.lines.join(), isNot(contains('ephemeral-test-secret')));
      transfers.cancelAllOperations();
      await Future.wait(handles.map((handle) => handle.completion));
    },
  );

  for (final afterWrite in [false, true]) {
    test(
      'a ${afterWrite ? 'lost' : 'failed'} second admission acknowledgement cancels the durable prefix',
      () async {
        storage
          ..failSecond = true
          ..failAfterWrite = afterWrite;
        await expectLater(
          transfers.enqueueArchiveCreationBatch(
            source: source,
            destination: destination,
            items: await items(),
          ),
          throwsStateError,
        );
        await _turn();
        expect(source.sourceReads, 0);
        expect(destination.writes, isEmpty);
        expect(transfers.queuedCount, 0);
        expect(
          transfers.savedJobs.every((job) => !transfers.isJobLive(job.id)),
          isTrue,
        );
        expect(
          journal.jobs.where((job) => job.id != storage.secondId).single.status,
          TransferJobStatus.cancelled,
        );
        final replay = TransferJournal(storage);
        await replay.initialize();
        expect(
          replay.jobs.any(
            (job) =>
                job.status == TransferJobStatus.running ||
                job.status == TransferJobStatus.queued,
          ),
          isFalse,
        );
        expect(destination.writes, isEmpty);
      },
    );
  }

  for (final admission in [1, 2]) {
    test(
      'Stop all during admission $admission prevents every batch worker from starting',
      () async {
        storage
          ..gate = true
          ..gatedAdmission = admission;
        final pending = transfers.enqueueArchiveCreationBatch(
          source: source,
          destination: destination,
          items: await items(),
        );
        final rejection = expectLater(
          pending,
          throwsA(isA<FileOperationCancelled>()),
        );
        await storage.entered.future.timeout(const Duration(seconds: 5));
        transfers.cancelAllOperations();
        storage.release.complete();
        await rejection;
        await _turn();
        expect(source.sourceReads, 0);
        expect(destination.writes, isEmpty);
        expect(transfers.queuedCount, 0);
        expect(
          journal.jobs.every(
            (job) => job.status == TransferJobStatus.cancelled,
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'Stop all during output preflight prevents the first journal admission',
    () async {
      destination.beforeStat = (path) async {
        transfers.cancelAllOperations();
      };
      await expectLater(
        transfers.enqueueArchiveCreationBatch(
          source: source,
          destination: destination,
          items: await items(),
        ),
        throwsA(isA<FileOperationCancelled>()),
      );
      expect(journal.jobs, isEmpty);
      expect(source.sourceReads, 0);
      expect(destination.writes, isEmpty);
    },
  );

  test('batch admission preserves shared queue pause, priority and scheduled start', () async {
    await transfers.setQueuePaused(true);
    final scheduled = DateTime.now().toUtc().add(const Duration(days: 1));
    final handles = await transfers.enqueueArchiveCreationBatch(
      source: source,
      destination: destination,
      items: await items(),
      priority: 7,
      notBefore: scheduled,
    );
    expect(transfers.queuePaused, isTrue);
    expect(source.sourceReads, 0);
    for (final handle in handles) {
      expect(transfers.isQueued(handle.id), isTrue);
      expect(journal.job(handle.id)!.priority, 7);
      expect(journal.job(handle.id)!.scheduledAt, scheduled);
      expect(journal.job(handle.id)!.source, source.storageReference);
      expect(journal.job(handle.id)!.destination, destination.storageReference);
    }
    transfers.cancelAllOperations();
    await Future.wait(handles.map((handle) => handle.completion));
  });

  test(
    'fully admitted jobs retain independent failure and publication results',
    () async {
      destination.beforeStageVerification = () {
        destination.beforeStageVerification = null;
        throw StateError('First candidate verification failed.');
      };
      var created = 0;
      final handles = await transfers.enqueueArchiveCreationBatch(
        source: source,
        destination: destination,
        items: await items(),
        onCreated: () => created++,
      );
      await Future.wait(handles.map((handle) => handle.completion));
      expect(handles.first.error, isNotNull);
      expect(handles.last.error, isNull);
      expect(journal.job(handles.first.id)!.status, TransferJobStatus.failed);
      expect(journal.job(handles.last.id)!.status, TransferJobStatus.completed);
      expect(
        destination.contents.containsKey('/output/first.txt.zip'),
        isFalse,
      );
      expect(
        destination.contents.containsKey('/output/second.txt.zip'),
        isTrue,
      );
      expect(created, 1);
    },
  );
}

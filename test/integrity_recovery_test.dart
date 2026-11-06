import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/file_integrity_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/file_split_service.dart';
import 'package:crisp_cloud/services/integrity_recovery_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Backend source;
  late _Backend destination;
  late MemoryTransferJournalStorage storage;
  late TransferJournal journal;
  late IntegrityRecoveryService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = _Backend('source')
      ..put('/data.bin', List.generate(10, (index) => index));
    destination = _Backend('destination');
    storage = MemoryTransferJournalStorage();
    journal = TransferJournal(storage);
    service = IntegrityRecoveryService(journal);
  });

  Future<TransferJobRecord> prepareSplit() => service.prepareSplit(
    source: source,
    file: source.item('/data.bin')!,
    destination: destination,
    targetDirectory: '/',
    chunkSizeBytes: 3,
  );

  Future<String> interruptSplit({String path = '/data.bin.part002'}) async {
    final job = await prepareSplit();
    final review = await service.review(
      job.id,
      source: source,
      destination: destination,
    );
    destination.failAfterCommit = path;
    await expectLater(
      service.resume(review, source: source, destination: destination),
      throwsStateError,
    );
    destination.failAfterCommit = null;
    return job.id;
  }

  Future<void> reopen() async {
    journal = TransferJournal(storage);
    await journal.initialize();
    service = IntegrityRecoveryService(journal);
  }

  Future<TransferJobRecord> prepareCombine() async {
    await service.startSplit(
      source: source,
      file: source.item('/data.bin')!,
      destination: destination,
      targetDirectory: '/',
      chunkSizeBytes: 3,
    );
    return service.prepareCombine(
      source: destination,
      destination: source,
      manifestFile: destination.item('/data.bin.split.json'),
      outputPath: '/combined.bin',
    );
  }

  test(
    'whole-source evidence is saved before the first output mutation',
    () async {
      final job = await prepareSplit();
      expect(destination.writes, isEmpty);
      expect(job.entries, hasLength(5));
      final hash = ChecksumAccumulator(ChecksumAlgorithm.sha256)
        ..add(source.files['/data.bin']!);
      expect(job.entries.first.recovery['expectedSha256'], hash.finish());
      expect(
        job.entries
            .skip(1)
            .every((entry) => entry.recovery['partSha256'] is String),
        isTrue,
      );
      final review = await service.review(
        job.id,
        source: source,
        destination: destination,
      );
      await service.resume(review, source: source, destination: destination);
      expect(journal.job(job.id)!.status, TransferJobStatus.completed);
      final manifest = SplitManifest.decode(
        destination.files['/data.bin.split.json']!,
      );
      expect(manifest.status, SplitManifestStatus.complete);
      expect(manifest.parts, hasLength(4));
      expect([
        for (final part in manifest.parts)
          ...destination.files['/${part.path}']!,
      ], source.files['/data.bin']);
    },
  );

  test('restart reconciles an unacknowledged part and resumes only remaining parts', () async {
    final id = await interruptSplit();
    expect(destination.files['/data.bin.part002'], [3, 4, 5]);
    await reopen();
    final review = await service.review(
      id,
      source: source,
      destination: destination,
    );
    expect(review.verifiedParts, 2);
    await service.resume(review, source: source, destination: destination);
    for (var i = 1; i <= 4; i++) {
      expect(
        destination.writes.where(
          (path) => path == FileSplitService.partName('/data.bin', i),
        ),
        hasLength(1),
      );
    }
    expect(journal.job(id)!.status, TransferJobStatus.completed);
    expect(
      SplitManifest.decode(destination.files['/data.bin.split.json']!).status,
      SplitManifestStatus.complete,
    );
    expect(source.files['/data.bin'], List.generate(10, (index) => index));
  });

  test(
    'cancel after part commit retains a resumable part with no duplicate bytes',
    () async {
      final control = FileOperationControl();
      String? id;
      destination.onCommitted = (path) {
        if (path == '/data.bin.part001') control.cancel();
      };
      await expectLater(
        service.startSplit(
          source: source,
          file: source.item('/data.bin')!,
          destination: destination,
          targetDirectory: '/',
          chunkSizeBytes: 3,
          control: control,
          onJobCreated: (value) => id = value,
        ),
        throwsA(
          anyOf(isA<FileOperationCancelled>(), isA<FileIntegrityCancelled>()),
        ),
      );
      expect(journal.job(id!)!.status, TransferJobStatus.cancelled);
      destination.onCommitted = null;
      await reopen();
      final review = await service.review(
        id!,
        source: source,
        destination: destination,
      );
      expect(review.verifiedParts, 1);
      await service.resume(review, source: source, destination: destination);
      expect(
        destination.writes.where((path) => path == '/data.bin.part001'),
        hasLength(1),
      );
      expect(destination.files['/data.bin.part004'], [9]);
    },
  );

  test('a same-size same-metadata rewrite of the unsplit suffix blocks every further write', () async {
    final id = await interruptSplit(path: '/data.bin.part001');
    source.replaceBytes('/data.bin', [0, 1, 2, 3, 4, 5, 99, 98, 97, 96]);
    await reopen();
    final writes = destination.writes.length;
    await expectLater(
      service.review(id, source: source, destination: destination),
      throwsStateError,
    );
    expect(destination.writes.length, writes);
    expect(destination.files['/data.bin.part001'], [0, 1, 2]);
    expect(destination.files['/data.bin.part003'], isNull);
  });

  test(
    'changed completed parts and changed manifest definitions stay untouched',
    () async {
      final id = await interruptSplit();
      destination.replaceBytes('/data.bin.part001', [9, 9, 9]);
      await reopen();
      final writes = destination.writes.length;
      await expectLater(
        service.review(id, source: source, destination: destination),
        throwsStateError,
      );
      expect(destination.files['/data.bin.part001'], [9, 9, 9]);
      destination.replaceBytes('/data.bin.part001', [0, 1, 2]);
      final original = SplitManifest.decode(
        destination.files['/data.bin.split.json']!,
      );
      final changed = SplitManifest(
        originalName: 'other.bin',
        totalBytes: original.totalBytes,
        chunkSize: original.chunkSize,
        status: original.status,
        parts: original.parts,
      );
      destination.replaceBytes('/data.bin.split.json', changed.encode());
      await expectLater(
        service.review(id, source: source, destination: destination),
        throwsStateError,
      );
      expect(destination.writes.length, writes);
    },
  );

  test('newly occupied part names are not adopted or overwritten without a saved intent', () async {
    final job = await prepareSplit();
    destination.put('/data.bin.part004', [9]);
    await expectLater(
      service.review(job.id, source: source, destination: destination),
      throwsStateError,
    );
    expect(destination.writes, isEmpty);
    expect(destination.files['/data.bin.part004'], [9]);
  });

  test('source account, destination account and replaced directory cannot redirect recovery', () async {
    final id = await interruptSplit();
    await reopen();
    await expectLater(
      service.review(
        id,
        source: _Backend('other')..put('/data.bin', source.files['/data.bin']!),
        destination: destination,
      ),
      throwsStateError,
    );
    await expectLater(
      service.review(id, source: source, destination: _Backend('other')),
      throwsStateError,
    );
    destination.directoryId = 'replacement';
    final writes = destination.writes.length;
    await expectLater(
      service.review(id, source: source, destination: destination),
      throwsStateError,
    );
    expect(destination.writes.length, writes);
  });

  test(
    'combine restart recognizes a fully committed output after a lost response',
    () async {
      final job = await prepareCombine();
      final review = await service.review(
        job.id,
        source: destination,
        destination: source,
      );
      source.failAfterCommit = '/combined.bin';
      await expectLater(
        service.resume(review, source: destination, destination: source),
        throwsStateError,
      );
      source.failAfterCommit = null;
      await reopen();
      final recovered = await service.review(
        job.id,
        source: destination,
        destination: source,
      );
      expect(recovered.reconcilesOutput, isTrue);
      final writes = source.writes.length;
      await service.resume(recovered, source: destination, destination: source);
      expect(source.writes.length, writes);
      expect(source.files['/combined.bin'], source.files['/data.bin']);
      expect(journal.job(job.id)!.status, TransferJobStatus.completed);
    },
  );

  test('combine restarts unfinished staging from verified inputs without appending bytes', () async {
    final job = await prepareCombine();
    final review = await service.review(
      job.id,
      source: destination,
      destination: source,
    );
    source.failDuringWrite = '/combined.bin';
    await expectLater(
      service.resume(review, source: destination, destination: source),
      throwsStateError,
    );
    source.failDuringWrite = null;
    await reopen();
    final recovered = await service.review(
      job.id,
      source: destination,
      destination: source,
    );
    expect(recovered.retainedPaths, hasLength(1));
    final retained = recovered.retainedPaths.single;
    final partial = List<int>.of(source.files[retained]!);
    await service.resume(recovered, source: destination, destination: source);
    expect(source.files['/combined.bin'], source.files['/data.bin']);
    expect(source.files[retained], partial);
    expect(journal.job(job.id)!.status, TransferJobStatus.completed);
  });

  test(
    'same-metadata input changes and occupied combine outputs block recovery',
    () async {
      final job = await prepareCombine();
      destination.replaceBytes('/data.bin.part003', [6, 7, 99]);
      await reopen();
      await expectLater(
        service.review(job.id, source: destination, destination: source),
        throwsStateError,
      );
      expect(source.writes, isEmpty);
      destination.replaceBytes('/data.bin.part003', [6, 7, 8]);
      source.put('/combined.bin', [9, 9, 9]);
      await expectLater(
        service.review(job.id, source: destination, destination: source),
        throwsStateError,
      );
      expect(source.files['/combined.bin'], [9, 9, 9]);
      expect(source.writes, isEmpty);
    },
  );

  test('changes after recovery review prevent execution', () async {
    final id = await interruptSplit();
    final reviewed = await service.review(
      id,
      source: source,
      destination: destination,
    );
    destination.replaceBytes('/data.bin.part002', [9, 9, 9]);
    final writes = destination.writes.length;
    await expectLater(
      service.resume(reviewed, source: source, destination: destination),
      throwsStateError,
    );
    expect(destination.writes.length, writes);
    expect(destination.files['/data.bin.part002'], [9, 9, 9]);
  });

  test('service admission rejects a concurrent resume and history sees it as active', () async {
    final job = await prepareSplit();
    final reviewed = await service.review(
      job.id,
      source: source,
      destination: destination,
    );
    final started = Completer<void>();
    final release = Completer<void>();
    source.beforeRead = (_) async {
      if (!started.isCompleted) {
        started.complete();
        await release.future;
      }
    };
    final container = ProviderContainer(
      overrides: [transferJournalProvider.overrideWithValue(journal)],
    );
    addTearDown(container.dispose);
    final transfers = container.read(transferProvider);
    await transfers.ready;
    final first = service.resume(
      reviewed,
      source: source,
      destination: destination,
    );
    await started.future;
    expect(transfers.isJobLive(job.id), isTrue);
    await transfers.refreshIntegrityHistory();
    expect(
      transfers.operations.where((operation) => operation.id == job.id),
      isEmpty,
    );
    await expectLater(
      IntegrityRecoveryService(journal)
          .resume(reviewed, source: source, destination: destination),
      throwsStateError,
    );
    await expectLater(service.forget(job.id), throwsStateError);
    await expectLater(transfers.dismissSavedJob(job.id), throwsStateError);
    release.complete();
    await first;
    expect(transfers.isJobLive(job.id), isFalse);
    await transfers.refreshIntegrityHistory();
    expect(transfers.operations.single.status, OperationStatus.completed);
    expect(transfers.operations.single.totalBytes, 10);
    expect(transfers.operations.single.currentBytes, 10);
    await service.forget(job.id);
    await transfers.refreshIntegrityHistory();
    expect(transfers.operations, isEmpty);
    expect(
      destination.writes.where((path) => path == '/data.bin.part001'),
      hasLength(1),
    );
  });

  test('restart does not enqueue integrity jobs or permit generic transfer execution', () async {
    final job = await prepareSplit();
    await reopen();
    final restored = journal.job(job.id)!;
    expect(restored.status, TransferJobStatus.interrupted);
    final container = ProviderContainer(
      overrides: [transferJournalProvider.overrideWithValue(journal)],
    );
    addTearDown(container.dispose);
    final transfers = container.read(transferProvider);
    await transfers.ready;
    expect(transfers.queuedIds, isEmpty);
    final plan = FileOperationPlan(
      source: source,
      destination: destination,
      targetDirectory: '/',
      options: const FileOperationOptions(),
      entries: [
        for (final entry in restored.entries)
          FileOperationEntry(entry.source, entry.destination),
      ],
      errors: const [],
    );
    await expectLater(
      const TransferRecoveryService().prepare(
        restored,
        source: source,
        destination: destination,
        control: FileOperationControl(),
      ),
      throwsStateError,
    );
    await expectLater(
      JournaledTransferRunner(TransferJournal(storage))
          .execute(job.id, plan, control: FileOperationControl()),
      throwsStateError,
    );
    await expectLater(
      transfers.runFileOperation(
        plan,
        recoveryJobId: job.id,
        control: FileOperationControl(),
      ),
      throwsStateError,
    );
    await expectLater(
      const TransferRecoveryService().restoreBackup(
        restored,
        restored.entries.first,
        destination,
        FileOperationControl(),
      ),
      throwsStateError,
    );
    expect(
      journal.job(job.id)!.entries.first.recovery['integrityKind'],
      'split',
    );
    expect(destination.writes, isEmpty);
  });

  test('cancelling the initial full-source evidence pass stops a pending stream without outputs', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    source.beforeRead = (_) async {
      started.complete();
      await release.future;
    };
    final control = FileOperationControl();
    final operation = service.startSplit(
      source: source,
      file: source.item('/data.bin')!,
      destination: destination,
      targetDirectory: '/',
      chunkSizeBytes: 3,
      control: control,
    );
    final result = expectLater(
      operation,
      throwsA(
        anyOf(isA<FileOperationCancelled>(), isA<FileIntegrityCancelled>()),
      ),
    );
    await started.future;
    control.cancel();
    await result.timeout(const Duration(seconds: 3));
    release.complete();
    expect(destination.writes, isEmpty);
    expect(journal.jobs, isEmpty);
  });

  test(
    'forgetting recovery keeps every source, part, manifest and retained stage',
    () async {
      final id = await interruptSplit();
      final snapshot = jsonEncode(destination.files);
      await service.forget(id);
      await reopen();
      expect(journal.job(id), isNull);
      expect(jsonEncode(destination.files), snapshot);
      expect(source.files['/data.bin'], List.generate(10, (index) => index));
    },
  );

  test(
    'failed persistence of the first staging intent prevents all output writes',
    () async {
      final faulty = _FailingStorage();
      storage = faulty;
      journal = TransferJournal(storage);
      service = IntegrityRecoveryService(journal);
      final job = await prepareSplit();
      final review = await service.review(
        job.id,
        source: source,
        destination: destination,
      );
      faulty.failStaging = true;
      await expectLater(
        service.resume(review, source: source, destination: destination),
        throwsStateError,
      );
      expect(destination.files, isEmpty);
      expect(destination.writes, isEmpty);
      await reopen();
      final retried = await service.review(
        job.id,
        source: source,
        destination: destination,
      );
      await service.resume(retried, source: source, destination: destination);
      expect(journal.job(job.id)!.status, TransferJobStatus.completed);
    },
  );

  test('empty files retain one verified empty part and completed recovery is idempotent', () async {
    source.put('/empty.bin', []);
    String? id;
    final result = await service.startSplit(
      source: source,
      file: source.item('/empty.bin')!,
      destination: destination,
      targetDirectory: '/',
      chunkSizeBytes: 3,
      onJobCreated: (value) => id = value,
    );
    expect(result.manifest.parts.single.size, 0);
    expect(destination.files['/empty.bin.part001'], isEmpty);
    await reopen();
    final review = await service.review(
      id!,
      source: source,
      destination: destination,
    );
    final writes = destination.writes.length;
    await service.resume(review, source: source, destination: destination);
    expect(destination.writes.length, writes);
    expect(journal.job(id!)!.status, TransferJobStatus.completed);
  });

  test('legacy combination requires consent and retains restart-verifiable input hashes', () async {
    source.put('/legacy.part001', [1, 2, 3]);
    source.put('/legacy.part002', [4]);
    final parts = [
      source.item('/legacy.part001')!,
      source.item('/legacy.part002')!,
    ];
    await expectLater(
      service.prepareCombine(
        source: source,
        destination: destination,
        outputPath: '/legacy.bin',
        legacyParts: parts,
      ),
      throwsStateError,
    );
    expect(journal.jobs, isEmpty);
    final job = await service.prepareCombine(
      source: source,
      destination: destination,
      outputPath: '/legacy.bin',
      legacyParts: parts,
      allowUnverifiedLegacy: true,
    );
    final review = await service.review(
      job.id,
      source: source,
      destination: destination,
    );
    destination.failAfterCommit = '/legacy.bin';
    await expectLater(
      service.resume(review, source: source, destination: destination),
      throwsStateError,
    );
    destination.failAfterCommit = null;
    await reopen();
    final recovered = await service.review(
      job.id,
      source: source,
      destination: destination,
    );
    expect(recovered.reconcilesOutput, isTrue);
    await service.resume(recovered, source: source, destination: destination);
    expect(destination.files['/legacy.bin'], [1, 2, 3, 4]);
    expect(destination.writes, ['/legacy.bin']);
  });
}

class _FailingStorage extends MemoryTransferJournalStorage {
  bool failStaging = false;
  @override
  Future<void> append(String line) async {
    final event = decodeTransferEvent(line);
    if (failStaging &&
        event['kind'] == 'entries' &&
        (event['entries'] as List).any(
          (entry) => (entry as Map)['phase'] == 'staging',
        )) {
      failStaging = false;
      throw StateError('The staging intent was not persisted.');
    }
    await super.append(line);
  }
}

class _Backend extends FileOperationBackend {
  _Backend(this.account);
  final String account;
  final Map<String, List<int>> files = {};
  final Map<String, String> ids = {};
  final List<String> writes = [];
  String directoryId = 'original-directory';
  String? failAfterCommit;
  String? failDuringWrite;
  void Function(String path)? onCommitted;
  Future<void> Function(String path)? beforeRead;
  bool current = true;
  int _generation = 0;
  void put(String path, List<int> data) {
    files[path] = List.of(data);
    ids[path] = 'object-${++_generation}';
  }

  void replaceBytes(String path, List<int> data) => files[path] = List.of(data);
  FileItem? item(String path) => path == '/'
      ? FileItem(name: '/', path: '/', uuid: directoryId, isFolder: true)
      : files[path] == null
      ? null
      : FileItem(
          name: p.posix.basename(path),
          path: path,
          uuid: ids[path],
          isFolder: false,
          size: files[path]!.length,
          updatedAt: DateTime.utc(2026),
        );
  @override
  StorageReference get storageReference => StorageReference(
    kind: 'remote',
    provider: 'fixture',
    accountKey: account,
  );
  @override
  Object get identity => storageReference.id;
  @override
  bool get canRecover => true;
  @override
  bool get supportsStagedVerification => true;
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(
        boundedDownload: true,
        boundedUpload: true,
      );
  @override
  bool get isCurrent => current;
  @override
  String get label => account;
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) async => item(path);
  @override
  Future<List<FileItem>> list(String path) async => [
    for (final name in files.keys) item(name)!,
  ];
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    await beforeRead?.call(file.path!);
    final data = List<int>.of(files[file.path!]!);
    for (var i = 0; i < data.length; i += 2) {
      yield data.sublist(i, mathMin(i + 2, data.length));
    }
  }

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) async {
    if (!replace && files.containsKey(path)) {
      throw StateError('Occupied output');
    }
    final stage = '/.crisp-stage-${++_generation}';
    await checkpoint?.call({
      'phase': 'staging',
      'stagedPath': stage,
      'destination': path,
    });
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
      if (failDuringWrite == path) {
        put(stage, bytes);
        throw StateError('Simulated process interruption during staging');
      }
    }
    put(stage, bytes);
    await verifyStaged?.call(item(stage)!);
    await checkpoint?.call({
      'phase': 'committing',
      'stagedPath': stage,
      'destination': path,
    });
    if (!replace && files.containsKey(path)) {
      throw StateError('Occupied output');
    }
    put(path, bytes);
    files.remove(stage);
    ids.remove(stage);
    writes.add(path);
    onCommitted?.call(path);
    if (failAfterCommit == path) throw StateError('Lost commit response');
    await checkpoint?.call({'phase': 'committed', 'destination': path});
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => writePreparedFile(path, data, length, replace: replace);
  @override
  Future<void> createDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteEmptyDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw StateError('Recovery must not delete unverified files.');
}

int mathMin(int a, int b) => a < b ? a : b;

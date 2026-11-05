import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_journal_storage_io.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _MemoryBackend extends FileOperationBackend {
  _MemoryBackend(this.account);
  final String account;
  final Map<String, List<int>> bytes = {};
  final Set<String> directories = {'/', '/target'};
  final Map<String, DateTime> times = {};
  final List<int> rangeOffsets = [];
  bool current = true;
  bool loseMoveReply = false;
  bool loseDeleteReply = false;
  bool metadataFails = false;
  int? interruptAfter;
  int writes = 0;
  int stageCounter = 0;
  int clock = 0;
  @override
  StorageReference get storageReference =>
      StorageReference(kind: 'remote', provider: 'memory', accountKey: account);
  @override
  Object get identity => storageReference.id;
  @override
  String get persistentStorageId => storageReference.id;
  @override
  bool get canRecover => true;
  @override
  bool get supportsModifiedTime => true;
  @override
  bool get supportsStagedVerification => true;
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(
        setModifiedTime: true,
        readRanges: true,
      );
  @override
  String get label => account;
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => current;

  void file(String path, String content) {
    bytes[path] = utf8.encode(content);
    times[path] = DateTime.utc(2026, 1, 1).add(Duration(seconds: clock++));
  }

  @override
  Future<FileItem?> stat(String path) async {
    if (!current) throw StateError('Account disconnected');
    if (directories.contains(path)) {
      return FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: true,
        isSymlink: false,
      );
    }
    final data = bytes[path];
    return data == null
        ? null
        : FileItem(
            name: paths.basename(path),
            path: path,
            uuid: path,
            isFolder: false,
            isSymlink: false,
            size: data.length,
            updatedAt: times[path],
            metadata: const {'token': 'never-persist-this'},
          );
  }

  @override
  Future<List<FileItem>> list(String path) async => [
    for (final key in {...directories, ...bytes.keys})
      if (key != path && paths.dirname(key) == path) (await stat(key))!,
  ];
  @override
  Future<void> createDirectory(String path) async => directories.add(path);
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    final value = List<int>.of(bytes[file.path]!);
    for (var start = 0; start < value.length; start += 3) {
      yield value.sublist(start, (start + 3).clamp(0, value.length));
    }
  }

  @override
  Stream<List<int>> readRange(FileItem file, int offset) async* {
    rangeOffsets.add(offset);
    yield bytes[file.path]!.sublist(offset);
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => writePreparedFile(path, data, length, replace: replace);
  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    writes++;
    final stage = paths.join(
      paths.dirname(path),
      '.crisp-transfer-stage-${stageCounter++}',
    );
    await checkpoint?.call({
      'phase': 'staging',
      'stagedPath': stage,
      'destination': path,
    });
    bytes[stage] = [];
    times[stage] = DateTime.utc(2026);
    await for (final chunk in data) {
      bytes[stage]!.addAll(chunk);
      if (interruptAfter != null && bytes[stage]!.length >= interruptAfter!) {
        throw StateError('Connection interrupted; staged bytes remain.');
      }
    }
    if (length != null && bytes[stage]!.length != length) {
      throw StateError('Length mismatch');
    }
    await verifyStaged?.call((await stat(stage))!);
    await checkpoint?.call({
      'phase': 'committing',
      'stagedPath': stage,
      'destination': path,
    });
    if (!replace && bytes.containsKey(path)) {
      throw StateError('Occupied destination');
    }
    bytes[path] = bytes.remove(stage)!;
    times[path] = times.remove(stage)!;
    await checkpoint?.call({'phase': 'committed', 'destination': path});
  }

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    if (bytes.containsKey(destination)) {
      throw StateError('Occupied destination');
    }
    bytes[destination] = bytes.remove(file.path)!;
    times[destination] = times.remove(file.path)!;
    if (loseMoveReply) throw StateError('Move acknowledgement was lost');
    return true;
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    bytes.remove(file.path);
    times.remove(file.path);
    if (loseDeleteReply) throw StateError('Delete acknowledgement was lost');
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    if ((await list(path)).isNotEmpty) throw StateError('Directory not empty');
    directories.remove(path);
  }

  @override
  Future<void> setModified(String path, DateTime modified) async {
    if (metadataFails) throw StateError('Metadata denied');
    times[path] = modified;
  }
}

class _FailWritingIntent extends MemoryTransferJournalStorage {
  @override
  Future<void> append(String line) async {
    final event = decodeTransferEvent(line);
    if (event['kind'] == 'entries' &&
        (event['entries'] as List).any(
          (entry) => entry['phase'] == 'writing',
        )) {
      throw StateError('Disk is full');
    }
    await super.append(line);
  }
}

void main() {
  Future<FileOperationPlan> plan(
    _MemoryBackend source,
    _MemoryBackend target, {
    FileOperationOptions options = const FileOperationOptions(),
  }) async => const FileOperationService().prepare(
    source: source,
    destination: target,
    files: [
      for (final path in source.bytes.keys.where(
        (path) => !path.startsWith('/target/'),
      ))
        (await source.stat(path))!,
    ],
    targetDirectory: '/target',
    options: options,
  );

  test(
    'all rows survive restart beyond the old 50-item history limit',
    () async {
      final source = _MemoryBackend('a');
      final target = _MemoryBackend('b');
      for (var i = 0; i < 130; i++) {
        source.file('/file-$i', 'data-$i');
      }
      final storage = MemoryTransferJournalStorage();
      final journal = TransferJournal(storage);
      final prepared = await plan(source, target);
      await journal.create('batch', prepared);
      await JournaledTransferRunner(journal)
          .execute('batch', prepared, control: FileOperationControl());
      final restored = TransferJournal(storage);
      await restored.initialize();
      expect(restored.job('batch')!.entries, hasLength(130));
      expect(restored.job('batch')!.status, TransferJobStatus.completed);
      expect(
        restored
            .job('batch')!
            .entries
            .every((entry) => entry.outcome == FileOperationOutcome.copied),
        isTrue,
      );
      expect(storage.lines.join(), isNot(contains('never-persist-this')));
      final beforeCompaction = storage.lines.length;
      await restored.compact();
      expect(storage.lines.length, lessThan(beforeCompaction));
      final compacted = TransferJournal(storage);
      await compacted.initialize();
      expect(compacted.job('batch')!.entries, hasLength(130));
      expect(compacted.job('batch')!.status, TransferJobStatus.completed);
    },
  );

  test('selected destination sources remain protected after restart', () async {
    final source = _MemoryBackend('a')..file('/a', 'original');
    final target = _MemoryBackend('b');
    final prepared = await const FileOperationService().prepare(
      source: source,
      destination: target,
      files: [(await source.stat('/a'))!],
      targetDirectory: '/target',
      protectedDestinationPaths: ['/target/other-selected.txt'],
    );
    final storage = MemoryTransferJournalStorage();
    await TransferJournal(storage).create('job', prepared);
    final restored = TransferJournal(storage);
    await restored.initialize();
    final preview = await const TransferRecoveryService().prepare(
      restored.job('job')!,
      source: source,
      destination: target,
      control: FileOperationControl(),
    );
    expect(preview.plan.protectedDestinationPaths, [
      '/target/other-selected.txt',
    ]);
    expect(preview.excluding({}).protectedDestinationPaths, [
      '/target/other-selected.txt',
    ]);
    expect(
      () => preview.plan.assertDestinationUnprotected(
        '/target/other-selected.txt',
      ),
      throwsStateError,
    );
  });

  test(
    'failure to persist write intent prevents the filesystem mutation',
    () async {
      final source = _MemoryBackend('a')..file('/a', 'original');
      final target = _MemoryBackend('b');
      final journal = TransferJournal(_FailWritingIntent());
      final prepared = await plan(source, target);
      await journal.create('job', prepared);
      await JournaledTransferRunner(journal)
          .execute('job', prepared, control: FileOperationControl());
      expect(target.writes, 0);
      expect(source.bytes['/a'], utf8.encode('original'));
      expect(prepared.entries.single.failed, isTrue);
    },
  );

  test(
    'lost native move reply reconciles by contents even with path-based UUIDs',
    () async {
      final storage = _MemoryBackend('a')
        ..file('/a', 'unique original')
        ..loseMoveReply = true;
      final journal = TransferJournal(MemoryTransferJournalStorage());
      final prepared = await plan(
        storage,
        storage,
        options: const FileOperationOptions(kind: FileOperationKind.move),
      );
      await journal.create('job', prepared);
      await JournaledTransferRunner(journal)
          .execute('job', prepared, control: FileOperationControl());
      expect(prepared.entries.single.failed, isTrue);
      expect(storage.bytes.containsKey('/a'), isFalse);
      final preview = await const TransferRecoveryService().prepare(
        journal.job('job')!,
        source: storage,
        destination: storage,
        control: FileOperationControl(),
      );
      expect(preview.issues, isEmpty);
      expect(preview.plan.entries.single.outcome, FileOperationOutcome.moved);
    },
  );

  test('lost source-delete reply reconciles the verified copy without a second copy', () async {
    final source = _MemoryBackend('a')
      ..file('/a', 'contents')
      ..loseDeleteReply = true;
    final target = _MemoryBackend('b');
    final journal = TransferJournal(MemoryTransferJournalStorage());
    final prepared = await plan(
      source,
      target,
      options: const FileOperationOptions(kind: FileOperationKind.move),
    );
    await journal.create('job', prepared);
    await JournaledTransferRunner(journal)
        .execute('job', prepared, control: FileOperationControl());
    final preview = await const TransferRecoveryService().prepare(
      journal.job('job')!,
      source: source,
      destination: target,
      control: FileOperationControl(),
    );
    expect(preview.issues, isEmpty);
    expect(preview.plan.entries.single.outcome, FileOperationOutcome.moved);
    expect(target.writes, 1);
  });

  test('metadata failure retains both data copies and recovery finishes cleanup only', () async {
    final source = _MemoryBackend('a')..file('/a', 'contents');
    final target = _MemoryBackend('b')..metadataFails = true;
    final journal = TransferJournal(MemoryTransferJournalStorage());
    final prepared = await plan(
      source,
      target,
      options: const FileOperationOptions(
        kind: FileOperationKind.move,
        preserveModified: true,
      ),
    );
    await journal.create('job', prepared);
    await JournaledTransferRunner(journal)
        .execute('job', prepared, control: FileOperationControl());
    expect(
      prepared.entries.single.outcome,
      FileOperationOutcome.metadataFailed,
    );
    expect(source.bytes['/a'], target.bytes['/target/a']);
    final preview = await const TransferRecoveryService().prepare(
      journal.job('job')!,
      source: source,
      destination: target,
      control: FileOperationControl(),
    );
    expect(preview.issues, isEmpty);
    expect(preview.plan.entries.single.recovery!['resumeAfterCommit'], isTrue);
    target.metadataFails = false;
    await JournaledTransferRunner(journal)
        .execute('job', preview.plan, control: FileOperationControl());
    expect(target.writes, 1);
    expect(source.bytes.containsKey('/a'), isFalse);
    expect(journal.job('job')!.status, TransferJobStatus.completed);
  });

  test(
    'partial staged bytes resume only after source-prefix verification',
    () async {
      final source = _MemoryBackend('a')..file('/a', 'abcdefghij');
      final target = _MemoryBackend('b')..interruptAfter = 3;
      final journal = TransferJournal(MemoryTransferJournalStorage());
      final prepared = await plan(source, target);
      await journal.create('job', prepared);
      await JournaledTransferRunner(journal)
          .execute('job', prepared, control: FileOperationControl());
      final preview = await const TransferRecoveryService().prepare(
        journal.job('job')!,
        source: source,
        destination: target,
        control: FileOperationControl(),
      );
      expect(preview.issues, isEmpty);
      expect(preview.actions[0], contains('3 verified staged bytes'));
      target.interruptAfter = null;
      await JournaledTransferRunner(journal)
          .execute('job', preview.plan, control: FileOperationControl());
      expect(source.rangeOffsets, [3]);
      expect(target.bytes['/target/a'], utf8.encode('abcdefghij'));
      expect(journal.job('job')!.status, TransferJobStatus.completed);
    },
  );

  test(
    'same-size same-time external edits and wrong accounts cannot resume',
    () async {
      final source = _MemoryBackend('a')..file('/a', 'abcdefghij');
      final target = _MemoryBackend('b')..interruptAfter = 3;
      final journal = TransferJournal(MemoryTransferJournalStorage());
      final prepared = await plan(source, target);
      await journal.create('job', prepared);
      await JournaledTransferRunner(journal)
          .execute('job', prepared, control: FileOperationControl());
      source.bytes['/a'] = utf8.encode('abcDEFGHIJ');
      final preview = await const TransferRecoveryService().prepare(
        journal.job('job')!,
        source: source,
        destination: target,
        control: FileOperationControl(),
      );
      expect(preview.issues[0], contains('contents changed'));
      expect(preview.excluding({}).canExecute, isFalse);
      await expectLater(
        const TransferRecoveryService().prepare(
          journal.job('job')!,
          source: _MemoryBackend('other'),
          destination: target,
          control: FileOperationControl(),
        ),
        throwsStateError,
      );
    },
  );

  test('background conflicts persist waiting state instead of successful completion', () async {
    final source = _MemoryBackend('a')..file('/a', 'new');
    final target = _MemoryBackend('b')..file('/target/a', 'old');
    final journal = TransferJournal(MemoryTransferJournalStorage());
    final prepared = await plan(source, target);
    await journal.create('job', prepared);
    await JournaledTransferRunner(journal)
        .execute('job', prepared, control: FileOperationControl());
    expect(journal.job('job')!.status, TransferJobStatus.waitingForDecision);
    expect(target.bytes['/target/a'], utf8.encode('old'));
    final preview = await const TransferRecoveryService().prepare(
      journal.job('job')!,
      source: source,
      destination: target,
      control: FileOperationControl(),
    );
    await JournaledTransferRunner(journal).execute(
      'job',
      preview.plan,
      control: FileOperationControl(),
      resolveConflict: (_, _) async => FileConflictDecision.keepBoth,
    );
    expect(target.bytes['/target/a'], utf8.encode('old'));
    expect(journal.job('job')!.status, TransferJobStatus.completed);
  });

  test(
    'native log salvages only the incomplete tail and retains the old file',
    () async {
      final directory = await Directory.systemTemp.createTemp('crisp-journal-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'journal.jsonl'));
      final storage = NativeTransferJournalStorage(file: () async => file);
      final source = _MemoryBackend('a')..file('/a', 'contents');
      final target = _MemoryBackend('b');
      final journal = TransferJournal(storage);
      await journal.create('job', await plan(source, target));
      await journal.setStatus('job', TransferJobStatus.running);
      await file.writeAsString(
        '{"payload":',
        mode: FileMode.append,
        flush: true,
      );
      final restarted = TransferJournal(storage);
      await restarted.initialize();
      expect(restarted.warnings, hasLength(1));
      expect(restarted.job('job')!.status, TransferJobStatus.interrupted);
      expect(await File('${file.path}.previous').exists(), isTrue);
      await restarted.setStatus('job', TransferJobStatus.cancelled);
      final again = TransferJournal(storage);
      await again.initialize();
      expect(again.warnings, isEmpty);
      expect(again.job('job')!.status, TransferJobStatus.cancelled);
    },
  );

  test(
    'a corrupt middle checkpoint blocks recovery instead of skipping an intent',
    () async {
      final storage = MemoryTransferJournalStorage();
      final journal = TransferJournal(storage);
      final source = _MemoryBackend('a')..file('/a', 'contents');
      await journal.create('job', await plan(source, _MemoryBackend('b')));
      storage.lines.insert(1, '{corrupt');
      await expectLater(
        TransferJournal(storage).initialize(),
        throwsFormatException,
      );
      expect(storage.lines[1], '{corrupt');
    },
  );
}

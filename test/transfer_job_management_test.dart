import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/audit_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_resource_claims.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryBackend extends FileOperationBackend {
  _MemoryBackend(
    this.account, {
    p.Context? paths,
    this.caseSensitivity = StorageCaseSensitivity.sensitive,
  }) : paths = paths ?? p.posix;

  final String account;
  @override
  final p.Context paths;
  final StorageCaseSensitivity caseSensitivity;
  final bytes = <String, List<int>>{};
  final times = <String, DateTime>{};
  final directories = <String>{'/', '/target', '/other'};
  final unknownSizes = <String>{};
  final writeGates = <String, Completer<void>>{};
  final writeStarts = <String, Completer<void>>{};
  bool current = true;
  int writes = 0;
  int deletes = 0;
  int _revision = 0;

  @override
  StorageReference get storageReference =>
      StorageReference(kind: 'remote', provider: 'memory', accountKey: account);
  @override
  Object get identity => storageReference.id;
  @override
  String get persistentStorageId => storageReference.id;
  @override
  String get label => account;
  @override
  bool get canRecover => true;
  @override
  bool get isCurrent => current;
  @override
  bool get supportsStagedVerification => true;
  @override
  StorageTransferCapabilities get capabilities =>
      StorageTransferCapabilities(caseSensitivity: caseSensitivity);

  void file(String path, String text) {
    bytes[path] = utf8.encode(text);
    times[path] = DateTime.utc(2026).add(Duration(seconds: _revision++));
    var parent = paths.dirname(path);
    while (directories.add(parent)) {
      final next = paths.dirname(parent);
      if (next == parent) break;
      parent = next;
    }
  }

  Completer<void> blockWrite(String path) {
    writeStarts[path] = Completer<void>();
    return writeGates[path] = Completer<void>();
  }

  Future<void> writing(String path) =>
      writeStarts.putIfAbsent(path, Completer<void>.new).future;

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
    final content = bytes[path];
    return content == null
        ? null
        : FileItem(
            name: paths.basename(path),
            path: path,
            uuid: path,
            isFolder: false,
            isSymlink: false,
            size: unknownSizes.contains(path) ? null : content.length,
            updatedAt: times[path],
          );
  }

  @override
  Future<List<FileItem>> list(String path) async => [
    for (final candidate in {...directories, ...bytes.keys})
      if (candidate != path && paths.dirname(candidate) == path)
        (await stat(candidate))!,
  ];

  @override
  Future<void> createDirectory(String path) async => directories.add(path);

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    if (!current) throw StateError('Account disconnected');
    yield List<int>.of(bytes[file.path]!);
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
    final started = writeStarts.putIfAbsent(path, Completer<void>.new);
    if (!started.isCompleted) started.complete();
    await writeGates[path]?.future;
    final staged = paths.join(paths.dirname(path), '.stage-${_revision++}');
    await checkpoint?.call({'phase': 'staging', 'stagedPath': staged});
    bytes[staged] = [];
    times[staged] = DateTime.utc(2026).add(Duration(seconds: _revision++));
    await for (final chunk in data) {
      bytes[staged]!.addAll(chunk);
    }
    if (length != null && bytes[staged]!.length != length) {
      throw StateError('Length mismatch');
    }
    await verifyStaged?.call((await stat(staged))!);
    await checkpoint?.call({'phase': 'committing', 'stagedPath': staged});
    if (!replace && bytes.containsKey(path)) {
      throw StateError('Destination occupied');
    }
    bytes[path] = bytes.remove(staged)!;
    times[path] = times.remove(staged)!;
    await checkpoint?.call({'phase': 'committed', 'destination': path});
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    deletes++;
    bytes.remove(file.path);
    times.remove(file.path);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    if ((await list(path)).isNotEmpty) throw StateError('Directory not empty');
    directories.remove(path);
  }
}

class _BackupBackend extends _MemoryBackend {
  _BackupBackend(super.account);

  int backupReads = 0;
  int moves = 0;
  Completer<void>? backupReadStarted;
  Completer<void>? backupReadGate;

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    if (file.path == '/target/backup') {
      backupReads++;
      if (backupReadStarted case final started? when !started.isCompleted) {
        started.complete();
      }
      await backupReadGate?.future;
    }
    yield* super.readFile(file);
  }

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    if (await stat(destination) != null) {
      throw StateError('Destination occupied');
    }
    moves++;
    bytes[destination] = bytes.remove(file.path)!;
    times[destination] = times.remove(file.path)!;
    return true;
  }
}

class _JournalGate extends MemoryTransferJournalStorage {
  bool Function(Map<String, dynamic>)? _predicate;
  Completer<void>? entered;
  Completer<void>? release;

  void block(bool Function(Map<String, dynamic>) predicate) {
    _predicate = predicate;
    entered = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<void> append(String line) async {
    if (_predicate?.call(decodeTransferEvent(line)) == true) {
      _predicate = null;
      entered!.complete();
      await release!.future;
    }
    await super.append(line);
  }
}

/// Delay admission of a queue-settings write, leaving unrelated checkpoints
/// available. An active job can finish while the requested schedule is saving.
class _QueueUpdateGate extends TransferJournal {
  _QueueUpdateGate(super.storage);
  bool holdNextUpdate = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> updateQueue(
    String id, {
    int? priority,
    int? queueOrder,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
  }) async {
    if (holdNextUpdate) {
      holdNextUpdate = false;
      entered.complete();
      await release.future;
    }
    await super.updateQueue(
      id,
      priority: priority,
      queueOrder: queueOrder,
      scheduledAt: scheduledAt,
      clearScheduledAt: clearScheduledAt,
    );
  }
}

class _AuditGate extends AuditService {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> log(AuditEntry entry) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
}

Future<FileOperationPlan> _plan(
  _MemoryBackend source,
  _MemoryBackend destination, {
  List<String>? selected,
  String target = '/target',
  FileOperationOptions options = const FileOperationOptions(),
}) async => const FileOperationService().prepare(
  source: source,
  destination: destination,
  targetDirectory: target,
  files: [
    for (final path in selected ?? source.bytes.keys.toList())
      (await source.stat(path))!,
  ],
  options: options,
);

Future<TransferNotifier> _notifier(
  TransferJournal journal, {
  AuditService? audit,
}) async {
  final container = ProviderContainer(
    overrides: [
      transferJournalProvider.overrideWithValue(journal),
      if (audit != null) auditServiceProvider.overrideWithValue(audit),
    ],
  );
  addTearDown(container.dispose);
  final notifier = container.read(transferProvider);
  await notifier.ready;
  return notifier;
}

Future<void> _until(
  TransferNotifier notifier,
  bool Function() condition,
) async {
  if (condition()) return;
  final ready = Completer<void>();
  void changed() {
    if (condition() && !ready.isCompleted) ready.complete();
  }

  notifier.addListener(changed);
  try {
    await ready.future.timeout(const Duration(seconds: 5));
  } finally {
    notifier.removeListener(changed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'recovery admission and finalization each retain one exclusive owner',
    () async {
      final storage = _JournalGate();
      final journal = TransferJournal(storage);
      final source = _MemoryBackend('source')..file('/source/a', 'payload');
      final destination = _MemoryBackend('destination');
      final plan = await _plan(source, destination);
      await journal.create('recover_once', plan);
      await journal.setStatus('recover_once', TransferJobStatus.interrupted);
      final transfers = await _notifier(journal);
      await transfers.setConcurrency(0);
      storage.block((event) => event['kind'] == 'options');
      final owner = FileOperationControl();
      final run = transfers.runFileOperation(
        plan,
        recoveryJobId: 'recover_once',
        control: owner,
      );
      await storage.entered!.future;
      expect(transfers.isJobLive('recover_once'), isTrue);
      final other = FileOperationControl();
      await expectLater(
        transfers.runFileOperation(
          plan,
          recoveryJobId: 'recover_once',
          control: other,
        ),
        throwsStateError,
      );
      await expectLater(
        transfers.dismissSavedJob('recover_once'),
        throwsStateError,
      );
      expect(destination.writes, 0);
      storage.release!.complete();
      await _until(transfers, () => transfers.isQueued('recover_once'));
      transfers.pauseOperations(['recover_once']);
      expect(owner.isPaused, isTrue);
      expect(other.isPaused, isFalse);
      expect(transfers.operations, hasLength(1));

      storage.block(
        (event) =>
            event['kind'] == 'state' &&
            event['status'] == TransferJobStatus.cancelled.name,
      );
      transfers.cancelOperations(['recover_once']);
      await storage.entered!.future;
      expect(transfers.isJobLive('recover_once'), isTrue);
      expect(transfers.queueSummary.cancelling, 1);
      transfers.removeOperation('recover_once');
      expect(transfers.operations, hasLength(1));
      await expectLater(
        transfers.runFileOperation(
          plan,
          recoveryJobId: 'recover_once',
          control: FileOperationControl(),
        ),
        throwsStateError,
      );
      storage.release!.complete();
      await run;
      expect(transfers.isJobLive('recover_once'), isFalse);
      expect(transfers.queueSummary.cancelled, 1);
      expect(journal.job('recover_once')!.status, TransferJobStatus.cancelled);
      expect(destination.writes, 0);
      expect(source.bytes['/source/a'], utf8.encode('payload'));
    },
  );

  test(
    'queue pause persists separately and preserves individual pauses',
    () async {
      final storage = MemoryTransferJournalStorage();
      final transfers = await _notifier(TransferJournal(storage));
      await transfers.setConcurrency(2);
      await transfers.setQueuePaused(true);
      final source = _MemoryBackend('source')
        ..file('/a', 'first')
        ..file('/b', 'second');
      final destination = _MemoryBackend('destination');
      final firstControl = FileOperationControl();
      final first = transfers.runFileOperation(
        await _plan(source, destination, selected: ['/a']),
        control: firstControl,
      );
      await _until(transfers, () => transfers.queuedCount == 1);
      final firstId = transfers.queuedIds.single;
      final second = transfers.runFileOperation(
        await _plan(source, destination, selected: ['/b'], target: '/other'),
        control: FileOperationControl(),
      );
      await _until(transfers, () => transfers.queuedCount == 2);
      expect(transfers.maxConcurrent, 2);
      expect(destination.writes, 0);
      expect(transfers.queueSummary.queued, 2);
      transfers.pauseOperations([firstId]);
      await transfers.setQueuePaused(false);
      await second;
      expect(firstControl.isPaused, isTrue);
      expect(transfers.queueSummary.paused, 1);
      expect(transfers.queueSummary.completed, 1);
      expect(transfers.queueSummary.totalBytes, 5);
      expect(destination.bytes.containsKey('/target/a'), isFalse);
      transfers.resumeOperations([firstId]);
      await first;
      await transfers.setQueuePaused(true);
      final restarted = await _notifier(TransferJournal(storage));
      expect(restarted.queuePaused, isTrue);
      expect(restarted.maxConcurrent, 2);
      expect(restarted.queuedCount, 0);
      expect(destination.writes, 2);
    },
  );

  test(
    'clearing completed history retains a job until finalization settles',
    () async {
      final journal = TransferJournal(MemoryTransferJournalStorage());
      final audit = _AuditGate();
      final transfers = await _notifier(journal, audit: audit);
      final source = _MemoryBackend('source')..file('/a', 'complete payload');
      final destination = _MemoryBackend('destination');
      final run = transfers.runFileOperation(
        await _plan(source, destination),
        control: FileOperationControl(),
      );
      await audit.entered.future;
      final id = transfers.operations.single.id;
      expect(journal.job(id)!.status, TransferJobStatus.completed);
      expect(transfers.isJobLive(id), isTrue);
      await transfers.clearSavedCompleted();
      transfers.clearFinishedOperations();
      transfers.removeOperation(id);
      expect(transfers.operations, hasLength(1));
      expect(transfers.savedJobs, hasLength(1));
      audit.release.complete();
      await run;
      expect(transfers.isJobLive(id), isFalse);
      await transfers.clearSavedCompleted();
      expect(transfers.operations, isEmpty);
      expect(transfers.savedJobs, isEmpty);
      expect(destination.bytes['/target/a'], utf8.encode('complete payload'));
    },
  );

  test('backup restoration rejects active workers and holds queued dispatch through verification', () async {
    final journal = TransferJournal(MemoryTransferJournalStorage());
    final source = _MemoryBackend('source')
      ..file('/a', 'new')
      ..file('/b', 'active')
      ..file('/c', 'queued');
    final destination = _BackupBackend('destination')
      ..file('/target/backup', 'previous');
    final recoveryPlan = await _plan(source, destination, selected: ['/a']);
    recoveryPlan.entries.single
      ..outcome = FileOperationOutcome.failed
      ..recovery = {
        'backupPath': '/target/backup',
        'backupSha256': sha256.convert(utf8.encode('previous')).toString(),
      };
    await journal.create('restore', recoveryPlan);
    await journal.setStatus('restore', TransferJobStatus.failed);
    final transfers = await _notifier(journal);
    final writerGate = destination.blockWrite('/other/b');
    final active = transfers.runFileOperation(
      await _plan(source, destination, selected: ['/b'], target: '/other'),
      control: FileOperationControl(),
    );
    await destination.writing('/other/b');
    await expectLater(
      transfers.restoreSavedBackup(
        'restore',
        0,
        destination,
        FileOperationControl(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Wait for running transfers to finish before restoring a backup.',
        ),
      ),
    );
    expect(destination.backupReads, 0);
    expect(destination.moves, 0);
    expect(destination.bytes['/target/backup'], utf8.encode('previous'));
    writerGate.complete();
    await active;

    destination
      ..backupReadStarted = Completer<void>()
      ..backupReadGate = Completer<void>();
    final restore = transfers.restoreSavedBackup(
      'restore',
      0,
      destination,
      FileOperationControl(),
    );
    await destination.backupReadStarted!.future;
    expect(transfers.isJobLive('restore'), isTrue);
    final queued = transfers.runFileOperation(
      await _plan(source, destination, selected: ['/c']),
      control: FileOperationControl(),
    );
    await _until(transfers, () => transfers.queuedCount == 1);
    expect(
      transfers.queueBlockedReason(transfers.queuedIds.single),
      'Saving queue changes',
    );
    expect(destination.writes, 1);
    expect(destination.moves, 0);
    destination.backupReadGate!.complete();
    await Future.wait([restore, queued]);
    expect(destination.moves, 1);
    expect(destination.bytes.containsKey('/target/backup'), isFalse);
    expect(destination.bytes['/target/a'], utf8.encode('previous'));
    expect(destination.bytes['/target/c'], utf8.encode('queued'));
    expect(journal.job('restore')!.entries.single.phase, 'backupRestored');
    expect(transfers.isJobLive('restore'), isFalse);
    expect(transfers.queuePaused, isFalse);
  });

  test('schedule changes hold dispatch until durable and respect concurrent queue pause', () async {
    final journal = _QueueUpdateGate(MemoryTransferJournalStorage());
    final transfers = await _notifier(journal);
    await transfers.setConcurrency(1);
    final source = _MemoryBackend('source')
      ..file('/a', 'first')
      ..file('/b', 'second');
    final destination = _MemoryBackend('destination');
    final gate = destination.blockWrite('/target/a');
    final first = transfers.runFileOperation(
      await _plan(source, destination, selected: ['/a']),
      control: FileOperationControl(),
    );
    await destination.writing('/target/a');
    await expectLater(
      transfers.setScheduledStart(
        transfers.operations.single.id,
        DateTime.now().add(const Duration(hours: 1)),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('already started or finished'),
        ),
      ),
    );
    final second = transfers.runFileOperation(
      await _plan(source, destination, selected: ['/b'], target: '/other'),
      control: FileOperationControl(),
    );
    await _until(transfers, () => transfers.queuedCount == 1);
    final id = transfers.queuedIds.single;
    final scheduledAt = DateTime.now().toUtc().add(const Duration(hours: 1));
    journal.holdNextUpdate = true;
    final reschedule = transfers.setScheduledStart(id, scheduledAt);
    await journal.entered.future;
    final pause = transfers.setQueuePaused(true);
    gate.complete();
    await first;
    expect(destination.writes, 1);
    expect(transfers.queueBlockedReason(id), 'Saving queue changes');
    journal.release.complete();
    await Future.wait([reschedule, pause]);
    expect(transfers.queuePaused, isTrue);
    expect(journal.job(id)!.scheduledAt, scheduledAt);
    expect(transfers.queueSummary.scheduled, 1);
    await transfers.setScheduledStart(id, null);
    expect(journal.job(id)!.scheduledAt, isNull);
    expect(transfers.queueSummary.queued, 1);
    expect(destination.writes, 1);
    await transfers.setQueuePaused(false);
    await second;
    expect(destination.bytes['/other/b'], utf8.encode('second'));
  });

  test(
    'moving a shared source waits for its reader while disjoint jobs run',
    () async {
      final transfers = await _notifier(
        TransferJournal(MemoryTransferJournalStorage()),
      );
      await transfers.setConcurrency(3);
      final source = _MemoryBackend('source')
        ..file('/a', 'shared')
        ..file('/unrelated', 'independent');
      final firstTarget = _MemoryBackend('copy-target');
      final moveTarget = _MemoryBackend('move-target');
      final otherTarget = _MemoryBackend('other-target');
      final gate = firstTarget.blockWrite('/target/a');
      final first = transfers.runFileOperation(
        await _plan(source, firstTarget, selected: ['/a']),
        control: FileOperationControl(),
      );
      await firstTarget.writing('/target/a');
      final move = transfers.runFileOperation(
        await _plan(
          source,
          moveTarget,
          selected: ['/a'],
          options: const FileOperationOptions(kind: FileOperationKind.move),
        ),
        control: FileOperationControl(),
      );
      await _until(transfers, () => transfers.queuedCount == 1);
      expect(
        transfers.queueBlockedReason(transfers.queuedIds.single),
        'Path busy',
      );
      await transfers.runFileOperation(
        await _plan(source, otherTarget, selected: ['/unrelated']),
        control: FileOperationControl(),
      );
      expect(
        otherTarget.bytes['/target/unrelated'],
        utf8.encode('independent'),
      );
      expect(moveTarget.writes, 0);
      expect(source.deletes, 0);
      gate.complete();
      await Future.wait([first, move]);
      expect(firstTarget.bytes['/target/a'], utf8.encode('shared'));
      expect(moveTarget.bytes['/target/a'], utf8.encode('shared'));
      expect(source.bytes.containsKey('/a'), isFalse);
      expect(source.deletes, 1);
    },
  );

  test('destination directory reservations cover dynamic siblings without blocking other directories', () async {
    final transfers = await _notifier(
      TransferJournal(MemoryTransferJournalStorage()),
    );
    await transfers.setConcurrency(3);
    final source = _MemoryBackend('source')
      ..file('/a', 'first')
      ..file('/b', 'second')
      ..file('/c', 'third');
    final target = _MemoryBackend('target');
    final gate = target.blockWrite('/target/a');
    final first = transfers.runFileOperation(
      await _plan(source, target, selected: ['/a']),
      control: FileOperationControl(),
    );
    await target.writing('/target/a');
    final second = transfers.runFileOperation(
      await _plan(source, target, selected: ['/b']),
      control: FileOperationControl(),
    );
    await _until(transfers, () => transfers.queuedCount == 1);
    expect(
      transfers.queueBlockedReason(transfers.queuedIds.single),
      'Path busy',
    );
    await transfers.runFileOperation(
      await _plan(source, target, selected: ['/c'], target: '/other'),
      control: FileOperationControl(),
    );
    expect(target.bytes['/other/c'], utf8.encode('third'));
    expect(target.bytes.containsKey('/target/b'), isFalse);
    gate.complete();
    await Future.wait([first, second]);
    expect(target.bytes['/target/b'], utf8.encode('second'));
  });

  test('queue summary excludes history and separates waiting, review, pause and schedule', () async {
    final transfers = await _notifier(
      TransferJournal(MemoryTransferJournalStorage()),
    );
    final source = _MemoryBackend('source')
      ..file('/done', 'completed history')
      ..file('/conflict', 'new')
      ..file('/failed', 'changed source')
      ..file('/queued', '12345')
      ..file('/scheduled', '1234567')
      ..file('/paused', '123456789')
      ..file('/unknown', 'unknown bytes');
    final target = _MemoryBackend('target')..file('/target/conflict', 'old');
    await transfers.runFileOperation(
      await _plan(source, target, selected: ['/done']),
      control: FileOperationControl(),
    );
    await transfers.runFileOperation(
      await _plan(source, target, selected: ['/conflict']),
      control: FileOperationControl(),
    );
    final invalid = await _plan(source, target, selected: ['/failed']);
    source.file('/failed', 'modified after review');
    await transfers.runFileOperation(invalid, control: FileOperationControl());
    await transfers.setQueuePaused(true);
    final pending = <Future<void>>[];
    for (final name in ['queued', 'scheduled', 'paused', 'unknown']) {
      if (name == 'unknown') source.unknownSizes.add('/unknown');
      final admitted = Completer<void>();
      pending.add(
        transfers.runFileOperation(
          await _plan(source, target, selected: ['/$name']),
          control: FileOperationControl(),
          notBefore: name == 'scheduled'
              ? DateTime.now().add(const Duration(hours: 1))
              : null,
          onQueued: admitted.complete,
        ),
      );
      await admitted.future;
      if (name == 'paused') {
        transfers.pauseOperations([transfers.queuedIds.last]);
      }
    }
    final summary = transfers.queueSummary;
    expect(summary.totalJobs, 7);
    expect(summary.completed, 1);
    expect(summary.waiting, 1);
    expect(summary.needsReview, 1);
    expect(summary.queued, 2);
    expect(summary.scheduled, 1);
    expect(summary.paused, 1);
    expect(summary.running, 0);
    expect(summary.totalBytes, 21);
    expect(summary.transferredBytes, 0);
    expect(summary.bytesPerSecond, 0);
    expect(summary.hasUnknownSize, isTrue);
    expect(summary.progress, isNull);
    transfers.clearFinishedOperations();
    expect(transfers.queueSummary.completed, 0);
    expect(transfers.queueSummary.waiting, 1);
    expect(transfers.queueSummary.needsReview, 1);
    expect(transfers.savedJobs, hasLength(7));
    transfers.cancelOperations(transfers.queuedIds);
    await Future.wait(pending);
    expect(transfers.queueSummary.cancelled, 4);
    expect(transfers.queueSummary.totalBytes, 0);
    expect(transfers.queueSummary.hasLiveJobs, isFalse);
  });

  test('scheduled saved jobs require review after restart and keep their timestamp', () async {
    final storage = MemoryTransferJournalStorage();
    final journal = TransferJournal(storage);
    final source = _MemoryBackend('source')..file('/a', 'saved');
    final target = _MemoryBackend('target');
    final when = DateTime.now().toUtc().add(const Duration(hours: 1));
    await journal.create(
      'scheduled_restart',
      await _plan(source, target),
      priority: 10,
      scheduledAt: when,
    );
    final restarted = await _notifier(TransferJournal(storage));
    expect(restarted.savedJob('scheduled_restart')!.scheduledAt, when);
    expect(restarted.savedJob('scheduled_restart')!.priority, 10);
    expect(
      restarted.savedJob('scheduled_restart')!.status,
      TransferJobStatus.interrupted,
    );
    expect(restarted.queueSummary.needsReview, 1);
    expect(restarted.queueSummary.scheduled, 0);
    expect(restarted.queuedCount, 0);
    expect(target.writes, 0);
  });

  test(
    'claim paths respect account, case, separators and segment boundaries',
    () async {
      FileOperationPlan manual(
        _MemoryBackend source,
        String sourcePath,
        _MemoryBackend destination,
        String target, {
        FileOperationKind kind = FileOperationKind.copy,
        bool folder = false,
      }) => FileOperationPlan(
        source: source,
        destination: destination,
        targetDirectory: target,
        options: FileOperationOptions(kind: kind),
        entries: [
          FileOperationEntry(
            FileItem(
              name: source.paths.basename(sourcePath),
              path: sourcePath,
              isFolder: folder,
            ),
            destination.paths.join(target, 'copy'),
          ),
        ],
        errors: [],
      );
      bool conflicts(FileOperationPlan left, FileOperationPlan right) =>
          transferResourceClaims(left)
              .any((a) => transferResourceClaims(right).any(a.conflictsWith));
      final source = _MemoryBackend('source');
      final otherSource = _MemoryBackend('other-source');
      final a = _MemoryBackend('destination-a');
      final b = _MemoryBackend('destination-b');
      final copy = manual(source, '/photos', a, '/target', folder: true);
      expect(
        conflicts(copy, manual(source, '/photos/a', b, '/target')),
        isFalse,
      );
      expect(
        conflicts(
          copy,
          manual(
            source,
            '/photos/a',
            b,
            '/target',
            kind: FileOperationKind.move,
          ),
        ),
        isTrue,
      );
      expect(
        conflicts(
          copy,
          manual(
            source,
            '/photos-old/a',
            b,
            '/target',
            kind: FileOperationKind.move,
          ),
        ),
        isFalse,
      );
      expect(
        conflicts(
          copy,
          manual(
            otherSource,
            '/photos/a',
            b,
            '/target',
            kind: FileOperationKind.move,
          ),
        ),
        isFalse,
      );
      expect(
        conflicts(
          manual(source, r'/photos\a', a, '/target'),
          manual(
            source,
            '/photos/a',
            b,
            '/target',
            kind: FileOperationKind.move,
          ),
        ),
        isFalse,
      );
      final windows = _MemoryBackend(
        'windows',
        paths: p.windows,
        caseSensitivity: StorageCaseSensitivity.insensitive,
      );
      expect(
        conflicts(
          manual(windows, r'C:\Photos', a, '/target', folder: true),
          manual(
            windows,
            r'c:\photos\a',
            b,
            '/target',
            kind: FileOperationKind.move,
          ),
        ),
        isTrue,
      );
      expect(transferProviderNames(copy), {
        source.persistentStorageId,
        a.persistentStorageId,
      });
    },
  );

  test(
    'claims retain source-directory cleanup and collapse a large subtree',
    () {
      final source = _MemoryBackend('source');
      final target = _MemoryBackend('target');
      final plan = FileOperationPlan(
        source: source,
        destination: target,
        targetDirectory: '/target',
        options: const FileOperationOptions(kind: FileOperationKind.move),
        entries: [
          FileOperationEntry(
            FileItem(name: 'folder', path: '/source/folder', isFolder: true),
            '/target/folder',
          )..outcome = FileOperationOutcome.directoryCreated,
          for (var i = 0; i < 2000; i++)
            FileOperationEntry(
              FileItem(name: '$i', path: '/source/folder/$i', isFolder: false),
              '/target/folder/$i',
            ),
        ],
        errors: [],
      );
      final claims = transferResourceClaims(plan);
      expect(claims, hasLength(2));
      final sourceClaim = claims.singleWhere(
        (claim) => claim.namespace == source.persistentStorageId,
      );
      expect(sourceClaim.write, isTrue);
      expect(sourceClaim.pathSegments, ['/', 'source', 'folder']);
    },
  );
}

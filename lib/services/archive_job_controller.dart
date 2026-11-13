import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/archive_job.dart';
import '../models/file_item.dart';
import '../utils/async_lock.dart';
import 'archive_creation_service.dart';
import 'archive_creation_batch.dart';
import 'archive_creation_worker.dart';
import 'archive_job_journal.dart';
import 'archive_publication_lease.dart';
import 'archive_publication_lease_io.dart'
    if (dart.library.js_interop) 'archive_publication_lease_web.dart'
    as leases;
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';

typedef ArchiveJobWorkerFactory = Future<ArchiveCreationWorker> Function({
  required LocalFileService local,
  required List<FileItem> files,
  required String destinationDirectory,
  required ArchiveCreationOptions options,
  required void Function(ArchiveCreationProgress) onProgress,
  required Future<void> Function(ArchiveCreationPrepared) onPrepared,
});

/// One leased queue owns its durable intents and native workers. It outlives
/// dialogs and pane navigation. Startup never resumes an interrupted write;
/// restarting is an explicit source rebuild and publication never overwrites.
class ArchiveJobController extends ChangeNotifier {
  ArchiveJobController({
    required this.local,
    ArchiveJobJournal? journal,
    FileOperationBackend? backend,
    ArchiveJobWorkerFactory? workerFactory,
    Future<ArchivePublicationLease?> Function(String)? acquireLease,
  }) : journal = journal ?? ArchiveJobJournal(),
       _workerFactory = workerFactory ?? startArchiveCreationWorker,
       _acquireLease = acquireLease ?? leases.acquireArchivePublicationLease {
    _backend =
        backend ?? LocalOperationBackend(local, isCurrent: () => !_closed);
  }

  final LocalFileService local;
  final ArchiveJobJournal journal;
  final ArchiveJobWorkerFactory _workerFactory;
  final Future<ArchivePublicationLease?> Function(String) _acquireLease;
  late final FileOperationBackend _backend;
  final _mutations = AsyncLock();
  final Map<String, String> _passwords = {};
  final Map<String, ArchiveCreationProgress> _progress = {};
  final Set<String> _cancelRequests = {};
  final Set<String> _pauseRequests = {};
  final Map<String, Completer<void>> _pauseWaiters = {};
  ArchivePublicationLease? _lease;
  ArchiveCreationWorker? _worker;
  String? _activeId;
  Future<void>? _initializing;
  Future<void>? _driving;
  Future<void>? _closing;
  Timer? _notification;
  bool _closed = false, _disposed = false, _initialized = false;
  Object? _error;

  List<ArchiveJobRecord> get jobs => journal.records;
  ArchiveCreationProgress? progress(String id) => _progress[id];
  String? get activeId => _activeId;
  bool get isReady => _lease?.isHeld == true && !_closed && _error == null;
  bool get queuePaused => journal.paused;
  Object? get error => _error;
  bool get initialized => _initialized;
  bool get ownedElsewhere => _initialized && _lease == null && _error == null;
  ArchiveJobRecord? job(String id) {
    for (final record in jobs) {
      if (record.id == id) return record;
    }
    return null;
  }

  void _notify({bool throttle = false}) {
    if (_disposed) return;
    if (throttle) {
      _notification ??= Timer(const Duration(milliseconds: 100), () {
        _notification = null;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      _lease = await _acquireLease('archive-creation-queue-v1');
      await journal.load();
      if (_lease != null) {
        final records = [
          for (final record in jobs)
            if (!record.terminal)
              record.change(
                ArchiveJobStatus.interrupted,
                error: 'Interrupted. Review the saved source selection before restarting.',
              )
            else
              record,
        ];
        if (records.any(
          (record) => record.status == ArchiveJobStatus.interrupted,
        )) {
          await journal.replace(records);
        }
      }
    } catch (error) {
      _error = error;
      _lease?.close();
      _lease = null;
      rethrow;
    } finally {
      _initialized = true;
      _notify();
    }
  }

  void _authority() {
    if (!isReady || !_backend.isCurrent) {
      throw StateError(
        'The archive queue is unavailable or owned by another window.',
      );
    }
  }

  String _storage() {
    final reference = _backend.storageReference;
    if (reference == null ||
        !reference.isLocal ||
        !reference.persistent ||
        reference.provider == 'browser' ||
        !_backend.canRecover) {
      throw StateError(
        'Background archive jobs require persistent native local storage.',
      );
    }
    return reference.id;
  }

  Future<void> _edit(
    FutureOr<List<ArchiveJobRecord>> Function(List<ArchiveJobRecord>) edit, {
    bool? paused,
  }) => _mutations.synchronized(() async {
    _authority();
    final records = await edit(jobs);
    try {
      await journal.replace(records, paused: paused);
    } catch (error) {
      _error = error;
      _worker?.cancel();
      rethrow;
    } finally {
      _notify();
    }
  });

  Future<void> _change(
    String id,
    ArchiveJobRecord Function(ArchiveJobRecord) change,
  ) => _edit(
    (records) => [
      for (final record in records)
        if (record.id == id) change(record) else record,
    ],
  );

  Future<ArchiveJobRecord> enqueue({
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveCreationOptions options,
  }) async => (await enqueueBatch([
    ArchiveCreationBatchItem(
      files: files,
      destinationDirectory: destinationDirectory,
      options: options,
    ),
  ])).single;

  /// Admit every reviewed output in one durable update. A collision or invalid
  /// item never leaves only a prefix of the batch queued.
  Future<List<ArchiveJobRecord>> enqueueBatch(
    List<ArchiveCreationBatchItem> items,
  ) async {
    items = List.unmodifiable(items);
    await initialize();
    _authority();
    if (items.isEmpty || items.length > ArchiveJobJournal.maximumJobs) {
      throw StateError(
        'Choose between 1 and ${ArchiveJobJournal.maximumJobs} archive jobs.',
      );
    }
    final storage = _storage();
    final incoming = <ArchiveJobRecord>[];
    for (final item in items) {
      item.options.validate();
      final request = ArchiveJobRequest(
        id: const Uuid().v4(),
        storageId: storage,
        created: DateTime.now().toUtc(),
        destinationDirectory: item.destinationDirectory,
        name: item.options.name,
        format: item.options.format,
        compression: item.options.compression,
        files: item.files,
        passwordRequired: item.options.password != null,
        encryptNames: item.options.encryptNames,
      );
      if (incoming.any(
        (record) =>
            _backend.samePath(record.request.outputPath, request.outputPath),
      )) {
        throw StateError('Two archive jobs have the same destination.');
      }
      incoming.add(
        ArchiveJobRecord(
          request: request,
          status: ArchiveJobStatus.queued,
          updated: request.created,
        ),
      );
    }
    for (var index = 0; index < incoming.length; index++) {
      final password = items[index].options.password;
      if (password != null) _passwords[incoming[index].id] = password;
    }
    try {
      await _edit((records) async {
        if (records.length + incoming.length > ArchiveJobJournal.maximumJobs) {
          throw StateError(
            'Archive job history is full. Remove finished jobs before adding this batch.',
          );
        }
        for (final record in incoming) {
          if (records.any(
            (old) =>
                !old.terminal &&
                _backend.samePath(
                  old.request.outputPath,
                  record.request.outputPath,
                ),
          )) {
            throw StateError(
              'Another archive job already owns this destination.',
            );
          }
          if (await _backend.stat(record.request.outputPath) != null) {
            throw const ArchiveCreationException(
              ArchiveCreationError.destinationExists,
            );
          }
          _authority();
        }
        return [...records, ...incoming];
      });
    } catch (_) {
      for (final record in incoming) {
        _passwords.remove(record.id);
      }
      rethrow;
    }
    _schedule();
    return List.unmodifiable(incoming);
  }

  Future<void> setQueuePaused(bool paused) async {
    await initialize();
    await _edit((records) => records, paused: paused);
    if (!paused) _schedule();
  }

  Future<void> moveToTop(String id) async {
    await initialize();
    await _edit((records) {
      final selected = records.where((record) => record.id == id).single;
      if (selected.status != ArchiveJobStatus.queued) {
        throw StateError('Only queued jobs can be reordered.');
      }
      return [selected, ...records.where((record) => record.id != id)];
    });
  }

  Future<void> pause(String id) async {
    await initialize();
    _authority();
    final record = job(id);
    if (record == null ||
        !const {
          ArchiveJobStatus.queued,
          ArchiveJobStatus.running,
        }.contains(record.status)) {
      return;
    }
    _pauseRequests.add(id);
    _pauseWaiters.putIfAbsent(id, Completer<void>.new);
    if (_activeId == id) _worker?.pause();
    await _change(
      id,
      (old) =>
          const {
            ArchiveJobStatus.queued,
            ArchiveJobStatus.running,
          }.contains(old.status)
          ? old.change(ArchiveJobStatus.paused)
          : old,
    );
  }

  Future<void> resume(String id) async {
    await initialize();
    _authority();
    final record = job(id);
    if (record?.status != ArchiveJobStatus.paused) return;
    await _change(
      id,
      (old) => old.status == ArchiveJobStatus.paused
          ? old.change(
              _activeId == id
                  ? ArchiveJobStatus.running
                  : ArchiveJobStatus.queued,
            )
          : old,
    );
    _pauseRequests.remove(id);
    final waiter = _pauseWaiters.remove(id);
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    if (_activeId == id) _worker?.resume();
    _schedule();
  }

  Future<void> cancel(String id) async {
    await initialize();
    _authority();
    final record = job(id);
    if (record == null || record.terminal) return;
    _cancelRequests.add(id);
    _pauseRequests.remove(id);
    final waiter = _pauseWaiters.remove(id);
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    if (_activeId == id) _worker?.cancel();
    await _change(
      id,
      (old) => old.terminal
          ? old
          : old.change(
              _activeId == id
                  ? ArchiveJobStatus.stopping
                  : ArchiveJobStatus.cancelled,
            ),
    );
    if (_activeId != id) _passwords.remove(id);
  }

  /// Rebuilds the selected sources. A possibly installed candidate must be
  /// reconciled first; restart never replaces or silently adopts an existing file.
  Future<void> restart(String id, {String? password}) async {
    await initialize();
    _authority();
    final record = job(id);
    if (record == null ||
        _activeId == id ||
        record.status == ArchiveJobStatus.completed) {
      throw StateError('This archive job cannot be restarted.');
    }
    if (record.request.storageId != _storage()) {
      throw StateError(
        'Reconnect the original local storage before restarting.',
      );
    }
    record.request.options(password: password).validate();
    if (await _backend.stat(record.request.outputPath) != null) {
      throw StateError(
        'The output path already exists. Verify the saved output or choose a different name for a new job.',
      );
    }
    if (password != null) _passwords[id] = password;
    try {
      await _change(id, (old) {
        if (old != record) {
          throw StateError('The archive job changed. Review it again.');
        }
        return old.change(ArchiveJobStatus.queued, clearPrepared: true);
      });
    } catch (_) {
      _passwords.remove(id);
      rethrow;
    }
    _cancelRequests.remove(id);
    _pauseRequests.remove(id);
    _progress.remove(id);
    _schedule();
  }

  Future<void> verifyPublishedOutput(String id) async {
    await initialize();
    _authority();
    final record = job(id);
    final expected = record?.prepared;
    if (record == null ||
        expected == null ||
        _activeId == id ||
        record.request.storageId != _storage()) {
      throw StateError('No recoverable publication receipt is available.');
    }
    final file = await _backend.stat(expected.path);
    if (file == null ||
        file.isFolder ||
        file.isSymlink == true ||
        file.size != expected.bytes) {
      throw StateError(
        'The saved output is missing or does not match its verified size.',
      );
    }
    var length = 0;
    Stream<List<int>> bounded() async* {
      await for (final part
          in _backend.readFile(file).timeout(const Duration(seconds: 30))) {
        _authority();
        length += part.length;
        if (length > expected.bytes) {
          throw StateError('The output grew during verification.');
        }
        yield part;
      }
    }

    final actual = (await sha256.bind(bounded()).single).toString();
    final after = await _backend.stat(expected.path);
    if (length != expected.bytes ||
        actual != expected.sha256 ||
        after == null ||
        after.isFolder ||
        after.isSymlink == true ||
        after.size != file.size ||
        after.uuid != file.uuid ||
        after.updatedAt != file.updatedAt) {
      throw StateError(
        'The saved output does not match its verified contents.',
      );
    }
    await _change(id, (old) {
      if (old != record) {
        throw StateError('The archive job changed during verification.');
      }
      return old.change(ArchiveJobStatus.completed);
    });
  }

  Future<void> remove(String id) async {
    await initialize();
    await _edit((records) {
      if (records.any(
        (record) => record.id == id && (!record.terminal || _activeId == id),
      )) {
        throw StateError(
          'Stop or finish this job before removing its history.',
        );
      }
      return records.where((record) => record.id != id).toList();
    });
    _passwords.remove(id);
    _progress.remove(id);
  }

  void _schedule() {
    if (_driving != null || !isReady || queuePaused) return;
    _driving =
        Future<void>(() async {
              while (isReady && !queuePaused) {
                final queued = jobs.where(
                  (record) => record.status == ArchiveJobStatus.queued,
                );
                if (queued.isEmpty) break;
                await _run(queued.first);
              }
            })
            .catchError((Object error) {
              _error = error;
              _notify();
            })
            .whenComplete(() {
              _driving = null;
              if (isReady &&
                  !queuePaused &&
                  jobs.any((job) => job.status == ArchiveJobStatus.queued)) {
                _schedule();
              }
            });
  }

  Future<void> _run(ArchiveJobRecord original) async {
    final id = original.id;
    // Queue controls and admission share one mutation lock. A pause/cancel may
    // have begun while the scheduler still saw the previous queued snapshot.
    // Never overwrite that control with a later unconditional running state.
    final admitted = await _mutations.synchronized(() async {
      _authority();
      final current = job(id);
      if (queuePaused ||
          current?.status != ArchiveJobStatus.queued ||
          _pauseRequests.contains(id) ||
          _cancelRequests.contains(id)) {
        return false;
      }
      final running = current!.change(
        ArchiveJobStatus.running,
        attempt: current.attempt + 1,
        clearPrepared: true,
      );
      try {
        await journal.replace([
          for (final record in jobs) record.id == id ? running : record,
        ]);
        _activeId = id;
      } catch (error) {
        _error = error;
        rethrow;
      } finally {
        _notify();
      }
      return true;
    });
    // An unstarted protected job retains its in-memory password on pause.
    if (!admitted) return;
    try {
      _authority();
      if (original.request.storageId != _storage()) {
        throw StateError('The original local storage is unavailable.');
      }
      final options = original.request.options(password: _passwords[id]);
      final worker = await _workerFactory(
        local: local,
        files: original.request.files,
        destinationDirectory: original.request.destinationDirectory,
        options: options,
        onProgress: (progress) {
          if (_activeId != id || _closed) return;
          _progress[id] = progress;
          _notify(throttle: true);
        },
        onPrepared: (prepared) async {
          _authority();
          if (_pauseRequests.contains(id)) await _pauseWaiters[id]?.future;
          if (_closed || _cancelRequests.contains(id)) {
            throw const FileOperationCancelled();
          }
          if (prepared.path != original.request.outputPath) {
            throw StateError('The prepared archive changed destination.');
          }
          await _change(
            id,
            (old) => old.change(old.status, prepared: prepared),
          );
          _authority();
          if (_closed || _cancelRequests.contains(id)) {
            throw const FileOperationCancelled();
          }
        },
      );
      _worker = worker;
      if (_cancelRequests.contains(id) || _closed) {
        worker.cancel();
      } else if (_pauseRequests.contains(id)) {
        worker.pause();
      }
      final result = await worker.result;
      final prepared = job(id)?.prepared;
      if (prepared == null ||
          result.path != prepared.path ||
          result.bytes != prepared.bytes ||
          result.entryCount != prepared.entryCount) {
        throw StateError(
          'The archive worker returned no acknowledged publication receipt.',
        );
      }
      // A late cancellation cannot turn an acknowledged completed publication
      // into a claimed rollback. A lost completion remains recoverable by hash.
      if (!_closed && _error == null) {
        await _change(id, (old) => old.change(ArchiveJobStatus.completed));
      }
    } catch (error) {
      if (!_closed && _error == null) {
        await _change(
          id,
          (old) => old.change(
            _cancelRequests.contains(id)
                ? ArchiveJobStatus.cancelled
                : ArchiveJobStatus.failed,
            error: '$error',
          ),
        );
      }
    } finally {
      final worker = _worker;
      if (worker != null) await worker.close();
      _worker = null;
      _activeId = null;
      _passwords.remove(id);
      _pauseRequests.remove(id);
      final waiter = _pauseWaiters.remove(id);
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      _notify();
    }
  }

  Future<void> get idle async {
    while (_driving != null) {
      await _driving;
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _worker?.cancel();
    for (final waiter in _pauseWaiters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    try {
      try {
        await _initializing;
      } catch (_) {
        /* Initialization recorded its error. */
      }
      await _driving;
    } finally {
      _passwords.clear();
      _lease?.close();
      _lease = null;
      _notification?.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close().catchError((Object _) {}));
    _notification?.cancel();
    super.dispose();
  }
}

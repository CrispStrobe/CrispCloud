import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/storage_reference.dart';
import 'storage_scan_service.dart';
import 'storage_scan_snapshot_store.dart';

/// One already-authorized root. Live authority stays in memory; persistence
/// receives only the original opaque storage ID, label, path and full report.
class StorageScanBatchRoot {
  StorageScanBatchRoot({
    required this.source,
    required String rootPath,
    required this.storage,
    required this.sourceLabel,
    this.serialReadKey,
    String? snapshotStorageId,
  }) : rootPath = source.paths.normalize(rootPath),
       pathStyle = source.paths.style,
       snapshotStorageId = snapshotStorageId ?? storage.id,
       _identity = source.identity {
    if (rootPath.isEmpty ||
        rootPath.contains('\u0000') ||
        !source.paths.isAbsolute(this.rootPath)) {
      throw ArgumentError.value(rootPath, 'rootPath');
    }
  }

  final StorageScanSource source;
  final String rootPath;
  final StorageReference storage;
  final String sourceLabel;
  final String snapshotStorageId;
  final p.Style pathStyle;

  /// Roots sharing a stateful client serialize their reads. The slot can still
  /// overlap persistence with the next read after the previous scan closes.
  final Object? serialReadKey;
  final Object _identity;
  bool _lost = false;

  bool get isCurrent {
    if (_lost) return false;
    try {
      _lost = !source.isCurrent || source.identity != _identity;
    } catch (_) {
      _lost = true;
    }
    return !_lost;
  }
}

enum StorageScanBatchPhase {
  ready,
  queued,
  scanning,
  saving,
  stopping,
  saved,
  partial,
  cancelled,
  failed,
  sourceChanged,
  unconfirmed,
}

class StorageScanBatchJob {
  StorageScanBatchJob._(this.root);

  final StorageScanBatchRoot root;
  StorageScanBatchPhase _phase = StorageScanBatchPhase.ready;
  StorageScanProgress? _progress;
  StorageScanSummary? _summary;
  StorageScanSnapshotSummary? _snapshot;
  String? _error;

  StorageScanBatchPhase get phase => _phase;
  StorageScanProgress? get progress => _progress;
  StorageScanSummary? get summary => _summary;
  StorageScanSnapshotSummary? get snapshot => _snapshot;
  String? get error => _error;
}

/// Keeps at most two complete scan-and-save jobs in flight. Catalog publication
/// is serialized, and a job retains its slot until persistence has settled.
class StorageScanBatchService extends ChangeNotifier {
  StorageScanBatchService({
    required Iterable<StorageScanBatchRoot> roots,
    StorageScanService scanner = const StorageScanService(),
    StorageScanSnapshotStore? snapshots,
  }) : _scanner = scanner,
       snapshots = snapshots ?? StorageScanSnapshotStore(),
       jobs = List.unmodifiable(
         roots.take(maxRoots + 1).map(StorageScanBatchJob._),
       ) {
    if (jobs.isEmpty || jobs.length > maxRoots) {
      throw ArgumentError('A scan batch needs 1–$maxRoots folders.');
    }
  }

  static const maxRoots = 32;
  static const maxConcurrentJobs = 2;

  final StorageScanService _scanner;
  final StorageScanSnapshotStore snapshots;
  final List<StorageScanBatchJob> jobs;
  final _active = <StorageScanBatchJob>{};
  final _reading = HashSet<Object>.identity();
  final _finished = Completer<void>();
  Future<void> _saveTail = Future.value();
  bool _started = false;
  bool _cancelled = false;
  bool _disposed = false;

  bool get hasStarted => _started;
  bool get isRunning => _started && !_finished.isCompleted;
  bool get isStopping => _cancelled && isRunning;
  Future<void> get done => _finished.future;

  Future<void> start() {
    if (_disposed) throw StateError('This scan batch is closed.');
    if (_started || _finished.isCompleted) return done;
    _started = true;
    for (final job in jobs) {
      job._phase = StorageScanBatchPhase.queued;
    }
    _notify();
    _pump();
    return done;
  }

  void cancel() {
    if (_finished.isCompleted) return;
    _cancelled = true;
    for (final job in jobs) {
      switch (job.phase) {
        case StorageScanBatchPhase.ready:
        case StorageScanBatchPhase.queued:
          job._phase = StorageScanBatchPhase.cancelled;
        case StorageScanBatchPhase.scanning:
        case StorageScanBatchPhase.saving:
          job._phase = StorageScanBatchPhase.stopping;
        default:
          break;
      }
    }
    _notify();
    _completeIfDone();
  }

  void _pump() {
    while (!_disposed && !_cancelled && _active.length < maxConcurrentJobs) {
      StorageScanBatchJob? next;
      for (final job in jobs) {
        if (job.phase != StorageScanBatchPhase.queued) continue;
        final key = job.root.serialReadKey;
        if (key == null || !_reading.contains(key)) {
          next = job;
          break;
        }
      }
      if (next == null) break;
      if (!next.root.isCurrent) {
        next._phase = StorageScanBatchPhase.sourceChanged;
        _notify();
        continue;
      }
      _active.add(next);
      final key = next.root.serialReadKey;
      if (key != null) _reading.add(key);
      next._phase = StorageScanBatchPhase.scanning;
      _notify();
      unawaited(_run(next));
    }
    _completeIfDone();
  }

  Future<void> _run(StorageScanBatchJob job) async {
    var acceptedReport = false;
    try {
      late StorageScanResult result;
      try {
        result = await _scanner.scan(
          job.root.source,
          job.root.rootPath,
          isCancelled: () => _cancelled || _disposed,
          onProgress: (progress) {
            if (_cancelled || _disposed) return;
            job._progress = progress;
            _notify();
          },
        );
      } finally {
        final key = job.root.serialReadKey;
        if (key != null) _reading.remove(key);
        // The closed scan no longer uses a stateful source. Its job still owns
        // its slot while another slot may begin reading the next root.
        _pump();
      }
      job._summary = StorageScanSummary(
        rootPath: result.root.path,
        bytes: result.root.bytes,
        fileCount: result.root.fileCount,
        folderCount: result.root.folderCount,
        unknownSizeCount: result.root.unknownSizeCount,
        skippedLinkCount: result.root.skippedLinkCount,
        isComplete: result.isComplete,
        issues: result.issues,
        cancelled: result.cancelled,
        limited: result.limited,
        sourceChanged: result.sourceChanged,
        startedAt: result.startedAt,
        completedAt: result.completedAt,
        suppressedIssueCount: result.suppressedIssueCount,
      );
      if (result.sourceChanged || !job.root.isCurrent) {
        job._phase = StorageScanBatchPhase.sourceChanged;
      } else if (_cancelled || _disposed || result.cancelled) {
        job._phase = StorageScanBatchPhase.cancelled;
      } else if (result.issues.any(
        (issue) => issue.code == StorageScanIssueCode.rootUnavailable,
      )) {
        job._phase = StorageScanBatchPhase.failed;
        job._error = result.issues
            .firstWhere(
              (issue) => issue.code == StorageScanIssueCode.rootUnavailable,
            )
            .message;
      } else {
        // The completed report has passed its final live-source check. It is
        // now inert history, so a later disconnect cannot change its identity
        // or prevent persistence while it waits behind another accepted save.
        acceptedReport = true;
        job._phase = StorageScanBatchPhase.saving;
        _notify();
        final previousSave = _saveTail;
        final saveFinished = Completer<void>();
        _saveTail = saveFinished.future;
        try {
          await previousSave;
          if (_cancelled || _disposed) {
            throw StateError('Saving the scan was cancelled.');
          }
          final saved = await snapshots.save(
            result: result,
            storageId: job.root.snapshotStorageId,
            sourceLabel: job.root.sourceLabel,
            pathStyle: job.root.pathStyle,
            isCancelled: () => _cancelled || _disposed,
          );
          // A successful save is a durable commit, even if Stop or source loss
          // happened while the catalog acknowledgement was in flight.
          job._snapshot = saved;
          job._phase = saved.isComplete
              ? StorageScanBatchPhase.saved
              : StorageScanBatchPhase.partial;
        } finally {
          saveFinished.complete();
        }
      }
    } catch (error) {
      if (error is StorageScanSnapshotCommitUnconfirmed) {
        // The catalog may already contain this report. Stop or source loss
        // cannot establish that no save occurred, and retrying could duplicate
        // an existing historical version. Let the user inspect saved history.
        job._phase = StorageScanBatchPhase.unconfirmed;
        job._error = null;
      } else if (!acceptedReport && !job.root.isCurrent) {
        job._phase = StorageScanBatchPhase.sourceChanged;
      } else if (_cancelled || _disposed) {
        job._phase = StorageScanBatchPhase.cancelled;
      } else {
        job._phase = StorageScanBatchPhase.failed;
        job._error = error.toString();
      }
    } finally {
      _active.remove(job);
      _notify();
      _pump();
    }
  }

  void _completeIfDone() {
    if (_finished.isCompleted || _active.isNotEmpty) return;
    if (jobs.any(
      (job) =>
          job.phase == StorageScanBatchPhase.ready ||
          job.phase == StorageScanBatchPhase.queued,
    )) {
      return;
    }
    _finished.complete();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

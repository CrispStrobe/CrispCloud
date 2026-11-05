import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/rename_batch.dart';
import '../models/storage_reference.dart';
import 'multi_rename_service.dart';
import 'rename_batch_store.dart';

/// All calls stay bound to the captured storage. Implementations must reject
/// an existing destination. [exclusiveMoves] describes whether the provider
/// enforces that at the mutation itself, rather than a preceding check.
abstract class RenameBatchStorage {
  StorageReference get reference;
  bool get isCurrent;
  bool get exclusiveMoves;
  p.Context get paths;
  bool get caseSensitivePaths;
  Future<FileItem?> stat(String path);
  Future<void> move(FileItem source, String destination);

  /// A streaming digest is useful where the backend lacks stable object IDs.
  /// Null means an interrupted ambiguous rename requires manual inspection.
  Future<String?> contentDigest(FileItem item) async => null;

  String pathKey(String path) => caseSensitivePaths
      ? paths.normalize(path)
      : paths.normalize(path).toLowerCase();
}

class RenameBatchPersistenceException implements Exception {
  RenameBatchPersistenceException(this.record, this.cause);
  final RenameBatchRecord record;
  final Object cause;
  @override
  String toString() =>
      'Rename stopped because recovery history could not be saved: $cause';
}

class RenameBatchNeedsReview implements Exception {
  RenameBatchNeedsReview(this.message);
  final String message;
  @override
  String toString() => message;
}

class RenameBatchProgress {
  const RenameBatchProgress(
    this.message,
    this.completed,
    this.total,
    this.path,
  );
  final String message;
  final int completed;
  final int total;
  final String path;
}

/// A restartable sequence of exclusive (where available) sibling renames.
/// The journal is saved before and after each physical move. A batch is not a
/// filesystem transaction: completed work remains reviewable on interruption,
/// and restore is a separately checked reverse operation.
class RenameBatchService {
  RenameBatchService(this.store);
  final RenameBatchStore store;
  static final Set<String> _activeStorage = {};

  Future<RenameBatchRecord> prepare(
    MultiRenamePlan plan,
    RenameBatchStorage storage, {
    Map<String, dynamic> options = const {},
    bool Function()? isCancelled,
    void Function(RenameBatchProgress)? onProgress,
  }) async {
    _check(storage);
    if (!plan.canExecute) {
      throw MultiRenamePreflightException({
        '': plan.errors.isEmpty
            ? 'Resolve preview errors before renaming.'
            : plan.errors.join('\n'),
      });
    }
    if (plan.caseSensitivePaths != storage.caseSensitivePaths ||
        plan.pathContext.style != storage.paths.style) {
      throw StateError('Storage path rules changed. Rebuild the preview.');
    }
    final id = const Uuid().v4();
    final problems = <String, String>{};
    final items = <RenameBatchItem>[];
    final moving = {
      for (final entry in plan.entries.where((entry) => entry.directChange))
        storage.pathKey(entry.sourcePath): entry.sourcePath,
    };
    for (var index = 0; index < plan.entries.length; index++) {
      _check(storage);
      if (isCancelled?.call() == true) {
        throw StateError(
          'Rename preparation cancelled. No files were changed.',
        );
      }
      final entry = plan.entries[index];
      onProgress?.call(
        RenameBatchProgress(
          'Checking sources and destinations',
          index,
          plan.entries.length,
          entry.sourcePath,
        ),
      );
      final source = await storage.stat(entry.sourcePath);
      _check(storage);
      if (source == null) {
        problems[entry.sourcePath] = 'The original item no longer exists.';
        continue;
      }
      final captured = RenameFingerprint.fromFile(entry.file);
      final actual = RenameFingerprint.fromFile(source);
      if (!captured.matches(actual) ||
          storage.paths.normalize(source.path!) != entry.sourcePath) {
        problems[entry.sourcePath] =
            'The original item changed since selection. Refresh the preview.';
      }
      if (entry.directChange) {
        final directTarget = storage.paths.join(
          storage.paths.dirname(entry.sourcePath),
          entry.newName,
        );
        final target = await storage.stat(directTarget);
        _check(storage);
        if (target != null &&
            moving[storage.pathKey(target.path!)] != target.path) {
          problems[entry.sourcePath] =
              'A destination already exists: $directTarget';
        }
      }
      items.add(
        RenameBatchItem(
          sourcePath: entry.sourcePath,
          targetPath: entry.targetPath,
          currentPath: entry.sourcePath,
          fingerprint: actual,
        ),
      );
    }
    if (problems.isNotEmpty) throw MultiRenamePreflightException(problems);

    final current = items.map((item) => item.sourcePath).toList();
    final steps = <RenameBatchStep>[];
    void add(int index, String to, RenameStepKind kind) {
      final from = current[index];
      steps.add(
        RenameBatchStep(itemIndex: index, from: from, to: to, kind: kind),
      );
      _rewritePaths(current, from, to, items[index].fingerprint, storage);
    }

    final changed = [
      for (var i = 0; i < plan.entries.length; i++)
        if (plan.entries[i].directChange) i,
    ];
    if (plan.requiresStaging) {
      final deepest = List<int>.of(changed)
        ..sort(
          (a, b) => storage.paths
              .split(current[b])
              .length
              .compareTo(storage.paths.split(current[a]).length),
        );
      for (final index in deepest) {
        final temporary = storage.paths.join(
          storage.paths.dirname(current[index]),
          '.crisp-rename-${id.substring(0, 8)}-$index',
        );
        if (await storage.stat(temporary) != null) {
          throw MultiRenamePreflightException({
            items[index].sourcePath: 'A temporary recovery name already exists. Prepare the batch again.',
          });
        }
        _check(storage);
        add(index, temporary, RenameStepKind.stage);
      }
      final shallowest = List<int>.of(changed)
        ..sort(
          (a, b) => storage.paths
              .split(items[a].sourcePath)
              .length
              .compareTo(storage.paths.split(items[b].sourcePath).length),
        );
      for (final index in shallowest) {
        add(
          index,
          storage.paths.join(
            storage.paths.dirname(current[index]),
            plan.entries[index].newName,
          ),
          RenameStepKind.finish,
        );
      }
    } else {
      for (final index in changed) {
        add(index, plan.entries[index].targetPath, RenameStepKind.direct);
      }
    }
    for (var i = 0; i < items.length; i++) {
      if (current[i] != items[i].targetPath) {
        throw StateError('The rename dependency plan is inconsistent.');
      }
    }
    final record = RenameBatchRecord(
      id: id,
      storage: storage.reference,
      created: plan.referenceTime,
      items: items,
      steps: steps,
      windowsPaths: storage.paths.style == p.Style.windows,
      caseSensitivePaths: storage.caseSensitivePaths,
      exclusiveMoves: storage.exclusiveMoves,
      options: options,
    );
    _check(storage);
    await _save(record);
    return record;
  }

  Future<RenameBatchRecord> run(
    RenameBatchRecord record,
    RenameBatchStorage storage, {
    bool Function()? isCancelled,
    bool continueOnError = false,
    void Function(RenameBatchProgress)? onProgress,
  }) => _locked(
    storage,
    () => _run(
      record,
      storage,
      isCancelled: isCancelled,
      continueOnError: continueOnError,
      onProgress: onProgress,
    ),
  );

  Future<RenameBatchRecord> restore(
    RenameBatchRecord record,
    RenameBatchStorage storage, {
    bool Function()? isCancelled,
    void Function(RenameBatchProgress)? onProgress,
  }) => _locked(storage, () async {
    _validate(record, storage);
    if (record.isRestored) return record;
    await _reconcilePending(record, storage);
    // Resolve all currently existing reverse destinations before the first
    // write. Per-step checks still protect names created after this pass.
    final owned = record.items
        .map((item) => storage.pathKey(item.currentPath))
        .toSet();
    final problems = <String, String>{};
    for (final step in record.steps.where(
      (step) => step.state == RenameStepState.completed,
    )) {
      final target = await storage.stat(step.from);
      _check(storage);
      if (target != null && !owned.contains(storage.pathKey(target.path!))) {
        problems[step.from] =
            'Restore would overwrite an existing item: ${step.from}';
      }
    }
    if (problems.isNotEmpty) throw MultiRenamePreflightException(problems);
    record.restoring = true;
    record.state = RenameBatchState.restoring;
    record.message = null;
    await _save(record);
    return _run(
      record,
      storage,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  });

  /// Explicit user attestation for a provider that lacks stable IDs/digests.
  /// Only one observed destination with a missing source can be adopted. A
  /// known fingerprint mismatch or two existing paths is never overridden.
  Future<void> acknowledgeObservedDestination(
    RenameBatchRecord record,
    RenameBatchStorage storage,
  ) => _locked(storage, () async {
    _validate(record, storage);
    final pending = record.steps
        .where(
          (step) =>
              step.state == RenameStepState.inFlight ||
              step.state == RenameStepState.restoring,
        )
        .toList();
    if (pending.length != 1) {
      throw StateError('There is no single interrupted rename to verify.');
    }
    final step = pending.single;
    final reverse = step.state == RenameStepState.restoring;
    final from = reverse ? step.to : step.from;
    final to = reverse ? step.from : step.to;
    final expected = reverse ? step.after : step.before;
    if (expected == null) {
      throw StateError('The original fingerprint is unavailable.');
    }
    final source = await storage.stat(from);
    final destination = await storage.stat(to);
    _check(storage);
    if (source != null || destination == null) {
      throw StateError(
        'Manual verification requires a missing source and exactly one existing destination.',
      );
    }
    final actual = await _fingerprint(destination, storage);
    if (!expected.matches(actual, afterMove: true)) {
      throw StateError(
        'The observed destination conflicts with the saved object fingerprint.',
      );
    }
    _completeStep(record, step, actual, storage, reverse: reverse);
    record.manualResolutions.add(
      '${DateTime.now().toUtc().toIso8601String()}: User verified $from → $to',
    );
    record.state = RenameBatchState.paused;
    record.message =
        'Observed destination verified. Resume or restore this batch.';
    await _save(record);
  });

  Future<RenameBatchRecord> _run(
    RenameBatchRecord record,
    RenameBatchStorage storage, {
    bool Function()? isCancelled,
    bool continueOnError = false,
    void Function(RenameBatchProgress)? onProgress,
  }) async {
    _validate(record, storage);
    if (record.isRestored || (record.isComplete && !record.restoring)) {
      return record;
    }
    final errors = <String>[];
    try {
      await _reconcilePending(record, storage);
      record.state = record.restoring
          ? RenameBatchState.restoring
          : RenameBatchState.running;
      record.message = null;
      await _save(record);
      final ordered = record.restoring ? record.steps.reversed : record.steps;
      final canContinue =
          continueOnError &&
          record.steps.every((step) => step.kind == RenameStepKind.direct) &&
          !record.restoring;
      for (final step in ordered) {
        final expected = record.restoring
            ? RenameStepState.completed
            : RenameStepState.pending;
        if (step.state != expected) continue;
        if (isCancelled?.call() == true) {
          record.state = RenameBatchState.paused;
          record.message = 'Paused between operations. Resume or restore this batch from history.';
          await _save(record);
          return record;
        }
        _check(storage);
        final from = record.restoring ? step.to : step.from;
        final to = record.restoring ? step.from : step.to;
        onProgress?.call(
          RenameBatchProgress(
            record.restoring ? 'Restoring original names' : 'Renaming',
            record.restoring
                ? record.steps
                      .where((s) => s.state == RenameStepState.restored)
                      .length
                : record.completedSteps,
            record.steps.length,
            from,
          ),
        );
        try {
          final source = await storage.stat(from);
          _check(storage);
          if (source == null) throw StateError('Source is missing: $from');
          final wanted = record.restoring
              ? step.after
              : record.items[step.itemIndex].fingerprint;
          final fresh = await _fingerprint(source, storage);
          // A directory's contents and modified time may have changed through
          // earlier child steps. Its stable object ID and type must still match.
          if (wanted != null && !_matchesBeforeStep(wanted, fresh)) {
            throw StateError(
              'Source changed after the batch was prepared: $from',
            );
          }
          if (await storage.stat(to) != null) {
            throw StateError('Destination already exists: $to');
          }
          _check(storage);
          if (record.restoring) {
            step.state = RenameStepState.restoring;
            step.after = fresh;
          } else {
            step.state = RenameStepState.inFlight;
            step.before = fresh;
          }
          await _save(record);
          _check(storage);
          await storage.move(source, to);
          _check(storage);
          final moved = await storage.stat(to);
          if (moved == null) {
            throw RenameBatchNeedsReview(
              'The provider did not confirm the new path: $to',
            );
          }
          final after = await _fingerprint(moved, storage);
          if (!fresh.matches(after, afterMove: true)) {
            throw RenameBatchNeedsReview(
              'The destination identity changed unexpectedly: $to',
            );
          }
          _completeStep(
            record,
            step,
            after,
            storage,
            reverse: record.restoring,
          );
          await _save(record);
        } catch (error) {
          if (error is RenameBatchPersistenceException) rethrow;
          // A provider may fail after committing a rename. Reconcile the
          // journalled intent before deciding whether it is safe to continue.
          if (step.state == RenameStepState.inFlight ||
              step.state == RenameStepState.restoring) {
            await _reconcileStep(record, step, storage);
            if (step.state == RenameStepState.completed ||
                step.state == RenameStepState.restored) {
              continue;
            }
          }
          errors.add('$from: $error');
          if (!canContinue) rethrow;
        }
      }
      record.state = errors.isNotEmpty
          ? RenameBatchState.failed
          : record.restoring
          ? RenameBatchState.restored
          : RenameBatchState.completed;
      record.message = errors.isEmpty ? null : errors.join('\n');
      await _save(record);
    } on RenameBatchPersistenceException {
      rethrow;
    } catch (error) {
      record.state = error is RenameBatchNeedsReview
          ? RenameBatchState.needsReview
          : RenameBatchState.failed;
      record.message = error.toString();
      await _save(record);
    }
    return record;
  }

  Future<void> _reconcilePending(
    RenameBatchRecord record,
    RenameBatchStorage storage,
  ) async {
    for (final step in record.steps) {
      if (step.state == RenameStepState.inFlight ||
          step.state == RenameStepState.restoring) {
        await _reconcileStep(record, step, storage);
      }
    }
  }

  Future<void> _reconcileStep(
    RenameBatchRecord record,
    RenameBatchStep step,
    RenameBatchStorage storage,
  ) async {
    _check(storage);
    final reverse = step.state == RenameStepState.restoring;
    final from = reverse ? step.to : step.from;
    final to = reverse ? step.from : step.to;
    final expected = reverse ? step.after : step.before;
    if (expected == null) {
      throw RenameBatchNeedsReview(
        'The interrupted operation has no source fingerprint: $from',
      );
    }
    final before = await storage.stat(from);
    final after = await storage.stat(to);
    _check(storage);
    if (before != null && after == null) {
      final fingerprint = await _fingerprint(before, storage);
      if (!expected.matches(fingerprint)) {
        throw RenameBatchNeedsReview(
          'The source changed during interruption: $from',
        );
      }
      step.state = reverse
          ? RenameStepState.completed
          : RenameStepState.pending;
      await _save(record);
      return;
    }
    if (before == null && after != null && expected.canReconcile) {
      final fingerprint = await _fingerprint(after, storage);
      if (expected.matches(fingerprint, afterMove: true)) {
        _completeStep(record, step, fingerprint, storage, reverse: reverse);
        await _save(record);
        return;
      }
    }
    throw RenameBatchNeedsReview(
      'Inspect the interrupted rename before continuing. The original and destination cannot be safely reconciled: $from → $to. No further files were changed.',
    );
  }

  Future<RenameFingerprint> _fingerprint(
    FileItem file,
    RenameBatchStorage storage,
  ) async {
    final digest = file.uuid == null ? await storage.contentDigest(file) : null;
    _check(storage);
    return RenameFingerprint.fromFile(file, digest: digest);
  }

  bool _matchesBeforeStep(
    RenameFingerprint expected,
    RenameFingerprint actual,
  ) {
    if (expected.folder && !expected.link) {
      return actual.folder &&
          !actual.link &&
          (expected.objectId == null || expected.objectId == actual.objectId);
    }
    return expected.matches(actual);
  }

  void _completeStep(
    RenameBatchRecord record,
    RenameBatchStep step,
    RenameFingerprint after,
    RenameBatchStorage storage, {
    required bool reverse,
  }) {
    final from = reverse ? step.to : step.from;
    final to = reverse ? step.from : step.to;
    final current = record.items.map((item) => item.currentPath).toList();
    _rewritePaths(current, from, to, after, storage);
    for (var index = 0; index < current.length; index++) {
      record.items[index].currentPath = current[index];
    }
    record.items[step.itemIndex].fingerprint = after;
    if (!reverse) step.after = after;
    step.state = reverse ? RenameStepState.restored : RenameStepState.completed;
  }

  static void _rewritePaths(
    List<String> current,
    String from,
    String to,
    RenameFingerprint fingerprint,
    RenameBatchStorage storage,
  ) {
    for (var index = 0; index < current.length; index++) {
      if (storage.pathKey(current[index]) == storage.pathKey(from)) {
        current[index] = to;
      } else if (fingerprint.folder &&
          !fingerprint.link &&
          storage.paths.isWithin(
            storage.pathKey(from),
            storage.pathKey(current[index]),
          )) {
        current[index] = storage.paths.join(
          to,
          storage.paths.relative(current[index], from: from),
        );
      }
    }
  }

  void _validate(RenameBatchRecord record, RenameBatchStorage storage) {
    _check(storage);
    if (record.storage != storage.reference ||
        record.caseSensitivePaths != storage.caseSensitivePaths ||
        record.windowsPaths != (storage.paths.style == p.Style.windows)) {
      throw StateError(
        'Connect the original storage account and path namespace before recovering this batch.',
      );
    }
    if (record.exclusiveMoves && !storage.exclusiveMoves) {
      throw StateError(
        'The original exclusive rename capability is unavailable.',
      );
    }
    for (final step in record.steps) {
      if (!storage.paths.isAbsolute(step.from) ||
          !storage.paths.isAbsolute(step.to) ||
          storage.paths.dirname(step.from) != storage.paths.dirname(step.to) ||
          MultiRenameService.validateName(storage.paths.basename(step.to)) !=
              null) {
        throw const FormatException(
          'The recovery journal contains an invalid rename path.',
        );
      }
    }
  }

  static void _check(RenameBatchStorage storage) {
    if (!storage.isCurrent) {
      throw StateError('The captured storage account is no longer connected.');
    }
  }

  Future<void> _save(RenameBatchRecord record) async {
    try {
      await store.save(record);
    } catch (error) {
      throw RenameBatchPersistenceException(record, error);
    }
  }

  Future<T> _locked<T>(
    RenameBatchStorage storage,
    Future<T> Function() operation,
  ) async {
    final key = storage.reference.id;
    if (!_activeStorage.add(key)) {
      throw StateError(
        'Another rename batch is running on this storage. Wait for it to finish.',
      );
    }
    try {
      return await operation();
    } finally {
      _activeStorage.remove(key);
    }
  }

  static Map<String, FileItem> changes(
    RenameBatchRecord record, {
    bool sinceTargets = false,
  }) {
    final paths = p.Context(
      style: record.windowsPaths ? p.Style.windows : p.Style.posix,
    );
    return {
      for (final item in record.items)
        if ((sinceTargets ? item.targetPath : item.sourcePath) !=
            item.currentPath)
          (sinceTargets ? item.targetPath : item.sourcePath): item.asFile(
            paths.basename(item.currentPath),
          ),
    };
  }
}

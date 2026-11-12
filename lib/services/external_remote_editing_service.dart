import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/external_edit_session.dart';
import '../models/file_item.dart';
import '../models/storage_reference.dart';
import '../utils/async_lock.dart';
import 'cloud_storage_interface.dart';
import 'conditional_file_publication.dart';
import 'file_operation_backend.dart';
import 'private_tool_staging.dart';
import 'storage_identity.dart';

export '../models/external_edit_session.dart';

/// The host captures these values before its first await. The availability guard
/// belongs to the original source/account/grants, not to the current pane.
class ExternalEditSource {
  ExternalEditSource({
    required this.reference,
    required FileItem file,
    required this.client,
    required this.isCurrent,
    bool Function()? isReviewCurrent,
  }) : file = FileItem(
         name: file.name,
         path: file.path,
         uuid: file.uuid,
         storageId: file.storageId,
         isFolder: file.isFolder,
         size: file.size,
         updatedAt: file.updatedAt,
         isSymlink: file.isSymlink,
       ),
       isReviewCurrent = isReviewCurrent ?? isCurrent;

  final FileReference reference;
  final FileItem file;
  final CloudStorageClient client;
  final bool Function() isCurrent, isReviewCurrent;
  ConditionalFilePublication? get publication =>
      client is ConditionalFilePublication
      ? client as ConditionalFilePublication
      : null;
  bool get supportsStaging =>
      publication != null || client.transferCapabilities.boundedDownload;

  void check({bool review = false}) {
    if (!isCurrent() ||
        review && !isReviewCurrent() ||
        !client.isAuthenticated ||
        storageReferenceForClient(client) != reference.storage) {
      throw const ExternalEditException(ExternalEditFailure.sourceChanged);
    }
    if (reference.storage.isLocal ||
        file.isFolder ||
        file.isSymlink == true ||
        file.path != reference.path ||
        !p.posix.isAbsolute(reference.path) ||
        p.posix.normalize(reference.path) != reference.path ||
        reference.path == '/' ||
        reference.path.contains('\u0000')) {
      throw const ExternalEditException(ExternalEditFailure.invalid);
    }
    if (!supportsStaging) {
      throw const ExternalEditException(ExternalEditFailure.unsupported);
    }
  }
}

class ExternalEditConflictReview {
  ExternalEditConflictReview._(
    this.sessionId,
    this.generation,
    this.localSha256,
    this.remote,
  );
  final String sessionId, localSha256;
  final int generation;
  final FilePublicationVersion remote;
  bool _used = false;
}

/// Application-lifetime owner. Closing a dialog does not release a stage or
/// stop its save watcher; [close] retains all files before releasing leases.
class ExternalRemoteEditingService extends ChangeNotifier {
  ExternalRemoteEditingService({
    PrivateToolStagingStore? staging,
    DateTime Function()? now,
    this.debounce = const Duration(milliseconds: 700),
    this.pollInterval = const Duration(seconds: 3),
  }) : staging = staging ?? PrivateToolStagingStore(),
       _now = now ?? DateTime.now;
  final PrivateToolStagingStore staging;
  final DateTime Function() _now;
  final Duration debounce, pollInterval;
  final Map<String, ExternalEditSession> _sessions = {};
  final AsyncLock _catalog = AsyncLock();
  bool _closed = false;
  Future<void>? _closing;
  List<ExternalEditSession> get sessions => List.unmodifiable(_sessions.values);

  Future<List<ExternalEditSession>> restore() =>
      _catalog.synchronized(() async {
        if (_closed) {
          throw const ExternalEditException(
            ExternalEditFailure.retainedUnavailable,
          );
        }
        for (final id in await staging.list('external-edit')) {
          if (_sessions.containsKey(id)) continue;
          PrivateToolStage? stage;
          try {
            stage = await staging.open(kind: 'external-edit', id: id);
            ExternalEditRecord? record;
            try {
              final json = await stage.readManifest();
              if (json != null) record = ExternalEditRecord.fromJson(json);
            } catch (_) {
              /* Retain invalid/orphan stages for explicit cleanup. */
            }
            final session = ExternalEditSession._(this, stage, record, null);
            _sessions[id] = session;
          } on PrivateStageException catch (error) {
            await stage?.close();
            if (error.failure != PrivateStageFailure.busy) rethrow;
          }
        }
        if (!_closed) notifyListeners();
        return sessions;
      });

  Future<ExternalEditSession> prepare(ExternalEditSource source) =>
      _catalog.synchronized(() async {
        if (_closed) {
          throw const ExternalEditException(
            ExternalEditFailure.retainedUnavailable,
          );
        }
        source.check(review: true);
        final extension = p.posix.extension(source.file.name);
        final suffix = RegExp(r'^\.[A-Za-z0-9]{1,16}$').hasMatch(extension)
            ? extension
            : '.bin';
        final stage = await staging.create(kind: 'external-edit');
        final record = ExternalEditRecord(
          reference: source.reference,
          name: source.file.name,
          workingName: 'working$suffix',
          created: DateTime.now().toUtc(),
        );
        final session = ExternalEditSession._(this, stage, record, source);
        _sessions[stage.id] = session;
        try {
          await session._persist(record);
          await session._initialize();
        } catch (error) {
          await session._fail(error, phase: ExternalEditPhase.paused);
        }
        if (!_closed) notifyListeners();
        return session;
      });

  Future<void> _remove(ExternalEditSession session) async {
    _sessions.remove(session.id);
    if (!_closed) notifyListeners();
  }

  Future<void> close() => _closing ??= _closeAll();

  Future<void> _closeAll() async {
    _closed = true;
    await _catalog.synchronized(() async {
      Object? failure;
      StackTrace? trace;
      for (final session in List<ExternalEditSession>.of(_sessions.values)) {
        try {
          await session.close();
        } catch (error, stack) {
          failure ??= error;
          trace ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, trace!);
    });
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}

class ExternalEditSession extends ChangeNotifier {
  ExternalEditSession._(this.owner, this.stage, this._record, this._source);
  final ExternalRemoteEditingService owner;
  final PrivateToolStage stage;
  final AsyncLock _operations = AsyncLock();
  ExternalEditRecord? _record;
  ExternalEditSource? _source;
  StreamSubscription<void>? _watch;
  Timer? _debounce, _poll;
  bool _watching = false, _autoUpload = false, _closed = false;
  bool _launchPending = false;
  int _epoch = 0;
  Future<void>? _closeFuture;

  String get id => stage.id;
  String get directoryPath => stage.directoryPath;
  ExternalEditRecord? get record => _record;
  bool get isBound => _source != null;
  bool get watching => _watching;
  bool get autoUpload => _autoUpload;
  bool get canPublish =>
      _source?.publication != null && _record?.baseline != null;
  bool get isClosed => _closed;
  bool get isClosing => _closeFuture != null;

  ExternalEditRecord get _value {
    if (_closed || _record == null) {
      throw const ExternalEditException(
        ExternalEditFailure.retainedUnavailable,
      );
    }
    return _record!;
  }

  ExternalEditSource get _bound {
    if (owner._closed) {
      throw const ExternalEditException(
        ExternalEditFailure.retainedUnavailable,
      );
    }
    final source = _source;
    if (source == null) {
      throw const ExternalEditException(ExternalEditFailure.sourceChanged);
    }
    source.check();
    return source;
  }

  Future<void> _persist(ExternalEditRecord value) async {
    ExternalEditRecord.fromJson(value.toJson());
    await stage.writeManifest(value.toJson());
    _record = value;
    if (!_closed) notifyListeners();
  }

  static ExternalEditFailure _reason(Object error) {
    if (error is ExternalEditException) return error.failure;
    if (error is PrivateStageException) {
      return switch (error.failure) {
        PrivateStageFailure.tooLarge => ExternalEditFailure.tooLarge,
        PrivateStageFailure.changed => ExternalEditFailure.localChanged,
        PrivateStageFailure.busy => ExternalEditFailure.busy,
        _ => ExternalEditFailure.stagingFailed,
      };
    }
    if (error is FilePublicationException) {
      return switch (error.failure) {
        FilePublicationFailure.conflict => ExternalEditFailure.conflict,
        FilePublicationFailure.uncertain => ExternalEditFailure.uncertain,
        FilePublicationFailure.changed => ExternalEditFailure.sourceChanged,
        FilePublicationFailure.unsupported => ExternalEditFailure.unsupported,
        _ => ExternalEditFailure.uploadFailed,
      };
    }
    return ExternalEditFailure.uploadFailed;
  }

  Future<void> _fail(Object error, {ExternalEditPhase? phase}) async {
    if (_record == null || _closed) return;
    final reason = _reason(error);
    if (reason != ExternalEditFailure.localChanged) {
      _autoUpload = false;
    }
    final next = _record!.copyWith(
      failure: reason,
      phase:
          phase ??
          (reason == ExternalEditFailure.uncertain
              ? ExternalEditPhase.uncertain
              : reason == ExternalEditFailure.conflict
              ? ExternalEditPhase.conflict
              : ExternalEditPhase.paused),
    );
    try {
      await _persist(next);
    } catch (_) {
      // The working file and earlier durable intent survive a metadata failure.
      _record = next;
      _autoUpload = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _initialize() async {
    final source = _bound;
    final deadline = owner._now().add(const Duration(minutes: 2));
    void check() {
      if (owner._closed) {
        throw const ExternalEditException(
          ExternalEditFailure.retainedUnavailable,
        );
      }
      if (!owner._now().isBefore(deadline)) {
        throw const ExternalEditException(ExternalEditFailure.stagingFailed);
      }
      source.check(review: true);
    }

    Future<void> checkpoint() async => check();
    final record = _value;
    PrivateStagedFile working;
    FilePublicationVersion? baseline;
    if (source.publication case final publisher?) {
      baseline = await publisher.inspectForPublication(
        source.reference.path,
        checkCurrent: check,
      );
      if (source.reference.objectId != null &&
              source.reference.objectId != baseline.objectId ||
          source.reference.version != null &&
              source.reference.version != baseline.revision ||
          source.file.size != null && source.file.size != baseline.length) {
        throw const ExternalEditException(ExternalEditFailure.sourceChanged);
      }
      working = await stage.write(
        record.workingName,
        publisher.readForPublication(baseline, checkCurrent: check),
        maxBytes: conditionalFilePublicationLimit,
        expectedLength: baseline.length,
        checkpoint: checkpoint,
      );
      if (await publisher.inspectForPublication(
            source.reference.path,
            checkCurrent: check,
          ) !=
          baseline) {
        throw const ExternalEditException(ExternalEditFailure.conflict);
      }
    } else {
      final backend = CloudOperationBackend(
        source.client,
        isCurrent: source.isCurrent,
      );
      final before = await backend
          .stat(source.reference.path)
          .timeout(const Duration(seconds: 30));
      check();
      if (before == null ||
          before.isFolder ||
          before.isSymlink == true ||
          before.size == null ||
          before.size! < 0 ||
          source.file.uuid != null && source.file.uuid != before.uuid ||
          source.file.size != null && source.file.size != before.size) {
        throw const ExternalEditException(ExternalEditFailure.sourceChanged);
      }
      if (before.size! > conditionalFilePublicationLimit) {
        throw const ExternalEditException(ExternalEditFailure.tooLarge);
      }
      working = await stage.write(
        record.workingName,
        backend.readFile(before).timeout(const Duration(seconds: 30)),
        maxBytes: conditionalFilePublicationLimit,
        expectedLength: before.size,
        checkpoint: checkpoint,
      );
      final after = await backend
          .stat(source.reference.path)
          .timeout(const Duration(seconds: 30));
      check();
      if (after == null ||
          after.uuid != before.uuid ||
          after.size != before.size ||
          after.updatedAt != before.updatedAt ||
          after.isFolder ||
          after.isSymlink == true) {
        throw const ExternalEditException(ExternalEditFailure.sourceChanged);
      }
    }
    check();
    await _persist(
      record.copyWith(
        baseline: baseline,
        baselineSha256: working.sha256,
        localSha256: working.sha256,
        phase: ExternalEditPhase.ready,
        failure: null,
      ),
    );
  }

  /// A recovered session remains paused. Rebinding explicitly proves both the
  /// original storage route and the provider's immutable account/object identity.
  Future<void> rebind(ExternalEditSource source) => _operations.synchronized(
    () async {
      final value = _value;
      source.check(review: true);
      if (source.reference.storage != value.reference.storage ||
          source.reference.path != value.reference.path ||
          !value.reference.storage.persistent) {
        throw const ExternalEditException(ExternalEditFailure.sourceChanged);
      }
      final baseline = value.baseline;
      if (baseline != null) {
        final publisher = source.publication;
        if (publisher == null) {
          throw const ExternalEditException(ExternalEditFailure.unsupported);
        }
        final remote = await publisher.inspectForPublication(
          value.reference.path,
          checkCurrent: () => source.check(review: true),
        );
        if (!remote.sameObject(baseline)) {
          throw const ExternalEditException(ExternalEditFailure.sourceChanged);
        }
        _source = source;
        await _reconcile(remote);
      } else {
        _source = source;
      }
      await _captureLocal();
    },
  );

  Future<void> _reconcile(FilePublicationVersion remote) async {
    var value = _value;
    final attempt = value.attempt;
    if (attempt?.providerHash != null &&
        remote.sameObject(attempt!.expected) &&
        remote.contentHash == attempt.providerHash &&
        remote.length == attempt.length) {
      value = value.copyWith(
        baseline: remote,
        baselineSha256: attempt.sha256,
        savedGeneration: attempt.generation,
        attempt: null,
        phase: ExternalEditPhase.paused,
        failure: null,
      );
      await _persist(value);
      await _removeSnapshot(attempt.name);
    } else if (remote == (attempt?.expected ?? value.baseline)) {
      await _persist(
        value.copyWith(
          attempt: null,
          phase: ExternalEditPhase.paused,
          failure: null,
        ),
      );
      if (attempt != null) await _removeSnapshot(attempt.name);
    } else {
      await _persist(
        value.copyWith(
          phase: ExternalEditPhase.conflict,
          failure: ExternalEditFailure.conflict,
        ),
      );
    }
  }

  Future<PrivateStagedFile> workingFile({bool forExport = false}) =>
      stage.inspect(
        _value.workingName,
        maxBytes: forExport
            ? 0x1fffffffffffff
            : conditionalFilePublicationLimit,
      );

  Future<PrivateStagedFile> _captureLocal() async {
    final value = _value;
    final local = await workingFile();
    if (local.sha256 != value.localSha256) {
      final blocked =
          value.phase == ExternalEditPhase.conflict ||
          value.phase == ExternalEditPhase.uncertain;
      await _persist(
        value.copyWith(
          localSha256: local.sha256,
          generation: value.generation + 1,
          phase: blocked
              ? value.phase
              : local.sha256 == value.baselineSha256
              ? ExternalEditPhase.ready
              : ExternalEditPhase.pending,
          failure: blocked ? value.failure : null,
        ),
      );
    }
    return local;
  }

  void _requestScan({bool changed = false}) {
    if (!_watching || _closed || owner._closed) return;
    if (changed) _epoch++;
    _debounce?.cancel();
    _debounce = Timer(owner.debounce, () {
      unawaited(
        scan().catchError((Object error) async {
          await _fail(error);
        }),
      );
    });
  }

  /// Directory events include atomic-rename saves. Polling also catches missed
  /// platform events. Neither source starts automatically during recovery.
  Future<void> watch({required bool autoUpload}) =>
      _operations.synchronized(() async {
        if (_closeFuture != null || owner._closed) {
          throw const ExternalEditException(
            ExternalEditFailure.retainedUnavailable,
          );
        }
        final value = _value;
        if (autoUpload) {
          _bound;
          if (!canPublish ||
              value.phase == ExternalEditPhase.conflict ||
              value.phase == ExternalEditPhase.uncertain) {
            throw const ExternalEditException(ExternalEditFailure.conflict);
          }
        }
        await _captureLocal();
        _watching = true;
        _autoUpload = autoUpload;
        _watch ??= stage
            .watch(value.workingName)
            .listen(
              (_) => _requestScan(changed: true),
              onError: (Object _) {
                /* Periodic inspection remains available. */
              },
            );
        _poll ??= Timer.periodic(owner.pollInterval, (_) => _requestScan());
        notifyListeners();
        _requestScan();
      });

  Future<void> pause() async {
    _watching = false;
    _autoUpload = false;
    _debounce?.cancel();
    _poll?.cancel();
    _poll = null;
    await _watch?.cancel();
    _watch = null;
    await _operations.synchronized(() async {
      if (_closed || _record == null) return;
      if (_value.phase != ExternalEditPhase.uncertain &&
          _value.phase != ExternalEditPhase.conflict) {
        await _persist(_value.copyWith(phase: ExternalEditPhase.paused));
      }
    });
  }

  Future<void> scan() => _operations.synchronized(() async {
    await _captureLocal();
    if (_watching &&
        _autoUpload &&
        _value.hasLocalChanges &&
        _value.phase != ExternalEditPhase.conflict &&
        _value.phase != ExternalEditPhase.uncertain) {
      await _publish(automatic: true);
    }
  });

  Future<void> upload() => _operations.synchronized(() async {
    await _captureLocal();
    if (_value.phase == ExternalEditPhase.conflict ||
        _value.phase == ExternalEditPhase.uncertain) {
      throw const ExternalEditException(ExternalEditFailure.conflict);
    }
    if (_value.hasLocalChanges) await _publish(automatic: false);
  });

  Future<void> reconcile() => _operations.synchronized(() async {
    final source = _bound;
    final baseline = _value.baseline;
    if (baseline == null || source.publication == null) {
      throw const ExternalEditException(ExternalEditFailure.unsupported);
    }
    final remote = await source.publication!.inspectForPublication(
      _value.reference.path,
      checkCurrent: source.check,
    );
    if (!remote.sameObject(baseline)) {
      throw const ExternalEditException(ExternalEditFailure.sourceChanged);
    }
    await _reconcile(remote);
    await _captureLocal();
  });

  Future<ExternalEditConflictReview> reviewConflict() =>
      _operations.synchronized(() async {
        final source = _bound;
        final local = await _captureLocal();
        final baseline = _value.baseline;
        if (baseline == null || source.publication == null) {
          throw const ExternalEditException(ExternalEditFailure.unsupported);
        }
        final remote = await source.publication!.inspectForPublication(
          _value.reference.path,
          checkCurrent: source.check,
        );
        if (!remote.sameObject(baseline)) {
          throw const ExternalEditException(ExternalEditFailure.sourceChanged);
        }
        return ExternalEditConflictReview._(
          id,
          _value.generation,
          local.sha256,
          remote,
        );
      });

  Future<void> replaceReviewed(ExternalEditConflictReview review) =>
      _operations.synchronized(() async {
        final local = await _captureLocal();
        if (review._used ||
            review.sessionId != id ||
            review.generation != _value.generation ||
            review.localSha256 != local.sha256) {
          throw const ExternalEditException(ExternalEditFailure.localChanged);
        }
        review._used = true;
        await _publish(automatic: false, expected: review.remote);
      });

  Future<void> _publish({
    required bool automatic,
    FilePublicationVersion? expected,
  }) async {
    final source = _bound;
    final publisher = source.publication;
    expected ??= _value.baseline;
    if (publisher == null || expected == null) {
      throw const ExternalEditException(ExternalEditFailure.unsupported);
    }
    final capturedEpoch = _epoch;
    if (_value.generation == 0) {
      await _persist(_value.copyWith(generation: 1));
    }
    final generation = _value.generation;
    final snapshot = await stage.snapshot(
      _value.workingName,
      'generation-${const Uuid().v4()}.bin',
      maxBytes: conditionalFilePublicationLimit,
    );
    var intent = ExternalEditAttempt(
      generation: generation,
      name: snapshot.name,
      length: snapshot.length,
      sha256: snapshot.sha256,
      expected: expected,
    );
    var mayHaveCommitted = false;
    try {
      if (snapshot.sha256 != _value.localSha256) {
        throw const ExternalEditException(ExternalEditFailure.localChanged);
      }
      await _persist(
        _value.copyWith(
          attempt: intent,
          phase: ExternalEditPhase.uploading,
          failure: null,
        ),
      );
      final result = await publisher.publishFileVersion(
        expected,
        stage.openRead(snapshot),
        length: snapshot.length,
        checkCurrent: source.check,
        prepareCommit: (hash) async {
          final local = await workingFile();
          if (_closed ||
              owner._closed ||
              _epoch != capturedEpoch ||
              local.sha256 != snapshot.sha256 ||
              automatic && (!_watching || !_autoUpload)) {
            throw const ExternalEditException(ExternalEditFailure.localChanged);
          }
          intent = intent.prepared(hash);
          await _persist(_value.copyWith(attempt: intent));
          final currentLocal = await workingFile();
          source.check();
          if (currentLocal.sha256 != snapshot.sha256 ||
              _epoch != capturedEpoch ||
              automatic && (!_watching || !_autoUpload)) {
            throw const ExternalEditException(ExternalEditFailure.localChanged);
          }
          mayHaveCommitted = true;
        },
      );
      await _persist(
        _value.copyWith(
          baseline: result,
          baselineSha256: snapshot.sha256,
          savedGeneration: generation,
          attempt: null,
          phase: ExternalEditPhase.ready,
          failure: null,
        ),
      );
      mayHaveCommitted = false;
      await _removeSnapshot(snapshot.name);
      await _captureLocal();
    } catch (error) {
      final definiteConflict =
          error is FilePublicationException &&
          error.failure == FilePublicationFailure.conflict;
      final uncertain =
          error is FilePublicationException &&
              error.failure == FilePublicationFailure.uncertain ||
          mayHaveCommitted && !definiteConflict;
      if (!uncertain) {
        await _persist(_value.copyWith(attempt: null));
        await _removeSnapshot(snapshot.name);
      }
      await _fail(
        uncertain
            ? const ExternalEditException(ExternalEditFailure.uncertain)
            : error,
        phase: uncertain
            ? ExternalEditPhase.uncertain
            : definiteConflict
            ? ExternalEditPhase.conflict
            : ExternalEditPhase.pending,
      );
      if (_reason(error) == ExternalEditFailure.localChanged && automatic) {
        _requestScan();
      } else {
        rethrow;
      }
    }
  }

  Future<void> _removeSnapshot(String name) async {
    try {
      await stage.deleteFile(name);
    } catch (_) {
      /* Explicit cleanup also removes obsolete snapshots. */
    }
  }

  /// Pins the opening source guard independently of the subsequently persisted
  /// launch intent. Recovered local copies can be reviewed without reconnecting;
  /// their remote writes remain separately disabled until exact-source rebind.
  void Function() captureLaunchGuard() {
    final initial = !_value.launched ? _source : null;
    return () {
      if (_closed || owner._closed || _closeFuture != null) {
        throw const ExternalEditException(
          ExternalEditFailure.retainedUnavailable,
        );
      }
      initial?.check(review: true);
    };
  }

  /// Holds the session lease until a detached launch acknowledgement settles.
  /// Disposal waits and retains files; explicit deletion refuses a pending start.
  Future<void> runReviewedLaunch(Future<void> Function() launch) async {
    if (_launchPending || _closed || owner._closed || _closeFuture != null) {
      throw const ExternalEditException(ExternalEditFailure.busy);
    }
    _launchPending = true;
    try {
      await _operations.synchronized(() async {
        await _captureLocal();
        await _persist(_value.copyWith(launched: true));
        await launch();
      });
    } finally {
      _launchPending = false;
    }
  }

  /// Records intent without executing an application. Launchers use
  /// [runReviewedLaunch] to hold the lease through the actual OS acknowledgement.
  Future<void> recordLaunchIntent() => _operations.synchronized(() async {
    _source?.check(review: true);
    await _captureLocal();
    await _persist(_value.copyWith(launched: true));
  });

  Future<void> close() => _closeFuture ??= _close(delete: false);
  Future<void> discard({required bool editorClosed}) {
    if (!editorClosed || _closeFuture != null || _launchPending) {
      throw const ExternalEditException(ExternalEditFailure.busy);
    }
    return _closeFuture = _close(delete: true);
  }

  Future<void> _close({required bool delete}) async {
    Object? failure;
    StackTrace? trace;
    try {
      await pause();
    } catch (error, stack) {
      failure = error;
      trace = stack;
    }
    await _operations.synchronized(() async {
      _closed = true;
      try {
        if (delete && failure == null) {
          await stage.delete();
        } else {
          await stage.close();
        }
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
      if (delete) await owner._remove(this);
    });
    final error = failure;
    if (error != null) {
      if (delete && !owner._closed) {
        // Native cleanup always releases its lease, even on partial failure.
        // Reopen any surviving directory with a new handle so a failed handle
        // cannot conceal retained edits from the live catalog.
        try {
          await owner.restore();
        } catch (_) {
          /* Discovery can be retried. */
        }
      }
      Error.throwWithStackTrace(error, trace!);
    }
  }
}

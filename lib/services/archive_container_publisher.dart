import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:uuid/uuid.dart';

import '../models/archive_endpoint.dart';
import '../models/file_item.dart';
import 'archive_directory_snapshot.dart';
import 'archive_publication_journal.dart';
import 'archive_publication_lease.dart';
import 'archive_publication_access_policy.dart';
import 'archive_publication_cleanup_stub.dart'
    if (dart.library.io) 'archive_publication_cleanup_io.dart'
    as native_cleanup;
import 'file_operation_service.dart';
import 'file_operation_backend.dart' show LocalOperationBackend;
import 'storage_transfer_contract.dart';

/// Publication uses two exclusive moves, not an atomic replace. The original
/// may briefly be absent, but a verified backup is retained until the installed
/// candidate is read back. Every destructive intent is durably acknowledged.
class ArchiveContainerPublisher {
  ArchiveContainerPublisher(
    this.backend,
    this.journal, {
    Duration Function(int bytes)? verificationDeadline,
  }) : _deadlineForBytes = verificationDeadline ?? _verificationDeadline;
  final FileOperationBackend backend;
  final ArchivePublicationJournal journal;
  final Duration Function(int bytes) _deadlineForBytes;
  ArchivePublicationRecord? _active;
  bool _running = false;
  ArchivePublicationLease? _lease;
  bool _mutationAuthority = false;
  FileOperationControl? _control;
  bool _pauseAllowed = true;
  Duration _pausedTime = Duration.zero;
  bool _publicationCommitted = false;
  Object? _observerWarning;

  /// A phase observer failed after verified publication. The receipt remains
  /// authoritative; callers can surface this issue without replaying a save.
  Object? get observerWarning => _observerWarning;

  static String? unsupportedReason(FileOperationBackend backend) {
    if (kIsWeb) {
      return 'Archive publication is unavailable without a process-lifetime recovery lease in this browser.';
    }
    if (backend is! LocalOperationBackend &&
        (backend is! ArchivePublicationAccessPolicy ||
            !(backend as ArchivePublicationAccessPolicy)
                .preservesArchiveAccessPolicy)) {
      return 'This provider cannot establish that archive staging and replacement preserve the original sharing and access policy.';
    }
    final capabilities = backend.capabilities;
    if (!backend.supportsStagedVerification ||
        !capabilities.nativeMove ||
        !capabilities.atomicMove ||
        !capabilities.noReplaceMove) {
      return 'This destination cannot publish an archive with verified staging and exact no-replace moves.';
    }
    if (!backend.canRecover || backend.storageReference?.persistent != true) {
      return 'This destination has no persistent identity for archive publication recovery.';
    }
    return null;
  }

  ArchivePublicationRecord? get activeRecord => _active;

  void _check({bool Function()? isCancelled, bool allowCancellation = false}) {
    if (!backend.isCurrent) {
      throw StateError('The captured archive account is no longer current.');
    }
    if (_active != null && backend.storageReference != _active!.storage) {
      throw StateError('The captured archive storage identity changed.');
    }
    if (_running &&
        _active != null &&
        (!_mutationAuthority || _lease?.isHeld != true)) {
      throw StateError(
        'Archive publication mutation authority is no longer acknowledged.',
      );
    }
    if (!allowCancellation && (isCancelled?.call() ?? false)) {
      throw const FileOperationCancelled();
    }
  }

  Future<void> _checkpoint({bool Function()? isCancelled}) async {
    _check(isCancelled: isCancelled);
    if (_pauseAllowed && isCancelled != null && _control != null) {
      final paused = _control!.isPaused ? (Stopwatch()..start()) : null;
      try {
        await _control!.checkpoint();
      } finally {
        if (paused != null) _pausedTime += paused.elapsed;
      }
    }
    _check(isCancelled: isCancelled);
  }

  Stream<T> _controlled<T>(Stream<T> input, bool Function()? isCancelled) =>
      isCancelled == null ? input : _control?.bind(input) ?? input;

  void _notifyPhase(
    ArchivePublicationPhase phase,
    void Function(ArchivePublicationPhase)? observer,
  ) {
    try {
      observer?.call(phase);
    } catch (error) {
      if (!_publicationCommitted) rethrow;
      _observerWarning ??= error;
    }
  }

  Future<void> _guardPaths(ArchivePublicationRecord record) async {
    _check();
    if (unsupportedReason(backend) case final String reason) {
      throw UnsupportedError(reason);
    }
    if (backend.storageReference != record.storage) {
      throw StateError('Reconnect the exact original archive storage.');
    }
    final paths = backend.paths;
    final path = record.original.path!;
    if (!paths.isAbsolute(path) ||
        paths.normalize(path) != path ||
        backend.isRootPath(path)) {
      throw StateError('The archive publication path is invalid.');
    }
    for (final snapshot in [
      record.candidate,
      record.backup,
      record.published,
    ]) {
      if (snapshot == null) continue;
      final expected = identical(snapshot, record.candidate)
          ? record.candidatePath(paths)
          : identical(snapshot, record.backup)
          ? record.backupPath(paths)
          : path;
      if (snapshot.path != expected ||
          snapshot.isFolder ||
          snapshot.isSymlink == true) {
        throw StateError(
          'The saved archive publication contains an unsafe path.',
        );
      }
    }
    var parent = paths.dirname(path);
    while (true) {
      final item = await backend.stat(parent);
      _check();
      if (item == null || !item.isFolder || item.isSymlink == true) {
        throw StateError('The archive publication parent changed: $parent');
      }
      final next = paths.dirname(parent);
      if (parent == next) break;
      parent = next;
    }
  }

  Future<void> _record(
    ArchivePublicationRecord record, {
    bool begin = false,
  }) async {
    try {
      await journal.write(record, begin: begin, expected: _active);
    } catch (_) {
      _mutationAuthority = false;
      rethrow;
    }
    _active = record;
  }

  Future<({FileItem file, String hash})?> _inspect(
    String path, {
    bool Function()? isCancelled,
  }) async {
    await _checkpoint(isCancelled: isCancelled);
    final file = await backend.stat(path);
    _check(isCancelled: isCancelled);
    if (file == null) return null;
    if (file.isFolder ||
        file.isSymlink == true ||
        file.size == null ||
        file.size! < 0 ||
        file.size! > ArchivePublicationRecord.maximumContainerBytes) {
      throw StateError(
        'Archive recovery requires a bounded regular file: $path',
      );
    }
    var count = 0;
    final elapsed = Stopwatch()..start();
    final pausedBefore = _pausedTime;
    final deadline = _deadlineForBytes(file.size!);
    Stream<List<int>> verified() async* {
      await for (final chunk in _controlled(
        backend.readFile(file).timeout(const Duration(seconds: 30)),
        isCancelled,
      )) {
        await _checkpoint(isCancelled: isCancelled);
        if (elapsed.elapsed - (_pausedTime - pausedBefore) > deadline) {
          throw TimeoutException(
            'Archive verification exceeded its size-dependent deadline.',
          );
        }
        count += chunk.length;
        if (count > ArchivePublicationRecord.maximumContainerBytes ||
            count > file.size!) {
          throw StateError('Archive recovery file size changed: $path');
        }
        yield chunk;
      }
    }

    final hash = await sha256.bind(verified()).first;
    final after = await backend.stat(path);
    _check(isCancelled: isCancelled);
    if (count != file.size || !sameArchiveFile(file, after)) {
      throw StateError('Archive recovery file changed while reading: $path');
    }
    return (file: after!, hash: hash.toString());
  }

  Future<void> _verifyDependency(
    ArchivePublicationRecord record, {
    bool Function()? isCancelled,
  }) async {
    final directory = record.directoryDependency;
    if (directory != null) {
      _check(isCancelled: isCancelled);
      final path = directory.directory.path!;
      if (backend is! LocalOperationBackend ||
          directory.storage != backend.storageReference ||
          !backend.paths.isAbsolute(path) ||
          backend.paths.normalize(path) != path ||
          [
            record.original.path!,
            record.candidatePath(backend.paths),
            record.backupPath(backend.paths),
          ].any((other) => backend.isWithin(path, other))) {
        throw StateError(
          'The saved synchronization source directory is invalid or contains the archive.',
        );
      }
      await verifyArchiveDirectoryDependency(
        backend,
        directory,
        control: isCancelled == null ? null : _control,
        checkpoint: () => _checkpoint(isCancelled: isCancelled),
        isCancelled: () {
          _check(isCancelled: isCancelled);
          return false;
        },
      );
      _check(isCancelled: isCancelled);
    }
    final dependency = record.dependency;
    if (dependency == null) return;
    _check(isCancelled: isCancelled);
    final path = dependency.file.path!;
    if (dependency.storage != backend.storageReference ||
        !backend.paths.isAbsolute(path) ||
        backend.paths.normalize(path) != path ||
        backend.isRootPath(path) ||
        [
          record.original.path!,
          record.candidatePath(backend.paths),
          record.backupPath(backend.paths),
        ].any((other) => backend.samePath(path, other))) {
      throw StateError('The saved move destination authority is invalid.');
    }
    var parent = backend.paths.dirname(path);
    while (true) {
      final item = await backend
          .stat(parent)
          .timeout(const Duration(seconds: 30));
      _check(isCancelled: isCancelled);
      if (item == null || !item.isFolder || item.isSymlink == true) {
        throw StateError('The move destination parent changed.');
      }
      final next = backend.paths.dirname(parent);
      if (next == parent) break;
      parent = next;
    }
    final current = await _inspect(path, isCancelled: isCancelled);
    if (current == null ||
        current.hash != dependency.sha256 ||
        !sameArchiveFile(dependency.file, current.file)) {
      throw StateError(
        'The verified move destination changed or is missing. Source recovery files are retained.',
      );
    }
    if (_accessPolicyHash(await _readAccessPolicy(path)) !=
            dependency.accessPolicySha256 ||
        !sameArchiveFile(
          dependency.file,
          await backend.stat(path).timeout(const Duration(seconds: 30)),
        )) {
      throw StateError(
        'The verified move destination identity or access policy changed.',
      );
    }
    _check(isCancelled: isCancelled);
  }

  Future<ArchivePublicationReceipt> publish({
    required FileItem original,
    required String originalSha256,
    required Uint8List bytes,
    ArchivePublicationRecord? retry,
    bool Function()? isCancelled,
    FileOperationControl? control,
    void Function(ArchivePublicationPhase)? onPhase,
    TransferCheckpoint? beforePublication,
    ArchivePublicationDependency? dependency,
    ArchivePublicationDirectoryDependency? directoryDependency,
  }) async {
    // Keep the original buffered API bounded. Large candidates must retain
    // their private spool and use publishStream throughout publication.
    if (bytes.length > 256 * 1024 * 1024) {
      throw const FormatException(
        'Buffered archive publication is limited to 256 MiB. Use a streamed candidate.',
      );
    }
    return publishStream(
      original: original,
      originalSha256: originalSha256,
      length: bytes.length,
      candidateSha256: sha256.convert(bytes).toString(),
      openRead: () => Stream.value(bytes),
      retry: retry,
      isCancelled: isCancelled,
      control: control,
      onPhase: onPhase,
      beforePublication: beforePublication,
      dependency: dependency,
      directoryDependency: directoryDependency,
    );
  }

  /// Publishes a captured, repeatable candidate without collecting its bytes.
  ///
  /// The caller owns the source (normally a sealed private spool) until this
  /// future completes. [candidateSha256] and [length] describe the reviewed
  /// candidate. Every streamed byte is counted and hashed before staging may
  /// commit; staged and installed files are independently read back through
  /// the same recovery and access-policy guards as buffered publication.
  /// A retry can reuse an already verified candidate without reopening the
  /// source, but must still provide the identical length and fingerprint.
  Future<ArchivePublicationReceipt> publishStream({
    required FileItem original,
    required String originalSha256,
    required int length,
    required String candidateSha256,
    required Stream<List<int>> Function() openRead,
    ArchivePublicationRecord? retry,
    bool Function()? isCancelled,
    FileOperationControl? control,
    void Function(ArchivePublicationPhase)? onPhase,
    TransferCheckpoint? beforePublication,
    ArchivePublicationDependency? dependency,
    ArchivePublicationDirectoryDependency? directoryDependency,
  }) async {
    if (_running) {
      throw StateError('An archive publication is already running.');
    }
    if (length < 0 ||
        length > ArchivePublicationRecord.maximumContainerBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(candidateSha256)) {
      throw const FormatException('Invalid streamed archive candidate.');
    }
    _running = true;
    _active = null;
    _control = control;
    _pauseAllowed = retry?.backup == null;
    _pausedTime = Duration.zero;
    _publicationCommitted = false;
    _observerWarning = null;
    final externalCancellation = isCancelled;
    isCancelled = () =>
        (control?.isCancelled ?? false) ||
        (externalCancellation?.call() ?? false);
    try {
      await _checkpoint(isCancelled: isCancelled);
      if (unsupportedReason(backend) case final String reason) {
        throw UnsupportedError(reason);
      }
      final record =
          retry ??
          ArchivePublicationRecord(
            id: const Uuid().v4(),
            storage: backend.storageReference!,
            original: original,
            originalSha256: originalSha256,
            candidateSha256: candidateSha256,
            candidateBytes: length,
            phase: ArchivePublicationPhase.prepared,
            createdAt: DateTime.now().toUtc(),
            dependency: dependency,
            directoryDependency: directoryDependency,
          );
      if (record.candidateSha256 != candidateSha256 ||
          record.candidateBytes != length ||
          record.originalSha256 != originalSha256 ||
          dependency != null &&
              jsonEncode(record.dependency?.toJson()) !=
                  jsonEncode(dependency.toJson()) ||
          directoryDependency != null &&
              jsonEncode(record.directoryDependency?.toJson()) !=
                  jsonEncode(directoryDependency.toJson())) {
        throw StateError(
          'The saved publication belongs to a different archive draft.',
        );
      }
      await _guardPaths(record);
      if (retry == null) {
        await _verifyDependency(record, isCancelled: isCancelled);
      }
      _lease = await journal.acquirePublication(record.id);
      if (_lease == null) {
        throw StateError(
          'This archive publication is already owned by another operation.',
        );
      }
      _mutationAuthority = true;
      if (retry == null) {
        final current = await _inspect(
          original.path!,
          isCancelled: isCancelled,
        );
        if (current == null ||
            !sameArchiveFile(original, current.file) ||
            current.hash != originalSha256) {
          throw StateError(
            'The original archive changed. Reopen it before publishing.',
          );
        }
        if (await backend.stat(record.candidatePath(backend.paths)) != null ||
            await backend.stat(record.backupPath(backend.paths)) != null) {
          throw StateError('An archive recovery path is already occupied.');
        }
        await _record(record, begin: true);
      } else {
        await journal.initialize();
        final saved = journal.records
            .where((value) => value.id == record.id)
            .firstOrNull;
        if (saved == null ||
            saved.candidateSha256 != record.candidateSha256 ||
            saved.storage != record.storage ||
            jsonEncode(saved.dependency?.toJson()) !=
                jsonEncode(record.dependency?.toJson()) ||
            jsonEncode(saved.directoryDependency?.toJson()) !=
                jsonEncode(record.directoryDependency?.toJson())) {
          throw StateError(
            'The original publication intent is no longer available.',
          );
        }
        _active = saved;
      }
      if (_active!.candidate == null) {
        await _stage(openRead, isCancelled: isCancelled, onPhase: onPhase);
      }
      return await _finish(
        isCancelled: isCancelled,
        onPhase: onPhase,
        beforePublication: beforePublication,
      );
    } catch (error) {
      if (_active != null) {
        await _restoreVacantOriginal();
        throw ArchivePublicationException(
          '$error. The publication remains recorded for review; retain the original and recovery files.',
          _active!,
        );
      }
      rethrow;
    } finally {
      _lease?.close();
      _lease = null;
      _mutationAuthority = false;
      _running = false;
      _control = null;
    }
  }

  Future<void> _stage(
    Stream<List<int>> Function() openRead, {
    bool Function()? isCancelled,
    void Function(ArchivePublicationPhase)? onPhase,
  }) async {
    var record = _active!;
    await _guardPaths(record);
    await _verifyDependency(record, isCancelled: isCancelled);
    final original = await _inspect(
      record.original.path!,
      isCancelled: isCancelled,
    );
    if (original == null ||
        original.hash != record.originalSha256 ||
        !sameArchiveFile(record.original, original.file)) {
      throw StateError(
        'The original archive changed before candidate staging.',
      );
    }
    final attributes = await _readAccessPolicy(original.file.path!);
    final accessHash = _accessPolicyHash(attributes);
    if (record.accessPolicySha256 != null &&
        record.accessPolicySha256 != accessHash) {
      throw StateError('The original archive access policy changed.');
    }
    await _record(record.copyWith(accessPolicySha256: accessHash));
    record = _active!;
    final path = record.candidatePath(backend.paths);
    final existing = await _inspect(path, isCancelled: isCancelled);
    if (existing != null && existing.hash != record.candidateSha256) {
      throw StateError('The recorded candidate was changed.');
    }
    if (existing == null) {
      _notifyPhase(ArchivePublicationPhase.prepared, onPhase);
      await _checkpoint(isCancelled: isCancelled);
      var sourceVerified = false;
      Stream<List<int>> checkedRead() async* {
        final digest = _ArchiveCandidateDigest();
        final hash = sha256.startChunkedConversion(digest);
        var received = 0;
        var closed = false;
        final elapsed = Stopwatch()..start();
        final pausedBefore = _pausedTime;
        final deadline = _deadlineForBytes(record.candidateBytes);
        try {
          await for (final chunk in _controlled(
            openRead().timeout(const Duration(seconds: 30)),
            isCancelled,
          )) {
            await _checkpoint(isCancelled: isCancelled);
            if (elapsed.elapsed - (_pausedTime - pausedBefore) > deadline) {
              throw TimeoutException(
                'Archive candidate reading exceeded its size-dependent deadline.',
              );
            }
            if (chunk.length > record.candidateBytes - received) {
              throw StateError('The reviewed archive candidate grew.');
            }
            if (chunk is! Uint8List &&
                chunk.any((byte) => byte < 0 || byte > 255)) {
              throw StateError('The archive candidate contains invalid bytes.');
            }
            for (var offset = 0; offset < chunk.length; offset += 256 * 1024) {
              await _checkpoint(isCancelled: isCancelled);
              final end = offset + 256 * 1024 < chunk.length
                  ? offset + 256 * 1024
                  : chunk.length;
              // A provider may reuse its input buffer after yielding. Own each
              // bounded chunk until the upload consumer has processed it.
              final bytes = Uint8List.fromList(chunk.sublist(offset, end));
              received += bytes.length;
              hash.add(bytes);
              yield bytes;
            }
          }
          await _checkpoint(isCancelled: isCancelled);
          if (received != record.candidateBytes) {
            throw StateError('The reviewed archive candidate was truncated.');
          }
          hash.close();
          closed = true;
          if (digest.value?.toString() != record.candidateSha256) {
            throw StateError('The reviewed archive candidate changed.');
          }
          sourceVerified = true;
        } finally {
          if (!closed) hash.close();
        }
      }

      await backend.writePreparedFile(
        path,
        checkedRead(),
        record.candidateBytes,
        replace: false,
        checkpoint: (state) async {
          await _checkpoint(
            isCancelled: state['phase'] == 'committed' ? null : isCancelled,
          );
        },
        verifyStaged: (staged) async {
          await _checkpoint(isCancelled: isCancelled);
          if (!sourceVerified) {
            throw StateError('The archive candidate stream was not verified.');
          }
          await _applyAccessPolicy(staged.path!, attributes);
          final checked = await _inspect(
            staged.path!,
            isCancelled: isCancelled,
          );
          if (checked?.hash != record.candidateSha256 ||
              checked?.file.size != record.candidateBytes) {
            throw StateError(
              'The staged archive candidate could not be verified.',
            );
          }
          final latest = await _inspect(
            record.original.path!,
            isCancelled: isCancelled,
          );
          if (latest == null ||
              latest.hash != record.originalSha256 ||
              !sameArchiveFile(record.original, latest.file)) {
            throw StateError(
              'The original archive changed during candidate staging.',
            );
          }
        },
      );
      if (!sourceVerified) {
        throw StateError('The archive candidate stream was not verified.');
      }
    }
    _check(isCancelled: isCancelled);
    if (existing != null) await _applyAccessPolicy(path, attributes);
    if (!_sameMetadata(attributes, await _readAccessPolicy(path))) {
      throw StateError(
        'The outer archive access policy could not be preserved.',
      );
    }
    final candidate = await _inspect(path, isCancelled: isCancelled);
    if (candidate == null ||
        candidate.hash != record.candidateSha256 ||
        candidate.file.size != record.candidateBytes) {
      throw StateError('The written archive candidate could not be verified.');
    }
    await _record(
      record.copyWith(
        phase: ArchivePublicationPhase.candidateWritten,
        candidate: candidate.file,
        clearMessage: true,
      ),
    );
    _notifyPhase(ArchivePublicationPhase.candidateWritten, onPhase);
  }

  Future<void> _intent(
    ArchivePublicationPhase phase, {
    void Function(ArchivePublicationPhase)? onPhase,
  }) async {
    await _record(_active!.copyWith(phase: phase, clearMessage: true));
    _notifyPhase(phase, onPhase);
  }

  Future<ArchivePublicationReceipt> _finish({
    bool Function()? isCancelled,
    void Function(ArchivePublicationPhase)? onPhase,
    TransferCheckpoint? beforePublication,
  }) async {
    var record = _active!;
    await _guardPaths(record);
    await _verifyDependency(record, isCancelled: isCancelled);
    var original = await _inspect(
      record.original.path!,
      isCancelled: isCancelled,
    );
    if (original?.hash == record.candidateSha256 &&
        original?.file.size == record.candidateBytes) {
      return _confirmPublished(original!.file, onPhase: onPhase);
    }
    if (record.candidate == null) {
      throw StateError(
        'The candidate was not durably verified. Restore the original and recreate the draft.',
      );
    }
    final candidate = await _inspect(
      record.candidatePath(backend.paths),
      isCancelled: isCancelled,
    );
    if (candidate == null ||
        candidate.hash != record.candidateSha256 ||
        candidate.file.size != record.candidateBytes ||
        !sameArchiveFile(record.candidate!, candidate.file)) {
      throw StateError('The saved archive candidate changed or disappeared.');
    }
    await _verifyAccessPolicy(record, candidate.file.path!);
    var backup = await _inspect(
      record.backupPath(backend.paths),
      isCancelled: isCancelled,
    );
    if (backup != null && backup.hash != record.originalSha256) {
      throw StateError('The recorded original backup changed.');
    }
    if (beforePublication != null) {
      // A caller's guard may await the shared pause control. Never invoke it
      // while this attempt (or an interrupted earlier attempt) owns a vacant
      // original path. Restore the verified original before such a guard.
      if (original == null && backup != null) {
        await _restoreVacantOriginal();
        original = await _inspect(record.original.path!);
        backup = await _inspect(record.backupPath(backend.paths));
        if (original?.hash != record.originalSha256 || backup != null) {
          throw StateError(
            'Restore the original before revalidating the archive source.',
          );
        }
        record = _active!;
        _pauseAllowed = true;
      }
      await _checkpoint(isCancelled: isCancelled);
      await beforePublication();
      await _checkpoint(isCancelled: isCancelled);
    }
    if (backup == null) {
      if (original == null ||
          original.hash != record.originalSha256 ||
          !sameArchiveFile(record.original, original.file)) {
        throw StateError('The original archive changed before publication.');
      }
      await _verifyAccessPolicy(record, original.file.path!);
      await _intent(ArchivePublicationPhase.backingUp, onPhase: onPhase);
      await _guardPaths(_active!);
      original = await _inspect(
        record.original.path!,
        isCancelled: isCancelled,
      );
      if (original == null ||
          original.hash != record.originalSha256 ||
          !sameArchiveFile(record.original, original.file)) {
        throw StateError('The original archive changed before backup.');
      }
      await _verifyAccessPolicy(record, original.file.path!);
      await _verifyDependency(record, isCancelled: isCancelled);
      await _checkpoint(isCancelled: isCancelled);
      _pauseAllowed = false;
      if (!await backend.moveNoReplace(
        original.file,
        record.backupPath(backend.paths),
      )) {
        throw UnsupportedError('Exclusive archive backup was refused.');
      }
      backup = await _inspect(record.backupPath(backend.paths));
      if (backup == null || backup.hash != record.originalSha256) {
        throw StateError(
          'The moved original could not be verified; its recovery location is retained.',
        );
      }
      await _verifyAccessPolicy(record, backup.file.path!);
      await _record(
        _active!.copyWith(
          phase: ArchivePublicationPhase.backedUp,
          backup: backup.file,
        ),
      );
      _notifyPhase(ArchivePublicationPhase.backedUp, onPhase);
    } else if (original != null) {
      throw StateError(
        'Both the original name and backup are occupied. Recovery requires review.',
      );
    }
    record = _active!;
    _pauseAllowed = false;
    await _intent(ArchivePublicationPhase.installing, onPhase: onPhase);
    // The source guard already ran after staging while the original name
    // remained available. Keep these final candidate/backup/access/dependency
    // checks after that potentially long read. Pause no longer waits here;
    // cancellation before installation restores the verified original.
    await _verifyDependency(record, isCancelled: isCancelled);
    await _guardPaths(_active!);
    _check(isCancelled: isCancelled);
    final checkedCandidate = await _inspect(
      record.candidatePath(backend.paths),
      isCancelled: isCancelled,
    );
    final checkedBackup = await _inspect(
      record.backupPath(backend.paths),
      isCancelled: isCancelled,
    );
    if (checkedCandidate?.hash != record.candidateSha256 ||
        checkedBackup?.hash != record.originalSha256 ||
        await backend.stat(record.original.path!) != null) {
      throw StateError(
        'Archive publication files changed before installation.',
      );
    }
    await _verifyAccessPolicy(record, checkedCandidate!.file.path!);
    await _verifyAccessPolicy(record, checkedBackup!.file.path!);
    _check(isCancelled: isCancelled);
    if (!await backend.moveNoReplace(
      checkedCandidate.file,
      record.original.path!,
    )) {
      throw UnsupportedError('Exclusive archive installation was refused.');
    }
    // Once installation may have happened, cancellation never implies rollback.
    // Verify or retain the recovery record; source cleanup needs a receipt.
    final installed = await _inspect(record.original.path!);
    if (installed == null ||
        installed.hash != record.candidateSha256 ||
        installed.file.size != record.candidateBytes) {
      throw StateError('Installed archive verification is unconfirmed.');
    }
    return _confirmPublished(installed.file, onPhase: onPhase);
  }

  Future<ArchivePublicationReceipt> _confirmPublished(
    FileItem file, {
    void Function(ArchivePublicationPhase)? onPhase,
  }) async {
    _publicationCommitted = true;
    _pauseAllowed = false;
    // This also guards restart confirmation of a candidate already installed
    // before a lost acknowledgement. An ordinary transient callback cannot
    // provide that guarantee after restart.
    await _verifyDependency(_active!);
    await _verifyAccessPolicy(_active!, file.path!);
    await _record(
      _active!.copyWith(
        phase: ArchivePublicationPhase.published,
        published: file,
        clearMessage: true,
      ),
    );
    _notifyPhase(ArchivePublicationPhase.published, onPhase);
    try {
      final record = _active!;
      final backup = await _inspect(record.backupPath(backend.paths));
      if (backup != null) {
        if (backup.hash != record.originalSha256) {
          throw StateError('The original backup changed and was retained.');
        }
        await _intent(ArchivePublicationPhase.cleaningBackup, onPhase: onPhase);
        await _deleteVerified(
          record.backupPath(backend.paths),
          record.originalSha256,
          publishedSha256: record.candidateSha256,
        );
      }
      final candidate = await _inspect(record.candidatePath(backend.paths));
      if (candidate != null) {
        if (candidate.hash != record.candidateSha256) {
          throw StateError('The candidate path changed and was retained.');
        }
        await _intent(
          ArchivePublicationPhase.cleaningCandidate,
          onPhase: onPhase,
        );
        await _deleteVerified(
          record.candidatePath(backend.paths),
          record.candidateSha256,
          publishedSha256: record.candidateSha256,
        );
      }
      await _intent(ArchivePublicationPhase.complete, onPhase: onPhase);
      return ArchivePublicationReceipt(record: _active!, file: file);
    } catch (_) {
      // Publication was already verified and durably recorded. An uncertain
      // cleanup does not remove the backup reference or claim a rollback.
      // A changed durable dependency is stronger than an ordinary cleanup
      // warning: do not issue a successful guarded-publication receipt for it.
      await _verifyDependency(_active!);
      return ArchivePublicationReceipt(
        record: _active!,
        file: file,
        cleanupPending: true,
      );
    }
  }

  Future<void> _deleteVerified(
    String path,
    String hash, {
    required String publishedSha256,
  }) async {
    final record = _active!;
    if (path != record.candidatePath(backend.paths) &&
        path != record.backupPath(backend.paths)) {
      throw StateError('Unsafe archive cleanup path.');
    }
    await _guardPaths(record);
    final guardedCleanup =
        record.hasDependency && publishedSha256 == record.candidateSha256;
    if (guardedCleanup) await _verifyDependency(record);
    final published = await _inspect(record.original.path!);
    if (published?.hash != publishedSha256) {
      throw StateError(
        'The published archive changed; recovery files retained.',
      );
    }
    await _verifyAccessPolicy(record, record.original.path!);
    final item = await _inspect(path);
    if (item == null) return;
    if (item.hash != hash ||
        !sameArchiveFile(item.file, await backend.stat(path))) {
      throw StateError('The recovery file changed before cleanup.');
    }
    final latest = await backend.stat(record.original.path!);
    if (!sameArchiveFile(published!.file, latest)) {
      throw StateError('The published archive changed before cleanup.');
    }
    _check();
    final removed = await native_cleanup.deleteNativeArchiveRecoveryFile(
      backend,
      item.file,
      published.file,
      recoverySha256: hash,
      publishedSha256: publishedSha256,
      checkpoint: () async => _check(),
      beforeDelete: guardedCleanup ? () => _verifyDependency(record) : null,
    );
    if (!removed) {
      if (!backend.capabilities.conditionalDelete || !_hasVersion(item.file)) {
        throw UnsupportedError(
          'This provider cannot conditionally delete a verified recovery object. Its exact backup remains recorded.',
        );
      }
      if (guardedCleanup) await _verifyDependency(record);
      _check();
      await backend.deleteFile(item.file);
    }
    _check();
    if (await backend.stat(path) != null) {
      throw StateError('Recovery cleanup was not confirmed.');
    }
  }

  /// A reviewed restore of a guarded publication may undo an installed
  /// candidate while its verified original backup still exists. Keep that
  /// candidate at its generated path before restoring; never overwrite either
  /// the installed name or an occupied recovery path.
  Future<void> _retainInstalledCandidateForRestore({
    bool Function()? isCancelled,
    void Function(ArchivePublicationPhase)? onPhase,
  }) async {
    final record = _active!;
    if (!record.hasDependency) return;
    await _guardPaths(record);
    var original = await _inspect(
      record.original.path!,
      isCancelled: isCancelled,
    );
    if (original == null || original.hash == record.originalSha256) return;
    if (original.hash != record.candidateSha256 ||
        original.file.size != record.candidateBytes) {
      throw StateError(
        'The installed source archive changed before restoration.',
      );
    }
    await _intent(ArchivePublicationPhase.restoring, onPhase: onPhase);
    await _guardPaths(record);
    original = await _inspect(record.original.path!, isCancelled: isCancelled);
    final backup = await _inspect(
      record.backupPath(backend.paths),
      isCancelled: isCancelled,
    );
    if (original?.hash != record.candidateSha256 ||
        original?.file.size != record.candidateBytes ||
        backup?.hash != record.originalSha256 ||
        await backend.stat(record.candidatePath(backend.paths)) != null) {
      throw StateError('Source recovery files changed before restoration.');
    }
    await _verifyAccessPolicy(record, original!.file.path!);
    await _verifyAccessPolicy(record, backup!.file.path!);
    _check(isCancelled: isCancelled);
    if (!await backend.moveNoReplace(
      original.file,
      record.candidatePath(backend.paths),
    )) {
      throw UnsupportedError(
        'Exclusive source candidate retention was refused.',
      );
    }
    final retained = await _inspect(record.candidatePath(backend.paths));
    if (retained?.hash != record.candidateSha256 ||
        retained?.file.size != record.candidateBytes) {
      throw StateError('The retained source candidate could not be verified.');
    }
    await _record(_active!.copyWith(candidate: retained!.file));
  }

  Future<void> _restoreVacantOriginal() async {
    if (_active == null ||
        !backend.isCurrent ||
        !_mutationAuthority ||
        _lease?.isHeld != true) {
      return;
    }
    try {
      final record = _active!;
      await _guardPaths(record);
      if (await backend.stat(record.original.path!) != null) return;
      final backup = await _inspect(record.backupPath(backend.paths));
      if (backup == null || backup.hash != record.originalSha256) return;
      await _verifyAccessPolicy(record, backup.file.path!);
      await _intent(ArchivePublicationPhase.restoring);
      if (!await backend.moveNoReplace(backup.file, record.original.path!)) {
        return;
      }
      final original = await _inspect(record.original.path!);
      if (original?.hash != record.originalSha256) return;
      await _record(
        _active!.copyWith(
          phase: ArchivePublicationPhase.restored,
          original: original!.file,
          clearPublished: record.hasDependency,
        ),
      );
    } catch (_) {
      // Durable earlier intent still owns every possible recovery location.
    }
  }

  Future<ArchiveRecoveryInspection> inspect(
    ArchivePublicationRecord record, {
    bool Function()? isCancelled,
  }) async {
    _check(isCancelled: isCancelled);
    await _guardPaths(record);
    final original = await _inspect(
      record.original.path!,
      isCancelled: isCancelled,
    );
    final candidate = await _inspect(
      record.candidatePath(backend.paths),
      isCancelled: isCancelled,
    );
    final backup = await _inspect(
      record.backupPath(backend.paths),
      isCancelled: isCancelled,
    );
    final oldOriginal = original?.hash == record.originalSha256;
    final published =
        original?.hash == record.candidateSha256 &&
        original?.file.size == record.candidateBytes;
    final candidateValid =
        record.candidate != null &&
        candidate?.hash == record.candidateSha256 &&
        candidate?.file.size == record.candidateBytes;
    final backupValid = backup?.hash == record.originalSha256;
    if (published) await _verifyAccessPolicy(record, original!.file.path!);
    if (candidateValid) {
      await _verifyAccessPolicy(record, candidate!.file.path!);
    }
    if (backupValid) await _verifyAccessPolicy(record, backup!.file.path!);
    final foreign =
        original != null && !oldOriginal && !published ||
        candidate != null && candidate.hash != record.candidateSha256 ||
        backup != null && !backupValid;
    String? dependencyFailure;
    try {
      await _verifyDependency(record, isCancelled: isCancelled);
    } catch (error) {
      _check(isCancelled: isCancelled);
      dependencyFailure = '$error';
    }
    final guardedRestore =
        record.hasDependency && published && backupValid && candidate == null;
    return ArchiveRecoveryInspection(
      record: record,
      canFinish:
          !foreign &&
          dependencyFailure == null &&
          (published ||
              candidateValid &&
                  (oldOriginal && backup == null ||
                      original == null && backupValid)),
      canRestore:
          !foreign &&
          (!published && (oldOriginal || original == null && backupValid) ||
              guardedRestore),
      message: foreign
          ? 'A container or recovery file changed. No automatic mutation is safe.'
          : dependencyFailure != null
          ? 'Publication and original-backup cleanup are blocked: $dependencyFailure Restore the verified original archive when available.'
          : published
          ? 'The published container matches the verified candidate. Finish confirmation and exact cleanup.'
          : candidateValid
          ? 'A verified candidate is available. Finish publication or restore the original.'
          : 'The original can be retained or restored. Recreate edits whose candidate was not durably verified.',
    );
  }

  Future<ArchivePublicationReceipt?> recover(
    ArchivePublicationRecord record,
    ArchiveRecoveryAction action, {
    bool Function()? isCancelled,
    void Function(ArchivePublicationPhase)? onPhase,
  }) async {
    if (_running) {
      throw StateError('An archive publication is already running.');
    }
    _running = true;
    _active = null;
    _publicationCommitted = false;
    _observerWarning = null;
    try {
      _lease = await journal.acquirePublication(record.id);
      if (_lease == null) {
        throw StateError(
          'This archive publication is already owned by another operation.',
        );
      }
      _mutationAuthority = true;
      await journal.initialize();
      final current = journal.records
          .where((value) => value.id == record.id)
          .firstOrNull;
      if (current == null ||
          current.storage != record.storage ||
          current.originalSha256 != record.originalSha256 ||
          current.candidateSha256 != record.candidateSha256 ||
          jsonEncode(current.dependency?.toJson()) !=
              jsonEncode(record.dependency?.toJson()) ||
          jsonEncode(current.directoryDependency?.toJson()) !=
              jsonEncode(record.directoryDependency?.toJson())) {
        throw StateError('The saved archive recovery intent changed.');
      }
      _active = current;
      _check(isCancelled: isCancelled);
      final inspection = await inspect(current, isCancelled: isCancelled);
      if (action == ArchiveRecoveryAction.finishPublication) {
        if (!inspection.canFinish) throw StateError(inspection.message);
        return await _finish(isCancelled: isCancelled, onPhase: onPhase);
      }
      if (!inspection.canRestore) throw StateError(inspection.message);
      if (current.hasDependency) {
        await _retainInstalledCandidateForRestore(
          isCancelled: isCancelled,
          onPhase: onPhase,
        );
      }
      await _restoreVacantOriginal();
      final restored = await _inspect(
        current.original.path!,
        isCancelled: isCancelled,
      );
      if (restored?.hash != current.originalSha256) {
        throw StateError('The original restoration is unconfirmed.');
      }
      final candidate = await _inspect(
        current.candidatePath(backend.paths),
        isCancelled: isCancelled,
      );
      if (candidate != null) {
        await _intent(
          ArchivePublicationPhase.cleaningCandidate,
          onPhase: onPhase,
        );
        _check(isCancelled: isCancelled);
        await _deleteVerified(
          current.candidatePath(backend.paths),
          current.candidateSha256,
          publishedSha256: current.originalSha256,
        );
      }
      // A duplicated backup is never silently discarded by a restore action.
      if (await backend.stat(current.backupPath(backend.paths)) != null) {
        throw StateError('An original backup still requires review.');
      }
      await _intent(ArchivePublicationPhase.discarded, onPhase: onPhase);
      return null;
    } catch (error) {
      await _restoreVacantOriginal();
      if (_active != null) {
        throw ArchivePublicationException(
          '$error. Archive recovery remains recorded.',
          _active!,
        );
      }
      rethrow;
    } finally {
      _lease?.close();
      _lease = null;
      _mutationAuthority = false;
      _running = false;
    }
  }

  Future<void> verifyReceipt(ArchivePublicationReceipt receipt) async {
    await _guardPaths(receipt.record);
    await _verifyDependency(receipt.record);
    final current = await _inspect(receipt.file.path!);
    if (current == null ||
        current.hash != receipt.sha256 ||
        !sameArchiveFile(receipt.file, current.file)) {
      throw StateError(
        'The published archive changed. Source cleanup was refused.',
      );
    }
    await _verifyAccessPolicy(receipt.record, current.file.path!);
  }

  Future<TransferMetadata> _readAccessPolicy(String path) async {
    _check();
    final caps = backend.capabilities;
    if (!caps.permissions &&
        !caps.ownership &&
        !caps.accessControlLists &&
        !caps.extendedAttributes &&
        !caps.windowsAttributes) {
      return const TransferMetadata();
    }
    final result = await backend.readMetadataFields(
      path,
      permissions: caps.permissions,
      ownership: caps.ownership,
      acl: caps.accessControlLists,
      extendedAttributes: caps.extendedAttributes,
      windowsAttributes: caps.windowsAttributes,
    );
    _check();
    if (result.extendedAttributes.values.fold<int>(
              0,
              (sum, bytes) => sum + bytes.length,
            ) >
            1024 * 1024 ||
        (result.acl?.length ?? 0) > 128 * 1024 ||
        caps.permissions && result.mode == null ||
        caps.ownership && (result.owner == null || result.group == null)) {
      throw StateError(
        'The outer archive access policy is unavailable or exceeds its preservation limit.',
      );
    }
    return result;
  }

  Future<void> _applyAccessPolicy(
    String path,
    TransferMetadata attributes,
  ) async {
    _check();
    final caps = backend.capabilities;
    if (caps.permissions ||
        caps.ownership ||
        caps.accessControlLists ||
        caps.extendedAttributes ||
        caps.windowsAttributes) {
      await backend.writeMetadata(path, attributes);
    }
    if (!_sameMetadata(attributes, await _readAccessPolicy(path))) {
      throw StateError(
        'The outer archive access policy could not be preserved.',
      );
    }
  }

  Future<void> _verifyAccessPolicy(
    ArchivePublicationRecord record,
    String path,
  ) async {
    if (record.accessPolicySha256 == null ||
        _accessPolicyHash(await _readAccessPolicy(path)) !=
            record.accessPolicySha256) {
      throw StateError(
        'The original or candidate archive access policy changed.',
      );
    }
  }
}

// Preserve an inactivity deadline independently from total work. A fixed
// five-minute total makes otherwise healthy multi-gigabyte local files fail
// during recovery. Budget one second per MiB plus the original setup allowance.
Duration _verificationDeadline(int bytes) =>
    Duration(seconds: 5 * 60 + (bytes + 1024 * 1024 - 1) ~/ (1024 * 1024));

class _ArchiveCandidateDigest implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

String _accessPolicyHash(TransferMetadata metadata) {
  final keys = metadata.extendedAttributes.keys.toList()..sort();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'mode': metadata.mode,
            'owner': metadata.owner,
            'group': metadata.group,
            'acl': metadata.acl,
            'windowsAttributes': metadata.windowsAttributes,
            'extendedAttributes': {
              for (final key in keys)
                key: sha256
                    .convert(metadata.extendedAttributes[key]!)
                    .toString(),
            },
          }),
        ),
      )
      .toString();
}

bool _hasVersion(FileItem file) => const [
  'versionId',
  'version',
  'revision',
  'rev',
  'etag',
  'eTag',
  'cTag',
].any((key) => file.metadata?[key] != null);

bool _sameMetadata(TransferMetadata expected, TransferMetadata actual) =>
    expected.mode == actual.mode &&
    expected.owner == actual.owner &&
    expected.group == actual.group &&
    expected.acl == actual.acl &&
    expected.windowsAttributes == actual.windowsAttributes &&
    expected.extendedAttributes.length == actual.extendedAttributes.length &&
    expected.extendedAttributes.entries.every(
      (entry) =>
          actual.extendedAttributes[entry.key] != null &&
          listEquals(entry.value, actual.extendedAttributes[entry.key]),
    );

bool sameArchiveFile(FileItem before, FileItem? after) {
  if (after == null ||
      before.path != after.path ||
      before.isFolder != after.isFolder ||
      before.isSymlink == true ||
      after.isSymlink == true ||
      before.size != after.size ||
      before.uuid != after.uuid ||
      !_sameFileInstant(before.updatedAt, after.updatedAt)) {
    return false;
  }
  for (final key in [
    'version',
    'versionId',
    'revision',
    'rev',
    'etag',
    'eTag',
    'cTag',
  ]) {
    if (before.metadata?[key] != after.metadata?[key]) return false;
  }
  return true;
}

// Native stat returns local DateTimes, while the durable journal stores UTC.
// Time-zone representation must not invalidate an otherwise identical native
// file after restart; a different instant (or missing evidence) still refuses.
bool _sameFileInstant(DateTime? before, DateTime? after) => before == null
    ? after == null
    : after != null && before.isAtSameMomentAs(after);

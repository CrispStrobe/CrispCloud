import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/file_item.dart';
import 'archive_integrity_service.dart';
import 'archive_viewer_file.dart';
import 'archive_viewer_service.dart';
import 'archive_volume_backend.dart';
import 'archive_volume_source.dart';
import 'file_operation_service.dart';
import 'read_only_operation_backend.dart';
import 'viewer_spool.dart';

enum ArchiveBatchIntegritySkipReason {
  directory,
  symbolicLink,
  duplicate,
  passwordRequired,
}

enum ArchiveBatchIntegrityStopReason { cancelled, unavailable, reportLimit }

typedef ArchiveBatchPasswordRequest = Future<String?> Function(
  FileItem file, {
  required bool wrongPassword,
});

class ArchiveBatchIntegrityItem {
  const ArchiveBatchIntegrityItem({
    required this.file,
    this.report,
    this.snapshotSha256,
    this.skipReason,
    this.error,
  });

  final FileItem file;
  final ArchiveIntegrityReport? report;
  final String? snapshotSha256;
  final ArchiveBatchIntegritySkipReason? skipReason;
  final String? error;

  bool get fullyChecked =>
      error == null && report?.allRegularMembersChecked == true;
  bool get hasIssues => error != null || report != null && !fullyChecked;
}

class ArchiveBatchIntegrityProgress {
  const ArchiveBatchIntegrityProgress({
    required this.completedArchives,
    required this.totalArchives,
    this.currentFile,
    this.memberProgress,
  });
  final int completedArchives;
  final int totalArchives;
  final FileItem? currentFile;
  final ArchiveIntegrityProgress? memberProgress;
}

class ArchiveBatchIntegrityReport {
  ArchiveBatchIntegrityReport({
    required this.totalArchives,
    required List<ArchiveBatchIntegrityItem> items,
    this.stopReason,
  }) : items = List.unmodifiable(items);

  final int totalArchives;
  final List<ArchiveBatchIntegrityItem> items;
  final ArchiveBatchIntegrityStopReason? stopReason;
  int get checkedCount => items.where((item) => item.fullyChecked).length;
  int get issueCount => items.where((item) => item.hasIssues).length;
  int get skippedCount => items.where((item) => item.skipReason != null).length;
  int get unprocessedCount => totalArchives - items.length;
  bool get allArchivesChecked =>
      stopReason == null && totalArchives > 0 && checkedCount == totalArchives;
}

/// A single read-only check of one captured selection and backend identity.
/// Native files use the same bounded owned snapshot as archive pane browsing.
/// Opening without the pane index lets the integrity report retain namespace
/// failures instead of hiding otherwise readable members. Password retries for
/// one ordinary archive reuse that snapshot; no password is retained in results.
/// Split 7z manifests use the shared captured-volume opener and its fingerprint.
class ArchiveBatchIntegrityRun {
  ArchiveBatchIntegrityRun({
    required FileOperationBackend source,
    required List<FileItem> files,
    this.spoolToDisk = !kIsWeb,
    this.maxInputBytes = kArchiveStreamingLimit,
    this.maxReportEntries = 200000,
  }) : _source = source,
       _identity = source.identity,
       _storageId = source.persistentStorageId,
       files = List.unmodifiable(files.map(_captureFile)) {
    if (files.length > 5000) {
      throw const ArchiveViewException(
        'Select at most 5,000 archives per check.',
      );
    }
    if (maxInputBytes <= 0 ||
        maxInputBytes > kArchiveStreamingLimit ||
        maxReportEntries <= 0 ||
        maxReportEntries > 200000) {
      throw ArgumentError('Invalid batch archive check limits.');
    }
  }

  final FileOperationBackend _source;
  final Object _identity;
  final String? _storageId;
  final List<FileItem> files;
  final bool spoolToDisk;
  final int maxInputBytes;
  final int maxReportEntries;
  bool _started = false;

  bool get _available =>
      _source.isCurrent &&
      _source.identity == _identity &&
      _source.persistentStorageId == _storageId;

  Future<ArchiveBatchIntegrityReport> check({
    bool Function()? isCancelled,
    void Function(ArchiveBatchIntegrityProgress progress)? onProgress,
    ArchiveBatchPasswordRequest? requestPassword,
  }) async {
    if (_started) throw StateError('This captured archive check already ran.');
    _started = true;
    final items = <ArchiveBatchIntegrityItem>[];
    final seen = <String>{};
    var retainedEntries = 0, retainedPathBytes = 0;
    ArchiveBatchIntegrityStopReason? stopReason;
    final source = ReadOnlyOperationBackend(
      _source,
      isAvailable: () => _available,
    );
    final guard = _BatchGuard(
      isCancelled: () => isCancelled?.call() ?? false,
      isCurrent: () => _available,
    );
    void progress([FileItem? file, ArchiveIntegrityProgress? member]) =>
        onProgress?.call(
          ArchiveBatchIntegrityProgress(
            completedArchives: items.length,
            totalArchives: files.length,
            currentFile: file,
            memberProgress: member,
          ),
        );
    ArchiveBatchIntegrityStopReason? stopped() {
      if (isCancelled?.call() ?? false) {
        return ArchiveBatchIntegrityStopReason.cancelled;
      }
      if (!_available) return ArchiveBatchIntegrityStopReason.unavailable;
      return null;
    }

    for (final file in files) {
      await Future<void>.delayed(Duration.zero);
      stopReason = stopped();
      if (stopReason != null) break;
      progress(file);
      stopReason = stopped();
      if (stopReason != null) break;
      final reason = file.isFolder
          ? ArchiveBatchIntegritySkipReason.directory
          : file.isSymlink == true
          ? ArchiveBatchIntegritySkipReason.symbolicLink
          : file.path != null && !seen.add(source.pathKey(file.path!))
          ? ArchiveBatchIntegritySkipReason.duplicate
          : null;
      if (reason != null) {
        items.add(ArchiveBatchIntegrityItem(file: file, skipReason: reason));
        progress();
        continue;
      }
      _BatchSnapshot? snapshot;
      ViewerArchive? archive;
      String? fingerprint, password;
      ArchiveIntegrityReport? memberReport;
      ArchiveBatchIntegritySkipReason? skip;
      String? errorText;
      var attempts = 0;
      var declined = false;
      Future<bool> ask({required bool wrong}) async {
        if (requestPassword == null || declined || attempts >= 3) return false;
        guard.check();
        password = await requestPassword(file, wrongPassword: wrong);
        guard.check();
        if (password == null) {
          declined = true;
          return false;
        }
        attempts++;
        return true;
      }

      try {
        if (file.path == null) {
          throw const ArchiveViewException(
            'The selected archive has no source path.',
          );
        }
        if (file.storageId != null && file.storageId != _storageId) {
          throw const ArchiveViewException(
            'The selected archive belongs to another storage account.',
          );
        }
        final current = await guard.wait(() => source.stat(file.path!));
        if (!_matchesSelection(file, current)) throw _changed();
        final captured = _captureFile(current!);
        final split = sevenZipVolumeBaseName(file.name) != null;
        if (!split) {
          snapshot = await _BatchSnapshot.capture(
            source,
            captured,
            spoolToDisk: spoolToDisk && !kIsWeb,
            maxBytes: maxInputBytes,
            guard: guard,
          );
          fingerprint = snapshot.fingerprint;
        }
        while (true) {
          guard.check();
          try {
            if (split) {
              final opened = await openSevenZipVolumeArchive(
                _source,
                captured,
                password: password,
                maxInputBytes: maxInputBytes,
                spoolToDisk: spoolToDisk,
                isCancelled: isCancelled,
                onSnapshotCaptured: (capturedFingerprint) {
                  guard.check();
                  if (fingerprint != null &&
                      fingerprint != capturedFingerprint) {
                    throw _changed();
                  }
                  fingerprint = capturedFingerprint;
                },
              );
              archive = opened.archive;
              // This audited opener already grants no write access. Passing
              // the original backend preserves its native file identity checks.
              // The callback also sees captures whose encrypted header fails.
            } else {
              archive = await snapshot!.open(password: password, guard: guard);
            }
          } on ArchivePasswordRequiredException catch (error) {
            if (await ask(wrong: error.wrongPassword || attempts > 0)) continue;
            if (attempts == 0) {
              skip = ArchiveBatchIntegritySkipReason.passwordRequired;
            } else {
              errorText = 'The archive password was rejected; contents were not checked.';
            }
            break;
          }
          guard.check();
          if (password == null &&
              archive.members.any((member) => member.isEncrypted) &&
              await ask(wrong: false)) {
            await archive.close();
            archive = null;
            continue;
          }
          final pathBytes = archive.members.fold<int>(
            0,
            (sum, member) => sum + utf8.encode(member.name).length,
          );
          if (archive.members.length > maxReportEntries - retainedEntries ||
              pathBytes > 16 * 1024 * 1024 - retainedPathBytes) {
            throw const _ReportLimit();
          }
          memberReport = await checkArchiveIntegrity(
            archive,
            maxEntries: maxReportEntries,
            isCancelled: isCancelled,
            isCurrent: () => _available,
            onProgress: (member) => progress(file, member),
          );
          final failedProtected = memberReport.entries.any(
            (entry) =>
                entry.member.isEncrypted &&
                entry.status == ArchiveIntegrityStatus.failed,
          );
          if (failedProtected && stopped() == null && await ask(wrong: true)) {
            await archive.close();
            archive = null;
            continue;
          }
          retainedEntries += memberReport.entries.length;
          retainedPathBytes += pathBytes;
          break;
        }
      } on _ReportLimit {
        errorText =
            'Batch report limit reached ($maxReportEntries members or 16 MiB of paths).';
        stopReason = ArchiveBatchIntegrityStopReason.reportLimit;
      } catch (error) {
        stopReason = stopped();
        if (stopReason == null) errorText = _safeError(error, password);
      } finally {
        password = null;
        try {
          await archive?.close();
        } catch (_) {
          errorText ??= 'The archive reader could not be closed.';
        }
        try {
          await snapshot?.close();
        } catch (_) {
          errorText ??= 'The private archive snapshot could not be removed.';
        }
      }
      stopReason ??= stopped();
      if (stopReason == ArchiveBatchIntegrityStopReason.cancelled ||
          stopReason == ArchiveBatchIntegrityStopReason.unavailable) {
        // A snapshot interrupted before a report exists remains unprocessed.
        if (memberReport == null) break;
      }
      items.add(
        ArchiveBatchIntegrityItem(
          file: file,
          report: memberReport,
          snapshotSha256: fingerprint,
          skipReason: skip,
          error: errorText,
        ),
      );
      progress();
      if (stopReason != null) break;
    }
    stopReason ??= stopped();
    return ArchiveBatchIntegrityReport(
      totalArchives: files.length,
      items: items,
      stopReason: stopReason,
    );
  }
}

const _revisionKeys = [
  'etag',
  'eTag',
  'version',
  'versionId',
  'revision',
  'rev',
  'cTag',
];

FileItem _captureFile(FileItem file) => FileItem(
  name: file.name,
  path: file.path,
  uuid: file.uuid,
  storageId: file.storageId,
  isFolder: file.isFolder,
  size: file.size,
  updatedAt: file.updatedAt,
  isSymlink: file.isSymlink,
  symlinkTarget: file.symlinkTarget,
  metadata: Map.unmodifiable({
    for (final key in _revisionKeys)
      if (file.metadata?.containsKey(key) ?? false)
        key: _captureRevision(file.metadata![key]),
  }),
);

Object? _captureRevision(Object? value) {
  if (value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime) {
    return value;
  }
  throw const ArchiveViewException(
    'The archive revision metadata cannot be captured.',
  );
}

bool _matchesSelection(FileItem before, FileItem? after) =>
    after != null &&
    !after.isFolder &&
    after.isSymlink != true &&
    (before.uuid == null || before.uuid == after.uuid) &&
    (before.storageId == null ||
        after.storageId == null ||
        before.storageId == after.storageId) &&
    (before.size == null || before.size == after.size) &&
    (before.updatedAt == null ||
        after.updatedAt != null &&
            before.updatedAt!.isAtSameMomentAs(after.updatedAt!)) &&
    _revisionKeys.every(
      (key) =>
          !before.metadata!.containsKey(key) ||
          before.metadata?[key] == after.metadata?[key],
    );

bool _sameSnapshot(FileItem before, FileItem? after) =>
    _matchesSelection(before, after) &&
    before.uuid == after!.uuid &&
    before.storageId == after.storageId &&
    before.size == after.size &&
    ((before.updatedAt == null && after.updatedAt == null) ||
        before.updatedAt != null &&
            after.updatedAt != null &&
            before.updatedAt!.isAtSameMomentAs(after.updatedAt!)) &&
    _revisionKeys.every((key) => before.metadata?[key] == after.metadata?[key]);

ArchiveViewException _changed() => const ArchiveViewException(
  'The selected archive changed or was replaced. Select it again.',
);
String _safeError(Object error, String? password) {
  var message = error.toString();
  if (password != null && password.isNotEmpty) {
    message = message.replaceAll(password, '[redacted]');
  }
  return message.length > 4096 ? '${message.substring(0, 4096)}…' : message;
}

class _ReportLimit implements Exception {
  const _ReportLimit();
}

class _BatchSnapshot {
  _BatchSnapshot(this.name, this.fingerprint, this._bytes, this._spool);
  final String name, fingerprint;
  final Uint8List? _bytes;
  final ViewerSpool? _spool;

  static Future<_BatchSnapshot> capture(
    FileOperationBackend source,
    FileItem file, {
    required bool spoolToDisk,
    required int maxBytes,
    required _BatchGuard guard,
  }) async {
    final limit = spoolToDisk || maxBytes < 256 * 1024 * 1024
        ? maxBytes
        : 256 * 1024 * 1024;
    if ((file.size ?? 0) > limit) {
      throw ArchiveViewException(
        'Archive input exceeds the ${limit ~/ (1024 * 1024)} MiB snapshot limit.',
      );
    }
    ViewerSpool? spool;
    Uint8List? bytes;
    final sink = _DigestSink();
    final hash = sha256.startChunkedConversion(sink);
    final input = _HashingBackend(source, hash, guard);
    try {
      if (spoolToDisk) {
        spool = await createViewerSpool(
          input,
          file,
          maxBytes: limit,
          isCancelled: guard.isCancelled,
        );
      } else {
        final builder = BytesBuilder(copy: false);
        final stream = StreamIterator(input.readFile(file));
        try {
          while (await guard.wait(stream.moveNext)) {
            final chunk = stream.current;
            if (chunk.length > limit - builder.length) {
              throw const ArchiveViewException(
                'Archive input exceeds the browser snapshot limit.',
              );
            }
            builder.add(Uint8List.fromList(chunk));
          }
        } finally {
          // A provider that never acknowledges cancellation cannot keep this
          // read-only check open. Late cancellation errors are still observed.
          unawaited(
            stream.cancel().then<void>(
              (_) {},
              onError: (Object _, StackTrace __) {},
            ),
          );
        }
        bytes = builder.takeBytes();
        if (file.size != null && bytes.length != file.size) throw _changed();
      }
      guard.check();
      if (!_sameSnapshot(
        file,
        await guard.wait(() => source.stat(file.path!)),
      )) {
        throw _changed();
      }
      hash.close();
      return _BatchSnapshot(file.name, sink.value!.toString(), bytes, spool);
    } catch (_) {
      await spool?.close();
      rethrow;
    } finally {
      if (sink.value == null) hash.close();
    }
  }

  Future<ViewerArchive> open({
    required String? password,
    required _BatchGuard guard,
  }) async {
    guard.check();
    final archive = _spool != null
        ? await openViewerArchiveFile(
            _spool.path,
            name: name,
            password: password,
            streaming: true,
            isCancelled: guard.isCancelled,
          )
        : await openViewerArchive(_bytes!, name: name, password: password);
    try {
      guard.check();
      return archive;
    } catch (_) {
      await archive.close();
      rethrow;
    }
  }

  Future<void> close() async => _spool?.close();
}

class _HashingBackend extends ReadOnlyOperationBackend {
  _HashingBackend(super.source, this.hash, this.guard)
    : super(isAvailable: guard.isCurrent);
  final ByteConversionSink hash;
  final _BatchGuard guard;
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    await for (final chunk in super.readFile(file)) {
      guard.check();
      if (chunk is! Uint8List && chunk.any((byte) => byte < 0 || byte > 255)) {
        throw const ArchiveViewException(
          'The archive source returned invalid bytes.',
        );
      }
      hash.add(chunk);
      yield chunk;
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _BatchGuard {
  _BatchGuard({required this.isCancelled, required this.isCurrent});
  final bool Function() isCancelled, isCurrent;
  void check() {
    if (isCancelled()) {
      throw const ArchiveViewException('Archive check cancelled.');
    }
    if (!isCurrent()) {
      throw const ArchiveViewException(
        'The archive source is no longer available.',
      );
    }
  }

  Future<T> wait<T>(Future<T> Function() operation) async {
    check();
    final result = Completer<T>();
    final clock = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (result.isCompleted) return;
      try {
        check();
        if (clock.elapsed >= const Duration(minutes: 2)) {
          throw const ArchiveViewException(
            'The archive source stopped responding.',
          );
        }
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    unawaited(
      Future<T>.sync(operation).then<void>(
        (value) {
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    try {
      final value = await result.future;
      check();
      return value;
    } finally {
      timer.cancel();
      clock.stop();
    }
  }
}

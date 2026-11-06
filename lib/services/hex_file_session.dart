import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:madedit2_hex/hex_document.dart';
import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'hex_file_source.dart';
import 'transfer_spool.dart';

const kHexNativeInputLimit = 8 * 1024 * 1024 * 1024;
const kHexWebInputLimit = 32 * 1024 * 1024;

class HexSaveConflict implements Exception {
  const HexSaveConflict(this.message);
  final String message;
  @override
  String toString() => message;
}
class HexOperationCancelled implements Exception {
  const HexOperationCancelled();
  @override
  String toString() => 'The operation was cancelled. Unsaved edits are retained.';
}

/// Captures the original backend/account/path ONCE. Editing reads an owned
/// immutable copy, not a mutable local file or a stale preview cache.
///
/// Native input is spooled to disk, browser input has an explicit 32 MiB cap.
/// Saves use the existing staged transfer backend and verify both the staged
/// content and the original baseline immediately before replacement. Providers
/// without conditional writes still have a check/commit race; this is NOT a
/// claim of atomic compare-and-swap against external writers.
class HexFileSession {
  HexFileSession._(this.backend, this.path, this.source, this._spool,
      this._baseline, this._digest, this.maxBytes);
  final FileOperationBackend backend;
  final String path;
  final HexByteSource source;
  final TransferSpool? _spool;
  final int maxBytes;
  FileItem _baseline;
  String _digest;
  bool _closed = false;
  Completer<void>? _writeDone;
  bool get canSave => backend.isCurrent && backend.supportsStagedVerification;

  static Future<HexFileSession> open({
    required FileOperationBackend backend,
    required FileItem file,
    int? maxBytes,
    bool Function()? cancelled,
    void Function(int done, int? total)? onProgress,
  }) async {
    final limit = maxBytes ?? (kIsWeb ? kHexWebInputLimit : kHexNativeInputLimit);
    if (limit < 1 || (kIsWeb && limit > kHexWebInputLimit)) throw ArgumentError('Invalid hex input limit.');
    void check() {
      if (!backend.isCurrent) throw const HexSaveConflict('The original storage is no longer connected.');
      if (cancelled?.call() ?? false) throw const HexOperationCancelled();
    }
    check();
    final path = file.path;
    if (path == null || path.isEmpty || file.isFolder || file.isSymlink == true) {
      throw const HexSaveConflict('Only a verified regular file can be edited.');
    }
    final before = await backend.stat(path);
    if (before == null || before.isFolder || before.isSymlink == true ||
        (file.uuid != null && before.uuid != file.uuid)) {
      throw const HexSaveConflict('The original file is missing or has been replaced.');
    }
    if ((before.size ?? 0) > limit) throw StateError('File exceeds the ${limit ~/ (1024 * 1024)} MiB editing limit.');
    var received = 0;
    final collector = _DigestSink();
    final digest = sha256.startChunkedConversion(collector);
    Stream<List<int>> input() async* {
      try {
        await for (final chunk in backend.readFile(before.copyWith(path: path))) {
          check();
          received += chunk.length;
          if (received > limit) throw StateError('File exceeds the editing size limit.');
          digest.add(chunk);
          onProgress?.call(received, before.size);
          yield chunk;
        }
        if (before.size != null && received != before.size) throw const HexSaveConflict('File length changed during loading.');
      } finally { digest.close(); }
    }
    TransferSpool? spool;
    HexByteSource? source;
    try {
      if (kIsWeb) {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in input()) { bytes.add(chunk); }
        source = MemoryHexByteSource(bytes.takeBytes());
      } else {
        spool = await createTransferSpool(input(), expectedLength: before.size,
            maxBytes: limit, checkpoint: () async => check());
        source = await openHexFileSource(spool.localPath!);
      }
      check();
      final after = await backend.stat(path);
      if (!_same(before, after)) throw const HexSaveConflict('The file changed while preparing its editing snapshot.');
      final session = HexFileSession._(backend, path, source, spool,
          after!, collector.value!.toString(), limit);
      // A timestamp alone is not a content version. This second, bounded read
      // also catches a same-size external rewrite while the first was copied.
      await session._verifyOriginal(cancelled);
      return session;
    } catch (_) {
      if (source != null) await closeHexFileSource(source);
      await spool?.dispose();
      rethrow;
    }
  }

  void _check([bool Function()? cancelled]) {
    if (_closed) throw StateError('The hex session is closed.');
    if (!backend.isCurrent) throw const HexSaveConflict('The original account or storage changed. Reopen it before saving.');
    if (cancelled?.call() ?? false) throw const HexOperationCancelled();
  }
  Future<void> _verifyOriginal(bool Function()? cancelled) async {
    _check(cancelled);
    final before = await backend.stat(path);
    if (!_same(_baseline, before)) throw const HexSaveConflict('The original file changed outside this editor. Save a separate copy.');
    final hash = await _hashFile(before!.copyWith(path: path), cancelled);
    _check(cancelled);
    final after = await backend.stat(path);
    if (hash != _digest || !_same(before, after)) {
      throw const HexSaveConflict('The original file changed outside this editor. Save a separate copy.');
    }
  }
  Future<String> _hashFile(FileItem file, bool Function()? cancelled) async {
    var length = 0;
    Stream<List<int>> bounded() async* {
      await for (final chunk in backend.readFile(file)) {
        _check(cancelled);
        length += chunk.length;
        if (length > maxBytes || (file.size != null && length > file.size!)) {
          throw const HexSaveConflict('File length changed during verification.');
        }
        yield chunk;
      }
      if (file.size != null && length != file.size) throw const HexSaveConflict('File ended before its advertised length.');
    }
    return (await sha256.bind(bounded()).first).toString();
  }

  Future<void> save(HexSnapshot snapshot, {
    bool Function()? cancelled,
    void Function(int done, int total)? onProgress,
  }) => _write(snapshot, path, replace: true, cancelled: cancelled, onProgress: onProgress);

  /// Copy/export never acknowledges the original document's saved state.
  Future<String> saveCopy(HexSnapshot snapshot, String fileName, {
    bool Function()? cancelled,
  }) async {
    if (fileName.isEmpty || fileName == '.' || fileName == '..' ||
        fileName.contains('/') || fileName.contains(r'\') || fileName.contains('\u0000')) {
      throw ArgumentError('Enter a single file name.');
    }
    final target = backend.paths.join(backend.paths.dirname(path), fileName);
    if (backend.samePath(path, target)) throw ArgumentError('Use a different name for a copy.');
    await _write(snapshot, target, replace: false, cancelled: cancelled);
    return target;
  }

  Future<void> _write(HexSnapshot snapshot, String target, {
    required bool replace, bool Function()? cancelled,
    void Function(int done, int total)? onProgress,
  }) async {
    _check(cancelled);
    if (_writeDone != null) throw StateError('A save is already running.');
    if (!backend.supportsStagedVerification) {
      throw UnsupportedError('This storage cannot verify a staged save safely. Export or download the original and edit a local copy.');
    }
    if (snapshot.length > maxBytes) throw StateError('Edited file exceeds the ${maxBytes ~/ (1024 * 1024)} MiB save limit.');
    final done = _writeDone = Completer<void>();
    var commitStarted = false;
    bool isCancelled() => !commitStarted && (cancelled?.call() ?? false);
    try {
      if (replace) await _verifyOriginal(isCancelled);
      else if (await backend.stat(target) != null) throw const HexSaveConflict('A file already exists with that copy name.');
      final collector = _DigestSink();
      final digest = sha256.startChunkedConversion(collector);
      var sent = 0;
      Stream<List<int>> output() async* {
        try {
          await for (final chunk in snapshot.chunks()) {
            _check(isCancelled);
            sent += chunk.length; digest.add(chunk);
            onProgress?.call(sent, snapshot.length);
            yield chunk;
          }
        } finally { digest.close(); }
      }
      await backend.writePreparedFile(target, output(), snapshot.length,
        replace: replace,
        verifyStaged: (staged) async {
          _check(isCancelled);
          if (sent != snapshot.length || collector.value == null ||
              await _hashFile(staged, isCancelled) != collector.value.toString()) {
            throw StateError('Staged bytes do not match the editor snapshot. The original was not replaced.');
          }
          if (replace) await _verifyOriginal(isCancelled);
        },
        checkpoint: (state) async {
          final phase = state['phase'];
          if (phase == 'backingUp' || phase == 'committing') {
            _check(isCancelled);
            commitStarted = true; // Never cancel in the middle of replacement.
          } else if (phase != 'committed') { _check(isCancelled); }
        },
      );
      if (replace) {
        _digest = collector.value!.toString();
        // An acknowledged write stays successful if refreshing metadata fails.
        // Keeping the old stamp makes a later save conservative, not destructive.
        try {
          final current = await backend.stat(path);
          if (current != null && !current.isFolder) _baseline = current;
        } catch (_) { /* verified commit succeeded */ }
      }
    } finally { _writeDone = null; done.complete(); }
  }
  Future<void> close() async {
    await _writeDone?.future;
    if (_closed) return;
    _closed = true;
    try { await closeHexFileSource(source); }
    finally { await _spool?.dispose(); }
  }
}

bool _same(FileItem a, FileItem? b) => b != null && !b.isFolder && b.isSymlink != true &&
    a.uuid == b.uuid && a.size == b.size && a.updatedAt == b.updatedAt &&
    const ['etag', 'eTag', 'version', 'versionId', 'revision', 'rev', 'downloadSize']
        .every((key) => a.metadata?[key] == b.metadata?[key]);
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

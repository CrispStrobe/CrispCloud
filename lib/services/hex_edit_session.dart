import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:madedit2_hex/madedit2_hex.dart';

import '../models/file_item.dart';
import 'captured_file_target.dart';
import 'file_bytes_loader.dart';
import 'file_operation_service.dart';
import 'save_coordinator.dart';
import 'viewer_spool.dart';

/// Browser editing is deliberately bounded; native sessions use an owned disk
/// snapshot and stream both verification and writes. The original snapshot is
/// never replaced after a save, so undo still refers to the original bytes.
const int hexBrowserEditingLimit = 64 * 1024 * 1024;

/// A captured storage session for one binary document. A provider's staged
/// write contract supplies rollback/recovery; content hashes add the editor's
/// optimistic conflict check. The generic providers do not offer an atomic
/// compare-and-swap, so a change after the final check remains a provider race.
class HexEditSession extends ChangeNotifier {
  HexEditSession._({
    required this.backend,
    required this.file,
    required this.document,
    required Digest baselineDigest,
    required FileItem baseline,
    required this.inMemory,
  }) : _baselineDigest = baselineDigest,
       _baseline = baseline,
       _identity = backend.identity {
    _saves.addListener(_onSaveChanged);
  }

  final FileOperationBackend backend;
  final FileItem file;
  final HexDocument document;
  final bool inMemory;
  final Object _identity;
  final SaveCoordinator<HexSnapshot> _saves = SaveCoordinator<HexSnapshot>();
  Digest _baselineDigest;
  FileItem? _baseline;
  int _observedRevision = 0;
  bool _closed = false;
  bool _closeRequested = false;
  Future<void>? _closing;

  String get path => file.path!;
  bool get isSaving => _saves.isSaving;
  bool get isDirty => document.isDirty;
  bool get isCurrent =>
      !_closed && backend.isCurrent && backend.identity == _identity;
  Object? get lastError => _saves.lastError;
  FileItem? get savedFile => _baseline;
  Future<void> get idle => _saves.idle;

  /// Captures fresh bytes, bypassing every viewer/preview cache. Even local
  /// files are copied to a private spool: overwriting the host path must never
  /// change the byte source used by the piece table or its undo snapshots.
  static Future<HexEditSession> open({
    required FileOperationBackend backend,
    required FileItem file,
    bool inMemory = kIsWeb,
    bool Function()? isCancelled,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (file.path == null || file.isFolder || file.isSymlink == true) {
      throw const FileTargetConflict('Open a regular file before editing.');
    }
    final identity = backend.identity;
    void check() {
      if (!backend.isCurrent || backend.identity != identity) {
        throw const FileTargetConflict(
          'The original storage is disconnected or changed. Reopen the file before saving.',
        );
      }
      if (isCancelled?.call() ?? false) {
        throw StateError('Hex editor preparation cancelled.');
      }
    }

    check();
    final before = await backend.stat(file.path!);
    if (before == null ||
        before.isFolder ||
        before.isSymlink == true ||
        (file.uuid != null && before.uuid != file.uuid)) {
      throw const FileTargetConflict(
        'The original file has changed or is no longer available. Reopen it.',
      );
    }
    _SessionByteSource? source;
    ViewerSpool? spool;
    try {
      if (inMemory) {
        final data = await readFileBytesBounded(
          backend,
          before,
          maxBytes: hexBrowserEditingLimit,
          isCancelled: isCancelled,
        );
        source = _SessionByteSource(ViewBytesSource.memory(data));
        onProgress?.call(data.length, data.length);
      } else {
        spool = await createViewerSpool(
          backend,
          before,
          // The disk, rather than a full-file byte array, bounds native use.
          maxBytes: 0x1fffffffffffff,
          isCancelled: isCancelled,
          onProgress: onProgress,
        );
        source = _SessionByteSource(
          ViewBytesSource.file(spool.path),
          spool: spool,
        );
      }
      await source.open();
      check();
      final after = await backend.stat(file.path!);
      if (!_sameMetadata(before, after) ||
          (before.size != null && before.size != source.length)) {
        throw const FileTargetConflict(
          'The file changed while preparing the editor. Reopen it.',
        );
      }
      final digest = await sha256.bind(source.stream()).first;
      check();
      return HexEditSession._(
        backend: backend,
        file: file.copyWith(path: before.path ?? file.path),
        document: HexDocument(source),
        baselineDigest: digest,
        baseline: after!,
        inMemory: inMemory,
      );
    } catch (_) {
      if (source != null) {
        await source.close();
      } else {
        await spool?.close();
      }
      rethrow;
    }
  }

  /// Call after controller notifications; selection changes do not create a
  /// document revision. Also called by save, so direct engine edits are safe.
  void documentChanged() {
    if (_closed) return;
    if (_observedRevision == document.revision) return;
    _observedRevision = document.revision;
    _saves.markChanged();
    notifyListeners();
  }

  Future<EditorSaveResult> save() {
    if (_closeRequested) throw StateError('The hex edit session is closing.');
    _check();
    documentChanged();
    return _saves.save(
      snapshot: () {
        _check();
        documentChanged();
        return SaveSnapshot<HexSnapshot>(
          revision: _saves.revision,
          value: document.snapshot(),
        );
      },
      write: (captured) async {
        final snapshot = captured.value;
        try {
          await _write(snapshot);
          // Only the exact captured revision becomes saved. A subsequent edit
          // or queued save keeps its own snapshot and dirty state.
          document.markSaved(snapshot.revision);
        } finally {
          await snapshot.close();
        }
      },
    );
  }

  void _check() {
    if (!isCurrent) {
      throw const FileTargetConflict(
        'The original storage is disconnected or changed. Reopen the file before saving.',
      );
    }
  }

  Future<FileItem> _checkOriginal() async {
    _check();
    final before = await backend.stat(path);
    if (before == null ||
        before.isFolder ||
        before.isSymlink == true ||
        (_baseline != null && !_sameMetadata(_baseline!, before))) {
      throw const FileTargetConflict(
        'The file changed outside this editor. Your edits are kept; reopen the source before overwriting it.',
      );
    }
    final digest = await sha256.bind(_guarded(backend.readFile(before))).first;
    final after = await backend.stat(path);
    _check();
    if (!_sameMetadata(before, after) || digest != _baselineDigest) {
      throw const FileTargetConflict(
        'The file changed outside this editor. Your edits are kept; reopen the source before overwriting it.',
      );
    }
    return after!;
  }

  Stream<List<int>> _guarded(Stream<List<int>> stream) async* {
    _check();
    await for (final chunk in stream) {
      _check();
      yield chunk;
    }
    _check();
  }

  Future<void> _write(HexSnapshot snapshot) async {
    _check();
    if (inMemory && snapshot.length > hexBrowserEditingLimit) {
      throw const FileTargetConflict(
        'Browser hex editing is limited to 64 MiB. Open this file in the desktop app.',
      );
    }
    if (!backend.supportsStagedVerification) {
      throw const FileTargetConflict(
        'This storage cannot safely replace this file. Open it from a writable folder in the desktop app.',
      );
    }
    await _checkOriginal();
    final outputDigest = await sha256.bind(snapshot.stream()).first;
    _check();
    await backend.writePreparedFile(
      path,
      _guarded(snapshot.stream()),
      snapshot.length,
      replace: true,
      verifyStaged: (staged) async {
        _check();
        final stagedDigest = await sha256
            .bind(_guarded(backend.readFile(staged)))
            .first;
        if (stagedDigest != outputDigest) {
          throw const FileTargetConflict(
            'The staged file could not be verified. The original was not replaced.',
          );
        }
        // Recheck after a potentially long upload, immediately before the
        // backend commits. This also detects same-size/same-timestamp edits.
        await _checkOriginal();
      },
    );
    // A committed write must not become a reported failure because a later
    // metadata refresh failed. Future saves still compare the saved digest.
    _baselineDigest = outputDigest;
    _baseline = null;
    try {
      final current = await backend.stat(path);
      if (current != null && !current.isFolder && current.isSymlink != true) {
        _baseline = current;
      }
    } catch (_) {
      // Keep the exact saved content as the baseline for the next attempt.
    }
  }

  void _onSaveChanged() {
    if (!_closed) notifyListeners();
  }

  /// Wait for writes before releasing the stable byte source and temporary
  /// directory. Calling close twice shares the same cleanup operation.
  Future<void> close() {
    _closeRequested = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    await _saves.idle;
    if (_closed) return;
    _closed = true;
    _saves.removeListener(_onSaveChanged);
    _saves.dispose();
    await document.close();
    super.dispose();
  }
}

bool _sameMetadata(FileItem before, FileItem? after) =>
    after != null &&
    !after.isFolder &&
    after.isSymlink != true &&
    before.uuid == after.uuid &&
    before.size == after.size &&
    before.updatedAt == after.updatedAt &&
    !const [
      'etag',
      'versionId',
      'revision',
    ].any((key) => before.metadata?[key] != after.metadata?[key]);

/// Adapts the existing file viewer's bounded cached reads to the reusable
/// engine, and owns the lifetime of the immutable temporary source.
class _SessionByteSource implements HexByteSource {
  _SessionByteSource(this._source, {ViewerSpool? spool}) : _spool = spool;
  final ViewBytesSource _source;
  final ViewerSpool? _spool;
  bool _closed = false;
  int _readsSinceYield = 0;
  Future<void> open() => _source.open();
  @override
  int get length => _source.size;
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw StateError('The hex byte source is closed.');
    // Give input/progress events a turn during long streamed hashes and saves.
    if (++_readsSinceYield >= 16) {
      _readsSinceYield = 0;
      await Future<void>.delayed(Duration.zero);
      if (_closed) throw StateError('The hex byte source is closed.');
    }
    RangeError.checkValidRange(offset, offset + length, this.length);
    final output = Uint8List(length);
    for (var copied = 0; copied < length;) {
      final count = (length - copied).clamp(0, 64 * 1024);
      final chunk = _source.readSync(offset + copied, count);
      if (chunk.length != count)
        throw StateError('The immutable source became truncated.');
      output.setRange(copied, copied + count, chunk);
      copied += count;
    }
    return output;
  }

  Stream<List<int>> stream() async* {
    for (var offset = 0; offset < length;) {
      final count = (length - offset).clamp(0, 64 * 1024);
      yield await read(offset, count);
      offset += count;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _source.dispose();
    await _spool?.close();
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'hex_byte_source.dart';
import 'piece_tree.dart';

/// A byte-only editable document using the MIT MadEdit2 piece-tree design.
///
/// All mutations are synchronous and perform no source reads. Existing bytes
/// remain range references to [HexByteSource]; inserted bytes are owned,
/// immutable chunks. Reads capture their range before awaiting I/O, so edits
/// during a read cannot mix different document revisions.
///
/// A snapshot is a stable view suitable for saving or searching while editing
/// continues. Close each snapshot when finished. The source itself must remain
/// immutable for the document's lifetime; save to a different target or replace
/// this document after committing a saved snapshot.
class HexDocument {
  HexDocument(
    HexByteSource source, {
    this.maxUndoSteps = 1000,
    this.maxUndoBytes = 64 << 20,
    this.maxUndoPieces = 100000,
  }) : _source = _SourceLifetime(source),
       _tree = PieceTree<_ByteBuffer>.original(
         const _ByteBuffer.original(),
         source.length,
       ) {
    RangeError.checkNotNegative(maxUndoSteps, 'maxUndoSteps');
    RangeError.checkNotNegative(maxUndoBytes, 'maxUndoBytes');
    RangeError.checkNotNegative(maxUndoPieces, 'maxUndoPieces');
  }

  /// Maximum combined undo/redo steps; zero disables history.
  final int maxUndoSteps;

  /// Maximum distinct inserted-byte storage retained by undo/redo.
  ///
  /// Original-source ranges do not consume this byte budget. The separate
  /// [maxUndoPieces] bound limits descriptor storage. Current content and live
  /// snapshots may retain additional bytes that cannot be discarded.
  final int maxUndoBytes;
  final int maxUndoPieces;

  final _SourceLifetime _source;
  final PieceTree<_ByteBuffer> _tree;
  final List<_Edit> _undo = [];
  final List<_Edit> _redo = [];
  final Map<_ByteBuffer, int> _historyBuffers = {};
  final Map<int, _SnapshotState> _snapshotStates = {};
  int _historyBytes = 0;
  int _historyPieces = 0;
  int _revision = 0;
  int _state = 0;
  int _nextState = 1;
  int _savedState = 0;
  bool _closed = false;
  Future<void>? _closing;

  int get length => _tree.length;

  /// Monotonic change number, including undo and redo.
  int get revision => _revision;
  bool get canUndo => !_closed && _undo.isNotEmpty;
  bool get canRedo => !_closed && _redo.isNotEmpty;
  bool get isDirty => _state != _savedState;
  bool get isClosed => _closed;
  int get undoSteps => _undo.length;
  int get redoSteps => _redo.length;
  int get historyBytes => _historyBytes;
  int get historyPieces => _historyPieces;

  /// Replace exactly [deleteCount] bytes; all supplied values must be 0–255.
  ///
  /// Invalid ranges/bytes throw before the document changes. Unlike a read,
  /// a mutation never silently clips at EOF. A zero-length replacement with
  /// no inserted bytes leaves the revision and history unchanged.
  void replace(int offset, int deleteCount, List<int> bytes) {
    _checkOpen();
    _checkEditRange(offset, deleteCount);
    if (deleteCount == 0 && bytes.isEmpty) return;
    final owned = _copyBytes(bytes);
    final inserted = owned.isEmpty
        ? <PieceRef<_ByteBuffer>>[]
        : [PieceRef<_ByteBuffer>(_ByteBuffer.memory(owned), 0, owned.length)];
    final before = _state;
    final removed = _tree.replace(offset, deleteCount, inserted);
    _state = _nextState++;
    _revision++;
    _clearEntries(_redo);
    _record(
      _Edit(
        offset,
        List.unmodifiable(removed),
        List.unmodifiable(inserted),
        before,
        _state,
      ),
    );
  }

  void insert(int offset, List<int> bytes) => replace(offset, 0, bytes);

  void delete(int offset, int count) => replace(offset, count, const []);

  /// Overwrite bytes without changing the document length.
  void overwrite(int offset, List<int> bytes) =>
      replace(offset, bytes.length, bytes);

  bool undo() {
    _checkOpen();
    if (_undo.isEmpty) return false;
    final edit = _undo.removeLast();
    _tree.replace(edit.offset, edit.insertedLength, edit.removed);
    _redo.add(edit);
    _state = edit.before;
    _revision++;
    return true;
  }

  bool redo() {
    _checkOpen();
    if (_redo.isEmpty) return false;
    final edit = _redo.removeLast();
    _tree.replace(edit.offset, edit.removedLength, edit.inserted);
    _undo.add(edit);
    _state = edit.after;
    _revision++;
    return true;
  }

  /// Mark the current state, or a still-open snapshot's revision, as saved.
  ///
  /// Call only after the host successfully commits the snapshot. If edits
  /// occurred during saving, they stay dirty; undoing to the saved state makes
  /// the document clean again. Keep a snapshot open until after this call.
  void markSaved([int? revision]) {
    _checkOpen();
    if (revision == null || revision == _revision) {
      _savedState = _state;
      return;
    }
    RangeError.checkValueInInterval(revision, 0, _revision, 'revision');
    final state = _snapshotStates[revision];
    if (state == null) {
      throw ArgumentError.value(
        revision,
        'revision',
        'is neither current nor retained by an open snapshot',
      );
    }
    _savedState = state.state;
  }

  /// Discard history without changing content or the saved-state marker.
  void clearHistory() {
    _checkOpen();
    _clearEntries(_undo);
    _clearEntries(_redo);
  }

  /// Read an owned byte array; [length] is clipped at EOF.
  Future<Uint8List> read(int offset, int length) async {
    _checkOpen();
    final count = checkedReadLength(this.length, offset, length);
    if (count == 0) return Uint8List(0);
    final view = _ReadView(_tree.piecesInRange(offset, count));
    _source.retain();
    try {
      return await _readView(_source, view, 0, count);
    } finally {
      await _source.release();
    }
  }

  /// Capture immutable range descriptors without reading the original source.
  HexSnapshot snapshot() {
    _checkOpen();
    final view = _ReadView(_tree.pieces);
    final rev = _revision;
    final state = _snapshotStates.putIfAbsent(
      rev,
      () => _SnapshotState(_state),
    );
    state.references++;
    _source.retain();
    return HexSnapshot._(_source, view, rev, () {
      final retained = _snapshotStates[rev];
      if (retained != null && --retained.references == 0) {
        _snapshotStates.remove(rev);
      }
    });
  }

  /// Stop new operations and release document-owned storage.
  ///
  /// Existing snapshots and in-flight reads remain valid. Closing returns
  /// without waiting for snapshots the caller still owns; the underlying
  /// source is closed by whichever owner releases it last.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _tree.clear();
    _clearEntries(_undo);
    _clearEntries(_redo);
    _snapshotStates.clear();
    return _closing = _source.release();
  }

  /// Checks the byte tree's invariants without reading the source.
  String? debugValidate() => _tree.validate();

  int get debugPieceCount => _tree.pieces.length;

  void _checkOpen() {
    if (_closed) throw StateError('The hex document is closed.');
  }

  void _checkEditRange(int offset, int count) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    RangeError.checkValueInInterval(count, 0, length - offset, 'deleteCount');
  }

  void _record(_Edit edit) {
    _undo.add(edit);
    _historyPieces += edit.pieceCount;
    for (final buffer in edit.memoryBuffers) {
      final users = _historyBuffers[buffer] ?? 0;
      if (users == 0) _historyBytes += buffer.bytes!.length;
      _historyBuffers[buffer] = users + 1;
    }
    while (_undo.length + _redo.length > maxUndoSteps ||
        _historyBytes > maxUndoBytes ||
        _historyPieces > maxUndoPieces) {
      final entries = _undo.isNotEmpty ? _undo : _redo;
      if (entries.isEmpty) break;
      _releaseEntry(entries.removeAt(0));
    }
  }

  void _clearEntries(List<_Edit> entries) {
    for (final edit in entries) {
      _releaseEntry(edit);
    }
    entries.clear();
  }

  void _releaseEntry(_Edit edit) {
    _historyPieces -= edit.pieceCount;
    for (final buffer in edit.memoryBuffers) {
      final users = _historyBuffers[buffer]!;
      if (users == 1) {
        _historyBuffers.remove(buffer);
        _historyBytes -= buffer.bytes!.length;
      } else {
        _historyBuffers[buffer] = users - 1;
      }
    }
  }
}

/// A stable, read-only document revision. Release it with [close].
class HexSnapshot {
  HexSnapshot._(this._source, _ReadView view, this.revision, this._onClose)
    : _view = view,
      length = view.length;

  final _SourceLifetime _source;
  _ReadView? _view;
  void Function()? _onClose;
  Future<void>? _closing;
  final int length;
  final int revision;

  bool get isClosed => _view == null;

  Future<Uint8List> read(int offset, int length) async {
    final view = _requireView();
    final count = checkedReadLength(this.length, offset, length);
    if (count == 0) return Uint8List(0);
    _source.retain();
    try {
      return await _readView(_source, view, offset, count);
    } finally {
      await _source.release();
    }
  }

  /// Stream an immutable revision in bounded, owned chunks.
  ///
  /// Once subscribed, the stream retains its own source lease. It remains
  /// valid if the document or snapshot is closed while streaming. Canceling
  /// the subscription releases that lease in the same way as completion.
  Stream<List<int>> stream({int chunkSize = 65536}) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    var retained = false;
    var cancelled = false;

    Future<void> release() async {
      if (!retained) return;
      retained = false;
      await _source.release();
    }

    Stream<List<int>> chunks(_ReadView view) async* {
      try {
        var offset = 0;
        while (!cancelled && offset < length) {
          final remaining = length - offset;
          final count = remaining < chunkSize ? remaining : chunkSize;
          yield await _readView(_source, view, offset, count);
          offset += count;
        }
      } finally {
        await release();
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        try {
          if (chunkSize <= 0) {
            throw RangeError.value(chunkSize, 'chunkSize', 'must be positive');
          }
          // async* begins delivering after listen returns. Capture and retain
          // here so a subsequent snapshot.close cannot invalidate the stream.
          final view = _requireView();
          _source.retain();
          retained = true;
          subscription = chunks(view).listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        } catch (error, stack) {
          controller.addError(error, stack);
          unawaited(controller.close());
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        cancelled = true;
        try {
          await subscription?.cancel();
        } finally {
          // Cancellation before chunks starts does not run its finally block.
          await release();
        }
      },
    );
    return controller.stream;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _view = null;
    _onClose?.call();
    _onClose = null;
    return _closing = _source.release();
  }

  _ReadView _requireView() {
    final view = _view;
    if (view == null) throw StateError('The hex snapshot is closed.');
    return view;
  }
}

Uint8List _copyBytes(List<int> bytes) {
  if (bytes is Uint8List) return Uint8List.fromList(bytes);
  final owned = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    RangeError.checkValueInInterval(byte, 0, 255, 'bytes[$i]');
    owned[i] = byte;
  }
  return owned;
}

class _ByteBuffer {
  const _ByteBuffer.original() : bytes = null;
  const _ByteBuffer.memory(this.bytes);

  // Never exposed to callers and never mutated after construction.
  final Uint8List? bytes;
}

class _Edit {
  _Edit(this.offset, this.removed, this.inserted, this.before, this.after)
    : removedLength = removed.fold(0, (sum, p) => sum + p.length),
      insertedLength = inserted.fold(0, (sum, p) => sum + p.length),
      memoryBuffers = {
        for (final piece in [...removed, ...inserted])
          if (piece.buffer.bytes != null) piece.buffer,
      };

  final int offset;
  final List<PieceRef<_ByteBuffer>> removed;
  final List<PieceRef<_ByteBuffer>> inserted;
  final int removedLength;
  final int insertedLength;
  final int before;
  final int after;
  final Set<_ByteBuffer> memoryBuffers;
  int get pieceCount => removed.length + inserted.length;
}

class _SnapshotState {
  _SnapshotState(this.state);
  final int state;
  int references = 0;
}

class _ReadView {
  _ReadView(List<PieceRef<_ByteBuffer>> pieces)
    : pieces = List.unmodifiable(pieces),
      ends = [] {
    var position = 0;
    for (final piece in pieces) {
      position += piece.length;
      ends.add(position);
    }
    length = position;
  }

  final List<PieceRef<_ByteBuffer>> pieces;
  final List<int> ends;
  late final int length;

  int indexAt(int offset) {
    var low = 0, high = ends.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (ends[mid] <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

Future<Uint8List> _readView(
  _SourceLifetime source,
  _ReadView view,
  int offset,
  int count,
) async {
  final result = Uint8List(count);
  var out = 0;
  var index = view.indexAt(offset);
  var within = offset - (index == 0 ? 0 : view.ends[index - 1]);
  while (out < count) {
    final piece = view.pieces[index];
    final available = piece.length - within;
    final remaining = count - out;
    final take = available < remaining ? available : remaining;
    final memory = piece.buffer.bytes;
    if (memory != null) {
      result.setRange(out, out + take, memory, piece.start + within);
    } else {
      var read = 0;
      while (read < take) {
        final remaining = take - read;
        final part = remaining < 65536 ? remaining : 65536;
        final bytes = await source.readExact(piece.start + within + read, part);
        result.setRange(out + read, out + read + part, bytes);
        read += part;
      }
    }
    out += take;
    within = 0;
    index++;
  }
  return result;
}

/// Ref-counts external resource ownership and serializes source callbacks.
class _SourceLifetime {
  _SourceLifetime(this.source);
  final HexByteSource source;
  int _references = 1;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;

  void retain() {
    if (_references <= 0) {
      throw StateError('The byte source has been released.');
    }
    _references++;
  }

  Future<void> release() {
    assert(_references > 0);
    _references--;
    if (_references != 0) return Future<void>.value();
    return _closing ??= _tail.then((_) => source.close());
  }

  Future<Uint8List> readExact(int offset, int count) {
    final result = Completer<Uint8List>();
    _tail = _tail.then((_) async {
      try {
        final bytes = Uint8List(count);
        var done = 0;
        while (done < count) {
          final remaining = count - done;
          final part = await source.read(offset + done, remaining);
          if (part.isEmpty || part.length > remaining) {
            throw StateError(
              'Byte source returned ${part.length} bytes for a request of '
              '$remaining at ${offset + done}; its contents may have changed.',
            );
          }
          bytes.setRange(done, done + part.length, part);
          done += part.length;
        }
        result.complete(bytes);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}

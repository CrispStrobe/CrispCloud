import 'dart:typed_data';

/// Immutable, random-access backing storage. Implementations must keep the
/// original bytes stable for the lifetime of every editing snapshot.
abstract class HexByteSource {
  int get length;
  Future<Uint8List> read(int offset, int length);
}

class MemoryHexByteSource implements HexByteSource {
  MemoryHexByteSource(List<int> bytes) : _bytes = Uint8List.fromList(bytes);
  final Uint8List _bytes;
  @override
  int get length => _bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    _checkRange(offset, length, _bytes.length);
    return Uint8List.fromList(_bytes.sublist(offset, offset + length));
  }
}

void _checkRange(int offset, int count, int total) {
  if (offset < 0 || count < 0 || offset > total ||
      count > total - offset) {
    throw RangeError('Invalid byte range $offset+$count of $total');
  }
}

class _Piece {
  const _Piece(this.original, this.start, this.length, this.inserted);
  final bool original;
  final int start;
  final int length;
  final Uint8List? inserted;
  _Piece slice(int offset, int count) =>
      _Piece(original, start + offset, count, inserted);
}

/// Stable copy-on-write view of a byte document. Reads are bounded; writing
/// never changes the original source. The source must remain immutable.
class HexSnapshot {
  HexSnapshot._(this.source, this.pieces, this.length, this.revision);
  final HexByteSource source;
  final List<_Piece> pieces;
  final int length;
  final int revision;

  Future<Uint8List> read(int offset, int count) async {
    _checkRange(offset, count, length);
    final out = Uint8List(count);
    var cursor = 0;
    var written = 0;
    for (final piece in pieces) {
      final end = cursor + piece.length;
      if (end > offset && cursor < offset + count) {
        final from = offset > cursor ? offset - cursor : 0;
        final to = end < offset + count ? piece.length : offset + count - cursor;
        final bytes = piece.original
            ? await source.read(piece.start + from, to - from)
            : Uint8List.sublistView(piece.inserted!, piece.start + from,
                piece.start + to);
        out.setRange(written, written + bytes.length, bytes);
        written += bytes.length;
      }
      cursor = end;
      if (written == count) break;
    }
    return out;
  }

  Stream<Uint8List> chunks({int chunkSize = 65536}) async* {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    for (var offset = 0; offset < length; offset += chunkSize) {
      final count = length - offset < chunkSize ? length - offset : chunkSize;
      yield await read(offset, count);
    }
  }
}

/// Byte-exact insert, delete, overwrite and undo/redo without line indexing.
/// History is limited by number of edits; inserted byte buffers are retained
/// while referenced by history or snapshots.
class HexDocument {
  HexDocument(HexByteSource source, {this.maxUndoSteps = 100})
      : assert(maxUndoSteps > 0),
        _source = source,
        _pieces = source.length == 0
            ? <_Piece>[]
            : <_Piece>[_Piece(true, 0, source.length, null)],
        _length = source.length;
  final HexByteSource _source;
  final int maxUndoSteps;
  List<_Piece> _pieces;
  int _length;
  int _revision = 0;
  int _nextRevision = 0;
  int _savedRevision = 0;
  final List<HexSnapshot> _undo = [];
  final List<HexSnapshot> _redo = [];

  int get length => _length;
  int get revision => _revision;
  bool get isDirty => _revision != _savedRevision;
  HexSnapshot get snapshot =>
      HexSnapshot._(_source, List.unmodifiable(_pieces), _length, _revision);
  Future<Uint8List> read(int offset, int count) =>
      snapshot.read(offset, count);

  void markSaved(HexSnapshot saved) {
    _savedRevision = saved.revision;
  }

  void insert(int offset, List<int> bytes) => replace(offset, 0, bytes);
  void delete(int offset, int count) => replace(offset, count, const []);
  void overwrite(int offset, List<int> bytes) =>
      replace(offset, bytes.length, bytes);

  void replace(int offset, int count, List<int> bytes) {
    _checkRange(offset, count, _length);
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        throw RangeError.value(byte, 'byte', 'Must be 0..255');
      }
    }
    if (count == 0 && bytes.isEmpty) return;
    _undo.add(snapshot);
    if (_undo.length > maxUndoSteps) _undo.removeAt(0);
    _redo.clear();
    final replacement = Uint8List.fromList(bytes);
    final next = <_Piece>[];
    var cursor = 0;
    var inserted = false;
    for (final piece in _pieces) {
      final end = cursor + piece.length;
      if (end <= offset || cursor >= offset + count) {
        if (!inserted && cursor >= offset) {
          if (replacement.isNotEmpty) {
            next.add(_Piece(false, 0, replacement.length, replacement));
          }
          inserted = true;
        }
        next.add(piece);
      } else {
        if (cursor < offset) next.add(piece.slice(0, offset - cursor));
        if (!inserted) {
          if (replacement.isNotEmpty) {
            next.add(_Piece(false, 0, replacement.length, replacement));
          }
          inserted = true;
        }
        if (end > offset + count) {
          next.add(piece.slice(offset + count - cursor,
              end - offset - count));
        }
      }
      cursor = end;
    }
    if (!inserted && replacement.isNotEmpty) {
      next.add(_Piece(false, 0, replacement.length, replacement));
    }
    _pieces = next;
    _length += replacement.length - count;
    _revision = ++_nextRevision;
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(snapshot);
    _restore(_undo.removeLast());
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(snapshot);
    _restore(_redo.removeLast());
    return true;
  }

  void _restore(HexSnapshot state) {
    _pieces = List.of(state.pieces);
    _length = state.length;
    _revision = state.revision;
  }
}

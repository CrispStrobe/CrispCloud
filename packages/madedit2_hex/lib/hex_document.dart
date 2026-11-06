import 'dart:async';
import 'dart:typed_data';

/// Immutable random-access bytes. The host owns the source and must keep it
/// open AND unchanged while any document or snapshot references it.
abstract class HexByteSource {
  int get length;
  Future<Uint8List> read(int offset, int length);
}

class MemoryHexByteSource implements HexByteSource {
  MemoryHexByteSource(List<int> bytes) : _bytes = _copyBytes(bytes);
  final Uint8List _bytes;
  @override
  int get length => _bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async {
    _checkRange(offset, length, _bytes.length);
    return Uint8List.fromList(
      Uint8List.sublistView(_bytes, offset, offset + length),
    );
  }
}

Uint8List _copyBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) throw RangeError.range(byte, 0, 255, 'byte');
  }
  return Uint8List.fromList(bytes);
}

void _checkRange(int offset, int count, int total) {
  if (offset < 0 || count < 0 || offset > total || count > total - offset) {
    throw RangeError('Invalid byte range $offset+$count of $total');
  }
}

// Persistent, byte-only AVL rope. Like MadEdit2's piece tree, leaves point to
// original or added byte ranges. Unlike its text Document, this tree has NO
// newline aggregate/index and shares immutable roots with undo/save snapshots.
class _Piece {
  const _Piece(this.start, this.length, [this.data]);
  final int start;
  final int length;
  final Uint8List? data; // null = immutable original source
  _Piece slice(int offset, int count) => _Piece(start + offset, count, data);
}

class _Node {
  _Node.leaf(this.piece)
    : left = null,
      right = null,
      length = piece!.length,
      height = 1;
  _Node.branch(_Node a, _Node b)
    : left = a,
      right = b,
      piece = null,
      length = a.length + b.length,
      height = 1 + (a.height > b.height ? a.height : b.height);
  final _Node? left, right;
  final _Piece? piece;
  final int length, height;
}

int _height(_Node? node) => node?.height ?? 0;
_Node _balance(_Node a, _Node b) {
  if (a.height > b.height + 1) {
    final l = a.left!, r = a.right!;
    if (l.height >= r.height) return _Node.branch(l, _Node.branch(r, b));
    return _Node.branch(_Node.branch(l, r.left!), _Node.branch(r.right!, b));
  }
  if (b.height > a.height + 1) {
    final l = b.left!, r = b.right!;
    if (r.height >= l.height) return _Node.branch(_Node.branch(a, l), r);
    return _Node.branch(_Node.branch(a, l.left!), _Node.branch(l.right!, r));
  }
  return _Node.branch(a, b);
}

_Node? _join(_Node? a, _Node? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (a.height > b.height + 1) return _balance(a.left!, _join(a.right, b)!);
  if (b.height > a.height + 1) return _balance(_join(a, b.left)!, b.right!);
  return _Node.branch(a, b);
}

(_Node?, _Node?) _split(_Node? node, int offset) {
  if (node == null) return (null, null);
  if (offset == 0) return (null, node);
  if (offset == node.length) return (node, null);
  final piece = node.piece;
  if (piece != null)
    return (
      _Node.leaf(piece.slice(0, offset)),
      _Node.leaf(piece.slice(offset, piece.length - offset)),
    );
  final leftLength = node.left!.length;
  if (offset < leftLength) {
    final halves = _split(node.left, offset);
    return (halves.$1, _join(halves.$2, node.right));
  }
  final halves = _split(node.right, offset - leftLength);
  return (_join(node.left, halves.$1), halves.$2);
}

Iterable<_Piece> _range(_Node? node, int start, int count) sync* {
  if (node == null || count == 0) return;
  if (node.piece != null) {
    yield node.piece!.slice(start, count);
    return;
  }
  final leftLength = node.left!.length;
  if (start < leftLength) {
    final take = count < leftLength - start ? count : leftLength - start;
    yield* _range(node.left, start, take);
    if (take < count) yield* _range(node.right, 0, count - take);
  } else {
    yield* _range(node.right, start - leftLength, count);
  }
}

/// An O(1), stable snapshot of an editable document. All reads verify that the
/// backing source returned exactly the requested bytes; short reads never turn
/// into silent zero-filled data. Host persistence should consume [chunks].
class HexSnapshot {
  HexSnapshot._(this._owner, this._source, this._root, this.revision);
  final Object _owner;
  final HexByteSource _source;
  final _Node? _root;
  final int revision;
  int get length => _root?.length ?? 0;

  Future<Uint8List> read(int offset, int count) async {
    _checkRange(offset, count, length);
    final result = Uint8List(count);
    var written = 0;
    for (final piece in _range(_root, offset, count)) {
      final bytes = piece.data == null
          ? await _source.read(piece.start, piece.length)
          : Uint8List.sublistView(
              piece.data!,
              piece.start,
              piece.start + piece.length,
            );
      if (bytes.length != piece.length)
        throw StateError('The original byte source returned a short read.');
      result.setRange(written, written + bytes.length, bytes);
      written += bytes.length;
    }
    if (written != count)
      throw StateError('The document range could not be read completely.');
    return result;
  }

  Stream<Uint8List> chunks({
    int chunkSize = 65536,
    int start = 0,
    int? count,
  }) async* {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    final lengthToRead = count ?? length - start;
    _checkRange(start, lengthToRead, length);
    for (var offset = start; offset < start + lengthToRead;) {
      final remaining = start + lengthToRead - offset;
      final size = remaining < chunkSize ? remaining : chunkSize;
      yield await read(offset, size);
      offset += size;
    }
  }

  /// Bounded-memory KMP byte search, including matches across chunk/piece
  /// boundaries. Cancellation is cooperative and never changes the document.
  Future<int?> find(
    List<int> pattern, {
    int start = 0,
    int? end,
    bool Function()? cancelled,
    void Function(int position)? onProgress,
  }) async {
    final needle = _copyBytes(pattern);
    if (needle.isEmpty || needle.length > 1024 * 1024) {
      throw ArgumentError('Search must contain 1..1048576 bytes.');
    }
    final limit = end ?? length;
    _checkRange(start, limit - start, length);
    final table = List<int>.filled(needle.length, 0);
    for (var i = 1, j = 0; i < needle.length; i++) {
      while (j > 0 && needle[i] != needle[j]) {
        j = table[j - 1];
      }
      if (needle[i] == needle[j]) j++;
      table[i] = j;
    }
    var position = start, matched = 0, chunksRead = 0;
    await for (final bytes in chunks(start: start, count: limit - start)) {
      if (cancelled?.call() ?? false) throw const HexSearchCancelled();
      for (final byte in bytes) {
        while (matched > 0 && byte != needle[matched]) {
          matched = table[matched - 1];
        }
        if (byte == needle[matched]) matched++;
        position++;
        if (matched == needle.length) return position - matched;
      }
      onProgress?.call(position);
      if (++chunksRead % 16 == 0) await Future<void>.delayed(Duration.zero);
    }
    return null;
  }
}

class HexSearchCancelled implements Exception {
  const HexSearchCancelled();
}

class HexDocument {
  HexDocument(
    HexByteSource source, {
    this.maxUndoSteps = 500,
    this.maxSingleEditBytes = 16 * 1024 * 1024,
  }) : _source = source {
    if (maxUndoSteps < 1 || maxSingleEditBytes < 1)
      throw ArgumentError('Invalid editor limits.');
    // Native/web must agree on exact byte offsets (JS's largest safe integer).
    if (source.length < 0 || source.length > 0x1fffffffffffff) {
      throw RangeError(
        'Byte source length is outside the exact integer range.',
      );
    }
    if (source.length > 0) _root = _Node.leaf(_Piece(0, source.length));
  }
  final Object _owner = Object();
  final HexByteSource _source;
  final int maxUndoSteps, maxSingleEditBytes;
  _Node? _root;
  int _revision = 0, _nextRevision = 0, _savedRevision = 0;
  final List<HexSnapshot> _undo = [], _redo = [];
  int get length => _root?.length ?? 0;
  int get revision => _revision;
  bool get isDirty => _revision != _savedRevision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  HexSnapshot get snapshot => HexSnapshot._(_owner, _source, _root, _revision);
  Future<Uint8List> read(int offset, int count) => snapshot.read(offset, count);
  int get debugTreeHeight => _height(_root);

  void markSaved(HexSnapshot saved) {
    if (!identical(saved._owner, _owner))
      throw ArgumentError('Snapshot belongs to another document.');
    _savedRevision = saved.revision;
  }

  void insert(int offset, List<int> bytes) => replace(offset, 0, bytes);
  void delete(int offset, int count) => replace(offset, count, const []);
  void overwrite(int offset, List<int> bytes) =>
      replace(offset, bytes.length, bytes);

  /// [coalesce] groups the second nibble with the first; callers must only use
  /// it for one uninterrupted user gesture, never across a save or undo.
  void replace(
    int offset,
    int count,
    List<int> bytes, {
    bool coalesce = false,
  }) {
    _checkRange(offset, count, length);
    if (bytes.length > maxSingleEditBytes)
      throw StateError('This edit exceeds the configured byte limit.');
    final added = _copyBytes(bytes);
    if (count == 0 && added.isEmpty) return;
    if (length - count + added.length > 0x1fffffffffffff)
      throw RangeError('Document too large.');
    final before = snapshot;
    final first = _split(_root, offset);
    final second = _split(first.$2, count);
    final middle = added.isEmpty
        ? null
        : _Node.leaf(_Piece(0, added.length, added));
    final next = _join(_join(first.$1, middle), second.$2);
    if (!coalesce ||
        _undo.isEmpty ||
        _redo.isNotEmpty ||
        _revision == _savedRevision) {
      _undo.add(before);
      if (_undo.length > maxUndoSteps) _undo.removeAt(0);
    }
    _redo.clear();
    _root = next;
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

  void _restore(HexSnapshot value) {
    _root = value._root;
    _revision = value.revision;
  }
}

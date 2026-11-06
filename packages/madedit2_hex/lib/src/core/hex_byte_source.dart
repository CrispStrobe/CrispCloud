import 'dart:async';
import 'dart:typed_data';

/// An immutable, randomly readable sequence of bytes.
///
/// [length] and the bytes at each offset must remain stable until [close]. A
/// remote adapter should pin an object version or ETag; a file adapter should
/// keep a stable file handle or an immutable local copy. The document owns the
/// source and closes it after its last snapshot and in-flight read finish.
///
/// Reads may return fewer bytes than requested. The document retries partial
/// reads and reports an error if a source unexpectedly stops before [length].
abstract class HexByteSource {
  int get length;

  Future<Uint8List> read(int offset, int length);

  Future<void> close();
}

/// A source backed by an owned copy of [bytes].
///
/// Neither changing the constructor argument nor changing a returned read
/// buffer can alter this source.
class MemoryHexByteSource implements HexByteSource {
  MemoryHexByteSource(Uint8List bytes) : _bytes = Uint8List.fromList(bytes);

  Uint8List? _bytes;
  int? _closedLength;

  @override
  int get length => _bytes?.length ?? _closedLength!;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final bytes = _bytes;
    if (bytes == null) throw StateError('The byte source is closed.');
    final count = checkedReadLength(bytes.length, offset, length);
    return Uint8List.fromList(
      Uint8List.sublistView(bytes, offset, offset + count),
    );
  }

  @override
  Future<void> close() async {
    final bytes = _bytes;
    if (bytes == null) return;
    _closedLength = bytes.length;
    _bytes = null;
  }
}

typedef HexRangeReader = Future<Uint8List> Function(int offset, int length);
typedef HexSourceCloser = FutureOr<void> Function();

/// Adapts a host's range reader without imposing a filesystem or network API.
class CallbackHexByteSource implements HexByteSource {
  CallbackHexByteSource({
    required int length,
    required HexRangeReader read,
    HexSourceCloser? close,
  }) : _length = RangeError.checkNotNegative(length, 'length'),
       _read = read,
       _close = close;

  final int _length;
  final HexRangeReader _read;
  final HexSourceCloser? _close;
  bool _closed = false;
  Future<void>? _closing;

  @override
  int get length => _length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_closed) throw StateError('The byte source is closed.');
    final count = checkedReadLength(_length, offset, length);
    if (count == 0) return Uint8List(0);
    return _read(offset, count);
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = Future<void>.sync(() => _close?.call());
  }
}

/// Checks a read range and returns its length, clipped at EOF.
///
/// Internal to the package; callers should use source/document read methods.
int checkedReadLength(int total, int offset, int length) {
  RangeError.checkValueInInterval(offset, 0, total, 'offset');
  RangeError.checkNotNegative(length, 'length');
  final available = total - offset;
  return length < available ? length : available;
}

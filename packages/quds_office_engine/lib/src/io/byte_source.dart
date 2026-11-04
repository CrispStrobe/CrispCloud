import 'dart:typed_data';

/// Random-access byte provider used by ZIP and CFBF readers.
///
/// Implementations must support overlapping reads. Returned lists may be
/// views into an underlying buffer; callers that mutate bytes must copy.
abstract class ByteSource {
  /// length API.
  int get length;

  /// Reads [length] bytes starting at [offset].
  Uint8List read(int offset, int length);

  /// Returns a view of `[offset, offset + length)` when the source can do so
  /// without copying; otherwise returns a copy.
  Uint8List view(int offset, int length) => read(offset, length);
}

/// In-memory [ByteSource] backed by a single [Uint8List].
class MemoryByteSource implements ByteSource {
  /// MemoryByteSource API.
  MemoryByteSource(this._bytes);

  final Uint8List _bytes;

  @override
  /// length API.
  int get length => _bytes.length;

  @override
  /// read API.
  Uint8List read(int offset, int length) {
    _checkRange(offset, length);
    return Uint8List.fromList(
      Uint8List.sublistView(_bytes, offset, offset + length),
    );
  }

  @override
  /// view API.
  Uint8List view(int offset, int length) {
    _checkRange(offset, length);
    return Uint8List.sublistView(_bytes, offset, offset + length);
  }

  void _checkRange(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > _bytes.length) {
      throw RangeError(
        'ByteSource read out of range: offset=$offset length=$length '
        'size=${_bytes.length}',
      );
    }
  }
}

/// Sequential little-endian / big-endian cursor over a [Uint8List].
class ByteCursor {
  /// ByteCursor API.
  ByteCursor(this.buffer, {this.offset = 0});

  /// view API.
  factory ByteCursor.view(ByteSource source, int offset, int length) {
    return ByteCursor(source.view(offset, length));
  }

  /// buffer API.
  final Uint8List buffer;

  /// offset API.
  int offset;

  /// remaining API.
  int get remaining => buffer.length - offset;

  /// length API.
  int get length => buffer.length;

  /// isEof API.
  bool get isEof => offset >= buffer.length;

  /// seek API.
  void seek(int position) {
    if (position < 0 || position > buffer.length) {
      throw RangeError('seek out of range: $position');
    }
    offset = position;
  }

  /// skip API.
  void skip(int count) {
    seek(offset + count);
  }

  /// u8 API.
  int u8() {
    if (offset >= buffer.length) {
      throw RangeError('u8 past end at $offset');
    }
    return buffer[offset++];
  }

  /// u16le API.
  int u16le() {
    final int value = buffer[offset] | (buffer[offset + 1] << 8);
    offset += 2;
    return value;
  }

  /// u16be API.
  int u16be() {
    final int value = (buffer[offset] << 8) | buffer[offset + 1];
    offset += 2;
    return value;
  }

  /// u32le API.
  int u32le() {
    final int value =
        buffer[offset] |
        (buffer[offset + 1] << 8) |
        (buffer[offset + 2] << 16) |
        (buffer[offset + 3] << 24);
    offset += 4;
    return value & 0xFFFFFFFF;
  }

  /// u32be API.
  int u32be() {
    final int value =
        (buffer[offset] << 24) |
        (buffer[offset + 1] << 16) |
        (buffer[offset + 2] << 8) |
        buffer[offset + 3];
    offset += 4;
    return value & 0xFFFFFFFF;
  }

  /// i16le API.
  int i16le() {
    final int value = u16le();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  /// i16be API.
  int i16be() {
    final int value = u16be();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  /// i32le API.
  int i32le() {
    final int value = u32le();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  /// i32be API.
  int i32be() {
    final int value = u32be();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  /// u64le API.
  int u64le() {
    final int lo = u32le();
    final int hi = u32le();
    return (hi << 32) | lo;
  }

  /// bytes API.
  Uint8List bytes(int count) {
    if (offset + count > buffer.length) {
      throw RangeError(
        'bytes($count) past end at $offset (len=${buffer.length})',
      );
    }
    final Uint8List view = Uint8List.sublistView(
      buffer,
      offset,
      offset + count,
    );
    offset += count;
    return view;
  }

  /// copyBytes API.
  Uint8List copyBytes(int count) {
    return Uint8List.fromList(bytes(count));
  }
}

/// Growable little-endian byte sink used by writers.
class ByteSink {
  /// ByteSink API.
  ByteSink({int capacity = 256}) : _builder = BytesBuilder(copy: false);

  final BytesBuilder _builder;
  int _length = 0;

  /// length API.
  int get length => _length;

  /// u8 API.
  void u8(int value) {
    _builder.addByte(value & 0xFF);
    _length += 1;
  }

  /// u16le API.
  void u16le(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _length += 2;
  }

  /// u32le API.
  void u32le(int value) {
    _builder.addByte(value & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte((value >> 16) & 0xFF);
    _builder.addByte((value >> 24) & 0xFF);
    _length += 4;
  }

  /// u64le API.
  void u64le(int value) {
    u32le(value & 0xFFFFFFFF);
    u32le((value >> 32) & 0xFFFFFFFF);
  }

  /// u16be API.
  void u16be(int value) {
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte(value & 0xFF);
    _length += 2;
  }

  /// u32be API.
  void u32be(int value) {
    _builder.addByte((value >> 24) & 0xFF);
    _builder.addByte((value >> 16) & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte(value & 0xFF);
    _length += 4;
  }

  /// i16be API.
  void i16be(int value) => u16be(value & 0xFFFF);

  /// add API.
  void add(List<int> bytes) {
    _builder.add(bytes);
    _length += bytes.length;
  }

  /// padTo API.
  void padTo(int alignment, [int fill = 0]) {
    final int rem = _length % alignment;
    if (rem == 0) {
      return;
    }
    final int needed = alignment - rem;
    for (int i = 0; i < needed; i++) {
      u8(fill);
    }
  }

  /// takeBytes API.
  Uint8List takeBytes() => _builder.takeBytes();

  /// toBytes API.
  Uint8List toBytes() => _builder.toBytes();
}

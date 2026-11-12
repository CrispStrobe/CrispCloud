import 'dart:typed_data';

/// A reader of bytes sequence.
class BytesReader {
  final ByteData _data;
  int _offset = 0;

  /// Constructs a [BytesReader] from the [bytes] list.
  BytesReader(List<int> bytes)
      : _data = Uint8List.fromList(bytes).buffer.asByteData();

  /// Reads an unsigned 64-bit integer.
  int readUint64() {
    final low = readUint32();
    final high = readUint32();
    if (high > 0x1fffff) {
      throw const FormatException(
          '64-bit value exceeds portable integer range');
    }
    return high * 4294967296 + low;
  }

  /// Reads an signed 64-bit integer.
  int readInt64() {
    final low = readUint32();
    final high = readInt32();
    final result = high * 4294967296 + low;
    if (result.abs() > 9007199254740991) {
      throw const FormatException(
          '64-bit value exceeds portable integer range');
    }
    return result;
  }

  /// Reads an unsigned 32-bit integer.
  int readUint32() {
    final result = _data.getUint32(_offset, Endian.little);
    _offset += Uint32List.bytesPerElement;
    return result;
  }

  /// Reads an signed 32-bit integer.
  int readInt32() {
    final result = _data.getInt32(_offset, Endian.little);
    _offset += Int32List.bytesPerElement;
    return result;
  }

  /// Reads an unsigned 16-bit integer.
  int readUint16() {
    final result = _data.getUint16(_offset, Endian.little);
    _offset += Uint16List.bytesPerElement;
    return result;
  }

  /// Reads an unsigned 8-bit integer.
  int readUint8() {
    final result = _data.getUint8(_offset);
    _offset += Uint8List.bytesPerElement;
    return result;
  }

  /// Reads bytes sequence with [length].
  Uint8List readBytes(int length) {
    if (length < 0 || length > bytesLeft) {
      throw const FormatException('Truncated byte sequence');
    }

    final result = _data.buffer.asUint8List(_offset, length);
    _offset += length;
    return result;
  }

  /// Reads remaining amount of bytes.
  Uint8List readBytesToEnd() {
    final result = _data.buffer.asUint8List(_offset);
    _offset = _data.lengthInBytes;
    return result;
  }

  /// The bytes were already read.
  List<int> get past => _data.buffer.asUint8List(0, _offset);

  /// The remaining length of bytes.
  int get bytesLeft => _data.lengthInBytes - _offset;
}

/// A writer to a sequence of bytes.
class BytesWriter {
  final _builder = BytesBuilder();

  /// Writes unsigned 64-bit integer.
  writeUint64(int value) {
    // KDBX reserves the all-ones index for the header HMAC. Use -1 for that
    // sentinel so the source also compiles to JavaScript without lossy literals.
    if (value == -1) {
      writeUint32(0xffffffff);
      writeUint32(0xffffffff);
      return;
    }
    if (value < 0 || value > 9007199254740991) {
      throw const FormatException(
          '64-bit value exceeds portable integer range');
    }
    writeUint32(value % 4294967296);
    writeUint32(value ~/ 4294967296);
  }

  /// Writes signed 64-bit integer.
  writeInt64(int value) {
    if (value.abs() > 9007199254740991) {
      throw const FormatException(
          '64-bit value exceeds portable integer range');
    }
    final low = value % 4294967296;
    writeUint32(low);
    writeInt32((value - low) ~/ 4294967296);
  }

  /// Writes unsigned 32-bit integer.
  writeUint32(int value) {
    final data = ByteData(Uint32List.bytesPerElement)
      ..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  /// Writes signed 32-bit integer.
  writeInt32(int value) {
    final data = ByteData(Int32List.bytesPerElement)
      ..setInt32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  /// Writes unsigned 16-bit integer.
  writeUint16(int value) {
    final data = ByteData(Uint16List.bytesPerElement)
      ..setUint16(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  /// Writes unsigned 8-bit integer.
  writeUint8(int value) => _builder.add([value]);

  /// Writes list of the [bytes].
  writeBytes(List<int> bytes) => _builder.add(bytes);

  ///The result bytes sequence.
  Uint8List get bytes => _builder.toBytes(); //TODO: return without copy
}

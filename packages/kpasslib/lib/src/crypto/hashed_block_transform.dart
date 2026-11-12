import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:kpasslib/kpasslib.dart';

import '../utils/byte_utils.dart';

/// Hashed block transformation functions
abstract final class HashedBlockTransform {
  static const int _blockSize = DataSize.mebi;
  static const int _hashSize = 32;
  static const int _endBlockSize = 0;

  /// Returns encrypted [data].
  static Uint8List encrypt(List<int> data) {
    final reader = BytesReader(data);
    final writer = BytesWriter();
    var index = 0;

    while (reader.bytesLeft > 0) {
      final size = min(_blockSize, reader.bytesLeft);
      final data = reader.readBytes(size);
      writer.writeUint32(index++);
      writer.writeBytes(sha256.convert(data).bytes);
      writer.writeUint32(size);
      writer.writeBytes(data);
    }

    writer.writeUint32(index);
    writer.writeBytes(Uint8List(_hashSize));
    writer.writeUint32(_endBlockSize);
    return writer.bytes;
  }

  /// Returns decrypted [data].
  static Uint8List decrypt(List<int> data) {
    final reader = BytesReader(data);
    final builder = BytesBuilder();

    var index = 0;
    while (true) {
      if (index > 4096) {
        throw const ResourceLimitError('too many hashed blocks');
      }
      if (reader.readUint32() != index++) {
        throw const FileCorruptedError('invalid block index');
      }
      final hash = reader.readBytes(_hashSize);
      final size = reader.readUint32();
      if (size == 0) {
        if (hash.any((value) => value != 0) || reader.bytesLeft != 0) {
          throw const FileCorruptedError('invalid final hashed block');
        }
        break;
      }
      final data = reader.readBytes(size);
      builder.add(data);

      if (!ListEquality().equals(hash, sha256.convert(data).bytes)) {
        throw FileCorruptedError('invalid block hash');
      }
    }

    return builder.toBytes();
  }
}


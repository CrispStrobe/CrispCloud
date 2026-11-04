import 'dart:convert';
import 'dart:typed_data';

import '../../io/byte_source.dart';
import '../zip/deflate_codec.dart';
import '../zip/zip_reader.dart';
import '../zip/zip_writer.dart';

/// Recovers ZIP members when the central directory or file prefix is damaged.
abstract final class ZipRecovery {
  static const int _local = 0x04034b50;

  /// First `PK\x03\x04` offset, or -1.
  static int firstLocalHeader(Uint8List bytes) {
    for (int i = 0; i + 4 <= bytes.length; i++) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x03 &&
          bytes[i + 3] == 0x04) {
        return i;
      }
    }
    return -1;
  }

  /// stripLeadingJunk API.
  static Uint8List stripLeadingJunk(Uint8List bytes) {
    final int start = firstLocalHeader(bytes);
    if (start <= 0) {
      return bytes;
    }
    return Uint8List.sublistView(bytes, start);
  }

  /// tryOpen API.
  static ZipReader? tryOpen(Uint8List bytes) {
    return ZipReader.tryOpen(MemoryByteSource(bytes));
  }

  /// Rebuilds a ZIP by walking local file headers (used when EOCD is gone).
  static Uint8List? rebuildFromLocalHeaders(Uint8List bytes) {
    final List<({String name, Uint8List data})> members = scanLocalMembers(
      bytes,
    );
    if (members.isEmpty) {
      return null;
    }
    final ZipWriter writer = ZipWriter();
    for (final ({String name, Uint8List data}) m in members) {
      writer.addFile(m.name, m.data);
    }
    return writer.close();
  }

  /// scanLocalMembers API.
  static List<({String name, Uint8List data})> scanLocalMembers(
    Uint8List bytes,
  ) {
    final List<({String name, Uint8List data})> out =
        <({String name, Uint8List data})>[];
    var i = 0;
    while (i + 30 <= bytes.length) {
      final int sig =
          bytes[i] |
          (bytes[i + 1] << 8) |
          (bytes[i + 2] << 16) |
          (bytes[i + 3] << 24);
      if (sig != _local) {
        i++;
        continue;
      }
      final ByteCursor c = ByteCursor(bytes, offset: i);
      c.u32le();
      c.u16le();
      final int flags = c.u16le();
      final int method = c.u16le();
      c.skip(4);
      c.u32le(); // crc
      int comp = c.u32le();
      final int uncomp = c.u32le();
      final int nameLen = c.u16le();
      final int extraLen = c.u16le();
      if (i + 30 + nameLen + extraLen > bytes.length) {
        break;
      }
      final String name = utf8.decode(
        Uint8List.sublistView(bytes, i + 30, i + 30 + nameLen),
        allowMalformed: true,
      );
      final int dataStart = i + 30 + nameLen + extraLen;
      if ((flags & 8) != 0 && comp == 0) {
        final int next = _nextSignature(bytes, dataStart);
        if (next < 0) {
          break;
        }
        comp = next - dataStart;
        if (comp >= 16 &&
            bytes[next - 16] == 0x50 &&
            bytes[next - 15] == 0x4B &&
            bytes[next - 14] == 0x07 &&
            bytes[next - 13] == 0x08) {
          comp -= 16;
        } else if (comp >= 12) {
          // data descriptor without signature
        }
      }
      if (comp < 0 || dataStart + comp > bytes.length) {
        i++;
        continue;
      }
      final Uint8List payload = Uint8List.sublistView(
        bytes,
        dataStart,
        dataStart + comp,
      );
      Uint8List raw;
      try {
        raw = method == zipMethodDeflate
            ? RawDeflate.inflate(payload)
            : Uint8List.fromList(payload);
      } on Object {
        raw = Uint8List.fromList(payload);
      }
      if (uncomp > 0 && raw.length > uncomp) {
        raw = Uint8List.sublistView(raw, 0, uncomp);
      }
      if (name.isNotEmpty && !name.endsWith('/')) {
        out.add((name: name, data: raw));
      }
      i = dataStart + comp;
    }
    return out;
  }

  static int _nextSignature(Uint8List bytes, int from) {
    for (int i = from; i + 4 <= bytes.length; i++) {
      if (bytes[i] != 0x50 || bytes[i + 1] != 0x4B) {
        continue;
      }
      final int a = bytes[i + 2];
      final int b = bytes[i + 3];
      if ((a == 0x03 && b == 0x04) ||
          (a == 0x01 && b == 0x02) ||
          (a == 0x05 && b == 0x06) ||
          (a == 0x06 && b == 0x06)) {
        return i;
      }
    }
    return -1;
  }
}

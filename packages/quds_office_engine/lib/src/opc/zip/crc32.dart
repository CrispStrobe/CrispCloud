import 'dart:typed_data';

/// IEEE CRC-32 as used by ZIP and PNG.
abstract final class Crc32 {
  static final Uint32List _table = _buildTable();

  /// compute API.
  static int compute(List<int> data, [int crc = 0]) {
    int c = crc ^ 0xFFFFFFFF;
    for (int i = 0; i < data.length; i++) {
      c = _table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static Uint32List _buildTable() {
    final Uint32List table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        if ((c & 1) != 0) {
          c = 0xEDB88320 ^ (c >> 1);
        } else {
          c >>= 1;
        }
      }
      table[i] = c;
    }
    return table;
  }
}

import 'dart:typed_data';

/// IEEE CRC-32 as used by ZIP and PNG.
abstract final class Crc32 {
  static final Uint32List _table = _buildTable();

  /// compute API.
  static int compute(List<int> data, [int crc = 0]) {
    int c = crc ^ 0xFFFFFFFF;
    final length = data.length;
    var offset = 0;
    if (data is Uint8List && length >= 4 && crc >= 0 && crc <= 0xFFFFFFFF) {
      // Each table advances a byte by a different number of CRC steps.
      // Combining eight independent lookups cuts the loop-carried
      // dependencies. Two 32-bit loads support unaligned sublists and web.
      final words = ByteData.sublistView(data);
      final bulkEnd = length & ~7;
      while (offset < bulkEnd) {
        final low = c ^ words.getUint32(offset, Endian.little);
        final high = words.getUint32(offset + 4, Endian.little);
        c =
            _table[1792 + (low & 0xFF)] ^
            _table[1536 + ((low >>> 8) & 0xFF)] ^
            _table[1280 + ((low >>> 16) & 0xFF)] ^
            _table[1024 + (low >>> 24)] ^
            _table[768 + (high & 0xFF)] ^
            _table[512 + ((high >>> 8) & 0xFF)] ^
            _table[256 + ((high >>> 16) & 0xFF)] ^
            _table[high >>> 24];
        offset += 8;
      }
      final end = length & ~3;
      if (offset < end) {
        final word = c ^ words.getUint32(offset, Endian.little);
        c =
            _table[768 + (word & 0xFF)] ^
            _table[512 + ((word >>> 8) & 0xFF)] ^
            _table[256 + ((word >>> 16) & 0xFF)] ^
            _table[word >>> 24];
        offset += 4;
      }
    }
    for (; offset < length; offset++) {
      c = _table[(c ^ data[offset]) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static Uint32List _buildTable() {
    final Uint32List table = Uint32List(8 * 256);
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
    for (var slice = 1; slice < 8; slice++) {
      for (var byte = 0; byte < 256; byte++) {
        final previous = table[(slice - 1) * 256 + byte];
        table[slice * 256 + byte] = table[previous & 0xFF] ^ (previous >>> 8);
      }
    }
    return table;
  }
}

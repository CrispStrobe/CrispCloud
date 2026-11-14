// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'structured_word_fixture.dart';

/// Count-prefixed FIB records with independent compatibility copies. Unknown
/// trailing FIB words deliberately contain nonzero bytes; they are not DOP
/// flags and must never gain layout semantics from their mere presence.
Uint8List fibExtensionFixture({
  int words = 7,
  int newVersion = 0x10c,
  int pairCount = 183,
  int dopLength = 674,
  bool truncateExtension = false,
}) {
  final dop = Uint8List(dopLength);
  final data = ByteData.sublistView(dop);
  data.setUint16(8, 0x2000, Endian.little);
  data.setUint32(84, 0x2000, Endian.little);
  if (dopLength >= 540) {
    data.setUint32(508, 0x2000, Endian.little);
    data.setUint32(512, 1, Endian.little);
  }
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('Bounded FIB\r')],
    extraTablePairs: {31: dop},
  ).build(
    mutate: (fib, _) {
      fib.setUint16(152, pairCount, Endian.little);
      final at = 154 + pairCount * 8;
      fib.setUint16(at, words, Endian.little);
      if (words != 0) fib.setUint16(at + 2, newVersion, Endian.little);
      for (var i = 1; i < words; i++) {
        fib.setUint16(
          at + 2 + i * 2,
          i < (newVersion == 0x112 ? 5 : 2) ? 0 : 0xbeef,
          Endian.little,
        );
      }
      if (truncateExtension) {
        fib.setUint32(64, at + 2 + words * 2 - 1, Endian.little);
      }
    },
  );
}

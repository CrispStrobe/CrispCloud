// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/src/compound/byte_source.dart';
import 'package:test/test.dart';

void main() {
  for (final alignment in [4, 8]) {
    test('byte sink drains and reuses with $alignment-byte alignment', () {
      final sink = ByteSink()..add([1, 2, 3]);
      expect(sink.length, 3);
      expect(sink.toBytes(), [1, 2, 3]);
      expect(sink.length, 3);
      final first = sink.takeBytes();
      expect(first, [1, 2, 3]);
      expect(sink.length, 0);
      for (var attempt = 0; attempt < 3; attempt++) {
        expect(sink.takeBytes(), isEmpty);
        expect(sink.length, 0);
      }
      sink.padTo(alignment, 0xaa);
      expect(sink.toBytes(), isEmpty);
      expect(sink.length, 0);

      sink.u8(0x42);
      sink.u16le(0x1234);
      expect(sink.toBytes(), [0x42, 0x34, 0x12]);
      expect(sink.length, 3);
      sink.padTo(alignment, 0xcc);
      final expected = [0x42, 0x34, 0x12, ...List.filled(alignment - 3, 0xcc)];
      expect(sink.length, alignment);
      expect(sink.toBytes(), expected);
      expect(sink.length, alignment);
      final second = sink.takeBytes();
      expect(second, expected);
      expect(sink.length, 0);

      sink.u8(0x99);
      expect(first, [1, 2, 3]);
      expect(second, expected);
      expect(sink.length, 1);
      expect(sink.takeBytes(), [0x99]);
      expect(sink.length, 0);
      expect(sink.takeBytes(), isEmpty);
      expect(sink.length, 0);
    });
  }
}

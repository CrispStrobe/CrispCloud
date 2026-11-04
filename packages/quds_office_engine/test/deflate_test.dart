import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('RawDeflate', () {
    test('round-trips empty, short, and repetitive payloads', () {
      final List<Uint8List> samples = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(utf8.encode('a')),
        Uint8List.fromList(utf8.encode('Hello, Quds Office Suite')),
        Uint8List.fromList(utf8.encode('abababababababababababab')),
        Uint8List.fromList(List<int>.generate(4000, (int i) => i % 251)),
      ];
      for (final Uint8List sample in samples) {
        final Uint8List compressed = RawDeflate.deflate(sample);
        final Uint8List expanded = RawDeflate.inflate(compressed);
        expect(expanded, sample, reason: 'len=${sample.length}');
      }
    });

    test('inflates a zlib raw-DEFLATE stream (dynamic Huffman)', () {
      const String hex =
          'f348cdc9c9d751082c4d2956f04f4bcb4c4e55082ecd2c4955f0189518951895182e1200';
      final Uint8List raw = Uint8List.fromList(<int>[
        for (int i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      final Uint8List got = RawDeflate.inflate(raw);
      expect(utf8.decode(got), 'Hello, Quds Office Suite ' * 40);
    });

    test('inflates Office-style dynamic Huffman with long codes', () {
      const String hex =
          'edd6310ac2300085e1dd53e406ee256412c722880728259422b52506727d89077070fe96377dd39bfed88623c536943e35dd6b996a5ed6395ccbb4e5b69767788c975b78e7b9aefb2b00000000000000c00f10cfbd2afb96ef1ee9141527000000000000a03801000000000000c509000000000000008a13000000000000509c00000000000080e27425000000000000a03801000000000000c509000000000000284e57020000000000008a13000000000000509c00000000000080e2549c00000000000080e204000000000000142700000000000000284e0000000000004071020000000000008ad39500000000000080e2040000000000001427000000000000a0383d05000000000000284e0000000000004071020000000000008a5371020000000000008a13000000000000509c00000000000000a03801000000000000c509000000000000284e57020000000000008a13000000000000509c00000000000080e2f414000000000000a03801000000000000c509000000000000284ec509000000000000284e00000000000040710200000000000080e2040000000000001427000000000000a0385d09000000000000fc559c1f';
      final Uint8List raw = Uint8List.fromList(<int>[
        for (int i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      final String got = utf8.decode(RawDeflate.inflate(raw));
      expect(
        got,
        startsWith('<w:p><w:r><w:t>Strategic Framework UNDP section '),
      );
      expect(got.length, 106960);
    });
  });
}

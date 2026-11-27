import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('PDF Flate limits zlib-wrapped output', () {
    final data = Uint8List.fromList(utf8.encode('Office stream ' * 200));
    final compressed = PdfFlate.compress(data);
    expect(PdfFlate.decompress(compressed, maxOutputBytes: data.length), data);
    expect(
      () => PdfFlate.decompress(compressed, maxOutputBytes: data.length - 1),
      throwsA(
        isA<PdfOpenException>().having(
          (error) => error.error,
          'error',
          PdfOpenError.limit,
        ),
      ),
    );
  });

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

    test('matches unaligned overlapping data and short trailing ranges', () {
      for (final period in [1, 2, 3, 5, 7, 11]) {
        for (var tail = 0; tail < 8; tail++) {
          final bytes = Uint8List(260 + period + tail + 3);
          final data = Uint8List.sublistView(bytes, 1, bytes.length - 2);
          for (var i = 0; i < data.length; i++) {
            data[i] = i % period;
          }
          data[data.length - 1] = 255;
          final compressed = RawDeflate.deflate(data);
          expect(RawDeflate.inflate(compressed), data);
        }
      }
    });

    test('retains matches at the exact window boundary', () {
      final token = List<int>.generate(24, (index) => index + 1);
      for (final (level, window) in [(6, 4096), (9, 32768)]) {
        final data = Uint8List(window + token.length)
          ..setRange(0, token.length, token)
          ..setRange(window, window + token.length, token);
        final compressed = RawDeflate.deflate(data, level: level);
        expect(RawDeflate.inflate(compressed), data);
        expect(
          () => RawDeflate.inflatePrefix(
            compressed,
            maxOutputBytes: data.length,
            windowBytes: window - 1,
          ),
          throwsA(isA<ZipDeflateException>()),
        );
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

    test('prefix inflation stops at the end of a fixed Huffman stream', () {
      final data = Uint8List.fromList(
        List<int>.generate(4096, (index) => index % 3),
      );
      final compressed = RawDeflate.deflate(data);
      final input = Uint8List.fromList([...compressed, 0xFF, 0xFF, 0xFF]);
      final result = RawDeflate.inflatePrefix(
        input,
        maxOutputBytes: data.length,
      );
      expect(result.bytes, data);
      expect(result.consumed, compressed.length);
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

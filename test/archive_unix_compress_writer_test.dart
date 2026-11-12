import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_unix_compress_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_unix_compress_writer_fixtures.dart';

void main() {
  final payloads = unixCompressWriterPayloads();
  for (final width in [12, 14, 16]) {
    for (final item in payloads.entries) {
      test('block $width-bit ${item.key} round-trips with bounded output', () {
        final encoded = encodeArchiveUnixCompress(item.value, maxBits: width);
        expect(encoded.sublist(0, 3), [0x1f, 0x9d, 0x80 | width]);
        expect(decodeArchiveUnixCompress(encoded), item.value);
        if (item.value.isEmpty) expect(encoded.length, 3);
        if (item.key == 'phrases' || item.key == 'text') {
          expect(encoded.length, lessThan(item.value.length ~/ 10));
        }
        expect(
          encodeArchiveUnixCompress(
            item.value,
            maxBits: width,
            maxOutputBytes: encoded.length,
          ),
          encoded,
        );
        expect(
          () => encodeArchiveUnixCompress(
            item.value,
            maxBits: width,
            maxOutputBytes: encoded.length - 1,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }
  }

  test('canonical rewrite uses 14-bit block coding', () {
    expect(encodeArchiveUnixCompress(Uint8List(0)), [0x1f, 0x9d, 0x8e]);
  });

  test('refuses unsupported dictionary sizes and output limits', () {
    for (final width in [8, 9, 10, 11, 13, 15, 17]) {
      expect(
        () => encodeArchiveUnixCompress(Uint8List(0), maxBits: width),
        throwsArgumentError,
      );
    }
    for (final limit in [-1, 0, kArchiveReadLimit + 1]) {
      expect(
        () => encodeArchiveUnixCompress(Uint8List(0), maxOutputBytes: limit),
        throwsArgumentError,
      );
    }
  });

  test('refuses more than 64 MiB of source before compression', () {
    expect(
      () => encodeArchiveUnixCompress(Uint8List(kArchiveReadLimit + 1)),
      throwsA(isA<ArchiveViewException>()),
    );
  });
}

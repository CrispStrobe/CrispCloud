import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_adc_codec.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _literals(List<int> bytes) {
  final result = BytesBuilder();
  for (var i = 0; i < bytes.length; i += 128) {
    final end = (i + 128).clamp(0, bytes.length);
    result.addByte(0x80 | (end - i - 1));
    result.add(bytes.sublist(i, end));
  }
  return result.takeBytes();
}

void main() {
  test('decodes independently sourced hdiutil stream exactly', () {
    final packed = File('test/fixtures/archives/dmg-codecs/apple-hdiutil.adc')
        .readAsBytesSync();
    final expected = File('test/fixtures/archives/dmg-codecs/apple-hdiutil.bin')
        .readAsBytesSync();
    expect(decodeArchiveAdc(packed, expectedBytes: expected.length), expected);
  });

  test('decodes empty and maximum literal runs', () {
    expect(decodeArchiveAdc(Uint8List(0), expectedBytes: 0), isEmpty);
    final plain = List<int>.generate(257, (i) => i & 255);
    expect(decodeArchiveAdc(_literals(plain), expectedBytes: 257), plain);
  });

  test('short matches can overlap their own output', () {
    final encoded = Uint8List.fromList([0x82, 10, 20, 30, 0x04, 2]);
    expect(decodeArchiveAdc(encoded, expectedBytes: 7), [
      10,
      20,
      30,
      10,
      20,
      30,
      10,
    ]);
  });

  test('long matches can overlap their own output', () {
    final encoded = Uint8List.fromList([0x80, 23, 0x7f, 0, 0]);
    expect(decodeArchiveAdc(encoded, expectedBytes: 68), List.filled(68, 23));
  });

  for (final distance in [1024, 65536]) {
    test(
      'supports the maximum ${distance == 1024 ? 'short' : 'long'} distance',
      () {
        final history = List<int>.generate(distance, (i) => i % 251);
        final token = distance == 1024 ? [0x03, 0xff] : [0x40, 0xff, 0xff];
        final count = distance == 1024 ? 3 : 4;
        final encoded = Uint8List.fromList([..._literals(history), ...token]);
        expect(decodeArchiveAdc(encoded, expectedBytes: distance + count), [
          ...history,
          ...history.take(count),
        ]);
      },
    );
  }

  final malformed = <String, (List<int>, int)>{
    'truncated literal': ([0x81, 1], 2),
    'missing short operand': ([0x00], 3),
    'missing long operand': ([0x40, 0], 4),
    'short match before history': ([0, 0], 3),
    'long match before history': ([0x40, 0, 0], 4),
    'match beyond history': ([0x80, 1, 0, 1], 4),
    'literal exceeds expected length': ([0x81, 1, 2], 1),
    'match exceeds expected length': ([0x80, 1, 0x7f, 0, 0], 67),
    'valid prefix ends before declared length': ([0x80, 1], 2),
    'extra encoded bytes after exact output': ([0x80, 1, 0x80, 2], 1),
    'nonempty encoded data for zero output': ([0x80, 1], 0),
  };
  for (final entry in malformed.entries) {
    test('rejects ${entry.key}', () {
      expect(
        () => decodeArchiveAdc(
          Uint8List.fromList(entry.value.$1),
          expectedBytes: entry.value.$2,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    });
  }

  test('rejects output above fixed ceiling before allocation', () {
    expect(
      () => decodeArchiveAdc(
        Uint8List(0),
        expectedBytes: kArchiveAdcChunkLimit + 1,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(
      () => decodeArchiveAdc(Uint8List(0), expectedBytes: -1),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('caller can lower but cannot raise the decoder ceiling', () {
    expect(
      () => decodeArchiveAdc(Uint8List(0), expectedBytes: 2, maxOutputBytes: 1),
      throwsA(isA<ArchiveViewException>()),
    );
    for (final limit in [0, -1, kArchiveAdcChunkLimit + 1]) {
      expect(
        () => decodeArchiveAdc(
          Uint8List(0),
          expectedBytes: 0,
          maxOutputBytes: limit,
        ),
        throwsArgumentError,
      );
    }
  });
}

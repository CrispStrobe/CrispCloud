import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/outlook_rtf_compression.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/outlook_rtf_fixture.dart';

Matcher _failure(OutlookRtfErrorCode code) => throwsA(
  isA<OutlookRtfException>().having((error) => error.code, 'code', code),
);

void main() {
  test(
    'Microsoft overlapping-match golden vector includes its published CRC',
    () {
      // [MS-OXRTFCP] 3.1.2.2 header; 3.2.2.2/3 runs. No fixture CRC generation.
      final packet = Uint8List.fromList([
        0x1a,
        0,
        0,
        0,
        0x1c,
        0,
        0,
        0,
        0x4c,
        0x5a,
        0x46,
        0x75,
        0xe2,
        0xd4,
        0x4b,
        0x51,
        0x41,
        0,
        4,
        0x20,
        0x57,
        0x58,
        0x59,
        0x5a,
        0x0d,
        0x6e,
        0x7d,
        1,
        0x0e,
        0xb0,
      ]);
      expect(
        latin1.decode(decompressOutlookRtf(packet)),
        r'{\rtf1 WXYZWXYZWXYZWXYZWXYZ}',
      );
      packet[18] ^= 1;
      expect(
        () => decompressOutlookRtf(packet),
        _failure(OutlookRtfErrorCode.malformed),
      );
    },
  );

  test('literal and MELA bodies retain bytes and return immutable data', () {
    const rtf = r'{\rtf1\ansi Hello \b formatted\b0  body}';
    for (final raw in [false, true]) {
      final result = decompressOutlookRtf(
        literalOutlookRtf(rtf, uncompressed: raw),
      );
      expect(latin1.decode(result), rtf);
      expect(() => result[0] = 0, throwsUnsupportedError);
    }
  });

  test(
    'MELA must ignore CRC and uses the recommended read-to-end behavior',
    () {
      final packet = literalOutlookRtf(r'{\rtf1 raw}', uncompressed: true);
      ByteData.sublistView(packet)
        ..setUint32(4, 1, Endian.little)
        ..setUint32(12, 0x12345678, Endian.little);
      expect(latin1.decode(decompressOutlookRtf(packet)), r'{\rtf1 raw}');
    },
  );

  test('dictionary wrap and an overlapping reference across its boundary', () {
    final literals = [...List<int>.filled(3885, 0x58), 0x41, 0x42];
    final packet = outlookRtfPacket(
      outlookRtfRuns([...literals, -0xffc4 - 1, -0x0040 - 1]),
      literals.length + 6,
    );
    expect(decompressOutlookRtf(packet), [
      ...literals,
      ...ascii.encode('ABABAB'),
    ]);
  });

  test('compressed padding participates in CRC after the end marker', () {
    final contents = [
      ...outlookRtfRuns([0x41, -0x0d00 - 1]),
      0x12,
      0xff,
    ];
    final packet = outlookRtfPacket(contents, 1);
    expect(decompressOutlookRtf(packet), [0x41]);
    packet[packet.length - 1] = 0;
    expect(
      () => decompressOutlookRtf(packet),
      _failure(OutlookRtfErrorCode.malformed),
    );
  });

  test('specified empty stream and empty MELA are accepted', () {
    expect(decompressOutlookRtf(outlookRtfPacket([2, 0, 0x0d, 0], 0)), isEmpty);
    expect(
      decompressOutlookRtf(outlookRtfPacket([], 0, uncompressed: true)),
      isEmpty,
    );
  });

  test(
    'truncation, missing end, unknown dictionary and raw-size mismatches fail',
    () {
      final packets = [
        Uint8List(15),
        outlookRtfPacket([1, 0], 1),
        outlookRtfPacket([0, 0x41], 1),
        outlookRtfPacket([1, 0xff, 0xf0], 2),
        outlookRtfPacket([1, 0x0c, 0xf0], 3),
        outlookRtfPacket([0, 0x41], 0),
        outlookRtfPacket(outlookRtfRuns([0x41, -0x0d00 - 1]), 2),
      ];
      final wrongSize = literalOutlookRtf('A');
      wrongSize[0]++;
      packets.add(wrongSize);
      for (final packet in packets) {
        expect(
          () => decompressOutlookRtf(packet),
          _failure(OutlookRtfErrorCode.malformed),
        );
      }
    },
  );

  test('unknown compression and oversized raw data fail before allocation', () {
    final unknown = literalOutlookRtf('A');
    unknown[8] = 0;
    expect(
      () => decompressOutlookRtf(unknown),
      _failure(OutlookRtfErrorCode.unsupportedCompression),
    );
    final oversized = outlookRtfPacket([1, 0x0c, 0xf0], kOutlookRtfLimit + 1);
    expect(
      () => decompressOutlookRtf(oversized),
      _failure(OutlookRtfErrorCode.resourceLimit),
    );
  });
}

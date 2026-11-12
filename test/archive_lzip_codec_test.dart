import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/services/archive_lzip_codec.dart';
import 'package:crisp_cloud/services/archive_lzma_codec.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _randomData(int size) {
  var value = 0x13579bdf;
  return Uint8List.fromList(
    List.generate(size, (_) {
      value = (value * 1664525 + 1013904223) & 0xffffffff;
      return value >> 24;
    }),
  );
}

Uint8List _reference(String name) =>
    File('test/fixtures/archives/lzip-reference-$name.lz').readAsBytesSync();

List<int> _word(int value) => [
  for (var i = 0; i < 4; i++) value >> (8 * i) & 0xff,
];

void main() {
  final rejects = throwsA(isA<ArchiveViewException>());
  final payloads = {
    'default': _bytes('Independent Lzip reference fixture\n' * 5000),
    'distance': Uint8List.fromList([
      for (var i = 0; i < 4; i++) ..._randomData(8192),
    ]),
    'tiny': _bytes('x'),
    'empty': Uint8List(0),
  };

  for (final entry in payloads.entries) {
    test('reads libarchive/liblzma ${entry.key} reference', () {
      expect(decodeArchiveLzip(_reference(entry.key)), entry.value);
    });
  }

  test('combines complete nonempty members in original order', () {
    final source = Uint8List.fromList([
      ..._reference('default'),
      ..._reference('distance'),
      ..._reference('tiny'),
    ]);
    final expected = Uint8List.fromList([
      ...payloads['default']!,
      ...payloads['distance']!,
      ...payloads['tiny']!,
    ]);
    expect(
      decodeArchiveLzip(source, maxOutputBytes: expected.length),
      expected,
    );
    expect(
      () => decodeArchiveLzip(source, maxOutputBytes: expected.length - 1),
      rejects,
    );
  });

  test('enforces the no-empty-member rule in collections', () {
    for (final members in [
      ['empty', 'tiny'],
      ['tiny', 'empty'],
      ['empty', 'empty'],
    ]) {
      expect(
        () => decodeArchiveLzip(
          Uint8List.fromList([
            for (final member in members) ..._reference(member),
          ]),
        ),
        rejects,
      );
    }
    expect(decodeArchiveLzip(_reference('empty'), maxOutputBytes: 0), isEmpty);
  });

  test(
    'requires exactly bounded members and refuses ignored trailing data',
    () {
      final source = _reference('default');
      for (var size = 0; size < source.length; size++) {
        expect(
          () => decodeArchiveLzip(Uint8List.sublistView(source, 0, size)),
          rejects,
          reason: 'accepted truncated $size/${source.length}',
        );
      }
      for (final tail in [
        <int>[0],
        List.filled(36, 0),
        _bytes('opaque metadata'),
      ]) {
        expect(
          () => decodeArchiveLzip(Uint8List.fromList([...source, ...tail])),
          rejects,
        );
      }
    },
  );

  test(
    'validates CRC, decoded size, member size and both uint64 upper words',
    () {
      final source = _reference('default');
      for (final offset in [20, 16, 12, 8, 4]) {
        final bad = Uint8List.fromList(source)..[source.length - offset] ^= 1;
        expect(() => decodeArchiveLzip(bad), rejects);
      }
      final zeroMember = Uint8List.fromList(source)
        ..fillRange(source.length - 8, source.length, 0);
      expect(() => decodeArchiveLzip(zeroMember), rejects);
      final hugeDecoded = Uint8List.fromList(source);
      ByteData.sublistView(hugeDecoded)
          .setUint32(source.length - 16, kArchiveReadLimit + 1, Endian.little);
      expect(() => decodeArchiveLzip(hugeDecoded), rejects);
    },
  );

  test('rejects unsupported versions and invalid dictionary codes', () {
    final source = _reference('tiny');
    for (final version in [0, 2, 255]) {
      expect(
        () => decodeArchiveLzip(Uint8List.fromList(source)..[4] = version),
        rejects,
      );
    }
    for (final dictionary in [0, 11, 30, 31, 0x2c, 27, 29]) {
      expect(
        () => decodeArchiveLzip(Uint8List.fromList(source)..[5] = dictionary),
        rejects,
      );
    }
    expect(
      () => decodeArchiveLzip(Uint8List.fromList(source)..[0] ^= 1),
      rejects,
    );
  });

  test(
    'decodes fractional dictionaries and enforces actual match distance',
    () {
      final source = _reference('default');
      // 0xd3 encodes 512 KiB minus 6/16, or 320 KiB.
      expect(
        decodeArchiveLzip(Uint8List.fromList(source)..[5] = 0xd3),
        payloads['default'],
      );
      // The upper supported 64 MiB declaration does not trigger a large
      // dictionary allocation for this small-output stream.
      expect(decodeArchiveLzip(_reference('tiny')..[5] = 26), payloads['tiny']);
      final tooSmall = _reference('distance')..[5] = 12;
      expect(() => decodeArchiveLzip(tooSmall), rejects);
    },
  );

  test('requires EOS even when trailer size and checksum otherwise match', () {
    final expected = _bytes('Missing EOS must not be accepted ' * 100);
    final noMarker = encodeArchiveLzma(expected);
    final payload = Uint8List.sublistView(noMarker, 13);
    final invalid = Uint8List.fromList([
      ...ascii.encode('LZIP'),
      1,
      23,
      ...payload,
      ..._word(codecs.getCrc32(expected)),
      ..._word(expected.length),
      0,
      0,
      0,
      0,
      ..._word(6 + payload.length + 20),
      0,
      0,
      0,
      0,
    ]);
    expect(() => decodeArchiveLzip(invalid), rejects);
  });

  test('rejects data hidden before a correctly adjusted trailer', () {
    final source = _reference('default');
    final extra = Uint8List.fromList([
      ...source.take(source.length - 20),
      0,
      ...source.skip(source.length - 20),
    ]);
    ByteData.sublistView(extra)
        .setUint32(extra.length - 8, extra.length, Endian.little);
    expect(() => decodeArchiveLzip(extra), rejects);
  });

  test('bounds member count before expansion and validates caller limits', () {
    final tiny = _reference('tiny');
    final excessive = Uint8List.fromList([
      for (var i = 0; i < 4097; i++) ...tiny,
    ]);
    expect(() => decodeArchiveLzip(excessive), rejects);
    expect(() => decodeArchiveLzip(tiny, maxOutputBytes: 0), rejects);
    expect(
      () => decodeArchiveLzip(tiny, maxOutputBytes: -1),
      throwsArgumentError,
    );
    expect(
      () => decodeArchiveLzip(tiny, maxOutputBytes: kArchiveReadLimit + 1),
      throwsArgumentError,
    );
  });
}

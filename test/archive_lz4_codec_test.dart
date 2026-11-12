import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_lz4_codec.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _randomData(int size) {
  var value = 0x13579bdf;
  return Uint8List.fromList(
    List.generate(size, (_) {
      value = (value * 1664525 + 1013904223) & 0xffffffff;
      return value >> 24;
    }),
  );
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _reference(String name) =>
    File('test/fixtures/archives/lz4-reference-$name.lz4').readAsBytesSync();

List<int> _word(int value) => [
  for (var i = 0; i < 4; i++) value >> (8 * i) & 0xff,
];

Uint8List _frame(
  List<List<int>> blocks, {
  bool independent = true,
  bool stored = false,
  int? contentSize,
  int blockCode = 4,
}) {
  final descriptor = Uint8List.fromList([
    0x40 | (independent ? 0x20 : 0) | (contentSize == null ? 0 : 8),
    blockCode << 4,
    if (contentSize != null) ...[..._word(contentSize), 0, 0, 0, 0],
  ]);
  return Uint8List.fromList([
    4,
    0x22,
    0x4d,
    0x18,
    ...descriptor,
    archiveLz4Xxh32(descriptor) >> 8 & 0xff,
    for (final block in blocks) ...[
      ..._word(block.length | (stored ? 0x80000000 : 0)),
      ...block,
    ],
    0,
    0,
    0,
    0,
  ]);
}

void _repairHeader(Uint8List bytes) {
  final headerEnd = 6 + (bytes[4] & 8 != 0 ? 8 : 0);
  bytes[headerEnd] =
      archiveLz4Xxh32(Uint8List.sublistView(bytes, 4, headerEnd)) >> 8 & 0xff;
}

void main() {
  final rejects = throwsA(isA<ArchiveViewException>());
  final linkedPayload = Uint8List.fromList([
    for (var i = 0; i < 40; i++) ..._randomData(8192),
    ...utf8.encode('tail'),
  ]);
  final referencePayloads = {
    'linked': linkedPayload,
    'independent': _bytes('Independent LZ4 reference fixture\n' * 10000),
    'unchecked': Uint8List.fromList([
      for (var i = 0; i < 40; i++) ...List.generate(256, (byte) => byte),
      ...utf8.encode('end'),
    ]),
    'stored': _randomData(8192),
    'empty': Uint8List(0),
  };

  test('XXH32 agrees with independent libxxhash vectors', () {
    // Generated with libxxhash XXH32; covers short/striped/seeded arithmetic.
    expect(archiveLz4Xxh32(Uint8List(0)), 0x02cc5d05);
    expect(archiveLz4Xxh32(_bytes('a')), 0x550d7456);
    expect(archiveLz4Xxh32(_bytes('abc')), 0x32d153ff);
    final allBytes = Uint8List.fromList(List.generate(256, (i) => i));
    expect(archiveLz4Xxh32(allBytes), 0x59441253);
    expect(archiveLz4Xxh32(allBytes, seed: 0xffffffff), 0x3ee648a9);
    expect(
      archiveLz4Xxh32(_bytes('12345678901234567'), seed: 0x13579bdf),
      0xe520d479,
    );
  });

  for (final entry in referencePayloads.entries) {
    test('reads independent liblz4 ${entry.key} fixture', () {
      final decoded = decodeArchiveLz4(_reference(entry.key));
      expect(decoded.bytes, entry.value);
      expect(decoded.frameCount, 1);
      expect(decoded.skippableFrameCount, 0);
      expect(decoded.canRewrite, isTrue);
      expect(decoded.hasLinkedBlocks, entry.key == 'linked');
      expect(decoded.hasBlockChecksums, entry.key != 'unchecked');
      expect(decoded.hasContentChecksums, entry.key != 'unchecked');
    });
  }

  test('linked reference actually uses the previous block dictionary', () {
    final bytes = _reference('linked')..[4] |= 0x20;
    _repairHeader(bytes);
    expect(() => decodeArchiveLz4(bytes), rejects);
  });

  test('creates real compression across multiple independent blocks', () {
    final source = _bytes('CrispCloud LZ4 compression\n' * 30000);
    final packed = encodeArchiveLz4(source);
    expect(packed.length, lessThan(source.length ~/ 100));
    final decoded = decodeArchiveLz4(packed);
    expect(decoded.bytes, source);
    expect(decoded.hasLinkedBlocks, isFalse);
    expect(decoded.hasBlockChecksums, isTrue);
    expect(decoded.hasContentChecksums, isTrue);
  });

  test('round-trips incompressible and block-boundary lengths', () {
    for (final size in [0, 1, 4, 5, 12, 13, 15, 270, 65536, 262143, 262145]) {
      final source = _randomData(size);
      expect(decodeArchiveLz4(encodeArchiveLz4(source)).bytes, source);
    }
  });

  for (final compress in [true, false]) {
    test(
      'liblz4 independently decodes writer output (compress=$compress)',
      () async {
        final directory = await Directory.systemTemp.createTemp('crisp-lz4-');
        addTearDown(() => directory.delete(recursive: true));
        for (final entry in {
          'empty': Uint8List(0),
          'short': _bytes('short'),
          'repeated': linkedPayload,
          'random': _randomData(270003),
        }.entries) {
          final source = File('${directory.path}/${entry.key}.bin');
          final packed = File('${directory.path}/${entry.key}.lz4');
          await source.writeAsBytes(entry.value);
          await packed.writeAsBytes(
            encodeArchiveLz4(entry.value, compress: compress),
          );
          final result = await Process.run('python3', [
            'test/support/check_archive_lz4.py',
            'verify',
            packed.path,
            source.path,
          ]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        }
      },
    );
  }

  test('enforces decoded, encoded, and declared size bounds', () {
    final source = _bytes('A' * 1000);
    final packed = encodeArchiveLz4(source);
    expect(decodeArchiveLz4(packed, maxOutputBytes: 1000).bytes, source);
    expect(() => decodeArchiveLz4(packed, maxOutputBytes: 999), rejects);
    expect(() => encodeArchiveLz4(source, maxOutputBytes: 20), rejects);
    expect(
      () => decodeArchiveLz4(packed, maxOutputBytes: -1),
      throwsArgumentError,
    );
    expect(
      () => encodeArchiveLz4(source, maxOutputBytes: kArchiveReadLimit + 1),
      throwsArgumentError,
    );
    final tooLarge = Uint8List.fromList(packed)..[10] = 1;
    _repairHeader(tooLarge);
    expect(() => decodeArchiveLz4(tooLarge), rejects);
    final wrongSize = Uint8List.fromList(packed)..[6] ^= 1;
    _repairHeader(wrongSize);
    expect(() => decodeArchiveLz4(wrongSize), rejects);
    final noSize = _frame([source], stored: true);
    expect(() => decodeArchiveLz4(noSize, maxOutputBytes: 999), rejects);
  });

  test('verifies header, block and content checksums', () {
    final packed = encodeArchiveLz4(_bytes('checksum content' * 100));
    final firstBlockLength =
        ByteData.sublistView(packed).getUint32(15, Endian.little) & 0x7fffffff;
    for (final location in [14, 19 + firstBlockLength, packed.length - 1]) {
      final corrupt = Uint8List.fromList(packed)..[location] ^= 0x80;
      expect(() => decodeArchiveLz4(corrupt), rejects);
    }
  });

  test('rejects every truncated prefix of a small complete frame', () {
    final packed = encodeArchiveLz4(_bytes('CrispCloud LZ4\n' * 20));
    for (var size = 0; size < packed.length; size++) {
      expect(
        () => decodeArchiveLz4(Uint8List.sublistView(packed, 0, size)),
        rejects,
        reason: 'accepted truncated length $size/${packed.length}',
      );
    }
  });

  test('rejects versions, reserved bits, dictionary IDs and legacy frames', () {
    final packed = encodeArchiveLz4(_bytes('payload'));
    for (final flags in [0x3c, 0xbc, 0x7e, 0x7d]) {
      final bytes = Uint8List.fromList(packed)..[4] = flags;
      expect(() => decodeArchiveLz4(bytes), rejects);
    }
    for (final descriptor in [0x30, 0x51, 0xd0, 0]) {
      final bytes = Uint8List.fromList(packed)..[5] = descriptor;
      expect(() => decodeArchiveLz4(bytes), rejects);
    }
    expect(
      () => decodeArchiveLz4(Uint8List.fromList(_word(0x184c2102))),
      rejects,
    );
  });

  test('concatenates complete frames and reports skippable metadata', () {
    final first = encodeArchiveLz4(_bytes('first'));
    final second = encodeArchiveLz4(_bytes('second'));
    final skipped = [..._word(0x184d2a5f), ..._word(4), 1, 2, 3, 4];
    final collection = Uint8List.fromList([
      ...skipped,
      ...first,
      ...skipped,
      ...second,
    ]);
    final decoded = decodeArchiveLz4(collection);
    expect(decoded.bytes, _bytes('firstsecond'));
    expect(decoded.frameCount, 2);
    expect(decoded.skippableFrameCount, 2);
    expect(decoded.canRewrite, isFalse);
    expect(() => decodeArchiveLz4(collection, maxOutputBytes: 10), rejects);
    expect(() => decodeArchiveLz4(Uint8List.fromList(skipped)), rejects);
    expect(
      () =>
          decodeArchiveLz4(Uint8List.fromList([...first, ...skipped.take(10)])),
      rejects,
    );
    for (final tail in [
      [0],
      [1, 2, 3, 4],
    ]) {
      expect(
        () => decodeArchiveLz4(Uint8List.fromList([...first, ...tail])),
        rejects,
      );
    }
  });

  test('does not share dictionaries across independent blocks or frames', () {
    final literal = [0x80, ...utf8.encode('abcdefgh')];
    final borrowed = [0, 8, 0, 0x80, ...utf8.encode('ijklmnop')];
    final linked = _frame([literal, borrowed], independent: false);
    expect(decodeArchiveLz4(linked).bytes, _bytes('abcdefghabcdijklmnop'));
    expect(() => decodeArchiveLz4(_frame([literal, borrowed])), rejects);
    expect(
      () => decodeArchiveLz4(
        Uint8List.fromList([
          ..._frame([literal], independent: false),
          ..._frame([borrowed], independent: false),
        ]),
      ),
      rejects,
    );
  });

  test('rejects malformed block literals, offsets and ending conditions', () {
    for (final block in <List<int>>[
      [0xf0], // Missing literal length extension.
      [0x20, 1], // Truncated literals.
      [0, 1], // Truncated match offset.
      [0, 0, 0, 0x50, 1, 2, 3, 4, 5], // Zero offset.
      [0, 1, 0, 0x50, 1, 2, 3, 4, 5], // Missing dictionary.
      [0x10, 65, 1, 0], // No final literal sequence.
      [0x10, 65, 1, 0, 0x10, 65], // Too few final literals.
      [0x10, 65, 1, 0, 0x50, 65, 65, 65, 65, 65], // Last match too near end.
      [0x1f, 65, 1, 0], // Missing match length extension.
    ]) {
      expect(
        () => decodeArchiveLz4(_frame([block])),
        rejects,
        reason: '$block',
      );
    }
  });

  test('bounds block expansion independently of total output allowance', () {
    final hugeLiterals = [0xf0, ...List.filled(258, 255), 0];
    expect(() => decodeArchiveLz4(_frame([hugeLiterals])), rejects);
    final oversizedStored = _frame([List.filled(65537, 0)], stored: true);
    expect(() => decodeArchiveLz4(oversizedStored), rejects);
  });

  test('bounds empty frame collections and validates zero output limit', () {
    final empty = encodeArchiveLz4(Uint8List(0));
    expect(decodeArchiveLz4(empty, maxOutputBytes: 0).bytes, isEmpty);
    final excessive = Uint8List.fromList([
      for (var i = 0; i < 4097; i++) ...empty,
    ]);
    expect(() => decodeArchiveLz4(excessive), rejects);
  });
}

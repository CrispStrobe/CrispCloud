import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    File('test/fixtures/archives/lzma-reference-$name.lzma').readAsBytesSync();

Uint8List _knownSize(Uint8List input, int size) {
  final result = Uint8List.fromList(input);
  final header = ByteData.sublistView(result);
  header
    ..setUint32(5, size, Endian.little)
    ..setUint32(9, 0, Endian.little);
  return result;
}

void main() {
  final rejects = throwsA(isA<ArchiveViewException>());
  final payloads = {
    'default': _bytes('Independent LZMA-alone fixture\n' * 10000),
    'properties': Uint8List.fromList([
      for (var i = 0; i < 500; i++) ...[
        ...ascii.encode('Non-default literal positions'),
        0,
        255,
      ],
    ]),
    'distance': Uint8List.fromList([
      for (var i = 0; i < 4; i++) ..._randomData(8192),
    ]),
    'empty': Uint8List(0),
  };

  for (final entry in payloads.entries) {
    test('reads liblzma ${entry.key} fixture with unknown size', () {
      expect(decodeArchiveLzma(_reference(entry.key)), entry.value);
    });
    test('reads liblzma ${entry.key} fixture with known size and marker', () {
      expect(
        decodeArchiveLzma(
          _knownSize(_reference(entry.key), entry.value.length),
        ),
        entry.value,
      );
    });
  }

  test('writes known-size streams without markers and real compression', () {
    final source = _bytes('CrispCloud LZMA compression\n' * 10000);
    final packed = encodeArchiveLzma(source);
    expect(packed.length, lessThan(source.length ~/ 100));
    expect(
      ByteData.sublistView(packed).getUint32(5, Endian.little),
      source.length,
    );
    expect(decodeArchiveLzma(packed), source);
    final falselyUnknown = Uint8List.fromList(packed)..fillRange(5, 13, 255);
    expect(() => decodeArchiveLzma(falselyUnknown), rejects);
  });

  test(
    'round-trips all writer dictionaries and short/incompressible inputs',
    () {
      for (var level = 0; level <= 9; level++) {
        for (final source in [
          Uint8List(0),
          _bytes('tiny'),
          _randomData(2049),
        ]) {
          expect(
            decodeArchiveLzma(encodeArchiveLzma(source, level: level)),
            source,
          );
        }
      }
    },
  );

  test('liblzma independently decodes fresh writer output', () async {
    final directory = await Directory.systemTemp.createTemp('crisp-lzma-');
    addTearDown(() => directory.delete(recursive: true));
    for (final entry in {
      'empty': Uint8List(0),
      'short': _bytes('short'),
      'repeated': payloads['default']!,
      'random': _randomData(50003),
    }.entries) {
      final source = File('${directory.path}/${entry.key}.bin');
      final packed = File('${directory.path}/${entry.key}.lzma');
      await source.writeAsBytes(entry.value);
      await packed.writeAsBytes(encodeArchiveLzma(entry.value));
      final result = await Process.run('python3', [
        'test/support/check_archive_lzma.py',
        'verify',
        packed.path,
        source.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }
  });

  test('rejects every truncated prefix with and without a marker', () {
    for (final packed in [
      _reference('empty'),
      _reference('properties'),
      encodeArchiveLzma(_bytes('short data that repeats ' * 20)),
    ]) {
      for (var size = 0; size < packed.length; size++) {
        expect(
          () => decodeArchiveLzma(Uint8List.sublistView(packed, 0, size)),
          rejects,
          reason: 'accepted truncated length $size/${packed.length}',
        );
      }
    }
  });

  test(
    'rejects trailing bytes and concatenated streams for all size modes',
    () {
      for (final packed in [
        _reference('empty'),
        _reference('properties'),
        _knownSize(_reference('properties'), payloads['properties']!.length),
        encodeArchiveLzma(Uint8List(0)),
        encodeArchiveLzma(_bytes('sample' * 100)),
      ]) {
        for (final tail in [
          <int>[0],
          <int>[1, 2, 3],
          List.filled(8, 0),
          packed,
        ]) {
          expect(
            () => decodeArchiveLzma(Uint8List.fromList([...packed, ...tail])),
            rejects,
          );
        }
      }
    },
  );

  test(
    'enforces both declared output size and unknown-size expansion limit',
    () {
      final source = payloads['properties']!;
      final unknown = _reference('properties');
      expect(decodeArchiveLzma(unknown, maxOutputBytes: source.length), source);
      expect(
        () => decodeArchiveLzma(unknown, maxOutputBytes: source.length - 1),
        rejects,
      );
      for (final size in [
        0,
        source.length - 1,
        source.length + 1,
        kArchiveReadLimit + 1,
      ]) {
        expect(() => decodeArchiveLzma(_knownSize(unknown, size)), rejects);
      }
      final large64 = _knownSize(unknown, source.length)..[9] = 1;
      expect(() => decodeArchiveLzma(large64), rejects);
      final noMarker = encodeArchiveLzma(source);
      for (final size in [source.length - 1, source.length + 1]) {
        expect(() => decodeArchiveLzma(_knownSize(noMarker, size)), rejects);
      }
    },
  );

  test(
    'enforces dictionary distance even when the entire output is retained',
    () {
      final packed = _reference('distance');
      ByteData.sublistView(packed).setUint32(1, 4096, Endian.little);
      expect(() => decodeArchiveLzma(packed), rejects);
    },
  );

  test(
    'normalizes tiny declared dictionaries to the specified 4 KiB minimum',
    () {
      final source = _bytes('Small dictionary content ' * 100);
      final packed = encodeArchiveLzma(source, level: 0);
      for (final dictionary in [0, 1, 4095, 4096]) {
        ByteData.sublistView(packed).setUint32(1, dictionary, Endian.little);
        expect(decodeArchiveLzma(packed), source);
      }
    },
  );

  test(
    'rejects invalid properties, oversized dictionaries and initial state',
    () {
      final packed = encodeArchiveLzma(_bytes('payload'));
      for (final properties in [225, 255, 8, 44]) {
        final bad = Uint8List.fromList(packed)..[0] = properties;
        expect(() => decodeArchiveLzma(bad), rejects);
      }
      for (final dictionary in [kArchiveReadLimit + 1, 0xffffffff]) {
        final bad = Uint8List.fromList(packed);
        ByteData.sublistView(bad).setUint32(1, dictionary, Endian.little);
        expect(() => decodeArchiveLzma(bad), rejects);
      }
      expect(
        () => decodeArchiveLzma(Uint8List.fromList(packed)..[13] = 1),
        rejects,
      );
      final invalidCode = Uint8List.fromList(packed)..fillRange(14, 18, 255);
      expect(() => decodeArchiveLzma(invalidCode), rejects);
    },
  );

  test('rejects final range corruption with known and unknown sizes', () {
    for (final packed in [
      _reference('empty'),
      _reference('properties'),
      encodeArchiveLzma(Uint8List(0)),
      encodeArchiveLzma(_bytes('Final range state ' * 100)),
    ]) {
      final bad = Uint8List.fromList(packed)..[packed.length - 1] ^= 1;
      expect(() => decodeArchiveLzma(bad), rejects);
    }
  });

  test('bounds writer output and validates caller options', () {
    final source = _randomData(4096);
    expect(() => encodeArchiveLzma(source, maxOutputBytes: 30), rejects);
    expect(() => encodeArchiveLzma(Uint8List(0), maxOutputBytes: 17), rejects);
    expect(
      decodeArchiveLzma(encodeArchiveLzma(Uint8List(0), maxOutputBytes: 18)),
      isEmpty,
    );
    expect(() => encodeArchiveLzma(source, level: -1), throwsArgumentError);
    expect(() => encodeArchiveLzma(source, level: 10), throwsArgumentError);
    expect(
      () => decodeArchiveLzma(_reference('empty'), maxOutputBytes: -1),
      throwsArgumentError,
    );
    expect(
      () => encodeArchiveLzma(source, maxOutputBytes: kArchiveReadLimit + 1),
      throwsArgumentError,
    );
  });
}

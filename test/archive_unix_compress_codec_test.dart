import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_unix_compress_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'test/fixtures/archives';

/// A test-only wire builder: starts a fresh byte group for each width and
/// pads exactly eight code slots on a reset or width change.
class _CodeWriter {
  _CodeWriter({int maxBits = 16, bool block = true})
    : bytes = [0x1f, 0x9d, maxBits | (block ? 0x80 : 0)];
  final List<int> bytes;
  int _value = 0, _bits = 0, _codes = 0;
  void write(int value, int width) {
    _value |= value << _bits;
    _bits += width;
    while (_bits >= 8) {
      bytes.add(_value & 255);
      _value >>= 8;
      _bits -= 8;
    }
    _codes = (_codes + 1) % 8;
  }

  void finishGroup(int width) {
    while (_codes != 0) {
      write(0, width);
    }
    expect(_bits, 0);
  }

  Uint8List finish() {
    if (_bits != 0) bytes.add(_value & 255);
    return Uint8List.fromList(bytes);
  }
}

Uint8List _literals(List<int> data, {int maxBits = 16, bool block = true}) {
  final writer = _CodeWriter(maxBits: maxBits, block: block);
  var width = 9, remaining = block ? 256 : 257;
  for (final value in data) {
    writer.write(value, width);
    if (width < maxBits && --remaining == 0) {
      writer.finishGroup(width);
      width++;
      remaining = 1 << (width - 1);
    }
  }
  return writer.finish();
}

Uint8List _codes(List<int> values, {bool block = true}) {
  final writer = _CodeWriter(block: block);
  for (final value in values) {
    writer.write(value, 9);
    if (block && value == 256) writer.finishGroup(9);
  }
  return writer.finish();
}

void main() {
  final manifest = jsonDecode(
    File('$_fixtures/compress-reference-manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final item in manifest['files'] as List<dynamic>) {
    final entry = item as Map<String, dynamic>;
    test(
      'independent ${entry['name']} decodes to the exact reference hash',
      () {
        final packed = File('$_fixtures/${entry['name']}').readAsBytesSync();
        expect(packed.length, entry['packed_bytes']);
        expect(sha256.convert(packed).toString(), entry['packed_sha256']);
        final result = decodeArchiveUnixCompress(packed);
        expect(result.length, entry['decoded_bytes']);
        expect(sha256.convert(result).toString(), entry['decoded_sha256']);
      },
    );
  }

  for (var width = 9; width <= 16; width++) {
    for (final block in [false, true]) {
      test(
        '${block ? 'block' : 'nonblock'} width $width grows and saturates its dictionary',
        () {
          final data = List.generate((1 << width) + 19, (index) => index & 255);
          final packed = _literals(data, maxBits: width, block: block);
          expect(decodeArchiveUnixCompress(packed), data);
        },
      );
    }
  }

  test('the one permitted forward reference expands the preceding string', () {
    expect(
      decodeArchiveUnixCompress(_codes([65, 257, 258, 259])),
      List.filled(10, 65),
    );
    expect(
      decodeArchiveUnixCompress(_codes([65, 256, 257], block: false)),
      List.filled(6, 65),
    );
  });

  test('clear resets previous code and skips its unused nine-bit group', () {
    expect(decodeArchiveUnixCompress(_codes([65, 257, 256, 66, 257])), [
      65,
      65,
      65,
      66,
      66,
      66,
    ]);
    expect(decodeArchiveUnixCompress(_codes([256, 256, 65])), [65]);
  });

  test('terminal unused bits are padding, not a checksum', () {
    final data = _codes([65]);
    data[data.length - 1] |= 0xfe;
    expect(decodeArchiveUnixCompress(data), [65]);
  });

  test('valid-prefix truncation is inherently undetectable without an expected length', () {
    final data = _codes([65, 66, 67, 68]);
    expect(
      decodeArchiveUnixCompress(
        Uint8List.sublistView(data, 0, data.length - 1),
      ),
      [65, 66, 67],
    );
  });

  test(
    'rejects truncated headers, wrong magic, reserved flags and illegal widths',
    () {
      for (final value in <List<int>>[
        [],
        [0x1f],
        [0x1f, 0x9d],
        [0, 0x9d, 0x90],
        [0x1f, 0, 0x90],
        for (final flags in [0, 8, 17, 31, 0x88, 0x91, 0xb0, 0xd0])
          [0x1f, 0x9d, flags],
      ]) {
        expect(
          () => decodeArchiveUnixCompress(Uint8List.fromList(value)),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    },
  );

  test('rejects impossible first and forward dictionary codes', () {
    for (final values in [
      [257],
      [511],
      [65, 300],
      [65, 257, 400],
      [65, 256, 257],
    ]) {
      expect(
        () => decodeArchiveUnixCompress(_codes(values)),
        throwsA(isA<ArchiveViewException>()),
      );
    }
  });

  test(
    'rejects a whole trailing byte that cannot complete a nine-bit code',
    () {
      expect(
        () => decodeArchiveUnixCompress(
          Uint8List.fromList([0x1f, 0x9d, 0x90, 0x41]),
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      final complete = _literals(List.filled(8, 65));
      expect(
        () => decodeArchiveUnixCompress(Uint8List.fromList([...complete, 0])),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test('rejects truncated reset and nonblock width-alignment bytes', () {
    final reset = _codes([65, 256]);
    expect(
      () => decodeArchiveUnixCompress(
        Uint8List.sublistView(reset, 0, reset.length - 1),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    final growth = _literals(List.filled(257, 65), block: false);
    expect(
      () => decodeArchiveUnixCompress(
        Uint8List.sublistView(growth, 0, growth.length - 1),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('output limit is checked before expanding a dictionary string', () {
    final packed = _codes([65, for (var code = 257; code < 400; code++) code]);
    expect(
      () => decodeArchiveUnixCompress(packed, maxOutputBytes: 1024),
      throwsA(
        isA<ArchiveViewException>().having(
          (error) => error.message,
          'message',
          contains('output limit'),
        ),
      ),
    );
    expect(decodeArchiveUnixCompress(_codes([65]), maxOutputBytes: 1), [65]);
    expect(
      () => decodeArchiveUnixCompress(_codes([65, 257]), maxOutputBytes: 2),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('rejects invalid caller limits and oversized compressed input', () {
    final empty = Uint8List.fromList([0x1f, 0x9d, 0x90]);
    for (final limit in [0, -1, kArchiveReadLimit + 1]) {
      expect(
        () => decodeArchiveUnixCompress(empty, maxOutputBytes: limit),
        throwsArgumentError,
      );
    }
    expect(
      () => decodeArchiveUnixCompress(Uint8List(kArchiveReadLimit + 1)),
      throwsA(isA<ArchiveViewException>()),
    );
  });
}

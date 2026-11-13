// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/byte_source.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

void main() {
  for (final (value, bytes) in [
    (0, [0, 0, 0, 0, 0, 0, 0, 0]),
    (1, [1, 0, 0, 0, 0, 0, 0, 0]),
    (4294967295, [255, 255, 255, 255, 0, 0, 0, 0]),
    (4294967296, [0, 0, 0, 0, 1, 0, 0, 0]),
    (4294967297, [1, 0, 0, 0, 1, 0, 0, 0]),
    (9007199254740991, [255, 255, 255, 255, 255, 255, 31, 0]),
  ]) {
    test('unsigned 64-bit helper preserves exact portable integer $value', () {
      final source = Uint8List.fromList(bytes);
      final before = Uint8List.fromList(source);
      final cursor = ByteCursor(source);
      expect(cursor.u64le(), value);
      expect(cursor.offset, 8);
      expect(source, before);
      final sink = ByteSink()..u64le(value);
      expect(sink.takeBytes(), bytes);
    });
  }

  for (final value in [-1, 9007199254740992]) {
    test('unsigned 64-bit writer rejects unsupported integer $value', () {
      final sink = ByteSink()..u8(42);
      expect(() => sink.u64le(value), throwsRangeError);
      expect(sink.toBytes(), [42]);
      expect(sink.length, 1);
    });
  }

  for (final high in [0x200000, 0x80000000, 0xffffffff]) {
    test('unsigned 64-bit reader rejects nonportable high DWORD $high', () {
      final source = Uint8List(8);
      ByteData.sublistView(source).setUint32(4, high, Endian.little);
      final before = Uint8List.fromList(source);
      expect(() => ByteCursor(source).u64le(), throwsRangeError);
      expect(source, before);
    });
  }

  test('FILETIME metadata retains all 64 raw bits outside integer helpers', () {
    final time = Uint8List.fromList(List.filled(8, 255));
    final bytes = (CfbfWriter(
      modifiedFiletime: time,
    )..addStream('Small', [3])).build();
    final raw = CfbfFile.fromBytes(bytes);
    expect(raw.root.modifiedFiletime, time);
    expect(raw.readPath('Small'), [3]);
  });
}

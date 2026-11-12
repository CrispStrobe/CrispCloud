// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'media_word_fixture.dart';
import 'structured_word_fixture.dart';

Uint8List emfRecord(int type, List<int> payload) {
  assert(payload.length % 4 == 0);
  return Uint8List.fromList([
    ...wordU32(type),
    ...wordU32(payload.length + 8),
    ...payload,
  ]);
}

Uint8List emfFixture({List<Uint8List> records = const []}) {
  final eof = emfRecord(14, [...wordU32(0), ...wordU32(16), ...wordU32(20)]);
  final header = Uint8List(88);
  final fields = ByteData.sublistView(header);
  void put(int offset, int value) =>
      fields.setUint32(offset, value, Endian.little);
  put(0, 1);
  put(4, 88);
  put(16, 200);
  put(20, 100);
  put(32, 2000);
  put(36, 1000);
  put(40, 0x464d4520);
  put(44, 0x10000);
  put(
    48,
    88 + records.fold<int>(0, (n, record) => n + record.length) + eof.length,
  );
  put(52, records.length + 2);
  fields.setUint16(56, 16, Endian.little);
  put(72, 1000);
  put(76, 1000);
  put(80, 100);
  put(84, 100);
  return Uint8List.fromList([
    ...header,
    for (final record in records) ...record,
    ...eof,
  ]);
}

Uint8List wmfRecord(int type, List<int> payload) {
  assert(payload.length % 2 == 0);
  return Uint8List.fromList([
    ...wordU32(3 + payload.length ~/ 2),
    ...wordU16(type),
    ...payload,
  ]);
}

Uint8List wmfFixture({
  List<Uint8List> records = const [],
  bool placeable = false,
}) {
  final all = [...records, wmfRecord(0, [])];
  final size = 18 + all.fold<int>(0, (n, record) => n + record.length);
  final max = all.fold<int>(
    0,
    (n, record) => n > record.length ? n : record.length,
  );
  final header = [
    ...wordU16(1),
    ...wordU16(9),
    ...wordU16(0x300),
    ...wordU32(size ~/ 2),
    ...wordU16(16),
    ...wordU32(max ~/ 2),
    ...wordU16(0),
  ];
  final prefix = Uint8List(22);
  final data = ByteData.sublistView(prefix);
  data.setUint32(0, 0x9ac6cdd7, Endian.little);
  data.setInt16(10, 200, Endian.little);
  data.setInt16(12, 100, Endian.little);
  data.setUint16(14, 1440, Endian.little);
  var checksum = 0;
  for (var i = 0; i < 20; i += 2) {
    checksum ^= data.getUint16(i, Endian.little);
  }
  data.setUint16(20, checksum, Endian.little);
  return Uint8List.fromList([
    if (placeable) ...prefix,
    ...header,
    for (final r in all) ...r,
  ]);
}

Uint8List metafileBlip(
  Uint8List payload, {
  bool emf = true,
  bool compressed = true,
  bool twoUids = false,
  void Function(ByteData header)? mutateHeader,
  Uint8List Function(Uint8List)? mutateCompressed,
}) {
  var encoded = compressed ? ZLibEncoder().encodeBytes(payload) : payload;
  if (mutateCompressed != null) encoded = mutateCompressed(encoded);
  final header = Uint8List(34);
  final fields = ByteData.sublistView(header);
  fields.setUint32(0, payload.length, Endian.little);
  fields.setInt32(12, 200, Endian.little);
  fields.setInt32(16, 100, Endian.little);
  fields.setInt32(20, 914400, Endian.little);
  fields.setInt32(24, 457200, Endian.little);
  fields.setUint32(28, encoded.length, Endian.little);
  header[32] = compressed ? 0 : 0xfe;
  header[33] = 0xfe;
  mutateHeader?.call(fields);
  return officeArtRecord(emf ? 0xf01a : 0xf01b, [
    ...List.filled(twoUids ? 32 : 16, 0),
    ...header,
    ...encoded,
  ], instance: (emf ? 0x3d4 : 0x216) + (twoUids ? 1 : 0));
}

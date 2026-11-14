// Original ZIP test data, MIT licensed with archive_zip_recovery_service.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:koni_codecs/koni_codecs.dart' as koni_codecs;

/// Assemble local records without generating a central directory. This unit
/// fixture intentionally exposes malformed declarations independently.
Uint8List zipRecoveryLocalRecord(
  String name,
  List<int> content, {
  int method = 0,
  int flags = 0x800,
  int version = 20,
  bool signedDescriptor = true,
  List<int>? encodedName,
  List<int> extra = const [],
  List<int>? encodedPayload,
  int? declaredCrc,
  int? declaredPacked,
  int? declaredSize,
}) {
  final nameBytes = encodedName ?? utf8.encode(name);
  final raw = Uint8List.fromList(content);
  final packed =
      encodedPayload ??
      (method == 8 ? const koni_codecs.DeflateEncoder().convert(raw) : raw);
  final descriptor = flags & 8 != 0;
  final crc = codecs.getCrc32(raw);
  final bytes = Uint8List(
    30 +
        nameBytes.length +
        extra.length +
        packed.length +
        (descriptor ? (signedDescriptor ? 16 : 12) : 0),
  );
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x04034b50, Endian.little);
  data.setUint16(4, version, Endian.little);
  data.setUint16(6, flags, Endian.little);
  data.setUint16(8, method, Endian.little);
  data.setUint16(10, (12 << 11) | (34 << 5) | 28, Endian.little);
  data.setUint16(12, (46 << 9) | (11 << 5) | 14, Endian.little);
  data.setUint32(14, declaredCrc ?? (descriptor ? 0 : crc), Endian.little);
  data.setUint32(
    18,
    declaredPacked ?? (descriptor ? 0 : packed.length),
    Endian.little,
  );
  data.setUint32(
    22,
    declaredSize ?? (descriptor ? 0 : raw.length),
    Endian.little,
  );
  data.setUint16(26, nameBytes.length, Endian.little);
  data.setUint16(28, extra.length, Endian.little);
  bytes.setRange(30, 30 + nameBytes.length, nameBytes);
  bytes.setRange(
    30 + nameBytes.length,
    30 + nameBytes.length + extra.length,
    extra,
  );
  final payload = 30 + nameBytes.length + extra.length;
  bytes.setRange(payload, payload + packed.length, packed);
  if (descriptor) {
    var at = payload + packed.length;
    if (signedDescriptor) {
      data.setUint32(at, 0x08074b50, Endian.little);
      at += 4;
    }
    data.setUint32(at, crc, Endian.little);
    data.setUint32(at + 4, packed.length, Endian.little);
    data.setUint32(at + 8, raw.length, Endian.little);
  }
  return bytes;
}

Uint8List zipRecoveryRecords(List<List<int>> records) {
  final result = BytesBuilder(copy: false);
  for (final record in records) {
    result.add(record);
  }
  return result.takeBytes();
}

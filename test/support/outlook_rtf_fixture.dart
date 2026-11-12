import 'dart:convert';
import 'dart:typed_data';

// Independent bit-at-a-time CRC, used only to author protocol fixtures. The
// production reader uses a table; official golden vectors below test both.
Uint8List outlookRtfPacket(
  List<int> contents,
  int rawSize, {
  bool uncompressed = false,
}) {
  var crc = 0;
  for (final byte in contents) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  final bytes = Uint8List(16 + contents.length)..setAll(16, contents);
  ByteData.sublistView(bytes)
    ..setUint32(0, contents.length + 12, Endian.little)
    ..setUint32(4, rawSize, Endian.little)
    ..setUint32(8, uncompressed ? 0x414c454d : 0x75465a4c, Endian.little)
    ..setUint32(12, uncompressed ? 0 : crc, Endian.little);
  return bytes;
}

/// Positive integers are literal bytes, negative integers encode references as
/// -(word + 1), so this helper has no dictionary/decompression implementation.
List<int> outlookRtfRuns(List<int> tokens) {
  final output = <int>[];
  for (var start = 0; start < tokens.length; start += 8) {
    var control = 0;
    final run = <int>[];
    for (var i = start; i < tokens.length && i < start + 8; i++) {
      final token = tokens[i];
      if (token >= 0) {
        run.add(token);
      } else {
        control |= 1 << (i - start);
        final word = -token - 1;
        run.addAll([word >> 8, word & 0xff]);
      }
    }
    output.add(control);
    output.addAll(run);
  }
  return output;
}

Uint8List literalOutlookRtf(String rtf, {bool uncompressed = false}) {
  final raw = latin1.encode(rtf);
  if (uncompressed)
    return outlookRtfPacket(raw, raw.length, uncompressed: true);
  final end = ((207 + raw.length) & 0xfff) << 4;
  return outlookRtfPacket(outlookRtfRuns([...raw, -end - 1]), raw.length);
}

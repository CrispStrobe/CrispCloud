import 'dart:typed_data';

import 'archive_types.dart';

const kArchiveAdcChunkLimit = 16 * 1024 * 1024;

/// Decodes one Apple Data Compression run from a UDIF block map.
///
/// ADC has no header, end marker, checksum or embedded output length. Require
/// the exact declared length, validate every token before allocating output,
/// and consume the entire input. UDIF checksums remain the caller's concern.
/// The byte-level format references and independent fixture provenance are in
/// docs/archive-dmg-codecs.md. This implementation uses no native codec.
Uint8List decodeArchiveAdc(
  Uint8List input, {
  required int expectedBytes,
  int maxOutputBytes = kArchiveAdcChunkLimit,
}) {
  if (maxOutputBytes <= 0 || maxOutputBytes > kArchiveAdcChunkLimit) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  if (expectedBytes < 0 || expectedBytes > maxOutputBytes) {
    throw const ArchiveViewException('ADC output exceeds its chunk limit.');
  }
  if (input.length > kArchiveAdcChunkLimit) {
    throw const ArchiveViewException('ADC input exceeds its chunk limit.');
  }

  Never bad(String reason) =>
      throw ArchiveViewException('Invalid ADC chunk: $reason');

  void walk(Uint8List? output) {
    var at = 0;
    var written = 0;
    while (at < input.length) {
      final token = input[at++];
      if (token & 0x80 != 0) {
        final count = (token & 0x7f) + 1;
        if (count > input.length - at) bad('Truncated literal bytes.');
        if (count > expectedBytes - written) {
          bad('Literal bytes exceed the declared output length.');
        }
        output?.setRange(written, written + count, input, at);
        at += count;
        written += count;
      } else {
        final longMatch = token & 0x40 != 0;
        final operands = longMatch ? 2 : 1;
        if (operands > input.length - at) bad('Truncated match offset.');
        final count = longMatch ? (token & 0x3f) + 4 : (token >> 2) + 3;
        final distance = longMatch
            ? (input[at] * 256 + input[at + 1]) + 1
            : ((token & 3) * 256 + input[at]) + 1;
        at += operands;
        if (distance > written) bad('A match precedes the output history.');
        if (count > expectedBytes - written) {
          bad('A match exceeds the declared output length.');
        }
        if (output != null) {
          // Forward byte copying deliberately supports overlapping matches.
          for (var i = 0; i < count; i++) {
            output[written + i] = output[written + i - distance];
          }
        }
        written += count;
      }
    }
    if (written != expectedBytes) {
      bad('Decoded length does not match the block map.');
    }
  }

  walk(null);
  final output = Uint8List(expectedBytes);
  walk(output);
  return output;
}

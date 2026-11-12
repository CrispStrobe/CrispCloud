import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;

import 'archive_lzma_codec.dart';
import 'archive_types.dart';

// Original framing implementation from the published Lzip v1 file format:
// https://www.nongnu.org/lzip/manual/lzip_manual.html#File-format
// Only format documentation and the existing permissive LZMA primitives are
// used. The application has no native lzip/libarchive runtime dependency.

/// Reads complete Lzip v1 members, checking their CRC32, decoded size, member
/// size, required LZMA end marker and exact framing. Consecutive nonempty
/// members concatenate in order. Trailing data and old version-0 framing are
/// refused. The caller receives at most [maxOutputBytes] bytes.
Uint8List decodeArchiveLzip(
  Uint8List input, {
  int maxOutputBytes = kArchiveReadLimit,
}) {
  if (maxOutputBytes < 0 || maxOutputBytes > kArchiveReadLimit) {
    throw ArgumentError.value(
      maxOutputBytes,
      'maxOutputBytes',
      'Expected 0 to 64 MiB.',
    );
  }
  if (input.length > kArchiveReadLimit) {
    _fail('Lzip compressed input exceeds 64 MiB.');
  }
  if (input.length < 36) _fail('Lzip member is truncated.');
  final data = ByteData.sublistView(input);
  final members = <_LzipMember>[];
  var end = input.length;
  var total = 0;

  int size64(int at, int maximum, String field) {
    final low = data.getUint32(at, Endian.little);
    final high = data.getUint32(at + 4, Endian.little);
    // Reject before forming a 64-bit integer, retaining exact behavior on web.
    if (high != 0 || low > maximum) {
      _fail('Lzip $field exceeds its size limit.');
    }
    return low;
  }

  // Lzip's footer is a distributed index: walk it backwards, validate every
  // member boundary and size, and allocate only the bounded declared total.
  while (end > 0) {
    if (members.length >= 4096) _fail('Lzip contains too many members.');
    if (end < 36) _fail('Lzip member is truncated or has trailing data.');
    final memberSize = size64(end - 8, end, 'member size');
    if (memberSize < 36) _fail('Lzip member size is too small.');
    final start = end - memberSize;
    if (input[start] != 0x4c ||
        input[start + 1] != 0x5a ||
        input[start + 2] != 0x49 ||
        input[start + 3] != 0x50) {
      _fail('Lzip has an invalid member signature or trailing data.');
    }
    if (input[start + 4] != 1) _fail('Only Lzip version 1 is supported.');
    final code = input[start + 5];
    final exponent = code & 31;
    if (exponent < 12 || exponent > 29) {
      _fail('Lzip has an invalid dictionary code.');
    }
    final base = 1 << exponent;
    final dictionary = base - (base ~/ 16) * (code >> 5);
    if (dictionary < 4096 || dictionary > kArchiveReadLimit) {
      _fail('Lzip dictionary is outside the supported 4 KiB to 64 MiB range.');
    }
    final decodedSize = size64(
      end - 16,
      maxOutputBytes - total,
      'decoded contents',
    );
    total += decodedSize;
    members.add(
      _LzipMember(
        start: start,
        end: end,
        dictionary: dictionary,
        decodedSize: decodedSize,
        checksum: data.getUint32(end - 20, Endian.little),
      ),
    );
    end = start;
  }
  if (members.length > 1 && members.any((member) => member.decodedSize == 0)) {
    _fail('Lzip empty members are supported only in a single-member file.');
  }
  final output = Uint8List(total);
  var at = 0;
  for (final member in members.reversed) {
    final packedStart = member.start + 6;
    final packedEnd = member.end - 20;
    // Lzip fixes lc=3, lp=0, pb=2 and requires an end marker. Synthesizing an
    // unknown-size LZMA-alone header makes the strict shared decoder enforce
    // that marker, even when the Lzip footer declares the exact decoded size.
    final alone = Uint8List(13 + packedEnd - packedStart)
      ..[0] = 0x5d
      ..fillRange(5, 13, 255)
      ..setRange(13, 13 + packedEnd - packedStart, input, packedStart);
    ByteData.sublistView(alone).setUint32(1, member.dictionary, Endian.little);
    final decoded = decodeArchiveLzma(
      alone,
      maxOutputBytes: member.decodedSize,
    );
    if (decoded.length != member.decodedSize) {
      _fail('Lzip decoded length does not match its trailer.');
    }
    if (codecs.getCrc32(decoded) != member.checksum) {
      _fail('Lzip content checksum does not match.');
    }
    output.setRange(at, at + decoded.length, decoded);
    at += decoded.length;
  }
  return output;
}

Never _fail(String message) => throw ArchiveViewException(message);

class _LzipMember {
  final int start;
  final int end;
  final int dictionary;
  final int decodedSize;
  final int checksum;

  const _LzipMember({
    required this.start,
    required this.end,
    required this.dictionary,
    required this.decodedSize,
    required this.checksum,
  });
}

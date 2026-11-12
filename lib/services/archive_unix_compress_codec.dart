import 'dart:typed_data';

import 'archive_types.dart';

// Original bounded decoder for the UNIX compress (.Z) LZW wire format.
// Format behavior was checked against the OpenBSD compress(1) documentation
// and the BSD-licensed libarchive compress filter. No native runtime is used.
// https://man.openbsd.org/compress.1
// https://github.com/libarchive/libarchive/blob/master/libarchive/archive_read_support_filter_compress.c

/// Decodes one UNIX compress stream, using 9–16 bit block or nonblock codes.
/// The format has neither a stored output length nor a checksum. Invalid codes
/// and incomplete code/alignment bytes are rejected, but truncation at a valid
/// code boundary and corruption that produces other valid codes are inherently
/// undetectable. Callers must not advertise checksum or signature verification.
Uint8List decodeArchiveUnixCompress(
  Uint8List input, {
  int maxOutputBytes = kArchiveReadLimit,
}) {
  if (maxOutputBytes <= 0 || maxOutputBytes > kArchiveReadLimit) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  if (input.length > kArchiveReadLimit) {
    _fail('UNIX compress input exceeds 64 MiB.');
  }
  if (input.length < 3) _fail('UNIX compress header is truncated.');
  if (input[0] != 0x1f || input[1] != 0x9d) {
    _fail('UNIX compress has an invalid signature.');
  }
  final flags = input[2];
  final maxBits = flags & 0x1f;
  if (flags & 0x60 != 0 || maxBits < 9 || maxBits > 16) {
    _fail('UNIX compress uses reserved flags or an unsupported code width.');
  }
  final block = flags & 0x80 != 0;
  final capacity = 1 << maxBits;
  final prefixes = Uint16List(capacity);
  final endings = Uint8List(capacity);
  final reversed = Uint8List(capacity + 1);
  final bits = _CompressBits(input);
  final output = _CompressOutput(maxOutputBytes);
  var width = 9, next = block ? 257 : 256, previous = -1, first = 0;

  while (true) {
    final code = bits.read(width);
    if (code == null) break;
    if (block && code == 256) {
      bits.finishGroup(width);
      width = 9;
      next = 257;
      previous = -1;
      continue;
    }
    if (code > next || (previous < 0 && code >= 256)) {
      _fail('UNIX compress contains an invalid dictionary code.');
    }
    var value = code, count = 0;
    if (code == next) {
      // The only forward reference is the preceding string followed by its
      // own first byte. The new dictionary entry is created below.
      if (previous < 0 || next >= capacity) {
        _fail('UNIX compress contains an invalid forward reference.');
      }
      reversed[count++] = first;
      value = previous;
    }
    while (value >= 256) {
      if (value >= next || (block && value == 256) || count >= capacity) {
        _fail('UNIX compress contains an invalid dictionary chain.');
      }
      reversed[count++] = endings[value];
      final parent = prefixes[value];
      if (parent >= value) {
        _fail('UNIX compress contains a cyclic dictionary chain.');
      }
      value = parent;
    }
    reversed[count++] = value;
    first = value;
    output.appendReversed(reversed, count);
    if (previous >= 0 && next < capacity) {
      prefixes[next] = previous;
      endings[next] = first;
      next++;
    }
    previous = code;
    if (width < maxBits && next == 1 << width) {
      bits.finishGroup(width);
      width++;
    }
  }
  return output.takeBytes();
}

class _CompressBits {
  _CompressBits(this.bytes);
  final Uint8List bytes;
  int _at = 24;
  int _section = 24;

  int? read(int width) {
    final remaining = bytes.length * 8 - _at;
    if (remaining < width) {
      // Padding may occupy the unused high bits of the final byte. A whole
      // unused byte cannot be the end of a correctly emitted code stream.
      if (remaining > 7) _fail('UNIX compress ends with a partial code.');
      return null;
    }
    final offset = _at >> 3, shift = _at & 7;
    var value = bytes[offset] | (bytes[offset + 1] << 8);
    if (width + shift > 16) value |= bytes[offset + 2] << 16;
    _at += width;
    return (value >> shift) & ((1 << width) - 1);
  }

  void finishGroup(int width) {
    // Historical compress writes groups of eight equally wide codes. A width
    // change or dictionary reset discards the rest of that group, even when
    // it contains whole bytes. Group alignment is relative to the latest
    // width/reset boundary, not to the three-byte stream header.
    final group = width * 8;
    final used = _at - _section;
    final next = _section + ((used + group - 1) ~/ group) * group;
    if (next > bytes.length * 8) {
      _fail('UNIX compress dictionary alignment is truncated.');
    }
    _at = next;
    _section = next;
  }
}

class _CompressOutput {
  _CompressOutput(this.limit)
    : _bytes = Uint8List(limit < 65536 ? limit : 65536);
  final int limit;
  Uint8List _bytes;
  int _length = 0;

  void appendReversed(Uint8List bytes, int count) {
    if (count > limit - _length) {
      _fail('UNIX compress contents exceed the output limit.');
    }
    final required = _length + count;
    if (required > _bytes.length) {
      var capacity = _bytes.length * 2;
      if (capacity < required) capacity = required;
      if (capacity > limit) capacity = limit;
      _bytes = Uint8List(capacity)..setRange(0, _length, _bytes);
    }
    for (var index = count - 1; index >= 0; index--) {
      _bytes[_length++] = bytes[index];
    }
  }

  Uint8List takeBytes() => Uint8List.sublistView(_bytes, 0, _length);
}

Never _fail(String message) => throw ArchiveViewException(message);
